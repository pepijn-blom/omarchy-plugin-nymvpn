import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import split as nymsplit  # noqa: E402

EXCLUDED_NONE = """No excluded processes
"""

EXCLUDED_TWO = """Excluded processes: 2

- pid: 4242
- pid: 4343
"""

SPLIT_GET_ON = """Split-tunnel is supported
"""

SPLIT_GET_OFF = """Split-tunnel is not supported
"""


def _write_proc(root: Path, pid: int, comm: str, exe: str | None = None) -> None:
    proc = root / str(pid)
    proc.mkdir(parents=True)
    (proc / "comm").write_text(comm + "\n", encoding="utf-8")
    if exe is not None:
        target = Path(exe)
        if not target.is_absolute():
            target = root / "bin" / exe
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("", encoding="utf-8")
        (proc / "exe").symlink_to(target)


class NormalizeNameTests(unittest.TestCase):
    def test_trims_and_lowercases(self):
        self.assertEqual(nymsplit.normalize_name("  AgY "), "agy")

    def test_empty_and_junk(self):
        self.assertEqual(nymsplit.normalize_name(""), "")
        self.assertEqual(nymsplit.normalize_name(None), "")
        self.assertEqual(nymsplit.normalize_name("agy/../bin"), "")
        self.assertEqual(nymsplit.normalize_name("a" * 300), "")


class ProcessMatchTests(unittest.TestCase):
    def test_matches_comm(self):
        self.assertTrue(nymsplit.process_matches("agy", "agy", "/opt/antigravity/antigravity"))

    def test_matches_exe_basename(self):
        self.assertTrue(
            nymsplit.process_matches("antigravity", "agy", "/opt/antigravity/antigravity")
        )

    def test_case_insensitive(self):
        self.assertTrue(nymsplit.process_matches("AGY", "agy", "/opt/agy"))

    def test_truncated_comm_matches_full_name(self):
        comm = "google-chrome-s"
        self.assertEqual(len(comm), 15)
        self.assertTrue(
            nymsplit.process_matches("google-chrome-stable", comm, "/usr/bin/google-chrome-stable")
        )

    def test_unrelated_name_does_not_match(self):
        self.assertFalse(nymsplit.process_matches("agy", "firefox", "/usr/lib/firefox/firefox"))


class SkipTests(unittest.TestCase):
    def test_kernel_threads(self):
        self.assertTrue(nymsplit.is_kernel_thread("[kthreadd]"))
        self.assertFalse(nymsplit.is_kernel_thread("agy"))

    def test_skipped_binaries(self):
        self.assertTrue(nymsplit.is_skipped_name("nym-vpnd"))
        self.assertTrue(nymsplit.is_skipped_name("nym-vpnc"))
        self.assertFalse(nymsplit.is_skipped_name("agy"))


class ScanProcTests(unittest.TestCase):
    def test_reads_comm_and_exe_skips_kernel_and_vpn(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_proc(root, 1, "systemd", "/usr/lib/systemd/systemd")
            _write_proc(root, 42, "agy", "/opt/antigravity/antigravity")
            _write_proc(root, 43, "agy", "/opt/antigravity/antigravity")
            _write_proc(root, 7, "[kthreadd]")
            _write_proc(root, 9, "nym-vpnd", "/usr/bin/nym-vpnd")
            rows = nymsplit.scan_proc(root)
        names = {row["name"] for row in rows}
        self.assertIn("systemd", names)
        self.assertIn("antigravity", names)
        self.assertNotIn("kthreadd", names)
        self.assertNotIn("[kthreadd]", names)
        self.assertNotIn("nym-vpnd", names)
        agy = next(row for row in rows if row["name"] == "antigravity")
        self.assertEqual(sorted(agy["pids"]), [42, 43])
        self.assertTrue(agy["exe"].endswith("antigravity"))

    def test_falls_back_to_comm_when_exe_missing(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            _write_proc(root, 11, "foot")
            rows = nymsplit.scan_proc(root)
        self.assertEqual(rows[0]["name"], "foot")
        self.assertEqual(rows[0]["pids"], [11])
        self.assertEqual(rows[0]["exe"], "")


class ParseCliTests(unittest.TestCase):
    def test_parse_split_get(self):
        self.assertTrue(nymsplit.parse_split_get(SPLIT_GET_ON)["supported"])
        self.assertFalse(nymsplit.parse_split_get(SPLIT_GET_OFF)["supported"])
        self.assertFalse(nymsplit.parse_split_get("")["supported"])

    def test_parse_excluded_processes(self):
        self.assertEqual(nymsplit.parse_excluded_processes(EXCLUDED_NONE), [])
        self.assertEqual(nymsplit.parse_excluded_processes(EXCLUDED_TWO), [4242, 4343])


class SyncDeltaTests(unittest.TestCase):
    def test_adds_matching_and_removes_stale(self):
        processes = [
            {"name": "antigravity", "pids": [42, 43], "exe": "/opt/antigravity/antigravity", "comm": "agy"},
            {"name": "firefox", "pids": [88], "exe": "/usr/lib/firefox/firefox", "comm": "firefox"},
        ]
        add, remove = nymsplit.sync_delta(
            processes,
            names=["agy"],
            excluded=[43, 88],
        )
        self.assertEqual(add, [42])
        self.assertEqual(remove, [88])

    def test_empty_names_removes_all_known_excluded(self):
        processes = [
            {"name": "agy", "pids": [42], "exe": "", "comm": "agy"},
        ]
        add, remove = nymsplit.sync_delta(processes, names=[], excluded=[42, 99])
        self.assertEqual(add, [])
        self.assertEqual(remove, [42, 99])


class SyncTests(unittest.TestCase):
    def test_sync_calls_add_and_remove(self):
        calls = []

        def fake_vpnc(args, timeout=20):
            calls.append(args)
            if args[:2] == ["split-tunnel", "get"]:
                return 0, SPLIT_GET_ON, ""
            if args[:2] == ["split-tunnel", "excluded-processes"]:
                return 0, EXCLUDED_TWO, ""
            if args[:2] == ["split-tunnel", "add-process"]:
                return 0, "", ""
            if args[:2] == ["split-tunnel", "remove-process"]:
                return 0, "", ""
            return 1, "", "unexpected"

        processes = [
            {
                "name": "antigravity",
                "pids": [42, 4242],
                "exe": "/opt/antigravity/antigravity",
                "comm": "agy",
            }
        ]
        with mock.patch.object(nymsplit, "run_vpnc", side_effect=fake_vpnc), \
             mock.patch.object(nymsplit, "scan_proc", return_value=processes):
            payload = nymsplit.sync_excludes(["agy"])
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["supported"])
        self.assertEqual(payload["names"], ["agy"])
        self.assertEqual(payload["attached"][0]["name"], "agy")
        self.assertEqual(payload["attached"][0]["pids"], [42, 4242])
        self.assertIn(["split-tunnel", "add-process", "42"], calls)
        self.assertIn(["split-tunnel", "remove-process", "4343"], calls)
        self.assertNotIn(["split-tunnel", "add-process", "4242"], calls)

    def test_unsupported_skips_pid_changes(self):
        calls = []

        def fake_vpnc(args, timeout=20):
            calls.append(args)
            return 0, SPLIT_GET_OFF, ""

        with mock.patch.object(nymsplit, "run_vpnc", side_effect=fake_vpnc), \
             mock.patch.object(nymsplit, "scan_proc", return_value=[]):
            payload = nymsplit.sync_excludes(["agy"])
        self.assertTrue(payload["ok"])
        self.assertFalse(payload["supported"])
        self.assertEqual(payload["attached"], [])
        self.assertEqual(calls, [["split-tunnel", "get"]])

    def test_sync_get_error_does_not_hide_feature(self):
        with mock.patch.object(nymsplit, "run_vpnc", return_value=(1, "", "polkit denied")), \
             mock.patch.object(nymsplit, "scan_proc", return_value=[]):
            payload = nymsplit.sync_excludes(["agy"])
        self.assertFalse(payload["ok"])
        self.assertTrue(payload["supported"])
        self.assertEqual(payload["attached"], [])


class MainTests(unittest.TestCase):
    def test_list_running_emits_json(self):
        rows = [{"name": "agy", "pids": [1], "exe": "/opt/agy", "comm": "agy"}]
        stdout = _run_main(["list-running"], scan=rows)
        payload = json.loads(stdout)
        self.assertTrue(payload["ok"])
        self.assertEqual(payload["processes"][0]["name"], "agy")
        self.assertEqual(payload["processes"][0]["pids"], [1])

    def test_sync_passes_exclude_flags(self):
        with mock.patch.object(
            nymsplit,
            "sync_excludes",
            return_value={"ok": True, "supported": True, "names": ["agy"], "attached": []},
        ) as sync:
            stdout = _run_main(["sync", "--exclude", "agy", "--exclude", "firefox"])
        sync.assert_called_once_with(["agy", "firefox"])
        self.assertEqual(json.loads(stdout)["ok"], True)

    def test_unknown_command_fails(self):
        code, stdout, _stderr = _run_main_code(["nope"])
        self.assertEqual(code, 2)
        self.assertFalse(json.loads(stdout)["ok"])

    def test_get_emits_supported(self):
        with mock.patch.object(nymsplit, "run_vpnc", return_value=(0, SPLIT_GET_ON, "")):
            stdout = _run_main(["get"])
        payload = json.loads(stdout)
        self.assertTrue(payload["ok"])
        self.assertTrue(payload["supported"])

    def test_get_emits_unsupported(self):
        with mock.patch.object(nymsplit, "run_vpnc", return_value=(0, SPLIT_GET_OFF, "")):
            stdout = _run_main(["get"])
        self.assertFalse(json.loads(stdout)["supported"])

    def test_get_error_does_not_claim_unsupported(self):
        with mock.patch.object(nymsplit, "run_vpnc", return_value=(1, "", "daemon unavailable")):
            code, stdout, _stderr = _run_main_code(["get"])
        payload = json.loads(stdout)
        self.assertEqual(code, 1)
        self.assertFalse(payload["ok"])
        self.assertTrue(payload["supported"])


def _run_main(argv, scan=None):
    code, stdout, stderr = _run_main_code(argv, scan=scan)
    if code != 0:
        raise AssertionError(f"main {argv!r} exited {code}: {stdout}{stderr}")
    return stdout


def _run_main_code(argv, scan=None):
    import io

    stdout = io.StringIO()
    stderr = io.StringIO()
    extra = {}
    if scan is not None:
        extra["scan_proc"] = mock.Mock(return_value=scan)
    with mock.patch.object(sys, "stdout", stdout), \
         mock.patch.object(sys, "stderr", stderr), \
         mock.patch.dict(os.environ, {}, clear=False):
        ctx = mock.patch.object(nymsplit, "scan_proc", extra["scan_proc"]) if scan is not None else mock.MagicMock()
        if scan is None:
            ctx = mock.MagicMock()
        with ctx:
            code = nymsplit.main(argv)
    return code, stdout.getvalue(), stderr.getvalue()


if __name__ == "__main__":
    unittest.main()
