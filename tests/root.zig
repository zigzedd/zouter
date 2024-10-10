const std = @import("std");
const zouter = @import("../src/root.zig");

test {
//	try std.testing.refAllDecls(zouter);
}

comptime {
	_ = @import("example.zig");
	_ = @import("simple_routes.zig");
}
