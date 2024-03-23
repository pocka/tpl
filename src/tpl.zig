// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const json = std.json;

pub const FileRef = struct {
    path: []const u8,
};

pub const InlineText = struct {
    text: []const u8,
};

pub const IncludeItem = union(enum) {
    file: FileRef,
    text: InlineText,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try switch (self.*) {
            .file => |file| jw.write(file),
            .text => |text| jw.write(text),
        };
    }

    pub fn jsonParse(
        allocator: mem.Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) json.ParseError(@TypeOf(source.*))!@This() {
        const value = try json.innerParse(json.Value, allocator, source, options);

        return @This().jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: mem.Allocator,
        value: json.Value,
        options: json.ParseOptions,
    ) json.ParseFromValueError!@This() {
        if (value != .object) {
            return error.UnexpectedToken;
        }

        if (value.object.get("path")) |path| {
            if (path != .string) {
                return error.UnexpectedToken;
            }

            const file = try json.parseFromValueLeaky(FileRef, allocator, value, options);

            return @This(){ .file = file };
        } else {
            const text = try json.parseFromValueLeaky(InlineText, allocator, value, options);

            return @This(){ .text = text };
        }
    }
};

test "Parse IncludeItem (file)" {
    const input =
        \\{
        \\  "path": "lib/main.js"
        \\}
        \\
    ;

    const item = try json.parseFromSlice(IncludeItem, testing.allocator, input, .{});
    defer item.deinit();

    try testing.expectEqualStrings(@tagName(item.value), "file");
    try testing.expectEqualStrings(item.value.file.path, "lib/main.js");
}

test "Parse IncludeItem (text)" {
    const input =
        \\{
        \\  "text": "Lorem ipsum blah blah"
        \\}
        \\
    ;

    const item = try json.parseFromSlice(IncludeItem, testing.allocator, input, .{});
    defer item.deinit();

    try testing.expectEqualStrings(@tagName(item.value), "text");
    try testing.expectEqualStrings(item.value.text.text, "Lorem ipsum blah blah");
}

pub const Spdx2_3License = struct {
    id: []const u8,

    includesLaterVersions: ?bool = null,

    includes: []const IncludeItem,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();

        try jw.objectField("id");
        try jw.write(self.id);

        if (self.includesLaterVersions) |includesLaterVersions| {
            try jw.objectField("includesLaterVersions");
            try jw.write(includesLaterVersions);
        }

        try jw.objectField("includes");
        try jw.write(self.includes);

        try jw.endObject();
    }
};

pub const Spdx2_3LicenseRef = struct {
    licenseRef: []const u8,

    documentRef: ?[]const u8 = null,

    includes: []const IncludeItem,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();

        try jw.objectField("licenseRef");
        try jw.write(self.licenseRef);

        if (self.documentRef) |documentRef| {
            try jw.objectField("documentRef");
            try jw.write(documentRef);
        }

        try jw.objectField("includes");
        try jw.write(self.includes);

        try jw.endObject();
    }
};

pub const Spdx2_3SimpleExpression = union(enum) {
    license: Spdx2_3License,
    licenseRef: Spdx2_3LicenseRef,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try switch (self.*) {
            .license => |license| jw.write(license),
            .licenseRef => |licenseRef| jw.write(licenseRef),
        };
    }

    pub fn jsonParse(
        allocator: mem.Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) json.ParseError(@TypeOf(source.*))!@This() {
        const value = try json.innerParse(json.Value, allocator, source, options);

        return @This().jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: mem.Allocator,
        value: json.Value,
        options: json.ParseOptions,
    ) json.ParseFromValueError!@This() {
        if (value != .object) {
            return error.UnexpectedToken;
        }

        if (value.object.contains("licenseRef")) {
            return @This(){ .licenseRef = try json.parseFromValueLeaky(Spdx2_3LicenseRef, allocator, value, options) };
        }

        return @This(){ .license = try json.parseFromValueLeaky(Spdx2_3License, allocator, value, options) };
    }
};

test "Parse Spdx2_3SimpleExpression (known ID)" {
    const input =
        \\{
        \\  "id": "Apache-2.0",
        \\  "includes": [
        \\    { "path": "LICENSE" },
        \\    { "path": "NOTICE" }
        \\  ]
        \\}
        \\
    ;

    const spdx = try json.parseFromSlice(Spdx2_3SimpleExpression, testing.allocator, input, .{});
    defer spdx.deinit();

    try testing.expectEqualStrings(spdx.value.license.id, "Apache-2.0");
    try testing.expectEqualStrings(spdx.value.license.includes[1].file.path, "NOTICE");
}

test "Parse Spdx2_3SimpleExpression (known ID, includes later versions)" {
    const input =
        \\{
        \\  "id": "CDDL-1.0",
        \\  "includesLaterVersions": true,
        \\  "includes": [
        \\    { "path": "LICENSE.txt" }
        \\  ]
        \\}
        \\
    ;

    const spdx = try json.parseFromSlice(Spdx2_3SimpleExpression, testing.allocator, input, .{});
    defer spdx.deinit();

    try testing.expectEqualStrings(spdx.value.license.id, "CDDL-1.0");
    try testing.expectEqual(spdx.value.license.includesLaterVersions, true);
}

test "Parse Spdx2_3SimpleExpression (LicenseRef)" {
    const input =
        \\{
        \\  "licenseRef": "Foo",
        \\  "includes": []
        \\}
        \\
    ;

    const spdx = try json.parseFromSlice(Spdx2_3SimpleExpression, testing.allocator, input, .{});
    defer spdx.deinit();

    try testing.expectEqualStrings(spdx.value.licenseRef.licenseRef, "Foo");
    try testing.expectEqual(spdx.value.licenseRef.documentRef, null);
}

pub const Spdx2_3WithException = struct {
    conjunction: []const u8,

    license: Spdx2_3SimpleExpression,

    exceptionId: []const u8,

    exceptionIncludes: []const IncludeItem,
};

pub const Spdx2_3Conjunction = struct {
    conjunction: []const u8,
    left: Spdx2_3CompoundExpression,
    right: Spdx2_3CompoundExpression,
};

pub const Spdx2_3CompoundExpression = union(enum) {
    simple: Spdx2_3SimpleExpression,
    with_exception: Spdx2_3WithException,

    // These need to be pointers, otherwise Zig can't compile due to circular reference.
    @"and": *const Spdx2_3Conjunction,
    @"or": *const Spdx2_3Conjunction,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try switch (self.*) {
            .simple => |expr| jw.write(expr),
            .with_exception => |expr| jw.write(expr),
            .@"and" => |expr| jw.write(expr),
            .@"or" => |expr| jw.write(expr),
        };
    }

    pub fn jsonParse(
        allocator: mem.Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) json.ParseError(@TypeOf(source.*))!@This() {
        const value = try json.innerParse(json.Value, allocator, source, options);

        return @This().jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: mem.Allocator,
        value: json.Value,
        options: json.ParseOptions,
    ) json.ParseFromValueError!@This() {
        if (value != .object) {
            return error.UnexpectedToken;
        }

        if (value.object.get("conjunction")) |conjunction| {
            if (conjunction != .string) {
                return json.ParseFromValueError.InvalidEnumTag;
            }

            if (mem.eql(u8, conjunction.string, "WITH")) {
                return @This(){
                    .with_exception = try json.parseFromValueLeaky(Spdx2_3WithException, allocator, value, options),
                };
            }

            if (mem.eql(u8, conjunction.string, "AND")) {
                var expr = try allocator.create(Spdx2_3Conjunction);
                expr.* = (try json.parseFromValue(Spdx2_3Conjunction, allocator, value, options)).value;

                return @This(){ .@"and" = expr };
            }

            if (mem.eql(u8, conjunction.string, "OR")) {
                var expr = try allocator.create(Spdx2_3Conjunction);
                expr.* = (try json.parseFromValue(Spdx2_3Conjunction, allocator, value, options)).value;

                return @This(){ .@"or" = expr };
            }

            return json.ParseFromValueError.InvalidEnumTag;
        }

        return @This(){ .simple = try json.parseFromValueLeaky(Spdx2_3SimpleExpression, allocator, value, options) };
    }
};

pub const SpdxLicense = struct {
    type: []const u8,
    rawId: []const u8,
    expression: Spdx2_3CompoundExpression,
    includes: []const IncludeItem = &[0]IncludeItem{},
};

test "Parse complex SPDX format license" {
    const input =
        \\{
        \\  "type": "spdx",
        \\  "rawId": "(MIT AND DocumentRef-Foo:LicenseRef-Bar) OR (GPL-3.0-or-later WITH LLVM-exception)",
        \\  "expression": {
        \\    "conjunction": "OR",
        \\    "left": {
        \\      "conjunction": "AND",
        \\      "left": {
        \\        "id": "MIT",
        \\        "includes": [{ "text": "MIT text" }]
        \\      },
        \\      "right": {
        \\        "documentRef": "Foo",
        \\        "licenseRef": "Bar",
        \\        "includes": [{ "text": "Custom text" }]
        \\      }
        \\    },
        \\    "right": {
        \\      "conjunction": "WITH",
        \\      "license": {
        \\        "id": "GPL-3.0-or-later",
        \\        "includes": [{ "text": "GPL 3.0 text" }]
        \\      },
        \\      "exceptionId": "LLVM-exception",
        \\      "exceptionIncludes": [{ "text": "LLVM exception text" }]
        \\    }
        \\  }
        \\}
        \\
    ;

    const spdx = try json.parseFromSlice(SpdxLicense, testing.allocator, input, .{});
    defer spdx.deinit();

    try testing.expectEqualStrings(
        spdx.value.expression.@"or".left.@"and".right.simple.licenseRef.documentRef.?,
        "Foo",
    );
}

pub const ArbitraryLicense = struct {
    type: []const u8,
    includes: []const IncludeItem,
};

test "Parse ArbitraryLicense" {
    const input =
        \\{
        \\  "type": "arbitrary",
        \\  "includes": [{ "text": "foo" }, { "path": "COPYRIGHT" }]
        \\}
        \\
    ;

    const arbitrary = try json.parseFromSlice(ArbitraryLicense, testing.allocator, input, .{});
    defer arbitrary.deinit();

    try testing.expectEqualStrings(arbitrary.value.type, "arbitrary");
    try testing.expectEqualStrings(arbitrary.value.includes[0].text.text, "foo");
}

pub const License = union(enum) {
    spdx: SpdxLicense,
    arbitrary: ArbitraryLicense,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try switch (self.*) {
            .spdx => |spdx| jw.write(spdx),
            .arbitrary => |arbitrary| jw.write(arbitrary),
        };
    }

    pub fn jsonParse(
        allocator: mem.Allocator,
        source: anytype,
        options: json.ParseOptions,
    ) json.ParseError(@TypeOf(source.*))!@This() {
        const value = try json.innerParse(json.Value, allocator, source, options);

        return @This().jsonParseFromValue(allocator, value, options);
    }

    pub fn jsonParseFromValue(
        allocator: mem.Allocator,
        value: json.Value,
        options: json.ParseOptions,
    ) json.ParseFromValueError!@This() {
        return switch (value) {
            .object => |obj| {
                const t = obj.get("type") orelse return error.UnexpectedToken;
                if (t != .string) {
                    return error.UnexpectedToken;
                }

                if (mem.eql(u8, t.string, "spdx")) {
                    const spdx = try json.parseFromValueLeaky(SpdxLicense, allocator, value, options);

                    return @This(){ .spdx = spdx };
                }

                if (mem.eql(u8, t.string, "arbitrary")) {
                    const arbitrary = try json.parseFromValueLeaky(ArbitraryLicense, allocator, value, options);

                    return @This(){ .arbitrary = arbitrary };
                }

                return error.UnexpectedToken;
            },

            else => error.UnexpectedToken,
        };
    }
};

test "Parse SPDX files (simple)" {
    const input =
        \\{
        \\  "type": "spdx",
        \\  "rawId": "CC0-1.0",
        \\  "expression": {
        \\    "id": "CC0-1.0",
        \\    "includes": [{ "path": "LICENSES/CC0-1.0.txt" }]
        \\  }
        \\}
        \\
    ;

    const license = try json.parseFromSlice(License, testing.allocator, input, .{});
    defer license.deinit();

    try testing.expectEqualStrings(@tagName(license.value), "spdx");
    try testing.expectEqualStrings(license.value.spdx.expression.simple.license.id, "CC0-1.0");
}

test "Parse arbitrary files" {
    const input =
        \\{
        \\  "type": "arbitrary",
        \\  "includes": [{ "path": "LICENSE.txt" }]
        \\}
        \\
    ;

    const license = try json.parseFromSlice(License, testing.allocator, input, .{});
    defer license.deinit();

    try testing.expectEqualStrings(license.value.arbitrary.includes[0].file.path, "LICENSE.txt");
    try testing.expectEqualStrings(@tagName(license.value), "arbitrary");
}

test "Reject invalid license format" {
    const input =
        \\{
        \\  "type": "my_custom_format",
        \\  "includes": [{"text": "foo"}]
        \\}
        \\
    ;

    _ = json.parseFromSlice(License, testing.allocator, input, .{}) catch {
        return;
    };

    @panic("LicenseGroup.jsonParse did not return an error.");
}

pub const CopyrightHolder = struct {
    name: []const u8,

    email: ?[]const u8 = null,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();

        try jw.objectField("name");
        try jw.write(self.name);

        if (self.email) |email| {
            try jw.objectField("email");
            try jw.write(email);
        }

        try jw.endObject();
    }
};

test "Parse CopyrightHolder JSON" {
    const input =
        \\{
        \\  "name": "John Doe",
        \\  "email": "johndoe@example.com"
        \\}
        \\
    ;

    const holder = try json.parseFromSlice(CopyrightHolder, testing.allocator, input, .{});
    defer holder.deinit();

    try testing.expect(mem.eql(u8, holder.value.name, "John Doe"));
    try testing.expect(mem.eql(u8, holder.value.email.?, "johndoe@example.com"));
}

test "Parse CopyrightHolder JSON without email" {
    const input =
        \\{
        \\  "name": "John Doe"
        \\}
        \\
    ;

    const holder = try json.parseFromSlice(CopyrightHolder, testing.allocator, input, .{});
    defer holder.deinit();

    try testing.expectEqualStrings(holder.value.name, "John Doe");
    try testing.expect(holder.value.email == null);
}

pub const Copyright = struct {
    text: []const u8,

    year: ?u32 = null,

    holders: ?[]const CopyrightHolder = null,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();

        try jw.objectField("text");
        try jw.write(self.text);

        if (self.year) |year| {
            try jw.objectField("year");
            try jw.write(year);
        }

        if (self.holders) |holders| {
            try jw.objectField("holders");
            try jw.write(holders);
        }

        try jw.endObject();
    }
};

test "Parse full copyright object" {
    const input =
        \\{
        \\  "text": "© 2020 John Doe <johndoe@example.com>",
        \\  "year": 2020,
        \\  "holders": [{
        \\    "name": "John Doe",
        \\    "email": "johndoe@example.com"
        \\  }]
        \\}
        \\
    ;

    const copyright = try json.parseFromSlice(Copyright, testing.allocator, input, .{});
    defer copyright.deinit();

    try testing.expectEqualStrings(copyright.value.holders.?[0].name, "John Doe");
    try testing.expectEqual(copyright.value.year, 2020);
}

pub const Tpl = struct {
    files: []const FileRef,

    license: ?License = null,

    copyrights: ?[]const Copyright = null,

    metadata: ?json.ArrayHashMap(json.Value) = null,

    pub fn jsonStringify(self: *const @This(), jw: anytype) !void {
        try jw.beginObject();

        try jw.objectField("files");
        try jw.write(self.files);

        if (self.license) |license| {
            try jw.objectField("license");
            try jw.write(license);
        }

        if (self.copyrights) |copyrights| {
            try jw.objectField("copyrights");
            try jw.write(copyrights);
        }

        if (self.metadata) |metadata| {
            try jw.objectField("metadata");
            try jw.write(metadata);
        }

        try jw.endObject();
    }
};

test "Omit empty properties" {
    const input = Tpl{
        .files = &[_]FileRef{.{ .path = "foo" }},
        .license = null,
        .copyrights = null,
        .metadata = null,
    };

    const seriealized = try json.stringifyAlloc(testing.allocator, input, .{});
    defer testing.allocator.free(seriealized);

    try testing.expect(mem.indexOf(u8, seriealized, "files").? >= 0);
    try testing.expect(mem.indexOf(u8, seriealized, "license") == null);
    try testing.expect(mem.indexOf(u8, seriealized, "copyrights") == null);
    try testing.expect(mem.indexOf(u8, seriealized, "metadata") == null);
}

test "Parse TPL line JSON" {
    const input =
        \\{
        \\  "files": [{ "path": "vendor/something/libsomething.h" }],
        \\  "license": {
        \\    "type": "spdx",
        \\    "rawId": "CC0-1.0",
        \\    "expression": {
        \\      "id": "CC0-1.0",
        \\      "includes": [{ "path": "vendor/something/LICENSES/CC0-1.0.txt" }]
        \\    }
        \\  },
        \\  "copyrights": [
        \\    { "text": "Copyright 2020 John Doe" }
        \\  ],
        \\  "metadata": {
        \\    "some-namespace": {
        \\      "propertyA": "foo"
        \\    }
        \\  }
        \\}
        \\
    ;

    const tpl = try json.parseFromSlice(Tpl, testing.allocator, input, .{});
    defer tpl.deinit();

    try testing.expectEqualStrings(tpl.value.copyrights.?[0].text, "Copyright 2020 John Doe");
}

test "Serialize <-> Deserialize without problem" {
    const input = Tpl{
        .files = &[_]FileRef{.{ .path = "vendor/foo/foo.c" }},
        .license = .{
            .spdx = .{
                .type = "spdx",
                .rawId = "MIT OR LicenseRef-Foo",
                .expression = .{
                    .@"or" = &.{
                        .conjunction = "OR",
                        .left = .{
                            .simple = .{
                                .license = .{
                                    .id = "MIT",
                                    .includes = &[_]IncludeItem{
                                        IncludeItem{ .file = .{ .path = "vendor/foo/LICENSE-MIT.txt" } },
                                    },
                                },
                            },
                        },
                        .right = .{
                            .simple = .{
                                .licenseRef = .{
                                    .licenseRef = "Foo",
                                    .includes = &[_]IncludeItem{IncludeItem{ .file = .{ .path = "vendor/foo/LICENSE-Foo.txt" } }},
                                },
                            },
                        },
                    },
                },
            },
        },
        .copyrights = &[_]Copyright{.{ .text = "Copyright 2020 John Doe" }},
    };

    const serialized1 = try json.stringifyAlloc(testing.allocator, input, .{});
    defer testing.allocator.free(serialized1);

    const deserialized = try json.parseFromSlice(Tpl, testing.allocator, serialized1, .{});
    defer deserialized.deinit();

    const serialized2 = try json.stringifyAlloc(testing.allocator, deserialized.value, .{});
    defer testing.allocator.free(serialized2);

    try testing.expectEqualStrings(serialized1, serialized2);
}
