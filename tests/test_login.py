import io
import json
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import account_rpc  # noqa: E402
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


class SocketStoreTests(unittest.TestCase):
    def test_login_helper_never_spawns_a_process(self):
        source = (ROOT / "login.py").read_text(encoding="utf-8")
        self.assertNotIn("Popen", source)
        self.assertNotIn("subprocess", source)

    def test_phrase_is_not_in_this_process_cmdline(self):
        seen = {}
        with self._server(seen=seen) as path:
            code, out, err = account_rpc.store_account(TWELVE, path)
        self.assertEqual((code, out, err), (0, "", ""))
        self.assertIn(TWELVE, seen["body"])
        self.assertNotIn(TWELVE, Path("/proc/self/cmdline").read_bytes())

    def test_rejected_phrase_is_a_fixed_message(self):
        detail = account_rpc._encode_len_field(10, TWELVE)
        body = account_rpc._encode_len_field(1, detail)
        with self._server(body=body) as path:
            code, out, err = account_rpc.store_account(TWELVE, path)
        self.assertEqual(code, 1)
        self.assertEqual(err, "Invalid recovery phrase")
        self.assertNotIn(TWELVE.decode(), out)
        self.assertNotIn(TWELVE.decode(), err)

    def test_auth_refusal_does_not_send_the_phrase(self):
        seen = {}
        with self._server(auth=b"\x02", seen=seen) as path:
            code, _out, err = account_rpc.store_account(TWELVE, path)
        self.assertEqual(code, 1)
        self.assertEqual(err, "Could not save account")
        self.assertNotIn(TWELVE, seen.get("received", b""))

    def test_run_account_set_does_not_call_popen(self):
        with self._server() as path, \
             mock.patch.object(account_rpc, "socket_path", return_value=path), \
             mock.patch.object(subprocess, "Popen", side_effect=AssertionError("spawned")):
            code, out, err = nymlogin.run_account_set(TWELVE)
        self.assertEqual((code, out, err), (0, "", ""))

    def _server(self, body=b"", auth=b"\x01", seen=None):
        return _FakeDaemon(body=body, auth=auth, seen=seen)


class _FakeDaemon:
    def __init__(self, body: bytes, auth: bytes, seen: dict | None) -> None:
        self.body = body
        self.auth = auth
        self.seen = seen if seen is not None else {}
        self._tmp = tempfile.TemporaryDirectory()
        self.path = str(Path(self._tmp.name) / "nym-vpn.sock")
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._ready = threading.Event()

    def __enter__(self) -> str:
        self._thread.start()
        self._ready.wait(2)
        return self.path

    def __exit__(self, *args) -> None:
        self._thread.join(3)
        self._tmp.cleanup()

    def _run(self) -> None:
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        srv.bind(self.path)
        srv.listen(1)
        srv.settimeout(5)
        self._ready.set()
        try:
            conn, _addr = srv.accept()
        except OSError:
            srv.close()
            return
        conn.settimeout(5)
        try:
            query = conn.recv(1)
            self.seen["received"] = query
            conn.sendall(self.auth)
            if self.auth != b"\x01":
                return
            preface = _recv(conn, 24)
            self.seen["received"] += preface
            _read_frame(conn)
            conn.sendall(account_rpc._frame(0x4, 0, 0))
            blobs = bytearray()
            while True:
                kind, flags, _stream, payload = _read_frame(conn)
                blobs += payload
                if kind == 0 and flags & 0x1:
                    break
            self.seen["received"] += bytes(blobs)
            self.seen["body"] = bytes(blobs)
            conn.sendall(account_rpc._frame(0x1, 0x4, 1, bytes([0x88])))
            message = b"\x00" + len(self.body).to_bytes(4, "big") + self.body
            conn.sendall(account_rpc._frame(0x0, 0, 1, message))
            trailers = account_rpc._literal("grpc-status", "0")
            conn.sendall(account_rpc._frame(0x1, 0x5, 1, trailers))
        finally:
            conn.close()
            srv.close()


def _recv(sock: socket.socket, size: int) -> bytes:
    buf = bytearray()
    while len(buf) < size:
        chunk = sock.recv(size - len(buf))
        if not chunk:
            break
        buf += chunk
    return bytes(buf)


def _read_frame(sock: socket.socket):
    header = _recv(sock, 9)
    length = int.from_bytes(header[:3], "big")
    kind, flags = header[3], header[4]
    payload = _recv(sock, length) if length else b""
    return kind, flags, 0, payload


if __name__ == "__main__":
    unittest.main()
