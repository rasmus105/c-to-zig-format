//! This library provides a compile-time function to convert C-style format
//! strings to Zig format strings.
const std = @import("std");

const FormatState = enum {
    start, // no % found
    percent, // percent found. Any of "flags", "width", "precision", "length", or "conversion" may follow.
    flags, // flags found, any of "width", "precision", "length", or "conversion" may follow.
    width, // width found, any of "precision", "length", or "conversion" may follow. (width is a digit, 0-9)
    dot_found, // '.' found, digits expected next.
    precision, // precision found, any of "length" or "conversion" may follow.
    length, // length found, only "specifier" may follow (length is one of h, hh, l, ll, j, z, t, L)
    specifier, // only specifier is missing
    conversion, // specifier found, should convert to zig format and return to start state now.
};

const LengthModifier = enum {
    hh, // signed char or unsigned char
    h, // short int or unsigned short int
    l, // long int or unsigned long int or double (when used with e, E, f, F, g, G, a, A)
    ll, // long long int or unsigned long long int
    j, // intmax_t or uintmax_t
    z, // size_t
    t, // ptrdiff_t
    L, // long double (when used with e, E, f, F, g, G, a, A)

    pub fn slice_to_modifier(string: []u8) !LengthModifier {
        const length = string.len;
        if (length >= 3 or length == 0) {
            return error.UnknownLengthModifier;
        }

        switch (string[0]) {
            'h' => {
                if (length == 2) {
                    if (string[1] == 'h') {
                        return .hh;
                    } else {
                        return error.UnknownLengthModifier;
                    }
                } else {
                    return .h;
                }
            },
            'l' => {
                if (length == 2) {
                    if (string[1] == 'l') {
                        return .ll;
                    } else {
                        return error.UnknownLengthModifier;
                    }
                } else {
                    return .l;
                }
            },
            'j', 'z', 't', 'L' => {
                if (length == 1) {
                    return switch (string[0]) {
                        'j' => .j,
                        'z' => .z,
                        't' => .t,
                        'L' => .L,
                        else => unreachable,
                    };
                } else {
                    return error.UnknownLengthModifier;
                }
            },
            else => return error.UnknownLengthModifier,
        }
    }

    pub fn modifier_to_slice(self: LengthModifier) []const u8 {
        return switch (self) {
            .hh => "hh",
            .h => "h",
            .l => "l",
            .ll => "ll",
            .j => "j",
            .z => "z",
            .t => "t",
            .L => "L",
        };
    }
};

const CSpecifier = enum {
    signed_decimal,
    unsigned_octal,
    unsigned_decimal,
    unsigned_hex,
    unsigned_hex_uppercase,
    scientific_notation,
    scientific_notation_uppercase,
    decimal_float,
    decimal_float_uppercase,
    shortest_possible,
    shortest_possible_uppercase,
    hexadecimal_float,
    hexadecimal_float_uppercase,
    unsigned_char,
    null_terminated_string,
    pointer,
    number_of_characters_written,
    percent_sign,

    pub fn char_to_specifier(char: u8) !CSpecifier {
        return switch (char) {
            'd', 'i' => .signed_decimal,
            'o' => .unsigned_octal,
            'u' => .unsigned_decimal,
            'x' => .unsigned_hex,
            'X' => .unsigned_hex_uppercase,
            'e' => .scientific_notation,
            'E' => .scientific_notation_uppercase,
            'f' => .decimal_float,
            'F' => .decimal_float_uppercase,
            'g' => .shortest_possible,
            'G' => .shortest_possible_uppercase,
            'a' => .hexadecimal_float,
            'A' => .hexadecimal_float_uppercase,
            'c' => .unsigned_char,
            's' => .null_terminated_string,
            'p' => .pointer,
            'n' => .number_of_characters_written,
            '%' => .percent_sign,
            else => error.UnknownSpecifier,
        };
    }

    pub fn specifier_to_char(self: CSpecifier) []const u8 {
        return switch (self) {
            .signed_decimal => "d",
            .unsigned_octal => "o",
            .unsigned_decimal => "u",
            .unsigned_hex => "x",
            .unsigned_hex_uppercase => "X",
            .scientific_notation => "e",
            .scientific_notation_uppercase => "E",
            .decimal_float => "f",
            .decimal_float_uppercase => "F",
            .shortest_possible => "g",
            .shortest_possible_uppercase => "G",
            .hexadecimal_float => "a",
            .hexadecimal_float_uppercase => "A",
            .unsigned_char => "c",
            .null_terminated_string => "s",
            .pointer => "p",
            .number_of_characters_written => "n",
            .percent_sign => "%",
        };
    }

    pub fn to_zig_specifier(self: CSpecifier) !ZigSpecifier {
        return switch (self) {
            .signed_decimal => .decimal,
            .unsigned_octal => .octal,
            .unsigned_decimal => .decimal,
            .unsigned_hex => .hex,
            .unsigned_hex_uppercase => .hex_uppercase,
            .scientific_notation => .floating_point_scientific_notation,
            .scientific_notation_uppercase => .floating_point_scientific_notation, // zig does not differentiate between e and E
            .decimal_float => .decimal,
            .decimal_float_uppercase => .decimal, // zig does not differentiate between f and F
            .shortest_possible => .decimal, // more complicated logic is required for accurate conversion
            .shortest_possible_uppercase => .decimal, // more complicated logic is required for accurate conversion
            .hexadecimal_float => .hex, // zig does not have a direct equivalent for hexadecimal floating point
            .hexadecimal_float_uppercase => .hex_uppercase, // zig does not have a direct equivalent for hexadecimal floating point
            .unsigned_char => .ascii_character,
            .null_terminated_string => .null_terminated_string,
            .pointer => .address,
            .number_of_characters_written => error.NoZigEquivalent,
            .percent_sign => error.NoZigEquivalent,
        };
    }
};

const ZigSpecifier = enum {
    hex,
    hex_uppercase,
    null_terminated_string,
    tag_name,
    base64,
    floating_point_scientific_notation,
    decimal,
    binary,
    octal,
    ascii_character,
    utf8,
    duration,
    si_units,
    iec_units,
    optional,
    error_union,
    address,
    any,

    pub fn slice_to_specifier(string: []u8) !ZigSpecifier {
        const length = string.len;
        if (length >= 4 or length == 0) {
            return error.UnknownSpecifier;
        }

        if (length == 3) {
            if (std.mem.eql(u8, string, "any")) {
                return .any;
            } else {
                return error.UnknownSpecifier;
            }
        } else if (length == 2) {
            if (std.mem.eql(u8, string, "Bi")) {
                return .iec_units;
            } else if (std.mem.eql(u8, string, "b64")) {
                return .base64;
            } else {
                return error.UnknownSpecifier;
            }
        } else {
            return switch (string[0]) {
                'x' => .hex,
                'X' => .hex_uppercase,
                's' => .null_terminated_string,
                't' => .tag_name,
                'e' => .floating_point_scientific_notation,
                'd' => .decimal,
                'b' => .binary,
                'o' => .octal,
                'c' => .ascii_character,
                'u' => .utf8,
                'D' => .duration,
                'B' => .si_units,
                '?' => .optional,
                '!' => .error_union,
                '*' => .address,
                else => error.UnknownSpecifier,
            };
        }
    }

    pub fn specifier_to_slice(self: ZigSpecifier) []const u8 {
        return switch (self) {
            .hex => "x",
            .hex_uppercase => "X",
            .null_terminated_string => "s",
            .tag_name => "t",
            .base64 => "b64",
            .floating_point_scientific_notation => "e",
            .decimal => "d",
            .binary => "b",
            .octal => "o",
            .ascii_character => "c",
            .utf8 => "u",
            .duration => "D",
            .si_units => "B",
            .iec_units => "Bi",
            .optional => "?",
            .error_union => "!",
            .address => "*",
            .any => "any",
        };
    }
};

pub fn cToZigFormat(c_fmt: []const u8) ![100]u8 {
    // We create a buffer that is guaranteed to be large enough.
    var zig_fmt_buf: [100]u8 = undefined;
    var zig_fmt_index: usize = 0;

    var flag: ?[5]u8 = null; // e.g. '#', '0', '-', ' ', '+' (only up to 5 flags can be specified)
    var width_specifier: ?u16 = null; // e.g. 2, 5, etc.
    var precision_specifier: ?u16 = null; // e.g. .2, .5, etc.
    var length_modifier: ?LengthModifier = null; // e.g. ll, h, hh, etc. (an equivalent does not directly exist in zig)
    var conversion: ?CSpecifier = null; // called "specifier" in zig and "conversion" in C

    var state: FormatState = .start;

    inline for (c_fmt, 0..) |c, i| {
        @compileLog("i = " ++ std.fmt.comptimePrint("{d}", .{i}) ++ ", char = " ++ std.fmt.comptimePrint("{c}", .{c}) ++ ", state = " ++ std.fmt.comptimePrint("{t}", .{state}));

        switch (state) {
            .start => switch (c) {
                '%' => state = .percent,
                else => {
                    zig_fmt_buf[zig_fmt_index] = c;
                    zig_fmt_index += 1;
                },
            },
            .percent => switch (c) {
                '%' => {
                    // '%%' in C becomes '%' in Zig
                    zig_fmt_buf[zig_fmt_index] = '%';
                    zig_fmt_index += 1;
                    state = .start;
                },
                '#', '0', '-', ' ', '+' => {
                    flag = [5]u8{ c, 0, 0, 0, 0 }; // first flag found
                    state = .flags;
                },
                '1'...'9' => {
                    // save width specifier for later
                    width_specifier = c;
                    state = .width;
                },
                '.' => {
                    state = .dot_found; // next character should be precision specifier
                },
                'h', 'l', 'j', 'z', 't', 'L' => {
                    length_modifier = try LengthModifier.slice_to_modifier(@constCast(c_fmt[i..i]));
                    state = .length;
                },
                'd', 'i', 'o', 'u', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n' => {
                    conversion = try CSpecifier.char_to_specifier(c);
                    state = .conversion;
                },
                else => @compileError("expected flag, width, precision, length modifier, or conversion specifier after '%' (i = " ++ std.fmt.comptimePrint("{d}", .{i}) ++ ", char = " ++ std.fmt.comptimePrint("{c}", .{c}) ++ "): \"" ++ c_fmt ++ "\""),
            },
            .flags => switch (c) {
                '#', '0', '-', ' ', '+' => {
                    // multiple flags can be specified, apppend to the flag array
                    for (flag, 0..) |f, idx| {
                        if (f == 0) {
                            flag[idx] = c;
                            break;
                        } else if (idx == 4) {
                            @compileError("too many flags specified");
                        }
                    }
                },
                '1'...'9' => {
                    // save width specifier for later
                    width_specifier = c;
                    state = .width;
                },
                '.' => {
                    state = .dot_found; // next character should be precision specifier
                },
                'h', 'l', 'j', 'z', 't', 'L' => {
                    length_modifier = try LengthModifier.slice_to_modifier(c);
                    state = .length;
                },
                'd', 'i', 'o', 'u', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n' => {
                    conversion = try CSpecifier.char_to_specifier(c);
                    state = .conversion;
                },
                else => @compileError("expected width, precision, length modifier, or conversion specifier after flag"),
            },
            .width => switch (c) {
                '1'...'9' => {
                    // width specifier is multiple digits
                    const new_digit = std.fmt.parseInt(u8, c, 10) catch @compileError("invalid width specifier");
                    width_specifier = width_specifier + new_digit * 10;
                },
                '.' => {
                    state = .dot_found; // next character should be precision specifier
                },
                'h', 'l', 'j', 'z', 't', 'L' => {
                    length_modifier = try LengthModifier.slice_to_modifier(c);
                    state = .length;
                },
                'd', 'i', 'o', 'u', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n' => {
                    conversion = try CSpecifier.char_to_specifier(c);
                    state = .conversion;
                },
                else => @compileError("expected '.', length modifier, or conversion specifier after width specifier"),
            },
            .dot_found => switch (c) {
                '1'...'9' => {
                    // save preicision specifier for later
                    precision_specifier = std.fmt.parseInt(u16, c, 10) catch @compileError("invalid precision specifier");
                    state = .precision;
                },
                else => @compileError("expected precision specifier after '.' (i = " ++ std.fmt.comptimePrint("{d}", .{i}) ++ ", char = " ++ std.fmt.comptimePrint("{c}", .{c}) ++ "): \"" ++ c_fmt ++ "\""),
            },
            .precision => switch (c) {
                '1'...'9' => {
                    // precision specifier is multiple digits
                    const new_digit = std.fmt.parseInt(u16, c, 10) catch @compileError("invalid precision specifier");
                    precision_specifier = precision_specifier + new_digit * 10;
                },
                'h', 'l', 'j', 'z', 't', 'L' => {
                    length_modifier = try LengthModifier.slice_to_modifier(c);
                    state = .length;
                },
                'd', 'i', 'o', 'u', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n' => {
                    conversion = try CSpecifier.char_to_specifier(c);
                    state = .conversion;
                },
                else => @compileError("expected length modifier or conversion specifier after precision specifier"),
            },
            .length => switch (c) {
                'd', 'i', 'o', 'u', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n' => {
                    conversion = try CSpecifier.char_to_specifier(c);
                    state = .conversion;
                },
                'h', 'l' => {
                    // length modifiers can be two characters, e.g. 'hh' or 'll'
                    length_modifier = try LengthModifier.slice_to_modifier(c_fmt[(i - 1)..i]);
                    state = .specifier; // stay in length state
                },
                else => @compileError("expected conversion specifier after length modifier"),
            },
            .specifier => switch (c) {
                'd', 'i', 'o', 'u', 'x', 'X', 'e', 'E', 'f', 'F', 'g', 'G', 'a', 'A', 'c', 's', 'p', 'n' => {
                    conversion = try CSpecifier.char_to_specifier(c);
                    state = .conversion;
                },
                else => @compileError("expected conversion specifier after length modifier"),
            },
            .conversion => {
                // All flags and conversion have been found, now map to zig format
                // first step is to map the C conversion specifier to zig equivalent
                zig_fmt_buf[zig_fmt_index] = '{';
                zig_fmt_index += 1;
                zig_fmt_buf[zig_fmt_index] = conversion.?.to_zig_specifier().*;
                zig_fmt_index += 1;

                // add ':' if any of the other specifiers are present
                if (flag or width_specifier or precision_specifier or length_modifier) {
                    zig_fmt_buf[zig_fmt_index] = ':';
                    zig_fmt_index += 1;

                    // now add the fill (should be ' ', unless '0' flag is specified, then it should be '0')
                    if (std.mem.contains(u8, flag[0..], '0')) {
                        zig_fmt_buf[zig_fmt_index] = '0';
                    } else {
                        zig_fmt_buf[zig_fmt_index] = ' ';
                    }
                    zig_fmt_index += 1;

                    // now add the alignment (should be '>' unless '-' flag is specified, then it should be '<')
                    if (std.mem.contains(u8, flag[0..], '-')) {
                        zig_fmt_buf[zig_fmt_index] = '<';
                    } else {
                        zig_fmt_buf[zig_fmt_index] = '>';
                    }
                    zig_fmt_index += 1;

                    // now add the width specifier if present
                    if (width_specifier) {
                        const width_string = std.fmt.comptimePrint("{d}", width_specifier.?);
                        for (width_string) |char| {
                            zig_fmt_buf[zig_fmt_index] = char;
                            zig_fmt_index += 1;
                        }
                    }

                    if (precision_specifier) {
                        zig_fmt_buf[zig_fmt_index] = '.';
                        zig_fmt_index += 1;
                        const precision_string = std.fmt.comptimePrint("{d}", precision_specifier.?);
                        for (precision_string) |char| {
                            zig_fmt_buf[zig_fmt_index] = char;
                            zig_fmt_index += 1;
                        }
                    }
                }

                zig_fmt_buf[zig_fmt_index] = '}';
                zig_fmt_index += 1;

                // check if another conversion specifier follows
                if (c == '%') {
                    state = .percent;
                } else {
                    state = .start;
                }
            },
        }

        // ensure there is a next character if we are not in start or conversion state
        if (state != .start and state != .conversion) {
            if (i >= c_fmt.len) {
                @compileError("incomplete format specifier at end of string: \"" ++ c_fmt ++ "\"");
            }
        }
    }

    if (state == .conversion) {
        // All flags and conversion have been found, now map to zig format
        // first step is to map the C conversion specifier to zig equivalent
        zig_fmt_buf[zig_fmt_index] = '{';
        zig_fmt_index += 1;

        const zig_specifier = ZigSpecifier.specifier_to_slice(try conversion.?.to_zig_specifier());

        for (zig_specifier) |char| {
            zig_fmt_buf[zig_fmt_index] = char;
            zig_fmt_index += 1;
        }

        // add ':' if any of the other specifiers are present
        if (flag != null or width_specifier != null or precision_specifier != null or length_modifier != null) {
            zig_fmt_buf[zig_fmt_index] = ':';
            zig_fmt_index += 1;

            // now add the fill (should be ' ', unless '0' flag is specified, then it should be '0')
            if (std.mem.contains(u8, flag[0..], '0')) {
                zig_fmt_buf[zig_fmt_index] = '0';
            } else {
                zig_fmt_buf[zig_fmt_index] = ' ';
            }
            zig_fmt_index += 1;

            // now add the alignment (should be '>' unless '-' flag is specified, then it should be '<')
            if (std.mem.contains(u8, flag[0..], '-')) {
                zig_fmt_buf[zig_fmt_index] = '<';
            } else {
                zig_fmt_buf[zig_fmt_index] = '>';
            }
            zig_fmt_index += 1;

            // now add the width specifier if present
            if (width_specifier) {
                const width_string = std.fmt.comptimePrint("{d}", width_specifier.?);
                for (width_string) |char| {
                    zig_fmt_buf[zig_fmt_index] = char;
                    zig_fmt_index += 1;
                }
            }

            if (precision_specifier) {
                zig_fmt_buf[zig_fmt_index] = '.';
                zig_fmt_index += 1;
                const precision_string = std.fmt.comptimePrint("{d}", precision_specifier.?);
                for (precision_string) |char| {
                    zig_fmt_buf[zig_fmt_index] = char;
                    zig_fmt_index += 1;
                }
            }
        }

        zig_fmt_buf[zig_fmt_index] = '}';
        zig_fmt_index += 1;
    }

    @compileLog("final string = " ++ std.fmt.comptimePrint("{s}", .{zig_fmt_buf[0..zig_fmt_index]}));

    return zig_fmt_buf;
}

// C overall syntax: %[$][flags][width][.precision][length modifier]conversion

// Zig overall syntax: {[argument][specifier]:[fill][alignment][width].[precision]}

const c_specifiers = [_]u8{
    'd', 'i', // signed decimal
    'o', 'u', 'x', 'X', // unsigned (octal, decimal, hex, hex uppercase)
    'e', 'E', // scientific notation
    'f', 'F', // decimal/float
    'g', 'G', // shortest possible
    'a', 'A', // hexadecimal floating point
    'c', // unsigned char
    's', // null-terminated string
    'p', // pointer address is printed as if by %#x or %#lx
    'n', // number of arguments printed so far is stored in the integer.
    '%', // % is printed. No argument is converted.
};

const c_flags = [_]u8{
    '#', // Use an alternative form: for o conversion, it increases the precision to force the first character of the output string to be a zero (except if a zero value is printed with an explicit precision of zero).
    '0', // Left-pads the number with zeroes (0) instead of spaces when padding is specified (see width sub-specifier).
    '-', // Left-justify within the given field width; Right justification is the default (see width sub-specifier).
    ' ', // If no sign is going to be written, a blank space is inserted before the value.
    '+', // Forces to precede the result with a plus or minus sign (+ or -) even for positive numbers. By default, only negative numbers are preceded with a - sign.
};

const c_width_specifiers = [_]u8{
    '1', '2', '3', '4', '5', '6', '7', '8', '9',
};

const c_length_modifiers = [_]u8{
    // 'hh', // signed char or unsigned char
    'h', // short int or unsigned short int
    'l', // long int or unsigned long int or double (when used with e, E, f, F, g, G, a, A)
    // 'll', // long long int or unsigned long long int
    'j', // intmax_t or uintmax_t
    'z', // size_t
    't', // ptrdiff_t
    'L', // long double (when used with e, E, f, F, g, G, a, A)
};

// const zig_specifiers = []u8{
//     'x', 'X', // output numeric value in hexadecimal notation, or string in hexadecimal bytes
//
//     // for pointer-to-many and C pointers of u8, print as a C-string using zero-termination
//     // for slices of u8, print the entire slice as a string without zero-termination
//     's',
//
//     // for enums and tagged unions: prints the tag name
//     // for error sets: prints the error name
//     't',
//     'b64', // output string as standard base64
//     'e', // output floating point value in scientific notation
//     'd', // output numeric value in decimal notation
//     'b', // output integer value in binary notation
//     'o', // output integer value in octal notation
//     'c', // output integer as an ASCII character. Integer type must have 8 bits at max.
//     'u', // output integer as an UTF-8 sequence. Integer type must have 21 bits at max.
//     'D', // output nanoseconds as duration
//     'B', // output bytes in SI units (decimal)
//     'Bi', // output bytes in IEC units (binary)
//     '?', // output optional value as either the unwrapped value, or null; may be followed by a format specifier for the underlying value.
//     '!', // output error union value as either the unwrapped value, or the formatted error value; may be followed by a format specifier for the underlying value.
//     '*', // output the address of the value instead of the value itself.
//     'any', // output a value of any type using its default format.
//     'f', // delegates to a method on the type named 'format' with the signature fn (*Writer, args: anytype) Writer.Error!void.
// };

/// outline for how c specifiers should be converted to zig specifiers.
const c_to_zig_specifier_conversions = [_][2]u8{
    // decimal
    [_]u8{ 'd', 'd' },
    [_]u8{ 'i', 'd' },

    // unsigned
    [_]u8{ 'o', 'o' },
    [_]u8{ 'u', 'd' },
    [_]u8{ 'x', 'x' },
    [_]u8{ 'X', 'X' },

    // scientific notation
    [_]u8{ 'e', 'e' },
    [_]u8{ 'E', 'e' },

    // floating point
    [_]u8{ 'f', 'd' },
    [_]u8{ 'F', 'd' },

    // shortest possible (more complicated logic is required for accurate conversion)
    [_]u8{ 'g', 'd' },
    [_]u8{ 'G', 'd' },

    // hexadecimal floating point
    [_]u8{ 'a', 'x' },
    [_]u8{ 'A', 'X' },

    // unsigned char
    [_]u8{ 'c', 'c' },

    // null-terminated strings
    [_]u8{ 's', 's' },

    // pointer
    [_]u8{ 'p', '*' },
};

test "basic format specifier conversion" {
    inline for (c_to_zig_specifier_conversions) |pair| {
        const c_fmt: [:0]const u8 = std.fmt.comptimePrint("format specifier: %{c}", .{pair[0]});
        const expected_zig_fmt: []const u8 = std.fmt.comptimePrint("format specifier: {{{c}}}", .{pair[1]});

        const zig_fmt = comptime try cToZigFormat(c_fmt);
        const zig_fmt_cut = zig_fmt[0 .. std.mem.indexOfScalarPos(u8, &zig_fmt, 0, 0) orelse zig_fmt.len];

        std.debug.print("C format:\t{s}\n", .{c_fmt});
        std.debug.print("Zig format (untouched):\t{s}\n", .{zig_fmt});
        std.debug.print("Zig format:\t{s}\n", .{zig_fmt_cut});
        std.debug.print("Expected:\t{s}\n\n", .{expected_zig_fmt});

        // try std.testing.expectEqualStrings(expected_zig_fmt, zig_fmt_cut);
        try std.testing.expectEqual(false, true);
    }
}
