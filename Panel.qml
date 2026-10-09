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
  property string codesMode: "Value"
  property string ledMode: "LED"
  property string rclcMode: "RC"

  // The colour bands being edited in Codes > Bands, and the band whose
  // colour the picker is showing (-1 for none).
  property var bandColours: ["yellow", "violet", "black", "brown", "brown"]
  property int selectedBand: -1

  // Which shared rows a calculator uses.
  readonly property bool usesSeries: tab === "E-series"
    || (tab === "Divider" && dividerMode === "Find values")
    || (tab === "LED / Ohm" && ledMode === "LED")
    || (tab === "RC / LC" && rclcMode === "RC")
  readonly property bool usesParts: tab === "E-series" || tab === "Divider" || tab === "Codes"
    || (tab === "LED / Ohm" && ledMode === "LED")

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

  // Optional fields go to the engine only when filled in: in the
  // any-two-of calculators an empty field is the one to work out.
  function addIfFilled(args, option, field) {
    if (field.text.trim() !== "") args.push(option, field.text)
  }

  // The any-two-of calculators wait for a second value instead of
  // reporting one as an error; three or more go to the engine, which says
  // why that does not work.
  function filledCount(fields) {
    var n = 0
    for (var i = 0; i < fields.length; i++) if (fields[i].text.trim() !== "") n++
    return n
  }

  function buildArgs() {
    if (tab === "E-series") {
      if (valueField.text.trim() === "") return null
      return ["eseries", valueField.text, "--series", series].concat(partArgs())
    }
    if (tab === "Codes") {
      if (codesMode === "Value") {
        if (codesValueField.text.trim() === "") return null
        return ["codes", codesValueField.text].concat(partArgs())
      }
      if (codesMode === "SMD code") {
        if (markingField.text.trim() === "") return null
        return ["marking", markingField.text].concat(partArgs())
      }
      return ["bands", bandColours.join(",")].concat(partArgs())
    }
    if (tab === "LED / Ohm") {
      if (ledMode === "LED") {
        if (ledVsField.text.trim() === "" || ledVfField.text.trim() === "" || ledIfField.text.trim() === "") return null
        var l = ["led", "--vs", ledVsField.text, "--vf", ledVfField.text, "--if", ledIfField.text, "--series", series]
        addIfFilled(l, "--count", ledCountField)
        return l.concat(partArgs())
      }
      if (filledCount([ohmVField, ohmIField, ohmRField, ohmPField]) < 2) return null
      var o = ["ohm"]
      addIfFilled(o, "--v", ohmVField)
      addIfFilled(o, "--i", ohmIField)
      addIfFilled(o, "--r", ohmRField)
      addIfFilled(o, "--p", ohmPField)
      return o
    }
    if (tab === "RC / LC") {
      if (rclcMode === "RC") {
        if (filledCount([rcRField, rcCField, rcFField, rcTauField]) < 2) return null
        var r = ["rc", "--series", series]
        addIfFilled(r, "--r", rcRField)
        addIfFilled(r, "--c", rcCField)
        addIfFilled(r, "--f", rcFField)
        addIfFilled(r, "--tau", rcTauField)
        return r
      }
      if (filledCount([lcLField, lcCField, lcFField]) < 2) return null
      var c = ["lc"]
      addIfFilled(c, "--l", lcLField)
      addIfFilled(c, "--c", lcCField)
      addIfFilled(c, "--f", lcFField)
      return c
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

  // The header version comes from manifest.json, so it can't drift from it.
  property string version: ""

  FileView {
    path: Model.localPath(Qt.resolvedUrl("manifest.json"))
    watchChanges: false
    printErrors: false
    onLoaded: {
      try { root.version = String(JSON.parse(text()).version || "") } catch (e) { root.version = "" }
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

  function firstField() {
    switch (tab) {
      case "E-series": return valueField
      case "Divider": return dividerMode === "Analyse" ? vinField : solveVinField
      case "Codes":
        if (codesMode === "Value") return codesValueField
        return codesMode === "SMD code" ? markingField : null
      case "LED / Ohm": return ledMode === "LED" ? ledVsField : ohmVField
      default: return rclcMode === "RC" ? rcRField : lcLField
    }
  }

  function focusFirstField() {
    var f = firstField()
    // Codes > Bands has no text field; keys then stay with the panel.
    if (f === null) { keyCatcher.forceActiveFocus(); return }
    f.forceActiveFocus()
    f.selectAll()
  }

  function setTab(value) {
    tab = value
    selectedBand = -1
    remember("tab", value)
    result = null
    errorText = ""
    request()
    Qt.callLater(focusFirstField)
  }

  function setMode(name, value) {
    root[name] = value
    selectedBand = -1
    result = null
    errorText = ""
    request()
    Qt.callLater(focusFirstField)
  }

  function setDividerMode(value) { setMode("dividerMode", value) }

  function setBandCount(count) {
    bandColours = Model.changeBandCount(bandColours, count)
    selectedBand = -1
    request()
  }

  function setBandColour(index, colour) {
    var b = bandColours.slice()
    b[index] = colour
    bandColours = b
    request()
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

  // ---- The ? button: the manual section for this screen, in the browser.
  function currentMode() {
    switch (tab) {
      case "Divider": return dividerMode
      case "Codes": return codesMode
      case "LED / Ohm": return ledMode
      case "RC / LC": return rclcMode
      default: return ""
    }
  }

  function openManual() {
    if (opener.running) return
    opener.command = ["xdg-open", Model.manualUrl(version, tab, currentMode())]
    opener.running = true
    root.close()
  }

  Process { id: opener; running: false }
  Timer { id: copiedReset; interval: 1500; onTriggered: root.copiedMpn = "" }

  // 5 % parts exist only in E24 values, so an E48/E96/E192 result at 5 %
  // has no part. Say how to get one rather than only that there is none.
  readonly property bool seriesHint: tolerance === "5" && (series === "E48" || series === "E96" || series === "E192")

  function loadColor(level) {
    if (level === "ok") return root.cGreen
    if (level === "high") return root.cYellow
    if (level === "over") return root.cRed
    return root.fg
  }

  function loadText(load, rating) {
    if (!load || !load.power) return ""
    // Below 1 % rounds to "0 %", which reads as no power at all.
    var pct = load.pct > 0 && load.pct < 1 ? "<1" : String(Math.round(load.pct))
    return Model.text(load.power) + " of " + Model.text(rating) + "  (" + pct + " %)"
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
  component PowerScope: Text {
    width: parent ? parent.width : 0
    text: "Nominal power only. Check voltage rating and thermal derating separately."
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: root.fg
    opacity: 0.85
    font.family: root.fontFamily
    font.pixelSize: root.fs(Style.font.bodySmall)
  }

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
    readonly property bool showSeriesHint: seriesHint && Model.suggestE24(block)

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
        text: partList.showSeriesHint ? "No 5 % part" : "No part"
        textFormat: Text.PlainText
        color: root.cCyan
        opacity: 0.85
        font.family: root.fontFamily
        font.pixelSize: root.fs(Style.font.body)
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: partList.showSeriesHint ? "choose E24"
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

  // The standard part nearest a value the RC/LC calculators worked out,
  // and what using it gives instead.
  component SuggestBlock: Column {
    id: suggest
    property var suggestion: null
    property string part: ""
    property string effect: ""
    width: parent ? parent.width : 0
    spacing: root.sp(2)
    topPadding: root.sp(8)
    visible: suggestion !== null

    PanelSectionHeader {
      fontSize: root.fs(Style.font.caption)
      text: "NEAREST " + (suggest.suggestion ? suggest.suggestion.series : "") + " " + suggest.part
      foreground: root.cPink
      fontFamily: root.fontFamily
    }
    Reading {
      label: suggest.part
      value: suggest.suggestion ? Model.text(suggest.suggestion.value) : ""
      valueColor: root.cPink
      strong: true
      detail: suggest.effect
      detailColor: root.cGreen
    }
  }

  // A through-hole resistor with its colour bands, laid out the way parts
  // are printed: the value bands together at one end, the tolerance band
  // (and the temperature coefficient band) set apart at the other. When
  // editable, a click on a band selects it for the colour picker.
  component BandResistor: Item {
    id: resistor
    property var bands: []
    property bool editable: false
    property int selected: -1
    signal bandClicked(int index)

    readonly property real bodyW: root.sp(230)
    readonly property real bodyH: root.sp(46)
    readonly property real lead: root.sp(34)
    readonly property real bandW: root.sp(14)
    readonly property real step: root.sp(26)
    // Digits and multiplier, then the rest after the gap.
    readonly property int headCount: bands.length === 4 ? 3 : 4
    width: bodyW + 2 * lead
    height: bodyH + root.sp(14)

    Rectangle {
      y: (resistor.bodyH - height) / 2
      width: parent.width
      height: root.sp(3)
      color: "#9A9A9A"
    }

    Rectangle {
      id: body
      x: resistor.lead
      width: resistor.bodyW
      height: resistor.bodyH
      radius: height * 0.35
      color: "#D8C7A0"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.35)
    }

    Repeater {
      model: resistor.bands

      Item {
        id: bandSlot
        required property var modelData
        required property int index
        readonly property bool head: index < resistor.headCount
        readonly property real tailStart: body.x + body.width - root.sp(30) - resistor.bandW
          - (resistor.bands.length - resistor.headCount - 1) * resistor.step
        readonly property bool isSelected: resistor.editable && resistor.selected === index
        x: (head ? body.x + root.sp(30) + index * resistor.step
                 : tailStart + (index - resistor.headCount) * resistor.step) - (resistor.step - resistor.bandW) / 2
        width: resistor.step
        height: resistor.height

        Rectangle {
          x: (parent.width - width) / 2
          y: 1
          width: resistor.bandW
          height: resistor.bodyH - 2
          color: Model.BAND_PAINT[bandSlot.modelData] || "transparent"
          border.width: bandSlot.modelData === "none" ? 1 : 0
          border.color: Qt.rgba(0, 0, 0, 0.45)
          opacity: bandSlot.modelData === "none" ? 0.6 : 1
        }

        // Marker under the selected band.
        Rectangle {
          visible: bandSlot.isSelected
          x: (parent.width - width) / 2
          y: resistor.bodyH + root.sp(5)
          width: resistor.bandW
          height: root.sp(4)
          radius: height / 2
          color: root.cPink
        }

        HoverHandler { enabled: resistor.editable; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: resistor.editable; onTapped: resistor.bandClicked(bandSlot.index) }
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

        // ---- Header: the name, then the calculators on a row of their own.
        Item {
          width: parent.width
          height: title.implicitHeight

          Row {
            id: title
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
            Text {
              anchors.baseline: parent.children[0].baseline
              visible: root.version !== ""
              text: "v" + root.version
              textFormat: Text.PlainText
              color: root.fg
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.body)
            }
          }

          // Help for the screen you're on.
          Rectangle {
            id: helpButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: root.sp(24)
            height: root.sp(24)
            radius: width / 2
            color: "transparent"
            border.width: 1
            border.color: helpHover.hovered ? root.cCyan : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.4)

            Text {
              anchors.centerIn: parent
              text: "?"
              textFormat: Text.PlainText
              color: helpHover.hovered ? root.cCyan : root.fg
              opacity: helpHover.hovered ? 1 : 0.7
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.body)
              font.weight: Font.Bold
            }

            HoverHandler { id: helpHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.openManual() }
          }
        }

        ButtonGroup {
          id: tabs
          options: Model.TABS
          value: root.tab
          focusable: false
          fontSize: root.fs(Style.font.body)
          foreground: root.cPurple
          fontFamily: root.fontFamily
          onChanged: function(value) { root.setTab(value) }
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

        // ---- Codes.
        Column {
          width: parent.width
          spacing: root.sp(8)
          visible: root.tab === "Codes"

          ButtonGroup {
            options: Model.CODES_MODES
            value: root.codesMode
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cPink
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setMode("codesMode", value) }
          }

          Field {
            id: codesValueField
            visible: root.codesMode === "Value"
            label: "Value"
            text: "4k99"
            hint: "Ω  e.g. 4k7, 2R2, 1M5"
          }

          Field {
            id: markingField
            visible: root.codesMode === "SMD code"
            label: "Code"
            text: "4991"
            hint: "e.g. 472, 4991, 4R7, 68C"
          }

          // Bands: pick a count, click a band, pick its colour.
          Column {
            width: parent.width
            spacing: root.sp(8)
            visible: root.codesMode === "Bands"

            ButtonGroup {
              options: Model.BAND_COUNTS
              value: String(root.bandColours.length)
              focusable: false
              fontSize: root.fs(Style.font.body)
              foreground: root.cCyan
              fontFamily: root.fontFamily
              onChanged: function(value) { root.setBandCount(parseInt(value, 10)) }
            }

            BandResistor {
              anchors.horizontalCenter: parent.horizontalCenter
              bands: root.bandColours
              editable: true
              selected: root.selectedBand
              onBandClicked: function(index) { root.selectedBand = root.selectedBand === index ? -1 : index }
            }

            Text {
              width: parent.width
              horizontalAlignment: Text.AlignHCenter
              textFormat: Text.PlainText
              text: root.selectedBand < 0
                ? "Click a band to change its colour."
                : "Band " + (root.selectedBand + 1) + ", " + Model.BAND_ROLE_NAMES[Model.bandRole(root.bandColours.length, root.selectedBand)]
                  + ": " + root.bandColours[root.selectedBand]
              color: root.cCyan
              opacity: 0.85
              font.family: root.fontFamily
              font.pixelSize: root.fs(Style.font.bodySmall)
            }

            // The colours that band may take.
            Flow {
              width: parent.width
              spacing: root.sp(6)
              visible: root.selectedBand >= 0

              Repeater {
                model: root.selectedBand >= 0
                  ? Model.bandChoices(Model.bandRole(root.bandColours.length, root.selectedBand), root.bandColours.length) : []

                Rectangle {
                  id: swatch
                  required property var modelData
                  readonly property bool current: root.bandColours[root.selectedBand] === modelData
                  width: swatchLabel.implicitWidth + root.sp(28)
                  height: root.sp(24)
                  radius: root.sp(4)
                  color: "transparent"
                  border.width: current ? 2 : 1
                  border.color: current ? root.cPink : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)

                  Rectangle {
                    x: root.sp(6)
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.sp(12)
                    height: root.sp(12)
                    radius: root.sp(2)
                    color: Model.BAND_PAINT[swatch.modelData]
                    border.width: 1
                    border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.5)
                  }

                  Text {
                    id: swatchLabel
                    x: root.sp(22)
                    anchors.verticalCenter: parent.verticalCenter
                    text: swatch.modelData
                    textFormat: Text.PlainText
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: root.fs(Style.font.bodySmall)
                  }

                  HoverHandler { cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: root.setBandColour(root.selectedBand, swatch.modelData) }
                }
              }
            }
          }
        }

        // ---- LED and Ohm's law.
        Column {
          width: parent.width
          spacing: root.sp(8)
          visible: root.tab === "LED / Ohm"

          ButtonGroup {
            options: Model.LED_MODES
            value: root.ledMode
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cPink
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setMode("ledMode", value) }
          }

          Column {
            width: parent.width
            spacing: root.sp(8)
            visible: root.ledMode === "LED"

            Field { id: ledVsField; label: "Supply"; text: "5"; hint: "V" }
            Field { id: ledVfField; label: "LED Vf"; text: "2"; hint: "V  forward voltage" }
            Field { id: ledIfField; label: "Current"; text: "10m"; hint: "A  e.g. 20m" }
            Field { id: ledCountField; label: "In series"; text: "1"; hint: "LEDs" }
          }

          Column {
            width: parent.width
            spacing: root.sp(8)
            visible: root.ledMode === "Ohm's law"

            Field { id: ohmVField; label: "Voltage"; text: "12"; hint: "V" }
            Field { id: ohmIField; label: "Current"; placeholder: "blank to work out"; hint: "A" }
            Field { id: ohmRField; label: "Resistance"; text: "1k"; hint: "Ω" }
            Field { id: ohmPField; label: "Power"; placeholder: "blank to work out"; hint: "W" }
          }
        }

        // ---- RC and LC.
        Column {
          width: parent.width
          spacing: root.sp(8)
          visible: root.tab === "RC / LC"

          ButtonGroup {
            options: Model.RCLC_MODES
            value: root.rclcMode
            focusable: false
            fontSize: root.fs(Style.font.body)
            foreground: root.cPink
            fontFamily: root.fontFamily
            onChanged: function(value) { root.setMode("rclcMode", value) }
          }

          Column {
            width: parent.width
            spacing: root.sp(8)
            visible: root.rclcMode === "RC"

            Field { id: rcRField; label: "R"; text: "10k"; hint: "Ω" }
            Field { id: rcCField; label: "C"; text: "100n"; hint: "F" }
            Field { id: rcFField; label: "Cutoff"; placeholder: "blank to work out"; hint: "Hz" }
            Field { id: rcTauField; label: "Time const."; placeholder: "or give this"; hint: "s  instead of cutoff" }
          }

          Column {
            width: parent.width
            spacing: root.sp(8)
            visible: root.rclcMode === "LC"

            Field { id: lcLField; label: "L"; text: "10u"; hint: "H" }
            Field { id: lcCField; label: "C"; text: "100n"; hint: "F" }
            Field { id: lcFField; label: "Resonance"; placeholder: "blank to work out"; hint: "Hz" }
          }
        }

        // ---- Series choice, shared by combinations and divider design.
        Item {
          width: parent.width
          height: seriesGroup.implicitHeight
          visible: root.usesSeries

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
          visible: root.usesParts

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
          visible: root.usesParts

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
            ? "The calculator program bin/ee-calc is missing. Reinstall the plugin using the README installation instructions."
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
          text: {
            switch (root.tab) {
              case "E-series": return "Type a value to see the nearest standard parts."
              case "Divider": return root.dividerMode === "Analyse" ? "Enter Vin, R1 and R2." : "Enter Vin and the Vout you need."
              case "Codes":
                if (root.codesMode === "Value") return "Type a value to see its codes and bands."
                return root.codesMode === "SMD code" ? "Type the code printed on the part." : "Click a band to change its colour."
              case "LED / Ohm": return root.ledMode === "LED" ? "Enter the supply, the LED's Vf and the current." : "Enter any two of V, I, R and P."
              default: return root.rclcMode === "RC" ? "Enter any two of R, C and the cutoff (or time constant)." : "Enter any two of L, C and the resonant frequency."
            }
          }
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

          PowerScope { }

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

          PowerScope { }

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

        // ---- Codes: value to codes and bands.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "Codes" && root.codesMode === "Value" && root.result !== null && root.result.smd !== undefined
          readonly property var smd: root.result && root.result.smd ? root.result.smd : ({})

          Reading {
            label: "Value"
            value: root.result ? Model.text(root.result.value) : ""
            valueColor: root.cGreen
            strong: true
            detail: root.result && root.result.series ? root.result.series + " value" : "not a standard value"
            detailColor: root.cPurple
          }
          Reading {
            label: "3-digit code"
            value: parent.smd.three || "—"
            valueColor: root.cYellow
            detail: parent.smd.three ? "E24 parts, 2 % and 5 %" : "no 3-digit code for this value"
            detailColor: root.cPurple
          }
          Reading {
            label: "4-digit code"
            value: parent.smd.four || "—"
            valueColor: root.cYellow
            detail: parent.smd.four ? "1 % and better" : "no 4-digit code for this value"
            detailColor: root.cPurple
          }
          Reading {
            label: "EIA-96 code"
            value: parent.smd.eia96 || "—"
            valueColor: root.cYellow
            detail: parent.smd.eia96 ? "0603 parts, 1 % and better" : "E96 values, 1 Ω to 97.6 MΩ"
            detailColor: root.cPurple
          }

          Item { width: 1; height: root.sp(8) }

          PanelSectionHeader {
            visible: root.result !== null && !!root.result.bands
            fontSize: root.fs(Style.font.caption)
            text: "COLOUR BANDS  " + (root.result ? root.result.tolerance : "")
            foreground: root.cPink
            fontFamily: root.fontFamily
          }

          Text {
            visible: root.result !== null && root.result.smd !== undefined && !root.result.bands
            width: parent.width
            textFormat: Text.PlainText
            text: "This encoder cannot represent this value with four or five bands."
            color: root.cCyan
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
          }

          BandResistor {
            visible: root.result !== null && !!root.result.bands
            anchors.horizontalCenter: parent.horizontalCenter
            bands: root.result && root.result.bands ? root.result.bands : []
          }

          Text {
            visible: root.result !== null && !!root.result.bands
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: root.result && root.result.bands ? root.result.bands.join("  ") : ""
            color: root.cCyan
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
          }

          PartList {
            title: "PART  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            block: root.result && root.result.parts ? root.result.parts : null
          }
        }

        // ---- Codes: SMD code to value. A code can have more than one
        //      reading ("10R"); each gets its own value and parts.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "Codes" && root.codesMode === "SMD code" && root.result !== null && root.result.readings !== undefined

          Text {
            width: parent.width
            visible: root.result !== null && !!root.result.readings && root.result.readings.length > 1
            wrapMode: Text.Wrap
            textFormat: Text.PlainText
            text: root.result && root.result.readings ? "This code reads " + root.result.readings.length + " ways. The part's datasheet or its size says which." : ""
            color: root.caution
            font.family: root.fontFamily
            font.pixelSize: root.fs(Style.font.body)
            bottomPadding: root.sp(6)
          }

          Repeater {
            model: root.result && root.result.readings ? root.result.readings : []

            Column {
              id: readingBlock
              required property var modelData
              required property int index
              width: parent.width
              spacing: root.sp(2)

              Reading {
                label: readingBlock.modelData.scheme
                value: Model.text(readingBlock.modelData.value)
                valueColor: root.cGreen
                strong: true
                detail: readingBlock.modelData.series ? readingBlock.modelData.series + " value" : ""
                detailColor: root.cPurple
              }
              Text {
                width: parent.width
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: readingBlock.modelData.note
                color: root.cCyan
                opacity: 0.85
                font.family: root.fontFamily
                font.pixelSize: root.fs(Style.font.bodySmall)
              }
              PartList {
                title: "PART  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
                block: readingBlock.modelData.parts ? readingBlock.modelData.parts : null
              }
              Item { width: 1; height: root.sp(8) }
            }
          }
        }

        // ---- Codes: colour bands to value.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "Codes" && root.codesMode === "Bands" && root.result !== null && root.result.tolerancePct !== undefined

          Reading {
            label: "Value"
            value: root.result ? Model.text(root.result.value) : ""
            valueColor: root.cGreen
            strong: true
            detail: root.result && root.result.series ? root.result.series + " value" : "not a standard value"
            detailColor: root.cPurple
          }
          Reading {
            label: "Tolerance"
            value: root.result ? "±" + root.result.tolerancePct + " %" : ""
            valueColor: root.cYellow
            detail: root.result ? Model.text(root.result.min) + " to " + Model.text(root.result.max) : ""
            detailColor: root.cCyan
          }
          Reading {
            visible: root.result !== null && typeof root.result.tcr === "number"
            label: "Temperature coefficient"
            value: root.result && typeof root.result.tcr === "number" ? "±" + root.result.tcr + " ppm/K" : ""
            valueColor: root.cPurple
          }

          Item { width: 1; height: root.sp(6) }

          PartList {
            title: "PART  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            block: root.result && root.result.parts ? root.result.parts : null
          }
        }

        // ---- LED series resistor.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "LED / Ohm" && root.ledMode === "LED" && root.result !== null && root.result.up !== undefined
          readonly property var up: root.result && root.result.up ? root.result.up : null
          readonly property var down: root.result && root.result.down ? root.result.down : null

          Reading {
            label: "Exact resistor"
            value: root.result ? Model.text(root.result.exact) : ""
            valueColor: root.cPurple
            detail: root.result ? Model.text(root.result.drop) + " across it" : ""
            detailColor: root.cCyan
          }
          Reading {
            label: "Use"
            value: parent.up ? Model.text(parent.up.r) : ""
            valueColor: root.cPink
            strong: true
            // No value below means the exact resistance is itself standard.
            detail: root.result ? (parent.down === null ? root.result.series + " value" : "next " + root.result.series + " up") : ""
            detailColor: root.cPurple
          }
          Reading {
            label: "LED current"
            value: parent.up ? Model.text(parent.up.current) : ""
            valueColor: root.cGreen
            detail: parent.up ? Model.pct(parent.up.currentErrorPct) : ""
            detailColor: parent.up ? root.levelColor(parent.up.currentErrorPct) : root.fg
          }
          Reading {
            label: "Resistor power"
            value: parent.up && root.result ? root.loadText(parent.up.load, root.result.rating) : ""
            valueColor: parent.up ? root.loadColor(parent.up.load.level) : root.cYellow
          }
          PowerScope { }
          Reading {
            label: "Power in each LED"
            value: parent.up ? Model.text(parent.up.pLed) : ""
            valueColor: root.cYellow
          }
          Reading {
            label: "Total from the supply"
            value: parent.up ? Model.text(parent.up.pTotal) : ""
            valueColor: root.cYellow
            detail: root.result && typeof root.result.efficiency === "number"
              ? Math.round(root.result.efficiency) + " % in the LEDs" : ""
            detailColor: root.cCyan
          }
          Reading {
            visible: parent.down !== null
            label: "Next value down"
            value: parent.down ? Model.text(parent.down.r) : ""
            valueColor: root.cPink
            detail: parent.down ? Model.text(parent.down.current) + "  " + Model.pct(parent.down.currentErrorPct) : ""
            detailColor: parent.down ? root.levelColor(parent.down.currentErrorPct) : root.fg
          }

          Item { width: 1; height: root.sp(6) }

          PartList {
            title: "R  " + (root.result ? root.result.package + "  " + root.result.tolerance : "")
            seriesHint: root.seriesHint
            block: root.result && root.result.parts ? root.result.parts : null
          }
        }

        // ---- Ohm's law. The two you gave are plain; the two worked out
        //      are bold.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "LED / Ohm" && root.ledMode === "Ohm's law" && root.result !== null && root.result.given !== undefined
          readonly property var given: root.result && root.result.given ? root.result.given : ({})

          Reading {
            label: "Voltage"
            value: root.result && root.result.v ? Model.text(root.result.v) : ""
            valueColor: parent.given.v ? root.fg : root.cYellow
            strong: !parent.given.v
            detail: parent.given.v ? "given" : ""
            detailColor: root.cPurple
          }
          Reading {
            label: "Current"
            value: root.result && root.result.i ? Model.text(root.result.i) : ""
            valueColor: parent.given.i ? root.fg : root.cCyan
            strong: !parent.given.i
            detail: parent.given.i ? "given" : ""
            detailColor: root.cPurple
          }
          Reading {
            label: "Resistance"
            value: root.result && root.result.r ? Model.text(root.result.r) : ""
            valueColor: parent.given.r ? root.fg : root.cPink
            strong: !parent.given.r
            detail: parent.given.r ? "given" : ""
            detailColor: root.cPurple
          }
          Reading {
            label: "Power"
            value: root.result && root.result.p ? Model.text(root.result.p) : ""
            valueColor: parent.given.p ? root.fg : root.cGreen
            strong: !parent.given.p
            detail: parent.given.p ? "given" : ""
            detailColor: root.cPurple
          }
        }

        // ---- RC.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "RC / LC" && root.rclcMode === "RC" && root.result !== null && root.result.tau !== undefined
          readonly property string solved: root.result && root.result.solved ? root.result.solved : ""

          Reading {
            label: "R"
            value: root.result && root.result.r ? Model.text(root.result.r) : ""
            valueColor: root.cPink
            strong: parent.solved === "r"
          }
          Reading {
            label: "C"
            value: root.result && root.result.c ? Model.text(root.result.c) : ""
            valueColor: root.cPurple
            strong: parent.solved === "c"
          }
          Reading {
            label: "Time constant RC"
            value: root.result && root.result.tau ? Model.text(root.result.tau) : ""
            valueColor: root.cYellow
            strong: parent.solved === "f"
            detail: "63 % of a step"
            detailColor: root.cCyan
          }
          Reading {
            label: "Settled"
            value: root.result && root.result.settle ? Model.text(root.result.settle) : ""
            valueColor: root.cYellow
            detail: "5 RC, 99.3 %"
            detailColor: root.cCyan
          }
          Reading {
            label: "Cutoff"
            value: root.result && root.result.fc ? Model.text(root.result.fc) : ""
            valueColor: root.cGreen
            strong: parent.solved === "f"
            detail: "−3 dB, first order"
            detailColor: root.cCyan
          }

          SuggestBlock {
            suggestion: root.result && root.result.suggest ? root.result.suggest : null
            part: parent.solved === "r" ? "R" : "C"
            effect: suggestion ? "cutoff " + Model.text(suggestion.fc) : ""
          }
        }

        // ---- LC.
        Column {
          width: parent.width
          spacing: root.sp(2)
          visible: root.tab === "RC / LC" && root.rclcMode === "LC" && root.result !== null && root.result.f0 !== undefined
          readonly property string solved: root.result && root.result.solved ? root.result.solved : ""

          Reading {
            label: "L"
            value: root.result && root.result.l ? Model.text(root.result.l) : ""
            valueColor: root.cPink
            strong: parent.solved === "l"
          }
          Reading {
            label: "C"
            value: root.result && root.result.c ? Model.text(root.result.c) : ""
            valueColor: root.cPurple
            strong: parent.solved === "c"
          }
          Reading {
            label: "Resonance"
            value: root.result && root.result.f0 ? Model.text(root.result.f0) : ""
            valueColor: root.cGreen
            strong: parent.solved === "f"
          }
          Reading {
            label: "Characteristic impedance"
            value: root.result && root.result.z0 ? Model.text(root.result.z0) : ""
            valueColor: root.cYellow
            detail: "√(L/C)"
            detailColor: root.cCyan
          }

          SuggestBlock {
            suggestion: root.result && root.result.suggest ? root.result.suggest : null
            part: parent.solved === "l" ? "L" : "C"
            effect: suggestion ? "resonance " + Model.text(suggestion.f0) : ""
          }
        }

        Item { width: 1; height: root.sp(6) }
      }
    }
  }
  }
}
