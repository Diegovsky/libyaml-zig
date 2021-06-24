usingnamespace @import("exports.zig");

const CParser = c.yaml_parser_t;
const CEvent = c.yaml_event_t;
const CEventType = c.yaml_event_e;
const CError = c.yaml_error_type_t;

/// A simple abstraction around libyaml's parser. This is for private use only.
/// Most of the resource ownership rules from libyaml still apply,
/// so be careful with this.
pub fn Parser(comptime Reader: type) type {
    return struct {
    raw: *CParser,
    allocator: *Allocator,

    const Self = @This();

    pub fn init(allocator: *Allocator, reader: Reader) ParserError!Self {
        var raw = try allocator.create(CParser);
        errdefer allocator.destroy(raw);

        // Checking if initialization failed.
        if (c.yaml_parser_initialize(raw) == 0) {
            return error.OutOfMemory;
        }
        errdefer c.yaml_parser_delete(raw);

        c.yaml_parser_set_input(self.raw, reader, Self.handler);
        return .{.raw = raw, .allocator = allocator, };
    }
        
    // This function is called by libyaml to get more data from a buffer.
    // `data` is a pointer we give to libyaml when `yaml_parser_set_input` is called.
    // `buff` is a pointer to a byte buffer of size `buflen`.
    //        This is were we should paste the data read from `context`.
    // `bytes_read` is a pointer in which we write the actual number of bytes that were read.
    fn handler(maybe_data: ?*c_void, buff: [*]u8, buflen: usize, bytes_read: *usize) callconv(.C) c_int {
        if (maybe_data) |data| {
            var ctx = @alignCast(@alignOf(context), data);
            if (ctx.readAll(buf[0..buflen])) |br| {
                bytes_read.* = br;
                return 1;
            } else {
                return 0;
            }
        } else {
            return 0;
        }
    }
    pub fn nextEvent(self: *Self) ParserError!events.Event {
        var raw_event: CEvent = undefined;
        if (c.yaml_parser_parse(self.raw, &raw_event) == 0) {}
        const etype = switch (raw_event.*.type) {
            .YAML_NO_EVENT => .NoEvent,
            .YAML_STREAM_START_EVENT => EventType{ .StreamStartEvent = switch (raw_event.*.data.stream_start.encoding) {
                .YAML_UTF8_ENCODING => .Utf8,
                .YAML_UTF16LE_ENCODING => .Utf16LittleEndian,
                .YAML_UTF16BE_ENCODING => .Utf16BigEndian,
                else => .Any,
            } },
            .YAML_STREAM_END_EVENT => .StreamEndEvent,
            .YAML_DOCUMENT_START_EVENT => blk: {
                const Tp = @TypeOf((EventType{ .DocumentStartEvent = undefined }).DocumentStartEvent.version);
                const version: Tp = if (raw_event.*.data.document_start.version_directive) |_ver| .{
                    .major = @intCast(u32, _ver.*.major),
                    .minor = @intCast(u32, _ver.*.minor),
                } else null;
                break :blk EventType{ .DocumentStartEvent = .{ .version = version } };
            },
            .YAML_DOCUMENT_END_EVENT => .DocumentEndEvent,
            .YAML_ALIAS_EVENT => unreachable,
            .YAML_SCALAR_EVENT => EventType{ .ScalarEvent = .{
                .value = try alloc.dupe(u8, raw_event.*.data.scalar.value[0..raw_event.*.data.scalar.length]),
            } },
            .YAML_SEQUENCE_START_EVENT => .SequenceStartEvent,
            .YAML_SEQUENCE_END_EVENT => .SequenceEndEvent,
            .YAML_MAPPING_START_EVENT => .MappingStartEvent,
            .YAML_MAPPING_END_EVENT => .MappingEndEvent,
            else => unreachable,
        };
        return Event{
            .start = Mark.fromRaw(raw_event.*.start_mark),
            .end = Mark.fromRaw(raw_event.*.end_mark),
            .etype = etype,
        };
    }
    pub fn deinit(self: Self) void {
        c.yaml_parser_delete(self.raw);
        self.allocator.free(self.raw);
    }
    };
}
