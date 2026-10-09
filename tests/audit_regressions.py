#!/usr/bin/env python3
"""Independent regressions for the October 2026 audit; no engine imports.

Run from any directory. Prints JSON; redirect it to the release evidence
directory to retain results. Does not write into historical audit records.
"""
import json
import math
import pathlib
import random
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
checks = 0


def call(*args, ok=True):
    global checks
    proc = subprocess.run([str(ROOT / "bin/ee-calc"), *map(str, args)],
                          text=True, capture_output=True, timeout=10)
    result = json.loads(proc.stdout)
    assert result["ok"] is ok and proc.returncode == (0 if ok else 2), (args, result)
    checks += 1
    return result


# A02: the full documented option set, with duplicate/unknown rejection.
args = ["divider-solve", "--vin", "12", "--vout", "3.3", "--series", "E24",
        "--rmin", "10k", "--rmax", "1M", "--rl", "100k", "--count", "5",
        "--package", "0603", "--tolerance", "1"]
assert len(call(*args)["candidates"]) == 5
assert call(*args, "--vin", "5", ok=False)["error"] == "option given twice"
assert call(*args, "--nonsense", "1", ok=False)["error"] == "unknown option"

# A01: enumerate every eligible pair independently, without ratio collapse.
# Compare the complete ranked list, including count=20; counts/series vary.
rng = random.Random(30303)
cases = 0
for series, mantissas in [("E3", [1, 2.2, 4.7]), ("E6", [1, 1.5, 2.2, 3.3, 4.7, 6.8])]:
    values = [m * 10**d for d in range(-3, 6) for m in mantissas if m * 10**d <= 1e5]
    for n in range(50):
        target, load = rng.uniform(.1, 4.9), 10**rng.uniform(1, 6)
        count = [1, 5, 20][n % 3]
        rows = []
        for r1 in values:
            for r2 in values:
                if 1000 <= r1 + r2 <= 100000:
                    voltage = 5 / (1 + r1 / r2 + r1 / load)
                    rows.append((abs(voltage - target), abs(math.log((r1 + r2) / 10000))))
        rows.sort()
        got = call("divider-solve", "--vin", 5, "--vout", target, "--rl", load,
                   "--rmin", 1000, "--rmax", 100000, "--series", series,
                   "--count", count)["candidates"]
        assert len(got) == count
        seen = set()
        for actual, expected in zip(got, rows):
            r1, r2 = actual["r1"]["value"], actual["r2"]["value"]
            assert (r1, r2) not in seen
            seen.add((r1, r2))
            assert math.isclose(actual["vout"]["value"], 5 / (1 + r1/r2 + r1/load), rel_tol=1e-12)
            assert abs(actual["vout"]["value"] - target) <= expected[0] + 1e-10
        cases += 1

# A05: the produced code must independently decode to the requested value.
digits = ["black", "brown", "red", "orange", "yellow", "green", "blue", "violet", "grey", "white"]
for tol, colour in [("1", "brown"), ("0.5", "green"), ("0.1", "violet")]:
    result = call("codes", ".047", "--tolerance", tol)
    assert result["bands"] == ["yellow", "violet", "pink", colour]
    assert (10 * digits.index(result["bands"][0]) + digits.index(result["bands"][1])) * .001 == .047

# A10: preserve the numerical result and meaningful display for both extremes.
tiny = call("ohm", "--v", "1e-15", "--r", "1e15")
for key, expected in [("i", 1e-30), ("p", 1e-45)]:
    assert math.isclose(tiny[key]["value"], expected, rel_tol=1e-12)
    assert math.isclose(float(tiny[key]["text"].split()[0]), expected, rel_tol=1e-3)

# A07: all executable/package/manifest release metadata agrees.
version = json.loads((ROOT / "manifest.json").read_text())["version"]
assert call("version")["version"] == version
assert f'.version = "{version}"' in (ROOT / "engine/build.zig.zon").read_text()
assert f"Version {version}" in (ROOT / "docs/USER_MANUAL.md").read_text()

print(json.dumps({"passed": True, "engine_calls": checks,
                  "exhaustive_loaded_shortlists": cases, "version": version}, indent=2))
