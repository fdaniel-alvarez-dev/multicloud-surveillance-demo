#!/usr/bin/env python3
"""Simple DNS verification for Arlo multi-cloud endpoint."""
from __future__ import annotations

import argparse
import socket
import sys


def resolve(host: str) -> list[str]:
    try:
        results = socket.getaddrinfo(host, None)
    except socket.gaierror as exc:  # pragma: no cover
        raise SystemExit(f"Failed to resolve {host}: {exc}")
    ips: set[str] = set()
    for family, _type, _proto, _canon, sockaddr in results:
        if family in (socket.AF_INET, socket.AF_INET6):
            ips.add(sockaddr[0])
    return sorted(ips)


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate DNS warm-standby configuration")
    parser.add_argument("hostname", help="DNS name to verify", nargs="?", default="api.arlo-resilience.com")
    args = parser.parse_args()

    addresses = resolve(args.hostname)
    if not addresses:
        raise SystemExit(f"No DNS records found for {args.hostname}")

    print(f"{args.hostname} resolves to: {', '.join(addresses)}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
