#!/usr/bin/env python3
"""Fetch and parse a club news feed (RSS 2.0 or Atom) into JSON.

Prints one JSON array to stdout:
  [{"title", "link", "author", "published", "snippet",
    "blocks": [{"t": "h"|"p"|"li", "text"}], "truncated"}]
newest first, or {"error": "..."} on stderr with a non-zero exit.

`blocks` comes from the feed's own full-content element (Atom <content>, RSS
<description>/<summary>), flattened to plain text: no tags, attributes, URLs,
images, or scripts. It is a display convenience, not a trust boundary — the
QML side still renders every string as PlainText.

No third-party dependencies; only the standard library. The URL comes from
the plugin's own config, and everything parsed out of the feed is treated as
untrusted data: the QML side renders every string as PlainText.
"""

import email.utils
import html
import json
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from html.parser import HTMLParser

MAX_BYTES = 1_000_000
TIMEOUT = 10
SNIPPET_LEN = 220
MAX_BLOCKS = 250
MAX_BLOCK_CHARS = 2000
UA = "OmarchyPlugin/1.0 (Linux; Wayland)"


def fail(message: str) -> None:
    print(json.dumps({"error": message}), file=sys.stderr)
    raise SystemExit(1)


def local_name(tag: str) -> str:
    """Namespace-agnostic tag name: '{http://...}creator' -> 'creator'."""
    return tag.rsplit("}", 1)[-1].lower()


def find_child(element, *names):
    for child in element:
        if local_name(child.tag) in names:
            return child
    return None


def child_text(element, *names) -> str:
    child = find_child(element, *names)
    if child is None:
        return ""
    return (child.text or "").strip()


def entry_link(element) -> str:
    # Atom: <link rel="alternate" href="...">; fall back to the first link.
    for child in element:
        if local_name(child.tag) != "link":
            continue
        href = (child.get("href") or "").strip()
        rel = (child.get("rel") or "alternate").strip()
        if href and rel == "alternate":
            return href
        if href and not child.get("rel"):
            return href
    # RSS 2.0: <link>text</link>
    return child_text(element, "link")


def entry_author(element) -> str:
    # dc:creator, RSS author, or Atom <author><name>.
    text = child_text(element, "creator", "author", "publishedby")
    if text:
        return text
    author = find_child(element, "author")
    if author is not None:
        return child_text(author, "name") or (author.text or "").strip()
    return ""


def entry_published(element):
    raw = child_text(element, "pubdate", "published", "updated", "date")
    if not raw:
        return None
    for parse in (email.utils.parsedate_to_datetime, _parse_iso):
        try:
            parsed = parse(raw)
        except (TypeError, ValueError):
            continue
        if parsed is None:
            continue
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    return None


def _parse_iso(raw: str):
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def clean_snippet(element) -> str:
    raw = child_text(element, "description", "summary", "content")
    if not raw:
        return ""
    text = html.unescape(re.sub(r"<[^>]*>", " ", raw))
    text = re.sub(r"\s+", " ", text).strip()
    return text[:SNIPPET_LEN].rsplit(" ", 1)[0] if len(text) > SNIPPET_LEN else text


HEADING_TAGS = {"h1", "h2", "h3", "h4", "h5", "h6"}
# Block-level tags that end the current paragraph/list item.
BLOCK_TAGS = {
    "address", "article", "aside", "blockquote", "dd", "div", "dl", "dt",
    "fieldset", "figcaption", "footer", "form", "h1", "h2", "h3", "h4", "h5",
    "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section",
    "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul",
}
# Subtrees dropped entirely, including their text: media, embeds, and the
# chrome some feeds wrap around the article body.
SKIP_TAGS = {
    "script", "style", "img", "svg", "noscript", "iframe", "figure",
    "figcaption", "video", "audio", "canvas", "object", "embed", "template",
}


class BlockExtractor(HTMLParser):
    """Flatten article HTML into heading/paragraph/list-item text blocks.

    The feed's <content> is untrusted markup, so nothing here keeps tags,
    attributes, or URLs: only text, split on the tags that carry structure.
    Caps keep one hostile or enormous article from filling the panel.
    """

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.blocks = []
        self.truncated = False
        self._parts = []
        self._kind = "p"
        self._skip = 0

    @staticmethod
    def _tag(tag: str) -> str:
        return tag.lower().rsplit(":", 1)[-1]

    def _flush(self) -> None:
        raw = "".join(self._parts)
        self._parts = []
        # collapse runs of whitespace, then unescape any entity that survived
        # the XML/HTML decoding (some feeds double-escape their content).
        text = html.unescape(re.sub(r"\s+", " ", raw)).strip()
        if not text:
            return
        if len(self.blocks) >= MAX_BLOCKS:
            self.truncated = True
            return
        if len(text) > MAX_BLOCK_CHARS:
            text = text[:MAX_BLOCK_CHARS].rstrip()
            self.truncated = True
        self.blocks.append({"t": self._kind, "text": text})

    def handle_starttag(self, tag, attrs):
        tag = self._tag(tag)
        if tag in SKIP_TAGS:
            self._skip += 1
            return
        if self._skip:
            return
        if tag in HEADING_TAGS:
            self._flush()
            self._kind = "h"
        elif tag == "li":
            self._flush()
            self._kind = "li"
        elif tag in BLOCK_TAGS or tag == "br":
            self._flush()
            self._kind = "p"

    def handle_endtag(self, tag):
        tag = self._tag(tag)
        if tag in SKIP_TAGS:
            if self._skip > 0:
                self._skip -= 1
            return
        if self._skip:
            return
        if tag in HEADING_TAGS or tag == "li" or tag in BLOCK_TAGS:
            self._flush()
            self._kind = "p"

    def handle_data(self, data):
        if self._skip:
            return
        if not self._parts and not data.strip():
            return
        self._parts.append(data)

    def finish(self):
        self.close()
        self._flush()
        return self.blocks, self.truncated


def entry_content_html(element) -> str:
    """The entry's full body: Atom <content>, else RSS <description>.

    Returns the inner HTML as text. For XHTML content (child elements instead
    of escaped markup) the children are serialized; the wrapper tag is dropped.
    """
    for name in ("content", "encoded", "description", "summary"):
        child = find_child(element, name)
        if child is None:
            continue
        if len(child) > 0:
            parts = [child.text or ""]
            parts.extend(ET.tostring(sub, encoding="unicode") for sub in child)
            return "".join(parts)
        if child.text and child.text.strip():
            return child.text
    return ""


def extract_blocks(content_html: str):
    parser = BlockExtractor()
    parser.feed(content_html)
    return parser.finish()


def collect_entries(root_element):
    """RSS 2.0 nests items under <channel>; Atom lists entries at the top."""
    entries = []
    for element in root_element.iter():
        if local_name(element.tag) in ("item", "entry"):
            entries.append(element)
    return entries


def parse(feed_xml: bytes):
    root = ET.fromstring(feed_xml)
    items = []
    for element in collect_entries(root):
        title = child_text(element, "title")
        link = entry_link(element)
        if not title or not link:
            continue
        published = entry_published(element)
        blocks, truncated = extract_blocks(entry_content_html(element))
        items.append({
            "title": title,
            "link": link,
            "author": entry_author(element),
            "published": published.isoformat() if published else "",
            "snippet": clean_snippet(element),
            "blocks": blocks,
            "truncated": truncated,
        })
    items.sort(key=lambda item: item["published"], reverse=True)
    return items


def fetch(url: str) -> bytes:
    scheme = url.split(":", 1)[0].lower()
    if scheme not in ("https", "http"):
        fail("unsupported URL scheme: " + scheme)
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read(MAX_BYTES + 1)[:MAX_BYTES]


def main() -> None:
    if len(sys.argv) != 2:
        fail("usage: rss.py <feed-url>")
    try:
        items = parse(fetch(sys.argv[1]))
    except Exception as error:  # noqa: BLE001 - one JSON error line, whatever happened
        fail(f"{type(error).__name__}: {error}")
    json.dump(items, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
