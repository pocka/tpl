// SPDX-FileCopyrightText: 2024 Shota FUJI <pockawoooh@gmail.com>
//
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

mode: Mode,
file: std.fs.File,

const Mode = enum {
    enabled,
    disabled,
    colors_only,
    styles_only,
};

pub const InitOptionsMode = union(enum) {
    auto,
    manual: Mode,
};

pub const InitOptions = struct {
    mode: InitOptionsMode = .{ .auto = {} },

    file: std.fs.File,
};

pub fn init(opts: InitOptions) @This() {
    return @This(){
        .mode = if (opts.mode == .auto) brk: {
            const tty = std.io.tty.detectConfig(opts.file);

            break :brk switch (tty) {
                .no_color => .disabled,
                .escape_codes => .enabled,
                .windows_api => .disabled,
            };
        } else opts.mode.manual,
        .file = opts.file,
    };
}

pub fn format(self: @This(), comptime tmpl: []const u8, args: anytype) !void {
    const writer = self.file.writer();

    return switch (self.mode) {
        .enabled => std.fmt.format(writer, comptime formatInternal(tmpl, .enabled), args),
        .disabled => std.fmt.format(writer, comptime formatInternal(tmpl, .disabled), args),
        .colors_only => std.fmt.format(writer, comptime formatInternal(tmpl, .colors_only), args),
        .styles_only => std.fmt.format(writer, comptime formatInternal(tmpl, .styles_only), args),
    };
}

const LexicalState = union(enum) {
    nothing,
    start_tag: []const u8,
    end_tag: []const u8,
};

const Color = enum(u8) {
    black,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    default,

    fn parse(comptime str: []const u8) Color {
        if (std.mem.eql(u8, str, "black")) {
            return .black;
        }

        if (std.mem.eql(u8, str, "red")) {
            return .red;
        }

        if (std.mem.eql(u8, str, "green")) {
            return .green;
        }

        if (std.mem.eql(u8, str, "yellow")) {
            return .yellow;
        }

        if (std.mem.eql(u8, str, "blue")) {
            return .blue;
        }

        if (std.mem.eql(u8, str, "magenta")) {
            return .magenta;
        }

        if (std.mem.eql(u8, str, "cyan")) {
            return .cyan;
        }

        if (std.mem.eql(u8, str, "white")) {
            return .white;
        }

        if (std.mem.eql(u8, str, "default")) {
            return .default;
        }

        @compileError("Unknown color: " ++ str);
    }

    fn toFgCode(self: @This()) []const u8 {
        return switch (self) {
            .black => "30",
            .red => "31",
            .green => "32",
            .yellow => "33",
            .blue => "34",
            .magenta => "35",
            .cyan => "36",
            .white => "37",
            .default => "39",
        };
    }

    fn toBgCode(self: @This()) []const u8 {
        return switch (self) {
            .black => "40",
            .red => "41",
            .green => "42",
            .yellow => "43",
            .blue => "44",
            .magenta => "45",
            .cyan => "46",
            .white => "47",
            .default => "49",
        };
    }

    fn toString(self: @This()) []const u8 {
        return @tagName(self);
    }
};

const Tag = union(enum) {
    bold,
    dim,
    italic,
    underline,
    blinking,
    inverse,
    strikethrough,
    fg: Color,
    bg: Color,

    fn parse(comptime tag: []const u8) Tag {
        if (std.mem.eql(u8, tag, "b")) {
            return .{ .bold = {} };
        }

        if (std.mem.eql(u8, tag, "dim")) {
            return .{ .dim = {} };
        }

        if (std.mem.eql(u8, tag, "i")) {
            return .{ .italic = {} };
        }

        if (std.mem.eql(u8, tag, "u")) {
            return .{ .underline = {} };
        }

        if (std.mem.eql(u8, tag, "blink")) {
            return .{ .blinking = {} };
        }

        if (std.mem.eql(u8, tag, "inverse")) {
            return .{ .inverse = {} };
        }

        if (std.mem.eql(u8, tag, "s")) {
            return .{ .strikethrough = {} };
        }

        if (std.mem.startsWith(u8, tag, "fg.")) {
            const color = Color.parse(tag[3..]);

            return .{ .fg = color };
        }

        if (std.mem.startsWith(u8, tag, "bg.")) {
            const color = Color.parse(tag[3..]);

            return .{ .bg = color };
        }

        @compileError("Unknown tag name: " ++ tag);
    }

    fn toStartSequence(self: @This()) []const u8 {
        return switch (self) {
            .bold => "\x1b[1m",
            .dim => "\x1b[2m",
            .italic => "\x1b[3m",
            .underline => "\x1b[4m",
            .blinking => "\x1b[5m",
            .inverse => "\x1b[7m",
            .strikethrough => "\x1b[9m",
            .fg => |color| "\x1b[" ++ color.toFgCode() ++ "m",
            .bg => |color| "\x1b[" ++ color.toBgCode() ++ "m",
        };
    }

    fn toString(self: @This()) []const u8 {
        return switch (self) {
            .fg => |color| "fg." ++ color.toString(),
            .bg => |color| "bg." ++ color.toString(),
            else => @tagName(self),
        };
    }

    fn isActive(self: @This(), comptime mode: Mode) bool {
        return switch (self) {
            .fg => mode == .enabled or mode == .colors_only,
            .bg => mode == .enabled or mode == .colors_only,
            else => mode == .enabled or mode == .styles_only,
        };
    }
};

// These are not technically stack though...
const ColorStack = std.SinglyLinkedList(Color);
const TagStack = std.SinglyLinkedList(Tag);

fn formatInternal(comptime tmpl: []const u8, comptime mode: Mode) []const u8 {
    @setEvalBranchQuota(10000);
    comptime var result: [tmpl.len * 4]u8 = undefined;
    comptime var result_i: usize = 0;

    comptime var lex_state: LexicalState = .nothing;

    comptime var fg_stack = ColorStack{};
    comptime var bg_stack = ColorStack{};
    comptime var tag_stack = TagStack{};

    comptime var i: usize = 0;
    inline while (i < tmpl.len) {
        const char = tmpl[i];
        i += 1;

        switch (lex_state) {
            .nothing => {
                switch (char) {
                    '<' => {
                        lex_state = .{ .start_tag = "" };
                    },
                    '\\' => {
                        switch (tmpl[i]) {
                            '<', '>', '/' => {
                                result[result_i] = tmpl[i];
                                result_i += 1;
                                i += 1;
                            },
                            else => {
                                result[result_i] = char;
                                result_i += 1;
                            },
                        }
                    },
                    else => {
                        result[result_i] = char;
                        result_i += 1;
                    },
                }
            },
            .start_tag => |tag_name| {
                switch (char) {
                    '<' => {
                        if (tag_name.len > 0) {
                            @compileError("Invalid start tag name: tag name cannot contain character '<'.");
                        }

                        lex_state = .{ .nothing = {} };
                        result[result_i] = char;
                        result_i += 1;
                    },
                    '/' => {
                        if (tag_name.len > 0) {
                            @compileError("Invalid start tag name: tag name cannot contain character '/'.");
                        }

                        lex_state = .{ .end_tag = "" };
                    },
                    '>' => {
                        if (tag_name.len == 0) {
                            @compileError("Invalid start tag name: tag name cannot be empty.");
                        }

                        lex_state = .{ .nothing = {} };

                        const tag = Tag.parse(tag_name);
                        var tag_node = TagStack.Node{ .data = tag };
                        tag_stack.prepend(&tag_node);

                        if (tag.isActive(mode)) {
                            const escape_sequence = tag.toStartSequence();

                            const copy_start = result_i;
                            result_i += escape_sequence.len;
                            std.mem.copyForwards(u8, result[copy_start..result_i], escape_sequence);

                            switch (tag) {
                                .fg => |color| {
                                    var node = ColorStack.Node{ .data = color };
                                    fg_stack.prepend(&node);
                                },
                                .bg => |color| {
                                    var node = ColorStack.Node{ .data = color };
                                    bg_stack.prepend(&node);
                                },
                                else => {},
                            }
                        }
                    },
                    else => {
                        lex_state = .{ .start_tag = tag_name ++ .{char} };
                    },
                }
            },
            .end_tag => |tag_name| {
                switch (char) {
                    '<', '/' => {
                        @compileError("Invalid end tag name: tag name cannot contain character '" ++ .{char} ++ "'.");
                    },
                    '>' => {
                        if (tag_name.len == 0) {
                            @compileError("Invalid end tag name: tag name cannot be empty.");
                        }

                        const tag = Tag.parse(tag_name);
                        const top_tag = tag_stack.popFirst();

                        if (top_tag == null) {
                            @compileError("Mismatching tag: detected end tag without start tag, tag name =" ++ tag_name);
                        }

                        if (!std.mem.eql(u8, tag.toString(), top_tag.?.data.toString())) {
                            @compileError("Mismatching tag: start tag was <" ++ top_tag.?.data.toString() ++ ">, while end tag was </" ++ tag.toString() ++ ">.");
                        }

                        if (tag.isActive(mode)) {
                            const escape_sequence = switch (tag) {
                                .bold, .dim => "\x1b[22m",
                                .italic => "\x1b[23m",
                                .underline => "\x1b[24m",
                                .blinking => "\x1b[25m",
                                .inverse => "\x1b[27m",
                                .strikethrough => "\x1b[29m",
                                .fg => fg: {
                                    _ = fg_stack.popFirst();
                                    const restore = if (fg_stack.first) |first| first.data else Color.default;

                                    break :fg (Tag{ .fg = restore }).toStartSequence();
                                },
                                .bg => bg: {
                                    _ = bg_stack.popFirst();
                                    const restore = if (bg_stack.first) |first| first.data else Color.default;

                                    break :bg (Tag{ .bg = restore }).toStartSequence();
                                },
                            };

                            const copy_start = result_i;
                            result_i += escape_sequence.len;
                            std.mem.copyForwards(u8, result[copy_start..result_i], escape_sequence);
                        }

                        lex_state = .{ .nothing = {} };
                    },
                    else => {
                        lex_state = .{ .end_tag = tag_name ++ .{char} };
                    },
                }
            },
        }
    }

    return result[0..result_i];
}
