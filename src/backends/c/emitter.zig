usingnamespace @import("exports.zig");

const CEmitter = c.yaml_emitter_t;
const CEvent = c.yaml_event_s;
const CEventType = c.yaml_event_e;

fn emptyCEvent(cetype: CEventType) CEvent {
    return .{
        .type = cetype,
        .start_mark = undefined,
        .end_mark = undefined,
        .data = undefined,
    };
}

pub fn eventToC(evt: common.Event) common.EmitterError!void {
    return comptime switch(evt) {
        .NoEvent => emptyCEvent( c.YAML_NO_EVENT ),
        .StreamStartEvent => |encoding| try initCEvent(c.yaml_stream_start_event_initialize, .{encodingToC(encoding)}),
        .StreamEndEvent => try initCEvent(c.yaml_stream_end_event_initialize, .{}),
        .DocumentStartEvent => |ver| try initCEvent(c.yaml_stream_start_event_initialize, .{ ver orelse null, null, null, 0}),
        .DocumentEndEvent => try initCEvent(c.yaml_document_end_event_initialize, .{}),
        .SequenceStartEvent => try initCEvent(c.yaml_sequence_start_event_initialize, .{null, null, 0, c.YAML_BLOCK_SEQUENCE_STYLE}),
        .SequenceEndEvent => try initCEvent(c.yaml_sequence_end_event_initialize, .{}),
        .MappingStartEvent => try initCEvent(c.yaml_mapping_start_event_initialize, .{null, null, 0, c.YAML_BLOCK_MAPPING_STYLE}),
        .MappingEndEvent => try initCEvent(c.yaml_mapping_end_event_initialize, .{}),
        .ScalarEvent => |scalar| try initCEvent(c.yaml_scalar_event_initialize, .{null, null, scalar.value, 0, 0, c.YAML_ANY_SCALAR_STYLE}),
    };
}

fn initCEvent(initfn: anytype, args: anytype) common.EmitterError!CEvent {
    var cevt: CEvent = undefined;
    if( @call(.auto, initfn, .{&cevt} ++ args) == 0) {
        return .InternalError;
    } else {
        return cevt;
    }
}

fn encodingToC(enc: common.Encoding) c_int {
    return switch(enc) {
        Utf8 => c.YAML_UTF8_ENCODING,
        Utf16LittleEndian => c.YAML_UTF16LE_ENCODING,
        Utf16BigEndian => c.YAML_UTF16BE_ENCODING,
        Any => c.YAML_ANY_ENCODING,
    };
}

pub fn Emitter(comptime Writer: type) type {
    return struct {
        raw: *CEmitter,
        allocator: *Allocator,

        const Self = @This();

        pub fn init(allocator: *Allocator) OOM!Self {
            var raw = allocator.create(CEmitter);
            errdefer allocator.destroy(raw);
            if (c.yaml_emitter_initialize(raw) == 0) {
                return OOM.OutOfMemory;
            }
            return .{ .raw = raw, .allocator = allocator };
        }

        fn handler(maybe_data: ?*c_void, maybe_buff: ?[*]u8, buflen: usize) callconv(.C) c_int {
            if (maybe_data) |data| {
                if (maybe_buff) |buff| {
                    var writer = @ptrCast(Writer, @alignCast(@alignOf(Writer), data));
                    if (writer.write()) |br| {
                        bytes_read.?.* = br;
                        return 1;
                    } else |_| {
                        return 0;
                    }
                }
            }
            return 0;
        }

        pub fn deinit(self: *Self) void {
            c.yaml_emitter_delete(self.raw);
            self.allocator.destroy(self.raw);
        }

        pub emit(self: *Self, event: common.CEvent) common.EmitterError!void {
            if( c.yaml_emmiter_emit(self.raw, eventToC(event)) == 0) {
                return error.InternalError;
            }
        }
    };
}
