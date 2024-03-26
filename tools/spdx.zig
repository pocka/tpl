const std = @import("std");

const spdxLicenseListJsonUri = "https://raw.githubusercontent.com/spdx/license-list-data/v3.23/json/licenses.json";
const spdxExceptionListJsonUri = "https://raw.githubusercontent.com/spdx/license-list-data/v3.23/json/exceptions.json";

// TODO: Use git submodule once jj adds support fot it.
fn RemoteData(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        data: *const T,
        json_str: []const u8,

        fn init(allocator: std.mem.Allocator, url: []const u8) !@This() {
            const uri = try std.Uri.parse(url);

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

            const parsed = try std.json.parseFromSlice(T, allocator, body, .{ .ignore_unknown_fields = true });

            return @This(){
                .allocator = allocator,
                .data = &parsed.value,
                .json_str = body,
            };
        }

        fn deinit(self: @This()) void {
            self.allocator.destroy(self.data);
            self.allocator.free(self.json_str);
        }
    };
}

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

/// Data format for license-list-data's each exception.
/// Unnecessary fields are omitted: set `.ignore_unknown_fields` when parsing.
const SpdxExceptionSummary = struct {
    isDeprecatedLicenseId: bool,
    name: []const u8,
    licenseExceptionId: []const u8,
};

/// Data format for license-list-data exceptions JSON top-level object.
const SpdxExceptionsList = struct {
    licenseListVersion: []const u8,
    exceptions: []const SpdxExceptionSummary,
    releaseDate: []const u8,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);

    if (args.len != 2) fatal("wrong number of arguments", .{});

    const output_file_path = args[1];

    var output_file = std.fs.cwd().createFile(output_file_path, .{}) catch |err| {
        fatal("unable to open '{s}': {s}", .{ output_file_path, @errorName(err) });
    };
    defer output_file.close();

    const writer = output_file.writer();

    // Write license ids
    {
        const licenseList = try RemoteData(SpdxLicenseList).init(allocator, spdxLicenseListJsonUri);
        defer licenseList.deinit();

        if (licenseList.data.licenses.len == 0) {
            fatal("No license data found on the fetched data: licenseListVersion={s}, releaseDate={s}", .{
                licenseList.data.licenseListVersion,
                licenseList.data.releaseDate,
            });
        }

        try output_file.writeAll("pub const idList = [_][]const u8{");
        for (licenseList.data.licenses) |license| {
            // Escape double quotes in a license id.
            // This is here as a safety, although the current data do not contain a license id having double quotes.
            const safe_id = try std.mem.replaceOwned(u8, allocator, license.licenseId, "\"", "\\\"");
            defer allocator.free(safe_id);

            try std.fmt.format(writer, "\"{s}\",", .{license.licenseId});
        }
        try output_file.writeAll("};");
    }

    // Write exception ids
    {
        const exceptionList = try RemoteData(SpdxExceptionsList).init(allocator, spdxExceptionListJsonUri);
        defer exceptionList.deinit();

        if (exceptionList.data.exceptions.len == 0) {
            fatal("No exception data found on the fetched data: licenseListVersion={s}, releaseDate={s}", .{
                exceptionList.data.licenseListVersion,
                exceptionList.data.releaseDate,
            });
        }

        try output_file.writeAll("pub const exceptionIdList = [_][]const u8{");
        for (exceptionList.data.exceptions) |exception| {
            // Escape double quotes in an exception id.
            // This is here as a safety, although the current data do not contain an exception id having double quotes.
            const safe_id = try std.mem.replaceOwned(u8, allocator, exception.licenseExceptionId, "\"", "\\\"");
            defer allocator.free(safe_id);

            try std.fmt.format(writer, "\"{s}\",", .{exception.licenseExceptionId});
        }
        try output_file.writeAll("};");
    }

    return std.process.cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.debug.print(format, args);
    std.process.exit(1);
}
