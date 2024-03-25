// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const mem = std.mem;

const scan = @import("scan/command.zig");
const Term = @import("Term.zig");

const usage_tmpl =
    \\TPL - Third-Party License listing tool
    \\
    \\<b><u>USAGE</u></b>: tpl \<COMMAND\> [OPTIONS]
    \\
    \\<b><u>COMMAND</u></b>:
    \\  help    Print this message on stdout.
    \\  scan    Scan a license of a file.
    \\
;

fn printUsage(term: Term) !void {
    return term.format(usage_tmpl, .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    const command = if (args.len > 1) args[1] else "";

    const stderr = Term.init(.{ .file = std.io.getStdErr() });

    if (mem.eql(u8, command, "help")) {
        return printUsage(Term.init(.{ .file = std.io.getStdOut() }));
    }

    if (mem.eql(u8, command, "scan")) {
        return scan.command(allocator, args[2..]);
    }

    for (args) |arg| {
        std.debug.print("arg: {s}\n", .{arg});
    }

    try printUsage(stderr);

    if (command.len == 0) {
        return stderr.format("\n<fg.red>Please provide a COMMAND</fg.red>\n", .{});
    }

    return stderr.format("\n<fg.red>Unknown COMMAND</fg.red>: {s}\n", .{command});
}

test {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(@import("./spdx.zig"));
}
