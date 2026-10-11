#!/usr/bin/python3
"""Store a NymVPN account from a recovery phrase on stdin.

The phrase is never accepted from argv or the environment. It is sent to
nym-vpnd in a gRPC request on the local unix socket and is never placed in a
process argument. Daemon error text is not returned to the caller.
"""

from __future__ import annotations

import json
import re
import sys

import account_rpc

WORD_RE = re.compile(rb"^[a-z]+$")


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


def run_account_set(phrase: bytes) -> tuple[int, str, str]:
    return account_rpc.store_account(phrase)


def _set_from_buffer(buf: bytearray) -> int:
    normalized = bytearray(normalize_phrase(buf))
    try:
        phrase = bytes(normalized)
        if not is_mnemonic_shape(phrase):
            _emit({"ok": False, "error": "Invalid recovery phrase"})
            return 1
        code, out, err = run_account_set(phrase)
        if code == 0:
            _emit({"ok": True})
            return 0
        safe = sanitize_output(f"{out}\n{err}", phrase)
        if err == "Invalid recovery phrase":
            message = err
        else:
            message = classify_error(safe)
        _emit({"ok": False, "error": message})
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
