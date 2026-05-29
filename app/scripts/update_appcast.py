#!/usr/bin/env python3
"""Prepend (or replace) a release <item> in a Sparkle appcast.xml.

Keeps existing items so release history is preserved across CI runs that only
have the newest archive on hand. Idempotent: re-running for the same
sparkle:version replaces that item instead of duplicating it.
"""
import argparse
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def sp(tag: str) -> str:
    return f"{{{SPARKLE}}}{tag}"


def load_or_create(path: str) -> ET.ElementTree:
    try:
        tree = ET.parse(path)
        if tree.getroot().tag == "rss":
            return tree
    except (FileNotFoundError, ET.ParseError):
        pass
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "KorpProxy"
    ET.SubElement(channel, "description").text = "KorpProxy app updates"
    return ET.ElementTree(rss)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--appcast", required=True)
    ap.add_argument("--version", required=True, help="short version, e.g. 0.2.0")
    ap.add_argument("--build", required=True, help="CFBundleVersion integer")
    ap.add_argument("--url", required=True)
    ap.add_argument("--length", required=True)
    ap.add_argument("--ed-signature", required=True)
    ap.add_argument("--min-system", default="14.0")
    ap.add_argument("--title", default=None)
    ap.add_argument("--release-notes-url", default=None)
    args = ap.parse_args()

    tree = load_or_create(args.appcast)
    channel = tree.getroot().find("channel")
    if channel is None:
        channel = ET.SubElement(tree.getroot(), "channel")

    # Drop any existing item with the same build (idempotency).
    for item in list(channel.findall("item")):
        v = item.find(sp("version"))
        if v is not None and v.text == str(args.build):
            channel.remove(item)

    item = ET.Element("item")
    ET.SubElement(item, "title").text = args.title or f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = formatdate(usegmt=True)
    ET.SubElement(item, sp("version")).text = str(args.build)
    ET.SubElement(item, sp("shortVersionString")).text = args.version
    ET.SubElement(item, sp("minimumSystemVersion")).text = args.min_system
    if args.release_notes_url:
        ET.SubElement(item, sp("releaseNotesLink")).text = args.release_notes_url
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": str(args.length),
        "type": "application/octet-stream",
        sp("edSignature"): args.ed_signature,
    })

    # Newest first.
    channel.insert(list(channel).index(channel.findall("item")[0]) if channel.findall("item") else len(list(channel)), item)

    ET.indent(tree, space="  ")
    tree.write(args.appcast, encoding="utf-8", xml_declaration=True)
    print(f"appcast updated: {args.appcast} (+ version {args.version} build {args.build})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
