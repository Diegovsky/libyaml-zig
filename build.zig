const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});

    const mode = b.standardReleaseOptions();

    const lib = b.addExecutable("zyaml", "src/yaml.zig");
    lib.setTarget(target);
    lib.setBuildMode(mode);
    lib.linkLibC();
    lib.linkSystemLibrary("yaml");
    lib.install();
}
