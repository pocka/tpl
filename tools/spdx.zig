const std = @import("std");

const spdxLicenseListJsonUri = "https://raw.githubusercontent.com/spdx/license-list-data/v3.23/json/licenses.json";

/// Data format for license-list-data's each license.
/// Unnecessary fields are omitted: set `.ignore_unknown_fields` when parsing.
const SpdxLicenseSummary = struct {
    isDeprecatedLicenseId: bool,
    name: []const u8,
    licenseId: []const u8,
    isOsiApproved: bool,
};

/// Data format for license-list-data JSON top-level object.
const SpdxLicenseList = struct {
    licenseListVersion: []const u8,
    licenses: []const SpdxLicenseSummary,
    releaseDate: []const u8,
};

/// Fetches SPDX license list from spdx/license-list-data repository and Returns parsed data.
/// Some of the allocations made during this operation are not tracked. Use `std.heap.ArenaAllocator`.
/// TODO: Use git submodule once jj adds support fot it.
fn fetchSpdxLicense(allocator: std.mem.Allocator) !SpdxLicenseList {
    const uri = try std.Uri.parse(spdxLicenseListJsonUri);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var headers = std.http.Headers.init(allocator);
    defer headers.deinit();
    try headers.append("Accept", "application/json");

    var req = try client.request(.GET, uri, headers, .{});
    defer req.deinit();

    try req.start();
    try req.finish();
    try req.wait();

    const body = try req.reader().readAllAlloc(allocator, 8096 * 1024);

    return std.json.parseFromSliceLeaky(SpdxLicenseList, allocator, body, .{ .ignore_unknown_fields = true });
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len != 2) fatal("wrong number of arguments", .{});

    const licenseList = try fetchSpdxLicense(allocator);

    const output_file_path = args[1];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    const writer = output_file.writer();

    try output_file.writeAll("pub const idList = [_][]const u8{");
    for (licenseList.licenses) |license| {
        // Escape double quotes in a license id.
        // This is here as a safety, although the current data do not contain a license id having double quotes.
        const safe_id = try std.mem.replaceOwned(u8, allocator, license.licenseId, "\"", "\\\"");
        defer allocator.free(safe_id);

        try std.fmt.format(writer, "\"{s}\",", .{license.licenseId});
    }
    try output_file.writeAll("};");

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
