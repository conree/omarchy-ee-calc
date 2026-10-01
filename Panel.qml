pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The calculator panel. Every number shown here comes from the Zig engine
// in bin/ee-calc: the panel collects input, runs the engine as you type, and
// lays out the JSON it prints. No arithmetic happens in QML.
Panel {
  id: root
  moduleName: "conree.ee-calc"
  ipcTarget: ""
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // One step larger than the shell's own sizes (12 -> 13 px body text).
  // Every font size and spacing goes through these two helpers, so the
  // whole panel scales together and keeps its layout.
  readonly property real textScale: 13 / 12
  function fs(px) { return Math.round(px * textScale) }
  function sp(v) { return Style.space(v) * textScale }

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string shellFont: bar ? bar.fontFamily : Style.font.family
  // The panel's own font when it is installed, else the shell's, so a
  // missing font never drops to whatever Qt picks as a default.
  readonly property string chosenFont: hostWidget ? String(hostWidget.font || "").trim() : ""
  readonly property string fontFamily: chosenFont !== "" && Qt.fontFamilies().indexOf(chosenFont) !== -1 ? chosenFont : shellFont

  // Theme palette. The shell exposes only accent and urgent, so the rest of
  // the ANSI colours (color1..color6) are read from the active theme's own
  // colors.toml. Nothing here is a fixed colour: switch theme and the panel
  // follows. Under Dracula Pro Van Helsing these are salmon, green, yellow,
  // purple, pink and cyan.
  property color cRed: Color.urgent
  property color cGreen: Color.accent
  property color cYellow: Color.accent
  property color cPurple: Color.accent
  property color cPink: Color.accent
  property color cCyan: Color.accent
  readonly property color good: cGreen
  readonly property color caution: cYellow
  readonly property color bad: cRed

  function levelColor(value) {
    switch (Model.errorLevel(value)) {
      case "exact": return root.good
      case "close": return root.good
      case "fair": return root.caution
      case "far": return root.bad
      default: return root.fg
    }
  }

  // ---- Choices remembered in shell.json.
  readonly property string series: hostWidget ? hostWidget.series : "E24"
  readonly property string packageCode: hostWidget ? hostWidget.packageCode : "0603"
  readonly property string tolerance: hostWidget ? hostWidget.tolerance : "1"
  // The last calculator used. Read from settings once, when the widget
  // first hands itself over, then owned here so clicks do not fight a binding.
  property string tab: "E-series"
  property bool tabRestored: false
  onHostWidgetChanged: {
    if (hostWidget && !tabRestored) {
      tab = Model.TABS.indexOf(hostWidget.tab) !== -1 ? hostWidget.tab : "E-series"
      tabRestored = true
    }
  }
  property string dividerMode: "Analyse"

  function remember(key, value) {
    if (hostWidget) hostWidget.persistSetting(key, value)
  }

  // ---- Engine.
  readonly property string enginePath: Model.localPath(Qt.resolvedUrl("bin/ee-calc"))
  property bool engineChecked: false
  property bool engineFound: false
  property var result: null
  property string errorText: ""
  property var pendingCommand: null
  // The command whose answer the panel wants now. A reply to anything else
  // (a field since cleared, a tab since left) is dropped on arrival.
  property string wantedKey: ""
  property string runningKey: ""
  property bool engineStarted: false
  property bool timedOut: false

  function request() {
    var args = buildArgs()
    if (args === null) {
      debounce.stop()
      pendingCommand = null
      wantedKey = ""
      result = null
      errorText = ""
      return
    }
    pendingCommand = [enginePath].concat(args)
    wantedKey = JSON.stringify(pendingCommand)
    debounce.restart()
  }

  function partArgs() {
    return ["--package", packageCode, "--tolerance", tolerance]
  }

  function buildArgs() {
    if (tab === "E-series") {
      if (valueField.text.trim() === "") return null
      return ["eseries", valueField.text, "--series", series].concat(partArgs())
    }
    if (dividerMode === "Analyse") {
      if (vinField.text.trim() === "" || r1Field.text.trim() === "" || r2Field.text.trim() === "") return null
      var a = ["divider", "--vin", vinField.text, "--r1", r1Field.text, "--r2", r2Field.text]
      if (rlField.text.trim() !== "") a.push("--rl", rlField.text)
      return a.concat(partArgs())
    }
    if (solveVinField.text.trim() === "" || voutField.text.trim() === "") return null
    var s = ["divider-solve", "--vin", solveVinField.text, "--vout", voutField.text, "--series", series]
    if (rminField.text.trim() !== "") s.push("--rmin", rminField.text)
    if (rmaxField.text.trim() !== "") s.push("--rmax", rmaxField.text)
    if (solveRlField.text.trim() !== "") s.push("--rl", solveRlField.text)
    return s.concat(partArgs())
  }

  function launch() {
    if (!engineFound || pendingCommand === null || engine.running) return
    runningKey = JSON.stringify(pendingCommand)
    engine.command = pendingCommand
    pendingCommand = null
    engineStarted = false
    timedOut = false
    engine.running = true
    watchdog.restart()
  }

  function receive(raw) {
    watchdog.stop()
    if (timedOut) return
    if (runningKey !== wantedKey) return
    var parsed = Model.parseResult(raw)
    if (parsed.ok) {
      result = parsed
      errorText = ""
    } else {
      result = null
      errorText = parsed.error
    }
  }

  // Typing "4k99" is four keystrokes; one engine run after the pause is enough.
  Timer {
    id: debounce
    interval: 120
    onTriggered: root.launch()
  }

  // A hung engine must never leave the panel waiting forever.
  Timer {
    id: watchdog
    interval: 3000
    onTriggered: {
      root.timedOut = true
      if (engine.running) engine.running = false
      root.result = null
      root.errorText = "The engine did not answer"
    }
  }

  Process {
    id: engine
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.receive(text)
    }
    onStarted: root.engineStarted = true
    onRunningChanged: {
      if (running) return
      // A binary that cannot be executed never starts and never prints, so
      // say so now instead of waiting for the watchdog.
      if (!root.engineStarted && !root.timedOut) {
        watchdog.stop()
        root.result = null
        root.errorText = "The engine could not be started"
      }
      if (root.pendingCommand !== null) Qt.callLater(root.launch)
    }
  }

  // The engine is a compiled binary that `omarchy plugin add` does not
  // build, so its absence is reported in the panel instead of failing quietly.
  Process {
    id: engineCheck
    command: ["test", "-x", root.enginePath]
    running: false
    onExited: function(exitCode, exitStatus) {
      root.engineChecked = true
      root.engineFound = exitCode === 0
      if (root.engineFound) root.request()
    }
  }

  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: {
      var toml = text()
      function pick(key, fallback) {
        var c = Model.themeColor(toml, key)
        return c !== "" ? c : fallback
      }
      root.cRed = pick("color1", Color.urgent)
      root.cGreen = pick("color2", Color.accent)
      root.cYellow = pick("color3", Color.accent)
      root.cPurple = pick("color4", Color.accent)
      root.cPink = pick("color5", Color.accent)
      root.cCyan = pick("color6", Color.accent)
    }
  }

  // Theme switches arrive over shell IPC and reassign shellValues even when
  // the accent is unchanged (the Dracula Pro variants share one), so that is
  // the signal to re-read the palette.
  Connections {
    target: Color
    function onShellValuesChanged() { themeColors.reload() }
  }

  // ---- Panel lifecycle.
  function open() {
    root.controller.show()
    // Re-checked on every open until found, so building the engine while
    // the shell runs is picked up without a restart.
    if (!engineFound && !engineCheck.running) engineCheck.running = true
    Qt.callLater(focusFirstField)
  }

  function close() {
    root.controller.hide()
    keyCatcher.forceActiveFocus()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function focusFirstField() {
    var f = tab === "E-series" ? valueField : (dividerMode === "Analyse" ? vinField : solveVinField)
    f.forceActiveFocus()
    f.selectAll()
  }

  function setTab(value) {
    tab = value
    remember("tab", value)
    result = null
    errorText = ""
    request()
    Qt.callLater(focusFirstField)
  }

  function setDividerMode(value) {
    dividerMode = value
    result = null
    errorText = ""
    request()
    Qt.callLater(focusFirstField)
  }

  function setSeries(value) {
    remember("series", value)
    Qt.callLater(request)
  }

  function setPackage(value) {
    remember("packageCode", value)
    Qt.callLater(request)
  }

  function setTolerance(value) {
    remember("tolerance", value)
    Qt.callLater(request)
  }

  // ---- Copying a part number. wl-copy ships with Omarchy; the number is
  // passed as one argv element, never through a shell.
  property string copiedMpn: ""

  function copyMpn(mpn) {
    if (!mpn || copier.running) return
    copier.command = ["wl-copy", "--", mpn]
    copier.running = true
    copiedMpn = mpn
    copiedReset.restart()
  }

  Process { id: copier; running: false }
  Timer { id: copiedReset; interval: 1500; onTriggered: root.copiedMpn = "" }

  // 5 % parts exist only in E24 values, so an E48/E96 result at 5 % has no
  // part. Say how to get one rather than only that there is none.
  readonly property bool seriesHint: tolerance === "5" && (series === "E48" || series === "E96")

  function loadColor(level) {
    if (level === "ok") return root.cGreen
    if (level === "high") return root.cYellow
    if (level === "over") return root.cRed
    return root.fg
  }

  function loadText(load, rating) {
    if (!load || !load.power) return ""
    return Model.text(load.power) + " of " + Model.text(rating) + "  (" + Math.round(load.pct) + " %)"
  }

  // Keys typed into a field belong to the field. Esc closes the panel in one
  // press, and Enter runs the engine at once instead of waiting out the
  // debounce.
  function fieldKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.close()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      debounce.stop()
      launch()
      event.accepted = true
    }
  }

  property Item focusedField: null
  function trackFocus(field) {
    if (field.activeFocus) focusedField = field
    else if (focusedField === field) focusedField = null
  }

  // One labelled input row. Every field feeds request() and routes its keys
  // through fieldKey(), so the rows differ only in label and placeholder.
  component Field: Row {
    id: fieldRow
    property alias label: fieldLabel.text
    property alias placeholder: input.placeholderText
    property alias text: input.text
    property alias input: input
    property string hint: ""
    width: parent ? parent.width : 0
    spacing: root.sp(10)

    function forceActiveFocus() { input.forceActiveFocus() }
    function selectAll() { input.selectAll() }

    Text {
      id: fieldLabel
      width: root.sp(96)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      color: root.cCyan
      font.family: root.fontFamily
      font.pixelSize: root.fs(Style.font.body)
    }

    TextField {
      id: input
      width: root.sp(110)
      anchors.verticalCenter: parent.verticalCenter
      foreground: root.cYellow
      font.family: root.fontFamily
      font.pixelSize: root.fs(Style.font.body)
      font.weight: Font.Medium
      selectByMouse: true
      onTextChanged: root.request()
      onActiveFocusChanged: root.trackFocus(input)
      Keys.onPressed: function(event) { root.fieldKey(event) }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: fieldRow.hint !== ""
      text: fieldRow.hint
      textFormat: Text.PlainText
      color: root.cPink
      opacity: 0.8
      font.family: root.fontFamily
      font.pixelSize: root.fs(Style.font.bodySmall)
    }
  }

  // A label on the left and a value on the right, for result rows.
  component Reading: Item {
    id: reading
    property string label: ""
    property string value: ""
    property string detail: ""
    property color valueColor: root.fg
    property color detailColor: root.fg
    property bool strong: false
    width: parent ? parent.width : 0
    height: root.sp(24)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: reading.label
      textFormat: Text.PlainText
      color: root.cCyan
      opacity: 0.85
      font.family: root.fontFamily
      font.pixelSize: root.fs(Style.font.body)
    }

    Row {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: root.sp(8)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: text !== ""
        text: reading.detail
        textFormat: Text.PlainText
        color: reading.detailColor
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: root.fs(Style.font.bodySmall)
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: reading.value
        textFormat: Text.PlainText
        color: reading.valueColor
        font.family: root.fontFamily
        font.pixelSize: reading.strong ? root.fs(Style.font.subtitle) : root.fs(Style.font.body)
        font.weight: reading.strong ? Font.Bold : Font.Medium
      }
    }
  }

  // Part numbers for one value, one row per maker. Clicking a number
  // copies it; a size Panasonic marks "not for new designs" says so.
  component PartList: Column {
    id: partList
    property string title: ""
    property var block: null
    readonly property var list: block && block.list ? block.list : []
    width: parent ? parent.width : 0
    spacing: root.sp(2)
    topPadding: root.sp(10)
    visible: block !== null
    // When the panel knows a better next step than the engine's note.
    property bool seriesHint: false

    Text {
      text: partList.title + (partList.block && partList.block.value ? "  " + Model.text(partList.block.value) : "")
      textFormat: Text.PlainText
      color: root.cPink
      font.family: root.fontFamily
      font.pixelSize: root.fs(Style.font.caption)
      font.letterSpacing: 1
      bottomPadding: root.sp(6)
    }

    // No part: laid out like a maker row, label left and reason right.
    Item {
      visible: partList.list.length === 0
      width: partList.width
      height: root.sp(22)

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: partList.seriesHint ? "No 5 % part" : "No part"
        textFormat: Text.PlainText
        color: root.cCyan
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: root.fs(Style.font.body)
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: partList.seriesHint ? "choose E24"
          : (partList.block && partList.block.note ? partList.block.note : "")
        textFormat: Text.PlainText
        color: root.cYellow
        font.family: root.fontFamily
        font.pixelSize: root.fs(Style.font.body)
        font.weight: Font.Medium
      }
    }

    Repeater {
      model: partList.list

      Item {
        id: partRow
        required property var modelData
        readonly property bool copied: root.copiedMpn === modelData.mpn
        width: partList.width
        height: root.sp(22)

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: partRow.modelData.maker
          textFormat: Text.PlainText
          color: root.cCyan
          opacity: 0.85
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.body)
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.sp(8)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: partRow.modelData.nrfnd === true
            text: "not for new designs"
            textFormat: Text.PlainText
            color: root.cRed
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: partRow.copied ? "copied" : Model.text(partRow.modelData.power)
            textFormat: Text.PlainText
            color: partRow.copied ? root.cGreen : root.fg
            opacity: partRow.copied ? 1.0 : 0.55
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.bodySmall)
          }

          Text {
            id: mpnText
            anchors.verticalCenter: parent.verticalCenter
            text: partRow.modelData.mpn
            textFormat: Text.PlainText
            color: root.cYellow
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
            font.weight: Font.Medium
            font.underline: mpnHover.hovered

            HoverHandler { id: mpnHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.copyMpn(partRow.modelData.mpn) }
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.sp(500))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    // While a field has focus every key is the field's: without this the
    // catcher eats k, h, l, x and Enter, and "4k7" arrives as "47".
    blocked: root.focusedField !== null
    onCloseRequested: root.close()
    // Typing with no field focused goes to the first field rather than nowhere.
    onTextKey: function(text) {
      root.focusFirstField()
      var f = root.focusedField
      if (f && typeof f.insert === "function") f.insert(f.cursorPosition, text)
    }
    onActivateRequested: { debounce.stop(); root.launch() }
    onTabRequested: function(direction) { root.switchPanel(direction) }

    Flickable {
      id: scroll
      anchors.fill: parent
      contentWidth: width
      contentHeight: content.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      interactive: contentHeight > height

      Column {
        id: content
        x: root.sp(16)
        width: scroll.width - root.sp(32)
        spacing: root.sp(10)

        Item { width: 1; height: root.sp(4) }

        // ---- Header.
        Item {
          width: parent.width
          height: tabs.implicitHeight

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.sp(6)

            Text {
              text: "EE"
              textFormat: Text.PlainText
              color: root.cPink
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.heading)
              font.weight: Font.Bold
            }
            Text {
              anchors.baseline: parent.children[0].baseline
              text: "Calc"
              textFormat: Text.PlainText
              color: root.cPurple
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.heading)
              font.weight: Font.Bold
            }
          }

          ButtonGroup {
            id: tabs
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: Model.TABS
            value: root.tab
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cPurple
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setTab(value) }
          }
        }

        PanelSeparator { width: parent.width }

        // ---- E-series.
        Column {
          width: parent.width
          spacing: root.sp(8)
          visible: root.tab === "E-series"

          Field {
            id: valueField
            label: "Value"
            text: "4k99"
            hint: "Ω  e.g. 4k7, 2R2, 1M5"
          }
        }

        // ---- Divider.
        Column {
          width: parent.width
          spacing: root.sp(8)
          visible: root.tab === "Divider"

          ButtonGroup {
            options: Model.DIVIDER_MODES
            value: root.dividerMode
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cPink
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setDividerMode(value) }
          }

          Item {
            width: parent.width
            height: Math.max(analyseFields.implicitHeight, root.sp(170))
            visible: root.dividerMode === "Analyse"

            Column {
              id: analyseFields
              width: parent.width - schematic.width
              spacing: root.sp(8)

              Field { id: vinField; label: "Vin"; text: "12"; hint: "V" }
              Field { id: r1Field; label: "R1 (top)"; text: "10k"; hint: "Ω" }
              Field { id: r2Field; label: "R2 (bottom)"; text: "2k2"; hint: "Ω" }
              Field { id: rlField; label: "Load"; placeholder: "optional"; hint: "Ω" }
            }

            // The divider as you have entered it, redrawn on every change:
            // Vin at the top, R1, the Vout node with its live value, R2 to
            // ground, and the load beside R2 when one is given.
            Canvas {
              id: schematic
              anchors.right: parent.right
              anchors.top: parent.top
              width: root.sp(215)
              height: parent.height

              readonly property var inputs: [
                vinField.text, r1Field.text, r2Field.text, rlField.text,
                root.result && root.result.vout ? root.result.vout.text : "",
                root.cRed, root.cGreen, root.cYellow, root.cPurple, root.cPink, root.cCyan,
                root.fg, root.fontFamily
              ]
              onInputsChanged: requestPaint()

              function resistor(ctx, x, y1, y2) {
                var lead = (y2 - y1) * 0.22
                var zig = (y2 - y1 - 2 * lead) / 6
                var w = root.sp(6)  // matches zigHalf in onPaint
                ctx.beginPath()
                ctx.moveTo(x, y1)
                ctx.lineTo(x, y1 + lead)
                for (var i = 0; i < 6; i++)
                  ctx.lineTo(x + (i % 2 === 0 ? w : -w), y1 + lead + zig * (i + 0.5))
                ctx.lineTo(x, y2 - lead)
                ctx.lineTo(x, y2)
                ctx.stroke()
              }

              function label(ctx, text, x, y, color, px, weight) {
                ctx.fillStyle = color
                ctx.font = (weight || 500) + " " + px + "px \"" + root.fontFamily + "\""
                ctx.fillText(text, x, y)
              }

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.lineWidth = Math.max(1.5, root.sp(1.6))
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.textBaseline = "middle"

                var px = root.fs(Style.font.bodySmall)
                // Laid out from the right: the load resistor's outer edge
                // meets the canvas edge, which is the right edge of the
                // results below, and the main column sits a fixed step to
                // its left whether or not a load is drawn. The node voltage
                // then reads to the left of the junction with room to spare.
                var zigHalf = root.sp(6)
                var lx = width - zigHalf - ctx.lineWidth
                var x = lx - root.sp(100)
                var top = root.sp(10)
                var mid = height * 0.5
                var gnd = height - root.sp(24)
                var loaded = rlField.text.trim() !== ""
                var vout = root.result && root.result.vout ? root.result.vout.text : "?"

                // Vin terminal.
                ctx.strokeStyle = root.cYellow
                ctx.fillStyle = root.cYellow
                ctx.beginPath(); ctx.arc(x, top, root.sp(3), 0, 2 * Math.PI); ctx.fill()
                label(ctx, (vinField.text || "?") + " V", x + root.sp(12), top, root.cYellow, px, 600)

                // R1.
                ctx.strokeStyle = root.cPink
                resistor(ctx, x, top + root.sp(4), mid)
                label(ctx, "R1 " + (r1Field.text || "?"), x + root.sp(14), (top + mid) / 2, root.cPink, px)

                // R2.
                ctx.strokeStyle = root.cPurple
                resistor(ctx, x, mid, gnd)
                label(ctx, "R2 " + (r2Field.text || "?"), x + root.sp(14), (mid + gnd) / 2, root.cPurple, px)

                // Load, dashed, to the right of R2. It taps off just below
                // the Vout node so its wire never runs through the Vout
                // label, and its value sits under the ground return.
                if (loaded) {
                  var tap = mid + root.sp(10)
                  ctx.strokeStyle = root.cCyan
                  ctx.fillStyle = root.cCyan
                  ctx.setLineDash([root.sp(3), root.sp(3)])
                  ctx.beginPath(); ctx.moveTo(x, tap); ctx.lineTo(lx, tap); ctx.stroke()
                  ctx.beginPath(); ctx.moveTo(x, gnd); ctx.lineTo(lx, gnd); ctx.stroke()
                  ctx.setLineDash([])
                  resistor(ctx, lx, tap, gnd)
                  ctx.beginPath(); ctx.arc(x, tap, root.sp(2.5), 0, 2 * Math.PI); ctx.fill()
                  ctx.textAlign = "right"
                  label(ctx, "RL " + rlField.text, width, gnd + root.sp(11), root.cCyan, px)
                  ctx.textAlign = "start"
                }

                // Vout node, drawn last so it sits on top of the wires. Its
                // value reads level with the node, on the side no wire uses.
                ctx.fillStyle = root.cGreen
                ctx.beginPath(); ctx.arc(x, mid, root.sp(3.5), 0, 2 * Math.PI); ctx.fill()
                ctx.textAlign = "right"
                label(ctx, vout, x - root.sp(10), mid, root.cGreen, root.fs(Style.font.body), 700)
                ctx.textAlign = "start"

                // Ground.
                ctx.strokeStyle = root.fg
                ctx.globalAlpha = 0.7
                var g = root.sp(9)
                for (var k = 0; k < 3; k++) {
                  var hw = g - k * root.sp(3)
                  ctx.beginPath()
                  ctx.moveTo(x - hw, gnd + k * root.sp(4))
                  ctx.lineTo(x + hw, gnd + k * root.sp(4))
                  ctx.stroke()
                }
                ctx.globalAlpha = 1
              }
            }
          }

          Column {
            width: parent.width
            spacing: root.sp(8)
            visible: root.dividerMode === "Find values"

            Field { id: solveVinField; label: "Vin"; text: "12"; hint: "V" }
            Field { id: voutField; label: "Target Vout"; text: "3.3"; hint: "V" }
            Field { id: rminField; label: "Min R1+R2"; text: "10k"; hint: "Ω" }
            Field { id: rmaxField; label: "Max R1+R2"; text: "1M"; hint: "Ω" }
            Field { id: solveRlField; label: "Load"; placeholder: "optional"; hint: "Ω" }
          }
        }

        // ---- Series choice, shared by combinations and divider design.
        Item {
          width: parent.width
          height: seriesGroup.implicitHeight
          visible: root.tab === "E-series" || root.dividerMode === "Find values"

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Series"
            textFormat: Text.PlainText
            color: root.cCyan
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
          }

          ButtonGroup {
            id: seriesGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: Model.SERIES
            value: root.series
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cCyan
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setSeries(value) }
          }
        }

        // ---- Package and tolerance: drive the part numbers and the power
        //      check on every tab.
        Item {
          width: parent.width
          height: packageGroup.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Package"
            textFormat: Text.PlainText
            color: root.cCyan
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
          }

          ButtonGroup {
            id: packageGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: Model.PACKAGES
            value: root.packageCode
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cGreen
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setPackage(value) }
          }
        }

        Item {
          width: parent.width
          height: toleranceGroup.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Tolerance"
            textFormat: Text.PlainText
            color: root.cCyan
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
          }

          ButtonGroup {
            id: toleranceGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            options: Model.TOLERANCES
            value: root.tolerance
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cYellow
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setTolerance(value) }
          }
        }

        PanelSeparator { width: parent.width }

        // ---- Status: missing engine, or the engine's own error message.
        Text {
          width: parent.width
          visible: text !== ""
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.engineChecked && !root.engineFound
            ? "The calculator program bin/ee-calc is missing. Reinstall the plugin, or build it from source (see the README on GitHub)."
            : root.errorText
          color: root.bad
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.body)
        }

        Text {
          width: parent.width
          visible: root.result === null && root.errorText === "" && root.engineFound
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: root.tab === "E-series"
            ? "Type a value to see the nearest standard parts."
            : (root.dividerMode === "Analyse" ? "Enter Vin, R1 and R2." : "Enter Vin and the Vout you need.")
          color: root.cCyan
          opacity: 0.8
          font.family: root.fontFamily
          font.pixelSize: root.fs(Style.font.body)
        }

        // ---- E-series results.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "E-series" && root.result !== null && root.result.table !== undefined

          // Column heads.
          Item {
            width: parent.width
            height: root.sp(20)

            Repeater {
              model: [
                { text: "Series", x: 0 },
                { text: "Nearest", x: 0.2 },
                { text: "Error", x: 0.42 },
                { text: "Below / above", x: 0.64 }
              ]

              Text {
                required property var modelData
                x: parent.width * modelData.x
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.text
                textFormat: Text.PlainText
                color: root.cPink
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
                font.letterSpacing: 1
              }
            }
          }

          Repeater {
            model: root.result && root.result.table ? root.result.table : []

            Item {
              id: seriesRow
              required property var modelData
              readonly property bool chosen: modelData.series === root.series
              width: parent.width
              height: root.sp(24)

              Text {
                x: 0
                anchors.verticalCenter: parent.verticalCenter
                text: seriesRow.modelData.series
                textFormat: Text.PlainText
                color: seriesRow.chosen ? root.cPink : root.cPurple
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.body)
                font.weight: seriesRow.chosen ? Font.Medium : Font.Normal
              }

              Text {
                x: parent.width * 0.2
                anchors.verticalCenter: parent.verticalCenter
                text: Model.text(seriesRow.modelData.nearest)
                textFormat: Text.PlainText
                color: seriesRow.chosen ? root.cPink : root.fg
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.body)
                font.weight: seriesRow.chosen ? Font.Bold : Font.Medium
              }

              Text {
                x: parent.width * 0.42
                anchors.verticalCenter: parent.verticalCenter
                text: seriesRow.modelData.exact ? "exact" : Model.pct(seriesRow.modelData.nearestErrorPct)
                textFormat: Text.PlainText
                color: root.levelColor(seriesRow.modelData.nearestErrorPct)
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.body)
                font.weight: Font.Medium
              }

              Text {
                x: parent.width * 0.64
                anchors.verticalCenter: parent.verticalCenter
                visible: !seriesRow.modelData.exact
                text: Model.text(seriesRow.modelData.below) + "  /  " + Model.text(seriesRow.modelData.above)
                textFormat: Text.PlainText
                color: root.cCyan
                opacity: 0.75
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
            }
          }

          Item { width: 1; height: root.sp(6) }

          PanelSectionHeader {
            fontSize: root.fs(Style.font.caption)
            text: "TWO " + root.series + " PARTS"
            foreground: root.cPink
            fontFamily: root.fontFamily
          }

          Reading {
            readonly property var pair: root.result && root.result.pairs ? root.result.pairs.series : null
            label: "In series"
            value: pair ? Model.text(pair.a) + " + " + Model.text(pair.b) : "—"
            valueColor: root.cPurple
            detail: pair ? Model.pct(pair.errorPct) : ""
            detailColor: pair ? root.levelColor(pair.errorPct) : root.fg
          }

          Reading {
            id: parallelReading
            readonly property var pair: root.result && root.result.pairs ? root.result.pairs.parallel : null
            label: "In parallel"
            value: pair ? Model.text(pair.a) + " || " + Model.text(pair.b) : "—"
            valueColor: root.cPurple
            detail: pair ? Model.pct(pair.errorPct) : ""
            detailColor: pair ? root.levelColor(pair.errorPct) : root.fg
          }

          Item { width: 1; height: root.sp(6) }

          PartList {
            title: root.series + " PART  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            seriesHint: root.seriesHint
            block: root.result && root.result.parts ? root.result.parts : null
          }
        }

        // ---- Divider analysis results.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "Divider" && root.dividerMode === "Analyse" && root.result !== null && root.result.vout !== undefined

          Reading {
            label: "Vout"
            value: root.result ? Model.text(root.result.vout) : ""
            valueColor: root.cGreen
            strong: true
          }
          Reading {
            visible: root.result !== null && root.result.loaded === true
            label: "Vout without load"
            value: root.result ? Model.text(root.result.voutUnloaded) : ""
            valueColor: root.cGreen
          }
          Reading {
            label: "Ratio"
            value: root.result && typeof root.result.ratio === "number" ? root.result.ratio.toFixed(5) : ""
            valueColor: root.cPurple
          }
          Reading {
            label: "Current in R1"
            value: root.result ? Model.text(root.result.current) : ""
            valueColor: root.cCyan
          }
          Reading {
            label: "Power R1"
            value: root.result ? root.loadText(root.result.loadR1, root.result.rating) : ""
            valueColor: root.result && root.result.loadR1 ? root.loadColor(root.result.loadR1.level) : root.cYellow
          }
          Reading {
            label: "Power R2"
            value: root.result ? root.loadText(root.result.loadR2, root.result.rating) : ""
            valueColor: root.result && root.result.loadR2 ? root.loadColor(root.result.loadR2.level) : root.cYellow
          }
          Reading {
            visible: root.result !== null && root.result.loaded === true
            label: "Load current / power"
            value: root.result ? Model.text(root.result.loadCurrent) + "  /  " + Model.text(root.result.pLoad) : ""
            valueColor: root.cYellow
          }
          Reading {
            label: "Source resistance"
            value: root.result ? Model.text(root.result.sourceResistance) : ""
            valueColor: root.cPink
            detail: "R1 || R2"
            detailColor: root.cPurple
          }

          Item { width: 1; height: root.sp(6) }

          PartList {
            title: "R1  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            block: root.result && root.result.partsR1 ? root.result.partsR1 : null
          }
          PartList {
            title: "R2  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            block: root.result && root.result.partsR2 ? root.result.partsR2 : null
          }
        }

        // ---- Divider design results.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "Divider" && root.dividerMode === "Find values" && root.result !== null && root.result.candidates !== undefined

          Item {
            width: parent.width
            height: root.sp(20)

            Repeater {
              model: [
                { text: "R1", x: 0 },
                { text: "R2", x: 0.2 },
                { text: "Vout", x: 0.4 },
                { text: "Error", x: 0.6 },
                { text: "Current", x: 0.8 }
              ]

              Text {
                required property var modelData
                x: parent.width * modelData.x
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.text
                textFormat: Text.PlainText
                color: root.cPink
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.caption)
                font.letterSpacing: 1
              }
            }
          }

          Repeater {
            model: root.result && root.result.candidates ? root.result.candidates : []

            Item {
              id: candidateRow
              required property var modelData
              required property int index
              width: parent.width
              height: root.sp(24)

              Repeater {
                model: [
                  { text: Model.text(candidateRow.modelData.r1), x: 0,
                    tint: Model.overloaded(candidateRow.modelData.loadR1) ? root.cRed : root.cPink },
                  { text: Model.text(candidateRow.modelData.r2), x: 0.2,
                    tint: Model.overloaded(candidateRow.modelData.loadR2) ? root.cRed : root.cPurple },
                  { text: Model.text(candidateRow.modelData.vout), x: 0.4, tint: root.cGreen },
                  { text: Model.pct(candidateRow.modelData.errorPct), x: 0.6, err: true },
                  { text: Model.text(candidateRow.modelData.current), x: 0.8, tint: root.cCyan }
                ]

                Text {
                  required property var modelData
                  x: candidateRow.width * modelData.x
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.text
                  textFormat: Text.PlainText
                  color: modelData.err ? root.levelColor(candidateRow.modelData.errorPct) : modelData.tint
                  opacity: candidateRow.index === 0 || modelData.err ? 1.0 : 0.8
                  font.family: root.fontFamily
                  font.pixelSize: root.fs(Style.font.body)
                  font.weight: candidateRow.index === 0 && !modelData.err ? Font.Bold : Font.Medium
                }
              }
            }
          }

          Item { width: 1; height: root.sp(6) }

          PartList {
            title: "BEST R1  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            seriesHint: root.seriesHint
            block: root.result && root.result.partsR1 ? root.result.partsR1 : null
          }
          PartList {
            title: "BEST R2  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            seriesHint: root.seriesHint
            block: root.result && root.result.partsR2 ? root.result.partsR2 : null
          }

          Text {
            width: parent.width
            visible: root.result !== null && root.result.candidates !== undefined && root.result.candidates.length === 0
            text: "No " + root.series + " pair fits that total resistance range."
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: root.bad
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
          }
        }

        Item { width: 1; height: root.sp(6) }
      }
    }
  }
  }
}
