import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// The plugin's data owner, mounted once by the shell at startup (kind
// "service"). The panel and the bar widget read it through the scoped
// `shell.serviceFor(id)` instead of fetching anything themselves, so there is
// exactly one poller no matter how many surfaces are open.
//
// Network work follows the house rules: fixed https endpoints with explicit
// timeouts, argument-list processes (no shell), size-capped parsing, and
// keep-last-good on failure. Responses are cached in $XDG_CACHE_HOME so a
// shell reload, lock, or unlock never refetches inside the interval.

Item {
  id: root

  // Injected by the shell when the service is created.
  property var shell: null
  property var manifest: null

  Config { id: config }
  // The whole validated-config object, handed to the panel and bar widget
  // (ids are file-scoped and invisible across files, so the panel cannot
  // reach the Config instance any other way).
  readonly property var hubConfig: config

  readonly property string selfId: manifest && manifest.id ? manifest.id : "atifkhan161.club-hub"
  readonly property string rssScript: decodeURIComponent(String(Qt.resolvedUrl("bin/rss.py")).replace(/^file:\/\//, ""))
  readonly property string cacheDir: {
    var xdg = Quickshell.env("XDG_CACHE_HOME")
    return (xdg && xdg.length > 0 ? xdg : (Quickshell.env("HOME") + "/.cache")) + "/omarchy/club-hub"
  }

  // ---- matches state -------------------------------------------------------------
  property var matchesData: []
  property string matchesState: "loading"   // "loading" | "ok" | "error" | "no-key"
  property string matchesError: ""
  property real matchesFetchedAt: 0

  readonly property var nextMatch: Model.nextMatch(matchesData)
  readonly property var lastFive: Model.lastFive(matchesData)
  readonly property string teamName: Model.teamName(matchesData, config.teamId)
  onNextMatchChanged: root.updateCrests()

  // ---- rss state -----------------------------------------------------------------
  property var rssData: []
  property string rssState: "loading"       // "loading" | "ok" | "error"
  property string rssError: ""
  property real rssFetchedAt: 0

  readonly property var rssItems: rssData.slice(0, config.maxRssItems)

  // ---- crest state ----------------------------------------------------------------
  // Both teams' crests are downloaded by curl into the cache and shown from
  // local files, one per side. A QML Image pointed straight at an https crest
  // URL crashed the whole shell once (Qt 6.12 TLS-backend crash inside
  // QNetworkAccessManager during SSL-cert init), and keeping the download in
  // curl matches the plugin's network policy anyway: fixed source, timeout,
  // size cap.
  property string homeCrestFileUrl: ""
  property string homeCrestRequestedUrl: ""
  property string homeCrestPendingUrl: ""
  property string homeCrestPendingPath: ""
  property string awayCrestFileUrl: ""
  property string awayCrestRequestedUrl: ""
  property string awayCrestPendingUrl: ""
  property string awayCrestPendingPath: ""

  function crestUrlFor(team) {
    return team && Model.crestOk(team.crest) ? team.crest : ""
  }

  // One cache file per club id, so the Image source changes when the fixture
  // changes clubs and Qt reloads instead of showing the previous badge.
  function crestCachePath(team) {
    var id = team && team.id !== undefined && team.id !== null ? String(team.id) : ""
    return /^[0-9]+$/.test(id) ? root.cacheDir + "/crest-" + id + ".img" : ""
  }

  function updateCrests() {
    updateCrest("home")
    updateCrest("away")
  }

  function updateCrest(side) {
    var proc = side === "home" ? homeCrestProc : awayCrestProc
    if (!proc) return
    var team = root.nextMatch ? root.nextMatch[side + "Team"] : null
    var url = crestUrlFor(team)
    var path = crestCachePath(team)
    var key = url + "|" + path
    var requested = side === "home" ? root.homeCrestRequestedUrl : root.awayCrestRequestedUrl
    if (key === requested) return
    if (side === "home") {
      root.homeCrestRequestedUrl = key
      root.homeCrestPendingUrl = key
      root.homeCrestPendingPath = path
    } else {
      root.awayCrestRequestedUrl = key
      root.awayCrestPendingUrl = key
      root.awayCrestPendingPath = path
    }
    if (url === "" || path === "") {
      if (proc.running) proc.running = false
      if (side === "home") root.homeCrestFileUrl = ""
      else root.awayCrestFileUrl = ""
      return
    }
    // Stop a download for a badge the fixture no longer uses, then fetch the
    // current one into that club's cache file.
    if (proc.running) proc.running = false
    proc.command = ["curl", "-fsS", "--max-time", "10", "--max-filesize", "524288",
                    "-o", path, url]
    proc.running = true
  }

  // ---- fetching ------------------------------------------------------------------
  function matchesCacheStale() {
    return Date.now() - matchesFetchedAt > config.matchIntervalMinutes * 60000
  }

  function rssCacheStale() {
    return Date.now() - rssFetchedAt > config.rssIntervalMinutes * 60000
  }

  function maybeRefresh() {
    if (matchesCacheStale()) fetchMatches(false)
    if (rssCacheStale()) fetchRss(false)
  }

  function refreshAll() {
    fetchMatches(true)
    fetchRss(true)
  }

  function fetchMatches(force) {
    if (!force && !matchesCacheStale()) return
    if (config.apiKey === "") {
      matchesState = "no-key"
      return
    }
    matchesState = "loading"
    matchesError = ""
    matchesProc.command = [
      "curl", "-fsS", "--max-time", "15",
      "-H", "X-Auth-Token: " + config.apiKey,
      "https://api.football-data.org/v4/teams/" + config.teamId
        + "/matches?status=FINISHED,SCHEDULED,TIMED,IN_PLAY"
    ]
    console.log("club-hub fetching matches for team", config.teamId)
    matchesProc.running = true
  }

  function fetchRss(force) {
    if (!force && !rssCacheStale()) return
    rssState = "loading"
    rssError = ""
    rssProc.command = ["python3", rssScript, config.rssUrl]
    rssProc.running = true
  }

  function applyMatches(raw, exitCode) {
    if (exitCode === undefined || exitCode === null) exitCode = -1
    if (exitCode !== 0) {
      matchesState = "error"
      // curl's -f turns an HTTP failure into exit 22; the free tier answers
      // 400/403 for a bad or missing token.
      matchesError = exitCode === 22 ? "HTTP error" : "curl exit " + exitCode
      console.warn("club-hub matches fetch failed:", matchesError,
        "stderr:", String(matchesErr.text || "").slice(0, 200))
      return
    }
    var list = Model.matchList(raw)
    if (list.length === 0 && String(raw).trim() === "") {
      matchesState = "error"
      matchesError = "empty response"
      return
    }
    matchesData = list
    matchesFetchedAt = Date.now()
    matchesState = "ok"
    matchesError = ""
    saveMatchesCache(list)
    console.log("club-hub matches fetched", list.length, "fixtures; next:",
      Model.nextMatch(list) ? Model.nextMatch(list).utcDate : "none")
  }

  function applyRss(raw, exitCode) {
    if (exitCode === undefined || exitCode === null) exitCode = -1
    if (exitCode !== 0) {
      rssState = "error"
      rssError = "helper exit " + exitCode
      console.warn("club-hub rss helper failed, exit", exitCode)
      return
    }
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (!Array.isArray(parsed)) throw new Error("not an array")
      rssData = parsed
      rssFetchedAt = Date.now()
      rssState = "ok"
      rssError = ""
      saveRssCache(parsed)
      var withBlocks = parsed.filter(function(item) {
        return item && Array.isArray(item.blocks) && item.blocks.length > 0
      }).length
      console.log("club-hub rss fetched", parsed.length, "items;", withBlocks,
        "with article text")
    } catch (e) {
      rssState = "error"
      rssError = "bad helper output"
      console.warn("club-hub rss helper output unusable:", String(raw).slice(0, 200))
    }
  }

  // ---- cache ---------------------------------------------------------------------
  function ensureCacheDir() {
    if (!mkCacheDir.running) mkCacheDir.running = true
  }

  function saveMatchesCache(list) {
    matchesCacheFile.setText(JSON.stringify({ "fetchedAt": matchesFetchedAt, "data": list }))
  }

  function saveRssCache(list) {
    // The cache directory may still be materializing on first run, so the
    // write is retried once on the next tick if it did not land.
    rssCacheFile.setText(JSON.stringify({ "fetchedAt": rssFetchedAt, "data": list }))
  }

  Component.onCompleted: {
    ensureCacheDir()
    // FileViews load asynchronously; when they land they either hand back
    // cached data or leave the defaults, and the timers take it from there.
    matchTimer.restart()
    rssTimer.restart()
    staleCheck.start()
    // Retry any crest whose change handler ran before the processes existed.
    root.updateCrests()
  }

  // Kick off a fetch once the cache files have had their chance to load.
  Timer {
    id: staleCheck
    interval: 1500
    onTriggered: root.maybeRefresh()
  }

  // ---- processes -----------------------------------------------------------------
  Process {
    id: matchesProc
    stdout: StdioCollector {
      id: matchesOut
      waitForEnd: true
    }
    stderr: StdioCollector {
      id: matchesErr
      waitForEnd: true
    }
    // The exit code is only reliable once the process reports exited, so the
    // response is applied here rather than in the collector's stream signal.
    onExited: function(exitCode) {
      root.applyMatches(String(matchesOut.text || ""), exitCode)
    }
  }

  Process {
    id: rssProc
    stdout: StdioCollector {
      id: rssOut
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyRss(String(rssOut.text || ""), exitCode)
    }
  }

  // Crest downloads, one process per side. Exit 63 is curl's --max-filesize
  // refusal; both failures clear that side's badge instead of showing a stale
  // club's crest.
  Process {
    id: homeCrestProc
    onExited: function(exitCode) {
      if (root.homeCrestRequestedUrl !== root.homeCrestPendingUrl) return
      root.homeCrestFileUrl = exitCode === 0 ? "file://" + root.homeCrestPendingPath : ""
      if (exitCode !== 0) console.warn("club-hub home crest download failed, curl exit", exitCode)
    }
  }

  Process {
    id: awayCrestProc
    onExited: function(exitCode) {
      if (root.awayCrestRequestedUrl !== root.awayCrestPendingUrl) return
      root.awayCrestFileUrl = exitCode === 0 ? "file://" + root.awayCrestPendingPath : ""
      if (exitCode !== 0) console.warn("club-hub away crest download failed, curl exit", exitCode)
    }
  }

  // House pattern for directory creation: a plain bash process, not a shell
  // interpolating user data.
  Process {
    id: mkCacheDir
    command: ["bash", "-c", "mkdir -p \"$0\"", root.cacheDir]
  }

  // ---- timers --------------------------------------------------------------------
  Timer {
    id: matchTimer
    repeat: true
    interval: config.matchIntervalMinutes * 60000
    onTriggered: root.fetchMatches(false)
  }

  Timer {
    id: rssTimer
    repeat: true
    interval: config.rssIntervalMinutes * 60000
    onTriggered: root.fetchRss(false)
  }

  // Config edits restart the cadence and refetch immediately when the club
  // or feed changed, so the panel never shows another team's data.
  Connections {
    target: config
    function onTeamIdChanged() { root.fetchMatches(true); root.updateCrests() }
    function onRssUrlChanged() { root.fetchRss(true) }
    function onMatchIntervalMinutesChanged() { matchTimer.restart(); root.fetchMatches(true) }
    function onRssIntervalMinutesChanged() { rssTimer.restart(); root.fetchRss(true) }
    function onApiKeyChanged() { root.fetchMatches(true) }
    function onMaxRssItemsChanged() { /* rssItems re-slices on its own */ }
  }

  // ---- cache files ---------------------------------------------------------------
  FileView {
    id: matchesCacheFile
    path: root.cacheDir + "/matches-cache.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var cached = JSON.parse(String(text() || "{}"))
        if (Array.isArray(cached.data)) {
          root.matchesData = cached.data
          root.matchesFetchedAt = Number(cached.fetchedAt) || 0
          if (root.matchesState === "loading" && cached.data.length > 0) root.matchesState = "ok"
        }
      } catch (e) { /* corrupt cache: fall through to a fresh fetch */ }
    }
    onLoadFailed: function(error) { /* no cache yet: the timers will fetch */ }
  }

  FileView {
    id: rssCacheFile
    path: root.cacheDir + "/rss-cache.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: {
      try {
        var cached = JSON.parse(String(text() || "{}"))
        if (Array.isArray(cached.data)) {
          root.rssData = cached.data
          root.rssFetchedAt = Number(cached.fetchedAt) || 0
          if (root.rssState === "loading" && cached.data.length > 0) root.rssState = "ok"
        }
      } catch (e) { /* corrupt cache: fall through to a fresh fetch */ }
    }
    onLoadFailed: function(error) { /* no cache yet: the timers will fetch */ }
  }
}
