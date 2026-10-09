//! Resistive voltage divider: analyse a given R1/R2, or pick standard
//! values that hit a target output.
//!
//!   Vin ── R1 ──┬── Vout
//!               R2   (RL optional, across R2)
//!   GND ────────┴──

const std = @import("std");
const units = @import("units.zig");
const eseries = @import("eseries.zig");

pub const Analysis = struct {
    vout: f64,
    vout_unloaded: f64,
    ratio: f64,
    current: f64,
    p_r1: f64,
    p_r2: f64,
    p_load: f64,
    load_current: f64,
    source_resistance: f64,
};

fn parallel(a: f64, b: f64) f64 {
    return a * b / (a + b);
}

/// `load` of null or <= 0 means unloaded.
pub fn analyze(vin: f64, r1: f64, r2: f64, load: ?f64) Analysis {
    const rl = if (load) |l| (if (l > 0) l else null) else null;
    const r2eff = if (rl) |l| parallel(r2, l) else r2;
    const current = vin / (r1 + r2eff);
    const vout = current * r2eff;
    return .{
        .vout = vout,
        .vout_unloaded = vin * r2 / (r1 + r2),
        .ratio = vout / vin,
        .current = current,
        .p_r1 = current * current * r1,
        .p_r2 = vout * vout / r2,
        .p_load = if (rl) |l| vout * vout / l else 0,
        .load_current = if (rl) |l| vout / l else 0,
        .source_resistance = parallel(r1, r2),
    };
}

pub const Candidate = struct {
    r1: f64,
    r2: f64,
    vout: f64,
    error_pct: f64,
    total: f64,
    current: f64,
};

pub const SolveError = error{ OutOfRange, BadRange, OutOfMemory };

pub const SolveOptions = struct {
    series: eseries.Series = .e24,
    r_min: f64 = 10e3,
    r_max: f64 = 1e6,
    load: ?f64 = null,
    count: usize = 5,
};

/// Standard R1/R2 pairs for `vout` from `vin`, best first. Pairs that are
/// the same ratio a decade apart are collapsed only when unloaded. A fixed
/// load makes scaled pairs electrically different, so all remain eligible.
pub fn solve(gpa: std.mem.Allocator, vin: f64, vout: f64, opts: SolveOptions) SolveError![]Candidate {
    if (!(vin > 0) or !(vout > 0) or !(vout < vin)) return error.OutOfRange;
    if (!(opts.r_min > 0) or !(opts.r_max >= opts.r_min)) return error.BadRange;

    const k = vout / vin;
    const rl = if (opts.load) |l| (if (l > 0) l else null) else null;
    const mid = @sqrt(opts.r_min * opts.r_max);

    var all: std.ArrayList(Candidate) = .empty;
    defer all.deinit(gpa);

    // Every standard value either part could take, ascending: nothing above
    // the total's maximum, nothing outside the advertised part range.
    var vals: std.ArrayList(f64) = .empty;
    defer vals.deinit(gpa);
    var d: i32 = units.decadeOf(eseries.min_value);
    const d_hi = units.decadeOf(opts.r_max);
    while (d <= d_hi) : (d += 1) {
        for (opts.series.values()) |m| {
            const v = eseries.valueAt(m, d);
            if (eseries.inRange(v) and v <= opts.r_max * (1 + 1e-9)) try vals.append(gpa, v);
        }
    }

    // For each R2, R1 is confined to the values that keep R1+R2 in range.
    // Within that window take `count` values either side of the ideal R1:
    // the ideal's own neighbours can both fall outside the window, and
    // once equal ratios are collapsed two per R2 is too few to fill a list.
    for (vals.items) |r2| {
        const lo = lowerBound(vals.items, (opts.r_min - r2) * (1 - 1e-9));
        const hi = upperBound(vals.items, (opts.r_max - r2) * (1 + 1e-9));
        if (lo >= hi) continue;
        const r2eff = if (rl) |l| parallel(r2, l) else r2;
        const ideal_r1 = r2eff * (1 - k) / k;
        const centre = std.math.clamp(lowerBound(vals.items, ideal_r1), lo, hi - 1);
        const first = if (centre >= lo + opts.count) centre - opts.count else lo;
        const last = @min(hi, centre + opts.count + 1);
        for (vals.items[first..last]) |r1| {
            const a = analyze(vin, r1, r2, rl);
            try all.append(gpa, .{
                .r1 = r1,
                .r2 = r2,
                .vout = a.vout,
                .error_pct = eseries.errorPercent(a.vout, vout),
                .total = r1 + r2,
                .current = a.current,
            });
        }
    }

    std.mem.sort(Candidate, all.items, mid, lessThan);

    var out: std.ArrayList(Candidate) = .empty;
    errdefer out.deinit(gpa);
    for (all.items) |c| {
        if (out.items.len == opts.count) break;
        var duplicate = false;
        if (rl == null) {
            for (out.items) |kept| {
                if (@abs(c.r1 / c.r2 - kept.r1 / kept.r2) <= 1e-9 * (c.r1 / c.r2)) {
                    duplicate = true;
                    break;
                }
            }
        }
        if (!duplicate) try out.append(gpa, c);
    }
    return out.toOwnedSlice(gpa);
}

/// First index whose value is >= x.
fn lowerBound(items: []const f64, x: f64) usize {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (items[mid] < x) lo = mid + 1 else hi = mid;
    }
    return lo;
}

/// First index whose value is > x.
fn upperBound(items: []const f64, x: f64) usize {
    var lo: usize = 0;
    var hi: usize = items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (items[mid] <= x) lo = mid + 1 else hi = mid;
    }
    return lo;
}

fn lessThan(mid: f64, x: Candidate, y: Candidate) bool {
    const ex = @abs(x.error_pct);
    const ey = @abs(y.error_pct);
    if (@abs(ex - ey) > 1e-9) return ex < ey;
    return @abs(@log(x.total / mid)) < @abs(@log(y.total / mid));
}

const testing = std.testing;

test "analyze unloaded" {
    const a = analyze(12, 10e3, 2.2e3, null);
    try testing.expectApproxEqRel(@as(f64, 12.0 * 2.2 / 12.2), a.vout, 1e-12);
    try testing.expectApproxEqRel(@as(f64, 12.0 / 12.2e3), a.current, 1e-12);
    try testing.expectApproxEqRel(@as(f64, 10e3 * 2.2e3 / 12.2e3), a.source_resistance, 1e-12);
    try testing.expectEqual(a.vout, a.vout_unloaded);
    try testing.expectEqual(@as(f64, 0), a.p_load);
}

test "analyze loaded" {
    const a = analyze(10, 10e3, 10e3, 10e3);
    try testing.expectApproxEqRel(@as(f64, 10.0 / 3.0), a.vout, 1e-12);
    try testing.expectApproxEqRel(@as(f64, 5), a.vout_unloaded, 1e-12);
    try testing.expectApproxEqRel(a.current, a.vout / 10e3 + a.load_current, 1e-12);
}

test "solve 12V to 3.3V" {
    const got = try solve(testing.allocator, 12, 3.3, .{});
    defer testing.allocator.free(got);
    try testing.expect(got.len > 0);
    try testing.expect(@abs(got[0].error_pct) < 1.0);
    for (got) |c| {
        try testing.expect(c.total >= 10e3 and c.total <= 1e6);
    }
    for (got[1..], 0..) |c, i| try testing.expect(@abs(c.error_pct) >= @abs(got[i].error_pct) - 1e-9);
}

test "solve rejects impossible targets" {
    try testing.expectError(error.OutOfRange, solve(testing.allocator, 5, 5, .{}));
    try testing.expectError(error.OutOfRange, solve(testing.allocator, 5, 0, .{}));
    try testing.expectError(error.BadRange, solve(testing.allocator, 5, 3, .{ .r_min = 1e6, .r_max = 1e3 }));
}

test "solve finds pairs when the ideal's neighbours are out of range" {
    const got = try solve(testing.allocator, 5, 1, .{ .series = .e6, .r_min = 10e3, .r_max = 12e3 });
    defer testing.allocator.free(got);
    try testing.expect(got.len > 0);
    for (got) |c| try testing.expect(c.total >= 10e3 and c.total <= 12e3);
}

test "solve fills the requested count" {
    const got = try solve(testing.allocator, 10, 5, .{});
    defer testing.allocator.free(got);
    try testing.expectEqual(@as(usize, 5), got.len);
    try testing.expectEqual(@as(f64, 0), got[0].error_pct);
}

test "solve returns nothing when no pair fits" {
    const got = try solve(testing.allocator, 5, 1, .{ .series = .e6, .r_min = 10.5e3, .r_max = 10.6e3 });
    defer testing.allocator.free(got);
    try testing.expectEqual(@as(usize, 0), got.len);
}

test "solve never proposes parts outside 1 milliohm to 100 gigaohm" {
    const got = try solve(testing.allocator, 5, 4.9999999999, .{});
    defer testing.allocator.free(got);
    for (got) |c| try testing.expect(c.r1 >= 1e-3 and c.r2 >= 1e-3);
}

test "solve accepts an exact total" {
    const got = try solve(testing.allocator, 43.19, 21.02, .{ .r_min = 120, .r_max = 120 });
    defer testing.allocator.free(got);
    try testing.expect(got.len > 0);
    for (got) |c| try testing.expectApproxEqRel(@as(f64, 120), c.total, 1e-9);
}

test "loaded shortlist retains electrically different scaled pairs" {
    const got = try solve(testing.allocator, 5, 3.3, .{ .series = .e3, .r_min = 1e3, .r_max = 100e3, .load = 68e3 });
    defer testing.allocator.free(got);
    var found = false;
    for (got) |c| {
        if (c.r1 == 470 and c.r2 == 1000) {
            found = true;
            try testing.expectApproxEqRel(@as(f64, 5.0 / (1.0 + 470.0 / 1000.0 + 470.0 / 68000.0)), c.vout, 1e-12);
        }
    }
    try testing.expect(found);
}
