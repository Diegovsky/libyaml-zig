pub const std = @import("std");
pub const c = @cImport(@cInclude("yaml.h"));
pub const events = @import("../events.zig");
pub usingnamespace @import("../error.zig");
pub const Allocator = std.mem.Allocator;
pub const MemoryError = Allocator.Error;

fn cErrorToYamlError(cerr: CError) ?LoaderError {
    return switch(cerr) {
        .YAML_MEMORY_ERROR => LoaderError.MemError,
        .YAML_READER_ERROR => LoaderError.ReadingFailed,
        .YAML_PARSER_ERROR => LoaderError.InternalError,
        else => null,
    };
}