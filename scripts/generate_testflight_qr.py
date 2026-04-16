#!/usr/bin/env python3
"""Generate a TestFlight share QR image from a public link."""

from __future__ import annotations

import argparse
import pathlib
import sys
import urllib.parse
import urllib.request


def build_qr_url(link: str, size: int) -> str:
    encoded = urllib.parse.quote(link, safe="")
    return f"https://api.qrserver.com/v1/create-qr-code/?size={size}x{size}&data={encoded}"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate a PNG QR code for a TestFlight public link."
    )
    parser.add_argument(
        "link",
        help="TestFlight public invite link, e.g. https://testflight.apple.com/join/XXXXXXX",
    )
    parser.add_argument(
        "--size",
        type=int,
        default=600,
        help="QR image size in pixels (default: 600).",
    )
    parser.add_argument(
        "--output",
        default="output/testflight-public-link-qr.png",
        help="Output PNG path (default: output/testflight-public-link-qr.png).",
    )
    args = parser.parse_args()

    if not args.link.startswith("https://testflight.apple.com/join/"):
        print("Error: link must start with https://testflight.apple.com/join/", file=sys.stderr)
        return 1

    output_path = pathlib.Path(args.output).expanduser().resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    qr_url = build_qr_url(args.link, args.size)
    with urllib.request.urlopen(qr_url, timeout=20) as response:
        png_data = response.read()
    output_path.write_bytes(png_data)

    print(f"QR generated: {output_path}")
    print(f"Share link: {args.link}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
