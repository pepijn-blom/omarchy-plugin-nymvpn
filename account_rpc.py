"""Store a Nym account over the nym-vpnd unix socket.

The recovery phrase is written only into the gRPC request body. It is never
placed in a process argument, so it does not appear in /proc/<pid>/cmdline.
"""

from __future__ import annotations

import os
import socket
from pathlib import Path

SOCKET_CANDIDATES = ("/var/run/nym-vpn.sock", "/run/nym-vpn.sock")
RPC_TIMEOUT_SEC = 30
STORE_ACCOUNT = "/nym_vpn_service.NymVpnService/StoreAccount"

# HPACK Huffman code lengths, RFC 7541 Appendix B, symbols 0..256 (256 is EOS).
_HUFFMAN_LENGTHS = bytes.fromhex(
    "0d171c1c1c1c1c1c1c181e1c1c1e1c1c1c1c1c1c1c1c1e1c1c1c1c1c1c1c1c1c"
    "060a0a0c0d06080b0a0a080b080606060505050606060606060607080f060c0a"
    "0d06070707070707070707070707070707070707070707070807080d130d0e06"
    "0f05060506050606060507070606060506070605050607070707070f0b0e0d1c"
    "1416141416161617161717171717181718181617181717171715161716171718"
    "1615141616171715171616181516171715151615171617171416161617161617"
    "1a1a1413161716191a1a1a1b1b1a181913151a1b1b1a1b1815151a1a1c1b1b1b"
    "14181415161515171616191918181a171a1b1a1a1b1b1b1b1b1c1b1b1b1b1b1a1e"
)

# RFC 7541 Appendix A. Index 0 is unused.
_STATIC = [
    ("", ""),
    (":authority", ""),
    (":method", "GET"),
    (":method", "POST"),
    (":path", "/"),
    (":path", "/index.html"),
    (":scheme", "http"),
    (":scheme", "https"),
    (":status", "200"),
    (":status", "204"),
    (":status", "206"),
    (":status", "304"),
    (":status", "400"),
    (":status", "404"),
    (":status", "500"),
    ("accept-charset", ""),
    ("accept-encoding", "gzip, deflate"),
    ("accept-language", ""),
    ("accept-ranges", ""),
    ("accept", ""),
    ("access-control-allow-origin", ""),
    ("age", ""),
    ("allow", ""),
    ("authorization", ""),
    ("cache-control", ""),
    ("content-disposition", ""),
    ("content-encoding", ""),
    ("content-language", ""),
    ("content-length", ""),
    ("content-location", ""),
    ("content-range", ""),
    ("content-type", ""),
    ("cookie", ""),
    ("date", ""),
    ("etag", ""),
    ("expect", ""),
    ("expires", ""),
    ("from", ""),
    ("host", ""),
    ("if-match", ""),
    ("if-modified-since", ""),
    ("if-none-match", ""),
    ("if-range", ""),
    ("if-unmodified-since", ""),
    ("last-modified", ""),
    ("link", ""),
    ("location", ""),
    ("max-forwards", ""),
    ("proxy-authenticate", ""),
    ("proxy-authorization", ""),
    ("range", ""),
    ("referer", ""),
    ("refresh", ""),
    ("retry-after", ""),
    ("server", ""),
    ("set-cookie", ""),
    ("strict-transport-security", ""),
    ("transfer-encoding", ""),
    ("user-agent", ""),
    ("vary", ""),
    ("via", ""),
    ("www-authenticate", ""),
]


def _huffman_table() -> dict[tuple[int, int], int]:
    lengths = _HUFFMAN_LENGTHS
    order = sorted(range(len(lengths)), key=lambda i: (lengths[i], i))
    table: dict[tuple[int, int], int] = {}
    code = 0
    prev = int(lengths[order[0]])
    for n, symbol in enumerate(order):
        length = int(lengths[symbol])
        if n:
            code <<= length - prev
        table[(code, length)] = symbol
        code += 1
        prev = length
    return table


_HUFFMAN = _huffman_table()


def _huffman_decode(raw: bytes) -> bytes:
    out = bytearray()
    acc = 0
    nbits = 0
    for byte in raw:
        for shift in range(7, -1, -1):
            acc = (acc << 1) | ((byte >> shift) & 1)
            nbits += 1
            symbol = _HUFFMAN.get((acc, nbits))
            if symbol is None:
                if nbits > 30:
                    raise ValueError("bad huffman")
                continue
            if symbol == 256:
                raise ValueError("huffman eos")
            out.append(symbol)
            acc = 0
            nbits = 0
    if nbits >= 8 or (nbits and acc != (1 << nbits) - 1):
        raise ValueError("bad huffman padding")
    return bytes(out)


def _read_int(buf: bytes, index: int, prefix: int) -> tuple[int, int]:
    mask = (1 << prefix) - 1
    value = buf[index] & mask
    index += 1
    if value < mask:
        return value, index
    shift = 0
    while True:
        byte = buf[index]
        index += 1
        value += (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, index
        shift += 7


def _read_string(buf: bytes, index: int) -> tuple[str, int]:
    huffman = bool(buf[index] & 0x80)
    length, index = _read_int(buf, index, 7)
    raw = buf[index : index + length]
    index += length
    if huffman:
        raw = _huffman_decode(raw)
    return raw.decode("utf-8", "replace"), index


class _HeaderTable:
    def __init__(self) -> None:
        self.dynamic: list[tuple[str, str]] = []
        self.max_size = 4096

    def get(self, index: int) -> tuple[str, str]:
        if 1 <= index < len(_STATIC):
            return _STATIC[index]
        return self.dynamic[index - len(_STATIC)]

    def add(self, name: str, value: str) -> None:
        size = len(name.encode()) + len(value.encode()) + 32
        if size > self.max_size:
            self.dynamic.clear()
            return
        self.dynamic.insert(0, (name, value))
        while self._size() > self.max_size and self.dynamic:
            self.dynamic.pop()

    def _size(self) -> int:
        return sum(len(n.encode()) + len(v.encode()) + 32 for n, v in self.dynamic)


def decode_header_block(buf: bytes) -> list[tuple[str, str]]:
    table = _HeaderTable()
    headers: list[tuple[str, str]] = []
    index = 0
    while index < len(buf):
        byte = buf[index]
        if byte & 0x80:
            idx, index = _read_int(buf, index, 7)
            headers.append(table.get(idx))
        elif byte & 0x40:
            idx, index = _read_int(buf, index, 6)
            if idx:
                name = table.get(idx)[0]
            else:
                name, index = _read_string(buf, index)
            value, index = _read_string(buf, index)
            headers.append((name, value))
            table.add(name, value)
        elif byte & 0x20:
            size, index = _read_int(buf, index, 5)
            table.max_size = size
            while table._size() > table.max_size and table.dynamic:
                table.dynamic.pop()
        else:
            idx, index = _read_int(buf, index, 4)
            if idx:
                name = table.get(idx)[0]
            else:
                name, index = _read_string(buf, index)
            value, index = _read_string(buf, index)
            headers.append((name, value))
    return headers


def _literal(name: str, value: str) -> bytes:
    raw_name = name.encode()
    raw_value = value.encode()
    return bytes([0x00, len(raw_name)]) + raw_name + bytes([len(raw_value)]) + raw_value


def _frame(kind: int, flags: int, stream: int, payload: bytes = b"") -> bytes:
    return (
        len(payload).to_bytes(3, "big")
        + bytes([kind, flags])
        + stream.to_bytes(4, "big")
        + payload
    )


def _recv_exact(sock: socket.socket, size: int) -> bytes:
    buf = bytearray()
    while len(buf) < size:
        chunk = sock.recv(size - len(buf))
        if not chunk:
            raise ConnectionError("daemon closed the socket")
        buf += chunk
    return bytes(buf)


def _read_frame(sock: socket.socket) -> tuple[int, int, int, bytes]:
    header = _recv_exact(sock, 9)
    length = int.from_bytes(header[:3], "big")
    kind, flags = header[3], header[4]
    stream = int.from_bytes(header[5:], "big") & 0x7FFFFFFF
    payload = _recv_exact(sock, length) if length else b""
    return kind, flags, stream, payload


def _strip_header_payload(flags: int, payload: bytes) -> bytes:
    index = 0
    if flags & 0x08:
        pad = payload[0]
        index = 1
        payload = payload[: len(payload) - pad]
    if flags & 0x20:
        index += 5
    return payload[index:]


def _encode_varint(value: int) -> bytes:
    out = bytearray()
    while value > 0x7F:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def _encode_len_field(field: int, payload: bytes) -> bytes:
    return _encode_varint((field << 3) | 2) + _encode_varint(len(payload)) + payload


def encode_store_account(mnemonic: bytes) -> bytes:
    """Protobuf StoreAccountRequest for an API (vpn) account."""
    inner = _encode_len_field(1, mnemonic)
    return _encode_len_field(1, inner)


def _iter_fields(buf: bytes):
    index = 0
    while index < len(buf):
        key, index = _read_int_raw(buf, index)
        field, wire = key >> 3, key & 7
        if wire == 0:
            value, index = _read_int_raw(buf, index)
        elif wire == 2:
            length, index = _read_int_raw(buf, index)
            value = buf[index : index + length]
            index += length
        elif wire == 5:
            value = buf[index : index + 4]
            index += 4
        elif wire == 1:
            value = buf[index : index + 8]
            index += 8
        else:
            raise ValueError("unsupported protobuf wire type")
        yield field, value


def _read_int_raw(buf: bytes, index: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        byte = buf[index]
        index += 1
        value |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return value, index
        shift += 7


def account_error_kind(payload: bytes) -> str | None:
    """Return None on success, 'invalid' for a rejected phrase, or 'error'."""
    if not payload:
        return None
    for field, value in _iter_fields(payload):
        if field != 1 or not isinstance(value, bytes):
            continue
        kinds = {number for number, _ in _iter_fields(value)}
        if 9 in kinds or 10 in kinds:
            return "invalid"
        return "error"
    return None


def socket_path() -> str:
    override = os.environ.get("OMARCHY_NYMVPN_SOCKET")
    if override:
        return override
    for candidate in SOCKET_CANDIDATES:
        if Path(candidate).exists():
            return candidate
    return SOCKET_CANDIDATES[0]


def grpc_unary(path: str, body: bytes, sock_path: str | None = None) -> tuple[bytes, list[tuple[str, str]]]:
    """One unary gRPC call. Returns the protobuf message and the trailers."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(RPC_TIMEOUT_SEC)
    try:
        sock.connect(sock_path or socket_path())
        sock.sendall(b"\x01")
        if _recv_exact(sock, 1) != b"\x01":
            raise PermissionError("daemon refused the connection")
        sock.sendall(b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" + _frame(0x4, 0, 0))
        kind, flags, _stream, _payload = _read_frame(sock)
        if kind == 0x4 and not flags & 0x1:
            sock.sendall(_frame(0x4, 0x1, 0))
        block = b"".join(
            [
                _literal(":method", "POST"),
                _literal(":scheme", "http"),
                _literal(":path", path),
                _literal(":authority", "localhost"),
                _literal("content-type", "application/grpc"),
                _literal("te", "trailers"),
            ]
        )
        sock.sendall(_frame(0x1, 0x4, 1, block))
        message = b"\x00" + len(body).to_bytes(4, "big") + body
        sock.sendall(_frame(0x0, 0x1, 1, message))
        data = bytearray()
        header_buf = bytearray()
        trailers: list[tuple[str, str]] = []
        while True:
            kind, flags, stream, payload = _read_frame(sock)
            if kind == 0x4 and not flags & 0x1:
                sock.sendall(_frame(0x4, 0x1, 0))
            elif kind == 0x6 and not flags & 0x1:
                sock.sendall(_frame(0x6, 0x1, 0, payload))
            elif kind == 0x7:
                raise ConnectionError("daemon closed the RPC")
            elif kind == 0x3:
                raise ConnectionError("daemon reset the RPC")
            elif kind in (0x1, 0x9) and stream == 1:
                header_buf += _strip_header_payload(flags, payload)
                if flags & 0x4:
                    decoded = decode_header_block(bytes(header_buf))
                    header_buf.clear()
                    if flags & 0x1:
                        trailers = decoded
                        break
            elif kind == 0x0 and stream == 1:
                if flags & 0x08:
                    pad = payload[0]
                    payload = payload[1 : len(payload) - pad]
                data += payload
                if flags & 0x1 and not header_buf:
                    break
        if data[:1] != b"\x00" or len(data) < 5:
            raise ConnectionError("daemon returned an empty RPC body")
        size = int.from_bytes(data[1:5], "big")
        return bytes(data[5 : 5 + size]), trailers
    finally:
        sock.close()


def store_account(phrase: bytes, sock_path: str | None = None) -> tuple[int, str, str]:
    """Store the phrase. Returned text never includes the phrase."""
    try:
        payload, trailers = grpc_unary(STORE_ACCOUNT, encode_store_account(phrase), sock_path)
    except (OSError, TimeoutError, ValueError, ConnectionError, PermissionError):
        return 1, "", "Could not save account"
    status = "0"
    for name, value in trailers:
        if name == "grpc-status":
            status = value
    if status != "0":
        return 1, "", "Could not save account"
    kind = account_error_kind(payload)
    if kind == "invalid":
        return 1, "", "Invalid recovery phrase"
    if kind == "error":
        return 1, "", "Could not save account"
    return 0, "", ""
