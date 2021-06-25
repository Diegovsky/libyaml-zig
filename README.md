# libyaml-zig

Experimental yaml parsing using libyaml for the Zig :zap: Programming Language.

## Examples

hello.yaml:

```yaml
language: Zig
version: 8.0
```

main.zig:

```zig
const std = @import("std");
pub const yaml = @import("yaml.zig");

pub fn main() anyerror!void {
    var file = try std.fs.cwd().openFile("language.yaml", .{ .read = true, .write = false });
    defer file.close();
    var parser = try yaml.FileParser.init(std.heap.c_allocator, &file.reader());
    const node = try parser.parseDynamic();
    const language = parser.Object.get("language").?.Scalar.String;
    const version = parser.Object.get("version").?.Scalar.Number;
    std.debug.print("Language name: {s}\nLanguage version: {}\n", .{ language, version });
}
```
output:
```
Language name: Zig
Language version: 8.0e+1
```

## Building

### Requirements

To build libyaml-zig you need to have

- [libyaml](https://github.com/yaml/libyaml)  
- Zig 8.0 stable

### How to build

At project root, just run

```bash
zig build
```

And that should get you going.

## Documentation

Since this is still in development, no docs are available yet, but are planned. You can look at the source code to learn more.

## Planned Features

In no particular order and not limited to:

- [ ] More scalar types.
- [ ] Choose between internal errors or panics (safety vs optimization).
- [ ] Schema support.
- [ ] Make libyaml an optional dependency.

At the time of writing, the basic structures such as objects, sequences and scalars (numbers and string) are supported. This project currently aims to be [StrictYaml](https://github.com/crdoconnor/strictyaml) compliant. If you want comlex features like direct representation, duplicate keys, node anchors and [others](https://hitchdev.com/strictyaml/features-removed/), consider using a simple embedded programming language like Lua or Guile Scheme.
