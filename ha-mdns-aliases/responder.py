#!/usr/bin/env python3
"""Small IPv4 mDNS A-record responder for configured .local aliases.

Important safeguards:
- ignores DNS responses (QR=1) and non-standard DNS opcodes;
- does not echo the question section in responses;
- disables multicast loopback for packets sent by this socket;
- does not use SO_REUSEPORT;
- logs packet-level details only at debug level.
"""
import json
import logging
import socket
import struct
import sys

OPTIONS_FILE = "/data/options.json"
MDNS_GROUP = "224.0.0.251"
MDNS_PORT = 5353
RECORD_TTL = 120

VALID_LOG_LEVELS = {
    "debug": logging.DEBUG,
    "info": logging.INFO,
    "warning": logging.WARNING,
    "error": logging.ERROR,
    "silent": logging.CRITICAL + 1,
}


def configure_logging(level_name):
    level = VALID_LOG_LEVELS.get(str(level_name).lower(), logging.INFO)
    logging.basicConfig(
        level=level,
        format="%(levelname)s: %(message)s",
        stream=sys.stdout,
        force=True,
    )
    return logging.getLogger("ha_mdns_aliases")


def load_options():
    with open(OPTIONS_FILE, "r", encoding="utf-8") as file:
        options = json.load(file)

    hostnames = []
    for raw_name in str(options.get("hostnames", "")).split(","):
        name = raw_name.strip().lower()
        if name.endswith(".local"):
            name = name[:-6]
        name = name.rstrip(".")
        if not name:
            continue

        labels = name.split(".")
        valid = all(
            label
            and len(label) <= 63
            and all(c.isalnum() or c == "-" for c in label)
            and not label.startswith("-")
            and not label.endswith("-")
            for label in labels
        )
        if valid and name not in hostnames:
            hostnames.append(name)

    log_level = str(options.get("log_level", "info")).lower()
    if log_level not in VALID_LOG_LEVELS:
        log_level = "info"

    return hostnames, log_level


def detect_lan_ipv4():
    """Return the IPv4 address selected by the system's default route."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        sock.connect(("192.0.2.1", 9))
        address = sock.getsockname()[0]
        ip = socket.inet_aton(address)
        if address.startswith("127.") or address.startswith("169.254."):
            raise RuntimeError(f"Detected a non-LAN IPv4 address: {address}")
        return address
    finally:
        sock.close()


def decode_name(packet, offset):
    labels = []
    original_offset = offset
    jumped = False
    jumps = 0

    while True:
        if offset >= len(packet):
            raise ValueError("DNS name exceeds packet length")

        length = packet[offset]
        if length == 0:
            offset += 1
            break

        if length & 0xC0 == 0xC0:
            if offset + 1 >= len(packet):
                raise ValueError("Incomplete DNS compression pointer")
            pointer = ((length & 0x3F) << 8) | packet[offset + 1]
            if pointer >= len(packet):
                raise ValueError("DNS compression pointer is out of range")
            if not jumped:
                original_offset = offset + 2
                jumped = True
            offset = pointer
            jumps += 1
            if jumps > 20:
                raise ValueError("Too many DNS compression pointers")
            continue

        if length & 0xC0:
            raise ValueError("Invalid DNS label length")

        offset += 1
        if offset + length > len(packet):
            raise ValueError("DNS label exceeds packet length")
        labels.append(packet[offset:offset + length].decode("utf-8", errors="ignore"))
        offset += length

    return ".".join(labels), (original_offset if jumped else offset)


def encode_name(name):
    encoded = bytearray()
    for label in name.rstrip(".").split("."):
        raw = label.encode("utf-8")
        if not raw or len(raw) > 63:
            raise ValueError(f"Invalid DNS label: {label!r}")
        encoded.append(len(raw))
        encoded.extend(raw)
    encoded.append(0)
    return bytes(encoded)


def parse_questions(packet):
    if len(packet) < 12:
        raise ValueError("DNS packet is shorter than the header")

    question_count = struct.unpack_from("!H", packet, 4)[0]
    offset = 12
    questions = []

    for _ in range(question_count):
        name, offset = decode_name(packet, offset)
        if offset + 4 > len(packet):
            raise ValueError("Incomplete DNS question")
        qtype, qclass = struct.unpack_from("!HH", packet, offset)
        offset += 4
        questions.append((name.lower().rstrip("."), qtype, qclass))

    return questions, offset


def build_response(packet, aliases, address):
    """Build an answer only for an actual standard DNS query."""
    if len(packet) < 12:
        return None, []

    flags = struct.unpack_from("!H", packet, 2)[0]
    # QR=1 means this packet is already a response. Never answer it.
    if flags & 0x8000:
        return None, []
    # Ignore non-standard DNS opcodes.
    if flags & 0x7800:
        return None, []

    questions, _ = parse_questions(packet)
    if not questions:
        return None, []

    answers = []
    matched = []

    for name, qtype, qclass in questions:
        # Only IN-class IPv4 address (A) queries for configured aliases.
        if qtype != 1 or (qclass & 0x7FFF) != 1 or name not in aliases:
            continue

        answer = (
            encode_name(name)
            + struct.pack("!HHIH", 1, 0x8001, RECORD_TTL, 4)
            + socket.inet_aton(address)
        )
        answers.append(answer)
        matched.append(name)

    if not answers:
        return None, []

    # A multicast DNS response does not need to echo the question section.
    header = struct.pack("!HHHHHH", 0, 0x8400, 0, len(answers), 0, 0)
    return header + b"".join(answers), matched


def main():
    hostnames, log_level = load_options()
    logger = configure_logging(log_level)

    if not hostnames:
        logger.error("No valid hostnames configured.")
        return 1

    aliases = {f"{name}.local" for name in hostnames}

    try:
        address = detect_lan_ipv4()
    except Exception as error:
        logger.error("Could not determine the IPv4 address: %s", error)
        return 1

    logger.info("Configured aliases: %s", ", ".join(sorted(aliases)))
    logger.info("Detected response IPv4 address: %s", address)
    logger.debug("Logging level: %s", log_level)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    try:
        # SO_REUSEADDR is used for multicast socket sharing on Linux.
        # SO_REUSEPORT is deliberately not enabled.
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(("", MDNS_PORT))

        membership = socket.inet_aton(MDNS_GROUP) + socket.inet_aton("0.0.0.0")
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
        # Prevent this socket's outgoing multicast packets from looping back locally.
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 0)
        # Prefer the interface/address selected by the default route.
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(address))
    except OSError as error:
        logger.error("Could not start the mDNS listener: %s", error)
        sock.close()
        return 1

    logger.info("Listening for mDNS queries on UDP port %s", MDNS_PORT)

    try:
        while True:
            packet, client = sock.recvfrom(9000)
            try:
                response, matched = build_response(packet, aliases, address)
            except (ValueError, struct.error) as error:
                logger.debug("Ignoring malformed DNS packet from %s: %s", client[0], error)
                continue

            if response is None:
                continue

            try:
                # QU bit asks for a unicast reply; otherwise use mDNS multicast.
                questions, _ = parse_questions(packet)
                unicast_requested = any(qclass & 0x8000 for _, _, qclass in questions)
                destination = client if unicast_requested else (MDNS_GROUP, MDNS_PORT)
                sock.sendto(response, destination)
                logger.debug(
                    "Answered %s from %s -> %s",
                    ", ".join(sorted(set(matched))),
                    client[0],
                    address,
                )
            except OSError as error:
                logger.warning("Could not send mDNS response: %s", error)
    except KeyboardInterrupt:
        logger.info("Stopping HA mDNS Aliases.")
    finally:
        sock.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
