const std = @import("std");
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;

usingnamespace @import("backend.zig");

const List = std.ArrayList(Node);
const Object = std.StringHashMap(Node);

const String = []const u8;

const ScalarType = enum {
    String,
    Integer,
    Float,
    Bool,
};

const Scalar = union(ScalarType) {
    String: String,
    Integer: u64,
    Float: f64,
    Bool: bool,

    pub fn fromString(string: String, typeHint: ?ScalarType) LoaderError!Scalar {
        if (typeHint) |stype| {
            switch (stype) {
                .Integer => {
                    if (std.fmt.parseInt(u64, string, 0)) |int| {
                        return Scalar{ .Integer = int };
                    } else |_| {
                        return LoaderError.UnexpectedType;
                    }
                },
                .Float => {
                    if (std.fmt.parseFloat(f64, string)) |float| {
                        return Scalar{ .Float = float };
                    } else |_| {
                        return LoaderError.UnexpectedType;
                    }
                },
                .Bool => {
                    if (std.mem.eql(u8, "true", string)) {
                        return Scalar{ .Bool = true };
                    } else if (std.mem.eql(u8, "false", string)) {
                        return Scalar{ .Bool = false };
                    } else {
                        return LoaderError.UnexpectedType;
                    }
                },
                else => {
                    return Scalar{ .String = string };
                },
            }
        } else {
            return Scalar{ .String = string };
        }
    }
};

const Node = union(enum) {
    Scalar: Scalar,
    List: List,
    Object: Object,
};

const Command = enum {
    Mapping,
    Sequencing,
};
const State = union(Command) {
    Mapping: struct {
        object: Object,
        name: ?String,
    },
    Sequencing: List,

    pub fn addNode(self: *@This(), node: Node) LoaderError!void {
        switch (self.*) {
            .Mapping => |*mapping| {
                if (mapping.name) |name| {
                    try mapping.object.put(name, node);
                    mapping.name = null;
                } else panic("Expected key but there was none", .{});
            },
            .Sequencing => |*seq| {
                try seq.append(node);
            },
        }
    }
};

/// A basic YAML loader. If you just want to parse a string instead, see `stringLoader`.
pub fn Loader(comptime Reader: type) type {
    const Parser = parser.Parser(Reader);
    return struct {
        inner: Parser,
        allocator: *Allocator,

        const Self = @This();

        fn init(allocator: *Allocator, reader: Reader) ParserError!Self {
            return Self{ .allocator = allocator, .inner = try Parser.init(allocator, reader) };
        }
        fn parse(self: *Self, command: ?Command) YamlError!Node {
            var state: ?State = if (command) |cmd| switch (cmd) {
                .Mapping => State{ .Mapping = .{ .object = Object.init(self.allocator), .name = null } },
                .Sequencing => State{ .Sequencing = List.init(self.allocator) },
            } else null;
            var evt: Event = undefined;
            while (true) {
                evt = try self.inner.nextEvent();
                switch (evt.etype) {
                    .MappingStartEvent => {
                        const obj = try self.parse(.Mapping);
                        if (state) |*st| {
                            try st.addNode(obj);
                        } else return obj;
                    },
                    .MappingEndEvent => {
                        if (state) |st| switch (st) {
                            .Mapping => |map| {
                                if (map.name) |name| panic("Mapping stopped before key \'{s}\' could receive a value", .{name});
                                return Node{ .Object = map.object };
                            },
                            else => |cur| panic("Current state is '{s}', expected '{s}'", .{ @tagName(cur), @tagName(.Mapping) }),
                        } else panic("Impossible to end mapping; nothing is supposed to be happening", .{});
                    },
                    .SequenceStartEvent => {
                        const seq = try self.parse(.Sequencing);
                        if (state) |*st| {
                            try st.addNode(seq);
                        } else return seq;
                    },
                    .ScalarEvent => |scalar| {
                        if (state) |*st| {
                            // If we're currently mapping and there is no name yet,
                            //  store this scalar to be used as a key.
                            switch (st.*) {
                                .Mapping => |*map| if (map.name == null) {
                                    map.name = scalar.value;
                                    continue;
                                },
                                else => {},
                            }
                            try st.addNode(.{ .Scalar = try Scalar.fromString(scalar.value, null) });
                        } else return Node{ .Scalar = try Scalar.fromString(scalar.value, null) };
                    },
                    .SequenceEndEvent => {
                        if (state) |st| {
                            switch (st) {
                                .Sequencing => |seq| return Node{ .List = seq },
                                .Mapping => panic("Received sequence stop event while mapping", .{}),
                            }
                        } else panic("Impossible to end sequencing; nothing is supposed to be happening", .{});
                    },
                    else => {},
                }
            }
            unreachable;
        }
        // This function returns the intermediate representation of YAML.
        // This is useful when you don't know the data beforehand.
        pub fn parseDynamic(self: *Self) YamlError!Node {
            return self.parse(null);
        }
        pub fn deinit(self: Self) void {
            self.inner.deinit();
        }
    };
}

pub const StringLoader = Loader(*std.io.FixedBufferStream(String).Reader);
pub fn stringLoader(allocator: *Allocator, string: String) !StringLoader {
    var buf = std.io.fixedBufferStream(string);
    return StringLoader.init(allocator, &buf.reader());
}

test "Load String" {
    const string = "name: Bob\nage: 100";
    var buf = std.io.fixedBufferStream(string);
    var reader = buf.reader(); 
    var stringloader = try StringLoader.init(std.testing.allocator, &reader);
    // defer stringloader.deinit();
    const result = try stringloader.parseDynamic();
    const name = result.Object.get("name").?.Scalar.String;
    const age = result.Object.get("age").?.Scalar.String;
    try std.testing.expectEqualStrings("Bob", name);
    try std.testing.expectEqualStrings("100", age);
}
