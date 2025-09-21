# C-Zig Format Converter

> [!WARNING]
> This library is incomplete. Currently only C -> Zig format conversion is supported, there are no comptime functions, and the conversion may not be very exact with some of C's flag characters or length modifiers.

This Zig library converts C format strings (like those used in `printf`) into Zig format strings (like those used in `std.debug.print`)
E.g:
- `"counter = %d"` -> `"counter = {d}"`
- `"Memory address: %08x\n"` -> `"Memory address: {x:0>8}\n"`

## Basic Usage

### As a Library
```zig
const std = @import("std");
const converter = @import("c-zig-format-converter");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Convert a C format string to Zig format
    const c_format = "User %s has %d points (%.2f%%)";
    const zig_format = try converter.cToZigFormat(allocator, c_format);
    defer allocator.free(zig_format);

    // Use the converted format string
    const output = try std.fmt.allocPrint(allocator, zig_format, .{ "Alice", 1337, 98.5 });
    defer allocator.free(output);
    
    std.debug.print("{s}\n", .{output}); // "User Alice has 1337 points (98.50%)"
}
```

### As a CLI
```bash
$ zig build -Doptimize=ReleaseFast
$ ./zig-out/bin/c-zig-format-converter c "counter = %d\n"
counter = {d}
```

## Formats

For reference, these are the expected conversion specifiers:
- The official C syntax: `%[flags][width][.precision][length]specifier`
- The official Zig syntax: `{[argument][specifier]:[fill][alignment][width][.precision]}`

See `man 3 printf` for specifics regarding the C format strings and [Zig std.Io.Writer](https://ziglang.org/documentation/master/std/#std.Io.Writer) for specifics regarding the Zig format strings.
