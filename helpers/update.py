"""Whether a newer Shale is on GitHub, and what changed: the commits on main after the installed one.

GitHub is asked at most every 12 hours, with one anonymous request, and never for a copy with local changes or
without a recorded commit. After an update, the commits it brought stay listed until the user has seen them."""
import datetime
import json
from pathlib import Path
import re
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, Request, build_opener

REPO = 'TurcanS/shale'
BRANCH = 'main'
_API = f'https://api.github.com/repos/{REPO}/compare/'
WEB = f'https://github.com/{REPO}'
FRESH = 12 * 60 * 60
# A manual check still reuses an answer from the last minute, so repeated clicks stay polite.
POLITE = 60
# The compare answer also carries the changed files; a few MB covers any update of this repository.
_MAX_RESPONSE = 8 * 1024 * 1024
_MAX_COMMITS = 100
_MAX_MESSAGE = 8000
SHA = re.compile(r'[0-9a-f]{7,40}')


def _url(value):
    parsed = urlparse(str(value))
    if parsed.scheme != 'https' or parsed.hostname != 'api.github.com' or parsed.username or parsed.password \
            or parsed.port not in (None, 443):
        raise ValueError('Unexpected update service address.')
    return str(value)


class _RestrictedRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        _url(newurl)
        return super().redirect_request(request, response, code, message, headers, newurl)


def _json(url):
    request = Request(_url(url), headers={'User-Agent': 'ShaleShell/1.0', 'Accept': 'application/vnd.github+json',
                                          'X-GitHub-Api-Version': '2022-11-28', 'Accept-Encoding': 'identity'})
    with build_opener(_RestrictedRedirect()).open(request, timeout=20) as response:
        content = response.read(_MAX_RESPONSE + 1)
    if len(content) > _MAX_RESPONSE:
        raise ValueError('GitHub returned too much data.')
    try:
        value = json.loads(content)
    except (ValueError, UnicodeDecodeError):
        raise ValueError('GitHub returned invalid data.') from None
    if not isinstance(value, dict):
        raise ValueError('GitHub returned invalid data.')
    return value


def message(exc):
    if isinstance(exc, HTTPError):
        return 'GitHub is busy. Try again later.' if exc.code in (403, 429, 502, 503, 504) else f'GitHub refused the request ({exc.code}).'
    if isinstance(exc, (URLError, TimeoutError, OSError)):
        return 'Checking for updates needs a network connection.'
    return str(exc) or 'Could not check for updates.'


def installed(folder):
    """The commit the installer recorded in the shell folder ("-modified" when installed with local changes), or ''."""
    try:
        return (Path(folder) / 'COMMIT').read_text().split()[0][:48]
    except (OSError, IndexError, UnicodeDecodeError):
        return ''


def source(folder):
    """The git checkout this shell was installed from (the installer records it), when it can still update itself."""
    try:
        path = Path((Path(folder) / 'SOURCE').read_text().strip())
    except (OSError, UnicodeDecodeError):
        return ''
    try:
        return str(path) if path.is_absolute() and (path / 'install.sh').is_file() and (path / '.git').exists() else ''
    except OSError:
        return ''


def _time(value):
    """Epoch seconds from GitHub's ISO 8601 time, or 0."""
    try:
        return int(datetime.datetime.fromisoformat(str(value).replace('Z', '+00:00')).timestamp())
    except ValueError:
        return 0


def _commit(item):
    """{sha, message, time} from one commit in a GitHub answer, or None. The message is kept as written."""
    if not isinstance(item, dict) or not isinstance(item.get('sha'), str) or not SHA.fullmatch(item['sha']):
        return None
    commit = item.get('commit') if isinstance(item.get('commit'), dict) else {}
    if not isinstance(commit.get('message'), str):
        return None
    stamp = commit.get('committer') if isinstance(commit.get('committer'), dict) else commit.get('author')
    return {'sha': item['sha'], 'message': commit['message'][:_MAX_MESSAGE].rstrip(),
            'time': _time(stamp.get('date')) if isinstance(stamp, dict) else 0}


def compare(base, fetch=_json):
    """{status, ahead, commits (newest first)} for main against `base`, from GitHub. `status` is GitHub's: "ahead"
    when main has newer commits, "identical", "behind" (base is newer) or "diverged"; "unknown" when GitHub doesn't
    have `base` (a commit that was never pushed)."""
    try:
        data = fetch(_API + f'{base}...{BRANCH}')
    except HTTPError as exc:
        if exc.code in (404, 422):
            return {'status': 'unknown', 'ahead': 0, 'commits': []}
        raise
    status = data.get('status')
    if status not in ('ahead', 'identical', 'behind', 'diverged'):
        raise ValueError('GitHub returned invalid data.')
    ahead = data.get('ahead_by')
    commits = [commit for commit in map(_commit, data.get('commits') or []) if commit]
    return {'status': status, 'ahead': ahead if type(ahead) is int and ahead >= 0 else len(commits),
            'commits': commits[::-1][:_MAX_COMMITS]}


def _read(path):
    try:
        value = json.loads(Path(path).read_text())
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def _write(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value))
    temporary.replace(path)


def _matches(sha, short):
    return bool(short) and sha.startswith(short.split('-')[0])


def status(folder, cache, state, check=True, refresh=False, fetch=_json, now=time.time):
    """What the shell shows about updates:
    {installed, latest, available, skipped, commits, ahead, checked, compare, source, recent, warning}.

    `cache` keeps GitHub's last answer, `state` what the user has seen and skipped. `check` is the updateCheck
    setting: without it GitHub is never asked. `recent` lists what the last update brought ({from, to, commits})
    until `seen` is called."""
    current = installed(folder)
    saved, remembered = _read(cache), _read(state)
    result = {'installed': current, 'latest': '', 'available': False, 'skipped': False, 'commits': [], 'ahead': 0,
              'checked': 0, 'compare': '', 'source': source(folder), 'recent': None, 'warning': ''}
    if not current or current.endswith('-modified') or not SHA.fullmatch(current):
        return result

    # The commits an update brought: the answer GitHub gave for the commit installed before lists them.
    seen = remembered.get('seen')
    if not isinstance(seen, str) or not seen:
        remembered = {**remembered, 'seen': current}
        _write(state, remembered)
    elif seen != current and (remembered.get('recent') or {}).get('to') != current:
        brought = saved.get('commits') if saved.get('installed') == seen and isinstance(saved.get('commits'), list) else []
        index = next((i for i, commit in enumerate(brought) if isinstance(commit, dict) and _matches(commit.get('sha', ''), current)), None)
        remembered = {**remembered, 'recent': {'from': seen, 'to': current, 'commits': brought[index:] if index is not None else []}}
        _write(state, remembered)
    recent = remembered.get('recent')
    if isinstance(recent, dict) and recent.get('to') == current:
        result['recent'] = recent

    if check:
        age = now() - saved['fetched'] if type(saved.get('fetched')) in (int, float) else None
        stale = saved.get('installed') != current or age is None or not 0 <= age < (POLITE if refresh else FRESH)
        if stale:
            try:
                answer = compare(current, fetch)
                saved = {'installed': current, 'fetched': now(), **answer}
                _write(cache, saved)
            except Exception as exc:  # offline or GitHub busy: the last answer, if any, still stands
                result['warning'] = message(exc)
    # With checking off, nothing is offered: not even an update found before it was turned off.
    if check and saved.get('installed') == current and saved.get('status') == 'ahead' and saved.get('commits'):
        commits = saved['commits']
        latest = commits[0]['sha']
        skipped = remembered.get('skip') == latest
        result.update(latest=latest[:7], commits=commits, ahead=saved.get('ahead', len(commits)), skipped=skipped,
                      available=not skipped, compare=f'{WEB}/compare/{current}...{latest[:7]}')
    if saved.get('installed') == current:
        result['checked'] = saved.get('fetched', 0)
    return result


def skip(cache, state):
    """Hide the update GitHub last offered until a newer commit arrives."""
    commits = _read(cache).get('commits')
    latest = commits[0].get('sha') if isinstance(commits, list) and commits and isinstance(commits[0], dict) else None
    if not isinstance(latest, str) or not SHA.fullmatch(latest):
        raise ValueError('There is no update to skip.')
    _write(state, {**_read(state), 'skip': latest})


def seen(folder, state):
    """The user has seen what the installed update brought."""
    current = installed(folder)
    remembered = {key: value for key, value in _read(state).items() if key != 'recent'}
    if current:
        remembered['seen'] = current
    _write(state, remembered)
