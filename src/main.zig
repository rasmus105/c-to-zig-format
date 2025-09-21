const std = @import("std");
const lib = @import("root.zig");

// TODO eventually conversion from zig to c should be added
const Format = enum {
    c,
    zig,

    pub fn from_string(string: []u8) !Format {
        if (std.mem.eql(u8, "c", string) or std.mem.eql(u8, "C", string)) {
            return .c;
        } else if (std.mem.eql(u8, "zig", string) or std.mem.eql(u8, "Zig", string) or std.mem.eql(u8, "ZIG", string)) {
            return .zig;
        } else {
            return error.InvalidFormat;
        }
    }
};

pub fn main() !void {
    const args = try std.process.argsAlloc(std.heap.page_allocator);

    if (args.len != 3) {
        std.debug.print("Usage: {s} <arg1> <arg2>\n", .{args[0]});
        return error.InvalidNoArguments;
    }

    const source_format = Format.from_string(args[1]) catch |err| {
        std.debug.print("Invalid source format\n", .{});
        return err;
    };
    const format_string = args[2];

    const output = switch (source_format) {
        .c => lib.cToZigFormat(std.heap.page_allocator, format_string) catch |err| {
            std.debug.print("Invalid string format", .{});
            return err;
        },
        else => {
            std.debug.print("Source format not supported\n", .{});
            return error.FormatNotSupported;
        },
    };

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("{s}\n", .{output});
    try stdout.flush();
}
