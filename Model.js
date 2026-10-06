.pragma library

// Pure helpers for the panel: nothing here touches QML objects.

var SERIES = ["E3", "E6", "E12", "E24", "E48", "E96", "E192"]
var TABS = ["E-series", "Divider", "Codes", "LED / Ohm", "RC / LC"]
var DIVIDER_MODES = ["Analyse", "Find values"]
var CODES_MODES = ["Value", "SMD code", "Bands"]
var LED_MODES = ["LED", "Ohm's law"]
var RCLC_MODES = ["RC", "LC"]
var BAND_COUNTS = [
  { value: 4, label: "4 band" },
  { value: 5, label: "5 band" },
  { value: 6, label: "6 band" }
]
// value is what the engine takes; label is what the chip shows.
var PACKAGES = [
  { value: "0402", label: "0402" },
  { value: "0603", label: "0603" },
  { value: "0805", label: "0805" },
  { value: "1206", label: "1206" },
  { value: "tht-quarter", label: "\u00BCW", tooltip: "Through hole, 1/4 W metal film" },
  { value: "tht-half", label: "\u00BDW", tooltip: "Through hole, 1/2 W metal film" }
]
var TOLERANCES = [
  { value: "0.1", label: "0.1 %" },
  { value: "0.5", label: "0.5 %" },
  { value: "1", label: "1 %" },
  { value: "5", label: "5 %" }
]

// ---- Colour bands. The engine decides what a set of bands means and
// rejects a colour in the wrong place; these lists only decide which
// swatches the picker offers for each band (IEC 60062:2016).

// The real paint colours, not the theme's: a band has to look like the part.
var BAND_PAINT = {
  black: "#1A1A1A", brown: "#7B4A26", red: "#D7262B", orange: "#F08A1C",
  yellow: "#F3D221", green: "#2E9D47", blue: "#2D6CDF", violet: "#8E44C9",
  grey: "#8C8C8C", white: "#F4F4F4", gold: "#CFA539", silver: "#C2C6CC",
  pink: "#F19CBB", none: "transparent"
}
var DIGIT_COLOURS = ["black", "brown", "red", "orange", "yellow", "green", "blue", "violet", "grey", "white"]
// Lowest multiplier first, so one step along the list is one decade.
var MULTIPLIER_COLOURS = ["pink", "silver", "gold"].concat(DIGIT_COLOURS)
var TOLERANCE_COLOURS = ["brown", "red", "green", "blue", "violet", "grey", "orange", "yellow", "gold", "silver", "none"]
var TCR_COLOURS = ["black", "brown", "red", "orange", "yellow", "green", "blue", "violet", "grey"]

// What band `index` of a `count`-band resistor is for.
function bandRole(count, index) {
  var digits = count === 4 ? 2 : 3
  if (index < digits) return "digit"
  if (index === digits) return "multiplier"
  if (index === digits + 1) return "tolerance"
  return "tcr"
}

// "none" (±20 %) is the missing tolerance band of the two-digit code, so
// only four-band sets offer it.
function bandChoices(role, count) {
  if (role === "digit") return DIGIT_COLOURS
  if (role === "multiplier") return MULTIPLIER_COLOURS
  if (role === "tolerance") return count === 4 ? TOLERANCE_COLOURS : TOLERANCE_COLOURS.filter(function(c) { return c !== "none" })
  return TCR_COLOURS
}

var BAND_ROLE_NAMES = { digit: "digit", multiplier: "multiplier", tolerance: "tolerance", tcr: "temperature coefficient" }

// Moves a band set to another band count and keeps the value where it can.
// Four to five: a black third digit with the multiplier one decade lower,
// or, at the lowest multiplier (pink), a black first digit instead. Five to
// four: drop a black first digit, else drop a black third digit and raise
// the multiplier. A value that needs three digits cannot fit in four bands,
// so its third digit is dropped. Six bands add a 100 ppm/K band.
function changeBandCount(bands, count) {
  var b = bands.slice()
  var from = b.length
  if (from === count) return b
  var top = MULTIPLIER_COLOURS.length - 1
  if (from === 4) {
    var m4 = MULTIPLIER_COLOURS.indexOf(b[2])
    b = m4 > 0 ? [b[0], b[1], "black", MULTIPLIER_COLOURS[m4 - 1], b[3]]
               : ["black", b[0], b[1], b[2], b[3]]
  } else if (count === 4) {
    var m5 = MULTIPLIER_COLOURS.indexOf(b[3])
    if (b[0] === "black") b = [b[1], b[2], b[3], b[4]]
    else b = [b[0], b[1], MULTIPLIER_COLOURS[Math.min(top, m5 + 1)], b[4]]
  } else {
    b = b.slice(0, 5)
  }
  // Three digits need a real tolerance band: ±20 % becomes ±10 % (silver).
  if (count > 4 && b[4] === "none") b[4] = "silver"
  if (count === 6) b.push("brown")
  return b
}

// ---- The ? button. Each screen opens its own section of the user manual
// on GitHub, at the release tag of the installed version, so the manual
// matches the plugin. Anchors are GitHub's heading slugs.
var MANUAL_BASE = "https://github.com/conree/omarchy-ee-calc/blob/"
var MANUAL_SECTIONS = {
  "E-series": "6-the-e-series-tab",
  "Divider/Analyse": "7-divider-analyse",
  "Divider/Find values": "8-divider-find-values",
  "Codes/Value": "value",
  "Codes/SMD code": "smd-code",
  "Codes/Bands": "bands",
  "LED / Ohm/LED": "led",
  "LED / Ohm/Ohm's law": "ohms-law",
  "RC / LC/RC": "rc",
  "RC / LC/LC": "lc"
}

function manualUrl(version, tab, mode) {
  var ref = version ? "v" + version : "main"
  var anchor = MANUAL_SECTIONS[tab + "/" + mode] || MANUAL_SECTIONS[tab] || ""
  return MANUAL_BASE + ref + "/docs/USER_MANUAL.md" + (anchor ? "#" + anchor : "")
}

// Local path of a file bundled with the plugin. The shell hands entry points
// percent-encoded file URLs, so a plain "file://" strip breaks on spaces.
function localPath(url) {
  return decodeURIComponent(String(url).replace(/^file:\/\//, ""))
}

function pct(value) {
  if (typeof value !== "number" || !isFinite(value)) return "—"
  if (Math.abs(value) < 0.00005) return "0.00 %"
  var digits = Math.abs(value) < 0.1 ? 3 : 2
  return (value > 0 ? "+" : "") + value.toFixed(digits) + " %"
}

function text(quantity) {
  return quantity && typeof quantity.text === "string" ? quantity.text : "—"
}

// Engine output is trusted only after its shape is checked, so a stray
// line on stdout can never bind undefined into the panel.
function parseResult(raw) {
  var s = String(raw || "").trim()
  if (s === "") return { ok: false, error: "No answer from the engine" }
  var parsed
  try { parsed = JSON.parse(s) } catch (e) { return { ok: false, error: "Engine returned unreadable output" } }
  if (!parsed || typeof parsed !== "object") return { ok: false, error: "Engine returned unreadable output" }
  if (parsed.ok !== true) return { ok: false, error: typeof parsed.error === "string" ? parsed.error : "Engine error" }
  return parsed
}

// Colour for an error: exact is good news, within 1 % is fine, anything more
// is worth a second look.
function errorLevel(value) {
  if (typeof value !== "number" || !isFinite(value)) return "none"
  var a = Math.abs(value)
  if (a < 0.00005) return "exact"
  if (a <= 1) return "close"
  if (a <= 5) return "fair"
  return "far"
}

// Reads colorN = "#RRGGBB" lines out of an Omarchy colors.toml.
function themeColor(toml, key) {
  var re = new RegExp("^\\s*" + key + "\\s*=\\s*\"(#[0-9A-Fa-f]{6})\"", "m")
  var m = re.exec(String(toml || ""))
  return m ? m[1] : ""
}

// True when the engine's power check says a part is past its rating.
function overloaded(load) {
  return !!load && load.level === "over"
}
