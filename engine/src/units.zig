//! Engineering notation in and out: "4k7", "2R2", "100n" parse to plain
//! numbers, and plain numbers format back to "4.7 kΩ" for display.

const std = @import("std");

pub const ParseError = error{Invalid};

const Prefix = struct { text: []const u8, scale: f64 };

// Longest spellings first, so "µ" (two bytes) is matched before anything else.
const prefixes = [_]Prefix{
    .{ .text = "\u{00B5}", .scale = 1e-6 },
    .{ .text = "\u{03BC}", .scale = 1e-6 },
    .{ .text = "p", .scale = 1e-12 },
    .{ .text = "n", .scale = 1e-9 },
    .{ .text = "u", .scale = 1e-6 },
    .{ .text = "m", .scale = 1e-3 },
    .{ .text = "R", .scale = 1 },
    .{ .text = "r", .scale = 1 },
    .{ .text = "k", .scale = 1e3 },
    .{ .text = "K", .scale = 1e3 },
    .{ .text = "M", .scale = 1e6 },
    .{ .text = "G", .scale = 1e9 },
    .{ .text = "T", .scale = 1e12 },
};

// Unit symbols a user may type after the value; they carry no scale.
const unit_suffixes = [_][]const u8{ "\u{2126}", "\u{03A9}", "ohms", "ohm", "Ohms", "Ohm", "V", "A", "W" };

/// Parses a positive or negative value in engineering notation.
/// Lowercase m is milli and uppercase M is mega; a prefix may stand in for
/// the decimal point ("4k7" = 4700, "2R2" = 2.2, "R47" = 0.47).
pub fn parse(text: []const u8) ParseError!f64 {
    var buf: [64]u8 = undefined;
    var len: usize = 0;
    for (text) |c| {
        if (c == ' ' or c == '\t') continue;
        if (len == buf.len) return error.Invalid;
        buf[len] = c;
        len += 1;
    }
    var s: []const u8 = buf[0..len];
    for (unit_suffixes) |suffix| {
        if (s.len > suffix.len and std.mem.endsWith(u8, s, suffix)) {
            s = s[0 .. s.len - suffix.len];
            break;
        }
    }
    if (s.len == 0) return error.Invalid;

    var scale: f64 = 1;
    var number: []const u8 = s;
    var joined: [66]u8 = undefined;

    if (findPrefix(s)) |hit| {
        const left = s[0..hit.index];
        const right = s[hit.index + hit.prefix.text.len ..];
        scale = hit.prefix.scale;
        if (right.len > 0) {
            // Prefix used as the decimal point: both halves must be digits.
            if (!allDigits(right)) return error.Invalid;
            if (std.mem.indexOfScalar(u8, left, '.') != null) return error.Invalid;
            // Only R may open a value ("R47" = 0.47); "k7" is a typo, not 700.
            if (left.len == 0 and hit.prefix.scale != 1) return error.Invalid;
            const lead = if (left.len == 0) "0" else left;
            if (!allDigits(if (lead[0] == '-' or lead[0] == '+') lead[1..] else lead)) return error.Invalid;
            const out = std.fmt.bufPrint(&joined, "{s}.{s}", .{ lead, right }) catch return error.Invalid;
            number = out;
        } else {
            if (left.len == 0) return error.Invalid;
            number = left;
        }
    }

    if (!plainNumber(number)) return error.Invalid;
    const value = std.fmt.parseFloat(f64, number) catch return error.Invalid;
    const result = value * scale;
    // Beyond these, products and quotients in the calculators overflow or
    // underflow; no component or supply lives out there anyway.
    if (!std.math.isFinite(result)) return error.Invalid;
    // parseFloat rounds 1e-400 to 0; only a written zero may be zero.
    if (result == 0 and hasNonZeroDigit(number)) return error.Invalid;
    if (result != 0 and (@abs(result) < 1e-15 or @abs(result) > 1e15)) return error.Invalid;
    return result;
}

const PrefixHit = struct { index: usize, prefix: Prefix };

fn findPrefix(s: []const u8) ?PrefixHit {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        // An exponent ("1e3", "1E-3") is not a prefix position.
        for (prefixes) |p| {
            if (std.mem.startsWith(u8, s[i..], p.text)) return .{ .index = i, .prefix = p };
        }
    }
    return null;
}

fn hasNonZeroDigit(s: []const u8) bool {
    for (s) |c| {
        if (c == 'e' or c == 'E') return false;
        if (c >= '1' and c <= '9') return true;
    }
    return false;
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| if (c < '0' or c > '9') return false;
    return true;
}

/// Digits, one optional point, optional leading sign, optional exponent.
/// Rejects the words parseFloat would otherwise accept ("inf", "nan").
fn plainNumber(s: []const u8) bool {
    var i: usize = 0;
    if (i < s.len and (s[i] == '-' or s[i] == '+')) i += 1;
    var digits: usize = 0;
    var dots: usize = 0;
    while (i < s.len) : (i += 1) {
        const c = s[i];
        if (c >= '0' and c <= '9') {
            digits += 1;
        } else if (c == '.') {
            dots += 1;
            if (dots > 1) return false;
        } else if (c == 'e' or c == 'E') {
            if (digits == 0) return false;
            i += 1;
            if (i < s.len and (s[i] == '-' or s[i] == '+')) i += 1;
            return allDigits(s[i..]);
        } else return false;
    }
    return digits > 0;
}

const display_prefixes = [_][]const u8{ "p", "n", "\u{00B5}", "m", "", "k", "M", "G", "T" };

/// Formats `value` to `sig` significant figures with an SI prefix, trimming
/// trailing zeros: 4700 -> "4.7 kΩ", 0.0033 -> "3.3 mA".
pub fn format(buf: []u8, value: f64, sig: u8, unit: []const u8) []const u8 {
    if (!std.math.isFinite(value)) return std.fmt.bufPrint(buf, "—", .{}) catch buf[0..0];
    if (value == 0) return std.fmt.bufPrint(buf, "0 {s}", .{unit}) catch buf[0..0];

    const magnitude = @abs(value);
    const rounded = roundSig(magnitude, sig);
    const exponent: i32 = decadeOf(rounded);
    var group: i32 = @divFloor(exponent, 3);
    group = std.math.clamp(group, -4, 4);
    const mantissa = rounded / pow10(group * 3);
    const decimals_signed: i32 = @as(i32, sig) - 1 - (exponent - group * 3);
    const decimals: usize = @intCast(std.math.clamp(decimals_signed, 0, 9));

    var num_buf: [48]u8 = undefined;
    const num = printFixed(&num_buf, mantissa, decimals);
    const trimmed = trimZeros(num);
    const sign: []const u8 = if (value < 0) "-" else "";
    const prefix = display_prefixes[@intCast(group + 4)];
    return std.fmt.bufPrint(buf, "{s}{s} {s}{s}", .{ sign, trimmed, prefix, unit }) catch buf[0..0];
}

fn printFixed(buf: []u8, v: f64, decimals: usize) []const u8 {
    return switch (decimals) {
        0 => std.fmt.bufPrint(buf, "{d:.0}", .{v}),
        1 => std.fmt.bufPrint(buf, "{d:.1}", .{v}),
        2 => std.fmt.bufPrint(buf, "{d:.2}", .{v}),
        3 => std.fmt.bufPrint(buf, "{d:.3}", .{v}),
        4 => std.fmt.bufPrint(buf, "{d:.4}", .{v}),
        5 => std.fmt.bufPrint(buf, "{d:.5}", .{v}),
        6 => std.fmt.bufPrint(buf, "{d:.6}", .{v}),
        7 => std.fmt.bufPrint(buf, "{d:.7}", .{v}),
        8 => std.fmt.bufPrint(buf, "{d:.8}", .{v}),
        else => std.fmt.bufPrint(buf, "{d:.9}", .{v}),
    } catch buf[0..0];
}

fn trimZeros(s: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, s, '.') == null) return s;
    var end = s.len;
    while (end > 0 and s[end - 1] == '0') end -= 1;
    if (end > 0 and s[end - 1] == '.') end -= 1;
    return s[0..end];
}

/// 10^e, computed so that exact powers stay exact in both directions.
pub fn pow10(e: i32) f64 {
    if (e >= 0) return std.math.pow(f64, 10, @floatFromInt(e));
    return 1 / std.math.pow(f64, 10, @floatFromInt(-e));
}

/// Multiplies an integer mantissa by 10^e without the error that a
/// negative-power multiply introduces (470 * 0.01 != 4.7 exactly).
pub fn scaleInt(mantissa: f64, e: i32) f64 {
    if (e >= 0) return mantissa * std.math.pow(f64, 10, @floatFromInt(e));
    return mantissa / std.math.pow(f64, 10, @floatFromInt(-e));
}

/// floor(log10(v)) for v > 0, corrected for log10 landing just under an
/// exact power of ten.
pub fn decadeOf(v: f64) i32 {
    var d: i32 = @intFromFloat(@floor(std.math.log10(v)));
    while (v / pow10(d) >= 10) d += 1;
    while (v / pow10(d) < 1) d -= 1;
    return d;
}

fn roundSig(v: f64, sig: u8) f64 {
    const d = decadeOf(v);
    const shift: i32 = @as(i32, sig) - 1 - d;
    if (shift >= 0) return @round(v * pow10(shift)) / pow10(shift);
    return @round(v / pow10(-shift)) * pow10(-shift);
}

const testing = std.testing;

test "parse engineering notation" {
    try testing.expectEqual(@as(f64, 4700), try parse("4k7"));
    try testing.expectEqual(@as(f64, 4700), try parse("4.7k"));
    try testing.expectEqual(@as(f64, 2.2), try parse("2R2"));
    try testing.expectEqual(@as(f64, 0.47), try parse("R47"));
    try testing.expectEqual(@as(f64, 1e7), try parse("10M"));
    try testing.expectApproxEqRel(@as(f64, 1e-3), try parse("1m"), 1e-12);
    try testing.expectApproxEqRel(@as(f64, 100e-9), try parse("100n"), 1e-12);
    try testing.expectApproxEqRel(@as(f64, 47e-6), try parse("47u"), 1e-12);
    try testing.expectApproxEqRel(@as(f64, 47e-6), try parse("47\u{00B5}"), 1e-12);
    try testing.expectEqual(@as(f64, 3.3), try parse("3.3"));
    try testing.expectEqual(@as(f64, 3.3), try parse("3.3V"));
    try testing.expectEqual(@as(f64, 4700), try parse("4.7 k\u{2126}"));
    try testing.expectEqual(@as(f64, 1000), try parse("1e3"));
    try testing.expectEqual(@as(f64, 1e6), try parse("1M"));
}

test "parse rejects garbage" {
    const bad = [_][]const u8{ "", "k", "abc", "4.7k7", "1..2", "inf", "nan", "4k7k", "k7", "1.2.3", "--1", "V", "1_000", "1e-400", "1e300", "1e16" };
    for (bad) |b| try testing.expectError(error.Invalid, parse(b));
}

test "format with prefixes" {
    var buf: [64]u8 = undefined;
    try testing.expectEqualStrings("4.7 k\u{2126}", format(&buf, 4700, 3, "\u{2126}"));
    try testing.expectEqualStrings("10 k\u{2126}", format(&buf, 10000, 3, "\u{2126}"));
    try testing.expectEqualStrings("1.02 k\u{2126}", format(&buf, 1020, 3, "\u{2126}"));
    try testing.expectEqualStrings("3.3 mA", format(&buf, 0.0033, 3, "A"));
    try testing.expectEqualStrings("1 k\u{2126}", format(&buf, 999.96, 3, "\u{2126}"));
    try testing.expectEqualStrings("470 m\u{2126}", format(&buf, 0.47, 3, "\u{2126}"));
    try testing.expectEqualStrings("-1.5 V", format(&buf, -1.5, 3, "V"));
    try testing.expectEqualStrings("0 V", format(&buf, 0, 3, "V"));
}

test "decade of exact powers" {
    try testing.expectEqual(@as(i32, 3), decadeOf(1000));
    try testing.expectEqual(@as(i32, -3), decadeOf(0.001));
    try testing.expectEqual(@as(i32, 2), decadeOf(999.9));
}
