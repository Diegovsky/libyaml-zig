const yaml = @cImport(
    @cInclude("yaml.h")
);
const std = @import("std");
const string = @import("string.zig");
const MemErr = std.mem.Allocator.Error;

fn to_bool(i: anytype) bool {
    return i != 0;
}

const String = string.String;
const List = std.ArrayList(Node);
const Object = string.StringHashMap(Node);
const Scalar = union(enum) {
    String: String,
    Number: f64,
};
const Node = union(enum) {
    Scalar: Scalar,
    List: List,
    Object: Object,
    Unknown: void,
};
const MState = union(enum) {
    Mapping: struct { 
        Object: Object,
        name: ?String,
    },
    Sequencing: *List,
    Nothing: void,
};

fn parse(parser: *yaml.yaml_parser_t, _state: MState) MemErr!Node {
    var done = false;
    var event: yaml.yaml_event_t = undefined;
    var state = _state;
    const stop_condition: yaml.yaml_event_type_e = switch(state) {
        .Mapping => .YAML_MAPPING_END_EVENT,
        .Sequencing => .YAML_SEQUENCE_END_EVENT,
        else => .YAML_STREAM_END_EVENT,
    };
    while (!done)
    {
        if (!to_bool(yaml.yaml_parser_parse(parser, &event))) {
            break;
        }
        defer yaml.yaml_event_delete(&event);
        switch(event.type) {
            .YAML_SCALAR_EVENT => {
                var scalar = event.data.scalar;
                var value = try string.stringFromPtr(scalar.value, scalar.length);
                std.debug.print("Got scalar {s}\n", .{value.items});
                switch(state) {
                    .Mapping => |info| {
                        if(info.name) |name| { 
                            try info.Object.put(name,.{ .Scalar = .{ .String = value}});
                            info.name = null;
                        } else {
                            info.name = value;
                        }
                    },
                    .Sequencing => |list| {
                        try list.append(.{ .Scalar = .{ .String = value} });
                    },
                    .Nothing => {
                        std.debug.print("Ignored scalar '{s}'.\n", .{value.items});
                    }
                }
            },
            .YAML_MAPPING_START_EVENT => {
                std.debug.print("TODO ({s})!\n", .{ @tagName(event.type) });
            },
            .YAML_SEQUENCE_START_EVENT => {
                std.debug.print("TODO ({s})!\n", .{ @tagName(event.type) });
            },
            else => {
                std.debug.print("Received event {s}\n", .{@tagName(event.type)});
            },
        }
        done = event.type == .YAML_STREAM_END_EVENT;
        done = event.type == stop_condition or done;
    }
    // Temporary, remove after
    return switch(state) {
        .Nothing => .Unknown,
        .Mapping => |info| .{ .Object = info.Object },
        .Sequencing => |list| .{.List = list.*},
    };
}

pub fn showEvents() void {
    std.debug.print("const Event = {{\n", .{});
    inline for(@typeInfo(yaml.yaml_event_type_e).Enum.fields) |v| {
        std.debug.print("\t{s} = {},\n", .{ v.name, v.value });
    }
    std.debug.print("}}\n", .{});
}

pub fn main() anyerror!void {
    var parser: yaml.yaml_parser_t = undefined;
    var file = yaml.fopen("hello.yaml", "rb") orelse unreachable;
    _ = yaml.yaml_parser_initialize(&parser);
    defer yaml.yaml_parser_delete(&parser);
    yaml.yaml_parser_set_input_file(&parser, file);
    var doc = parse(&parser, .{ .Mapping = .{
        .Object = Object.init(std.heap.c_allocator),
        .name = null }});
}
