#!/usr/bin/python3
"""Store a NymVPN account from a recovery phrase on stdin.

The phrase is never accepted from argv or the environment. It is passed to
a root-owned system nym-vpnc for `account set`. The child argv is overwritten
before the call is allowed to finish; if that overwrite cannot be confirmed,
the child is killed. Captured CLI output is stripped of the phrase before
any JSON is printed.
"""

from __future__ import annotations

import ctypes
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from pathlib import Path

WORD_RE = re.compile(rb"^[a-z]+$")
VPNC_TIMEOUT_SEC = 30
SCRUB_DEADLINE_SEC = 0.2
SYSTEM_BINDIRS = ("/usr/bin", "/usr/sbin", "/bin")

PTRACE_ATTACH = 16
PTRACE_DETACH = 17


class _Iovec(ctypes.Structure):
    _fields_ = [("iov_base", ctypes.c_void_p), ("iov_len", ctypes.c_size_t)]


def normalize_phrase(raw: bytes | bytearray) -> bytes:
    return b" ".join(bytes(raw).lower().split())


def is_mnemonic_shape(normalized: bytes) -> bool:
    words = bytes(normalized).split()
    if len(words) not in (12, 24):
        return False
    return all(WORD_RE.fullmatch(word) is not None for word in words)


def sanitize_output(text: str, phrase: bytes) -> str:
    value = str(text or "")
    if not phrase:
        return value
    try:
        secret = phrase.decode("ascii")
    except UnicodeDecodeError:
        return value
    if secret:
        value = value.replace(secret, "")
    return value


def wipe(buf: bytearray) -> None:
    for i in range(len(buf)):
        buf[i] = 0
    del buf[:]


def classify_error(text: str) -> str:
    compact = str(text or "").lower().replace(" ", "")
    if "invalid" in compact and "mnemonic" in compact:
        return "Invalid recovery phrase"
    return "Could not save account"


def _emit(payload: dict) -> None:
    json.dump(payload, sys.stdout)
    sys.stdout.write("\n")


def trusted_system_binary(name: str) -> str | None:
    """Return a root-owned, non-writable executable directly under a system bin dir."""
    found = shutil.which(name)
    if not found:
        return None
    try:
        real = Path(found).resolve()
        st = real.stat()
    except OSError:
        return None
    if not stat.S_ISREG(st.st_mode):
        return None
    if real.parent.as_posix() not in SYSTEM_BINDIRS:
        return None
    if st.st_uid != 0:
        return None
    if st.st_mode & 0o022:
        return None
    return str(real)


def _proc_fields(pid: int) -> list[str] | None:
    try:
        raw = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    except OSError:
        return None
    close = raw.rfind(")")
    if close < 0:
        return None
    return raw[close + 1 :].split()


def _proc_starttime(pid: int) -> str | None:
    fields = _proc_fields(pid)
    if not fields or len(fields) <= 19:
        return None
    return fields[19]


def _arg_bounds(pid: int) -> tuple[int, int] | None:
    fields = _proc_fields(pid)
    if not fields or len(fields) < 47:
        return None
    try:
        start = int(fields[45])
        end = int(fields[46])
    except (IndexError, ValueError):
        return None
    if end <= start:
        return None
    return start, end


def _vm_write(pid: int, addr: int, data: bytes) -> bool:
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
    except OSError:
        return False
    buf = ctypes.create_string_buffer(data, len(data))
    local = _Iovec(ctypes.cast(buf, ctypes.c_void_p), len(data))
    remote = _Iovec(ctypes.c_void_p(addr), len(data))
    libc.process_vm_writev.restype = ctypes.c_ssize_t
    wrote = libc.process_vm_writev(
        ctypes.c_int(pid),
        ctypes.byref(local),
        ctypes.c_ulong(1),
        ctypes.byref(remote),
        ctypes.c_ulong(1),
        ctypes.c_ulong(0),
    )
    return wrote == len(data)


def _mem_write(pid: int, addr: int, data: bytes) -> bool:
    try:
        with open(f"/proc/{pid}/mem", "r+b", buffering=0) as mem:
            mem.seek(addr)
            return mem.write(data) == len(data)
    except OSError:
        return False


def _ptrace_mem_write(pid: int, addr: int, data: bytes) -> bool:
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
    except OSError:
        return False
    libc.ptrace.restype = ctypes.c_long
    libc.ptrace.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_void_p,
    ]
    if libc.ptrace(PTRACE_ATTACH, pid, None, None) != 0:
        return False
    try:
        os.waitpid(pid, 0)
        return _mem_write(pid, addr, data)
    except OSError:
        return False
    finally:
        libc.ptrace(PTRACE_DETACH, pid, None, None)


def scrub_child_argv(pid: int, secret: bytes, starttime: str | None = None) -> bool:
    if not secret:
        return False
    if starttime is not None and _proc_starttime(pid) != starttime:
        return False
    try:
        cmdline = Path(f"/proc/{pid}/cmdline").read_bytes()
    except OSError:
        return False
    idx = cmdline.find(secret)
    if idx < 0:
        return False
    bounds = _arg_bounds(pid)
    if bounds is None:
        return False
    start, end = bounds
    addr = start + idx
    if addr < start or addr + len(secret) > end:
        return False
    if starttime is not None and _proc_starttime(pid) != starttime:
        return False
    stars = b"*" * len(secret)
    if _vm_write(pid, addr, stars):
        return True
    if starttime is not None and _proc_starttime(pid) != starttime:
        return False
    if _mem_write(pid, addr, stars):
        return True
    if starttime is not None and _proc_starttime(pid) != starttime:
        return False
    return _ptrace_mem_write(pid, addr, stars)


def _same_process(pid: int, starttime: str | None) -> bool | None:
    """True when pid still has starttime, False if reused, None if it is gone."""
    now = _proc_starttime(pid)
    if now is None:
        return None
    if starttime is None:
        return False
    return now == starttime


def hold_until_argv_clear(
    proc: subprocess.Popen[str],
    phrase: bytes,
    timeout: float = SCRUB_DEADLINE_SEC,
) -> bool:
    """Return True only when phrase is no longer in the live cmdline.

    Kills the child when the phrase is still visible at the deadline and the
    pid has not been reused. A reused pid is left alone.
    """
    deadline = time.monotonic() + timeout
    start = _proc_starttime(proc.pid)
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            return True
        if start is None:
            start = _proc_starttime(proc.pid)
            if start is None:
                time.sleep(0.001)
                continue
        ident = _same_process(proc.pid, start)
        if ident is False:
            return False
        if ident is None:
            return True
        try:
            data = Path(f"/proc/{proc.pid}/cmdline").read_bytes()
        except OSError:
            return proc.poll() is not None
        if phrase in data:
            scrub_child_argv(proc.pid, phrase, start)
            if _same_process(proc.pid, start) is False:
                return False
            try:
                after = Path(f"/proc/{proc.pid}/cmdline").read_bytes()
            except OSError:
                return proc.poll() is not None
            if phrase not in after:
                return True
        elif b"nym-vpnc" in data:
            return True
        time.sleep(0.001)
    if proc.poll() is not None:
        return True
    if start is not None and _same_process(proc.pid, start) is False:
        return False
    try:
        data = Path(f"/proc/{proc.pid}/cmdline").read_bytes()
    except OSError:
        data = b""
    if phrase not in data and (b"nym-vpnc" in data or proc.poll() is not None):
        return True
    try:
        proc.kill()
    except OSError:
        pass
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        pass
    return False


def run_account_set(phrase: bytes) -> tuple[int, str, str]:
    binary = trusted_system_binary("nym-vpnc")
    if not binary:
        return 127, "", "nym-vpnc not found"
    try:
        text = phrase.decode("ascii")
    except UnicodeDecodeError:
        return 1, "", "Invalid recovery phrase"
    try:
        proc = subprocess.Popen(
            [binary, "account", "set", text],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
            text=True,
        )
    except OSError as exc:
        return 1, "", str(exc)
    if not hold_until_argv_clear(proc, phrase):
        return 1, "", "Could not save account"
    try:
        stdout, stderr = proc.communicate(timeout=VPNC_TIMEOUT_SEC)
    except subprocess.TimeoutExpired:
        proc.kill()
        stdout, stderr = proc.communicate()
        return 124, stdout or "", stderr or "timed out"
    return proc.returncode if proc.returncode is not None else 1, stdout or "", stderr or ""


def _set_from_buffer(buf: bytearray) -> int:
    normalized = bytearray(normalize_phrase(buf))
    try:
        phrase = bytes(normalized)
        if not is_mnemonic_shape(phrase):
            _emit({"ok": False, "error": "Invalid recovery phrase"})
            return 1
        code, out, err = run_account_set(phrase)
        combined = sanitize_output(f"{out}\n{err}", phrase)
        if code == 0:
            _emit({"ok": True})
            return 0
        _emit({"ok": False, "error": classify_error(combined)})
        return 1
    finally:
        wipe(normalized)


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args:
        print("login.py reads the recovery phrase from stdin only", file=sys.stderr)
        return 2
    raw = sys.stdin.buffer.readline() or sys.stdin.buffer.read()
    buf = bytearray(raw)
    try:
        return _set_from_buffer(buf)
    finally:
        wipe(buf)


if __name__ == "__main__":
    raise SystemExit(main())
