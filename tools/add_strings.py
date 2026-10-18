#!/usr/bin/env python3
"""Add or update strings in one of Kitbag's String Catalogs (English source, Japanese translation).

  tools/add_strings.py Calendar <<'JSON'
  { "Done": ["完了", null], "Due %@": ["期限: %@", "Body of a reminder; %@ is a date."] }
  JSON

Each key is the English text (what `Text("…", tableName: "Calendar")` uses); the value is [Japanese, comment or null].
The catalog is App/Resources/<table>.xcstrings; it is created when it does not exist. Keys are written in sorted order.
"""
import json
import os
import sys

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "App", "Resources")
table = sys.argv[1]
path = os.path.join(root, f"{table}.xcstrings")
new = json.load(sys.stdin)

if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        catalog = json.load(f)
else:
    catalog = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}

for key, (ja, comment) in new.items():
    item = {}
    if comment:
        item["comment"] = comment
    item["localizations"] = {"ja": {"stringUnit": {"state": "translated", "value": ja}}}
    catalog["strings"][key] = item

catalog["strings"] = dict(sorted(catalog["strings"].items(), key=lambda kv: kv[0].lower()))
with open(path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"{table}: {len(catalog['strings'])} strings")
