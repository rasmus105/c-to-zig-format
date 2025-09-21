const std = @import("std");
const lib = @import("root.zig");

const ProgramError = error{
    InvalidNumberOfArguments,
    InvalidFormat,
    FormatNotSupported,
    FormatError,
};

const Format = enum {
    c,
    zig,

    pub fn from_string(string: []u8) !Format {
        if (std.mem.eql([]u8, "c", string) or std.mem.eql([]u8, "C", string)) {
            return .c;
        } else if (std.mem.eql([]u8, "zig", string) or std.mem.eql([]u8, "Zig", string) or std.mem.eql([]u8, "ZIG", string)) {
            return .zig;
        } else {
            return ProgramError.InvalidFormat;
        }
    }
};

fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    if (args.len != 3) {
        std.debug.print("Usage: {s} <arg1> <arg2>\n", .{args[0]});
        return ProgramError.InvalidNumberOfArguments;
    }

    const source_format = Format.from_string(args[1]) catch |err| {
        std.debug.print("Invalid source format\n", .{});
        return err;
    };
    const format_string = args[2];

    var output = undefined;

    switch (source_format) {
        .c => {
            output = lib.cToZigFormat(format_string);
        },
        else => {
            std.debug.print("Source format not supported\n");
            return ProgramError.FormatNotSupported;
        },
    }

    try std.io.getStdOut().writer().print("{s}\n", .{output});
}
