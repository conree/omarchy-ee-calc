.pragma library

// Pure helpers for the panel: nothing here touches QML objects.

var SERIES = ["E3", "E6", "E12", "E24", "E48", "E96"]
var TABS = ["E-series", "Divider"]
var DIVIDER_MODES = ["Analyse", "Find values"]

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
