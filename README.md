# C-Zig Format Converter

> [!WARNING]
> This library is incomplete. Currently only C -> Zig format conversion is supported and the conversion may not be very exact with some of C's flag characters or length modifiers.

This Zig library converts C format strings (like those used in `printf`) into Zig format strings (like those used in `std.debug.print`)
E.g:
- `"counter = %d"` -> `"counter = {d}"`
- `"Memory address = %08x\n"` -> `"Memory address ={x:0>8}\n"`
- `"Percentage = %.2f%%\n"` -> `"Percentage = {d:.2}%""`

## Basic Usage

### As a Library
```zig
const std = @import("std");
const converter = @import("c-zig-format-converter.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Convert a C format string to Zig format
    const c_format = "User %s has %d points (%.2f%%)";
    const zig_format = try converter.cToZigFormat(allocator, c_format);
    defer allocator.free(zig_format);

    std.debug.print("{s}\n", .{zig_format}); // "User {s} has {d} points ({d:.2}%)"

    // Convert a C format string to Zig format at compile time
    const zig_format_comptime = converter.cToZigFormatComptime(c_format);

    std.debug.print("{s}\n", .{zig_format_comptime}); // "User {s} has {d} points ({d:.2}%)"
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
