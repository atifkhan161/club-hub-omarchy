# Implementation Plan: In-Panel Article Reader (no scraping)

## 1. Objective & Scope
- **Goal:** Clicking a news article in the Club Hub panel opens the article inside
  the same panel window (dedicated reader view) instead of launching a browser.
- **Key recon finding:** the Managing Madrid Atom feed already embeds the **full
  article HTML** in `<content>` (~9–12 KB per article). **No scraping.** The reader
  works entirely from data we already fetch; only the helper's parsing changes.
- **In Scope:**
  - `bin/rss.py`: extract per-entry content into structured text blocks
  - `Panel.qml`: third view ("reader") with back button, title, byline, scrollable
    blocks, "Open in browser" footer row
  - `Model.js` + `Service.qml`: validate/pass through blocks; safe fallbacks
  - `i18n/en.json`: new reader strings
- **Out of Scope:**
  - Any fetching of article URLs (no scraping, no readability extraction)
  - Images in articles (remote images are a shell-crash class in plugin QML)
  - Rich markup (StyledText) — untrusted text stays PlainText
  - Changing the feed URL or feed default

## 2. Resolved Design Decisions & Edge Cases
- **Content source: feed's own `<content>`** (user decision). Articles without
  content in their feed degrade to the snippet + "Open in browser" hint.
- **Rendering: paragraphs + headings** as separate `PlainText` items — `h1–h6`
  become bold Text rows, `<li>` becomes "• " rows, `<p>`/`<br>` break paragraphs;
  `script`/`style`/`img` and their text are dropped; entities unescaped.
- **Browser escape hatch: footer row** in the reader, guarded by `Model.linkOk()`
  (unchanged safety rule) → `xdg-open` via `execDetached`.
- **Block caps (size & count):** per-block text ≤ 2000 chars, ≤ 250 blocks per
  article; truncated articles get a visible "open in browser for more" hint.
- **Cache compatibility:** old `rss-cache.json` items have no `blocks` — treated as
  the no-content fallback; next successful refresh overwrites with blocks.
- **Stale index safety:** the reader stores an index; a mid-read RSS refresh that
  shrinks the list bounds-checks and falls back to the hub view.
- **Panel close resets** `view` to "hub" (existing behavior, extended to reader).

## 3. Execution Tasks (Vertical Slices)

- [ ] **Task 1: `bin/rss.py` — emit structured text blocks**
  - **Files:** `bin/rss.py`
  - **Details:** Add a stdlib `html.parser.HTMLParser` subclass that walks
    `<content>` (Atom) / `<description>` (RSS) and outputs
    `blocks: [{ "t": "h" | "p" | "li", "text": str }]`. Headings via h1–h6 tags,
    list items via `<li>`, paragraph breaks via `<p>`/`<br>`/block tags; skip
    `script`, `style`, `img`, `svg` subtrees entirely; `html.unescape` text nodes;
    collapse whitespace. Enforce caps (2000 chars/block, 250 blocks). Keep
    `title/link/author/published` and the old `snippet` field (backward compat).
  - **Acceptance:** `python3 bin/rss.py https://www.managingmadrid.com/rss/index.xml`
    prints items whose first blocks match the article title theme; no item without
    title/link; exit 0; malformed feeds still fail with one JSON error line.

- [ ] **Task 2: `Service.qml` + `Model.js` — validation pass-through**
  - **Files:** `Service.qml`, `Model.js`
  - **Details:** `Model.articleBlocks(item)` returns `item.blocks` only when it is
    an array of `{t, text}` objects with string `text`, else `[]` (pure helper,
    capped). `applyRss` accepts items with or without blocks (no error). Cache
    save/load unchanged.
  - **Acceptance:** old cache still loads; helper unit-style check in a throwaway
    offscreen harness or code review (no automated suites per project norms).

- [ ] **Task 3: `Panel.qml` — reader view**
  - **Files:** `Panel.qml`
  - **Details:**
    - `view: "hub" | "settings" | "reader"`, plus `property int readerIndex: -1`.
      Article row `onClicked` → `openReader(index)`; back button and `close()` →
      hub.
    - Reader column: title (word-wrapped), author · age byline, separator, a
      `Flickable` whose `ColumnLayout` maps `Model.articleBlocks(item)`:
      `h` → bold `heading`-size Text, `p` → body Text, `li` → body Text prefixed
      "• "; all `PlainText`, `wrapMode: Text.WordWrap`, `Layout.fillWidth: true`.
    - Empty-blocks fallback: snippet text + `rss.openConfig`-style hint.
    - Truncation hint when block cap was hit.
    - Footer row ("Open in browser", globe glyph): `execDetached(["xdg-open",
      link])` only when `Model.linkOk(link)`; mirrors the settings' open-config row
      styling.
    - No new keyboard focus mode (no text input in reader).
  - **Acceptance:** qmlformat parses; panel opens/closes clean in `journalctl`;
    clicking an article shows the article; hub/settings unaffected.

- [ ] **Task 4: `i18n/en.json` — reader strings**
  - **Details:** `reader.back`, `reader.openBrowser`, `reader.noContent`,
    `reader.noContentHint`, `reader.truncated`.
  - **Acceptance:** valid JSON; no missing-key fallbacks triggered at runtime.

- [ ] **Task 5: Install, verify, commit**
  - **Files:** installed clone `~/.config/omarchy/plugins/atifkhan161.club-hub/`
  - **Details:** commit first (installs clone the committed tree), restart shell
    (service + panel changed), run all gates.
  - **Acceptance:** see Verification below.

## 4. Verification & Rollback Plan
- **Automated/cheap gates:**
  - `python3 bin/rss.py <feed-url>` — inspect real blocks for 2–3 articles
  - `omarchy plugin validate .`
  - `qmlformat` on every touched QML file (only working parse gate here)
  - `journalctl --user | grep club-hub` — no WARN qml lines after restart
- **Manual check:**
  1. `omarchy restart shell`, summon panel
  2. Screenshot hub (unchanged layout), click a news article row
  3. Screenshot reader: title, byline, scrolling paragraphs/headings, footer row
  4. Footer row opens the article in the default browser
  5. Back button returns to hub; panel close returns to hub on reopen
  6. User confirms click behavior on their side (I cannot inject clicks)
- **Rollback:** single `git revert` of the feature commit; the installed clone is
  refreshed by re-copying files. Old rss cache remains valid either way.
