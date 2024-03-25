// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const spdx = b.addExecutable(.{
        .name = "spdx",
        .root_source_file = .{ .path = "tools/spdx.zig" },
        .target = target,
    });

    const spdx_step = b.addRunArtifact(spdx);
    const spdx_out = spdx_step.addOutputFileArg("spdx.zig");

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSafe,
    });

    const exe = b.addExecutable(.{
        .name = "tpl",
        .root_source_file = .{ .path = "src/cli.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addAnonymousModule("spdx", .{
        .source_file = spdx_out,
    });

    b.installArtifact(exe);

    const lib = b.addSharedLibrary(.{
        .name = "tpl",
        .root_source_file = .{ .path = "src/wasm.zig" },
        .target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
        .optimize = .ReleaseSmall,
    });
    lib.rdynamic = true;

    lib.addAnonymousModule("spdx", .{
        .source_file = spdx_out,
    });

    b.installArtifact(lib);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/cli.zig" },
        .target = target,
        .optimize = optimize,
    });

    unit_tests.addAnonymousModule("spdx", .{
        .source_file = spdx_out,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
