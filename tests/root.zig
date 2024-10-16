const std = @import("std");
const zouter = @import("zouter");

test {
//	try std.testing.refAllDecls(zouter);
}

comptime {
	_ = @import("example.zig");
	_ = @import("simple_routes.zig");
}
