import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The Club Hub panel: next fixture, last-five form, club news, and an
// in-panel article reader built from the feed's own content (no scraping).
// Open with the bar widget or: omarchy-shell shell toggle atifkhan161.club-hub
//
// All data comes from the plugin's Service (shared, single poller). Every
// string that came from the network is rendered as PlainText: titles,
// bylines, snippets, and reader blocks from a feed are untrusted markup sinks.

Item {
  id: root

  // ------------------------------------------------------------ panel contract
  property bool opened: false
  property var shell: null
  property var manifest: null
  property var service: null
  property string view: "hub"       // "hub" | "settings" | "reader"
  // Which rssItems entry the reader is showing; -1 means none.
  property int readerIndex: -1

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

  // A club badge in a fixed slot: the slot keeps its size while the download
  // is in flight, and disappears with the user's show-crest setting.
  component Crest: Item {
    property string source: ""
    visible: root.showCrests
    Layout.preferredWidth: root.crestSize
    Layout.preferredHeight: root.crestSize
    Layout.alignment: Qt.AlignVCenter

    Image {
      anchors.fill: parent
      source: parent.source
      visible: source !== ""
      asynchronous: true
      fillMode: Image.PreserveAspectFit
      sourceSize: Qt.size(root.crestSize, root.crestSize)
      smooth: true
    }
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
  readonly property var readerItem: root.view === "reader" && root.readerIndex >= 0
    && root.readerIndex < root.rssItems.length ? root.rssItems[root.readerIndex] : null
  readonly property var readerBlocks: Model.articleBlocks(root.readerItem)
  readonly property string readerByline: {
    if (!root.readerItem) return ""
    var parts = []
    if (root.readerItem.author) parts.push(root.readerItem.author)
    var age = root.ageLabel(root.readerItem.published)
    if (age !== "") parts.push(age)
    return parts.join(" · ")
  }
  // A refresh can reorder or shrink the feed mid-read. The bounds check runs
  // in a deferred callback: reading rssItems inside the change handler made
  // QML see a binding loop (the handler wrote view/index, which readerItem
  // depends on). If the stored index no longer points at an article, fall
  // back to the hub instead of rendering an empty reader.
  onRssItemsChanged: Qt.callLater(function() {
    if (root.view === "reader" && root.readerIndex >= root.rssItems.length) {
      root.readerIndex = -1
      root.view = "hub"
    }
  })
  readonly property bool teamIdMatches: nextMatch
    ? (nextMatch.homeTeam && nextMatch.homeTeam.id === (hubConfig ? hubConfig.teamId : -1)
       || (nextMatch.awayTeam && nextMatch.awayTeam.id === (hubConfig ? hubConfig.teamId : -1)))
    : true
  // Both club badges, downloaded by the service into the cache and shown from
  // local files. The size follows the shell's spacing scale like every other
  // dimension in the panel.
  readonly property bool showCrests: !!(root.hubConfig && root.hubConfig.showCrest)
  readonly property int crestSize: Style.space(28)
  readonly property string homeCrestUrl: root.showCrests && root.service
    && root.service.homeCrestFileUrl !== "" ? root.service.homeCrestFileUrl : ""
  readonly property string awayCrestUrl: root.showCrests && root.service
    && root.service.awayCrestFileUrl !== "" ? root.service.awayCrestFileUrl : ""
  readonly property string teamLabel: root.service && root.service.teamName !== ""
    ? root.service.teamName : strings.t("panel.title")

  // ------------------------------------------------------------- open / close
  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    if (!root.opened) return
    root.opened = false
    root.showHub()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.selfId)
  }

  // Reader navigation: the index is validated against the live feed so a
  // refresh that removed the article cannot leave the reader pointing past
  // the end.
  function openReader(index) {
    if (index < 0 || index >= root.rssItems.length) return
    root.readerIndex = index
    root.view = "reader"
    readerFlick.contentY = 0
  }

  function showHub() {
    root.readerIndex = -1
    root.view = "hub"
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
                    spacing: Style.space(8)
                    Layout.fillWidth: true

                    Crest { source: root.homeCrestUrl }

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

                    PlainText {
                      text: strings.t("match.vs")
                      color: root.muted
                      font.pixelSize: Style.font.bodySmall
                      Layout.alignment: Qt.AlignVCenter
                      Layout.preferredWidth: Style.space(24)
                      horizontalAlignment: Text.AlignHCenter
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

                    Crest { source: root.awayCrestUrl }
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
                  required property int index
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
                      onClicked: root.openReader(index)
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
                onClicked: root.showHub()
              }
            }
          }

          // ----------------------------------------------------------- reader
          // The reader is the third view. It renders only the feed's own
          // content (blocks parsed by bin/rss.py); no article URL is fetched.
          RowLayout {
            visible: root.view === "reader"
            Layout.fillWidth: true
            spacing: Style.space(6)

            PanelActionButton {
              iconText: "󰅁"
              tooltipText: strings.t("reader.back")
              foreground: root.foreground
              onClicked: root.showHub()
            }
            PlainText {
              text: strings.t("reader.back")
              color: root.muted
              font.pixelSize: Style.font.caption
              Layout.alignment: Qt.AlignVCenter
            }
            Item { Layout.fillWidth: true }
          }

          Flickable {
            id: readerFlick
            visible: root.view === "reader"
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: readerColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: readerColumn
              width: readerFlick.width
              spacing: Style.space(10)

              PlainText {
                text: root.readerItem ? root.readerItem.title : ""
                font.pixelSize: Style.font.title
                font.bold: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              PlainText {
                text: root.readerByline
                color: root.muted
                font.pixelSize: Style.font.caption
                visible: text !== ""
                Layout.fillWidth: true
              }

              Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.border
              }

              Repeater {
                model: root.readerBlocks

                delegate: PlainText {
                  required property var modelData
                  text: (modelData.t === "li" ? "• " : "") + modelData.text
                  textFormat: Text.PlainText
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: modelData.t === "h" ? Style.font.heading : Style.font.body
                  font.bold: modelData.t === "h"
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                  Layout.leftMargin: modelData.t === "li" ? Style.space(10) : 0
                }
              }

              // No body in the feed (or an old cache entry written before
              // blocks existed): show the snippet, then point at the browser.
              ColumnLayout {
                visible: root.readerItem !== null && root.readerBlocks.length === 0
                spacing: Style.space(6)
                Layout.fillWidth: true

                PlainText {
                  text: root.readerItem && root.readerItem.snippet
                    ? root.readerItem.snippet : strings.t("reader.noContent")
                  color: root.foreground
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
                PlainText {
                  text: strings.t("reader.noContentHint")
                  color: root.muted
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                  Layout.fillWidth: true
                }
              }

              PlainText {
                visible: root.readerItem !== null && Model.articleTruncated(root.readerItem)
                text: strings.t("reader.truncated")
                color: root.muted
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
              }

              // Browser escape hatch: only for a link that passes the same
              // safety rule the hub rows use. Styled like the settings row.
              Rectangle {
                visible: root.readerItem !== null && Model.linkOk(root.readerItem.link)
                Layout.fillWidth: true
                Layout.topMargin: Style.space(4)
                implicitHeight: openBrowserRow.implicitHeight + Style.space(12)
                radius: Style.cornerRadius
                color: openBrowserArea.containsMouse ? root.selBg : "transparent"

                RowLayout {
                  id: openBrowserRow
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  spacing: Style.space(6)
                  PlainText {
                    text: "󰐗"
                    color: root.accent
                    Layout.alignment: Qt.AlignVCenter
                  }
                  PlainText {
                    text: strings.t("reader.openBrowser")
                    color: root.accent
                    font.pixelSize: Style.font.bodySmall
                    Layout.alignment: Qt.AlignVCenter
                  }
                }
                MouseArea {
                  id: openBrowserArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openArticle(root.readerItem)
                }
              }
            }
          }
        }
      }
    }
  }
}
