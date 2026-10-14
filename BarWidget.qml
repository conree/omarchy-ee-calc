import QtQuick
import qs.Commons
import qs.Ui

// EE Calc's bar icon, and the host for its panel. The icon is all the bar
// shows; every calculation lives in the panel and the Zig engine behind it.
BarWidget {
  id: root
  moduleName: "conree.ee-calc"

  readonly property string series: setting("series", "E24")
  readonly property string tab: setting("tab", "E-series")
  readonly property string font: setting("font", "Comic Code Ligatures")
  readonly property string packageCode: setting("packageCode", "0603")
  readonly property string tolerance: setting("tolerance", "1")

  // Choices made in the panel are remembered the way the built-in clock
  // remembers its format: applied locally, then written to shell.json.
  function persistSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- Panel plumbing. Bar.findPanelWidget requires open/close/opened on
  //      the bar-widget root, so the widget stands in as the panel's identity.
  //
  // The panel is loaded when it opens and unloaded once it has faded out.
  // Every editable Qt text field re-reads the clipboard's text on each
  // clipboard change, hidden or not, and on Wayland that read has no size cap
  // or overall deadline, so the panel's fields exist only while it is in use.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    unloadTimer.stop()
    panelLoader.active = true
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() {
    if (root.opened) root.close()
    else root.open()
  }

  // Box values, tab modes and colour bands, held here while the panel is
  // unloaded so closing it does not lose them. Not written to shell.json.
  property var panelSession: null

  readonly property bool panelIdle: panelLoader.item
    ? panelLoader.item.opened !== true && panelLoader.item.windowVisible !== true
    : false
  onPanelIdleChanged: {
    if (panelIdle) unloadTimer.restart()
    else unloadTimer.stop()
  }

  Timer {
    id: unloadTimer
    interval: 250
    onTriggered: {
      var item = panelLoader.item
      if (!item || !root.panelIdle) return
      if (typeof item.saveSession === "function") root.panelSession = item.saveSession()
      panelLoader.active = false
    }
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: false
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{f00ec}"
    labelVisible: true
    hasVisualContent: true
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: "EE Calc"

    onPressed: function(b) { root.togglePanel() }
  }
}
