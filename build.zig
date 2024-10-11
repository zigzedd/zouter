const std = @import("std");

pub fn build(b: *std.Build) void {
	// Standard target options allows the person running `zig build` to choose
	// what target to build for. Here we do not override the defaults, which
	// means any target is allowed, and the default is native. Other options
	// for restricting supported target set are available.
	const target = b.standardTargetOptions(.{});

	// Standard optimization options allow the person running `zig build` to select
	// between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
	// set a preferred release mode, allowing the user to decide how to optimize.
	const optimize = b.standardOptimizeOption(.{});

	// Load zap dependency.
	const zap = b.dependency("zap", .{
		.target = target,
		.optimize = optimize,
		.openssl = false,
	});

	const lib = b.addSharedLibrary(.{
		.name = "zouter",
		.root_source_file = b.path("src/root.zig"),
		.target = target,
		.optimize = optimize,
	});

	// This declares intent for the library to be installed into the standard
	// location when the user invokes the "install" step (the default step when
	// running `zig build`).
	b.installArtifact(lib);

	// Add zouter module.
	const zouter_module = b.addModule("zouter", .{
		.root_source_file = b.path("src/root.zig"),
		.target = target,
		.optimize = optimize,
	});

	// Add zap dependency.
	lib.root_module.addImport("zap", zap.module("zap"));
	zouter_module.addImport("zap", zap.module("zap"));

	// Creates a step for unit testing. This only builds the test executable
	// but does not run it.
	const lib_unit_tests = b.addTest(.{
		.root_source_file = b.path("tests/root.zig"),
		.target = target,
		.optimize = optimize,
	});

	// Add zap dependency.
	lib_unit_tests.root_module.addImport("zap", zap.module("zap"));
	// Add zouter dependency.
	lib_unit_tests.root_module.addImport("zouter", zouter_module);

	const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

	// Similar to creating the run step earlier, this exposes a `test` step to
	// the `zig build --help` menu, providing a way for the user to request
	// running the unit tests.
	const test_step = b.step("test", "Run unit tests.");
	test_step.dependOn(&run_lib_unit_tests.step);


	// Documentation generation.
	const install_docs = b.addInstallDirectory(.{
		.source_dir = lib.getEmittedDocs(),
		.install_dir = .prefix,
		.install_subdir = "docs",
	});

	// Documentation generation step.
	const docs_step = b.step("docs", "Emit documentation.");
	docs_step.dependOn(&install_docs.step);
}
