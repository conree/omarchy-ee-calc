//! Resistor packages, their power ratings, and manufacturer part numbers
//! built offline from each maker's published ordering-code scheme.
//!
//! Sources (manufacturer datasheets, checked 2026-09-30):
//!   Yageo RC_L thick film chip, "PYu-RC_Group_51_RoHS_L" V.14, 2025-11-14
//!   Vishay D/CRCW e3 thick film chip, doc. 20035, rev. 2026-04-14
//!   Panasonic ERJ ±1 % precision thick film, AOA0000C304, 2025-05-29
//!   Panasonic ERJ ±5 % thick film, AOA0000C301, 2022-12-22
//!   Yageo MFR metal film through hole, "YAGEO-MFR_DATASHEET" V.4, 2024-04-03
//! Precision thin film, 0.5 % and 0.1 % (checked 2026-10-05):
//!   Yageo RT thin film chip, "PYu-RT_1-to-0.01_RoHS_L" V.17, 2026-02-12
//!   Vishay TNPW e3 thin film chip, doc. 28758, rev. 2026-04-10
//!   Panasonic ERA A type thin film chip, AOA0000C307, 2024-04-24

const std = @import("std");
const units = @import("units.zig");
const eseries = @import("eseries.zig");

pub const Package = enum {
    p0402,
    p0603,
    p0805,
    p1206,
    tht_quarter,
    tht_half,

    pub fn name(self: Package) []const u8 {
        return switch (self) {
            .p0402 => "0402",
            .p0603 => "0603",
            .p0805 => "0805",
            .p1206 => "1206",
            .tht_quarter => "THT 1/4 W",
            .tht_half => "THT 1/2 W",
        };
    }

    pub fn parse(text: []const u8) ?Package {
        const table = .{
            .{ "0402", Package.p0402 },     .{ "0603", Package.p0603 },
            .{ "0805", Package.p0805 },     .{ "1206", Package.p1206 },
            .{ "tht-quarter", Package.tht_quarter }, .{ "tht-half", Package.tht_half },
        };
        inline for (table) |entry| {
            if (std.ascii.eqlIgnoreCase(text, entry[0])) return entry[1];
        }
        return null;
    }

    /// The rating the power check uses: the lowest standard rating among
    /// the makers offered for this package, so a pass holds for any of them.
    pub fn rating(self: Package) f64 {
        return switch (self) {
            .p0402 => 1.0 / 16.0, // Yageo RC0402 1/16 W (Panasonic and Vishay 0.1 W)
            .p0603 => 0.1, // Yageo RC0603 1/10 W, Panasonic ERJ-3 0.1 W (Vishay 0.125 W)
            .p0805 => 0.125, // Yageo RC0805 1/8 W, Panasonic ERJ-6 0.125 W (Vishay 0.25 W)
            .p1206 => 0.25, // all three 0.25 W
            .tht_quarter => 0.25, // Yageo MFR-25
            .tht_half => 0.5, // Yageo MFR-50
        };
    }
};

pub const Tolerance = enum {
    tenth,
    half,
    one,
    five,

    pub fn name(self: Tolerance) []const u8 {
        return switch (self) {
            .tenth => "0.1%",
            .half => "0.5%",
            .one => "1%",
            .five => "5%",
        };
    }

    pub fn parse(text: []const u8) ?Tolerance {
        const table = .{
            .{ "0.1", Tolerance.tenth }, .{ "0.5", Tolerance.half },
            .{ "1", Tolerance.one },     .{ "5", Tolerance.five },
        };
        const t = if (std.mem.endsWith(u8, text, "%")) text[0 .. text.len - 1] else text;
        inline for (table) |entry| {
            if (std.mem.eql(u8, t, entry[0])) return entry[1];
        }
        return null;
    }

    /// 0.5 % and 0.1 % are thin film parts with their own makers' series.
    pub fn precision(self: Tolerance) bool {
        return self == .tenth or self == .half;
    }

    /// The tolerance letter Yageo, Vishay and Panasonic share (IEC 60062).
    fn letter(self: Tolerance) u8 {
        return switch (self) {
            .tenth => 'B',
            .half => 'D',
            .one => 'F',
            .five => 'J',
        };
    }
};

pub const Part = struct {
    maker: []const u8,
    family: []const u8,
    mpn: []const u8,
    power: f64,
    /// Panasonic marks some sizes "not recommended for new design".
    nrfnd: bool = false,
};

pub const Result = struct {
    parts: []const Part,
    /// Why nothing (or something) was left out, for the panel to show.
    note: []const u8 = "",
};

// ---- Value codes ----------------------------------------------------------

/// Splits a standard value into its three significant digits (100..999)
/// and the power of ten they are scaled by: 4990 -> {499, 1}.
const Digits = struct { sig: u32, exp: i32 };

fn digits(value: f64) Digits {
    const d = units.decadeOf(value);
    const sig: u32 = @intFromFloat(@round(value / units.pow10(d - 2)));
    if (sig >= 1000) return .{ .sig = sig / 10, .exp = d - 1 };
    return .{ .sig = sig, .exp = d - 2 };
}

/// Letter-as-decimal-point code with three significant digits:
/// R below 1 kΩ, K below 1 MΩ, M above. Returns the integer part, the
/// letter, and the three-digit fraction string to trim as each maker wants.
fn rkmParts(value: f64) struct { whole: u32, letter: u8, frac: [3]u8, frac_len: usize } {
    const unit: f64, const letter: u8 = if (value < 1e3 * (1 - 1e-9))
        .{ 1, 'R' }
    else if (value < 1e6 * (1 - 1e-9))
        .{ 1e3, 'K' }
    else
        .{ 1e6, 'M' };
    // Hundredths of the scaled value, rounded: exact for 3-significant-digit
    // standard values from 1 Ω upward.
    const scaled: u64 = @intFromFloat(@round(value / unit * 100));
    const whole: u32 = @intCast(scaled / 100);
    const cents: u32 = @intCast(scaled % 100);
    const frac: [3]u8 = .{ '0' + @as(u8, @intCast(cents / 10)), '0' + @as(u8, @intCast(cents % 10)), '0' };
    return .{ .whole = whole, .letter = letter, .frac = frac, .frac_len = 2 };
}

/// Yageo (RC, MFR): the shortest form, trailing zeros dropped.
/// 97R6, 9K76, 1M, 100K, 10R, 2R2, 4K99.
pub fn yageoCode(buf: []u8, value: f64) []const u8 {
    const p = rkmParts(value);
    var frac_len: usize = p.frac_len;
    while (frac_len > 0 and p.frac[frac_len - 1] == '0') frac_len -= 1;
    return std.fmt.bufPrint(buf, "{d}{c}{s}", .{ p.whole, p.letter, p.frac[0..frac_len] }) catch buf[0..0];
}

/// Vishay CRCW: always four characters, three significant digits.
/// 562R, 10K0, 1K00, 100K, 4K99, 1M00, 10R0, 1R00.
pub fn vishayCode(buf: []u8, value: f64) []const u8 {
    const p = rkmParts(value);
    var whole_buf: [8]u8 = undefined;
    const whole = std.fmt.bufPrint(&whole_buf, "{d}", .{p.whole}) catch return buf[0..0];
    const need = 3 -| whole.len;
    return std.fmt.bufPrint(buf, "{s}{c}{s}", .{ whole, p.letter, p.frac[0..need] }) catch buf[0..0];
}

/// Panasonic ±1 %: three significant digits and a multiplier; below
/// 100 Ω the decimal point is R. 1002 = 10 kΩ, 4991 = 4.99 kΩ, 49R9.
pub fn panasonic4(buf: []u8, value: f64) []const u8 {
    if (value < 100 * (1 - 1e-9)) {
        const cents: u32 = @intFromFloat(@round(value * 100));
        if (value < 10 * (1 - 1e-9))
            return std.fmt.bufPrint(buf, "{d}R{d:0>2}", .{ cents / 100, cents % 100 }) catch buf[0..0];
        const tenths: u32 = @intFromFloat(@round(value * 10));
        return std.fmt.bufPrint(buf, "{d}R{d}", .{ tenths / 10, tenths % 10 }) catch buf[0..0];
    }
    const g = digits(value);
    return std.fmt.bufPrint(buf, "{d}{d}", .{ g.sig, g.exp }) catch buf[0..0];
}

/// Panasonic ±5 %: two significant digits and a multiplier; below 10 Ω
/// the decimal point is R. 222 = 2.2 kΩ, 4R7 = 4.7 Ω.
pub fn panasonic3(buf: []u8, value: f64) []const u8 {
    if (value < 10 * (1 - 1e-9)) {
        const tenths: u32 = @intFromFloat(@round(value * 10));
        return std.fmt.bufPrint(buf, "{d}R{d}", .{ tenths / 10, tenths % 10 }) catch buf[0..0];
    }
    const g = digits(value);
    return std.fmt.bufPrint(buf, "{d}{d}", .{ g.sig / 10, g.exp + 1 }) catch buf[0..0];
}

// ---- Availability ---------------------------------------------------------

/// 5 % parts are E24 only; 1 % parts come in every E24 and E96 value.
/// At 0.5 % and 0.1 % Vishay TNPW also makes every E192 value; Yageo RT
/// and Panasonic ERA list E24 and E96 only (E192 "on request").
pub fn offered(value: f64, tolerance: Tolerance) bool {
    if (eseries.nearest(.e24, value).exact) return true;
    return switch (tolerance) {
        .five => false,
        .one => eseries.nearest(.e96, value).exact,
        .half, .tenth => eseries.nearest(.e192, value).exact,
    };
}

fn e24OrE96(value: f64) bool {
    return eseries.nearest(.e24, value).exact or eseries.nearest(.e96, value).exact;
}

fn within(value: f64, lo: f64, hi: f64) bool {
    return value >= lo * (1 - 1e-9) and value <= hi * (1 + 1e-9);
}

// ---- Part numbers ---------------------------------------------------------

pub const max_parts = 3;

/// Part numbers for one value. `storage` holds the strings; the returned
/// slices point into it. A value outside every maker's range, or not made
/// at this tolerance, returns no parts and a note saying why.
pub fn lookup(storage: *[max_parts][40]u8, out: *[max_parts]Part, value: f64, package: Package, tolerance: Tolerance) Result {
    if (!offered(value, tolerance)) {
        return .{ .parts = out[0..0], .note = switch (tolerance) {
            .five => "not made at 5 % (E24 values only)",
            .one => "not a standard E24 or E96 value",
            .half, .tenth => "not a standard E24 or E192 value",
        } };
    }
    if (tolerance.precision()) return precisionLookup(storage, out, value, package, tolerance);

    var n: usize = 0;
    var code: [16]u8 = undefined;

    switch (package) {
        .p0402, .p0603, .p0805, .p1206 => {
            const size = package.name();

            // Yageo RC: RC0603FR-074K99L. Standard power, 7" paper reel.
            const y_hi: f64 = if (tolerance == .one) 10e6 else switch (package) {
                .p0603 => 22e6,
                else => 100e6,
            };
            if (within(value, 1, y_hi)) {
                const s = std.fmt.bufPrint(&storage[n], "RC{s}{c}R-07{s}L", .{
                    size, @as(u8, if (tolerance == .one) 'F' else 'J'), yageoCode(&code, value),
                }) catch unreachable;
                out[n] = .{ .maker = "Yageo", .family = "RC", .mpn = s, .power = package.rating() };
                n += 1;
            }

            // Vishay CRCW e3: CRCW06034K99FKEA. The ±100 ppm (K) line covers
            // 1 Ω to 10 MΩ at 1 %, so 1 % always takes the tighter code.
            if (within(value, 1, 10e6)) {
                const tc: []const u8 = if (tolerance == .five) "JN" else "FK";
                const pack: []const u8 = if (package == .p0402) "ED" else "EA";
                const s = std.fmt.bufPrint(&storage[n], "CRCW{s}{s}{s}{s}", .{ size, vishayCode(&code, value), tc, pack }) catch unreachable;
                // Standard-mode dissipation; the headline 0.1/0.125/0.25 W
                // figures are Vishay's extended mode.
                const p: f64 = switch (package) {
                    .p0402 => 0.063,
                    .p0603 => 0.1,
                    .p0805 => 0.125,
                    else => 0.25,
                };
                out[n] = .{ .maker = "Vishay", .family = "CRCW e3", .mpn = s, .power = p };
                n += 1;
            }

            // Panasonic ERJ: ERJ3EKF4991V (1 %), ERJ3GEYJ472V (5 %). The
            // datasheets print part numbers without the hyphen distributors add.
            // 0402 drops the marking letter and packs on 2 mm pitch (X).
            if (tolerance == .one) {
                const series: []const u8 = switch (package) {
                    .p0402 => "2RK",
                    .p0603 => "3EK",
                    .p0805 => "6EN",
                    else => "8EN",
                };
                const hi: f64 = if (package == .p0805 or package == .p1206) 2.2e6 else 1e6;
                if (within(value, 10, hi)) {
                    const pack: u8 = if (package == .p0402) 'X' else 'V';
                    const s = std.fmt.bufPrint(&storage[n], "ERJ{s}F{s}{c}", .{ series, panasonic4(&code, value), pack }) catch unreachable;
                    out[n] = .{ .maker = "Panasonic", .family = "ERJ", .mpn = s, .power = panasonicPower(package), .nrfnd = package == .p1206 };
                    n += 1;
                }
            } else if (within(value, 1, 10e6)) {
                const s = switch (package) {
                    .p0402 => std.fmt.bufPrint(&storage[n], "ERJ2GEJ{s}X", .{panasonic3(&code, value)}),
                    else => std.fmt.bufPrint(&storage[n], "ERJ{s}GEYJ{s}V", .{
                        @as([]const u8, switch (package) {
                            .p0603 => "3",
                            .p0805 => "6",
                            else => "8",
                        }), panasonic3(&code, value),
                    }),
                } catch unreachable;
                out[n] = .{ .maker = "Panasonic", .family = "ERJ", .mpn = s, .power = panasonicPower(package), .nrfnd = package == .p1206 };
                n += 1;
            }

            if (n == 0) return .{ .parts = out[0..0], .note = "outside every maker's range for this size" };
            return .{ .parts = out[0..n] };
        },
        .tht_quarter, .tht_half => {
            // Yageo MFR metal film, 52.4 mm tape forming. 1 %: bulk, ±100 ppm
            // (MFR-25FBF52-10K). 5 %: box pack, TCR per spec (MFR-25JT-52-4K7).
            if (!within(value, 1, 4.7e6))
                return .{ .parts = out[0..0], .note = "outside the 1 \u{03A9} to 4.7 M\u{03A9} range" };
            const series: []const u8 = if (package == .tht_quarter) "-25" else "-50";
            const s = (if (tolerance == .one)
                std.fmt.bufPrint(&storage[0], "MFR{s}FBF52-{s}", .{ series, yageoCode(&code, value) })
            else
                std.fmt.bufPrint(&storage[0], "MFR{s}JT-52-{s}", .{ series, yageoCode(&code, value) })) catch unreachable;
            out[0] = .{ .maker = "Yageo", .family = "MFR", .mpn = s, .power = package.rating() };
            return .{ .parts = out[0..1] };
        },
    }
}

/// 0.5 % and 0.1 % thin film chips, all at ±25 ppm/K where the maker
/// offers it, since that is the line each maker stocks for these tolerances.
fn precisionLookup(storage: *[max_parts][40]u8, out: *[max_parts]Part, value: f64, package: Package, tolerance: Tolerance) Result {
    if (package == .tht_quarter or package == .tht_half)
        return .{ .parts = out[0..0], .note = "no through-hole part at this tolerance" };

    var n: usize = 0;
    var code: [16]u8 = undefined;
    const size = package.name();
    const tol = tolerance.letter();

    // Yageo RT: RT0603BRD0710KL. D = ±25 ppm/K, 07 = 7" reel. E24/E96
    // values only; the ±25 ppm ranges are the same at 0.5 % and 0.1 %.
    if (e24OrE96(value)) {
        const lo: f64, const hi: f64 = switch (package) {
            .p0402 => .{ 4.7, 240e3 },
            .p0603 => .{ 1, 1e6 },
            else => .{ 1, 1.5e6 },
        };
        if (within(value, lo, hi)) {
            const s = std.fmt.bufPrint(&storage[n], "RT{s}{c}RD07{s}L", .{ size, tol, yageoCode(&code, value) }) catch unreachable;
            out[n] = .{ .maker = "Yageo", .family = "RT 25 ppm", .mpn = s, .power = package.rating() };
            n += 1;
        }
    }

    // Vishay TNPW e3: TNPW06034K99BEEA. E = ±25 ppm/K; EA reel, ED for
    // 0402. E24 and E192 values. Power is the "general" operation mode.
    {
        const lo: f64 = switch (package) {
            .p0402 => if (tolerance == .tenth) 47 else 10,
            else => if (tolerance == .tenth) 3.5 else 1,
        };
        const hi: f64 = switch (package) {
            .p0402 => 100e3,
            .p0603 => 332e3,
            .p0805 => 1e6,
            else => 2e6,
        };
        if (within(value, lo, hi)) {
            const pack: []const u8 = if (package == .p0402) "ED" else "EA";
            const s = std.fmt.bufPrint(&storage[n], "TNPW{s}{s}{c}E{s}", .{ size, vishayCode(&code, value), tol, pack }) catch unreachable;
            const p: f64 = switch (package) {
                .p0402 => 0.07,
                .p0603 => 0.11,
                .p0805 => 0.14,
                else => 0.27,
            };
            out[n] = .{ .maker = "Vishay", .family = "TNPW e3 25 ppm", .mpn = s, .power = p };
            n += 1;
        }
    }

    // Panasonic ERA A type: ERA3AEB102V (E24, three figures), ERA3AEB1051V
    // (E96, four). E = ±25 ppm/K from 47 Ω; below that only 0.5 % exists,
    // at ±50 ppm/K (H), or ±100 ppm/K (K) in 0402. X = 0402 reel, else V.
    if (e24OrE96(value)) {
        const hi: f64 = switch (package) {
            .p0402 => 100e3,
            .p0603 => 330e3,
            else => 1e6,
        };
        const tcr: ?u8 = if (within(value, 47, hi))
            'E'
        else if (tolerance == .half and within(value, 10, 46.4))
            (if (package == .p0402) 'K' else 'H')
        else
            null;
        if (tcr) |t| {
            const sz: u8 = switch (package) {
                .p0402 => '2',
                .p0603 => '3',
                .p0805 => '6',
                else => '8',
            };
            const v = if (eseries.nearest(.e24, value).exact) panasonic3(&code, value) else panasonic4(&code, value);
            const pack: u8 = if (package == .p0402) 'X' else 'V';
            const s = std.fmt.bufPrint(&storage[n], "ERA{c}A{c}{c}{s}{c}", .{ sz, t, tol, v, pack }) catch unreachable;
            const family: []const u8 = switch (t) {
                'E' => "ERA 25 ppm",
                'H' => "ERA 50 ppm",
                else => "ERA 100 ppm",
            };
            // ERA ratings (datasheet): 0.063 / 0.1 / 0.125 / 0.25 W.
            const p: f64 = if (package == .p0402) 0.063 else package.rating();
            out[n] = .{ .maker = "Panasonic", .family = family, .mpn = s, .power = p };
            n += 1;
        }
    }

    if (n == 0) return .{ .parts = out[0..0], .note = "outside every maker's range for this size" };
    return .{ .parts = out[0..n] };
}

fn panasonicPower(package: Package) f64 {
    return switch (package) {
        .p0402, .p0603 => 0.1,
        .p0805 => 0.125,
        else => 0.25,
    };
}

pub const Load = enum { ok, high, over };

/// Within half the rating is comfortable; up to the rating works but runs
/// hot; above it the part is overloaded.
pub fn loadLevel(power: f64, rating: f64) Load {
    const u = power / rating;
    if (u <= 0.5) return .ok;
    if (u <= 1.0) return .high;
    return .over;
}

const testing = std.testing;

fn expectMpn(value: f64, package: Package, tolerance: Tolerance, maker: []const u8, want: []const u8) !void {
    var storage: [max_parts][40]u8 = undefined;
    var out: [max_parts]Part = undefined;
    const r = lookup(&storage, &out, value, package, tolerance);
    for (r.parts) |p| {
        if (std.mem.eql(u8, p.maker, maker)) return testing.expectEqualStrings(want, p.mpn);
    }
    std.debug.print("no {s} part for {d}\n", .{ maker, value });
    return error.TestExpectedEqual;
}

test "examples printed in the datasheets" {
    // Yageo RC ordering example: 100 kΩ, 5 %, 0402, 7" reel.
    try expectMpn(100e3, .p0402, .five, "Yageo", "RC0402JR-07100KL");
    // Vishay CRCW part number example: 562 Ω, 1 %, ±100 ppm, EA.
    try expectMpn(562, .p0603, .one, "Vishay", "CRCW0603562RFKEA");
    // Panasonic 5 % part number example: 1 kΩ, 0603, marked.
    try expectMpn(1e3, .p0603, .five, "Panasonic", "ERJ3GEYJ102V");
    // Panasonic 1 % part number example: 10 kΩ, 1206.
    try expectMpn(10e3, .p1206, .one, "Panasonic", "ERJ8ENF1002V");
}

test "value codes match each maker's examples" {
    var b: [16]u8 = undefined;
    // Yageo: 97R6, 9K76, 1M, 100R, 10K (RC and MFR datasheets).
    try testing.expectEqualStrings("97R6", yageoCode(&b, 97.6));
    try testing.expectEqualStrings("9K76", yageoCode(&b, 9760));
    try testing.expectEqualStrings("1M", yageoCode(&b, 1e6));
    try testing.expectEqualStrings("100R", yageoCode(&b, 100));
    try testing.expectEqualStrings("10K", yageoCode(&b, 10e3));
    // Vishay: 562R, 10R (description) -> 10R0 in the four-character code.
    try testing.expectEqualStrings("562R", vishayCode(&b, 562));
    try testing.expectEqualStrings("10R0", vishayCode(&b, 10));
    try testing.expectEqualStrings("1M00", vishayCode(&b, 1e6));
    try testing.expectEqualStrings("100K", vishayCode(&b, 100e3));
    // Panasonic: 1002 = 10 kΩ, 222 = 2.2 kΩ, 4R7 = 4.7 Ω.
    try testing.expectEqualStrings("1002", panasonic4(&b, 10e3));
    try testing.expectEqualStrings("222", panasonic3(&b, 2.2e3));
    try testing.expectEqualStrings("4R7", panasonic3(&b, 4.7));
}

test "common catalogue parts" {
    try expectMpn(4990, .p0603, .one, "Yageo", "RC0603FR-074K99L");
    try expectMpn(4990, .p0603, .one, "Vishay", "CRCW06034K99FKEA");
    try expectMpn(4990, .p0603, .one, "Panasonic", "ERJ3EKF4991V");
    try expectMpn(10e3, .p0402, .one, "Panasonic", "ERJ2RKF1002X");
    try expectMpn(1e3, .p0603, .five, "Panasonic", "ERJ3GEYJ102V");
    try expectMpn(1e3, .p0402, .five, "Panasonic", "ERJ2GEJ102X");
    try expectMpn(4.7e3, .tht_quarter, .five, "Yageo", "MFR-25JT-52-4K7");
    try expectMpn(10e3, .tht_quarter, .one, "Yageo", "MFR-25FBF52-10K");
    try expectMpn(1.8e6, .tht_quarter, .one, "Yageo", "MFR-25FBF52-1M8");
    try expectMpn(10, .p0603, .one, "Yageo", "RC0603FR-0710RL");
    try expectMpn(2.2, .p0603, .one, "Vishay", "CRCW06032R20FKEA");
}

test "availability" {
    var storage: [max_parts][40]u8 = undefined;
    var out: [max_parts]Part = undefined;
    // 4.99 kΩ is E96 only: no 5 % part.
    try testing.expectEqual(@as(usize, 0), lookup(&storage, &out, 4990, .p0603, .five).parts.len);
    // Panasonic 1 % starts at 10 Ω, so 2.2 Ω offers only two makers.
    try testing.expectEqual(@as(usize, 2), lookup(&storage, &out, 2.2, .p0603, .one).parts.len);
    // Through hole: 5 % metal film exists; above 4.7 MΩ it does not.
    try testing.expectEqual(@as(usize, 1), lookup(&storage, &out, 10e3, .tht_quarter, .five).parts.len);
    try testing.expectEqual(@as(usize, 0), lookup(&storage, &out, 10e6, .tht_quarter, .one).parts.len);
    // Panasonic 1206 is flagged as not for new designs.
    const r = lookup(&storage, &out, 10e3, .p1206, .one);
    for (r.parts) |p| if (std.mem.eql(u8, p.maker, "Panasonic")) try testing.expect(p.nrfnd);
}

test "precision parts match live catalogue numbers" {
    // Each checked against a distributor listing, 2026-10-05.
    try expectMpn(10e3, .p0603, .tenth, "Yageo", "RT0603BRD0710KL");
    try expectMpn(10e3, .p0603, .half, "Yageo", "RT0603DRD0710KL");
    try expectMpn(10e3, .p0603, .tenth, "Vishay", "TNPW060310K0BEEA");
    try expectMpn(10e3, .p0603, .half, "Vishay", "TNPW060310K0DEEA");
    try expectMpn(1010, .p0402, .tenth, "Vishay", "TNPW04021K01BEED");
    try expectMpn(10e3, .p0603, .tenth, "Panasonic", "ERA3AEB103V");
    try expectMpn(10e3, .p0603, .half, "Panasonic", "ERA3AED103V");
    try expectMpn(1050, .p0603, .tenth, "Panasonic", "ERA3AEB1051V");
}

test "precision examples printed in the datasheets" {
    // Vishay part number example: TNPW12061K32DEEA (1.32 kΩ, 0.5 %, 25 ppm).
    try expectMpn(1320, .p1206, .half, "Vishay", "TNPW12061K32DEEA");
    // Panasonic E24 example layout ERA3AEB102V (1 kΩ).
    try expectMpn(1e3, .p0603, .tenth, "Panasonic", "ERA3AEB102V");
}

test "precision availability" {
    var storage: [max_parts][40]u8 = undefined;
    var out: [max_parts]Part = undefined;
    // E192-only value: Vishay alone.
    const r = lookup(&storage, &out, 1010, .p0603, .tenth);
    try testing.expectEqual(@as(usize, 1), r.parts.len);
    try testing.expectEqualStrings("Vishay", r.parts[0].maker);
    // Not a standard value at all.
    try testing.expectEqual(@as(usize, 0), lookup(&storage, &out, 1234, .p0603, .tenth).parts.len);
    // No through-hole precision part.
    try testing.expectEqual(@as(usize, 0), lookup(&storage, &out, 10e3, .tht_quarter, .tenth).parts.len);
    // 22 Ω at 0.5 %: Panasonic switches to ±50 ppm/K.
    try expectMpn(22, .p0603, .half, "Panasonic", "ERA3AHD220V");
    // ... and has nothing at 0.1 %.
    for (lookup(&storage, &out, 22, .p0603, .tenth).parts) |p| try testing.expect(!std.mem.eql(u8, p.maker, "Panasonic"));
}

test "load levels" {
    try testing.expectEqual(Load.ok, loadLevel(0.05, 0.1));
    try testing.expectEqual(Load.high, loadLevel(0.08, 0.1));
    try testing.expectEqual(Load.over, loadLevel(0.11, 0.1));
}
