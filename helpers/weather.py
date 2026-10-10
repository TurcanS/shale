"""City search and forecasts from Open-Meteo (no API key) using the Python standard library."""
import json
import math
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlparse
from urllib.request import Request, HTTPRedirectHandler, build_opener

_GEOCODING = 'https://geocoding-api.open-meteo.com/v1/search'
_FORECAST = 'https://api.open-meteo.com/v1/forecast'
_HOSTS = {'geocoding-api.open-meteo.com', 'api.open-meteo.com'}
_MAX_RESPONSE = 512 * 1024
FRESH = 30 * 60
UNITS = ('metric', 'imperial')

# WMO weather interpretation codes -> (label, day icon, night icon).
CODES = {
    0: ('Clear', 'sun', 'moon'),
    1: ('Mostly clear', 'cloud-sun', 'cloud-moon'),
    2: ('Partly cloudy', 'cloud-sun', 'cloud-moon'),
    3: ('Overcast', 'cloud', 'cloud'),
    45: ('Fog', 'fog', 'fog'),
    48: ('Freezing fog', 'fog', 'fog'),
    51: ('Light drizzle', 'rain', 'rain'),
    53: ('Drizzle', 'rain', 'rain'),
    55: ('Heavy drizzle', 'rain', 'rain'),
    56: ('Freezing drizzle', 'rain', 'rain'),
    57: ('Freezing drizzle', 'rain', 'rain'),
    61: ('Light rain', 'rain', 'rain'),
    63: ('Rain', 'rain', 'rain'),
    65: ('Heavy rain', 'rain', 'rain'),
    66: ('Freezing rain', 'rain', 'rain'),
    67: ('Freezing rain', 'rain', 'rain'),
    71: ('Light snow', 'snow', 'snow'),
    73: ('Snow', 'snow', 'snow'),
    75: ('Heavy snow', 'snow', 'snow'),
    77: ('Snow grains', 'snow', 'snow'),
    80: ('Light showers', 'rain', 'rain'),
    81: ('Showers', 'rain', 'rain'),
    82: ('Heavy showers', 'rain', 'rain'),
    85: ('Snow showers', 'snow', 'snow'),
    86: ('Heavy snow showers', 'snow', 'snow'),
    95: ('Thunderstorm', 'storm', 'storm'),
    96: ('Thunderstorm with hail', 'storm', 'storm'),
    99: ('Thunderstorm with hail', 'storm', 'storm'),
}

def _url(value):
    parsed = urlparse(str(value))
    if parsed.scheme != 'https' or parsed.hostname not in _HOSTS or parsed.username or parsed.password or parsed.port not in (None, 443):
        raise ValueError('Unexpected weather service address.')
    return str(value)

class _RestrictedRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        _url(newurl)
        return super().redirect_request(request, response, code, message, headers, newurl)

def _json(url):
    request = Request(_url(url), headers={'User-Agent': 'ShaleShell/1.0', 'Accept': 'application/json', 'Accept-Encoding': 'identity'})
    with build_opener(_RestrictedRedirect()).open(request, timeout=15) as response:
        content = response.read(_MAX_RESPONSE + 1)
    if len(content) > _MAX_RESPONSE:
        raise ValueError('The weather service returned too much data.')
    try:
        value = json.loads(content)
    except (ValueError, UnicodeDecodeError):
        raise ValueError('The weather service returned invalid data.') from None
    if not isinstance(value, dict):
        raise ValueError('The weather service returned invalid data.')
    return value

def message(exc):
    if isinstance(exc, HTTPError):
        return 'The weather service is busy. Try again later.' if exc.code in (429, 502, 503, 504) else f'The weather service refused the request ({exc.code}).'
    if isinstance(exc, (URLError, TimeoutError, OSError)):
        return 'Weather is unavailable offline.'
    return str(exc) or 'Weather is unavailable.'

def _number(value, low, high):
    return type(value) in (int, float) and math.isfinite(value) and low <= value <= high

def validate_location(value):
    """A saved location: {} (none) or {name, region, latitude, longitude}."""
    if value == {}:
        return {}
    if not isinstance(value, dict) or set(value) - {'name', 'region', 'latitude', 'longitude'}:
        raise ValueError('Choose a city from the search results.')
    name, region = value.get('name'), value.get('region', '')
    if not isinstance(name, str) or not 0 < len(name) <= 100 or not isinstance(region, str) or len(region) > 200:
        raise ValueError('Choose a city from the search results.')
    if not _number(value.get('latitude'), -90, 90) or not _number(value.get('longitude'), -180, 180):
        raise ValueError('Choose a city from the search results.')
    return value

def search(query, fetch=_json):
    if not isinstance(query, str) or not 2 <= len(query.strip()) <= 100:
        raise ValueError('Type at least two letters of a city name.')
    data = fetch(_GEOCODING + '?' + urlencode({'name': query.strip(), 'count': 6, 'language': 'en', 'format': 'json'}))
    results = []
    for item in data.get('results') or []:
        if not isinstance(item, dict) or not isinstance(item.get('name'), str):
            continue
        latitude, longitude = item.get('latitude'), item.get('longitude')
        if not _number(latitude, -90, 90) or not _number(longitude, -180, 180):
            continue
        region = ', '.join(part for part in (item.get('admin1'), item.get('country')) if isinstance(part, str) and part and part != item['name'])
        results.append({'name': item['name'][:100], 'region': region[:200], 'latitude': round(latitude, 4), 'longitude': round(longitude, 4)})
    return results

def _code(value, day=True):
    label, sun, night = CODES.get(value, ('Unknown', 'cloud', 'cloud'))
    return label, sun if day else night

def _round(value):
    return round(value) if _number(value, -1000, 1000) else None

def parse(data):
    """Reduce an Open-Meteo forecast to what the calendar shows."""
    current, daily = data.get('current'), data.get('daily')
    if not isinstance(current, dict) or not isinstance(daily, dict):
        raise ValueError('The weather service returned an incomplete forecast.')
    label, icon = _code(current.get('weather_code'), current.get('is_day', 1) == 1)
    days = []
    columns = [daily.get(key) or [] for key in ('time', 'weather_code', 'temperature_2m_max', 'temperature_2m_min', 'precipitation_probability_max')]
    # The first daily row is today; the card shows the next three days.
    for date, code, high, low, rain in list(zip(*columns))[1:4]:
        day_label, day_icon = _code(code)
        days.append({'date': str(date), 'label': day_label, 'icon': day_icon, 'high': _round(high), 'low': _round(low), 'rain': _round(rain)})
    today = list(zip(*columns))[:1]
    return {
        'current': {'temperature': _round(current.get('temperature_2m')), 'feelsLike': _round(current.get('apparent_temperature')),
                    'label': label, 'icon': icon,
                    'high': _round(today[0][2]) if today else None, 'low': _round(today[0][3]) if today else None},
        'days': days,
    }

def forecast(location, units, cache, refresh=False, fetch=_json, now=time.time):
    """The forecast for a saved location, cached for 30 minutes. Falls back to an old copy when offline."""
    location = validate_location(location)
    if not location:
        raise ValueError('Choose a city first.')
    if units not in UNITS:
        raise ValueError('Choose metric or imperial units.')
    key = f"{location['latitude']:.4f},{location['longitude']:.4f},{units}"
    try:
        saved = json.loads(Path(cache).read_text())
        if not isinstance(saved, dict) or saved.get('key') != key or not isinstance(saved.get('weather'), dict) or type(saved.get('fetched')) not in (int, float):
            saved = None
    except (OSError, ValueError):
        saved = None
    age = now() - saved['fetched'] if saved else None
    # A manual refresh still reuses a copy from the last minute so repeated clicks stay polite.
    if saved and 0 <= age < (60 if refresh else FRESH):
        return {**saved['weather'], 'location': location, 'units': units, 'fetched': saved['fetched'], 'stale': False}
    params = {'latitude': location['latitude'], 'longitude': location['longitude'], 'timezone': 'auto', 'forecast_days': 4,
              'current': 'temperature_2m,apparent_temperature,weather_code,is_day',
              'daily': 'weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'}
    if units == 'imperial':
        params['temperature_unit'] = 'fahrenheit'
    try:
        weather = parse(fetch(_FORECAST + '?' + urlencode(params)))
    except Exception as exc:
        if saved:
            return {**saved['weather'], 'location': location, 'units': units, 'fetched': saved['fetched'], 'stale': True, 'warning': message(exc)}
        raise
    fetched = now()
    Path(cache).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    temporary = Path(cache).with_suffix('.tmp')
    temporary.write_text(json.dumps({'key': key, 'fetched': fetched, 'weather': weather}))
    temporary.replace(cache)
    return {**weather, 'location': location, 'units': units, 'fetched': fetched, 'stale': False}
