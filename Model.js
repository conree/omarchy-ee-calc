.pragma library

// Pure helpers for the panel: nothing here touches QML objects.

var SERIES = ["E3", "E6", "E12", "E24", "E48", "E96"]
var TABS = ["E-series", "Divider"]
var DIVIDER_MODES = ["Analyse", "Find values"]
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
  { value: "1", label: "1 %" },
  { value: "5", label: "5 %" }
]

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
