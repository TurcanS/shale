from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
loader = SourceFileLoader("session_action", str(ROOT / "scripts/session-action"))
session = module_from_spec(spec_from_loader("session_action", loader))
loader.exec_module(session)


class Clock:
    def __init__(self):
        self.now = 0.0

    def __call__(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


def reader(states):
    states = list(states)
    return lambda: states.pop(0) if len(states) > 1 else states[0]


def locked(pid="10", secure=True):
    return {"locked": True, "secure": secure, "pid": pid, "owner": "shell"}


class WatchTests(unittest.TestCase):
    def watch(self, states, **options):
        clock = Clock()
        return session.watch("10", read=reader(states), sleep=clock.sleep, clock=clock, **options)

    def test_follows_the_lock_until_the_password_unlocks_it(self):
        states = [locked(secure=False), locked()] + [locked()] * 20 + [{"locked": False, "secure": False, "pid": "10"}]
        self.assertEqual(self.watch(states), "unlocked")

    def test_a_lock_the_compositor_never_confirms_falls_back(self):
        self.assertEqual(self.watch([locked(secure=False)]), "unconfirmed")

    def test_a_confirmed_lock_is_not_abandoned_later(self):
        states = [locked()] + [locked(secure=False)] * 10 + [{"locked": False, "pid": "10"}]
        self.assertEqual(self.watch(states), "unlocked")

    def test_a_restarted_shell_means_the_lock_screen_is_gone(self):
        self.assertEqual(self.watch([locked(), locked(pid="99")]), "lost")

    def test_a_silent_shell_is_given_a_few_tries(self):
        self.assertEqual(self.watch([locked(), None, None, locked(), {"locked": False, "pid": "10"}]), "unlocked")
        self.assertEqual(self.watch([locked(), None, None, None, None]), "lost")


class LockBeforeSuspendTests(unittest.TestCase):
    def wait(self, states, lockers=lambda since: []):
        clock = Clock()
        return session.wait_locked(100.0, read=reader(states), lockers=lockers, sleep=clock.sleep, clock=clock)

    def test_waits_for_the_shell_lock_to_be_confirmed(self):
        self.assertTrue(self.wait([None, locked(secure=False), locked()]))

    def test_a_new_hyprlock_that_stays_up_counts_as_locked(self):
        self.assertTrue(self.wait([None], lockers=lambda since: [42]))

    def test_a_hyprlock_that_exits_immediately_does_not_count(self):
        calls = iter([[42], []])
        self.assertFalse(self.wait([None], lockers=lambda since: next(calls)))

    def test_never_confirmed_means_no_suspend(self):
        self.assertFalse(self.wait([locked(secure=False)]))

    def test_only_this_users_hyprlock_started_after_the_request_is_fresh(self):
        from unittest.mock import patch
        import subprocess
        stats = {"7": "7 (hyprlock) S " + " ".join(["0"] * 18) + " 5000 0", "8": "8 (hyprlock) S " + " ".join(["0"] * 18) + " 20000 0"}
        listing = subprocess.CompletedProcess([], 0, stdout="7\n8\n")
        with patch.object(session.subprocess, "run", return_value=listing) as run, \
                patch.object(session.os, "sysconf", return_value=100), \
                patch.object(session.Path, "read_text", lambda path: stats[path.parent.name]):
            self.assertEqual(session.fresh_hyprlock(150.0), [8])
        self.assertIn("-u", run.call_args.args[0])


class SuspendTests(unittest.TestCase):
    def inhibitors(self, *items, returncode=0):
        import json
        import subprocess
        from unittest.mock import patch
        stdout = json.dumps({"type": "a(ssssuu)", "data": [list(items)]})
        return patch.object(session.subprocess, "run", return_value=subprocess.CompletedProcess([], returncode, stdout=stdout))

    def test_a_hypridle_that_delays_sleep_is_trusted_to_lock(self):
        import os
        uid = os.getuid()
        hypridle = ["sleep", "hypridle", "Hypridle wants to delay sleep", "delay", uid, 812]
        with self.inhibitors(["sleep", "UPower", "Pause polling", "delay", 0, 9], hypridle) as run:
            self.assertTrue(session.hypridle_delays_sleep())
        self.assertIn("ListInhibitors", run.call_args.args[0])
        for others in (["sleep", "UPower", "Pause polling", "delay", 0, 9],      # not hypridle
                       ["idle", "hypridle", "Idle", "block", uid, 812],         # not sleep
                       ["sleep", "hypridle", "Another user", "delay", uid + 1, 812]):
            with self.subTest(others=others), self.inhibitors(others):
                self.assertFalse(session.hypridle_delays_sleep())
        with self.inhibitors(hypridle, returncode=1):
            self.assertFalse(session.hypridle_delays_sleep())
        from unittest.mock import patch
        with patch.object(session.subprocess, "run", side_effect=FileNotFoundError("busctl")):
            self.assertFalse(session.hypridle_delays_sleep())

    def suspend(self, started=0, confirmed=True):
        import subprocess
        from unittest.mock import patch
        with patch.object(session, "hypridle_delays_sleep", return_value=False), patch.object(session, "uptime", return_value=1.0), \
                patch.object(session.subprocess, "run", return_value=subprocess.CompletedProcess([], started)) as run, \
                patch.object(session.subprocess, "Popen") as popen, patch.object(session, "wait_locked", return_value=confirmed) as wait, \
                patch.object(session.subprocess, "call", return_value=0) as call, patch("sys.stderr"):
            result = session.suspend()
        popen.assert_not_called()
        return result, run, wait, call

    def test_another_hypridle_still_locks_first(self):
        result, run, wait, call = self.suspend(confirmed=False)
        self.assertEqual(result, 1)
        run.assert_called_once()
        call.assert_not_called()

    def test_the_lock_runs_as_its_own_unit_so_it_outlives_this_one(self):
        # The shell runs suspend in a transient unit; systemd stops what's left in it once suspend exits,
        # which must not take hyprlock or the lock watcher with it.
        result, run, wait, call = self.suspend()
        self.assertEqual(result, 0)
        self.assertEqual(run.call_args.args[0], ["systemd-run", "--user", "--quiet", "--collect", "--",
                                                 str(ROOT / "scripts/session-action"), "lock"])
        self.assertNotIn("--wait", run.call_args.args[0])
        wait.assert_called_once_with(1.0)
        call.assert_called_once_with(["systemctl", "suspend"])
        # A lock that could not be started means no suspend, without waiting for one.
        result, run, wait, call = self.suspend(started=1)
        self.assertEqual(result, 1)
        wait.assert_not_called()
        call.assert_not_called()


class HyprlockConfigTests(unittest.TestCase):
    def test_the_users_own_config_wins(self):
        import tempfile
        with tempfile.TemporaryDirectory() as temp:
            home = Path(temp)
            hypr = home / ".config/hypr"
            hypr.mkdir(parents=True)
            self.assertEqual(session.hyprlock_config(home), hypr / "shale-hyprlock.conf")
            (hypr / "hyprlock.conf").touch()
            self.assertEqual(session.hyprlock_config(home), hypr / "hyprlock.conf")


if __name__ == "__main__":
    unittest.main()
