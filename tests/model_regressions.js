// Run the real pure UI helpers; no copy of their implementation.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const vm = require("node:vm")
const root = path.resolve(__dirname, "..")
const model = vm.createContext({})
vm.runInContext(fs.readFileSync(path.join(root, "Model.js"), "utf8").replace(/^\.pragma library\s*/, ""), model)
const cases = [
  [null, false],
  [{note: "not made at 5 % (E24 values only)"}, true],
  [{note: "outside every maker's range for this size"}, false],
  [{note: "outside the 1 Ω to 4.7 MΩ range"}, false],
  [{note: "no through-hole part at this tolerance"}, false],
  [{note: ""}, false]
]
for (const [block, expected] of cases) assert.equal(model.suggestE24(block), expected)

// Field editing: the fields are read-only to Qt, so these helpers do the typing.
assert.deepEqual({...model.replaceRange("4k99", 1, 1, "7")}, {text: "47k99", cursor: 2})
assert.deepEqual({...model.replaceRange("4k99", 0, 4, "10k")}, {text: "10k", cursor: 3})
assert.deepEqual({...model.replaceRange("4k99", 3, 4, "")}, {text: "4k9", cursor: 3})
assert.equal(model.typedText("k"), "k")
assert.equal(model.typedText("µ"), "µ")
for (const key of ["", "\b", "\t", "\r", "\u001b", "\u007f", "\u0085"]) assert.equal(model.typedText(key), "")

// Pasting: short text is cleaned; anything longer than a value is refused,
// including text cut short at the read limit.
assert.equal(model.pastedText(" 4k7\n"), "4k7")
assert.equal(model.pastedText("4\tk7"), "4k7")
assert.equal(model.pastedText("x".repeat(model.PASTE_MAX_CHARS)), "x".repeat(model.PASTE_MAX_CHARS))
assert.equal(model.pastedText("x".repeat(model.PASTE_MAX_CHARS + 1)), "")
assert.equal(model.PASTE_READ_BYTES, model.PASTE_MAX_CHARS * 4 + 1)
const cut = Buffer.from("€".repeat(200)).subarray(0, model.PASTE_READ_BYTES).toString("utf8")
assert.equal(model.pastedText(cut), "")
assert.equal(model.pastedText(null), "")

console.log(JSON.stringify({passed: true, reason_preservation_cases: cases.length}))
