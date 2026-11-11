# Implementation Plan: Omarchy Club Hub Plugin (`atifkhan161.club-hub`)

## 1. Objective & Scope
- **Goal:** A native Omarchy shell plugin (bar icon + panel popup) tracking one football
  club's next fixture and last-5 results (football-data.org) plus one club RSS feed
  (default: Managing Madrid), configured in-panel.
- **In Scope:**
  - Plugin kinds `service` + `panel` + `bar-widget` (the `omarchy.media` architecture:
    one `Service.qml` instance does all fetching; panel and bar widget read it via the
    plugin-scoped `shell.serviceFor(id)`).
  - Next-fixture card (competition, opponent, home/away, localized kickoff,
    relative countdown badge), last-5 form strip (W/D/L + scores), RSS stream
    (title, author, relative time, click opens browser).
  - In-panel settings editor (API key, team id, feed URL, refresh intervals,
    display options) writing `~/.config/omarchy/club-hub.json` via Quickshell
    `FileView`, hot-reloaded on save; plus an "open config file" row.
  - Curl-based match fetch (weather-plugin pattern) and a Python RSS helper
    (`bin/rss.py`, livewall/collectors pattern) that fetches + parses RSS 2.0/Atom
    to JSON with timeout, size cap, and a proper User-Agent.
  - Cache in `$XDG_CACHE_HOME/omarchy/club-hub/` (matches.json, rss.json) so shell
    reloads and lock/unlock cycles don't refetch within the interval.
  - `i18n/en.json` (English-only; Omarchy's fallback chain covers the rest).
  - README + `omarchy plugin validate .` as the required check.
- **Out of Scope (locked with user):**
  - Live minute tracking ("Live - 64'") — free tier doesn't return it reliably;
    a match that is `IN_PLAY` at poll time shows a static "In progress" badge.
  - Multiple clubs / multiple RSS feeds — exactly one of each (user changed their
    mind from the earlier multi-club answer; final call: single, configurable).
  - Match-start/goal notifications, standings, automated test suites
    (minimal checks only), offline fake-data demo mode.

## 2. Resolved Design Decisions & Edge Cases
- **Architecture:** Pure QML inside `omarchy-shell` — no C++ (`QNetworkAccessManager` /
  `QXmlStreamReader` from the PRD are not available to shell plugins). Network via
  Quickshell `Process` + `curl -fsS --max-time 15`, matching the weather plugin.
- **State ownership:** `Service.qml` (kind `service`) is instantiated once by the shell
  at startup and owns polling, parsing, and cached state. `Panel.qml` and
  `BarWidget.qml` look it up via the injected `shell` object (`shell.serviceFor(pluginId)`,
  `shell.toggle(pluginId)` to open the panel) — verified against `shell.qml:937`
  (`ensureService`) and `shell.qml:1414` (panels get `item.service`).
- **Config location:** `~/.config/omarchy/club-hub.json` — NOT inside the plugin folder
  (a git-installed plugin dir is the repo checkout; `omarchy plugin update` would
  clobber a config living there). Schema per PRD §4.3, minus API key rename kept as
  `football_data_api_key`; defaults: team_id 86, Managing Madrid feed,
  matches 20 min, RSS 30 min, max_rss_items 8.
- **Live match:** featured card = earliest of `SCHEDULED`/`TIMED`/`IN_PLAY`;
  `IN_PLAY` renders a static "In progress" badge with the score as of last poll,
  no countdown ticking, no minute.
- **Last 5:** `FINISHED` matches sorted desc by `utcDate`, take 5, reverse to
  chronological; result letter derived from the team's perspective (home/away aware).
- **Missing/invalid API key:** explicit error state in panel and bar tooltip with a
  clickable row that opens `https://www.football-data.org/client/register` via
  `Quickshell.execDetached(["xdg-open", url])`; matches section shows fallback text,
  RSS section keeps working (no key needed).
- **Network safety (per omarchy skill plugins.md):** fixed HTTPS sources, explicit
  timeouts, response-size caps, `textFormat: Text.PlainText` on every text element
  fed by network data (titles, bylines, snippets are untrusted markup sinks),
  stripped HTML snippets only. Polling cadence is user-configurable and disclosed
  in the README.
- **Countdown:** computed locally from `utcDate` vs current time, refreshed by a
  1-minute local timer — no extra network traffic.
- **Crests:** opponent crest from football-data.org's `crest` URL rendered via
  `qs.Ui` `SizedImage` with a text shortName fallback; downloaded images are
  cache-capped and size-limited. `display.show_crest` can turn it off.
- **Bar widget:** icon-only (glyph badge following the theme), click toggles the
  panel, `defaultSection: "right"`; hides when no club is configured/fetchable.
- **Plugin id:** `atifkhan161.club-hub` (matches the shell id regex; `omarchy.*` is
  reserved). Installed dir: `~/.config/omarchy/plugins/atifkhan161.club-hub/`.

## 3. Execution Tasks (Vertical Slices)
- [ ] **Task 1: Scaffold the plugin**
  - **Files:** `manifest.json`, `i18n/en.json`, `README.md`, `.gitignore`
  - **Details:** Manifest with `schemaVersion: 1`, `id: atifkhan161.club-hub`,
    `kinds: ["service","panel","bar-widget"]`, `entryPoints` mapping
    (`service→Service.qml`, `panel→Panel.qml`, `barWidget→BarWidget.qml`),
    `barWidget.defaultSection: "right"`. en.json with every UI string used later.
  - **Acceptance Criteria:** `omarchy plugin validate .` exits 0.
- [ ] **Task 2: Config layer**
  - **Files:** `Config.qml` (non-entry-point component), `~/.config/omarchy/club-hub.json` (created on first run with defaults)
  - **Details:** Quickshell `FileView` with `watchChanges: true` reading the XDG
    path; defaults merged for missing keys; schema validation (intervals clamped
    to ≥5 min, URLs must be https, team_id integer); invalid JSON falls back to
    defaults with a logged warning rather than breaking the shell.
  - **Acceptance Criteria:** Editing the file while the panel is open updates the
    UI without a shell restart; a malformed file does not crash the shell.
- [ ] **Task 3: RSS helper**
  - **Files:** `bin/rss.py`
  - **Details:** Stdin/stdout JSON tool: fetches a feed URL (urllib, 10s timeout,
    512KB read cap, UA `OmarchyPlugin/1.0 (Linux; Wayland)`), parses RSS 2.0 and
    Atom (`<title>`, `<link>`, `<pubDate>`/`<updated>`, `<dc:creator>`/`<author>`),
    strips HTML from descriptions, emits `[{title, link, author, publishedIso,
    snippet}]`, newest first. Errors print JSON `{"error": "..."}` on stderr-shaped
    failure, exit non-zero.
  - **Acceptance Criteria:** `python3 bin/rss.py https://www.managingmadrid.com/rss/index.xml`
    prints valid JSON with ≥3 items containing real titles, links, and authors;
    a bogus URL exits non-zero with an error object.
- [ ] **Task 4: Service (data + polling)**
  - **Files:** `Service.qml`
  - **Details:** curl `Process` for
    `GET https://api.football-data.org/v4/teams/{id}/matches?status=FINISHED,SCHEDULED,TIMED,IN_PLAY`
    with `X-Auth-Token` from config; `Process` running `python3 bin/rss.py <feed>`;
    `Timer`s at configured intervals with retry-on-failure (keep last-good data);
    cache `FileView`s in `$XDG_CACHE_HOME/omarchy/club-hub/` with last-fetched
    timestamps — a fresh instance (shell reload, lock/unlock) reads cache and only
    refetches past the interval; derived state: `nextMatch`, `lastFive`,
    `wDlStrip`, `rssItems`, `errorState` (`no-key`, `http`, `offline`, `ok`).
  - **Acceptance Criteria:** With a valid key, `omarchy-shell` logs show one fetch
    per interval (not per reload); killing the network mid-cycle keeps the panel
    populated with cached data and sets `errorState`.
- [ ] **Task 5: Panel UI**
  - **Files:** `Panel.qml` (+ small `PanelModel.js` if formatting grows)
  - **Details:** PRD §6 wireframe: header (club name, refresh, gear), NEXT MATCH
    card, RECENT FORM strip (W green / D neutral / L red per theme tokens from
    `qs.Commons`), RSS list (title, author, relative time), settings view behind
    the gear (API key field, team id, feed URL, intervals, display toggles,
    "open config file" row). All text `Text.PlainText`; motion via
    `qs.Ui` `PanelController`/`PopupCard` and `Style.duration(ms)` only.
    Clicking an article runs `Quickshell.execDetached(["xdg-open", link])`.
  - **Acceptance Criteria:** Panel matches the wireframe layout; empty, no-key,
    and offline states each render their designed fallback; a language switch
    re-renders strings live (`strings.t()` kept in bindings).
- [ ] **Task 6: Bar widget**
  - **Files:** `BarWidget.qml`
  - **Details:** Icon-only widget on `qs.Ui` `BarWidget` base; click calls
    `shell.toggle(pluginId)`; visible only when the service has data or a
    configuration error to signal; theme-driven colors, no own palette.
  - **Acceptance Criteria:** Appears in `omarchy bar move` lists after enable,
    opens/closes the panel on click, follows theme changes live.
- [ ] **Task 7: Install, polish, verify**
  - **Files:** `README.md` (usage, config schema, data sources, polling disclosure, uninstall), final manifest tweaks
  - **Details:** Install the repo into the shell:
    `omarchy plugin add /home/atif/Work/sports-omarchy-plugin --enable` then
    `omarchy plugin enable atifkhan161.club-hub --section right`; run
    `qmllint` on the QML files; execute the manual checklist below; commit.
  - **Acceptance Criteria:** Plugin enabled in `omarchy plugin list`, bar icon in
    the right section, panel functional end-to-end.

## 4. Verification & Rollback Plan
- **Automated checks (minimal, per user decision):**
  - `omarchy plugin validate .` — required after every manifest change.
  - `python3 bin/rss.py <feed-url>` — helper smoke check (valid JSON out, non-zero on bad URL).
  - `qmllint Panel.qml BarWidget.qml Service.qml Config.qml` — no errors.
- **Manual Check:**
  1. `omarchy plugin add <repo> --enable` and confirm it appears in `omarchy plugin list`.
  2. Bar icon shows in the right section; click opens the panel.
  3. With no API key: panel shows the registration-link error state; RSS still loads.
  4. With key: next fixture card + 5 form chips match football-data.org's website for team 86.
  5. Edit `~/.config/omarchy/club-hub.json` (change feed URL / team id) → panel updates without restart.
  6. Disconnect network → cached content persists, error badge appears, no crash.
  7. Reload shell (`omarchy restart shell`) → cache prevents immediate refetch (watch logs).
- **Rollback:** `omarchy plugin remove atifkhan161.club-hub --yes` uninstalls; config
  and cache live under `~/.config/omarchy/club-hub.json` and `$XDG_CACHE_HOME/omarchy/club-hub/`
  and can be deleted independently; git history reverts any repo state.
