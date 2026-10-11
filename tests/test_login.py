import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import login as nymlogin  # noqa: E402

# Fake words only — not a BIP39 phrase.
TWELVE = b"alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
TWENTY_FOUR = TWELVE + b" " + TWELVE


class NormalizeTests(unittest.TestCase):
    def test_collapses_whitespace_and_lowercases(self):
        raw = b"  Alpha   BRAVO\tCharlie  "
        self.assertEqual(nymlogin.normalize_phrase(raw), b"alpha bravo charlie")


class ShapeTests(unittest.TestCase):
    def test_twelve_words_ok(self):
        self.assertTrue(nymlogin.is_mnemonic_shape(TWELVE))

    def test_twenty_four_words_ok(self):
        self.assertTrue(nymlogin.is_mnemonic_shape(TWENTY_FOUR))

    def test_wrong_count_rejected(self):
        self.assertFalse(nymlogin.is_mnemonic_shape(b"alpha bravo charlie"))
        eleven = b" ".join([b"alpha"] * 11)
        thirteen = b" ".join([b"alpha"] * 13)
        self.assertFalse(nymlogin.is_mnemonic_shape(eleven))
        self.assertFalse(nymlogin.is_mnemonic_shape(thirteen))

    def test_non_letters_rejected(self):
        words = TWELVE.split()
        words[0] = b"alpha1"
        self.assertFalse(nymlogin.is_mnemonic_shape(b" ".join(words)))


class SanitizeTests(unittest.TestCase):
    def test_strips_full_phrase_only(self):
        raw = "Failed: " + TWELVE.decode() + " and also alpha is fine"
        out = nymlogin.sanitize_output(raw, TWELVE)
        self.assertNotIn(TWELVE.decode(), out)
        self.assertIn("alpha is fine", out)

    def test_empty_phrase_returns_text(self):
        self.assertEqual(nymlogin.sanitize_output("ok", b""), "ok")


class WipeTests(unittest.TestCase):
    def test_wipe_clears_buffer(self):
        buf = bytearray(b"secret-bytes")
        nymlogin.wipe(buf)
        self.assertEqual(bytes(buf), b"")


class ClassifyErrorTests(unittest.TestCase):
    def test_invalid_mnemonic_message(self):
        self.assertEqual(
            nymlogin.classify_error("Failed to set account: InvalidMnemonic(bad word)"),
            "Invalid recovery phrase",
        )

    def test_generic_failure(self):
        self.assertEqual(
            nymlogin.classify_error("daemon unavailable"),
            "Could not save account",
        )


class MainArgvTests(unittest.TestCase):
    def test_rejects_extra_argv_without_echoing_it(self):
        stderr = io.StringIO()
        with mock.patch.object(sys, "stderr", stderr):
            code = nymlogin.main(["alpha", "bravo"])
        self.assertEqual(code, 2)
        message = stderr.getvalue()
        self.assertIn("stdin only", message.lower())
        self.assertNotIn("alpha", message)
        self.assertNotIn("bravo", message)


class MainStdinTests(unittest.TestCase):
    def test_invalid_shape_does_not_spawn_vpnc(self):
        with mock.patch.object(nymlogin, "run_account_set") as run:
            code, stdout, _stderr = _run_main(b"only three words here\n")
        run.assert_not_called()
        self.assertEqual(code, 1)
        payload = json.loads(stdout)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "Invalid recovery phrase")
        self.assertNotIn("only three words", stdout)

    def test_success_returns_ok_without_phrase(self):
        with mock.patch.object(
            nymlogin, "run_account_set", return_value=(0, "Your account has been set", "")
        ) as run:
            code, stdout, _stderr = _run_main(TWELVE + b"\n")
        run.assert_called_once_with(TWELVE)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(stdout), {"ok": True})
        self.assertNotIn("alpha", stdout)

    def test_vpnc_invalid_mnemonic_is_generic(self):
        leaked = "Failed to set account: InvalidMnemonic " + TWELVE.decode()
        with mock.patch.object(
            nymlogin, "run_account_set", return_value=(1, "", leaked)
        ):
            code, stdout, _stderr = _run_main(TWELVE + b"\n")
        self.assertEqual(code, 1)
        payload = json.loads(stdout)
        self.assertFalse(payload["ok"])
        self.assertEqual(payload["error"], "Invalid recovery phrase")
        self.assertNotIn(TWELVE.decode(), stdout)

    def test_vpnc_other_failure_is_generic(self):
        with mock.patch.object(
            nymlogin, "run_account_set", return_value=(1, "", "daemon down")
        ):
            code, stdout, _stderr = _run_main(TWELVE + b"\n")
        payload = json.loads(stdout)
        self.assertEqual(payload["error"], "Could not save account")
        self.assertNotIn("daemon down", stdout)

    def test_empty_stdin_does_not_spawn_vpnc(self):
        with mock.patch.object(nymlogin, "run_account_set") as run:
            code, stdout, _stderr = _run_main(b"")
        run.assert_not_called()
        self.assertEqual(code, 1)
        self.assertEqual(json.loads(stdout)["error"], "Invalid recovery phrase")


class ScriptInvocationTests(unittest.TestCase):
    def test_cli_args_are_rejected_and_not_echoed(self):
        completed = subprocess.run(
            [sys.executable, str(ROOT / "login.py"), "alpha", "bravo"],
            capture_output=True,
            text=True,
            input="ignored\n",
        )
        self.assertEqual(completed.returncode, 2)
        self.assertNotIn("alpha", completed.stdout)
        self.assertNotIn("bravo", completed.stdout)
        self.assertNotIn("alpha", completed.stderr)
        self.assertNotIn("bravo", completed.stderr)
        self.assertIn("stdin only", completed.stderr.lower())


def _run_main(stdin_bytes):
    stdin = io.BytesIO(stdin_bytes)
    stdout = io.StringIO()
    stderr = io.StringIO()
    with mock.patch.object(sys, "stdin", mock.Mock(buffer=stdin)), \
         mock.patch.object(sys, "stdout", stdout), \
         mock.patch.object(sys, "stderr", stderr):
        code = nymlogin.main([])
    return code, stdout.getvalue(), stderr.getvalue()


class TrustedBinaryTests(unittest.TestCase):
    def test_user_owned_binary_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "nym-vpnc"
            fake.write_bytes(b"")
            fake.chmod(0o755)
            with mock.patch.object(nymlogin.shutil, "which", return_value=str(fake)):
                self.assertIsNone(nymlogin.trusted_system_binary("nym-vpnc"))

    def test_root_owned_path_outside_system_dirs_is_rejected(self):
        target = Path("/tmp/nym-vpnc")
        fake_stat = os.stat_result((0o100755, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        with mock.patch.object(nymlogin.shutil, "which", return_value=str(target)), \
             mock.patch.object(Path, "resolve", return_value=target), \
             mock.patch.object(Path, "stat", return_value=fake_stat):
            self.assertIsNone(nymlogin.trusted_system_binary("nym-vpnc"))

    def test_group_writable_system_binary_is_rejected(self):
        target = Path("/usr/bin/nym-vpnc")
        fake_stat = os.stat_result((0o100775, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        with mock.patch.object(nymlogin.shutil, "which", return_value=str(target)), \
             mock.patch.object(Path, "resolve", return_value=target), \
             mock.patch.object(Path, "stat", return_value=fake_stat):
            self.assertIsNone(nymlogin.trusted_system_binary("nym-vpnc"))

    def test_root_owned_system_binary_is_accepted(self):
        target = Path("/usr/bin/nym-vpnc")
        fake_stat = os.stat_result((0o100755, 0, 0, 1, 0, 0, 0, 0, 0, 0))
        with mock.patch.object(nymlogin.shutil, "which", return_value=str(target)), \
             mock.patch.object(Path, "resolve", return_value=target), \
             mock.patch.object(Path, "stat", return_value=fake_stat):
            self.assertEqual(nymlogin.trusted_system_binary("nym-vpnc"), str(target))

    def test_untrusted_binary_does_not_spawn(self):
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / "nym-vpnc"
            fake.write_bytes(b"")
            fake.chmod(0o755)
            with mock.patch.object(nymlogin.shutil, "which", return_value=str(fake)), \
                 mock.patch.object(nymlogin.subprocess, "Popen") as popen:
                code, out, err = nymlogin.run_account_set(TWELVE)
        popen.assert_not_called()
        self.assertEqual(code, 127)
        self.assertNotIn(TWELVE.decode(), out)
        self.assertNotIn(TWELVE.decode(), err)


class ScrubTests(unittest.TestCase):
    def test_scrub_clears_cmdline_or_kills_the_child(self):
        secret = b"notarealsecretphrasexyz"
        proc = subprocess.Popen(
            [sys.executable, "-c", "import time; time.sleep(12)", secret.decode()],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        try:
            deadline = time.monotonic() + 2
            cmdline = b""
            while time.monotonic() < deadline:
                try:
                    cmdline = Path(f"/proc/{proc.pid}/cmdline").read_bytes()
                except OSError:
                    cmdline = b""
                if secret in cmdline:
                    break
                time.sleep(0.02)
            self.assertIn(secret, cmdline)
            cleared = nymlogin.hold_until_argv_clear(proc, secret)
            if cleared:
                after = Path(f"/proc/{proc.pid}/cmdline").read_bytes()
                self.assertNotIn(secret, after)
                self.assertIsNone(proc.poll())
            else:
                proc.wait(timeout=2)
                self.assertIsNotNone(proc.poll())
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait(timeout=2)


if __name__ == "__main__":
    unittest.main()
