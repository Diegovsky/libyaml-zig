pub const std = @import("std");
pub const c = @cImport(@cInclude("yaml.h"));
pub const common = @import("../common.zig");
pub const Allocator = std.mem.Allocator;

fn cErrorToYamlError(cerr: CError) ?common.LoaderError {
    return switch(cerr) {
        .YAML_MEMORY_ERROR => .MemError,
        .YAML_READER_ERROR => .ReadingFailed,
        .YAML_PARSER_ERROR => .InternalError,
        else => null,
    };
}