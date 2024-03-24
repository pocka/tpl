// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
//
// This file provides abstracted filesystem interface that works over both native FS
// and WebAssembly.

const builtin = @import("builtin");
const std = @import("std");
const mem = std.mem;

const MAX_READ_BYTES = std.math.maxInt(usize);

pub usingnamespace switch (builtin.os.tag) {
    .freestanding => struct {
        extern "fs" fn read_text_file(allocator: *const mem.Allocator, path_ptr: [*]const u8, path_len: usize) [*:0]u8;
        extern "fs" fn list_dir(
            allocator: *const mem.Allocator,
            path_ptr: [*]const u8,
            path_len: usize,
            ctx: *WasmDirEntryContext,
        ) void;

        const WasmDirEntryContext = struct {
            entries: *std.ArrayList(Entry),
        };

        export fn add_file_to_dir_entry_context(
            ctx: *WasmDirEntryContext,
            path_ptr: [*]const u8,
            path_len: usize,
        ) void {
            const path = path_ptr[0..path_len];

            ctx.entries.append(.{ .file = .{ .path = path } }) catch unreachable;
        }

        pub const Entry = union(enum) {
            dir: Dir,
            file: File,
        };

        pub const Dir = struct {
            path: []const u8,

            pub fn list(self: @This(), allocator: mem.Allocator) ![]const Entry {
                var entries = std.ArrayList(Entry).init(allocator);

                var ctx = try allocator.create(WasmDirEntryContext);
                ctx.* = .{ .entries = &entries };
                defer allocator.destroy(ctx);

                list_dir(
                    &allocator,
                    self.path.ptr,
                    self.path.len,
                    ctx,
                );

                return entries.toOwnedSlice();
            }

            pub fn open(path: []const u8) !@This() {
                return @This(){ .path = path };
            }
        };

        pub const File = struct {
            path: []const u8,

            /// Returns file contents as UTF-8 text.
            /// Caller owns the returned slice.
            pub fn readText(self: @This(), allocator: mem.Allocator) ![]const u8 {
                const contents = read_text_file(&allocator, self.path.ptr, self.path.len);

                return mem.span(contents);
            }

            /// Returns File struct.
            /// This function succeeded does not guarantee the file is accessible.
            pub fn open(path: []const u8) @This() {
                return @This(){ .path = path };
            }

            /// Returns full path for the file.
            /// Caller owns the returned slice.
            pub fn getPath(self: @This(), allocator: mem.Allocator) ![]const u8 {
                return allocator.dupe(u8, self.path);
            }
        };
    },
    else => struct {
        pub const Entry = union(enum) {
            dir: Dir,
            file: File,
        };

        pub const Dir = struct {
            path: []const u8,
            parent: ?*const Dir,

            fn getPathTraversing(self: @This(), result_path: *std.ArrayList(u8)) !void {
                if (self.parent) |parent| {
                    try parent.getPathTraversing(result_path);
                    try result_path.append(std.fs.path.sep);
                }

                try result_path.appendSlice(self.path);
            }

            fn getFsDir(self: @This(), allocator: mem.Allocator) !*std.fs.Dir {
                var dir = try allocator.create(std.fs.Dir);

                if (self.parent) |parent| {
                    const parent_dir = try parent.getFsDir(allocator);
                    defer parent_dir.close();

                    dir.* = try parent_dir.openDir(self.path, .{});
                    return dir;
                }

                var result_path = std.ArrayList(u8).init(allocator);

                try self.getPathTraversing(&result_path);

                const p = try result_path.toOwnedSlice();
                defer allocator.free(p);

                dir.* = try std.fs.openDirAbsolute(p, .{});

                return dir;
            }

            pub fn list(self: @This(), allocator: mem.Allocator) ![]const Entry {
                var entries = std.ArrayList(Entry).init(allocator);

                const dir = try self.getFsDir(allocator);
                defer dir.close();

                var iterable = try dir.openIterableDir(".", .{});
                defer iterable.close();

                var iter = iterable.iterate();

                while (try iter.next()) |entry| {
                    const name = try allocator.dupe(u8, entry.name);

                    switch (entry.kind) {
                        .file => {
                            try entries.append(.{ .file = .{ .path = name, .parent = &self } });
                        },
                        .directory => {
                            try entries.append(.{ .dir = .{ .path = name, .parent = &self } });
                        },
                        else => {},
                    }
                }

                return entries.toOwnedSlice();
            }

            pub fn open(path: []const u8) !@This() {
                return @This(){
                    .path = path,
                    .parent = null,
                };
            }
        };

        pub const File = struct {
            path: []const u8,
            parent: ?*const Dir,

            /// Returns file contents as UTF-8 text.
            /// Caller owns the returned slice.
            pub fn readText(self: @This(), allocator: mem.Allocator) ![]const u8 {
                const file = if (self.parent) |parent| try parent.openFile(self.path, .{}) else try std.fs.openFileAbsolute(self.path, .{});

                return file.readToEndAlloc(allocator, MAX_READ_BYTES);
            }

            /// Returns File struct.
            /// This function succeeded does not guarantee the file is accessible.
            pub fn open(path: []const u8) @This() {
                return @This(){
                    .path = path,
                    .parent = null,
                };
            }

            /// Returns full path for the file.
            /// Caller owns the returned slice.
            pub fn getPath(self: @This(), allocator: mem.Allocator) ![]const u8 {
                if (self.parent) |parent| {
                    var result_path = std.ArrayList(u8).init(allocator);

                    try parent.getPathTraversing(&result_path);

                    try result_path.append(std.fs.path.sep);
                    try result_path.appendSlice(self.path);

                    return result_path.toOwnedSlice();
                }

                return allocator.dupe(u8, self.path);
            }
        };
    },
};
