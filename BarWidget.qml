import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar icon for Club Hub: a click opens the panel. All data lives in the
// plugin's service; the widget only reads its state for the tooltip and a
// trouble color, and never fetches anything itself.

BarWidget {
  id: root
  moduleName: "atifkhan161.club-hub"

  readonly property string selfId: "atifkhan161.club-hub"

  // The bar hands third-party widgets a scoped shell facade whose
  // serviceFor() resolves only this plugin's own service.
  readonly property var service: root.bar && root.bar.shell
    && typeof root.bar.shell.serviceFor === "function"
    ? root.bar.shell.serviceFor(root.selfId) : null

  readonly property bool trouble: root.service
    && (root.service.matchesState === "no-key" || root.service.matchesState === "error"
        || root.service.rssState === "error")

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uF1E3"   // nf-fa-futbol
    tooltipText: root.trouble ? strings.t("state.noKey") : strings.t("bar.tooltip")
    fixedWidth: root.bar && root.bar.vertical ? -1 : Style.space(27)
    fixedHeight: root.bar && root.bar.vertical ? Style.space(26) : -1
    dimmed: root.trouble
    onPressed: function(b) {
      if (!root.bar) return
      // The scoped facade knows only this plugin's panel; a replacement bar
      // gets a service-less facade, so fall back to the IPC round trip.
      if (root.bar.shell && typeof root.bar.shell.toggle === "function")
        root.bar.shell.toggle(root.selfId)
      else
        root.bar.run("omarchy-shell shell toggle " + root.selfId)
    }
  }
}
