#!/usr/bin/env python3
"""Adds a fresh build to source.json — the list SideStore reads to install and update the app.

usage: update_source.py VERSION BUILD IPA OWNER/REPO "what changed"
"""
import datetime
import json
import os
import sys

version, build, ipa, repo = sys.argv[1:5]
notes = sys.argv[5] if len(sys.argv) > 5 else ""

with open("source.json", encoding="utf-8") as f:
    source = json.load(f)

app = source["apps"][0]
url = f"https://github.com/{repo}/releases/download/v{version}/GymTracker.ipa"
date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
size = os.path.getsize(ipa)

entry = {
    "version": version,
    "buildVersion": build,
    "date": date,
    "localizedDescription": notes,
    "downloadURL": url,
    "size": size,
    "minOSVersion": "17.0",
}
older = [v for v in app.get("versions", []) if v.get("version") != version]
app["versions"] = [entry] + older[:9]

# older SideStore versions read the newest build from these fields
app["version"] = version
app["versionDate"] = date
app["versionDescription"] = notes
app["downloadURL"] = url
app["size"] = size

with open("source.json", "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
    f.write("\n")

print(f"source.json → {version} ({size} bytes)")
