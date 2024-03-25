// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0
//
// # References
//
// ## Expressions grammar
// https://spdx.github.io/spdx-spec/v2.3/SPDX-license-expressions/

const std = @import("std");
const mem = std.mem;

const spdx = @import("spdx");

const ParseError = error{
    LessThanMinimumCharacterLength,
    IllegalCharacter,
    MissingColonAfterDocumentRef,
    MissingLicenseRefPrefix,
    UnknownLicenseId,
};

pub const IdString = struct {
    value: []const u8,

    pub fn parse(text: []const u8) ParseError!@This() {
        if (text.len == 0) {
            return ParseError.LessThanMinimumCharacterLength;
        }

        for (text) |char| {
            switch (char) {
                'a'...'z', 'A'...'Z', '0', '1'...'9', '-', '.' => {},
                else => {
                    return ParseError.IllegalCharacter;
                },
            }
        }

        return @This(){ .value = text };
    }
};

test "Parse valid idstring" {
    const testing = std.testing;

    try testing.expectEqualSlices(u8, "foobar", (try IdString.parse("foobar")).value);
    try testing.expectEqualSlices(u8, "foobar123", (try IdString.parse("foobar123")).value);
    try testing.expectEqualSlices(u8, "foo-bar", (try IdString.parse("foo-bar")).value);
    try testing.expectEqualSlices(u8, "-foobar-", (try IdString.parse("-foobar-")).value);
    try testing.expectEqualSlices(u8, ".foo.bar", (try IdString.parse(".foo.bar")).value);
    try testing.expectEqualSlices(u8, "..-.0---0---0-...0.-0.-.", (try IdString.parse("..-.0---0---0-...0.-0.-.")).value);
}

test "Reject invalid idstring" {
    const testing = std.testing;

    try testing.expectError(ParseError.LessThanMinimumCharacterLength, IdString.parse(""));
    try testing.expectError(ParseError.IllegalCharacter, IdString.parse(" "));
    try testing.expectError(ParseError.IllegalCharacter, IdString.parse("foo_bar"));
}

const document_ref_prefix = "DocumentRef-";
const license_ref_prefix = "LicenseRef-";

pub const LicenseRef = struct {
    document_ref: ?IdString = null,
    license_ref: IdString,

    pub fn parse(text: []const u8) ParseError!@This() {
        var cursor: usize = 0;

        var document_ref: ?IdString = null;
        if (mem.startsWith(u8, text, document_ref_prefix)) {
            cursor += document_ref_prefix.len;
            const colon_pos = mem.indexOfScalar(u8, text[cursor..], ':');
            if (colon_pos == null) {
                return ParseError.MissingColonAfterDocumentRef;
            }

            document_ref = try IdString.parse(text[cursor .. cursor + colon_pos.?]);
            // Place cursor after the position of the colon, thus plus one.
            cursor += colon_pos.? + 1;
        }

        if (!mem.startsWith(u8, text[cursor..], license_ref_prefix)) {
            return ParseError.MissingLicenseRefPrefix;
        }

        cursor += license_ref_prefix.len;
        const license_ref = try IdString.parse(text[cursor..]);

        return @This(){
            .document_ref = document_ref,
            .license_ref = license_ref,
        };
    }
};

test "Parse valid license-ref" {
    const testing = std.testing;

    {
        const result = try LicenseRef.parse("LicenseRef-foobar");
        try testing.expectEqualSlices(u8, "foobar", result.license_ref.value);
    }

    {
        const result = try LicenseRef.parse("LicenseRef-1");
        try testing.expectEqualSlices(u8, "1", result.license_ref.value);
    }

    {
        const result = try LicenseRef.parse("LicenseRef---");
        try testing.expectEqualSlices(u8, "--", result.license_ref.value);
    }

    {
        const result = try LicenseRef.parse("DocumentRef-foo:LicenseRef-foo");
        try testing.expectEqualSlices(u8, "foo", result.license_ref.value);
        try testing.expectEqualSlices(u8, "foo", result.document_ref.?.value);
    }
}

test "Reject invalid license-ref" {
    const testing = std.testing;

    try testing.expectError(ParseError.MissingColonAfterDocumentRef, LicenseRef.parse("DocumentRef-foo"));
    try testing.expectError(ParseError.MissingLicenseRefPrefix, LicenseRef.parse("DocumentRef-foo:"));
    try testing.expectError(ParseError.MissingLicenseRefPrefix, LicenseRef.parse("foo"));
    try testing.expectError(ParseError.LessThanMinimumCharacterLength, LicenseRef.parse("LicenseRef-"));
    try testing.expectError(ParseError.IllegalCharacter, LicenseRef.parse("LicenseRef-foo:LicenseRef-foo"));
    try testing.expectError(ParseError.MissingLicenseRefPrefix, LicenseRef.parse("DocumentRef-foo:foo"));
}

pub const LicenseId = struct {
    id: []const u8,

    pub fn parse(text: []const u8) ParseError!@This() {
        inline for (spdx.idList) |id| {
            if (std.ascii.eqlIgnoreCase(id, text)) {
                return @This(){ .id = id };
            }
        }

        return ParseError.UnknownLicenseId;
    }
};

test "Parse valid license-id" {
    const testing = std.testing;

    {
        const result = try LicenseId.parse("MIT");
        try testing.expectEqualSlices(u8, "MIT", result.id);
    }

    {
        const result = try LicenseId.parse("mit");
        try testing.expectEqualSlices(u8, "MIT", result.id);
    }

    {
        const result = try LicenseId.parse("gpl-3.0-or-LaTER");
        try testing.expectEqualSlices(u8, "GPL-3.0-or-later", result.id);
    }
}

test "Reject invalid license-id" {
    const testing = std.testing;

    try testing.expectError(ParseError.UnknownLicenseId, LicenseId.parse("LicenseRef-foo"));
    try testing.expectError(ParseError.UnknownLicenseId, LicenseId.parse("Mit-with-my-super-lines"));
}
