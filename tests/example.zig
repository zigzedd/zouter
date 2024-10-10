const std = @import("std");
const zap = @import("zap");
const zouter = @import("zouter");

/// Stop zap in 3s.
fn stopAfter3s() !void {
	std.time.sleep(3 * std.time.ns_per_s);
	zap.stop();
}

// Spawn a new thread to stop zap in 3s.
fn stopAfter3sThread() !std.Thread {
	return try std.Thread.spawn(.{}, stopAfter3s, .{});
}

// Make an HTTP request to the given URL and put the result in the given pointed variable.
fn makeRequest(allocator: std.mem.Allocator, method: std.http.Method, url: []const u8, varPointer: *[]const u8) !void {
	// Emit HTTP request to the server.
	var http_client: std.http.Client = .{ .allocator = allocator };
	defer http_client.deinit();
	var response = std.ArrayList(u8).init(allocator);
	defer response.deinit();
	_ = try http_client.fetch(.{
		.method = method,
		.location = .{ .url = url },
		.response_storage = .{ .dynamic = &response },
	});

	varPointer.* = try allocator.dupe(u8, response.items);
}

/// Make a request thread.
fn makeRequestThread(allocator: std.mem.Allocator, method: std.http.Method, url: []const u8, varPointer: *[]const u8) !std.Thread {
	return try std.Thread.spawn(.{}, makeRequest, .{ allocator, method, url, varPointer });
}

/// GET /foo/:arg/bar request handler.
fn get(route: zouter.MatchedRoute, request: zap.Request) !void {
	var bodyBuffer: [512]u8 = undefined;
	const body = try std.fmt.bufPrint(&bodyBuffer, "get: {s}", .{route.params.get("arg").?});
	try request.sendBody(body);
}

/// POST /foo/:arg/bar request handler.
fn post(route: zouter.MatchedRoute, request: zap.Request) !void {
	var bodyBuffer: [512]u8 = undefined;
	const body = try std.fmt.bufPrint(&bodyBuffer, "post: {s}", .{route.params.get("arg").?});
	try request.sendBody(body);
}

/// Setup an example router.
fn setupExampleRouter(allocator: std.mem.Allocator) !zouter.Router {
	// Initialize an example router.
	var exampleRouter = try zouter.Router.init(allocator, .{});

	// Add a route to the example router.
	try exampleRouter.route(.{
		.path = "foo",
		.children = &[_]zouter.RouteDefinition{
			.{
				.path = ":arg",
				.children = &[_]zouter.RouteDefinition{
					.{
						.path = "bar",
						.handle = .{
							.get = &get,
							.post = &post,
						},
					}
				},
			}
		},
	});

	return exampleRouter;
}

/// Run HTTP server with test router.
fn runHttp(allocator: std.mem.Allocator) !void {
	// Setup test router.
	var exampleRouter = try setupExampleRouter(allocator);
	defer exampleRouter.deinit();

	// Setup HTTP listener.
	var listener = zap.HttpListener.init(.{
		.interface = "127.0.0.1",
		.port = 8112,
		.log = true,
		// Add zouter to the listener.
		.on_request = zouter.Router.onRequest,
	});
	try listener.listen();

	// Emit a GET HTTP request.
	const getThread = try makeRequestThread(allocator, std.http.Method.GET, "http://127.0.0.1:8112/foo/any%20value/bar", &getResponse);
	defer getThread.join();

	// Emit a POST HTTP request.
	const postThread = try makeRequestThread(allocator, std.http.Method.POST, "http://127.0.0.1:8112/foo/any%20value/bar", &postResponse);
	defer postThread.join();

	// Add zap stop in 3s.
	const stopThread = try stopAfter3sThread();
	defer stopThread.join();

	// Start HTTP server workers.
	zap.start(.{
		.threads = 1,
		.workers = 1,
	});
}

var getResponse: []const u8 = undefined;
var postResponse: []const u8 = undefined;

test {
	const allocator = std.testing.allocator;
	try runHttp(allocator);

	// Test that responses are correct.
	try std.testing.expectEqualStrings("get: any value", getResponse);
	try std.testing.expectEqualStrings("post: any value", postResponse);

	// Free allocated responses.
	allocator.free(getResponse);
	allocator.free(postResponse);
}
