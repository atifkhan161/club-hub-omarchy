.pragma library

// Pure helpers for the football-data.org team-matches payload and the RSS
// helper's JSON. No imports, no Qt.Singletons: the offscreen test harness and
// the panel both call these straight.

var UPCOMING = ["SCHEDULED", "TIMED", "IN_PLAY"]
var FINISHED = "FINISHED"

function safeDate(value) {
  var ms = Date.parse(String(value || ""))
  return isFinite(ms) ? new Date(ms) : null
}

function matchList(raw) {
  try {
    var parsed = JSON.parse(String(raw || ""))
    return Array.isArray(parsed && parsed.matches) ? parsed.matches : []
  } catch (e) {
    return []
  }
}

function teamName(matches, teamId) {
  for (var i = 0; i < matches.length; i++) {
    var m = matches[i]
    if (!m || !m.homeTeam || !m.awayTeam) continue
    if (m.homeTeam.id === teamId) return m.homeTeam.name || ""
    if (m.awayTeam.id === teamId) return m.awayTeam.name || ""
  }
  return ""
}

// Earliest match that is not over. An IN_PLAY match sorts by its kickoff and
// shows a static "In progress" badge; the free tier's data lags too much for
// a live-minute display.
function nextMatch(matches) {
  var upcoming = matches.filter(function(m) {
    return m && UPCOMING.indexOf(m.status) !== -1 && safeDate(m.utcDate)
  })
  upcoming.sort(function(a, b) { return safeDate(a.utcDate) - safeDate(b.utcDate) })
  return upcoming[0] || null
}

// Last five finished matches, oldest first, for a left-to-right form strip.
function lastFive(matches) {
  var done = matches.filter(function(m) {
    return m && m.status === FINISHED && safeDate(m.utcDate)
  })
  done.sort(function(a, b) { return safeDate(b.utcDate) - safeDate(a.utcDate) })
  return done.slice(0, 5).reverse()
}

function opponentOf(match, teamId) {
  if (!match) return null
  if (match.homeTeam && match.homeTeam.id === teamId) return match.awayTeam || null
  return match.homeTeam || null
}

function isHome(match, teamId) {
  return !!(match && match.homeTeam && match.homeTeam.id === teamId)
}

// W/D/L from the configured team's point of view, preferring the payload's
// own winner field and falling back to comparing full-time goals.
function resultFor(match, teamId) {
  if (!match || !match.score || !match.score.fullTime) return ""
  var home = Number(match.score.fullTime.home)
  var away = Number(match.score.fullTime.away)
  if (!isFinite(home) || !isFinite(away)) {
    var winner = match.score.winner
    if (winner === "HOME_TEAM") return isHome(match, teamId) ? "W" : "L"
    if (winner === "AWAY_TEAM") return isHome(match, teamId) ? "L" : "W"
    return "D"
  }
  var forTeam = isHome(match, teamId) ? home : away
  var againstTeam = isHome(match, teamId) ? away : home
  if (forTeam > againstTeam) return "W"
  if (forTeam < againstTeam) return "L"
  return "D"
}

// "3 - 1" always reads home-away, matching the wireframe.
function scoreline(match) {
  if (!match || !match.score || !match.score.fullTime) return ""
  var home = match.score.fullTime.home
  var away = match.score.fullTime.away
  if (home === null || home === undefined || away === null || away === undefined) return ""
  return home + " - " + away
}

// Countdown pieces relative to `now`, for the panel to translate:
//   {unit: "min"|"hour"|"day"|"today"|"tomorrow", value: n, value2: n, time: "20:00"}
function countdown(utcDate, now) {
  var then = safeDate(utcDate)
  if (!then) return { unit: "", value: 0, value2: 0, time: "" }
  var ms = then - now
  var time = Qt.formatDateTime(then, "HH:mm")
  if (ms <= 0) return { unit: "today", value: 0, value2: 0, time: time }
  var minutes = Math.floor(ms / 60000)
  var days = Math.floor(minutes / 1440)
  var hours = Math.floor((minutes % 1440) / 60)
  var sameDay = then.getFullYear() === now.getFullYear()
    && then.getMonth() === now.getMonth()
    && then.getDate() === now.getDate()
  var tomorrow = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
  var isTomorrow = then.getFullYear() === tomorrow.getFullYear()
    && then.getMonth() === tomorrow.getMonth()
    && then.getDate() === tomorrow.getDate()
  if (sameDay) return { unit: "today", value: 0, value2: 0, time: time }
  if (isTomorrow && days <= 1) return { unit: "tomorrow", value: 0, value2: 0, time: time }
  if (days >= 1 && hours > 0) return { unit: "dayshours", value: days, value2: hours, time: time }
  if (days >= 1) return { unit: "day", value: days, value2: 0, time: time }
  if (minutes >= 60) return { unit: "hour", value: Math.floor(minutes / 60), value2: 0, time: time }
  return { unit: "min", value: Math.max(1, minutes), value2: 0, time: time }
}

// Localized "Sat, Nov 21 · 20:00". The locale comes from the caller, since a
// .pragma library cannot import qs.Commons.
function kickoffLabel(utcDate, localeName) {
  var then = safeDate(utcDate)
  if (!then) return ""
  return Qt.formatDateTime(then, "ddd, MMM d · HH:mm", Qt.locale(localeName))
}

// Short "21 Nov" date for form rows.
function shortDate(utcDate, localeName) {
  var then = safeDate(utcDate)
  if (!then) return ""
  return Qt.formatDate(then, "d MMM", Qt.locale(localeName))
}

// Age of a published ISO timestamp, for the panel to translate:
//   {unit: "now"|"min"|"hour"|"yesterday"|"day", value: n}
function age(iso, now) {
  var then = safeDate(iso)
  if (!then) return { unit: "", value: 0 }
  var minutes = Math.floor((now - then) / 60000)
  if (minutes < 1) return { unit: "now", value: 0 }
  if (minutes < 60) return { unit: "min", value: minutes }
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return { unit: "hour", value: hours }
  var dayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  var thenDayStart = new Date(then.getFullYear(), then.getMonth(), then.getDate())
  if (dayStart - thenDayStart === 86400000) return { unit: "yesterday", value: 0 }
  return { unit: "day", value: Math.max(1, Math.floor(hours / 24)) }
}

// A crest URL is shown only when it looks safe: https, short, and it names
// an image. Everything else falls back to the short name.
function crestOk(url) {
  var s = String(url || "")
  return s.indexOf("https://") === 0 && s.length < 500 && /\.(png|jpe?g|svg|webp)(\?|$)/i.test(s)
}

// A feed article is opened only when its link is a plain short https URL —
// anything else from the feed is ignored rather than handed to xdg-open.
function linkOk(url) {
  var s = String(url || "")
  return s.indexOf("https://") === 0 && s.length < 2048 && !/\s/.test(s)
}

