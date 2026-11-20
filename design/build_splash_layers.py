#!/usr/bin/env python3
"""Split assets/icons/appicon.svg into the layers the GUI splash animates.

Every layer keeps the 1024x1024 artwork coordinate space, so stacking them
reproduces the icon without its background tile or paper grain.
"""

from __future__ import annotations

import copy
import re
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/icons/appicon.svg"
OUT = ROOT / "zero-beat-gui/app/assets/splash"

SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)

LAYERS = {
    "halo": {"halo-1"},
    "note_left": {"left-music-notes-2"},
    "note_right": {"right-music-note-1"},
    "eyes": {"left-eye-7", "right-eye-8"},
}
MOVING = set().union(*LAYERS.values())


def tag(name: str) -> str:
    return f"{{{SVG}}}{name}"


def prune(node: ET.Element, keep) -> bool:
    """Drop shapes rejected by keep; returns whether anything is left."""
    for child in list(node):
        if child.tag == tag("g"):
            if not prune(child, keep):
                node.remove(child)
        elif not keep(child.get("id", "")):
            node.remove(child)
    return len(node) > 0


def layer(artwork: ET.Element, defs: ET.Element, keep) -> ET.ElementTree:
    root = ET.Element(tag("svg"), {"viewBox": "0 0 1024 1024", "width": "1024", "height": "1024"})
    body = copy.deepcopy(artwork)
    body.attrib.pop("transform", None)
    prune(body, keep)
    used = set(re.findall(r"url\(#([^)]+)\)", ET.tostring(body, encoding="unicode")))
    kept = ET.SubElement(root, tag("defs"))
    for gradient in defs:
        if gradient.get("id") in used:
            kept.append(copy.deepcopy(gradient))
    root.append(body)
    ET.indent(root, space="  ")
    return ET.ElementTree(root)


def main() -> None:
    source = ET.parse(SOURCE).getroot()
    defs = source.find(tag("defs"))
    artwork = source.find(f".//{tag('g')}[@id='icon-artwork']")
    OUT.mkdir(parents=True, exist_ok=True)
    outputs = {"body": lambda id_: id_ not in MOVING}
    outputs.update({name: (lambda ids: lambda id_: id_ in ids)(ids) for name, ids in LAYERS.items()})
    for name, keep in outputs.items():
        path = OUT / f"{name}.svg"
        layer(artwork, defs, keep).write(path, encoding="utf-8", xml_declaration=True)
        print(path.relative_to(ROOT))


if __name__ == "__main__":
    main()
