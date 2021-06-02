const std = @import("std");
pub const String = std.ArrayList(u8);
const MemErr = std.mem.Allocator.Error;

fn hashString(st: String) u64 {
    return std.hash_map.hashString(st.items);
}

fn eqlString(st: String, st2: String) bool {
    return std.hash_map.eqlString(st.items, st2.items);
}

pub fn stringFromPtr(ptr: [*]const u8, len: usize) MemErr!String {
    var st = try String.initCapacity(std.heap.c_allocator, len);
    st.appendSliceAssumeCapacity(ptr[0..len]);
    return st;
}

pub fn StringHashMap(comptime V: type) type {
    return std.HashMap(String, V, hashString, eqlString, std.hash_map.DefaultMaxLoadPercentage);
}