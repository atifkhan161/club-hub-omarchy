# Club Hub for Omarchy

A bar widget and panel for the [Omarchy](https://omarchy.org) desktop that
tracks one football club: the next fixture with a countdown, the last five
results as a form strip, and the club's RSS news feed — all in one panel.

Default club: Real Madrid C.F. (football-data.org team id 86). Default feed:
[Managing Madrid](https://www.managingmadrid.com/rss/index.xml). Both are
configurable in the panel's settings.

## Install

```bash
omarchy plugin add <this-repo-url> --enable
```

The bar icon lands in the right section (`omarchy bar move` to rearrange).
Click it, or run `omarchy-shell shell toggle atifkhan161.club-hub`, to open
the panel.

## Requirements

- **football-data.org API key** — free, at
  [football-data.org/client/register](https://www.football-data.org/client/register).
  The panel shows a registration link until a key is configured.
- `python3` for the RSS helper (`bin/rss.py`, standard library only).
- `curl` (already part of Omarchy).

## Settings

The gear button in the panel opens the settings view. Everything is stored in
`~/.config/omarchy/club-hub.json` — outside the plugin folder, so plugin
updates never touch it — and applies immediately:

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

You can edit the file directly; it hot-reloads.

## Data sources and privacy

- Matches: `api.football-data.org/v4/teams/{team_id}/matches`, fetched every
  `refresh_interval_matches_minutes` (minimum 5). Sent with the request: only
  your API token, over HTTPS.
- News: the configured feed URL, fetched every `refresh_interval_rss_minutes`
  (minimum 5) by `bin/rss.py` with a plain `OmarchyPlugin/1.0 (Linux; Wayland)`
  User-Agent. Responses are size-capped; article links open with `xdg-open`
  only when they are plain https URLs.
- Responses are cached in `$XDG_CACHE_HOME/omarchy/club-hub/` so shell reloads
  and lock/unlock cycles do not refetch inside the interval.
- No live-minute display: the free tier's data lags, so a match that is in
  progress shows a static "In progress" badge instead of a ticking clock.

The W/D/L form chips use the theme's accent (win), muted (draw), and urgent
(loss) colors, so the panel follows the active Omarchy theme.

## Layout

| | |
|---|---|
| `manifest.json` | Plugin id, kinds, and entry points |
| `Service.qml` | The single poller: fetching, parsing, caching, timers |
| `Panel.qml` | The panel UI and settings view |
| `BarWidget.qml` | The bar icon |
| `Config.qml` | Config read/validate/write against `~/.config/omarchy/club-hub.json` |
| `Model.js` | Pure helpers: match selection, results, countdowns, ages |
| `bin/rss.py` | RSS 2.0 / Atom fetch-and-parse helper |
| `i18n/en.json` | UI strings (English; the shell's fallback chain handles the rest) |

## Uninstall

```bash
omarchy plugin remove atifkhan161.club-hub --yes
```

The config and cache files under `~/.config/omarchy/club-hub.json` and
`$XDG_CACHE_HOME/omarchy/club-hub/` are yours to keep or delete.

## License

MIT.
