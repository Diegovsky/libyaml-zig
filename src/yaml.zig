const yaml = @cImport(@cInclude("yaml.h"));
const std = @import("std");
const panic = std.debug.panic;
const Allocator = std.mem.Allocator;
const MemErr = Allocator.Error;

pub const YamlError = error{ ParserInit, ParsingError, OutOfMemory };

pub const Encoding = enum { Utf8, Utf16LittleEndian, Utf16BigEndian, Any };
const List = std.ArrayList(Node);
const Object = std.StringHashMap(Node);

const String = []const u8;

const Scalar = union(enum) {
    String: String,
    Number: f64,

    pub fn fromString(string: String) Scalar {
        const num = std.fmt.parseFloat(f64, string) catch {
            return .{ .String = string };
        };
        return .{ .Number = num };
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

    pub fn addNode(self: *@This(), node: Node) YamlError!void {
        switch(self.*) {
            .Mapping => |*mapping| {
                if(mapping.name) |name| {
                    try mapping.object.put(name, node);
                    mapping.name = null;
                } else panic("Expected key but there was none", .{});
            },
            .Sequencing => |*seq| {
                try seq.append(node);
            }
        }
    }
};

pub const Mark = struct {
    index: usize,
    line: usize,
    column: usize,

    pub fn fromRaw(raw: yaml.yaml_mark_t) Mark {
        return .{
            .index = raw.index,
            .line = raw.line,
            .column = raw.column,
        };
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

pub fn Parser(comptime _Reader: type) type {
    const Reader = *_Reader;
    return struct {
        inner: yaml.yaml_parser_t,
        wrapper: *ReaderWrapper,
        _alloc: *Allocator,

        const Self = @This();

        // A helper struct to pass data to C code. This is because `Reader`
        //  can be of any size and alignment, also it's `read` function returns a generic error,
        //  but a pointer to it will be of a predictable size, making this possible.
        const ReaderWrapper = struct {
            inner: Reader,
            const RW = @This();

            pub fn fromReader(reader: Reader) RW {
                return .{ .inner = reader };
            }
            pub fn read_handler_raw(selfopt: ?*c_void, buf: [*c]u8, buflen: usize, readlen: [*c]usize) callconv(.C) c_int {
                if (selfopt) |selfptr| {
                    const self = @ptrCast(*RW, @alignCast(@alignOf(RW), selfptr));
                    const size = self.read_handler(buf[0..buflen]) catch return 0;
                    readlen.* = size;
                    return 1;
                } else {
                    std.debug.print("!! ReaderWrapper was null !!\n", .{});
                    unreachable;
                }
            }
            pub fn read_handler(self: *RW, buf: []u8) anyerror!u64 {
                return self.inner.read(buf);
            }
        };
        // reader must outlive this.
        pub fn init(alloc: *Allocator, reader: Reader) YamlError!Self {
            var self: Self = .{ .inner = undefined, .wrapper = undefined, ._alloc = alloc };
            if (yaml.yaml_parser_initialize(&self.inner) == 0) {
                return YamlError.ParserInit;
            }
            self.wrapper = try alloc.create(ReaderWrapper);
            self.wrapper.* = ReaderWrapper.fromReader(reader);
            yaml.yaml_parser_set_input(
                &self.inner,
                ReaderWrapper.read_handler_raw,
                @ptrCast(*c_void, self.wrapper),
            );
            return self;
        }

        pub fn deinit(self: *Self) void {
            yaml.yaml_parser_delete(self.inner);
            self._alloc.destroy(self.wrapper);
        }
        // You must call Event.deinit if this call is successful.
        pub fn nextEvent(self: *Self) YamlError!Event {
            var event: yaml.yaml_event_t = undefined;
            if (yaml.yaml_parser_parse(&self.inner, &event) == 0) {
                return YamlError.ParsingError;
            }
            const ev = Event.fromRaw(&event, self._alloc);
            yaml.yaml_event_delete(&event);
            return ev;
        }
        // This function returns the intermediate representation of YAML.
        // This is useful when you don't know the data beforehand.
        fn parse(self: *Self, command: ?Command) YamlError!Node {
            var state: ?State = if(command) |cmd| switch (cmd) {
                .Mapping => State { .Mapping = .{ .object = Object.init(self._alloc), .name = null } },
                .Sequencing => State { .Sequencing = List.init(self._alloc)},
            } else null;
            while(true) {
                const evt = try self.nextEvent();
                if(false) {
                    switch(evt.etype) {
                        .ScalarEvent => |sc|  std.debug.print("Scalar Event: {s}\n", .{sc.value}),
                        else => std.debug.print("Event: {s}\n", .{@tagName(evt.etype)}),
                    }
                }
                switch (evt.etype) {
                    .MappingStartEvent => |mse| {
                        const obj = try self.parse(.Mapping);
                        if(state) |*st| {
                            try st.addNode(obj);
                        } else return obj;
                    },
                    .MappingEndEvent => |mee| {
                        if(state) |st| switch (st) {
                            .Mapping => |map| {
                                if (map.name) |name| panic("Mapping stopped before key \'{s}\' could receive a value", .{name});
                                return Node{ .Object = map.object };
                            },
                            else => |cur| panic("Current state is '{s}', expected '{s}'", .{ @tagName(cur), @tagName(.Mapping) }),
                        } else panic("Impossible to end mapping; nothing is supposed to be happening", .{});
                    },
                    .SequenceStartEvent => |sse| {
                        const seq = try self.parse(.Sequencing);
                        if(state) |*st| {
                            try st.addNode(seq);
                        } else return seq;
                    },
                    .ScalarEvent => |scalar| {
                        if(state) |*st| {
                            // If we're currently mapping and there is no name yet,
                            //  store this scalar to be used as a key.
                            switch(st.*) {
                                .Mapping => |*map| if(map.name == null) {
                                    map.name = scalar.value;
                                    continue;
                                },
                                else => {},
                            }
                            try st.addNode(.{.Scalar = Scalar.fromString(scalar.value)});
                        } else return Node {.Scalar = Scalar.fromString(scalar.value)};
                    },
                    .SequenceEndEvent => {
                        if(state) |st| {
                            switch(st) {
                                .Sequencing => |seq| return Node{ .List =  seq },
                                .Mapping => panic("Received sequence stop event while mapping", .{}),
                            } 
                        } else panic("Impossible to end sequencing; nothing is supposed to be happening", .{});
                    },
                    else => {},
                }
            }
            unreachable;
        }
        pub fn parseDynamic(self: *Self) YamlError!Node {
            return self.parse(null);
        }
    };
}

// Just a convenience definition for `File`s. For more information,
//  go to `Parser`.
pub const FileParser = Parser(std.fs.File.Reader);
