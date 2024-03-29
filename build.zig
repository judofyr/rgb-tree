const std = @import("std");

pub fn build(b: *std.build.Builder) void {
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
        tests_run_step.argv.insertSlice(0, &[_]std.Build.RunStep.Arg{
            .{ .bytes = b.dupe("kcov") },
            .{ .bytes = b.dupe("--include-path") },
            .{ .bytes = b.dupe(".") },
            .{ .bytes = b.dupe("coverage") }, // output dir
        }) catch unreachable;
    }

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&tests_run_step.step);
}
