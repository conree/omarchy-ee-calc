//! IEC 60063 preferred-number series and the searches built on them:
//! nearest standard value, and the best two-part series/parallel pair.

const std = @import("std");
const units = @import("units.zig");

pub const Series = enum {
    e3,
    e6,
    e12,
    e24,
    e48,
    e96,
    e192,

    pub fn name(self: Series) []const u8 {
        return switch (self) {
            .e3 => "E3",
            .e6 => "E6",
            .e12 => "E12",
            .e24 => "E24",
            .e48 => "E48",
            .e96 => "E96",
            .e192 => "E192",
        };
    }

    pub fn parse(text: []const u8) ?Series {
        inline for (std.meta.fields(Series)) |f| {
            if (std.ascii.eqlIgnoreCase(text, f.name)) return @enumFromInt(f.value);
        }
        return null;
    }

    /// Mantissas x100, one decade, ascending.
    pub fn values(self: Series) []const u16 {
        return switch (self) {
            .e3 => &e3,
            .e6 => &e6,
            .e12 => &e12,
            .e24 => &e24,
            .e48 => &e48,
            .e96 => &e96,
            .e192 => &e192,
        };
    }
};

// E24 carries the historical values (2.7, 3.0 ... 8.2, 9.1) that differ from
// the 10^(i/24) formula, so the lower series are tables, not computed.
const e24 = [_]u16{ 100, 110, 120, 130, 150, 160, 180, 200, 220, 240, 270, 300, 330, 360, 390, 430, 470, 510, 560, 620, 680, 750, 820, 910 };
const e12 = everyOther(24, e24);
const e6 = everyOther(12, e12);
const e3 = everyOther(6, e6);

const e96 = [_]u16{
    100, 102, 105, 107, 110, 113, 115, 118, 121, 124, 127, 130, 133, 137, 140, 143,
    147, 150, 154, 158, 162, 165, 169, 174, 178, 182, 187, 191, 196, 200, 205, 210,
    215, 221, 226, 232, 237, 243, 249, 255, 261, 267, 274, 280, 287, 294, 301, 309,
    316, 324, 332, 340, 348, 357, 365, 374, 383, 392, 402, 412, 422, 432, 442, 453,
    464, 475, 487, 499, 511, 523, 536, 549, 562, 576, 590, 604, 619, 634, 649, 665,
    681, 698, 715, 732, 750, 768, 787, 806, 825, 845, 866, 887, 909, 931, 953, 976,
};
const e48 = everyOther(96, e96);

// E192 is the rounding formula except at index 185, where IEC 60063 lists
// 920 and the formula gives 919. Every second entry is E96.
const e192 = [_]u16{
    100, 101, 102, 104, 105, 106, 107, 109, 110, 111, 113, 114, 115, 117, 118, 120,
    121, 123, 124, 126, 127, 129, 130, 132, 133, 135, 137, 138, 140, 142, 143, 145,
    147, 149, 150, 152, 154, 156, 158, 160, 162, 164, 165, 167, 169, 172, 174, 176,
    178, 180, 182, 184, 187, 189, 191, 193, 196, 198, 200, 203, 205, 208, 210, 213,
    215, 218, 221, 223, 226, 229, 232, 234, 237, 240, 243, 246, 249, 252, 255, 258,
    261, 264, 267, 271, 274, 277, 280, 284, 287, 291, 294, 298, 301, 305, 309, 312,
    316, 320, 324, 328, 332, 336, 340, 344, 348, 352, 357, 361, 365, 370, 374, 379,
    383, 388, 392, 397, 402, 407, 412, 417, 422, 427, 432, 437, 442, 448, 453, 459,
    464, 470, 475, 481, 487, 493, 499, 505, 511, 517, 523, 530, 536, 542, 549, 556,
    562, 569, 576, 583, 590, 597, 604, 612, 619, 626, 634, 642, 649, 657, 665, 673,
    681, 690, 698, 706, 715, 723, 732, 741, 750, 759, 768, 777, 787, 796, 806, 816,
    825, 835, 845, 856, 866, 876, 887, 898, 909, 920, 931, 942, 953, 965, 976, 988,
};

fn everyOther(comptime n: usize, comptime src: [n]u16) [n / 2]u16 {
    var out: [n / 2]u16 = undefined;
    for (&out, 0..) |*v, i| v.* = src[i * 2];
    return out;
}

/// Standard value for mantissa `m` (x100) in decade `d`: m * 10^(d-2).
pub fn valueAt(m: u16, d: i32) f64 {
    return units.scaleInt(@floatFromInt(m), d - 2);
}

pub const Nearest = struct {
    below: f64,
    above: f64,
    nearest: f64,
    exact: bool,
};

// Relative tolerance for treating a typed value as already standard, so
// 4700 is E12 even when the arithmetic lands on 4699.999999999.
const exact_tolerance = 1e-9;

/// Nearest standard values to `target` (> 0). "Nearest" is by ratio, the way
/// tolerance is specified; a geometric tie goes to the lower value.
pub fn nearest(series: Series, target: f64) Nearest {
    const d = units.decadeOf(target);
    const vals = series.values();

    // Walk the decade plus the next decade's first value (x10).
    var below = valueAt(vals[0], d);
    var above = valueAt(100, d + 1);
    for (vals) |m| {
        const v = valueAt(m, d);
        if (@abs(v - target) <= target * exact_tolerance) {
            return .{ .below = v, .above = v, .nearest = v, .exact = true };
        }
        if (v < target) below = v;
        if (v > target) {
            above = v;
            break;
        }
    }
    const next = valueAt(100, d + 1);
    if (@abs(next - target) <= target * exact_tolerance) {
        return .{ .below = next, .above = next, .nearest = next, .exact = true };
    }
    const pick = if (target / below <= above / target) below else above;
    return .{ .below = below, .above = above, .nearest = pick, .exact = false };
}

/// The part range the calculators advertise: 1 mΩ to 100 GΩ.
pub const min_value = 1e-3;
pub const max_value = 1e11;

pub fn inRange(v: f64) bool {
    return v >= min_value * (1 - 1e-9) and v <= max_value * (1 + 1e-9);
}

pub fn errorPercent(actual: f64, target: f64) f64 {
    return (actual - target) / target * 100;
}

pub const Combo = struct {
    a: f64,
    b: f64,
    result: f64,
    error_pct: f64,
};

pub const Topology = enum { series, parallel };

/// Best pair from one series for `target`, searching three decades either
/// side. `a` is always the larger part.
pub fn bestPair(series: Series, topology: Topology, target: f64) ?Combo {
    const d0 = units.decadeOf(target);
    var best: ?Combo = null;
    var d: i32 = d0 - 3;
    while (d <= d0 + 3) : (d += 1) {
        for (series.values()) |m| {
            const a = valueAt(m, d);
            if (!inRange(a)) continue;
            const ideal_b = switch (topology) {
                .series => target - a,
                .parallel => if (a > target) a * target / (a - target) else -1,
            };
            if (ideal_b <= 0 or !std.math.isFinite(ideal_b)) continue;
            const b = nearest(series, ideal_b).nearest;
            if (!inRange(b)) continue;
            const result = switch (topology) {
                .series => a + b,
                .parallel => a * b / (a + b),
            };
            const err = errorPercent(result, target);
            const candidate = Combo{ .a = @max(a, b), .b = @min(a, b), .result = result, .error_pct = err };
            if (best == null or better(candidate, best.?)) best = candidate;
        }
    }
    return best;
}

// Smaller error wins; on a tie, the pair whose parts are closer in value,
// because 4k7 + 4k7 is easier to buy than 9k1 + 330R.
fn better(x: Combo, y: Combo) bool {
    const ex = @abs(x.error_pct);
    const ey = @abs(y.error_pct);
    if (@abs(ex - ey) > 1e-9) return ex < ey;
    return x.a / x.b < y.a / y.b;
}

const testing = std.testing;

test "table sizes" {
    try testing.expectEqual(@as(usize, 3), Series.e3.values().len);
    try testing.expectEqual(@as(usize, 6), Series.e6.values().len);
    try testing.expectEqual(@as(usize, 12), Series.e12.values().len);
    try testing.expectEqual(@as(usize, 24), Series.e24.values().len);
    try testing.expectEqual(@as(usize, 48), Series.e48.values().len);
    try testing.expectEqual(@as(usize, 96), Series.e96.values().len);
    try testing.expectEqual(@as(usize, 192), Series.e192.values().len);
}

test "E192 is the formula except 920, and contains E96" {
    for (e192, 0..) |m, i| {
        const f = @round(std.math.pow(f64, 10, @as(f64, @floatFromInt(i)) / 192) * 100);
        const want: f64 = if (i == 185) 920 else f;
        try testing.expectEqual(want, @as(f64, @floatFromInt(m)));
    }
    for (e96, 0..) |m, i| try testing.expectEqual(m, e192[i * 2]);
    try testing.expect(nearest(.e192, 1010).exact);
    try testing.expect(nearest(.e192, 9200).exact);
    try testing.expect(!nearest(.e192, 9190).exact);
}

test "E96 matches the rounding formula except where the standard differs" {
    for (e96, 0..) |m, i| {
        const f = @round(std.math.pow(f64, 10, @as(f64, @floatFromInt(i)) / 96) * 100);
        try testing.expectEqual(@as(f64, @floatFromInt(m)), f);
    }
}

test "E12 and E6 contents" {
    try testing.expectEqualSlices(u16, &.{ 100, 120, 150, 180, 220, 270, 330, 390, 470, 560, 680, 820 }, Series.e12.values());
    try testing.expectEqualSlices(u16, &.{ 100, 150, 220, 330, 470, 680 }, Series.e6.values());
    try testing.expectEqualSlices(u16, &.{ 100, 220, 470 }, Series.e3.values());
}

test "nearest exact values" {
    const n = nearest(.e12, 4700);
    try testing.expect(n.exact);
    try testing.expectEqual(@as(f64, 4700), n.nearest);
    try testing.expect(nearest(.e24, 10000).exact);
    try testing.expect(nearest(.e96, 4.99).exact);
    try testing.expect(nearest(.e24, 0.001).exact);
}

test "nearest brackets" {
    const n = nearest(.e24, 5000);
    try testing.expectEqual(@as(f64, 4700), n.below);
    try testing.expectEqual(@as(f64, 5100), n.above);
    try testing.expectEqual(@as(f64, 5100), n.nearest);

    // Top of a decade rolls into the next one.
    const top = nearest(.e12, 9900);
    try testing.expectEqual(@as(f64, 8200), top.below);
    try testing.expectEqual(@as(f64, 10000), top.above);
    try testing.expectEqual(@as(f64, 10000), top.nearest);

    const small = nearest(.e96, 1.234);
    try testing.expectEqual(@as(f64, 1.21), small.below);
    try testing.expectEqual(@as(f64, 1.24), small.above);
    try testing.expectEqual(@as(f64, 1.24), small.nearest);
}

test "best pairs" {
    const s = bestPair(.e24, .series, 5000).?;
    try testing.expect(@abs(s.error_pct) < 0.01);
    try testing.expectEqual(@as(f64, 5000), s.result);

    const p = bestPair(.e12, .parallel, 5000).?;
    try testing.expect(@abs(p.error_pct) < 1.0);
    try testing.expect(p.a >= p.b);
}

test "pairs stay inside the advertised part range" {
    if (bestPair(.e24, .series, 1e-3)) |c| try testing.expect(c.b >= min_value);
    if (bestPair(.e24, .parallel, 1e11)) |c| try testing.expect(c.a <= max_value);
}
