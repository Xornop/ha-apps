#!/usr/bin/env python3
"""Small IPv4 mDNS A-record responder for configured .local aliases.

Safeguards to coexist with Home Assistant's built-in mDNS (Avahi / zeroconf):
- binds to the mDNS multicast address only, so it never receives (and never
  steals) unicast packets meant for other mDNS services on port 5353;
- joins the multicast group on the detected LAN interface only;
- ignores DNS responses (QR=1) and non-standard DNS opcodes;
- answers legacy unicast queries (source port != 5353) the RFC 6762 way;
- answers AAAA queries for its aliases with an NSEC (no IPv6) so clients
  don't wait for a timeout;
- disables multicast loopback for packets sent by this socket;
- logs packet-level details only at debug level.
"""
import json
import logging
import socket
import struct
import sys
import time

OPTIONS_FILE = "/data/options.json"
MDNS_GROUP = "224.0.0.251"
MDNS_PORT = 5353
RECORD_TTL = 120
LEGACY_TTL = 10
ADDRESS_REFRESH_SECONDS = 60

TYPE_A = 1
TYPE_AAAA = 28
TYPE_NSEC = 47
TYPE_ANY = 255

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
        socket.inet_aton(address)
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


def a_record(name, address, ttl, cache_flush):
    rclass = 0x8001 if cache_flush else 0x0001
    return (
        encode_name(name)
        + struct.pack("!HHIH", TYPE_A, rclass, ttl, 4)
        + socket.inet_aton(address)
    )


def nsec_record(name, ttl):
    # NSEC stating that only an A record exists for this name (no AAAA).
    rdata = encode_name(name) + bytes([0, 1, 0x40])
    return (
        encode_name(name)
        + struct.pack("!HHIH", TYPE_NSEC, 0x8001, ttl, len(rdata))
        + rdata
    )


def build_response(packet, aliases, address, client_port=MDNS_PORT):
    """Build an answer for a standard DNS query.

    Returns (response, matched_names, unicast). `unicast` is True when the
    reply must go directly to the sender (legacy unicast query or QU bit).
    """
    if len(packet) < 12:
        return None, [], False

    query_id, flags = struct.unpack_from("!HH", packet, 0)
    # QR=1 means this packet is already a response. Never answer it.
    if flags & 0x8000:
        return None, [], False
    # Ignore non-standard DNS opcodes.
    if flags & 0x7800:
        return None, [], False

    questions, question_end = parse_questions(packet)
    if not questions:
        return None, [], False

    legacy = client_port != MDNS_PORT
    qu_bit = False
    answers = []
    matched = []
    seen = set()

    for name, qtype, qclass in questions:
        if (qclass & 0x7FFF) not in (1, 255) or name not in aliases:
            continue

        if qclass & 0x8000:
            qu_bit = True

        if qtype in (TYPE_A, TYPE_ANY) and (name, TYPE_A) not in seen:
            seen.add((name, TYPE_A))
            if legacy:
                answers.append(a_record(name, address, LEGACY_TTL, False))
            else:
                answers.append(a_record(name, address, RECORD_TTL, True))
            matched.append(name)
        elif qtype == TYPE_AAAA and (name, TYPE_AAAA) not in seen:
            seen.add((name, TYPE_AAAA))
            matched.append(name)
            # Legacy clients get an empty (NODATA) reply; mDNS clients get NSEC.
            if not legacy:
                answers.append(nsec_record(name, RECORD_TTL))

    if not matched:
        return None, [], False

    if legacy:
        # RFC 6762 6.7: legacy unicast replies echo ID and question section.
        header = struct.pack(
            "!HHHHHH", query_id, 0x8400, len(questions), len(answers), 0, 0
        )
        body = packet[12:question_end] + b"".join(answers)
        return header + body, matched, True

    header = struct.pack("!HHHHHH", 0, 0x8400, 0, len(answers), 0, 0)
    return header + b"".join(answers), matched, qu_bit


def join_group(sock, address):
    membership = socket.inet_aton(MDNS_GROUP) + socket.inet_aton(address)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, membership)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(address))


def leave_group(sock, address):
    membership = socket.inet_aton(MDNS_GROUP) + socket.inet_aton(address)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_DROP_MEMBERSHIP, membership)


def open_socket(address, logger):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if hasattr(socket, "SO_REUSEPORT"):
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
        except OSError:
            pass

    try:
        # Bind to the multicast group address only: we then receive multicast
        # queries but never unicast traffic meant for Avahi / HA zeroconf.
        sock.bind((MDNS_GROUP, MDNS_PORT))
    except OSError as error:
        logger.warning("Could not bind to %s (%s); falling back to all addresses", MDNS_GROUP, error)
        sock.bind(("", MDNS_PORT))

    join_group(sock, address)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 255)
    # Prevent this socket's outgoing multicast packets from looping back locally.
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 0)
    sock.settimeout(ADDRESS_REFRESH_SECONDS)
    return sock


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

    try:
        sock = open_socket(address, logger)
    except OSError as error:
        logger.error("Could not start the mDNS listener: %s", error)
        return 1

    logger.info("Listening for mDNS queries on UDP port %s (group %s via %s)", MDNS_PORT, MDNS_GROUP, address)
    last_refresh = time.monotonic()

    try:
        while True:
            # Follow IP changes (e.g. DHCP renewal) without a restart.
            if time.monotonic() - last_refresh >= ADDRESS_REFRESH_SECONDS:
                last_refresh = time.monotonic()
                try:
                    new_address = detect_lan_ipv4()
                except Exception as error:
                    logger.debug("Address refresh failed: %s", error)
                    new_address = address
                if new_address != address:
                    try:
                        leave_group(sock, address)
                    except OSError:
                        pass
                    try:
                        join_group(sock, new_address)
                        logger.info("IPv4 address changed: %s -> %s", address, new_address)
                        address = new_address
                    except OSError as error:
                        logger.warning("Could not switch to %s: %s", new_address, error)

            try:
                packet, client = sock.recvfrom(9000)
            except socket.timeout:
                continue

            if logger.isEnabledFor(logging.DEBUG):
                try:
                    flags = struct.unpack_from("!H", packet, 2)[0] if len(packet) >= 12 else 0
                    if not flags & 0x8000:
                        seen_questions, _ = parse_questions(packet)
                        logger.debug(
                            "Query from %s:%s: %s",
                            client[0],
                            client[1],
                            ", ".join(f"{n} (type {t})" for n, t, _ in seen_questions) or "-",
                        )
                except (ValueError, struct.error):
                    pass

            try:
                response, matched, unicast = build_response(
                    packet, aliases, address, client[1]
                )
            except (ValueError, struct.error) as error:
                logger.debug("Ignoring malformed DNS packet from %s: %s", client[0], error)
                continue

            if response is None:
                continue

            try:
                destination = client if unicast else (MDNS_GROUP, MDNS_PORT)
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
