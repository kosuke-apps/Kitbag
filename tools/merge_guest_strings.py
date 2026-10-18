#!/usr/bin/env python3
"""Merge the guests' String Catalogs into one: Guests/Merged/Localizable.xcstrings.

Every guest looks its text up in the main bundle's "Localizable" table, so two guests cannot each bring a catalog of that
name into one app. This reads Guests/<name>/App/Resources/Localizable.xcstrings for each guest in tools/guests.txt (in
that order) and writes one catalog with all their keys. When two guests use the same English key for different
translations, the first guest in guests.txt keeps its translation and the clash is printed.
"""
import json
import os
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
merged = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
owner = {}
clashes = []

with open(os.path.join(root, "tools", "guests.txt"), encoding="utf-8") as f:
    names = [line.split()[0] for line in f if line.strip() and not line.lstrip().startswith("#")]

for name in names:
    path = os.path.join(root, "Guests", name, "App", "Resources", "Localizable.xcstrings")
    if not os.path.exists(path):
        continue
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
    merged["sourceLanguage"] = catalog.get("sourceLanguage", "en")
    for key, entry in catalog["strings"].items():
        if key not in merged["strings"]:
            merged["strings"][key] = entry
            owner[key] = name
        elif merged["strings"][key].get("localizations") != entry.get("localizations"):
            clashes.append((key, owner[key], name))

out = os.path.join(root, "Guests", "Merged")
os.makedirs(out, exist_ok=True)
merged["strings"] = dict(sorted(merged["strings"].items(), key=lambda kv: kv[0].lower()))
with open(os.path.join(out, "Localizable.xcstrings"), "w", encoding="utf-8") as f:
    json.dump(merged, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"merged strings: {len(merged['strings'])} keys from {len(names)} guest(s)")
for key, first, second in clashes:
    print(f'warning: "{key}" differs between {first} and {second}; {first} wins', file=sys.stderr)
