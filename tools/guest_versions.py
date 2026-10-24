#!/usr/bin/env python3
"""Write Guests/GuestVersions.json: the version and build of each guest in tools/guests.txt, from the guest's own project file.

The apps inside Kitbag read their version from the main bundle, which is Kitbag's, so Kitbag shows them their own
(App/Support/GuestShims.swift). tools/sync_guests.sh runs this after it has unpacked the guests.
"""
import json
import os
import re

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
guests = {}
with open(os.path.join(root, "tools", "guests.txt")) as listing:
    for line in listing:
        fields = line.split()
        if len(fields) < 3 or fields[0].startswith("#"):
            continue
        name = fields[0]
        with open(os.path.join(root, "Guests", name, "project.yml")) as project:
            text = project.read()
        version = re.search(r'MARKETING_VERSION:\s*"?([^"\s]+)', text)
        build = re.search(r'CURRENT_PROJECT_VERSION:\s*"?([^"\s]+)', text)
        if not version or not build:
            raise SystemExit(f"error: {name}: no MARKETING_VERSION or CURRENT_PROJECT_VERSION in its project.yml")
        guests[name] = {"version": version.group(1), "build": build.group(1)}

with open(os.path.join(root, "Guests", "GuestVersions.json"), "w") as out:
    json.dump(guests, out, indent=2, sort_keys=True)
    out.write("\n")
print("guest versions: " + ", ".join(f"{n} {g['version']} ({g['build']})" for n, g in guests.items()))
