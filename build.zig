const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const customParser = b.option(bool, "custom", "Use the custom parser instead of libyaml (WIP)") orelse false;

    const lib = b.addSharedLibrary("libyaml-zig", "src/yaml.zig", .unversioned);
    lib.setTarget(target);
    lib.setBuildMode(mode);
    if (!customParser) {
        lib.linkLibC();
        lib.linkSystemLibrary("yaml");
    }
    lib.addBuildOption(bool, "customParser", customParser);
    lib.install();

    const tests = b.addTest("src/yaml.zig");
    tests.setBuildMode(mode);
    tests.addBuildOption(bool, "customParser", customParser);
    tests.linkLibrary(lib);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}
