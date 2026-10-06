//! Small circuit calculators: LED series resistor, Ohm's law and power,
//! RC time constant and cutoff, LC resonance.

const std = @import("std");
const eseries = @import("eseries.zig");

// ---- LED series resistor ------------------------------------------------------

pub const LedError = error{NoHeadroom};

pub const Led = struct {
    /// Resistance that gives exactly the target current.
    exact: f64,
    /// Voltage across the resistor.
    drop: f64,
};

/// `count` LEDs in series, each dropping `vf`, from `vs` at `current`.
pub fn led(vs: f64, vf: f64, current: f64, count: u32) LedError!Led {
    const drop = vs - vf * @as(f64, @floatFromInt(count));
    if (!(drop > 0)) return error.NoHeadroom;
    return .{ .exact = drop / current, .drop = drop };
}

/// What a chosen resistor actually does in the LED circuit.
pub const LedChoice = struct {
    r: f64,
    current: f64,
    p_resistor: f64,
    p_led: f64,
};

pub fn ledWith(drop: f64, vf: f64, r: f64) LedChoice {
    const i = drop / r;
    return .{ .r = r, .current = i, .p_resistor = drop * i, .p_led = vf * i };
}

// ---- Ohm's law -------------------------------------------------------------------

pub const Ohm = struct { v: f64, i: f64, r: f64, p: f64 };

pub const OhmError = error{NeedTwo};

/// Any two of V, I, R, P give the other two.
pub fn ohm(v: ?f64, i: ?f64, r: ?f64, p: ?f64) OhmError!Ohm {
    var given: u8 = 0;
    inline for (.{ v, i, r, p }) |x| given += @intFromBool(x != null);
    if (given != 2) return error.NeedTwo;
    if (v != null and i != null) return .{ .v = v.?, .i = i.?, .r = v.? / i.?, .p = v.? * i.? };
    if (v != null and r != null) return .{ .v = v.?, .i = v.? / r.?, .r = r.?, .p = v.? * v.? / r.? };
    if (v != null and p != null) return .{ .v = v.?, .i = p.? / v.?, .r = v.? * v.? / p.?, .p = p.? };
    if (i != null and r != null) return .{ .v = i.? * r.?, .i = i.?, .r = r.?, .p = i.? * i.? * r.? };
    if (i != null and p != null) return .{ .v = p.? / i.?, .i = i.?, .r = p.? / (i.? * i.?), .p = p.? };
    return .{ .v = @sqrt(p.? * r.?), .i = @sqrt(p.? / r.?), .r = r.?, .p = p.? };
}

// ---- RC ------------------------------------------------------------------------------

pub const Rc = struct {
    r: f64,
    c: f64,
    tau: f64,
    /// -3 dB frequency of a first-order RC filter.
    fc: f64,
    /// The part that was worked out, if any.
    solved: Solved,
};

pub const Solved = enum { none, r, c, l, f };

pub const RcError = error{ NeedTwo, Both };

/// Any two of R, C and (cutoff frequency or time constant). `f` and `tau`
/// describe the same thing, so only one of them may be given.
pub fn rc(r: ?f64, c: ?f64, f: ?f64, tau: ?f64) RcError!Rc {
    if (f != null and tau != null) return error.Both;
    // tau = RC = 1 / (2 pi fc)
    const t: ?f64 = if (f) |fc| 1 / (2 * std.math.pi * fc) else tau;
    var given: u8 = 0;
    inline for (.{ r, c, t }) |x| given += @intFromBool(x != null);
    if (given != 2) return error.NeedTwo;
    const rr, const cc, const solved: Solved = if (t == null)
        .{ r.?, c.?, .f }
    else if (r == null)
        .{ t.? / c.?, c.?, .r }
    else
        .{ r.?, t.? / r.?, .c };
    const tt = rr * cc;
    return .{ .r = rr, .c = cc, .tau = tt, .fc = 1 / (2 * std.math.pi * tt), .solved = solved };
}

// ---- LC --------------------------------------------------------------------------------

pub const Lc = struct {
    l: f64,
    c: f64,
    f0: f64,
    /// sqrt(L/C): the reactance of either part at resonance.
    z0: f64,
    solved: Solved,
};

pub const LcError = error{NeedTwo};

/// Any two of L, C and the resonant frequency.
pub fn lc(l: ?f64, c: ?f64, f: ?f64) LcError!Lc {
    var given: u8 = 0;
    inline for (.{ l, c, f }) |x| given += @intFromBool(x != null);
    if (given != 2) return error.NeedTwo;
    // f0 = 1 / (2 pi sqrt(LC))  =>  LC = 1 / (2 pi f0)^2
    const ll, const cc, const solved: Solved = if (f == null)
        .{ l.?, c.?, .f }
    else blk: {
        const w = 2 * std.math.pi * f.?;
        break :blk if (l == null) .{ 1 / (w * w * c.?), c.?, Solved.l } else .{ l.?, 1 / (w * w * l.?), Solved.c };
    };
    return .{ .l = ll, .c = cc, .f0 = 1 / (2 * std.math.pi * @sqrt(ll * cc)), .z0 = @sqrt(ll / cc), .solved = solved };
}

/// Capacitors and inductors are stocked in E12 and E6 values; the nearest
/// E12 value is what the calculators suggest for a solved part.
pub fn nearestE12(v: f64) f64 {
    return eseries.nearest(.e12, v).nearest;
}

const testing = std.testing;

test "led resistor" {
    // 12 V, three 2 V LEDs at 20 mA: 6 V across 300 Ω.
    const a = try led(12, 2, 0.02, 3);
    try testing.expectApproxEqRel(@as(f64, 300), a.exact, 1e-12);
    const ch = ledWith(a.drop, 2, 330);
    try testing.expectApproxEqRel(@as(f64, 6.0 / 330.0), ch.current, 1e-12);
    try testing.expectApproxEqRel(@as(f64, 6.0 * 6.0 / 330.0), ch.p_resistor, 1e-12);
    try testing.expectError(error.NoHeadroom, led(5, 2.5, 0.02, 2));
}

test "ohm's law, every pair" {
    const want = Ohm{ .v = 12, .i = 0.5, .r = 24, .p = 6 };
    const cases = [_]Ohm{
        try ohm(12, 0.5, null, null), try ohm(12, null, 24, null), try ohm(12, null, null, 6),
        try ohm(null, 0.5, 24, null), try ohm(null, 0.5, null, 6), try ohm(null, null, 24, 6),
    };
    for (cases) |c| {
        try testing.expectApproxEqRel(want.v, c.v, 1e-12);
        try testing.expectApproxEqRel(want.i, c.i, 1e-12);
        try testing.expectApproxEqRel(want.r, c.r, 1e-12);
        try testing.expectApproxEqRel(want.p, c.p, 1e-12);
    }
    try testing.expectError(error.NeedTwo, ohm(1, null, null, null));
    try testing.expectError(error.NeedTwo, ohm(1, 2, 3, null));
}

test "rc" {
    const a = try rc(10e3, 100e-9, null, null);
    try testing.expectApproxEqRel(@as(f64, 1e-3), a.tau, 1e-12);
    try testing.expectApproxEqRel(@as(f64, 159.15494309189535), a.fc, 1e-12);
    const b = try rc(null, 100e-9, 159.15494309189535, null);
    try testing.expectApproxEqRel(@as(f64, 10e3), b.r, 1e-12);
    try testing.expectEqual(Solved.r, b.solved);
    const c = try rc(10e3, null, null, 1e-3);
    try testing.expectApproxEqRel(@as(f64, 100e-9), c.c, 1e-12);
    try testing.expectError(error.Both, rc(1, null, 1, 1));
    try testing.expectError(error.NeedTwo, rc(1, null, null, null));
}

test "lc" {
    const a = try lc(10e-6, 100e-9, null);
    try testing.expectApproxEqRel(@as(f64, 159154.94309189535), a.f0, 1e-12);
    try testing.expectApproxEqRel(@as(f64, 10), a.z0, 1e-12);
    const b = try lc(null, 100e-9, 159154.94309189535);
    try testing.expectApproxEqRel(@as(f64, 10e-6), b.l, 1e-12);
    const c = try lc(10e-6, null, 159154.94309189535);
    try testing.expectApproxEqRel(@as(f64, 100e-9), c.c, 1e-12);
    try testing.expectError(error.NeedTwo, lc(1, 1, 1));
}
