# Product Requirements Document (PRD): Omarchy Club Hub Plugin

A native desktop widget/plugin for the Omarchy Linux desktop environment (Qt/QML, Wayland/Hyprland) designed to track live football club fixtures, recent results, and curate custom RSS club news feeds in a unified view.

---

## 1. Overview & Objectives

* **Target Platform:** Omarchy OS desktop shell (Qt 6 / QML widget layer).
* **Primary Scope:** 
  1. Configurable single-club match tracking (upcoming fixture countdown, last 5 match results).
  2. Integrated club RSS feed parser (headlines, publication timestamps, inline preview/links).
* **Target Club Default:** Real Madrid C.F. (configurable by club identifier).
* **Target RSS Default:** `https://www.managingmadrid.com/rss/index.xml`.

---

## 2. API & Data Provider Analysis

### Recommended Football Data API: **football-data.org**
* **Tier:** Free tier (Registration requires an API token, zero cost).
* **Rate Limits:** 10 requests per minute (sufficient for cached local polling every 15–30 minutes).
* **Key Endpoints:**
  * **Team Matches:** `GET https://api.football-data.org/v4/teams/{team_id}/matches`
  * **Real Madrid ID:** `86`
* **Free Tier Coverage:** Includes La Liga (`PD`), UEFA Champions League (`CL`), and domestic cups where tracked.
* **Alternative Options Evaluated:**
  * *TheSportsDB (Free API V1):* Unauthenticated public tier is rate-limited and lacks timely schedule updates for certain European competitions.
  * *API-Football (RapidAPI):* Free tier hard-capped at 100 requests/day, making frequent desktop polling prone to mid-day cutoffs.

### RSS Parser Architecture
* Direct HTTP GET fetching of standard RSS 2.0 / Atom XML feeds.
* Parsed via standard XML DOM/XPath or lightweight C++/QML parser (`QXmlStreamReader` or JS helper within QML engine).

---

## 3. Architecture & Data Flow

```text
┌────────────────────────────────────────────────────────┐
│                   Omarchy Shell UI                     │
│      (QML Widget / Wayland Surface / Quick View)       │
└──────────────┬──────────────────────────┬──────────────┘
               │                          │
        [Match Data Model]         [RSS News Model]
               │                          │
   ┌───────────┴───────────┐      ┌───────┴──────────────┐
   │ football-data.org API │      │ Managing Madrid RSS  │
   │  (Polling: 15-30m)    │      │  (Polling: 30m)      │
   └───────────────────────┘      └──────────────────────┘
```

---

## 4. Feature Specifications

### 4.1. Match Tracker Module
* **Next Fixture Card:**
  * Competition emblem / name (e.g., La Liga, Champions League).
  * Opponent club name and crest.
  * Home / Away indicator.
  * Match date, kickoff time (localized to user system timezone), and relative countdown badge (e.g., `In 2 days`, `Live - 64'`).
* **Recent Form (Last 5 Matches):**
  * Horizontal strip or compact list showing the last 5 completed matches in chronological order.
  * Form indicators: **W** (Green), **D** (Gray/Yellow), **L** (Red).
  * Scoreline display: Home Score vs Away Score, opponent crest/abbreviation, and date.

### 4.2. RSS Club Feed Module
* **Feed Stream:**
  * Parses up to 10 latest entries from configured feed URL (`https://www.managingmadrid.com/rss/index.xml`).
  * Displays Article Title, Author, and Relative Time (`2h ago`, `Yesterday`).
  * Click-to-action: Opens article link in default system browser (`xdg-open`).
  * Optional clean preview snippet (strips embedded HTML tags).

### 4.3. Settings & Configuration
* Persistent config file: `~/.config/omarchy/plugins/club-hub/config.json`.

```json
{
  "football_data_api_key": "YOUR_API_KEY",
  "team_id": 86,
  "refresh_interval_matches_minutes": 20,
  "rss_url": "https://www.managingmadrid.com/rss/index.xml",
  "refresh_interval_rss_minutes": 30,
  "display": {
    "show_crest": true,
    "max_rss_items": 8,
    "compact_mode": false
  }
}
```

---

## 5. API Integration Schema

### 5.1. Fetching Fixtures & Results
```http
GET https://api.football-data.org/v4/teams/86/matches?status=FINISHED,SCHEDULED,TIMED,IN_PLAY
X-Auth-Token: <API_KEY>
```

#### Processing Logic:
* **Last 5 Matches:** Filter where `status == "FINISHED"`, sort descending by `utcDate`, take the first 5 records, then reverse for chronological left-to-right form display.
* **Next Match:** Filter where `status IN ["SCHEDULED", "TIMED", "IN_PLAY"]`, sort ascending by `utcDate`, select item index `0`.

```json
{
  "competition": {
    "name": "Primera Division",
    "code": "PD"
  },
  "utcDate": "2026-11-21T20:00:00Z",
  "status": "TIMED",
  "homeTeam": { "id": 86, "name": "Real Madrid CF", "shortName": "Real Madrid" },
  "awayTeam": { "id": 78, "name": "Club Atlético de Madrid", "shortName": "Atleti" },
  "score": {
    "winner": null,
    "fullTime": { "home": null, "away": null }
  }
}
```

### 5.2. RSS Parsing
* **Endpoint:** `GET https://www.managingmadrid.com/rss/index.xml`
* **Headers:** `User-Agent: OmarchyPlugin/1.0 (Linux; Wayland)`
* **Extracted Fields:**
  * `<title>` $\rightarrow$ Card headline
  * `<pubDate>` $\rightarrow$ Converted to relative human-readable timestamp
  * `<link>` $\rightarrow$ Execution payload for browser dispatch
  * `<dc:creator>` or `<author>` $\rightarrow$ Byline attribution

---

## 6. UI/UX Layout (QML Wireframe Spec)

* **Shell Footprint:** Suitable as a panel popup, floating widget, or desktop glance module.
* **Color Palette:** Follows Omarchy/Hyprland active system theme (Catppuccin, Nord, or Tokyo Night variables).

```text
+--------------------------------------------------------------+
|  REAL MADRID C.F.                           [Refresh] [Gear] |
+--------------------------------------------------------------+
|  NEXT MATCH                                                  |
|  [La Liga]  Real Madrid  vs  Atlético Madrid                 |
|  Sat, Nov 21 · 20:00 Local (In 3 days)                       |
+--------------------------------------------------------------+
|  RECENT FORM (Last 5)                                        |
|  [W] 3 - 1 vs Osasuna                                        |
|  [W] 2 - 0 @ Leganés                                         |
|  [L] 1 - 3 vs AC Milan                                       |
|  [W] 4 - 0 vs Villarreal                                     |
|  [D] 1 - 1 @ Atlético Madrid                                 |
+--------------------------------------------------------------+
|  MANAGING MADRID (RSS)                                       |
|  * Post-Match Analysis: Tactical Adjustments in Midfield     |
|    by Kiyan Sobhani · 4h ago                                 |
|  * Player Ratings from Weekend Clash                         |
|    by Matt Wiltse · 7h ago                                   |
|  * Injury Update: Training Ground Reports Ahead of Derby     |
|    by Lucas Navarrete · 1d ago                               |
+--------------------------------------------------------------+
```

---

## 7. Non-Functional Requirements & Performance

* **Memory Footprint:** Under 25MB resident memory footprint when idle.
* **Network Throttling:** 
  * Caching layer to persist responses in `/tmp/omarchy-clubhub-cache.json` or `$XDG_CACHE_HOME`.
  * Prevent duplicate requests on rapid shell reload or desktop lock/unlock.
* **Error Handling:**
  * Graceful fallback states for offline network modes.
  * Clear UI feedback if `football_data_api_key` is missing or invalid, showing an explicit link to grab a free token.
  * Non-blocking asynchronous network requests using Qt Network (`QNetworkAccessManager`) or QML `XMLHttpRequest`.