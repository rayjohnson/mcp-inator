#!/usr/bin/env python3
"""Prepend a new Sparkle <item> into appcast.xml before </channel>."""
import os
import datetime

version = os.environ["VERSION"]
tag = os.environ["TAG"]
build = os.environ["BUILD"]
ed_sig = os.environ["ED_SIG"]
length = os.environ["LENGTH"]
download_url = os.environ["DOWNLOAD_URL"]
repo = os.environ["REPO"]

pub_date = datetime.datetime.now(
    datetime.timezone.utc
).strftime("%a, %d %b %Y %H:%M:%S +0000")

new_item = (
    f"    <item>\n"
    f"      <title>Version {version}</title>\n"
    f"      <pubDate>{pub_date}</pubDate>\n"
    f"      <sparkle:version>{build}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    f"      <sparkle:releaseNotesLink>"
    f"https://github.com/{repo}/releases/tag/{tag}"
    f"</sparkle:releaseNotesLink>\n"
    f"      <enclosure\n"
    f'        url="{download_url}"\n'
    f'        sparkle:edSignature="{ed_sig}"\n'
    f'        length="{length}"\n'
    f'        type="application/octet-stream" />\n'
    f"    </item>"
)

with open("appcast.xml", "r") as f:
    content = f.read()

updated = content.replace("  </channel>", new_item + "\n  </channel>", 1)

with open("appcast.xml", "w") as f:
    f.write(updated)

print(f"Inserted item for version {version} (build {build})")
