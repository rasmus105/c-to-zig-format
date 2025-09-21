//! This file will convert a C-style format string (like "Hello %s, you have %d new messages\n")
//! into a Zig format string (like "Hello {s}, you have {d} new messages\n").
//!
//! The official C syntax for a format specifier is: `%[flags][width][.precision][length]specifier`
//! The official Zig syntax for a format specifier is: `{[argument][specifier]:[fill][alignment][width][.precision]}`
//!
//! This implementation is not perfect, and there are several cases where the conversion will not be exact.
//! E.g.:
//!  - "%#x" in C means to prefix the output with "0x" if the value is non-zero, but Zig does not have a direct equivalent.
//!     This will instead be converted to "{x:0>}", which will pad the output with leading zeros, but will not add the "0x" prefix.

const std = @import("std");

const LengthModifier = enum {
    hh,
    h,
    l,
    ll,
    j,
    z,
    t,
    L,
};

const ZigSpecifier = enum {
    x,
    X,
    s,
    t,
    b64,
    e,
    d,
    b,
    o,
    c,
    u,
    D,
    B,
    Bi,
    @"?",
    @"!",
    @"*",
    any,
    f,

    pub fn from_c_specifier(c: u8) !ZigSpecifier {
        return switch (c) {
            'd', 'i' => .d,
            'u' => .u,
            'f', 'F' => .d,
            'e', 'E' => .e,
            'g', 'G' => .d, // Zig does not have a 'g' specifier
            'x' => .x,
            'X' => .X,
            'o' => .o,
            's' => .s,
            'c' => .c,
            'p' => .t, // pointer
            'a', 'A' => .f, // Zig does not have an 'a' specifier
            else => return error.FormatError,
        };
    }

    pub fn toString(self: ZigSpecifier) []const u8 {
        return switch (self) {
            .x => "x",
            .X => "X",
            .s => "s",
            .t => "t",
            .b64 => "b64",
            .e => "e",
            .d => "d",
            .b => "b",
            .o => "o",
            .c => "c",
            .u => "u",
            .D => "D",
            .B => "B",
            .Bi => "Bi",
            .@"?" => "?",
            .@"!" => "!",
            .@"*" => "*",
            .any => "",
            .f => "f",
        };
    }
};

const State = enum {
    start, // not processing format specifier
    percent_found, // '%' found, next should be flag, width, precision, length, or specifier
    flag_found, // flag found, any of flag, width, precision, length, or specifier can follow (multiple flags allowed) - (note: this state is technically not needed, as there is no difference between being in percent_found and flag_found)
    width_found, // width digit(s) found, next should be width digit(s), precision, length, or specifier
    dot_found, // '.' found, next should be precision digit(s)
    precision_found, // precision digit(s) found, next should be precision digit(s), length, or specifier
    length_found, // length modifier found, next should be length modifier (if 'l' or 'h') or specifier
    specifier_awaited, // length found, next should be specifier
    specifier_found, // specifier found, conversion to zig format specifier should now happen
};

fn handle_conversion(
    flags: ?[5]u8,
    width: ?u32,
    precision: ?u32,
    length: ?LengthModifier,
    c_specifier: ZigSpecifier,
    comptime T: type,
    format_buffer: *T,
) !void {
    _ = length; // currently unused
    try format_buffer.addChar('{');
    try format_buffer.addString(c_specifier.toString());

    if (flags == null and width == null and precision == null) {
        // no flags, width, or precision
        try format_buffer.addChar('}');
        return;
    }

    try format_buffer.addChar(':');

    if (flags != null) {
        // flags is guranteed to only contain valid flag characters
        // and no duplicates
        if (std.mem.count(u8, &flags.?, &[_]u8{'0'}) > 0) {
            try format_buffer.addChar('0');
        } else {
            try format_buffer.addChar(' ');
        }

        if (std.mem.count(u8, &flags.?, &[_]u8{'-'}) > 0) {
            try format_buffer.addChar('<');
        } else {
            try format_buffer.addChar('>');
        }
    }

    if (width != null) {
        try format_buffer.addInt(u32, width.?);
    }

    if (precision != null) {
        try format_buffer.addChar('.');
        try format_buffer.addInt(u32, precision.?);
    }

    try format_buffer.addChar('}');
}

pub fn convert_from_c_to_zig(comptime T: type, zig_format: *T, c_format: []const u8) !void {
    var flags: ?[5]u8 = null; // possible flags: '-', '+', ' ', '#', '0'
    var width: ?u32 = null; // e.g. 2, 10, 256, ...
    var precision: ?u32 = null; // e.g. .2, .10, .256, ...
    var length: ?LengthModifier = null; // e.g. h, hh, l, ll, j, z, t, L

    var state: State = .start;

    for (c_format, 0..) |c, i| {
        // only start processing when we find a '%'
        if (state == .start) {
            if (c == '%') {
                state = .percent_found;
            } else {
                try zig_format.addChar(c);
            }

            continue;
        }

        switch (c) {
            '%' => {
                if (state != .percent_found) {
                    // we found a '%' while already processing a format specifier
                    // this means it is an invalid format string
                    return error.FormatError;
                } else {
                    // 2 '%' characters in a row means a literal '%'
                    try zig_format.addChar('%');
                    state = .start;
                }
            },
            '-', '+', ' ', '#', '0' => {
                if (state != .percent_found and state != .flag_found) {
                    // flags should come after '%' or other flags
                    return error.FormatError;
                }

                if (flags == null) {
                    flags = [_]u8{ c, 0, 0, 0, 0 };
                } else {
                    // 1 or more flags already found, append this one (returning error if there are too many)
                    for (flags.?, 0..) |f, idx| {
                        if (f == 0) {
                            flags.?[idx] = c;
                            break;
                        } else if (f == c) {
                            return error.FormatError; // duplicate flag
                        } else if (idx == flags.?.len - 1) {
                            return error.FormatError; // too many flags
                        }
                    }
                }

                state = .flag_found;
            },
            '1'...'9' => {
                if (state != .percent_found and state != .flag_found and state != .width_found and state != .precision_found and state != .dot_found) {
                    // width should come after '%' or flags or other width digits
                    return error.FormatError;
                }

                const digit = c - '0';

                if (state == .dot_found or state == .precision_found) {
                    // we are processing precision
                    if (precision == null) {
                        precision = digit;
                    } else {
                        // multi-digit precision
                        precision = precision.? * 10 + digit;
                    }
                    state = .precision_found;
                } else {
                    if (width == null) {
                        width = digit;
                    } else {
                        // multi-digit width
                        width = width.? * 10 + digit;
                    }
                    // we are processing width
                    state = .width_found;
                }
            },
            '.' => {
                if (state != .percent_found and state != .flag_found and state != .width_found) {
                    // '.' should come after '%' or flags or width
                    return error.FormatError;
                }

                state = .dot_found;
            },
            'l', 'h', 'j', 'z', 't', 'L' => {
                if (state != .percent_found and state != .flag_found and state != .width_found and state != .precision_found and state != .length_found) {
                    // length should come after '%' or flags or width or precision
                    return error.FormatError;
                }

                if (length == null) {
                    // first length modifier character
                    length = switch (c) {
                        'l' => .l,
                        'h' => .h,
                        'j' => .j,
                        'z' => .z,
                        't' => .t,
                        'L' => .L,
                        else => unreachable,
                    };
                    state = .length_found; // next will be either second 'l' or 'h' or specifier
                } else {
                    length = switch (c) {
                        'l' => .ll,
                        'h' => .hh,
                        else => return error.FormatError, // invalid length modifier
                    };
                    state = .specifier_awaited; // next should be specifier
                }
            },
            'd', 'i', 'u', 'f', 'F', 'e', 'E', 'g', 'G', 'x', 'X', 'o', 's', 'c', 'p', 'a', 'A' => {
                if (state == .dot_found) {
                    // we found a '.' but no precision digits
                    return error.FormatError;
                }

                // convert the c format specifier to zig format specifier
                try handle_conversion(
                    flags,
                    width,
                    precision,
                    length,
                    try ZigSpecifier.from_c_specifier(c),
                    T,
                    zig_format,
                );

                // reset all state
                flags = null;
                width = null;
                precision = null;
                length = null;
                state = .start;
            },
            else => {
                // invalid character in format specifier
                return error.FormatError;
            },
        }

        if (state != .start and i >= c_format.len - 1) {
            // we reached the end of the string while still processing a format specifier
            return error.FormatError;
        }
    }
}

// ===========================================================================
// Runtime Function
// ===========================================================================

const FormatBuffer = struct {
    data: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator, size: usize) !FormatBuffer {
        return FormatBuffer{
            .data = try std.ArrayList(u8).initCapacity(allocator, size),
            .allocator = allocator,
        };
    }

    fn deinit(self: *FormatBuffer) void {
        self.data.deinit(self.allocator);
    }

    fn addChar(self: *FormatBuffer, c: u8) !void {
        try self.data.append(self.allocator, c);
    }

    fn addString(self: *FormatBuffer, str: []const u8) !void {
        try self.data.appendSlice(self.allocator, str);
    }

    fn addInt(self: *FormatBuffer, comptime T: type, value: T) !void {
        try self.data.print(self.allocator, "{d}", .{value});
    }

    fn toOwnedSlice(self: *FormatBuffer) ![]u8 {
        return self.data.toOwnedSlice(self.allocator);
    }

    fn items(self: *const FormatBuffer) []const u8 {
        return self.data.items;
    }
};

pub fn cToZigFormat(allocator: std.mem.Allocator, c_format: []const u8) ![]u8 {
    var zig_format: FormatBuffer = try FormatBuffer.init(allocator, c_format.len * 1);
    errdefer zig_format.deinit();

    try convert_from_c_to_zig(FormatBuffer, &zig_format, c_format);

    return zig_format.toOwnedSlice();
}

// ===========================================================================
// Compile-time Function
// ===========================================================================

// functions can return error so that the declarations match `FormatBuffer`
const ComptimeFormatBuffer = struct {
    data: []u8,
    len: usize = 0,

    pub fn init(buf: []u8) !ComptimeFormatBuffer {
        return ComptimeFormatBuffer{
            .data = buf,
            .len = 0,
        };
    }

    pub fn addChar(self: *ComptimeFormatBuffer, c: u8) !void {
        self.data[self.len] = c;
        self.len += 1;
    }

    pub fn addString(self: *ComptimeFormatBuffer, str: []const u8) !void {
        @memcpy(self.data[self.len..(self.len + str.len)], str);
        self.len += str.len;
    }

    pub fn addInt(self: *ComptimeFormatBuffer, comptime T: type, value: T) !void {
        const written = std.fmt.bufPrint(self.data[self.len..], "{d}", .{value}) catch unreachable;
        self.len += written.len;
    }

    pub fn toOwnedSlice(self: *ComptimeFormatBuffer) ![]u8 {
        return self.data[0..self.len];
    }

    pub fn items(self: *const ComptimeFormatBuffer) ![]const u8 {
        return self.data[0..self.len];
    }

    pub fn getLen(self: *ComptimeFormatBuffer) usize {
        return self.len;
    }
};

fn getZigFormatLenFromCFormat(comptime c_format: []const u8) usize {
    // allocate generous size (FIXME can overflow, though VERY unlikely to happen!)
    // when the input buffer is small, it seems more likely the input string consists
    // solely of conversion specifiers.
    const max_len = if (c_format.len < 64) 255 else c_format.len * 3;
    var buf: [max_len]u8 = undefined;
    var zig_format: ComptimeFormatBuffer = comptime try ComptimeFormatBuffer.init(&buf);

    comptime convert_from_c_to_zig(ComptimeFormatBuffer, &zig_format, c_format) catch |err| {
        @compileError("Invalid format, error: " ++ err);
    };

    return zig_format.getLen();
}

// this approach seems sub-optimal, since the string is parsed multiple times,
// though I have been unable to find a better solution, since comptime var pointers
// can't be referenced at runtime.
// (also it will only affect the compilation time, so it is not very important)
pub inline fn cToZigFormatComptime(comptime c_format: []const u8) [getZigFormatLenFromCFormat(c_format)]u8 {
    comptime {
        var buf: [getZigFormatLenFromCFormat(c_format)]u8 = undefined;
        var zig_format: ComptimeFormatBuffer = try ComptimeFormatBuffer.init(&buf);

        convert_from_c_to_zig(ComptimeFormatBuffer, &zig_format, c_format) catch |err| {
            @compileError("Invalid format, error: " ++ err);
        };

        return buf;
    }
}

// ===========================================================================
// Unit Tests
// ===========================================================================

const c_to_zig_specifiers = [_][2][]const u8{
    .{ "d", "d" },
    .{ "i", "d" },
    .{ "u", "u" },
    .{ "f", "f" },
    .{ "F", "f" },
    .{ "e", "e" },
    .{ "E", "e" },
    .{ "g", "f" }, // Zig does not have a 'g' specifier
    .{ "G", "f" }, // Zig does not have a 'G' specifier
    .{ "x", "x" },
    .{ "X", "X" },
    .{ "o", "o" },
    .{ "s", "s" },
    .{ "c", "c" },
    .{ "p", "t" }, // pointer
    .{ "a", "f" }, // Zig does not have an 'a' specifier
    .{ "A", "f" }, // Zig does not have an 'A' specifier
};

// Runtime

test "basic specifier conversion" {
    for (c_to_zig_specifiers) |pair| {
        const c_spec = pair[0];
        const expected_zig_spec = pair[1];

        const c_format = try std.fmt.allocPrint(std.testing.allocator, "Value: %{s}\n", .{c_spec});
        defer std.testing.allocator.free(c_format);

        const result = try cToZigFormat(std.testing.allocator, c_format);
        defer std.testing.allocator.free(result);

        const expected = try std.fmt.allocPrint(std.testing.allocator, "Value: {{{s}}}\n", .{expected_zig_spec});
        defer std.testing.allocator.free(expected);

        try std.testing.expectEqualSlices(u8, expected, result);
    }
}

test "hex with width specifier" {
    const c_format = "Memory address: %08x\n";
    const expected = "Memory address: {x:0>8}\n";

    const result = try cToZigFormat(std.testing.allocator, c_format);
    defer std.testing.allocator.free(result);

    try std.testing.expectEqualSlices(u8, expected, result);
}

// Comptime

test "basic specifier conversion (comptime)" {
    inline for (c_to_zig_specifiers) |pair| {
        const c_spec = pair[0];
        const expected_zig_spec = pair[1];

        const c_format = std.fmt.comptimePrint("Value: %{s}\n", .{c_spec});
        const result = cToZigFormatComptime(c_format);

        const expected = std.fmt.comptimePrint("Value: {{{s}}}\n", .{expected_zig_spec});

        try std.testing.expectEqualSlices(u8, expected, &result);
    }
}

test "hex with width specifier (comptime)" {
    const c_format = "Memory address: %08x\n";
    const expected = "Memory address: {x:0>8}\n";

    const result = cToZigFormatComptime(c_format);

    try std.testing.expectEqualSlices(u8, expected, &result);
}
