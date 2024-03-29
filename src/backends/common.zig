pub const OOM = Allocator.Error;
pub const ParserError = error{ ParserInit, AlreadySet, ReadingFailed, ParsingError, InternalError, TypeError } || OOM;
pub const LoaderError = error{UnexpectedType} || OOM;
pub const YamlError = LoaderError || ParserError;
const Allocator = @import("std").mem.Allocator;

const String = []const u8;
pub const Version = struct {
    major: u32,
    minor: u32,
};

pub const Encoding = enum { Utf8, Utf16LittleEndian, Utf16BigEndian, Any };
pub const EventType = union(enum) {
    NoEvent: void,
    StreamStartEvent: Encoding,
    StreamEndEvent: void,
    DocumentStartEvent: struct {
        version: ?Version
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
