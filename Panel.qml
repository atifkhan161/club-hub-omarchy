import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The Club Hub panel: next fixture, last-five form, and the club news feed.
// Open with the bar widget or: omarchy-shell shell toggle atifkhan161.club-hub
//
// All data comes from the plugin's Service (shared, single poller). Every
// string that came from the network is rendered as PlainText: titles,
// bylines, and snippets from a feed are untrusted markup sinks.

Item {
  id: root

  // ------------------------------------------------------------ panel contract
  property bool opened: false
  property var shell: null
  property var manifest: null
  property var service: null
  property string view: "hub"       // "hub" | "settings"

  readonly property string selfId: manifest && manifest.id ? manifest.id : "atifkhan161.club-hub"

  onShellChanged: {
    if (!root.opened && root.shell && root.shell.openPanelIds
        && root.shell.openPanelIds[root.selfId] === true)
      root.open("{}")
  }

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  component PlainText: Text {
    textFormat: Text.PlainText
    font.family: root.fontFamily
    color: root.foreground
  }

  // -------------------------------------------------------------------- theme
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color accent: Color.accent
  property color urgent: Color.urgent
  readonly property color selBg: Color.menu.selectedBackground
  readonly property color muted: Color.muted
  readonly property color secondary: Qt.rgba(foreground.r * 0.65 + background.r * 0.35,
                                             foreground.g * 0.65 + background.g * 0.35,
                                             foreground.b * 0.65 + background.b * 0.35, 1)
  property string fontFamily: Style.font.menuFamily

  // -------------------------------------------------------------------- state
  // Rebuilt every minute so countdowns and feed ages re-render without any
  // network traffic.
  property var now: new Date()
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.now = new Date()
  }

  readonly property var hubConfig: root.service ? root.service.hubConfig : null
  readonly property var nextMatch: root.service ? root.service.nextMatch : null
  readonly property var lastFive: root.service ? root.service.lastFive : []
  readonly property var rssItems: root.service ? root.service.rssItems : []
  readonly property bool teamIdMatches: nextMatch
    ? (nextMatch.homeTeam && nextMatch.homeTeam.id === (hubConfig ? hubConfig.teamId : -1)
       || (nextMatch.awayTeam && nextMatch.awayTeam.id === (hubConfig ? hubConfig.teamId : -1)))
    : true
  readonly property string teamLabel: root.service && root.service.teamName !== ""
    ? root.service.teamName : strings.t("panel.title")

  // ------------------------------------------------------------- open / close
  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    root.view = "hub"
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.selfId)
  }

  function refresh() {
    if (root.service) root.service.refreshAll()
  }

  function countdownLabel(m) {
    if (!m) return ""
    if (m.status === "IN_PLAY") return strings.t("match.inProgress")
    var c = Model.countdown(m.utcDate, root.now)
    switch (c.unit) {
      case "today": return strings.t("countdown.today").arg(c.time)
      case "tomorrow": return strings.t("countdown.tomorrow").arg(c.time)
      case "dayshours": return strings.t("countdown.inDaysHours").arg(c.value).arg(c.value2)
      case "day": return strings.t("countdown.inDays").arg(c.value)
      case "hour": return strings.t("countdown.inHours").arg(c.value)
      case "min": return strings.t("countdown.inMinutes").arg(c.value)
    }
    return ""
  }

  function ageLabel(iso) {
    var a = Model.age(iso, root.now)
    switch (a.unit) {
      case "now": return strings.t("time.now")
      case "min": return strings.t("time.minutesAgo").arg(a.value)
      case "hour": return strings.t("time.hoursAgo").arg(a.value)
      case "yesterday": return strings.t("time.yesterday")
      case "day": return strings.t("time.daysAgo").arg(a.value)
    }
    return ""
  }

  function opponentShort(m) {
    var opp = Model.opponentOf(m, hubConfig ? hubConfig.teamId : -1)
    if (!opp) return strings.t("match.unknownOpponent")
    return opp.shortName || opp.name || strings.t("match.unknownOpponent")
  }

  function openArticle(item) {
    if (item && Model.linkOk(item.link))
      Quickshell.execDetached(["xdg-open", item.link])
  }

  // ------------------------------------------------------------------- window
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-atifkhan161-club-hub"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened && root.view === "settings"
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Clicking the scrim closes, exactly like the other panels.
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(620), panel.height * 0.85)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding
      clip: true
      LayoutMirroring.enabled: Commons.I18n.rightToLeft
      LayoutMirroring.childrenInherit: true

      MouseArea { anchors.fill: parent; onClicked: {} }

      // Entrance: grow and fade per the shell's motion rules — short, eased,
      // never from zero.
      opacity: root.opened ? 1 : 0
      scale: root.opened ? 1 : 0.97
      Behavior on opacity {
        NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic }
      }
      Behavior on scale {
        NumberAnimation {
          duration: Style.duration(180)
          easing.type: Easing.Bezier
          easing.bezierCurve: Style.easeOut
        }
      }

      ColumnLayout {
        anchors.fill: parent
        // anchors.fill ignores the card's padding, so the content margins
        // carry it instead — otherwise the header row sits flush against
        // the card border.
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(8)

        // ------------------------------------------------------------- header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          ColumnLayout {
            spacing: 0
            Layout.fillWidth: true
            PlainText {
              text: root.teamLabel
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
            PlainText {
              text: strings.t("panel.title")
              font.pixelSize: Style.font.caption
              color: root.muted
              visible: root.teamLabel !== strings.t("panel.title")
            }
          }

          PanelActionButton {
            iconText: "󰑐"
            tooltipText: strings.t("panel.refresh")
            foreground: root.foreground
            onClicked: root.refresh()
          }
          PanelActionButton {
            iconText: "󰒓"
            tooltipText: strings.t("panel.settings")
            foreground: root.foreground
            onClicked: root.view = root.view === "settings" ? "hub" : "settings"
          }
          PanelActionButton {
            iconText: "󰅙"
            tooltipText: strings.t("panel.close")
            foreground: root.foreground
            onClicked: root.close()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          height: 1
          color: root.border
          Layout.topMargin: Style.space(2)
          Layout.bottomMargin: Style.space(4)
        }

        // ------------------------------------------------------------ content
        // Settings view replaces the hub view; each keeps its own scroll.
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          Flickable {
            id: hubFlick
            visible: root.view === "hub"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: hubColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: hubColumn
              width: hubFlick.width
              spacing: Style.spacing.panelGap

              // ---------------------------------------------------- next match
              PanelSectionHeader {
                text: strings.t("section.nextMatch")
                foreground: root.muted
              }

              // No key configured: say so and hand over a link, the way the
              // PRD asks — never a silent blank.
              ColumnLayout {
                visible: !!root.service && root.service.matchesState === "no-key"
                spacing: Style.space(4)
                Layout.fillWidth: true
                PlainText {
                  text: strings.t("state.noKey")
                  color: root.urgent
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
                PlainText {
                  text: strings.t("state.noKeyHint")
                  color: root.secondary
                  font.pixelSize: Style.font.bodySmall
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
                Row {
                  spacing: Style.space(6)
                  Rectangle {
                    radius: Style.cornerRadius
                    color: root.selBg
                    width: registerRow.implicitWidth + Style.space(16)
                    height: registerRow.implicitHeight + Style.space(10)
                    Row {
                      id: registerRow
                      anchors.centerIn: parent
                      spacing: Style.space(6)
                      PlainText {
                        text: "󰐗"
                        color: root.accent
                        font.pixelSize: Style.font.body
                        anchors.verticalCenter: parent.verticalCenter
                      }
                      PlainText {
                        text: strings.t("state.openRegister")
                        color: root.accent
                        font.pixelSize: Style.font.bodySmall
                        anchors.verticalCenter: parent.verticalCenter
                      }
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: Quickshell.execDetached(
                        ["xdg-open", "https://www.football-data.org/client/register"])
                    }
                  }
                }
              }

              PlainText {
                visible: !!root.service && root.service.matchesState === "error"
                text: strings.t("state.error")
                color: root.urgent
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              PlainText {
                visible: !!root.service && root.service.matchesState === "loading" && !root.nextMatch
                text: strings.t("state.loading")
                color: root.muted
                font.pixelSize: Style.font.bodySmall
              }

              // The fixture card itself, on its own padded block.
              Rectangle {
                visible: root.nextMatch !== null
                radius: Style.cornerRadius
                color: root.selBg
                Layout.fillWidth: true
                implicitHeight: fixtureColumn.implicitHeight + Style.space(20)

                ColumnLayout {
                  id: fixtureColumn
                  anchors.fill: parent
                  anchors.margins: Style.space(10)
                  spacing: Style.space(8)

                  PlainText {
                    text: root.nextMatch
                      ? (root.nextMatch.competition && root.nextMatch.competition.name
                         || root.nextMatch.competition && root.nextMatch.competition.code || "")
                      : ""
                    color: root.muted
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                    visible: text !== ""
                  }

                  RowLayout {
                    spacing: Style.space(10)
                    Layout.fillWidth: true

                    PlainText {
                      text: root.nextMatch
                        ? (root.nextMatch.homeTeam && (root.nextMatch.homeTeam.shortName
                           || root.nextMatch.homeTeam.name) || strings.t("match.unknownOpponent"))
                        : ""
                      color: root.teamIdMatches && Model.isHome(root.nextMatch, root.hubConfig ? root.hubConfig.teamId : -1)
                        ? root.accent : root.foreground
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                      horizontalAlignment: Text.AlignLeft
                    }

                    ColumnLayout {
                      spacing: 0
                      PlainText {
                        text: strings.t("match.vs")
                        color: root.muted
                        font.pixelSize: Style.font.bodySmall
                        Layout.alignment: Qt.AlignHCenter
                      }
                      // Opponent crest, downloaded by the service into the
                      // cache and shown from the local file — never loaded
                      // over the network by the Image element itself, and
                      // hidden entirely when the user turned crests off.
                      Image {
                        source: root.hubConfig && root.hubConfig.showCrest
                          && root.service && root.service.crestFileUrl !== ""
                          ? root.service.crestFileUrl : ""
                        visible: source !== ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                        sourceSize: Qt.size(22, 22)
                        smooth: true
                        Layout.alignment: Qt.AlignHCenter
                      }
                    }

                    PlainText {
                      text: root.nextMatch
                        ? (root.nextMatch.awayTeam && (root.nextMatch.awayTeam.shortName
                           || root.nextMatch.awayTeam.name) || strings.t("match.unknownOpponent"))
                        : ""
                      color: root.teamIdMatches && !Model.isHome(root.nextMatch, root.hubConfig ? root.hubConfig.teamId : -1)
                        ? root.accent : root.foreground
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                      horizontalAlignment: Text.AlignRight
                    }
                  }

                  RowLayout {
                    spacing: Style.space(8)
                    Layout.fillWidth: true
                    PlainText {
                      text: root.nextMatch
                        ? Model.kickoffLabel(root.nextMatch.utcDate, Commons.I18n.formatLocale)
                        : ""
                      color: root.secondary
                      font.pixelSize: Style.font.bodySmall
                    }
                    Rectangle {
                      radius: Style.cornerRadius
                      color: root.nextMatch && root.nextMatch.status === "IN_PLAY"
                        ? root.urgent : root.accent
                      Layout.alignment: Qt.AlignLeft
                      implicitWidth: countdownText.implicitWidth + Style.space(16)
                      implicitHeight: countdownText.implicitHeight + Style.space(8)
                      PlainText {
                        id: countdownText
                        anchors.centerIn: parent
                        text: root.countdownLabel(root.nextMatch)
                        // Both badge colors (accent, urgent) are read with
                        // theme-background text on top.
                        color: root.background
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }
                    }
                    Item { Layout.fillWidth: true }
                  }
                }
              }

              // ---------------------------------------------------- recent form
              PanelSectionHeader {
                text: strings.t("section.form")
                foreground: root.muted
                visible: root.lastFive.length > 0
              }

              Repeater {
                model: root.lastFive
                delegate: Rectangle {
                  required property var modelData
                  color: "transparent"
                  Layout.fillWidth: true
                  implicitHeight: formRow.implicitHeight + Style.space(10)
                  radius: Style.cornerRadius

                  RowLayout {
                    id: formRow
                    anchors.fill: parent
                    anchors.margins: Style.space(5)
                    spacing: Style.space(10)

                  Rectangle {
                    radius: Style.cornerRadius
                    readonly property string letter: Model.resultFor(modelData, root.hubConfig ? root.hubConfig.teamId : -1)
                    readonly property color base: letter === "W" ? root.accent
                      : letter === "L" ? root.urgent : root.muted
                    color: base
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: resultLetter.implicitWidth + Style.space(12)
                    implicitHeight: resultLetter.implicitHeight + Style.space(6)
                    PlainText {
                      id: resultLetter
                      anchors.centerIn: parent
                      text: parent.letter === "W" ? strings.t("result.win")
                        : parent.letter === "L" ? strings.t("result.loss") : strings.t("result.draw")
                      color: root.background
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  PlainText {
                    text: Model.scoreline(modelData)
                    color: root.foreground
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }

                  PlainText {
                    text: (Model.isHome(modelData, root.hubConfig ? root.hubConfig.teamId : -1)
                           ? strings.t("match.vs") : strings.t("match.at"))
                      + " " + (Model.opponentOf(modelData, root.hubConfig ? root.hubConfig.teamId : -1)
                               ? (Model.opponentOf(modelData, root.hubConfig ? root.hubConfig.teamId : -1).shortName
                                  || Model.opponentOf(modelData, root.hubConfig ? root.hubConfig.teamId : -1).name) : "")
                    color: root.secondary
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  PlainText {
                    text: Model.shortDate(modelData.utcDate, Commons.I18n.formatLocale)
                    color: root.muted
                    font.pixelSize: Style.font.caption
                  }
                  }
                }
              }

              // ------------------------------------------------------ club news
              PanelSectionHeader {
                text: strings.t("section.news")
                foreground: root.muted
              }

              PlainText {
                visible: !!root.service && root.service.rssState === "error"
                text: strings.t("rss.error") + " " + strings.t("rss.openConfig")
                color: root.urgent
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              PlainText {
                visible: !!root.service && root.service.rssState === "loading" && root.rssItems.length === 0
                text: strings.t("state.loading")
                color: root.muted
                font.pixelSize: Style.font.bodySmall
              }

              PlainText {
                visible: !!root.service && root.service.rssState === "ok" && root.rssItems.length === 0
                text: strings.t("rss.empty")
                color: root.muted
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.rssItems
                delegate: ColumnLayout {
                  required property var modelData
                  spacing: 0
                  Layout.fillWidth: true

                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: articleRow.implicitHeight + Style.space(14)
                    radius: Style.cornerRadius
                    color: articleArea.containsMouse ? root.selBg : "transparent"

                    RowLayout {
                      id: articleRow
                      anchors.fill: parent
                      anchors.margins: Style.space(6)
                      anchors.leftMargin: Style.space(10)
                      spacing: Style.space(8)

                      ColumnLayout {
                        spacing: 0
                        Layout.fillWidth: true
                        PlainText {
                          text: modelData.title
                          color: root.foreground
                          font.pixelSize: Style.font.body
                          wrapMode: Text.Wrap
                          Layout.fillWidth: true
                        }
                        PlainText {
                          text: modelData.author !== ""
                            ? modelData.author + " · " + root.ageLabel(modelData.published)
                            : root.ageLabel(modelData.published)
                          color: root.muted
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                          visible: text !== ""
                          Layout.fillWidth: true
                        }
                      }
                    }

                    MouseArea {
                      id: articleArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.openArticle(modelData)
                    }
                  }
                }
              }

              Item { Layout.fillHeight: true; visible: root.view === "hub" }
            }
          }

          // --------------------------------------------------------- settings
          Flickable {
            id: settingsFlick
            visible: root.view === "settings"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: settingsColumn
              width: settingsFlick.width
              spacing: Style.space(12)
              visible: root.hubConfig !== null

              PlainText {
                text: strings.t("settings.savedNote")
                color: root.muted
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              PlainText {
                text: strings.t("settings.apiKey")
                color: root.secondary
                font.pixelSize: Style.font.caption
              }
              TextField {
                Layout.fillWidth: true
                password: true
                text: root.hubConfig ? root.hubConfig.apiKey : ""
                onEditingFinished: if (root.hubConfig) root.hubConfig.save({ "football_data_api_key": text })
              }

              PlainText {
                text: strings.t("settings.teamId")
                color: root.secondary
                font.pixelSize: Style.font.caption
              }
              TextField {
                Layout.fillWidth: true
                text: root.hubConfig ? String(root.hubConfig.teamId) : ""
                validator: IntValidator { bottom: 1; top: 9999999 }
                onEditingFinished: if (root.hubConfig && text !== "") root.hubConfig.save({ "team_id": parseInt(text, 10) })
              }
              PlainText {
                text: strings.t("settings.teamIdHint")
                color: root.muted
                font.pixelSize: Style.font.caption
              }

              PlainText {
                text: strings.t("settings.feedUrl")
                color: root.secondary
                font.pixelSize: Style.font.caption
              }
              TextField {
                Layout.fillWidth: true
                text: root.hubConfig ? root.hubConfig.rssUrl : ""
                onEditingFinished: if (root.hubConfig) root.hubConfig.save({ "rss_url": text })
              }
              PlainText {
                text: strings.t("settings.feedUrlHint")
                color: root.muted
                font.pixelSize: Style.font.caption
              }

              RowLayout {
                spacing: Style.space(10)
                Layout.fillWidth: true
                ColumnLayout {
                  spacing: 2
                  PlainText {
                    text: strings.t("settings.matchInterval")
                    color: root.secondary
                    font.pixelSize: Style.font.caption
                  }
                  TextField {
                    text: root.hubConfig ? String(root.hubConfig.matchIntervalMinutes) : ""
                    validator: IntValidator { bottom: 5; top: 720 }
                    onEditingFinished: if (root.hubConfig && text !== "") root.hubConfig.save({ "refresh_interval_matches_minutes": parseInt(text, 10) })
                  }
                }
                ColumnLayout {
                  spacing: 2
                  PlainText {
                    text: strings.t("settings.rssInterval")
                    color: root.secondary
                    font.pixelSize: Style.font.caption
                  }
                  TextField {
                    text: root.hubConfig ? String(root.hubConfig.rssIntervalMinutes) : ""
                    validator: IntValidator { bottom: 5; top: 720 }
                    onEditingFinished: if (root.hubConfig && text !== "") root.hubConfig.save({ "refresh_interval_rss_minutes": parseInt(text, 10) })
                  }
                }
                ColumnLayout {
                  spacing: 2
                  PlainText {
                    text: strings.t("settings.maxItems")
                    color: root.secondary
                    font.pixelSize: Style.font.caption
                  }
                  TextField {
                    text: root.hubConfig ? String(root.hubConfig.maxRssItems) : ""
                    validator: IntValidator { bottom: 1; top: 10 }
                    onEditingFinished: if (root.hubConfig && text !== "") root.hubConfig.save({ "max_rss_items": parseInt(text, 10) })
                  }
                }
              }

              RowLayout {
                spacing: Style.space(8)
                ToggleSwitch {
                  checked: root.hubConfig ? root.hubConfig.showCrest : true
                  foreground: root.foreground
                  accent: root.accent
                  onToggled: if (root.hubConfig) root.hubConfig.save({ "show_crest": checked })
                }
                PlainText {
                  text: strings.t("settings.showCrest")
                  color: root.secondary
                  font.pixelSize: Style.font.bodySmall
                }
              }

              Rectangle {
                Layout.fillWidth: true
                implicitHeight: openConfigRow.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: openConfigArea.containsMouse ? root.selBg : "transparent"
                RowLayout {
                  id: openConfigRow
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(6)
                  PlainText {
                    text: "󰈙"
                    color: root.accent
                    Layout.alignment: Qt.AlignVCenter
                  }
                  PlainText {
                    text: strings.t("settings.openConfig")
                    color: root.accent
                    font.pixelSize: Style.font.bodySmall
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
                MouseArea {
                  id: openConfigArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.hubConfig) Quickshell.execDetached(["xdg-open", root.hubConfig.configDir])
                }
              }

              Button {
                Layout.alignment: Qt.AlignRight
                text: strings.t("settings.done")
                foreground: root.foreground
                accent: root.accent
                onClicked: root.view = "hub"
              }
            }
          }
        }
      }
    }
  }
}
