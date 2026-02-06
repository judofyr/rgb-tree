const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const root_mod = b.addModule("rgb-tree", .{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/root.zig"),
    });

    const lib = b.addLibrary(.{
        .name = "rgb-tree",
        .root_module = root_mod,
    });
    b.default_step.dependOn(&lib.step);

    const tests = b.addTest(.{ .root_module = root_mod });
    const tests_run = b.addRunArtifact(tests);

    const tests_step = b.step("test", "run tests");
    tests_step.dependOn(&tests_run.step);

    // tests_run_step.has_side_effects = true;

    // const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    // if (coverage) {
    //     const runner = [_][]const u8{
    //         "kcov",
    //         "--include-path",
    //         ".",
    //         "coverage", // output dir
    //     };

    //     const dst = try tests_run_step.argv.addManyAt(0, runner.len);
    //     for (runner, 0..) |arg, idx| {
    //         dst[idx] = .{ .bytes = b.dupe(arg) };
    //     }
    // }

    // const test_step = b.step("test", "Run unit tests");
    // test_step.dependOn(&tests_run_step.step);
}
