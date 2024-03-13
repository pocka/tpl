// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

const scan = @import("scan/scan.zig");

/// Allocates `len` size memory for u8 slice and Returns its address.
/// When to use: Host wants to pass a string (slice of u8) to the wasm module.
/// Fails if no enough space is available on memory.
export fn allocate_u8(allocator: *std.mem.Allocator, len: usize) [*]u8 {
    return (allocator.alloc(u8, len) catch unreachable).ptr;
}

/// Returns length of the string part of the NULL-terminated string (C string).
/// NULL character is not included in the range.
/// When to use: Host wants to read an address for a string (slice of u8) returned
///              by wasm functions, and needs to know the length.
export fn get_cstring_len(ptr: [*:0]u8) usize {
    return std.mem.span(ptr).len;
}

/// Creates arena allocator and Returns its address.
/// Fails if no enough space is available on memory.
export fn init_arena() *std.heap.ArenaAllocator {
    var arena = std.heap.wasm_allocator.create(std.heap.ArenaAllocator) catch unreachable;

    arena.* = std.heap.ArenaAllocator.init(std.heap.wasm_allocator);

    return arena;
}

/// Gets an allocator interface from an arena then its address.
/// Fails if no enough space is available on memory.
export fn get_arena_allocator(arena: *std.heap.ArenaAllocator) *std.mem.Allocator {
    var allocator = std.heap.wasm_allocator.create(std.mem.Allocator) catch unreachable;

    allocator.* = arena.allocator();

    return allocator;
}

/// Frees all memory allocated in the arena.
export fn deinit_arena(arena: *std.heap.ArenaAllocator) void {
    arena.deinit();
}

/// Context object for ease of use.
const Scanner = struct {
    params: *scan.Params,
};

/// Create Scanner context object and Returns its address.
/// Caller needs to fill every field using `set_scanner_*` functions.
/// Fails if no enough space is available on memory.
export fn create_scanner(allocator: *const std.mem.Allocator) *Scanner {
    var params = allocator.create(scan.Params) catch unreachable;
    params.* = scan.Params{
        .strategy = .file,
        .package_root = "",
        .file = "",
        .root = "",
    };

    var scanner = allocator.create(Scanner) catch unreachable;
    scanner.* = Scanner{ .params = params };

    return scanner;
}

/// Sets package_root field on a scanner.
export fn set_scanner_package_root(
    scanner: *Scanner,
    path_ptr: [*]u8,
    path_len: usize,
) void {
    scanner.*.params.*.package_root = path_ptr[0..path_len];
}

/// Sets `file` field on a scanner.
export fn set_scanner_file(
    scanner: *Scanner,
    path_ptr: [*]u8,
    path_len: usize,
) void {
    scanner.*.params.*.file = path_ptr[0..path_len];
}

/// Sets `root` field on a scanner.
export fn set_scanner_root(
    scanner: *Scanner,
    path_ptr: [*]u8,
    path_len: usize,
) void {
    scanner.*.params.*.root = path_ptr[0..path_len];
}

export fn scan_file(allocator: *const std.mem.Allocator, scanner: *const Scanner) [*:0]u8 {
    const tpl = scan.scan(allocator.*, scanner.*.params.*) catch |err| {
        const msg = std.fmt.allocPrintZ(allocator.*, "{{\"error\":\"{s}\"}}", .{@errorName(err)}) catch unreachable;

        return msg;
    };

    const output = std.json.stringifyAlloc(allocator.*, tpl, .{}) catch unreachable;
    defer allocator.free(output);

    var out_c = allocator.allocSentinel(u8, output.len, 0) catch unreachable;

    std.mem.copy(u8, out_c, output);

    return out_c;
}
