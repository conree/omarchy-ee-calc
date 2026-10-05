//! ee-calc: the calculation engine behind the EE Calc Omarchy plugin.
//! Every command prints one JSON object on stdout. Failures print
//! {"ok":false,"error":"..."} and exit 2, so the UI has one path to read.
//!
//!   ee-calc eseries <value> [--series E24]
//!   ee-calc divider --vin <V> --r1 <R> --r2 <R> [--rl <R>]
//!   ee-calc divider-solve --vin <V> --vout <V> [--series E24]
//!                         [--rmin 10k] [--rmax 1M] [--rl <R>] [--count 5]
//!   ee-calc parts <value> [--package 0603] [--tolerance 1]
//!   (eseries, divider and divider-solve also take --package and
//!    --tolerance, and then add part numbers and power checks)
//!   ee-calc parse <text>
//!   ee-calc version

const std = @import("std");
const Io = std.Io;
const units = @import("units.zig");
const eseries = @import("eseries.zig");
const divider = @import("divider.zig");
const parts = @import("parts.zig");

const version = "0.2.5";
// Greek capital omega rather than U+2126 OHM SIGN: far more fonts carry it.
const ohm = "\u{03A9}";

const usage_text =
    \\ee-calc eseries <value> [--series E24]
    \\ee-calc divider --vin <V> --r1 <R> --r2 <R> [--rl <R>]
    \\ee-calc divider-solve --vin <V> --vout <V> [--series E24] [--rmin 10k] [--rmax 1M] [--rl <R>] [--count 5]
    \\ee-calc parts <value> [--package 0603|0402|0805|1206|tht-quarter|tht-half] [--tolerance 1|5]
    \\  eseries, divider and divider-solve also accept --package and --tolerance
    \\ee-calc parse <text>
    \\ee-calc version
;

const Failure = error{ Usage, OutOfMemory, WriteFailed };

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var buffer: [16 * 1024]u8 = undefined;
    var file_writer: Io.File.Writer = .init(.stdout(), init.io, &buffer);
    const out = &file_writer.interface;

    var message: []const u8 = "";
    run(arena, args, out, &message) catch |err| switch (err) {
        error.Usage => {
            try out.writeAll("{\"ok\":false,\"error\":");
            try writeString(out, message);
            try out.writeAll("}\n");
            try out.flush();
            std.process.exit(2);
        },
        else => |e| return e,
    };
    try out.flush();
}

fn run(arena: std.mem.Allocator, args: []const [:0]const u8, out: *Io.Writer, message: *[]const u8) Failure!void {
    if (args.len < 2) return usage(message, "missing command");
    const cmd = args[1];
    const rest = args[2..];

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help")) {
        try out.writeAll("{\"ok\":true,\"usage\":");
        try writeString(out, usage_text);
        try out.writeAll("}\n");
    } else if (std.mem.eql(u8, cmd, "version")) {
        try out.print("{{\"ok\":true,\"version\":\"{s}\"}}\n", .{version});
    } else if (std.mem.eql(u8, cmd, "parse")) {
        if (rest.len != 1) return usage(message, "parse takes one value");
        const v = units.parse(rest[0]) catch return usage(message, "not a number");
        try out.writeAll("{\"ok\":true,\"value\":");
        try writeNumber(out, v);
        try out.writeAll("}\n");
    } else if (std.mem.eql(u8, cmd, "parts")) {
        try cmdParts(rest, out, message);
    } else if (std.mem.eql(u8, cmd, "eseries")) {
        try cmdEseries(rest, out, message);
    } else if (std.mem.eql(u8, cmd, "divider")) {
        try cmdDivider(rest, out, message);
    } else if (std.mem.eql(u8, cmd, "divider-solve")) {
        try cmdSolve(arena, rest, out, message);
    } else {
        return usage(message, "unknown command");
    }
}

fn usage(message: *[]const u8, text: []const u8) Failure {
    message.* = text;
    return error.Usage;
}

// ---- Options -------------------------------------------------------------

const Options = struct {
    positional: ?[]const u8 = null,
    keys: [8][]const u8 = undefined,
    vals: [8][]const u8 = undefined,
    len: usize = 0,

    fn get(self: *const Options, key: []const u8) ?[]const u8 {
        for (self.keys[0..self.len], self.vals[0..self.len]) |k, v| {
            if (std.mem.eql(u8, k, key)) return v;
        }
        return null;
    }
};

fn parseOptions(rest: []const [:0]const u8, allowed: []const []const u8, message: *[]const u8) Failure!Options {
    var o: Options = .{};
    var i: usize = 0;
    while (i < rest.len) : (i += 1) {
        const a = rest[i];
        if (std.mem.startsWith(u8, a, "--")) {
            const key = a[2..];
            var known = false;
            for (allowed) |k| known = known or std.mem.eql(u8, k, key);
            if (!known) return usage(message, "unknown option");
            if (i + 1 >= rest.len) return usage(message, "option needs a value");
            if (o.get(key) != null) return usage(message, "option given twice");
            if (o.len == o.keys.len) return usage(message, "too many options");
            o.keys[o.len] = key;
            o.vals[o.len] = rest[i + 1];
            o.len += 1;
            i += 1;
        } else {
            if (o.positional != null) return usage(message, "unexpected argument");
            o.positional = a;
        }
    }
    return o;
}

fn number(o: *const Options, key: []const u8, message: *[]const u8, what: []const u8) Failure!?f64 {
    const text = o.get(key) orelse return null;
    if (std.mem.trim(u8, text, " ").len == 0) return null;
    return units.parse(text) catch return usage(message, what);
}

fn requirePositive(v: ?f64, message: *[]const u8, missing: []const u8, bad: []const u8) Failure!f64 {
    const x = v orelse return usage(message, missing);
    if (!(x > 0)) return usage(message, bad);
    return x;
}

fn seriesOption(o: *const Options, message: *[]const u8) Failure!eseries.Series {
    const text = o.get("series") orelse return .e24;
    return eseries.Series.parse(text) orelse usage(message, "series must be E3, E6, E12, E24, E48 or E96");
}

/// Package and tolerance for part numbers and power checks. Absent when
/// neither option is given, so older callers get the output they expect.
const Selection = struct { package: parts.Package, tolerance: parts.Tolerance };

fn selectionOption(o: *const Options, message: *[]const u8) Failure!?Selection {
    const ptext = o.get("package");
    const ttext = o.get("tolerance");
    if (ptext == null and ttext == null) return null;
    return .{
        .package = if (ptext) |t| parts.Package.parse(t) orelse
            return usage(message, "package must be 0402, 0603, 0805, 1206, tht-quarter or tht-half")
        else
            .p0603,
        .tolerance = if (ttext) |t| parts.Tolerance.parse(t) orelse
            return usage(message, "tolerance must be 1 or 5")
        else
            .one,
    };
}

// ---- Commands ------------------------------------------------------------

fn cmdParts(rest: []const [:0]const u8, out: *Io.Writer, message: *[]const u8) Failure!void {
    const o = try parseOptions(rest, &.{ "package", "tolerance" }, message);
    const text = o.positional orelse return usage(message, "enter a value");
    const value = units.parse(text) catch return usage(message, "not a number");
    if (!(value > 0)) return usage(message, "value must be above zero");
    const sel = (try selectionOption(&o, message)) orelse Selection{ .package = .p0603, .tolerance = .one };
    try out.writeAll("{\"ok\":true");
    try writeSelection(out, sel);
    try out.writeAll(",\"parts\":");
    try writeParts(out, value, sel);
    try out.writeAll("}\n");
}

fn cmdEseries(rest: []const [:0]const u8, out: *Io.Writer, message: *[]const u8) Failure!void {
    const o = try parseOptions(rest, &.{ "series", "package", "tolerance" }, message);
    const sel = try selectionOption(&o, message);
    const text = o.positional orelse return usage(message, "enter a value");
    const target = units.parse(text) catch return usage(message, "not a number");
    if (!(target > 0)) return usage(message, "value must be above zero");
    if (target < 1e-3 or target > 1e11) return usage(message, "value must be between 1 m and 100 G");
    const chosen = try seriesOption(&o, message);

    try out.writeAll("{\"ok\":true,\"target\":");
    try writeQuantity(out, target, 4, ohm);
    try out.print(",\"series\":\"{s}\",\"table\":[", .{chosen.name()});
    inline for (std.meta.fields(eseries.Series), 0..) |f, i| {
        const s: eseries.Series = @enumFromInt(f.value);
        const n = eseries.nearest(s, target);
        if (i > 0) try out.writeAll(",");
        try out.print("{{\"series\":\"{s}\",\"exact\":{},\"below\":", .{ s.name(), n.exact });
        try writeQuantity(out, n.below, 3, ohm);
        try out.writeAll(",\"belowErrorPct\":");
        try writeNumber(out, eseries.errorPercent(n.below, target));
        try out.writeAll(",\"above\":");
        try writeQuantity(out, n.above, 3, ohm);
        try out.writeAll(",\"aboveErrorPct\":");
        try writeNumber(out, eseries.errorPercent(n.above, target));
        try out.writeAll(",\"nearest\":");
        try writeQuantity(out, n.nearest, 3, ohm);
        try out.writeAll(",\"nearestErrorPct\":");
        try writeNumber(out, eseries.errorPercent(n.nearest, target));
        try out.writeAll("}");
    }
    try out.writeAll("],\"pairs\":{");
    inline for (.{ eseries.Topology.series, eseries.Topology.parallel }, 0..) |topo, i| {
        if (i > 0) try out.writeAll(",");
        try out.print("\"{s}\":", .{@tagName(topo)});
        if (eseries.bestPair(chosen, topo, target)) |c| {
            try out.writeAll("{\"a\":");
            try writeQuantity(out, c.a, 3, ohm);
            try out.writeAll(",\"b\":");
            try writeQuantity(out, c.b, 3, ohm);
            try out.writeAll(",\"result\":");
            try writeQuantity(out, c.result, 4, ohm);
            try out.writeAll(",\"errorPct\":");
            try writeNumber(out, c.error_pct);
            if (sel) |s| {
                try out.writeAll(",\"aParts\":");
                try writeParts(out, c.a, s);
                try out.writeAll(",\"bParts\":");
                try writeParts(out, c.b, s);
            }
            try out.writeAll("}");
        } else try out.writeAll("null");
    }
    try out.writeAll("}");
    if (sel) |s| {
        // Part numbers for the nearest value in the chosen series.
        try writeSelection(out, s);
        try out.writeAll(",\"parts\":");
        try writeParts(out, eseries.nearest(chosen, target).nearest, s);
    }
    try out.writeAll("}\n");
}

fn cmdDivider(rest: []const [:0]const u8, out: *Io.Writer, message: *[]const u8) Failure!void {
    const o = try parseOptions(rest, &.{ "vin", "r1", "r2", "rl", "package", "tolerance" }, message);
    const sel = try selectionOption(&o, message);
    if (o.positional != null) return usage(message, "unexpected argument");
    const vin = try requirePositive(try number(&o, "vin", message, "Vin is not a number"), message, "enter Vin", "Vin must be above zero");
    const r1 = try requirePositive(try number(&o, "r1", message, "R1 is not a number"), message, "enter R1", "R1 must be above zero");
    const r2 = try requirePositive(try number(&o, "r2", message, "R2 is not a number"), message, "enter R2", "R2 must be above zero");
    const rl = try number(&o, "rl", message, "load is not a number");
    if (rl) |l| if (!(l > 0)) return usage(message, "load must be above zero");

    const a = divider.analyze(vin, r1, r2, rl);
    try out.writeAll("{\"ok\":true,\"vout\":");
    try writeQuantity(out, a.vout, 4, "V");
    try out.writeAll(",\"voutUnloaded\":");
    try writeQuantity(out, a.vout_unloaded, 4, "V");
    try out.writeAll(",\"ratio\":");
    try writeNumber(out, a.ratio);
    try out.writeAll(",\"current\":");
    try writeQuantity(out, a.current, 3, "A");
    try out.writeAll(",\"pR1\":");
    try writeQuantity(out, a.p_r1, 3, "W");
    try out.writeAll(",\"pR2\":");
    try writeQuantity(out, a.p_r2, 3, "W");
    try out.writeAll(",\"pLoad\":");
    try writeQuantity(out, a.p_load, 3, "W");
    try out.writeAll(",\"loadCurrent\":");
    try writeQuantity(out, a.load_current, 3, "A");
    try out.writeAll(",\"sourceResistance\":");
    try writeQuantity(out, a.source_resistance, 3, ohm);
    try out.print(",\"loaded\":{}", .{rl != null});
    if (sel) |s| {
        try writeSelection(out, s);
        try out.writeAll(",\"loadR1\":");
        try writeLoad(out, a.p_r1, s.package);
        try out.writeAll(",\"loadR2\":");
        try writeLoad(out, a.p_r2, s.package);
        try out.writeAll(",\"partsR1\":");
        try writeParts(out, r1, s);
        try out.writeAll(",\"partsR2\":");
        try writeParts(out, r2, s);
    }
    try out.writeAll("}\n");
}

fn cmdSolve(arena: std.mem.Allocator, rest: []const [:0]const u8, out: *Io.Writer, message: *[]const u8) Failure!void {
    const o = try parseOptions(rest, &.{ "vin", "vout", "series", "rmin", "rmax", "rl", "count", "package", "tolerance" }, message);
    const sel = try selectionOption(&o, message);
    if (o.positional != null) return usage(message, "unexpected argument");
    const vin = try requirePositive(try number(&o, "vin", message, "Vin is not a number"), message, "enter Vin", "Vin must be above zero");
    const vout = try requirePositive(try number(&o, "vout", message, "Vout is not a number"), message, "enter the target Vout", "Vout must be above zero");
    if (!(vout < vin)) return usage(message, "Vout must be below Vin");

    var opts: divider.SolveOptions = .{ .series = try seriesOption(&o, message) };
    if (try number(&o, "rmin", message, "minimum total is not a number")) |v| opts.r_min = v;
    if (try number(&o, "rmax", message, "maximum total is not a number")) |v| opts.r_max = v;
    opts.load = try number(&o, "rl", message, "load is not a number");
    if (opts.load) |l| if (!(l > 0)) return usage(message, "load must be above zero");
    if (o.get("count")) |c| {
        opts.count = std.fmt.parseInt(usize, c, 10) catch return usage(message, "count must be a whole number");
        if (opts.count == 0 or opts.count > 20) return usage(message, "count must be 1 to 20");
    }

    const got = divider.solve(arena, vin, vout, opts) catch |err| switch (err) {
        error.OutOfRange => return usage(message, "Vout must be between 0 and Vin"),
        error.BadRange => return usage(message, "total resistance range is invalid"),
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (got.len == 0) return usage(message, "no pair from this series fits the total resistance range");

    try out.print("{{\"ok\":true,\"series\":\"{s}\",\"target\":", .{opts.series.name()});
    try writeQuantity(out, vout, 4, "V");
    try out.writeAll(",\"rMin\":");
    try writeQuantity(out, opts.r_min, 3, ohm);
    try out.writeAll(",\"rMax\":");
    try writeQuantity(out, opts.r_max, 3, ohm);
    try out.writeAll(",\"candidates\":[");
    for (got, 0..) |c, i| {
        if (i > 0) try out.writeAll(",");
        try out.writeAll("{\"r1\":");
        try writeQuantity(out, c.r1, 3, ohm);
        try out.writeAll(",\"r2\":");
        try writeQuantity(out, c.r2, 3, ohm);
        try out.writeAll(",\"vout\":");
        try writeQuantity(out, c.vout, 4, "V");
        try out.writeAll(",\"errorPct\":");
        try writeNumber(out, c.error_pct);
        try out.writeAll(",\"total\":");
        try writeQuantity(out, c.total, 3, ohm);
        try out.writeAll(",\"current\":");
        try writeQuantity(out, c.current, 3, "A");
        if (sel) |s| {
            try out.writeAll(",\"loadR1\":");
            try writeLoad(out, c.current * c.current * c.r1, s.package);
            try out.writeAll(",\"loadR2\":");
            try writeLoad(out, c.vout * c.vout / c.r2, s.package);
        }
        try out.writeAll("}");
    }
    try out.writeAll("]");
    if (sel) |s| {
        // Part numbers for the best pair only; the list is a shortlist and
        // the panel shows numbers for the one it recommends.
        try writeSelection(out, s);
        try out.writeAll(",\"partsR1\":");
        try writeParts(out, got[0].r1, s);
        try out.writeAll(",\"partsR2\":");
        try writeParts(out, got[0].r2, s);
    }
    try out.writeAll("}\n");
}

// ---- JSON ----------------------------------------------------------------

fn writeSelection(out: *Io.Writer, s: Selection) Io.Writer.Error!void {
    try out.print(",\"package\":\"{s}\",\"tolerance\":\"{s}\",\"rating\":", .{ s.package.name(), s.tolerance.name() });
    try writeQuantity(out, s.package.rating(), 3, "W");
}

/// {"value": .., "note": "..", "list": [{"maker","family","mpn","power","nrfnd"}]}
fn writeParts(out: *Io.Writer, value: f64, s: Selection) Io.Writer.Error!void {
    var storage: [parts.max_parts][40]u8 = undefined;
    var list: [parts.max_parts]parts.Part = undefined;
    const r = parts.lookup(&storage, &list, value, s.package, s.tolerance);
    try out.writeAll("{\"value\":");
    try writeQuantity(out, value, 3, ohm);
    try out.writeAll(",\"note\":");
    try writeString(out, r.note);
    try out.writeAll(",\"list\":[");
    for (r.parts, 0..) |p, i| {
        if (i > 0) try out.writeAll(",");
        try out.writeAll("{\"maker\":");
        try writeString(out, p.maker);
        try out.writeAll(",\"family\":");
        try writeString(out, p.family);
        try out.writeAll(",\"mpn\":");
        try writeString(out, p.mpn);
        try out.writeAll(",\"power\":");
        try writeQuantity(out, p.power, 3, "W");
        try out.print(",\"nrfnd\":{}}}", .{p.nrfnd});
    }
    try out.writeAll("]}");
}

/// {"power": .., "pct": 37.5, "level": "ok" | "high" | "over"}
fn writeLoad(out: *Io.Writer, power: f64, package: parts.Package) Io.Writer.Error!void {
    const rating = package.rating();
    try out.writeAll("{\"power\":");
    try writeQuantity(out, power, 3, "W");
    try out.writeAll(",\"pct\":");
    try writeNumber(out, power / rating * 100);
    try out.print(",\"level\":\"{s}\"}}", .{@tagName(parts.loadLevel(power, rating))});
}

/// {"value": 4700, "text": "4.7 kΩ"}
fn writeQuantity(out: *Io.Writer, value: f64, sig: u8, unit: []const u8) Io.Writer.Error!void {
    var buf: [64]u8 = undefined;
    try out.writeAll("{\"value\":");
    try writeNumber(out, value);
    try out.writeAll(",\"text\":");
    try writeString(out, units.format(&buf, value, sig, unit));
    try out.writeAll("}");
}

fn writeNumber(out: *Io.Writer, v: f64) Io.Writer.Error!void {
    if (!std.math.isFinite(v)) return out.writeAll("null");
    const a = @abs(v);
    if (a != 0 and (a < 1e-6 or a >= 1e15)) return out.print("{e}", .{v});
    try out.print("{d}", .{v});
}

fn writeString(out: *Io.Writer, s: []const u8) Io.Writer.Error!void {
    try out.writeByte('"');
    for (s) |c| switch (c) {
        '"' => try out.writeAll("\\\""),
        '\\' => try out.writeAll("\\\\"),
        '\n' => try out.writeAll("\\n"),
        0...0x09, 0x0b...0x1f => try out.print("\\u{x:0>4}", .{c}),
        else => try out.writeByte(c),
    };
    try out.writeByte('"');
}

test {
    _ = units;
    _ = eseries;
    _ = divider;
    _ = parts;
}
