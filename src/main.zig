const std = @import("std");
pub const string = @import("string.zig");
pub const yaml = @import("yaml.zig");
const MemErr = std.mem.Allocator.Error;

pub fn main() anyerror!void {
    var file = try std.fs.cwd().openFile("hello.yaml", .{ .read = true, .write = false });
    defer file.close();
    var parser = try yaml.FileParser.init(std.heap.c_allocator, &file.reader());
    const node = try parser.parseDynamic();
    std.debug.print("valor simples: {d}", .{ node.Object.get("valor simples") orelse unreachable });
}
