import QtQuick
import Quickshell
import Quickshell.Io

// The plugin's settings, read from an XDG config file outside the plugin
// folder so `omarchy plugin update` can never clobber it:
//   ~/.config/omarchy/club-hub.json
//
// Missing keys fall back to defaults, invalid values are clamped or replaced,
// and a malformed file is ignored with a warning instead of breaking the
// shell. Edits on disk hot-reload via watchChanges, exactly like shell.json.

QtObject {
  id: root

  readonly property string configDir: {
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    return (xdg && xdg.length > 0 ? xdg : (Quickshell.env("HOME") + "/.config")) + "/omarchy"
  }
  readonly property string configPath: configDir + "/club-hub.json"

  readonly property var defaults: ({
    "football_data_api_key": "",
    "team_id": 86,
    "refresh_interval_matches_minutes": 20,
    "rss_url": "https://www.managingmadrid.com/rss/index.xml",
    "refresh_interval_rss_minutes": 30,
    "display": {
      "show_crest": true,
      "max_rss_items": 8,
      "compact_mode": false
    }
  })

  // Validated view of the file, merged over the defaults. Consumers bind to
  // the typed accessors below; the raw object is only for saving.
  property var config: defaults

  // ---- typed, clamped accessors ------------------------------------------------
  readonly property string apiKey: {
    var raw = String(config.football_data_api_key || "").trim()
    return raw.length > 0 && raw.length <= 200 ? raw : ""
  }
  readonly property int teamId: clampInt(config.team_id, 1, 9999999, 86)
  readonly property int matchIntervalMinutes: clampInt(config.refresh_interval_matches_minutes, 5, 720, 20)
  readonly property int rssIntervalMinutes: clampInt(config.refresh_interval_rss_minutes, 5, 720, 30)

  // Feeds must be fixed https sources; anything else falls back to the default.
  readonly property string rssUrl: {
    var raw = String(config.rss_url || "").trim()
    return raw.indexOf("https://") === 0 && raw.length < 2048 && !/\s/.test(raw) ? raw : defaults.rss_url
  }

  readonly property var display: config.display && typeof config.display === "object" ? config.display : defaults.display
  readonly property bool showCrest: display.show_crest !== false
  readonly property int maxRssItems: clampInt(display.max_rss_items, 1, 10, 8)

  function clampInt(value, min, max, fallback) {
    var n = parseInt(value, 10)
    if (!isFinite(n)) return fallback
    return Math.min(max, Math.max(min, n))
  }

  // ---- reading ------------------------------------------------------------------
  function parse(raw) {
    var out = defaults
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && typeof parsed === "object") {
        out = parsed
      } else {
        console.warn("club-hub config is not an object; using defaults")
        return
      }
    } catch (e) {
      console.warn("club-hub config is not valid JSON; using defaults:", e)
      return
    }
    // Reclamp through the accessors so the stored object stays honest too.
    var merged = {
      "football_data_api_key": String(out.football_data_api_key !== undefined ? out.football_data_api_key : defaults.football_data_api_key),
      "team_id": clampInt(out.team_id, 1, 9999999, 86),
      "refresh_interval_matches_minutes": clampInt(out.refresh_interval_matches_minutes, 5, 720, 20),
      "rss_url": String(out.rss_url !== undefined ? out.rss_url : defaults.rss_url),
      "refresh_interval_rss_minutes": clampInt(out.refresh_interval_rss_minutes, 5, 720, 30),
      "display": {
        "show_crest": !(out.display && out.display.show_crest === false),
        "max_rss_items": clampInt(out.display && out.display.max_rss_items, 1, 10, 8),
        "compact_mode": !!(out.display && out.display.compact_mode)
      }
    }
    config = merged
  }

  // ---- writing ------------------------------------------------------------------
  // `patch` holds only the fields being changed; everything else is kept.
  // Values pass through the same clamps, so a bad edit cannot persist.
  function save(patch) {
    var next = {}
    for (var key in config) next[key] = config[key]
    var display = {}
    for (var dkey in (config.display || {})) display[dkey] = config.display[dkey]

    if ("football_data_api_key" in patch) next.football_data_api_key = String(patch.football_data_api_key).trim().slice(0, 200)
    if ("team_id" in patch) next.team_id = clampInt(patch.team_id, 1, 9999999, 86)
    if ("refresh_interval_matches_minutes" in patch) next.refresh_interval_matches_minutes = clampInt(patch.refresh_interval_matches_minutes, 5, 720, 20)
    if ("refresh_interval_rss_minutes" in patch) next.refresh_interval_rss_minutes = clampInt(patch.refresh_interval_rss_minutes, 5, 720, 30)
    if ("rss_url" in patch) next.rss_url = String(patch.rss_url).trim()
    if ("show_crest" in patch) display.show_crest = patch.show_crest === true
    if ("max_rss_items" in patch) display.max_rss_items = clampInt(patch.max_rss_items, 1, 10, 8)
    next.display = display

    configFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.parse(text())
    onLoadFailed: function(error) {
      // A missing config writes the defaults; an unreadable one simply fails
      // to write too and we stay on in-memory defaults either way.
      console.warn("club-hub config load failed (" + error + "); using defaults, path=" + root.configPath)
      configFile.setText(JSON.stringify(root.defaults, null, 2) + "\n")
      root.parse(JSON.stringify(root.defaults))
    }
    onFileChanged: reload()
  }
}
