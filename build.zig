const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{});

	// Load zap dependency.
	const zap = b.dependency("zap", .{
		.target = target,
		.optimize = optimize,
		.openssl = false,
	});

	const lib_mod = b.addModule("zouter", .{
		.root_source_file = b.path("src/root.zig"),
		.target = target,
		.optimize = optimize,
	});

	// Add zap dependency.
	lib_mod.addImport("zap", zap.module("zap"));

	// Add unit tests.
	const lib_unit_tests = b.addTest(.{
		.root_source_file = b.path("tests/root.zig"),
		.target = target,
		.optimize = optimize,
	});
	lib_unit_tests.root_module.addImport("zap", zap.module("zap"));
	lib_unit_tests.root_module.addImport("zouter", lib_mod);
	const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

	const test_step = b.step("test", "Run unit tests.");
	test_step.dependOn(&run_lib_unit_tests.step);


	// Documentation generation.
	const install_docs = b.addInstallDirectory(.{
		.source_dir = lib_unit_tests.getEmittedDocs(),
		.install_dir = .prefix,
		.install_subdir = "docs",
	});

	// Documentation generation step.
	const docs_step = b.step("docs", "Emit documentation.");
	docs_step.dependOn(&install_docs.step);
}
