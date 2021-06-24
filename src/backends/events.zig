const Allocator = @import("std").mem.Allocator;
pub const Encoding = enum { Utf8, Utf16LittleEndian, Utf16BigEndian, Any };
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
    allocator: *Allocator,

    const Self = @This();
    pub fn deinit(self: Self) void {
        switch (self) {
            .ScalarEvent => |str| {
                allocator.free(str);
            },
            else => {},
        }
    }
};
