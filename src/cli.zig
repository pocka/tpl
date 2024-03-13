// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const mem = std.mem;

const scan = @import("scan/command.zig");

const Chameleon = @import("chameleon").Chameleon;

const usage_tmpl =
    \\TPL - Third-Party License listing tool
    \\
    \\{[usage_title]s}: tpl <COMMAND> [OPTIONS]
    \\
    \\{[command_title]s}:
    \\  help    Print this message on stdout.
    \\  scan    Scan a license of a file.
    \\
;

fn printUsage(comptime cham: Chameleon, writer: anytype) !void {
    comptime var title = cham.underline().bold();

    return std.fmt.format(writer, usage_tmpl, .{ .command_title = title.fmt("COMMAND"), .usage_title = title.fmt("USAGE") });
}

pub fn main() !void {
    comptime var cham = Chameleon.init(.Auto);
    comptime var err = cham.red();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    const command = if (args.len > 1) args[1] else "";

    if (mem.eql(u8, command, "help")) {
        return printUsage(cham, std.io.getStdOut().writer());
    }

    if (mem.eql(u8, command, "scan")) {
        return scan.command(allocator, cham, args[2..]);
    }

    for (args) |arg| {
        std.debug.print("arg: {s}\n", .{arg});
    }

    const stderr = std.io.getStdErr();

    try printUsage(cham, stderr.writer());

    if (command.len == 0) {
        return stderr.writeAll(err.fmt("\nPlease provide a COMMAND\n"));
    }

    return std.fmt.format(stderr.writer(), err.fmt("\nUnknown COMMAND: {s}\n"), .{command});
}

test {
    std.testing.refAllDecls(@This());
}
