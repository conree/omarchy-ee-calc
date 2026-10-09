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
console.log(JSON.stringify({passed: true, reason_preservation_cases: cases.length}))
