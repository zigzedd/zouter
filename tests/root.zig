const std = @import("std");
const zouter = @import("zouter");

comptime {
	_ = @import("example.zig");
	_ = @import("simple_routes.zig");
}
