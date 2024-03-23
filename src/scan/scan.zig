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

fn findLicenseFile(allocator: Allocator, params: Params) !?*const fs.File {
    const dir = try fs.Dir.open(params.package_root);

    for (try dir.list(allocator)) |entry| {
        if (entry != .file) {
            continue;
        }

        const stem = std.fs.path.stem(entry.file.path);

        if (ascii.eqlIgnoreCase(stem, "LICENSE") or ascii.eqlIgnoreCase(stem, "LICENCE")) {
            return entry.file;
        }
    }

    return null;
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
    const file = try findLicenseFile(allocator, params);
    if (file == null) {
        return ScanError.LicenseOrCopyrightNotFound;
    }

    var target_files = try allocator.alloc(tpl.FileRef, 1);
    target_files[0] = .{ .path = stripRootPrefix(params.file, params.root) };

    var license_includes = try allocator.alloc(tpl.IncludeItem, 1);
    license_includes[0] = .{
        .file = .{
            .path = stripRootPrefix(try file.?.getPath(allocator), params.root),
        },
    };

    var licenses = try allocator.alloc(tpl.LicenseGroup, 1);
    licenses[0] = .{
        .files = target_files,
        .license = .{
            .arbitrary = .{
                .type = "arbitrary",
                .includes = license_includes,
            },
        },
    };

    var copyrights = try allocator.alloc(tpl.Copyright, 0);

    var result = try allocator.create(tpl.Tpl);
    result.* = tpl.Tpl{
        .project = .{
            .id = stripRootPrefix(params.package_root, params.root),
            .displayName = stripRootPrefix(params.package_root, params.root),
            .description = null,
        },
        .licenses = licenses,
        .copyrights = copyrights,
    };

    return result;
}

test {
    @import("std").testing.refAllDecls(@This());
}
