// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;

const scan = @import("scan.zig");
const Strategy = scan.Strategy;

const Term = @import("../Term.zig");

const usage =
    \\TPL Scan - Scan license for a file
    \\
    \\<u><b>USAGE</b></u>: tpl scan [OPTIONS] \<FILE\>
    \\
    \\<u><b>OPTIONS</b></u>:
    \\  --strategy \<VALUE>, -s  Scan strategy. Available values: file [default: file]
    \\  --package \<PATH>, -p    Package directory. Defaults to cwd.
    \\  --root \<PATH>           Root directory. Defaults to cwd.
    \\  --help                  Print this message on stdout.
    \\
;

fn printUsage(term: Term) !void {
    return term.format(usage, .{});
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

    fn parseInternal(self: *Options, stderr: Term, args: []const [:0]const u8) !void {
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
                try stderr.format("<fg.red>Option `{s}` requires a value.</fg.red>\n", .{flag});
                return OptionParseError.MissingValue;
            }

            const value = args[1];

            self.strategy = parseStrategy(value) catch |err| {
                try stderr.format("<fg.red>Invalid strategy option value: {s}.</fg.red>\n", .{value});
                return err;
            };

            return self.parseInternal(stderr, args[2..]);
        }

        if (mem.startsWith(u8, flag, "--package") or mem.eql(u8, flag, "-p")) {
            if (args.len < 2) {
                try stderr.format("<fg.red>Option `{s}` requires a value.</fg.red>\n", .{flag});
                return OptionParseError.MissingValue;
            }

            self.package_root = args[1];

            return self.parseInternal(stderr, args[2..]);
        }

        if (mem.startsWith(u8, flag, "--root")) {
            if (args.len < 2) {
                try stderr.format("<fg.red>Option `{s}` requires a value.</fg.red>\n", .{flag});
                return OptionParseError.MissingValue;
            }

            self.root = args[1];

            return self.parseInternal(stderr, args[2..]);
        }

        if (mem.startsWith(u8, flag, "-")) {
            try stderr.format("<fg.red>Unknown option: {s}</fg.red>\n", .{flag});
            return OptionParseError.UnknownOption;
        }

        if (self.file.len > 0) {
            try stderr.format("<fg.red>You can only pass one file at a time.</fg.red>\n", .{});
            return OptionParseError.DuplicatedFile;
        }

        self.file = flag;
        return self.parseInternal(stderr, args[1..]);
    }

    pub fn parse(stderr: Term, args: []const [:0]const u8) !Options {
        var my = Options{
            .help = false,
            .strategy = Strategy.file,
            .package_root = ".",
            .root = ".",
            .file = "",
        };

        try my.parseInternal(stderr, args);

        return my;
    }
};

pub fn command(allocator: mem.Allocator, args: []const [:0]const u8) !void {
    const stderr = Term.init(.{ .file = std.io.getStdErr() });

    var opts = Options.parse(stderr, args) catch {
        try printUsage(stderr);
        std.process.exit(1);
    };

    if (opts.help) {
        return printUsage(Term.init(.{ .file = std.io.getStdOut() }));
    }

    if (opts.file.len == 0) {
        try printUsage(stderr);
        try stderr.format("<fg.red>FILE is required</fg.red>\n", .{});
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
                try stderr.format("<fg.red>License file not found</fg.red>\n", .{});
                std.process.exit(2);
            },
            else => {
                try stderr.format("<fg.red>Scan aborted due to an error.</fg.red>\n", .{});
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
