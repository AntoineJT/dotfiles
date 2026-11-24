"""Tests for macOS/bin/.local/bin/reboot-snapshot.  Run: python3 -m unittest tests/reboot_snapshot_test.py"""
import importlib.util, io, json, subprocess, sys, tempfile, time, unittest
from contextlib import redirect_stdout
from importlib.machinery import SourceFileLoader
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "macOS/bin/.local/bin/reboot-snapshot"
loader = SourceFileLoader("reboot_snapshot", str(SCRIPT))
spec = importlib.util.spec_from_loader("reboot_snapshot", loader)
rs = importlib.util.module_from_spec(spec)
sys.dont_write_bytecode = True  # no __pycache__ inside the stow package
loader.exec_module(rs)

LSTART = "Wed Oct 28 16:38:55 2026"


class Env(unittest.TestCase):
    """A fake HOME with session files, WezTerm panes and `ps` answers."""

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.sessions_dir = self.tmp / "sessions"; self.sessions_dir.mkdir()
        self.projects = self.tmp / "projects/p"; self.projects.mkdir(parents=True)
        self.state = self.tmp / "state"
        self.cwd = self.tmp / "work"; self.cwd.mkdir()
        self.panes, self.ps = [], {}  # pid -> (tty, args, lstart)
        self.spawned, self.fail_spawn = [], set()
        for name, val in [("CLAUDE_SESSIONS", self.sessions_dir), ("CLAUDE_PROJECTS", self.tmp / "projects"),
                          ("STATE", self.state), ("FF_ROOT", self.tmp / "ff"), ("HOME", self.tmp)]:
            p = mock.patch.object(rs, name, val); p.start(); self.addCleanup(p.stop)
        for name, val in [("run", self.fake_run), ("wezterm", lambda: "wezterm")]:
            p = mock.patch.object(rs, name, val); p.start(); self.addCleanup(p.stop)
        p = mock.patch.object(rs.time, "sleep", lambda s: None); p.start(); self.addCleanup(p.stop)

    def session(self, pid, tty, args, name="s", kind="interactive", sid=None, started_delay=1.6,
                lstart=LSTART, pane=True):
        sid = sid or f"0000000{pid}-aaaa-bbbb-cccc-dddddddddddd"
        started = time.mktime(time.strptime(LSTART, "%a %b %d %H:%M:%S %Y")) + started_delay
        # procStart as claude really writes it: an hour off `ps lstart` after a DST change.
        rec = {"pid": pid, "sessionId": sid, "cwd": str(self.cwd), "kind": kind, "status": "idle",
               "procStart": "Wed Oct 28 15:38:55 2026", "startedAt": int(started * 1000)}
        if name is not None:
            rec["name"] = name
        (self.sessions_dir / f"{pid}.json").write_text(json.dumps(rec))
        (self.projects / f"{sid}.jsonl").write_text("{}")
        self.ps[pid] = (tty, args, lstart)
        if pane and not any(p["tty_name"] == f"/dev/{tty}" for p in self.panes):
            n = len(self.panes)
            self.panes.append({"window_id": 0, "tab_id": n, "pane_id": n, "tty_name": f"/dev/{tty}",
                               "cwd": f"file://{self.cwd}", "title": name or ""})
        return sid

    wezterm_fails = False

    def fake_run(self, cmd, env=None):
        if cmd[:2] == ["ps", "-o"]:
            pid = int(cmd[-1])
            if pid not in self.ps:
                raise subprocess.CalledProcessError(1, cmd)
            tty, args, lstart = self.ps[pid]
            if cmd[2].startswith("lstart"):
                # ps formats lstart in the user's locale, as on a French shell.
                c_locale = env is not None and env.get("LC_ALL") == "C"
                return (lstart if c_locale else "mer. 28 oct. 16:38:55 2026") + "\n"
            return f"{tty} {args}\n"
        if cmd[1:3] == ["cli", "list"]:
            if self.wezterm_fails:
                raise subprocess.CalledProcessError(1, cmd, stderr="no mux")
            return json.dumps(self.panes)
        if cmd[1:3] == ["cli", "spawn"]:
            self.spawned.append(cmd)
            if len(self.spawned) in self.fail_spawn:
                raise subprocess.CalledProcessError(1, cmd, stderr="mux error")
            return f"{100 + len(self.spawned)}\n"
        raise AssertionError(f"unexpected command {cmd}")

    def dump(self):
        out = io.StringIO()
        with redirect_stdout(out):
            try:
                rs.cmd_dump(None)
                code = 0
            except SystemExit as e:
                code = e.code
        return code, out.getvalue(), (self.state / "latest").resolve()


class DumpTest(Env):
    def test_prompt_with_apostrophe_does_not_crash_dump(self):
        self.session(1, "ttys001", "claude regarde l'erreur")
        code, _, snap = self.dump()
        tabs = json.loads((snap / "wezterm.json").read_text())
        self.assertEqual(tabs[0]["flags"], [], "a positional prompt must not be kept as a flag")

    def test_only_replayable_flags_are_kept(self):
        self.session(1, "ttys001", "claude --resume old --chrome fix the bug --model opus --fork-session")
        self.session(2, "ttys002", "node /opt/claude/cli.js --dangerously-skip-permissions")
        _, _, snap = self.dump()
        flags = [t["flags"] for t in json.loads((snap / "wezterm.json").read_text())]
        self.assertEqual(flags, [["--chrome", "--model", "opus"], ["--dangerously-skip-permissions"]])

    def test_unnamed_session_does_not_crash_dump(self):
        self.session(1, "ttys001", "claude", name=None)
        code, _, snap = self.dump()
        self.assertEqual(code, 0)
        self.assertTrue((snap / "RESTORE.md").exists())
        self.assertNotIn("None", (snap / "RESTORE.md").read_text())

    def test_failing_part_still_writes_restore_md_and_moves_latest(self):
        self.session(1, "ttys001", "claude", name="keep-me")
        with mock.patch.object(rs, "dump_firefox", side_effect=OSError("recovery.jsonlz4.tmp vanished")):
            code, out, snap = self.dump()
        self.assertNotEqual(code, 0, "a partial dump must exit non-zero")
        self.assertIn("keep-me", (snap / "RESTORE.md").read_text())
        self.assertIn("recovery.jsonlz4.tmp vanished", out)

    def test_wezterm_failure_still_dumps_firefox(self):
        def boom(snap):
            raise subprocess.CalledProcessError(1, ["wezterm"])
        with mock.patch.object(rs, "dump_wezterm", boom), \
             mock.patch.object(rs, "dump_firefox", return_value=([("prof", 3, 1)], [])) as ff:
            code, _, snap = self.dump()
        ff.assert_called_once()
        self.assertNotEqual(code, 0)
        self.assertIn("prof", (snap / "RESTORE.md").read_text())

    def test_sessions_outside_wezterm_are_reported(self):
        self.session(1, "ttys001", "claude", name="in-tab")
        self.session(2, "ttys009", "claude", name="in-tmux", pane=False)
        self.session(3, "ttys014", "claude bg-spare", name="background", kind="bg", pane=False)
        _, out, snap = self.dump()
        md = (snap / "RESTORE.md").read_text()
        for name in ("in-tmux", "background"):
            self.assertIn(name, md)
            self.assertIn(name, out)

    def test_two_sessions_on_one_tty_are_both_kept(self):
        self.session(1, "ttys001", "claude", name="suspended")
        self.session(2, "ttys001", "claude", name="foreground")
        _, _, snap = self.dump()
        names = {t.get("name") for t in json.loads((snap / "wezterm.json").read_text())}
        self.assertEqual(names, {"suspended", "foreground"})

    def test_reused_pid_is_not_taken_for_the_session(self):
        self.session(1, "ttys001", "claude", name="stale", started_delay=-86400 * 20)
        _, _, snap = self.dump()
        tabs = json.loads((snap / "wezterm.json").read_text())
        self.assertNotIn("session_id", tabs[0])


class RestoreHelpers(Env):
    def snapshot(self, n, missing_cwd=None):
        for i in range(1, n + 1):
            self.session(i, f"ttys00{i}", "claude", name=f"s{i}")
        _, _, snap = self.dump()
        if missing_cwd:
            tabs = json.loads((snap / "wezterm.json").read_text())
            tabs[missing_cwd - 1]["cwd"] = str(self.tmp / "gone")
            (snap / "wezterm.json").write_text(json.dumps(tabs))
        return snap

    def restore(self, snap, dry_run=False):
        out = io.StringIO()
        with redirect_stdout(out):
            try:
                rs.restore_wezterm(snap, dry_run, False)
            except SystemExit:
                pass  # failures exit 1; the tests check the output
        return out.getvalue()


class RestoreWeztermTest(RestoreHelpers):
    def test_failed_spawn_does_not_stop_the_others_and_rerun_skips_restored(self):
        snap = self.snapshot(3)
        self.fail_spawn = {2}
        out = self.restore(snap)
        self.assertEqual(len(self.spawned), 3, "the third session must still be spawned")
        self.assertIn("s2", out.split("chec")[-1], "the failure must be listed at the end")
        self.spawned, self.fail_spawn = [], set()
        self.restore(snap)
        resumed = [c[-1] for c in self.spawned]
        self.assertEqual(len(self.spawned), 1, f"only the failed one must be retried, got {resumed}")
        self.assertIn("00000002", resumed[0])

    def test_dry_run_flags_missing_directory(self):
        snap = self.snapshot(1, missing_cwd=1)
        self.assertIn("dossier absent", self.restore(snap, dry_run=True))

    def test_first_window_skipped_still_opens_second_window_separately(self):
        snap = self.snapshot(2, missing_cwd=1)
        tabs = json.loads((snap / "wezterm.json").read_text())
        tabs[1]["window_id"] = 1
        (snap / "wezterm.json").write_text(json.dumps(tabs))
        self.restore(snap)
        self.assertNotIn("--new-window", self.spawned[0],
                         "the first restored tab goes into the current window")


class Pass2Test(Env):
    def test_wezterm_unreachable_still_records_every_session(self):
        self.session(1, "ttys001", "claude", name="keep-me")
        self.wezterm_fails = True
        code, _, snap = self.dump()
        self.assertNotEqual(code, 0)
        self.assertIn("claude --resume 00000001", (snap / "RESTORE.md").read_text())

    def test_values_with_spaces_are_not_replayed(self):
        self.session(1, "ttys001", "claude --settings {\"model\": \"opus\"} --add-dir /x/My Dir --model opus")
        _, _, snap = self.dump()
        self.assertEqual(json.loads((snap / "wezterm.json").read_text())[0]["flags"], ["--model", "opus"])

    def test_two_dumps_in_the_same_second(self):
        self.session(1, "ttys001", "claude")
        with mock.patch.object(rs.datetime, "datetime") as dt:
            dt.now.return_value.strftime.return_value = "20261124-120000"
            first, second = self.dump(), self.dump()
        self.assertNotEqual(first[2], second[2])
        self.assertEqual(second[0], 0)


class RestorePass2Test(RestoreHelpers):
    def test_missing_directory_counts_as_a_failure(self):
        snap = self.snapshot(2, missing_cwd=1)
        out = io.StringIO()
        with redirect_stdout(out), self.assertRaises(SystemExit) as e:
            rs.restore_wezterm(snap, False, False)
        self.assertEqual(e.exception.code, 1)
        self.assertIn("s1", out.getvalue().split("chec")[-1])

    def test_shell_tabs_are_not_reopened_on_a_rerun(self):
        self.session(1, "ttys001", "claude", name="s1")
        self.panes.append({"window_id": 0, "tab_id": 9, "pane_id": 9, "tty_name": "/dev/ttys009",
                           "cwd": f"file://{self.cwd}", "title": "zsh"})
        _, _, snap = self.dump()
        with redirect_stdout(io.StringIO()):
            rs.restore_wezterm(snap, False, True)
            self.spawned = []
            rs.restore_wezterm(snap, False, True)
        self.assertEqual(self.spawned, [])


def mozlz4(obj):
    """Encode as mozLz4 with a single literals-only LZ4 sequence."""
    raw = json.dumps(obj).encode()
    n, ext = len(raw), b""
    if n >= 15:
        rest = n - 15
        ext = b"\xff" * (rest // 255) + bytes([rest % 255])
    return b"mozLz40\0" + n.to_bytes(4, "little") + bytes([min(n, 15) << 4]) + ext + raw


def ff_session(*urls):
    return {"windows": [{"tabs": [{"entries": [{"url": u, "title": u}], "index": 1} for u in urls]}]}


class Pass3Test(RestoreHelpers):
    def test_restore_without_wezterm_json_reopens_the_recorded_sessions(self):
        self.session(1, "ttys001", "claude", name="keep-me")
        self.wezterm_fails = True
        _, _, snap = self.dump()
        self.wezterm_fails = False
        self.restore(snap)
        self.assertEqual(len(self.spawned), 1)
        self.assertIn("00000001", self.spawned[0][-1])

    def test_malformed_session_file_does_not_lose_the_others(self):
        self.session(1, "ttys001", "claude", name="good")
        (self.sessions_dir / "2.json").write_text(json.dumps({"pid": 2, "kind": "interactive"}))
        (self.sessions_dir / "3.json").write_text("[1, 2]")
        self.ps[2] = ("ttys002", "claude", LSTART)
        _, _, snap = self.dump()
        self.assertIn("good", (snap / "RESTORE.md").read_text())

    def test_tabs_keep_wezterm_order(self):
        self.session(1, "ttys001", "claude", name="right")
        self.session(2, "ttys002", "claude", name="left")
        self.panes[0]["tab_id"], self.panes[1]["tab_id"] = 50, 7  # tab 50 was moved first
        _, _, snap = self.dump()
        names = [t["name"] for t in json.loads((snap / "wezterm.json").read_text())]
        self.assertEqual(names, ["right", "left"])

    def test_snapshot_by_name_resolves_under_state(self):
        self.session(1, "ttys001", "claude")
        _, _, snap = self.dump()
        self.assertEqual(rs.snapshot_dir(snap.name), snap)


class FirefoxDumpTest(Env):
    def profile(self, name, files):
        d = self.tmp / "ff/Profiles" / name
        (d / "sessionstore-backups").mkdir(parents=True)
        for rel, data in files.items():
            (d / rel).write_bytes(data)

    def test_recovery_rotated_mid_copy_falls_back_and_other_profiles_survive(self):
        self.profile("a.rotating", {"sessionstore-backups/recovery.jsonlz4": b"",
                                    "sessionstore-backups/recovery.baklz4": mozlz4(ff_session("https://bak"))})
        self.profile("b.fine", {"sessionstore.jsonlz4": mozlz4(ff_session("https://b"))})
        real_copy = rs.shutil.copy2

        def copy2(src, dst, **kw):
            if str(src).endswith("recovery.jsonlz4"):  # Firefox renamed it meanwhile
                raise FileNotFoundError(src)
            return real_copy(src, dst, **kw)
        snap = self.tmp / "snap"; snap.mkdir()
        with mock.patch.object(rs.shutil, "copy2", copy2), redirect_stdout(io.StringIO()):
            summary, problems = rs.dump_firefox(snap)
        self.assertEqual(problems, [])
        self.assertEqual(sorted(n for n, _, _ in summary), ["a.rotating", "b.fine"])
        tabs = json.loads((snap / "firefox/a.rotating/tabs.json").read_text())
        self.assertEqual(tabs[0][0]["url"], "https://bak")


class Pass4Test(RestoreHelpers):
    def test_odd_field_types_skip_one_record_not_all(self):
        self.session(1, "ttys001", "claude", name="good")
        self.session(2, "ttys002", "claude", name="odd")
        rec = json.loads((self.sessions_dir / "2.json").read_text())
        rec["startedAt"] = "2026-11-24T10:00:00Z"
        rec["cwd"] = None
        (self.sessions_dir / "2.json").write_text(json.dumps(rec))
        code, _, snap = self.dump()
        self.assertIn("good", (snap / "RESTORE.md").read_text())

    def test_restore_without_any_session_file_explains_instead_of_crashing(self):
        snap = self.state / "empty"; snap.mkdir(parents=True)
        out = io.StringIO()
        with redirect_stdout(out), self.assertRaises(SystemExit) as e:
            rs.restore_wezterm(snap, False, False)
        self.assertIn("RESTORE.md", str(e.exception.code))

    def test_session_launched_through_a_renamed_binary_is_kept(self):
        self.session(1, "ttys001", "cc --chrome", name="via-alias")
        _, _, snap = self.dump()
        tabs = json.loads((snap / "wezterm.json").read_text())
        self.assertEqual(tabs[0].get("name"), "via-alias")

    def test_wezterm_failure_says_restore_will_reopen_them(self):
        self.session(1, "ttys001", "claude --model opus", name="keep-me")
        self.wezterm_fails = True
        _, out, snap = self.dump()
        md = (snap / "RESTORE.md").read_text()
        self.assertNotIn("non rouvertes", md)
        self.assertNotIn("pas rouvertes", out)
        self.wezterm_fails = False
        self.restore(snap)
        self.assertIn("--model opus", self.spawned[0][-1], "the fallback must keep the flags")

    def test_fallback_skips_background_sessions_and_empty_cwd(self):
        self.session(1, "ttys001", "claude", name="tab")
        self.session(2, "ttys014", "claude bg-spare", name="bg", kind="bg", pane=False)
        rec = json.loads((self.sessions_dir / "1.json").read_text()); rec.pop("cwd")
        (self.sessions_dir / "1.json").write_text(json.dumps(rec))
        self.wezterm_fails = True
        _, _, snap = self.dump()
        self.wezterm_fails = False
        out = self.restore(snap)
        self.assertEqual(self.spawned, [])
        self.assertIn("dossier absent", out)


class FirefoxPass4Test(Env):
    def profile(self, name, files):
        d = self.tmp / "ff/Profiles" / name
        (d / "sessionstore-backups").mkdir(parents=True)
        for rel, data in files.items():
            (d / rel).write_bytes(data)
        return d

    def test_unreadable_session_is_never_left_for_restore(self):
        self.profile("a.bad", {"sessionstore.jsonlz4": b"mozLz40\0garbage"})
        snap = self.tmp / "snap"; snap.mkdir()
        with redirect_stdout(io.StringIO()):
            _, problems = rs.dump_firefox(snap)
        self.assertTrue(problems)
        self.assertFalse((snap / "firefox/a.bad/session.jsonlz4").exists())
        with mock.patch.object(rs, "firefox_running", return_value=False), \
             redirect_stdout(io.StringIO()) as out:
            rs.restore_firefox(snap, None, False)
        self.assertFalse((self.tmp / "ff/Profiles/a.bad/sessionstore.jsonlz4.before-restore").exists())
        self.assertIn("a.bad", out.getvalue())
        self.assertNotIn("remise en place", out.getvalue())

    def test_last_window_closed_still_lists_its_tabs(self):
        session = {"windows": [], "_closedWindows": [ff_session("https://kept")["windows"][0]]}
        self.profile("a.closed", {"sessionstore-backups/recovery.jsonlz4": mozlz4(session)})
        snap = self.tmp / "snap"; snap.mkdir()
        with redirect_stdout(io.StringIO()) as out:
            summary, _ = rs.dump_firefox(snap)
        self.assertEqual(summary[0][1], 1)
        self.assertIn("fenêtre fermée", out.getvalue())

    def test_restore_message_does_not_promise_automatic_reopen(self):
        snap = self.tmp / "snap/firefox/p"; snap.mkdir(parents=True)
        (snap / "session.jsonlz4").write_bytes(mozlz4(ff_session("https://a")))
        (self.tmp / "ff/Profiles/p").mkdir(parents=True)
        with mock.patch.object(rs, "firefox_running", return_value=False), \
             redirect_stdout(io.StringIO()) as out:
            rs.restore_firefox(self.tmp / "snap", None, False)
        self.assertIn("Restaurer la session précédente", out.getvalue())


class RestoreFirefoxTest(Env):
    def test_urls_mode_gives_up_when_firefox_never_starts(self):
        with mock.patch.object(rs.subprocess, "Popen"), \
             mock.patch.object(rs.subprocess, "run") as run, \
             mock.patch.object(rs, "firefox_running", return_value=False), \
             redirect_stdout(io.StringIO()) as out:
            rs.open_urls(self.tmp / "p", [[{"url": "https://a"}, {"url": "https://b"}]])
        run.assert_not_called()
        self.assertIn("pas démarré", out.getvalue())

    def test_full_restore_ignores_another_profile_running(self):
        root = self.tmp / "snap/firefox/abc.default-release"; root.mkdir(parents=True)
        (root / "session.jsonlz4").write_bytes(mozlz4(ff_session("https://a")))
        (self.tmp / "ff/Profiles/abc.default-release").mkdir(parents=True)
        with mock.patch.object(rs, "firefox_running", lambda prof=None: prof is None), \
             redirect_stdout(io.StringIO()):
            rs.restore_firefox(self.tmp / "snap", None, False)
        self.assertTrue((self.tmp / "ff/Profiles/abc.default-release/sessionstore.jsonlz4").exists())

    def test_urls_mode_skips_a_profile_without_tabs_json(self):
        snap = self.tmp / "snap/firefox"
        (snap / "a.broken").mkdir(parents=True)
        (snap / "b.ok").mkdir()
        (snap / "b.ok/tabs.json").write_text(json.dumps([[{"url": "https://b"}]]))
        with mock.patch.object(rs, "open_urls") as ou, redirect_stdout(io.StringIO()) as out:
            rs.restore_firefox(self.tmp / "snap", None, True)
        self.assertEqual([c.args[0].name for c in ou.call_args_list], ["b.ok"])
        self.assertIn("a.broken", out.getvalue())

    def test_urls_mode_checks_the_profile_not_any_firefox(self):
        root = self.tmp / "snap/firefox/abc.default-release"; root.mkdir(parents=True)
        (root / "tabs.json").write_text(json.dumps([[{"url": "https://a"}]]))
        profile = self.tmp / "ff/Profiles/abc.default-release"
        seen = []

        def running(prof=None):
            seen.append(prof)
            return prof is None  # ZAP's Firefox is up, this profile is not
        with mock.patch.object(rs.subprocess, "Popen") as popen, \
             mock.patch.object(rs.subprocess, "run"), \
             mock.patch.object(rs, "firefox_running", running):
            with redirect_stdout(io.StringIO()):
                rs.open_urls(profile, json.loads((root / "tabs.json").read_text()))
        self.assertIn(profile, seen, "must ask about this profile")
        popen.assert_called_once()

    def test_urls_mode_does_not_block_and_uses_the_profile(self):
        root = self.tmp / "snap/firefox/abc.default-release"; root.mkdir(parents=True)
        (root / "tabs.json").write_text(json.dumps([[{"url": "https://a"}, {"url": "https://b"}]]))
        popen, runs = mock.MagicMock(), []

        def fake_run(cmd, **kw):
            self.assertIn("timeout", kw, f"{cmd} could block forever")
            runs.append(cmd)
            return subprocess.CompletedProcess(cmd, 0)
        with mock.patch.object(rs.subprocess, "Popen", popen), \
             mock.patch.object(rs.subprocess, "run", fake_run), \
             mock.patch.object(rs, "firefox_running", side_effect=[False, True, True, True]):
            with redirect_stdout(io.StringIO()):
                rs.restore_firefox(self.tmp / "snap", None, True)
        cmds = [popen.call_args.args[0], *runs]
        profile = str(self.tmp / "ff/Profiles/abc.default-release")
        for c in cmds:
            self.assertIn(profile, c, f"{c} does not target the profile")
        self.assertEqual(sum("https://b" in c for c in cmds), 1)


if __name__ == "__main__":
    unittest.main()
