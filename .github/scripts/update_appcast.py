#!/usr/bin/env python3
"""Prepend a new Sparkle <item> into appcast.xml before </channel>."""
import os
import datetime


def md_to_html(text, version):
    """Convert simple markdown bullet lists to styled HTML for Sparkle."""
    css = (
        "body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;"
        "font-size:13px;line-height:1.5;margin:16px;"
        "color:#1d1d1f;background:transparent;}"
        "h3{font-size:14px;font-weight:600;margin:0 0 10px;}"
        "ul{margin:0;padding-left:18px;}"
        "li{margin-bottom:4px;}"
        "p{margin:0 0 8px;}"
    )
    lines = text.strip().splitlines()
    parts = [f"<h3>What&#8217;s New in {version}</h3>"]
    in_list = False

    for line in lines:
        line = line.rstrip()
        if line.startswith("## "):
            if in_list:
                parts.append("</ul>")
                in_list = False
            parts.append(f"<h3>{line[3:].strip()}</h3>")
        elif line.startswith(("- ", "* ")):
            if not in_list:
                parts.append("<ul>")
                in_list = True
            parts.append(f"<li>{line[2:].strip()}</li>")
        elif line == "":
            if in_list:
                parts.append("</ul>")
                in_list = False
        else:
            if in_list:
                parts.append("</ul>")
                in_list = False
            if line:
                parts.append(f"<p>{line}</p>")

    if in_list:
        parts.append("</ul>")

    body = "\n".join(parts)
    return f"<html><head><style>{css}</style></head><body>{body}</body></html>"


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

notes_file = os.environ.get("RELEASE_NOTES_FILE", "")
if notes_file and os.path.exists(notes_file):
    with open(notes_file, "r") as f:
        release_notes_html = md_to_html(f.read(), version)
    notes_xml = f"      <description><![CDATA[{release_notes_html}]]></description>\n"
else:
    notes_xml = (
        f"      <sparkle:releaseNotesLink>"
        f"https://github.com/{repo}/releases/tag/{tag}"
        f"</sparkle:releaseNotesLink>\n"
    )

new_item = (
    f"    <item>\n"
    f"      <title>Version {version}</title>\n"
    f"      <pubDate>{pub_date}</pubDate>\n"
    f"      <sparkle:version>{build}</sparkle:version>\n"
    f"      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>\n"
    f"{notes_xml}"
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
