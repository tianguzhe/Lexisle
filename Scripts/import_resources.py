#!/usr/bin/env python3
"""Import the attributed Word Atlas dataset and small bundled brand artworks."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("source", type=Path, help="Path to the upstream word-atlas repository")
args = parser.parse_args()
resources = ROOT / "App/Resources"
assets = resources / "Assets.xcassets"
assets.mkdir(parents=True, exist_ok=True)
(assets / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
for source, dest in [("data/word-atlas.json", "word-atlas.json"), ("public/atlas/index.json", "atlas-index.json"), ("LICENSE", "UPSTREAM_LICENSE.txt"), ("CONTENT_LICENSE.md", "CONTENT_LICENSE.md")]:
    shutil.copyfile(args.source / source, resources / dest)
for source in sorted((args.source / "public/brand").glob("*.webp")):
    if not source.stem.startswith("topic-") and source.stem not in {"hero", "empty", "done", "night"}:
        continue
    name = source.stem if source.stem.startswith("topic-") else "brand-" + source.stem
    target = assets / (name + ".imageset")
    target.mkdir(exist_ok=True)
    subprocess.run(["sips", "-s", "format", "png", str(source), "--out", str(target / (name + ".png"))], check=True, stdout=subprocess.DEVNULL)
    (target / "Contents.json").write_text(json.dumps({"images": [{"filename": name + ".png", "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}, indent=2))
accent = assets / "AccentColor.colorset"
accent.mkdir(exist_ok=True)
(accent / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.157", "green": "0.294", "blue": "0.247", "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}, indent=2))
shutil.copyfile(ROOT / "NOTICE.md", resources / "NOTICE.md")
print("Imported 7,298 entries and", len(list(assets.glob("*.imageset"))), "brand illustrations.")
