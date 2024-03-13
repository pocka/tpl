// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;

const scan = @import("scan.zig");
const Strategy = scan.Strategy;

const Chameleon = @import("chameleon").Chameleon;

const usage =
    \\TPL Scan - Scan license for a file
    \\
    \\{[usage_title]s}: tpl scan [OPTIONS] <FILE>
    \\
    \\{[option_title]s}:
    \\  --strategy <VALUE>, -s  Scan strategy. Available values: file [default: file]
    \\  --package <PATH>, -p    Package directory. Defaults to cwd.
    \\  --root <PATH>           Root directory. Defaults to cwd.
    \\  --help                  Print this message on stdout.
    \\
;

fn printUsage(comptime cham: Chameleon, writer: anytype) !void {
    comptime var title = cham.underline().bold();

    return std.fmt.format(writer, usage, .{
        .usage_title = title.fmt("USAGE"),
        .option_title = title.fmt("OPTIONS"),
    });
}

const StrategyParseError = error{
    UnknownStrategy,
};

fn parseStrategy(str: []const u8) StrategyParseError!Strategy {
    if (ascii.eqlIgnoreCase(str, "file")) {
        return Strategy.file;
    }

    return StrategyParseError.UnknownStrategy;
}

const OptionParseError = error{
    MissingValue,
    UnknownOption,
    DuplicatedFile,
};

const Options = struct {
    help: bool,
    strategy: Strategy,
    package_root: []const u8,
    root: []const u8,
    file: []const u8,

    fn toParams(self: Options) scan.Params {
        return scan.Params{
            .strategy = self.strategy,
            .file = self.file,
            .root = self.root,
            .package_root = self.package_root,
        };
    }

    fn parseInternal(self: *Options, args: []const [:0]const u8) !void {
        comptime var errmsg = Chameleon.init(.Auto).red();

        if (args.len == 0) {
            return;
        }

        const flag = args[0];

        if (mem.eql(u8, flag, "--help")) {
            self.help = true;
            return;
        }

        if (mem.eql(u8, flag, "--strategy") or mem.eql(u8, flag, "-s")) {
            if (args.len < 2) {
                try std.fmt.format(std.io.getStdErr().writer(), errmsg.fmt("Option `{s}` requires a value.\n"), .{flag});
                return OptionParseError.MissingValue;
            }

            const value = args[1];

            self.strategy = parseStrategy(value) catch |err| {
                try std.fmt.format(std.io.getStdErr().writer(), errmsg.fmt("Invalid strategy option value: {s}.\n"), .{value});
                return err;
            };

            return self.parseInternal(args[2..]);
        }

        if (mem.startsWith(u8, flag, "--package") or mem.eql(u8, flag, "-p")) {
            if (args.len < 2) {
                try std.fmt.format(std.io.getStdErr().writer(), errmsg.fmt("Option `{s}` requires a value.\n"), .{flag});
                return OptionParseError.MissingValue;
            }

            self.package_root = args[1];

            return self.parseInternal(args[2..]);
        }

        if (mem.startsWith(u8, flag, "--root")) {
            if (args.len < 2) {
                try std.fmt.format(std.io.getStdErr().writer(), errmsg.fmt("Option `{s}` requires a value.\n"), .{flag});
                return OptionParseError.MissingValue;
            }

            self.root = args[1];

            return self.parseInternal(args[2..]);
        }

        if (mem.startsWith(u8, flag, "-")) {
            try std.fmt.format(std.io.getStdErr().writer(), errmsg.fmt("Unknown option: {s}\n"), .{flag});
            return OptionParseError.UnknownOption;
        }

        if (self.file.len > 0) {
            try std.io.getStdErr().writeAll(errmsg.fmt("You can only pass one file at a time.\n"));
            return OptionParseError.DuplicatedFile;
        }

        self.file = flag;
        return self.parseInternal(args[1..]);
    }

    pub fn parse(args: []const [:0]const u8) !Options {
        var my = Options{
            .help = false,
            .strategy = Strategy.file,
            .package_root = ".",
            .root = ".",
            .file = "",
        };

        try my.parseInternal(args);

        return my;
    }
};

pub fn command(allocator: mem.Allocator, comptime cham: Chameleon, args: []const [:0]const u8) !void {
    comptime var errmsg = cham.red();

    const stderr = std.io.getStdErr();

    var opts = Options.parse(args) catch {
        try printUsage(cham, stderr.writer());
        std.process.exit(1);
    };

    if (opts.help) {
        return printUsage(cham, std.io.getStdOut().writer());
    }

    if (opts.file.len == 0) {
        try printUsage(cham, stderr.writer());
        try stderr.writeAll(errmsg.fmt("FILE is required\n"));
        std.process.exit(1);
    }

    const cwd = std.fs.cwd();

    var file_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    opts.file = try cwd.realpath(opts.file, &file_buffer);
    var root_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    opts.root = try cwd.realpath(opts.root, &root_buffer);
    var package_root_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    opts.package_root = try cwd.realpath(opts.package_root, &package_root_buffer);

    const result = scan.scan(allocator, opts.toParams()) catch |err| {
        switch (err) {
            scan.ScanError.LicenseOrCopyrightNotFound => {
                try stderr.writeAll(errmsg.fmt("License file not found.\n"));
                std.process.exit(2);
            },
            else => {
                try stderr.writeAll(errmsg.fmt("Scan aborted due to error.\n"));
                std.process.exit(1);
            },
        }
    };

    const output = try std.json.stringifyAlloc(allocator, result.*, .{});
    defer allocator.free(output);

    try std.io.getStdOut().writeAll(output);
    try std.io.getStdOut().writeAll("\n");
}

test {
    std.testing.refAllDecls(@This());
}
