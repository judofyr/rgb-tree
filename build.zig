const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const lib = b.addStaticLibrary("rgb-tree", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    const test_filter = b.option([]const u8, "test-filter", "Skip tests that do not match filter");

    const main_tests = b.addTest("src/main.zig");
    main_tests.addPackagePath("dot-builder", "../zig-dot-builder/src/main.zig");
    main_tests.setBuildMode(mode);
    if (test_filter) |filter| main_tests.setFilter(filter);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);
}
