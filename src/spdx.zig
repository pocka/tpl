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

pub const ParseError = error{
    LessThanMinimumCharacterLength,
    IllegalCharacter,
    MissingColonAfterDocumentRef,
    MissingLicenseRefPrefix,
    InvalidSimpleExpression,
    UnknownLicenseId,
    UnknownLicenseExceptionId,
    UnexpectedOperatorForWithExpression,
    UnexpectedToken,
    EndOfInput,
} || mem.Allocator.Error;

const Tokenizer = struct {
    source: []const u8,
    cursor: usize,

    fn init(source: []const u8) Tokenizer {
        return @This(){
            .source = source,
            .cursor = 0,
        };
    }

    fn peek(self: *@This()) ?[]const u8 {
        var found_token: bool = false;
        var start_index: usize = self.cursor;

        for (self.source[self.cursor..], self.cursor..) |char, i| {
            switch (char) {
                ' ' => {
                    if (!found_token) {
                        start_index = i + 1;
                        self.cursor = start_index;
                        continue;
                    }

                    return self.source[start_index..i];
                },
                '(', ')' => {
                    if (found_token) {
                        return self.source[start_index..i];
                    }

                    return self.source[start_index .. i + 1];
                },
                else => {
                    found_token = true;
                },
            }
        }

        if (!found_token) {
            return null;
        }

        return self.source[start_index..self.source.len];
    }

    fn next(self: *@This()) ?[]const u8 {
        const result = self.peek();

        if (result) |found| {
            self.cursor += found.len;
        } else {
            self.cursor = self.source.len;
        }

        return result;
    }
};

test "Tokenize inputs" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("foo");
        try testing.expectEqualSlices(u8, "foo", t.next().?);
    }

    {
        var t = Tokenizer.init("");
        try testing.expect(t.next() == null);
    }

    {
        var t = Tokenizer.init("      ");
        try testing.expect(t.next() == null);
    }

    {
        var t = Tokenizer.init("  foo bar   baz ");
        try testing.expectEqualSlices(u8, "foo", t.next().?);
        try testing.expectEqualSlices(u8, "bar", t.next().?);
        try testing.expectEqualSlices(u8, "baz", t.next().?);
    }

    {
        var t = Tokenizer.init("  foo bar   baz ");
        try testing.expectEqualSlices(u8, "foo", t.peek().?);
        try testing.expectEqualSlices(u8, "foo", t.peek().?);
        try testing.expectEqualSlices(u8, "foo", t.peek().?);
    }

    {
        var t = Tokenizer.init("(MIT OR Apache-2.0) AND (GPL-3.0-only WITH LLVM-exception)");
        try testing.expectEqualSlices(u8, "(", t.next().?);
        try testing.expectEqualSlices(u8, "MIT", t.next().?);
        try testing.expectEqualSlices(u8, "OR", t.next().?);
        try testing.expectEqualSlices(u8, "Apache-2.0", t.next().?);
        try testing.expectEqualSlices(u8, ")", t.next().?);
        try testing.expectEqualSlices(u8, "AND", t.next().?);
        try testing.expectEqualSlices(u8, "(", t.next().?);
        try testing.expectEqualSlices(u8, "GPL-3.0-only", t.next().?);
        try testing.expectEqualSlices(u8, "WITH", t.next().?);
        try testing.expectEqualSlices(u8, "LLVM-exception", t.next().?);
        try testing.expectEqualSlices(u8, ")", t.next().?);
    }
}

fn TryParser(comptime T: type) type {
    return struct {
        value: T,

        fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!T {
            const start_cursor = t.cursor;
            errdefer {
                t.cursor = start_cursor;
            }

            return T.parse(allocator, t);
        }
    };
}

test "TryParse should reset cursor on error" {
    const testing = std.testing;

    var t = Tokenizer.init(" ( ? ) ");
    try testing.expectError(ParseError.IllegalCharacter, TryParser(IdString).parse(testing.allocator, &t));
    try testing.expectEqualSlices(u8, "(", t.peek().?);
    try testing.expectError(ParseError.IllegalCharacter, TryParser(IdString).parse(testing.allocator, &t));
    try testing.expectEqualSlices(u8, "(", t.peek().?);
}

pub const IdString = struct {
    value: []const u8,

    fn parse(_: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        if (t.next()) |text| {
            return @This().parseText(text);
        }

        return ParseError.EndOfInput;
    }

    fn parseText(text: []const u8) ParseError!@This() {
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

    {
        var t = Tokenizer.init("foobar");
        const ret = try IdString.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "foobar", ret.value);
    }

    {
        var t = Tokenizer.init("foobar123");
        const ret = try IdString.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "foobar123", ret.value);
    }

    {
        var t = Tokenizer.init("foo-bar");
        const ret = try IdString.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "foo-bar", ret.value);
    }

    {
        var t = Tokenizer.init("-foobar-");
        const ret = try IdString.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "-foobar-", ret.value);
    }

    {
        var t = Tokenizer.init(".foo.bar");
        const ret = try IdString.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, ".foo.bar", ret.value);
    }

    {
        var t = Tokenizer.init("..-.0---0---0-...0.-0.-.");
        const ret = try IdString.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "..-.0---0---0-...0.-0.-.", ret.value);
    }
}

test "Reject invalid idstring" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("");
        try testing.expectError(ParseError.EndOfInput, IdString.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("foo_bar");
        try testing.expectError(ParseError.IllegalCharacter, IdString.parse(testing.allocator, &t));
    }
}

const document_ref_prefix = "DocumentRef-";
const license_ref_prefix = "LicenseRef-";

pub const LicenseRef = struct {
    document_ref: ?IdString = null,
    license_ref: IdString,

    fn parse(_: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        if (t.next()) |text| {
            return @This().parseText(text);
        }

        return ParseError.EndOfInput;
    }

    fn parseText(text: []const u8) ParseError!@This() {
        var cursor: usize = 0;

        var document_ref: ?IdString = null;
        if (mem.startsWith(u8, text, document_ref_prefix)) {
            cursor += document_ref_prefix.len;
            const colon_pos = mem.indexOfScalar(u8, text[cursor..], ':');
            if (colon_pos == null) {
                return ParseError.MissingColonAfterDocumentRef;
            }

            document_ref = try IdString.parseText(text[cursor .. cursor + colon_pos.?]);
            // Place cursor after the position of the colon, thus plus one.
            cursor += colon_pos.? + 1;
        }

        if (!mem.startsWith(u8, text[cursor..], license_ref_prefix)) {
            return ParseError.MissingLicenseRefPrefix;
        }

        cursor += license_ref_prefix.len;
        const license_ref = try IdString.parseText(text[cursor..]);

        return @This(){
            .document_ref = document_ref,
            .license_ref = license_ref,
        };
    }
};

test "Parse valid license-ref" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("LicenseRef-foobar");
        const result = try LicenseRef.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "foobar", result.license_ref.value);
    }

    {
        var t = Tokenizer.init("LicenseRef-1");
        const result = try LicenseRef.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "1", result.license_ref.value);
    }

    {
        var t = Tokenizer.init("LicenseRef---");
        const result = try LicenseRef.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "--", result.license_ref.value);
    }

    {
        var t = Tokenizer.init("DocumentRef-foo:LicenseRef-foo");
        const result = try LicenseRef.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "foo", result.license_ref.value);
        try testing.expectEqualSlices(u8, "foo", result.document_ref.?.value);
    }
}

test "Reject invalid license-ref" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("DocumentRef-foo");
        try testing.expectError(ParseError.MissingColonAfterDocumentRef, LicenseRef.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("DocumentRef-foo:");
        try testing.expectError(ParseError.MissingLicenseRefPrefix, LicenseRef.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("foo");
        try testing.expectError(ParseError.MissingLicenseRefPrefix, LicenseRef.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("LicenseRef-");
        try testing.expectError(ParseError.LessThanMinimumCharacterLength, LicenseRef.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("LicenseRef-foo:LicenseRef-foo");
        try testing.expectError(ParseError.IllegalCharacter, LicenseRef.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("DocumentRef-foo:foo");
        try testing.expectError(ParseError.MissingLicenseRefPrefix, LicenseRef.parse(testing.allocator, &t));
    }
}

pub const LicenseId = struct {
    id: []const u8,

    fn parse(_: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        if (t.next()) |text| {
            return @This().parseText(text);
        }

        return ParseError.EndOfInput;
    }

    fn parseText(text: []const u8) ParseError!@This() {
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
        var t = Tokenizer.init("MIT");
        const result = try LicenseId.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "MIT", result.id);
    }

    {
        var t = Tokenizer.init("mit");
        const result = try LicenseId.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "MIT", result.id);
    }

    {
        var t = Tokenizer.init("gpl-3.0-or-LaTER");
        const result = try LicenseId.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "GPL-3.0-or-later", result.id);
    }
}

test "Reject invalid license-id" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("LicenseRef-foo");
        try testing.expectError(ParseError.UnknownLicenseId, LicenseId.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("Mit-with-my-super-lines");
        try testing.expectError(ParseError.UnknownLicenseId, LicenseId.parse(testing.allocator, &t));
    }
}

pub const LicenseExceptionId = struct {
    id: []const u8,

    fn parse(_: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        if (t.next()) |text| {
            return @This().parseText(text);
        }

        return ParseError.EndOfInput;
    }

    fn parseText(text: []const u8) ParseError!@This() {
        inline for (spdx.exceptionIdList) |id| {
            if (std.ascii.eqlIgnoreCase(id, text)) {
                return @This(){ .id = id };
            }
        }

        return ParseError.UnknownLicenseExceptionId;
    }
};

test "Parse valid license-exception-id" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("LLVM-exception");
        const result = try LicenseExceptionId.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "LLVM-exception", result.id);
    }

    {
        var t = Tokenizer.init("llvm-eXceptiOn");
        const result = try LicenseExceptionId.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "LLVM-exception", result.id);
    }
}

test "Reject invalid license-exception-id" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("my-awesome-programs-super-exception");
        try testing.expectError(ParseError.UnknownLicenseExceptionId, LicenseExceptionId.parse(testing.allocator, &t));
    }
}

pub const SimpleExpression = union(enum) {
    license_id: LicenseId,
    license_id_and_plus: LicenseId,
    license_ref: LicenseRef,

    fn parse(_: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        if (t.next()) |text| {
            return @This().parseText(text);
        }

        return ParseError.EndOfInput;
    }

    fn parseText(text: []const u8) ParseError!@This() {
        if (LicenseId.parseText(text)) |ok| {
            return @This(){ .license_id = ok };
        } else |_| {}

        if (mem.endsWith(u8, text, "+")) {
            if (LicenseId.parseText(text[0 .. text.len - 1])) |ok| {
                return @This(){ .license_id_and_plus = ok };
            } else |_| {}
        }

        if (LicenseRef.parseText(text)) |ok| {
            return @This(){ .license_ref = ok };
        } else |_| {}

        // TODO: Revisit error handling. Because SimpleExpression only uses InvalidSimpleExpression,
        //       errors returned by LicenseId and LicenseRef (and downstream, too) are essentialy meaningless.
        return ParseError.InvalidSimpleExpression;
    }
};

test "Parse valid simple-expression" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("Apache-2.0");
        const result = try SimpleExpression.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "Apache-2.0", result.license_id.id);
    }

    {
        var t = Tokenizer.init("CDDL-1.0+");
        const result = try SimpleExpression.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "CDDL-1.0", result.license_id_and_plus.id);
    }

    {
        var t = Tokenizer.init("DocumentRef-Foo:LicenseRef-Bar");
        const result = try SimpleExpression.parse(testing.allocator, &t);
        try testing.expectEqualSlices(u8, "Foo", result.license_ref.document_ref.?.value);
        try testing.expectEqualSlices(u8, "Bar", result.license_ref.license_ref.value);
    }
}

test "Reject invalid simple-expression" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("my-awesome-license");
        try testing.expectError(ParseError.InvalidSimpleExpression, SimpleExpression.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("MIT+Apache-2.0");
        try testing.expectError(ParseError.InvalidSimpleExpression, SimpleExpression.parse(testing.allocator, &t));
    }

    {
        var t = Tokenizer.init("LicenseRef-Foo+");
        try testing.expectError(ParseError.InvalidSimpleExpression, SimpleExpression.parse(testing.allocator, &t));
    }
}

fn Literal(comptime literal: []const u8) type {
    return struct {
        literal: []const u8,

        fn parse(_: mem.Allocator, t: *Tokenizer) ParseError!@This() {
            if (t.next()) |text| {
                if (mem.eql(u8, literal, text)) {
                    return @This(){ .literal = literal };
                }

                return ParseError.UnexpectedToken;
            }

            return ParseError.EndOfInput;
        }
    };
}

fn Seq(comptime T1: type, comptime T2: type) type {
    return struct {
        t1: T1,
        t2: T2,

        pub fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
            const t1 = try T1.parse(allocator, t);
            const t2 = try T2.parse(allocator, t);

            return @This(){
                .t1 = t1,
                .t2 = t2,
            };
        }
    };
}

fn Seq3(comptime T1: type, comptime T2: type, comptime T3: type) type {
    return struct {
        t1: T1,
        t2: T2,
        t3: T3,

        fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
            const t1 = try T1.parse(allocator, t);
            const t2 = try T2.parse(allocator, t);
            const t3 = try T3.parse(allocator, t);

            return @This(){
                .t1 = t1,
                .t2 = t2,
                .t3 = t3,
            };
        }
    };
}

pub const SimpleWithExceptionExpression = struct {
    simple_expression: SimpleExpression,
    license_exception_id: LicenseExceptionId,

    const S = Seq3(SimpleExpression, Literal("WITH"), LicenseExceptionId);

    fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        const ret = try S.parse(allocator, t);

        return @This(){
            .simple_expression = ret.t1,
            .license_exception_id = ret.t3,
        };
    }
};

pub const ConjunctionExpression = struct {
    allocator: mem.Allocator,
    lhs: *const CompoundExpression,
    rhs: *const CompoundExpression,

    fn deinit(self: *const @This()) void {
        self.lhs.deinit();
        self.rhs.deinit();

        self.allocator.destroy(self.lhs);
        self.allocator.destroy(self.rhs);
    }
};

fn OneOf(comptime T1: type, comptime T2: type) type {
    const S1 = TryParser(T1);
    const S2 = TryParser(T2);

    return union(enum) {
        t1: T1,
        t2: T2,

        fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
            if (S1.parse(allocator, t)) |t1| {
                return @This(){ .t1 = t1 };
            } else |_| {}

            if (S2.parse(allocator, t)) |t2| {
                return @This(){ .t2 = t2 };
            } else |err| {
                return err;
            }
        }
    };
}

fn OneOf4(comptime T1: type, comptime T2: type, comptime T3: type, comptime T4: type) type {
    const S1 = TryParser(T1);
    const S2 = TryParser(T2);
    const S3 = TryParser(T3);
    const S4 = TryParser(T4);

    return union(enum) {
        t1: T1,
        t2: T2,
        t3: T3,
        t4: T4,

        fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
            if (S1.parse(allocator, t)) |t1| {
                return @This(){ .t1 = t1 };
            } else |_| {}

            if (S2.parse(allocator, t)) |t2| {
                return @This(){ .t2 = t2 };
            } else |_| {}

            if (S3.parse(allocator, t)) |t3| {
                return @This(){ .t3 = t3 };
            } else |_| {}

            if (S4.parse(allocator, t)) |t4| {
                return @This(){ .t4 = t4 };
            } else |err| {
                return err;
            }
        }
    };
}

fn Maybe(comptime T: type) type {
    const S = TryParser(T);

    return union(enum) {
        some: T,
        none,

        fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
            if (S.parse(allocator, t)) |ok| {
                return @This(){ .some = ok };
            } else |_| {
                return @This(){ .none = {} };
            }
        }
    };
}

pub const CompoundExpression = union(enum) {
    simple: SimpleExpression,
    with: SimpleWithExceptionExpression,
    @"and": ConjunctionExpression,
    @"or": ConjunctionExpression,

    const Simplish = OneOf(OneOf(SimpleWithExceptionExpression, SimpleExpression), Seq3(Literal("("), CompoundExpression, Literal(")")));
    const OrTarget = Seq(Simplish, Maybe(Seq(Literal("AND"), Simplish)));
    const Expression = Seq(OrTarget, Maybe(Seq(Literal("OR"), OrTarget)));

    fn fromSimplish(ast: Simplish) @This() {
        switch (ast) {
            // simple-expression / simple-expression "WITH" license-exception-id
            .t1 => |simple_or_with| {
                return switch (simple_or_with) {
                    // simple-expression "WITH" license-exception-id
                    .t1 => |with| @This(){ .with = with },
                    // simple-expression
                    .t2 => |simple| @This(){ .simple = simple },
                };
            },
            // "(" compound-expression ")"
            .t2 => |seq| {
                return seq.t2;
            },
        }
    }

    fn fromOrTarget(ast: OrTarget, allocator: mem.Allocator) ParseError!@This() {
        switch (ast.t2) {
            // compound-expression "AND" compound-expression
            .some => |seq| {
                var lhs = try allocator.create(CompoundExpression);
                lhs.* = @This().fromSimplish(ast.t1);

                var rhs = try allocator.create(CompoundExpression);
                rhs.* = @This().fromSimplish(seq.t2);

                return @This(){
                    .@"and" = .{
                        .allocator = allocator,
                        .lhs = lhs,
                        .rhs = rhs,
                    },
                };
            },
            .none => {
                return @This().fromSimplish(ast.t1);
            },
        }
    }

    fn fromExpression(ast: Expression, allocator: mem.Allocator) ParseError!@This() {
        switch (ast.t2) {
            // compound-expression "OR" compound-expression
            .some => |seq| {
                var lhs = try allocator.create(CompoundExpression);
                lhs.* = try @This().fromOrTarget(ast.t1, allocator);

                var rhs = try allocator.create(CompoundExpression);
                rhs.* = try @This().fromOrTarget(seq.t2, allocator);

                return @This(){
                    .@"or" = .{
                        .allocator = allocator,
                        .lhs = lhs,
                        .rhs = rhs,
                    },
                };
            },
            .none => {
                return @This().fromOrTarget(ast.t1, allocator);
            },
        }
    }

    fn parse(allocator: mem.Allocator, t: *Tokenizer) ParseError!@This() {
        const ast = try Expression.parse(allocator, t);

        return @This().fromExpression(ast, allocator);
    }

    pub fn deinit(self: *const @This()) void {
        switch (self.*) {
            .simple => {},
            .with => {},
            .@"and" => |ast| {
                ast.deinit();
            },
            .@"or" => |ast| {
                ast.deinit();
            },
        }
    }
};

test "Parse valid compound-expression" {
    const testing = std.testing;

    {
        var t = Tokenizer.init("Apache-2.0");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "Apache-2.0", result.simple.license_id.id);
    }

    {
        var t = Tokenizer.init("GPL-3.0-only WITH LLVM-exception");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "GPL-3.0-only", result.with.simple_expression.license_id.id);
        try testing.expectEqualSlices(u8, "LLVM-exception", result.with.license_exception_id.id);
    }

    {
        var t = Tokenizer.init("      DocumentRef-Foo:LicenseRef-Bar       WITH      LLVM-exception      ");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "Foo", result.with.simple_expression.license_ref.document_ref.?.value);
        try testing.expectEqualSlices(u8, "Bar", result.with.simple_expression.license_ref.license_ref.value);
        try testing.expectEqualSlices(u8, "LLVM-exception", result.with.license_exception_id.id);
    }

    {
        var t = Tokenizer.init(" ( MIT ) ");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "MIT", result.simple.license_id.id);
    }

    {
        var t = Tokenizer.init("LGPL-2.1-only OR BSD-3-Clause AND MIT");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "LGPL-2.1-only", result.@"or".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "BSD-3-Clause", result.@"or".rhs.@"and".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "MIT", result.@"or".rhs.@"and".rhs.simple.license_id.id);
    }

    {
        // Operator precedence
        var t = Tokenizer.init("LGPL-2.1-only AND BSD-3-Clause OR MIT");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "LGPL-2.1-only", result.@"or".lhs.@"and".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "BSD-3-Clause", result.@"or".lhs.@"and".rhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "MIT", result.@"or".rhs.simple.license_id.id);
    }

    {
        var t = Tokenizer.init("MIT AND (LGPL-2.1-or-later OR BSD-3-Clause)");
        const result = try CompoundExpression.parse(testing.allocator, &t);
        defer result.deinit();
        try testing.expectEqualSlices(u8, "MIT", result.@"and".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "LGPL-2.1-or-later", result.@"and".rhs.@"or".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "BSD-3-Clause", result.@"and".rhs.@"or".rhs.simple.license_id.id);
    }
}

/// Parse SPDX expression string and returns AST.
/// Caller is responsible for invoking `.deinit()` function on the returned AST.
///
/// Part of the returned data, such as idstring of "LicenseRef-" and "DocumentRef-" references
/// the source string (`text` argument), thus freeing the source string may lead to invalid memory access.
/// Use `Spdx.init()` function if you are not under control of the text lifetime.
pub fn parse(allocator: mem.Allocator, text: []const u8) ParseError!CompoundExpression {
    var t = Tokenizer.init(text);

    const expr = try CompoundExpression.parse(allocator, &t);

    if (t.peek()) |_| {
        return ParseError.UnexpectedToken;
    }

    return expr;
}

test "Parse valid SPDX expression" {
    const testing = std.testing;

    {
        const expr = try parse(testing.allocator, "MIT AND (LGPL-2.1-or-later OR BSD-3-Clause)");
        defer expr.deinit();

        try testing.expectEqualSlices(u8, "MIT", expr.@"and".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "LGPL-2.1-or-later", expr.@"and".rhs.@"or".lhs.simple.license_id.id);
        try testing.expectEqualSlices(u8, "BSD-3-Clause", expr.@"and".rhs.@"or".rhs.simple.license_id.id);
    }

    {
        const expr = try parse(testing.allocator, "((((((((((((((((((((MIT))))))))))))))))))))");
        defer expr.deinit();

        try testing.expectEqualSlices(u8, "MIT", expr.simple.license_id.id);
    }
}

test "Reject invalid SPDX expression" {
    const testing = std.testing;

    try testing.expectError(ParseError.UnexpectedToken, parse(testing.allocator, "MIT Apache-2.0"));
}

/// SPDX parsing result.
pub const Spdx = struct {
    allocator: mem.Allocator,
    source: []const u8,
    ast: *const CompoundExpression,

    /// Build an AST from SPDX expression string.
    /// This function copies `text` in its own memory: freeing the source string
    /// after `.init()` call is safe.
    pub fn init(allocator: mem.Allocator, text: []const u8) ParseError!@This() {
        var source = try allocator.alloc(u8, text.len);
        @memcpy(source, text);
        errdefer allocator.free(source);

        var expr = try allocator.create(CompoundExpression);
        errdefer allocator.destroy(expr);
        expr.* = try parse(allocator, source);

        return @This(){
            .allocator = allocator,
            .source = source,
            .ast = expr,
        };
    }

    /// Frees source string and AST structs.
    pub fn deinit(self: *const @This()) void {
        self.ast.deinit();
        self.allocator.destroy(self.ast);
        self.allocator.free(self.source);
    }
};

test "Spdx.parse() clones the source text" {
    const testing = std.testing;

    const TEXT = "DocumentRef-Foo:LicenseRef-Bar WITH LLVM-exception";

    var text = try testing.allocator.alloc(u8, TEXT.len);
    @memcpy(text, TEXT);

    const ret = try Spdx.init(testing.allocator, text);
    defer ret.deinit();

    testing.allocator.free(text);

    try testing.expectEqualSlices(u8, "Foo", ret.ast.with.simple_expression.license_ref.document_ref.?.value);
    try testing.expectEqualSlices(u8, "Bar", ret.ast.with.simple_expression.license_ref.license_ref.value);
    try testing.expectEqualSlices(u8, "LLVM-exception", ret.ast.with.license_exception_id.id);
}
