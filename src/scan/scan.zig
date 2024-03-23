// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const ascii = std.ascii;
const mem = std.mem;
const Allocator = mem.Allocator;

const builtin = @import("builtin");
const tpl = @import("../tpl.zig");
const fs = @import("../fs.zig");

pub const Strategy = enum {
    file,
};

pub const Params = struct {
    strategy: Strategy,
    package_root: []const u8,
    root: []const u8,
    file: []const u8,
};

pub const ScanError = error{
    LicenseOrCopyrightNotFound,
};

pub fn scan(allocator: Allocator, params: Params) !*const tpl.Tpl {
    return switch (params.strategy) {
        .file => scanFile(allocator, params),
    };
}

fn findLicenseFiles(allocator: Allocator, params: Params) ![]const fs.File {
    var files = std.ArrayList(fs.File).init(allocator);

    const dir = try fs.Dir.open(params.package_root);

    for (try dir.list(allocator)) |entry| {
        if (entry != .file) {
            continue;
        }

        const stem = std.fs.path.stem(entry.file.path);

        if (ascii.eqlIgnoreCase(stem, "LICENSE") or ascii.eqlIgnoreCase(stem, "LICENCE")) {
            try files.append(entry.file.*);
            continue;
        }

        const basename = std.fs.path.basename(entry.file.path);

        if (mem.eql(u8, basename, "COPYING")) {
            try files.append(entry.file.*);
            continue;
        }

        if (mem.eql(u8, basename, "NOTICE")) {
            try files.append(entry.file.*);
            continue;
        }
    }

    return files.toOwnedSlice();
}

fn stripRootPrefix(target_path: []const u8, root_dir: []const u8) []const u8 {
    if (target_path.len <= root_dir.len) {
        return target_path;
    }

    if (!mem.startsWith(u8, target_path, root_dir)) {
        return target_path;
    }

    if (target_path[root_dir.len] != std.fs.path.sep) {
        return target_path;
    }

    return target_path[(root_dir.len + 1)..];
}

fn scanFile(allocator: Allocator, params: Params) !*const tpl.Tpl {
    const files = try findLicenseFiles(allocator, params);
    if (files.len == 0) {
        return ScanError.LicenseOrCopyrightNotFound;
    }

    var target_files = try allocator.alloc(tpl.FileRef, 1);
    target_files[0] = .{ .path = stripRootPrefix(params.file, params.root) };

    var license_includes = try allocator.alloc(tpl.IncludeItem, files.len);
    for (files, 0..) |file, i| {
        license_includes[i] = .{
            .file = .{
                .path = stripRootPrefix(try file.getPath(allocator), params.root),
            },
        };
    }

    var result = try allocator.create(tpl.Tpl);
    result.* = tpl.Tpl{
        .files = target_files,
        .license = .{
            .arbitrary = .{
                .type = "arbitrary",
                .includes = license_includes,
            },
        },
    };

    return result;
}

test {
    @import("std").testing.refAllDecls(@This());
}
