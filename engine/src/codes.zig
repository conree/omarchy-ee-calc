//! Resistor markings, both ways: SMD codes (3-digit, 4-digit, R as the
//! decimal point, EIA-96) and IEC 60062 colour bands.
//!
//! Sources (checked 2026-10-05):
//!   Yageo "Chip resistors marking" V.3, 2017-09-11: 3- and 4-digit codes,
//!     R as the decimal point, 0 = jumper, the EIA-96 table and its
//!     multipliers X = 0.1, Y = 0.01, A = 1, B = 10 ... F = 100k.
//!   Hobby-Hour SMD code guide: the letters other makers use as well,
//!     Z = 0.001, R = Y, S = X, H = B; 0, 00, 000, 0000 = jumper.
//!   IEC 60062:2016 colour table, as reproduced in Wikipedia's
//!     "Electronic color code": digits, multipliers (pink 0.001), tolerances
//!     and temperature coefficients.

const std = @import("std");
const units = @import("units.zig");
const eseries = @import("eseries.zig");

// ---- Significant digits ---------------------------------------------------

/// value = sig * 10^exp, with sig holding exactly `n` digits.
pub const Sig = struct { sig: u32, exp: i32 };

/// `value` written with `n` significant digits, or null when it needs more.
pub fn sigDigits(value: f64, n: u8) ?Sig {
    if (!(value > 0) or !std.math.isFinite(value)) return null;
    var exp = units.decadeOf(value) - (@as(i32, n) - 1);
    var sig = @round(value / units.pow10(exp));
    if (sig >= units.pow10(n)) {
        sig /= 10;
        exp += 1;
    }
    if (@abs(units.scaleInt(sig, exp) - value) > value * 1e-9) return null;
    return .{ .sig = @intFromFloat(sig), .exp = exp };
}

/// The smallest E-series `value` belongs to, or null for none.
pub fn seriesOf(value: f64) ?eseries.Series {
    inline for (std.meta.fields(eseries.Series)) |f| {
        const s: eseries.Series = @enumFromInt(f.value);
        if (eseries.nearest(s, value).exact) return s;
    }
    return null;
}

// ---- SMD codes: value to code ---------------------------------------------

/// Two significant digits and a multiplier digit (E24, 2 % and 5 % parts):
/// 472 = 4.7 kΩ. Below 10 Ω R is the decimal point: 4R7, R47.
pub fn threeDigit(buf: []u8, value: f64) ?[]const u8 {
    const s = sigDigits(value, 2) orelse return null;
    return switch (s.exp) {
        0...9 => std.fmt.bufPrint(buf, "{d}{d}", .{ s.sig, s.exp }) catch null,
        -1 => std.fmt.bufPrint(buf, "{d}R{d}", .{ s.sig / 10, s.sig % 10 }) catch null,
        -2 => std.fmt.bufPrint(buf, "R{d}", .{s.sig}) catch null,
        else => null,
    };
}

/// Three significant digits and a multiplier digit (1 % and better):
/// 4991 = 4.99 kΩ. Below 100 Ω R is the decimal point: 31R6, 4R99, R220.
pub fn fourDigit(buf: []u8, value: f64) ?[]const u8 {
    const s = sigDigits(value, 3) orelse return null;
    return switch (s.exp) {
        0...9 => std.fmt.bufPrint(buf, "{d}{d}", .{ s.sig, s.exp }) catch null,
        -1 => std.fmt.bufPrint(buf, "{d}R{d}", .{ s.sig / 10, s.sig % 10 }) catch null,
        -2 => std.fmt.bufPrint(buf, "{d}R{d:0>2}", .{ s.sig / 100, s.sig % 100 }) catch null,
        -3 => std.fmt.bufPrint(buf, "R{d}", .{s.sig}) catch null,
        else => null,
    };
}

// Yageo's multiplier letters, 10^-2 (Y) to 10^5 (F).
const eia_letters = "YXABCDEF";

/// EIA-96: the value's index in the E96 table (01..96) and a letter for
/// the multiplier: 01C = 100 x 100 = 10 kΩ. E96 values from 1 Ω to 97.6 MΩ.
pub fn eia96(buf: []u8, value: f64) ?[]const u8 {
    const s = sigDigits(value, 3) orelse return null;
    if (s.exp < -2 or s.exp > 5) return null;
    const index = std.mem.indexOfScalar(u16, eseries.Series.e96.values(), @intCast(s.sig)) orelse return null;
    return std.fmt.bufPrint(buf, "{d:0>2}{c}", .{ index + 1, eia_letters[@intCast(s.exp + 2)] }) catch null;
}

// ---- SMD codes: code to value ---------------------------------------------

pub const Reading = struct {
    scheme: []const u8,
    value: f64,
    note: []const u8 = "",
};

pub const max_readings = 4;

/// Every way `code` can be read. "10R" is both 10 Ω and EIA-96 code 10
/// with the R (= Y) multiplier, so both come back; the panel shows each.
pub fn decode(code: []const u8, out: *[max_readings]Reading) []Reading {
    var buf: [8]u8 = undefined;
    var len: usize = 0;
    for (code) |ch| {
        if (ch == ' ' or ch == '\t') continue;
        if (len == buf.len) return out[0..0];
        buf[len] = std.ascii.toUpper(ch);
        len += 1;
    }
    const c = buf[0..len];
    if (c.len == 0) return out[0..0];
    var n: usize = 0;

    if (c.len <= 4 and allChar(c, '0')) {
        out[0] = .{ .scheme = "Jumper", .value = 0, .note = "zero-ohm link" };
        return out[0..1];
    }

    if (c.len == 3 and allDigits(c) and c[0] != '0') {
        const sig: f64 = @floatFromInt((c[0] - '0') * 10 + (c[1] - '0'));
        out[n] = .{ .scheme = "3-digit", .value = units.scaleInt(sig, c[2] - '0'), .note = "E24, usually 2 % or 5 %" };
        n += 1;
    }

    if (c.len == 4 and allDigits(c) and c[0] != '0') {
        const sig: f64 = @floatFromInt(@as(u32, c[0] - '0') * 100 + (c[1] - '0') * 10 + (c[2] - '0'));
        out[n] = .{ .scheme = "4-digit", .value = units.scaleInt(sig, c[3] - '0'), .note = "usually 1 % or better" };
        n += 1;
    }

    if (c.len >= 2 and c.len <= 4 and std.mem.count(u8, c, "R") == 1) {
        const at = std.mem.indexOfScalar(u8, c, 'R').?;
        const left = c[0..at];
        const right = c[at + 1 ..];
        if ((left.len == 0 or allDigits(left)) and (right.len == 0 or allDigits(right))) {
            var num: [12]u8 = undefined;
            const text = std.fmt.bufPrint(&num, "0{s}.{s}0", .{ left, right }) catch unreachable;
            const v = std.fmt.parseFloat(f64, text) catch 0;
            if (v > 0) {
                out[n] = .{
                    .scheme = "R as decimal point",
                    .value = v,
                    .note = if (c.len == 4) "usually 1 % or better" else "E24, usually 2 % or 5 %",
                };
                n += 1;
            }
        }
    }

    if (c.len == 3 and allDigits(c[0..2])) {
        const index = (c[0] - '0') * 10 + (c[1] - '0');
        const m: ?struct { exp: i32, note: []const u8 } = switch (c[2]) {
            'Z' => .{ .exp = -3, .note = "Z is not in Yageo's table" },
            'Y' => .{ .exp = -2, .note = "" },
            'R' => .{ .exp = -2, .note = "R = Y on some makers' parts" },
            'X' => .{ .exp = -1, .note = "" },
            'S' => .{ .exp = -1, .note = "S = X on some makers' parts" },
            'A' => .{ .exp = 0, .note = "" },
            'B' => .{ .exp = 1, .note = "" },
            'H' => .{ .exp = 1, .note = "H = B on some makers' parts" },
            'C' => .{ .exp = 2, .note = "" },
            'D' => .{ .exp = 3, .note = "" },
            'E' => .{ .exp = 4, .note = "" },
            'F' => .{ .exp = 5, .note = "" },
            else => null,
        };
        if (m) |mm| if (index >= 1 and index <= 96) {
            const sig: f64 = @floatFromInt(eseries.Series.e96.values()[index - 1]);
            out[n] = .{
                .scheme = "EIA-96",
                .value = units.scaleInt(sig, mm.exp),
                .note = if (mm.note.len > 0) mm.note else "E96, 1 % or better",
            };
            n += 1;
        };
    }
    return out[0..n];
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| if (ch < '0' or ch > '9') return false;
    return true;
}

fn allChar(s: []const u8, want: u8) bool {
    for (s) |ch| if (ch != want) return false;
    return true;
}

// ---- Colour bands ----------------------------------------------------------

pub const Colour = enum {
    black,
    brown,
    red,
    orange,
    yellow,
    green,
    blue,
    violet,
    grey,
    white,
    gold,
    silver,
    pink,
    none,

    pub fn parse(text: []const u8) ?Colour {
        const table = .{
            .{ "black", Colour.black },   .{ "blk", Colour.black },
            .{ "brown", Colour.brown },   .{ "brn", Colour.brown },
            .{ "red", Colour.red },       .{ "orange", Colour.orange },
            .{ "org", Colour.orange },    .{ "yellow", Colour.yellow },
            .{ "yel", Colour.yellow },    .{ "green", Colour.green },
            .{ "grn", Colour.green },     .{ "blue", Colour.blue },
            .{ "blu", Colour.blue },      .{ "violet", Colour.violet },
            .{ "vio", Colour.violet },    .{ "purple", Colour.violet },
            .{ "grey", Colour.grey },     .{ "gray", Colour.grey },
            .{ "gry", Colour.grey },      .{ "white", Colour.white },
            .{ "wht", Colour.white },     .{ "gold", Colour.gold },
            .{ "gld", Colour.gold },      .{ "silver", Colour.silver },
            .{ "slv", Colour.silver },    .{ "pink", Colour.pink },
            .{ "pnk", Colour.pink },      .{ "none", Colour.none },
        };
        inline for (table) |entry| {
            if (std.ascii.eqlIgnoreCase(text, entry[0])) return entry[1];
        }
        return null;
    }

    pub fn digit(self: Colour) ?u8 {
        const i = @intFromEnum(self);
        return if (i <= 9) @intCast(i) else null;
    }

    pub fn multiplierExp(self: Colour) ?i32 {
        return switch (self) {
            .gold => -1,
            .silver => -2,
            .pink => -3,
            .none => null,
            else => @intCast(@intFromEnum(self)),
        };
    }

    /// Tolerance in percent (IEC 60062:2016; grey was ±0.05 % before 2016).
    pub fn tolerance(self: Colour) ?f64 {
        return switch (self) {
            .none => 20,
            .silver => 10,
            .gold => 5,
            .brown => 1,
            .red => 2,
            .orange => 0.05,
            .yellow => 0.02,
            .green => 0.5,
            .blue => 0.25,
            .violet => 0.1,
            .grey => 0.01,
            else => null,
        };
    }

    /// Temperature coefficient in ppm/K, the sixth band.
    pub fn tcr(self: Colour) ?f64 {
        return switch (self) {
            .black => 250,
            .brown => 100,
            .red => 50,
            .orange => 15,
            .yellow => 25,
            .green => 20,
            .blue => 10,
            .violet => 5,
            .grey => 1,
            else => null,
        };
    }
};

pub const BandError = error{ Count, Digit, Multiplier, Tolerance, Tcr };

pub const BandValue = struct {
    value: f64,
    tolerance: f64,
    tcr: ?f64,
};

/// Reads 4 (two digits), 5 (three digits) or 6 (plus TCR) bands, from the
/// end opposite the tolerance band.
pub fn decodeBands(bands: []const Colour) BandError!BandValue {
    if (bands.len < 4 or bands.len > 6) return error.Count;
    const digits: usize = if (bands.len == 4) 2 else 3;
    var sig: f64 = 0;
    for (bands[0..digits]) |b| {
        sig = sig * 10 + @as(f64, @floatFromInt(b.digit() orelse return error.Digit));
    }
    const exp = bands[digits].multiplierExp() orelse return error.Multiplier;
    // No tolerance band (±20 %) exists only in the two-digit code
    // (IEC 60062:2016 3.3.1); three digits always carry a tolerance band.
    if (bands[digits + 1] == .none and digits == 3) return error.Tolerance;
    const tol = bands[digits + 1].tolerance() orelse return error.Tolerance;
    const t: ?f64 = if (bands.len == 6) (bands[5].tcr() orelse return error.Tcr) else null;
    return .{ .value = units.scaleInt(sig, exp), .tolerance = tol, .tcr = t };
}

/// The tolerance band for a tolerance in percent, if there is one.
pub fn toleranceColour(percent: f64) ?Colour {
    inline for ([_]Colour{ .none, .silver, .gold, .brown, .red, .orange, .yellow, .green, .blue, .violet, .grey }) |c| {
        if (c.tolerance().? == percent) return c;
    }
    return null;
}

/// Bands for `value`: four when two digits say it, else five. 5 % and
/// looser parts take four bands where they can, the way they are made.
pub fn encodeBands(out: *[5]Colour, value: f64, tolerance_band: Colour) ?[]Colour {
    const loose = (tolerance_band.tolerance() orelse 0) >= 2;
    if (loose) {
        if (sigDigits(value, 2)) |s| if (s.exp >= -3 and s.exp <= 9) {
            out[0] = @enumFromInt(s.sig / 10);
            out[1] = @enumFromInt(s.sig % 10);
            out[2] = expColour(s.exp);
            out[3] = tolerance_band;
            return out[0..4];
        };
    }
    const s = sigDigits(value, 3) orelse return null;
    if (s.exp < -3 or s.exp > 9) return null;
    out[0] = @enumFromInt(s.sig / 100);
    out[1] = @enumFromInt(s.sig / 10 % 10);
    out[2] = @enumFromInt(s.sig % 10);
    out[3] = expColour(s.exp);
    out[4] = tolerance_band;
    return out[0..5];
}

fn expColour(exp: i32) Colour {
    return switch (exp) {
        -3 => .pink,
        -2 => .silver,
        -1 => .gold,
        else => @enumFromInt(@as(u8, @intCast(exp))),
    };
}

// ---- Tests -------------------------------------------------------------------

const testing = std.testing;

test "significant digits" {
    try testing.expectEqual(Sig{ .sig = 47, .exp = 2 }, sigDigits(4700, 2).?);
    try testing.expectEqual(Sig{ .sig = 499, .exp = 1 }, sigDigits(4990, 3).?);
    try testing.expectEqual(Sig{ .sig = 470, .exp = 1 }, sigDigits(4700, 3).?);
    try testing.expect(sigDigits(4990, 2) == null);
    try testing.expectEqual(Sig{ .sig = 47, .exp = -2 }, sigDigits(0.47, 2).?);
}

test "value to SMD codes, Yageo's examples" {
    var b: [16]u8 = undefined;
    try testing.expectEqualStrings("244", threeDigit(&b, 240e3).?);
    try testing.expectEqualStrings("240", threeDigit(&b, 24).?);
    try testing.expectEqualStrings("6R8", threeDigit(&b, 6.8).?);
    try testing.expectEqualStrings("R22", threeDigit(&b, 0.22).?);
    try testing.expectEqualStrings("3160", fourDigit(&b, 316).?);
    try testing.expectEqualStrings("1002", fourDigit(&b, 10e3).?);
    try testing.expectEqualStrings("31R6", fourDigit(&b, 31.6).?);
    try testing.expectEqualStrings("R220", fourDigit(&b, 0.22).?);
    try testing.expectEqualStrings("4R99", fourDigit(&b, 4.99).?);
    try testing.expectEqualStrings("88A", eia96(&b, 806).?);
    try testing.expectEqualStrings("01C", eia96(&b, 10e3).?);
    try testing.expectEqualStrings("68C", eia96(&b, 49.9e3).?);
    try testing.expect(threeDigit(&b, 4990) == null);
    try testing.expect(eia96(&b, 4700) == null);
}

fn expectReading(code: []const u8, scheme: []const u8, value: f64) !void {
    var out: [max_readings]Reading = undefined;
    for (decode(code, &out)) |r| {
        if (std.mem.eql(u8, r.scheme, scheme)) return testing.expectApproxEqRel(value, r.value, 1e-12);
    }
    std.debug.print("no {s} reading for {s}\n", .{ scheme, code });
    return error.TestExpectedEqual;
}

test "code to value" {
    try expectReading("472", "3-digit", 4700);
    try expectReading("244", "3-digit", 240e3);
    try expectReading("100", "3-digit", 10);
    try expectReading("4991", "4-digit", 4990);
    try expectReading("3160", "4-digit", 316);
    try expectReading("4R7", "R as decimal point", 4.7);
    try expectReading("r47", "R as decimal point", 0.47);
    try expectReading("31R6", "R as decimal point", 31.6);
    try expectReading("88A", "EIA-96", 806);
    try expectReading("01C", "EIA-96", 10e3);
    try expectReading("01Y", "EIA-96", 1);
    try expectReading("96F", "EIA-96", 97.6e6);
    // Both readings of an ambiguous code.
    try expectReading("10R", "R as decimal point", 10);
    try expectReading("10R", "EIA-96", 1.24);
    try expectReading("000", "Jumper", 0);
    var out: [max_readings]Reading = undefined;
    try testing.expectEqual(@as(usize, 0), decode("abc", &out).len);
    try testing.expectEqual(@as(usize, 0), decode("97A", &out).len);
}

test "round trip every E96 value through the codes" {
    var b: [16]u8 = undefined;
    var out: [max_readings]Reading = undefined;
    var d: i32 = 0;
    while (d <= 7) : (d += 1) for (eseries.Series.e96.values()) |m| {
        const v = eseries.valueAt(m, d);
        const code = eia96(&b, v).?;
        var found = false;
        for (decode(code, &out)) |r| found = found or (std.mem.eql(u8, r.scheme, "EIA-96") and @abs(r.value - v) <= v * 1e-12);
        try testing.expect(found);
    };
}

test "colour bands" {
    // 4.7 kΩ 5 %: yellow violet red gold.
    var bands = [_]Colour{ .yellow, .violet, .red, .gold };
    const v = try decodeBands(&bands);
    try testing.expectEqual(@as(f64, 4700), v.value);
    try testing.expectEqual(@as(f64, 5), v.tolerance);
    // 4.99 kΩ 1 %: yellow white white brown brown.
    var five = [_]Colour{ .yellow, .white, .white, .brown, .brown };
    try testing.expectEqual(@as(f64, 4990), (try decodeBands(&five)).value);
    var six = [_]Colour{ .brown, .black, .black, .red, .violet, .red };
    const s = try decodeBands(&six);
    try testing.expectEqual(@as(f64, 10e3), s.value);
    try testing.expectEqual(@as(f64, 0.1), s.tolerance);
    try testing.expectEqual(@as(f64, 50), s.tcr.?);
    var bad = [_]Colour{ .gold, .violet, .red, .gold };
    try testing.expectError(error.Digit, decodeBands(&bad));
    var no_tol_five = [_]Colour{ .brown, .black, .red, .gold, .none };
    try testing.expectError(error.Tolerance, decodeBands(&no_tol_five));
    var no_tol_four = [_]Colour{ .yellow, .violet, .red, .none };
    try testing.expectEqual(@as(f64, 20), (try decodeBands(&no_tol_four)).tolerance);
    var bad_tol = [_]Colour{ .yellow, .violet, .red, .white };
    try testing.expectError(error.Tolerance, decodeBands(&bad_tol));

    var out: [5]Colour = undefined;
    try testing.expectEqualSlices(Colour, &.{ .yellow, .violet, .red, .gold }, encodeBands(&out, 4700, .gold).?);
    try testing.expectEqualSlices(Colour, &.{ .yellow, .violet, .black, .brown, .brown }, encodeBands(&out, 4700, .brown).?);
    try testing.expectEqualSlices(Colour, &.{ .yellow, .violet, .gold, .gold }, encodeBands(&out, 4.7, .gold).?);
    try testing.expectEqualSlices(Colour, &.{ .yellow, .violet, .black, .silver, .green }, encodeBands(&out, 4.7, .green).?);
    try testing.expectEqual(Colour.violet, toleranceColour(0.1).?);
}
