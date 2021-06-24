const std = @import("std");
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const MemErr = Allocator.Error;

usingnamespace if (!@import("build_options").customParser)
    @import("backends/c.zig")
else
    @import("backends/custom.zig");

pub const LoaderError = @import("backends/error.zig").LoaderError;

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
                        return .{ .Integer = int };
                    } else {
                        return LoaderError.TypeError;
                    }
                },
                .Float => {
                    if (std.fmt.parseFloat(f64, string)) |float| {
                        return .{ .Float = float };
                    } else {
                        return LoaderError.TypeError;
                    }
                },
                .Bool => {
                    if (std.mem.eql(u8, "true", string)) {
                        return .{ .Bool = true };
                    } else if (std.mem.eql(u8, "false", string)) {
                        return .{ .Bool = false };
                    } else {
                        return LoaderError.TypeError;
                    }
                },
                else => {
                    return .{ .String = string };
                },
            }
        } else {
            return .{ .String = string };
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
pub const Encoding = enum { Utf8, Utf16LittleEndian, Utf16BigEndian, Any };
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

pub const EventType = union(enum) {
    NoEvent: void,
    StreamStartEvent: Encoding,
    StreamEndEvent: void,
    DocumentStartEvent: struct {
        version: ?struct {
            major: u32,
            minor: u32,
        },
    },
    DocumentEndEvent: void,
    ScalarEvent: struct { value: String },
    SequenceStartEvent: void,
    SequenceEndEvent: void,
    MappingStartEvent: void,
    MappingEndEvent: void,
};
pub const Event = struct {
    etype: EventType,
    start: Mark,
    end: Mark,

    const Self = @This();

    fn fromRaw(raw: *yaml.yaml_event_t, alloc: *Allocator) YamlError!Self {
        const etype = switch (raw.*.type) {
            .YAML_NO_EVENT => .NoEvent,
            .YAML_STREAM_START_EVENT => EventType{ .StreamStartEvent = switch (raw.*.data.stream_start.encoding) {
                .YAML_UTF8_ENCODING => .Utf8,
                .YAML_UTF16LE_ENCODING => .Utf16LittleEndian,
                .YAML_UTF16BE_ENCODING => .Utf16BigEndian,
                else => .Any,
            } },
            .YAML_STREAM_END_EVENT => .StreamEndEvent,
            .YAML_DOCUMENT_START_EVENT => blk: {
                const Tp = @TypeOf((EventType{ .DocumentStartEvent = undefined }).DocumentStartEvent.version);
                const version: Tp = if (raw.*.data.document_start.version_directive) |_ver| .{
                    .major = @intCast(u32, _ver.*.major),
                    .minor = @intCast(u32, _ver.*.minor),
                } else null;
                break :blk EventType{ .DocumentStartEvent = .{ .version = version } };
            },
            .YAML_DOCUMENT_END_EVENT => .DocumentEndEvent,
            .YAML_ALIAS_EVENT => unreachable,
            .YAML_SCALAR_EVENT => EventType{ .ScalarEvent = .{
                .value = try alloc.dupe(u8, raw.*.data.scalar.value[0..raw.*.data.scalar.length]),
            } },
            .YAML_SEQUENCE_START_EVENT => .SequenceStartEvent,
            .YAML_SEQUENCE_END_EVENT => .SequenceEndEvent,
            .YAML_MAPPING_START_EVENT => .MappingStartEvent,
            .YAML_MAPPING_END_EVENT => .MappingEndEvent,
            else => unreachable,
        };
        return Event{
            .start = Mark.fromRaw(raw.*.start_mark),
            .end = Mark.fromRaw(raw.*.end_mark),
            .etype = etype,
        };
    }

    pub fn deinit(self: Self) void {
        switch (self.etype) {
            .ScalarEvent => |ev| ev.value.deinit(),
            else => {},
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

        fn init(allocator: *Allocator, reader: Reader) Self {
            return Self { .allocator = allocator, .inner = try Parser.init(allocator, reader) };
        }
        fn parse(self: *Self, command: ?Command) LoaderError!Node {
            var state: ?State = if (command) |cmd| switch (cmd) {
                .Mapping => State{ .Mapping = .{ .object = Object.init(self.allocator), .name = null } },
                .Sequencing => State{ .Sequencing = List.init(self.allocator) },
            } else null;
            var evt: Event = undefined;
            while (true) {
                evt = try self.inner.nextEvent();
                switch (evt.etype) {
                    .MappingStartEvent => |mse| {
                        const obj = try self.parse(.Mapping);
                        if (state) |*st| {
                            try st.addNode(obj);
                        } else return obj;
                    },
                    .MappingEndEvent => |mee| {
                        if (state) |st| switch (st) {
                            .Mapping => |map| {
                                if (map.name) |name| panic("Mapping stopped before key \'{s}\' could receive a value", .{name});
                                return Node{ .Object = map.object };
                            },
                            else => |cur| panic("Current state is '{s}', expected '{s}'", .{ @tagName(cur), @tagName(.Mapping) }),
                        } else panic("Impossible to end mapping; nothing is supposed to be happening", .{});
                    },
                    .SequenceStartEvent => |sse| {
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
                            try st.addNode(.{ .Scalar = Scalar.fromString(scalar.value) });
                        } else return Node{ .Scalar = Scalar.fromString(scalar.value) };
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
        pub fn parseDynamic(self: *Self) LoaderError!Node {
            return self.parse(null);
        }
        pub fn deinit(self: Self) void {
            self.inner.deinit();
        }
    };
}

pub const StringLoader = Loader(std.io.FixedBufferStream(String));
pub fn stringLoader(allocator: *Allocator, string: String) !StringLoader {
    const buf = std.io.fixedBufferStream(string);
    return StringLoader.init(allocator, buf);
}

test "Load String" {
    const string = "name: Bob\nage: 100";
    var strlod = try stringLoader(std.testing.allocator, string);
    defer strlod.deinit();
    const result = try strlod.parseDynamic();
    const name = result.Object.get("name").?.Scalar.String;
    const age = result.Object.get("age").?.Scalar.String;
    try std.testing.expectEqualStrings("Bob", name);
    try std.testing.expectEqualStrings("100", age);
}

