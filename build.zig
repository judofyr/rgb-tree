const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    const tests_run_step = b.addRunArtifact(tests);
    tests_run_step.has_side_effects = true;

    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;
    if (coverage) {
        const runner = [_][]const u8{
            "kcov",
            "--include-path",
            ".",
            "coverage", // output dir
        };

        const dst = try tests_run_step.argv.addManyAt(0, runner.len);
        for (runner, 0..) |arg, idx| {
            dst[idx] = .{ .bytes = b.dupe(arg) };
        }
    }

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests_run_step.step);
}
