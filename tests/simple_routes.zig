const std = @import("std");
const zap = @import("zap");
const zouter = @import("zouter");

var notFoundResponse: []const u8 = undefined;
var errorResponse: []const u8 = undefined;
var customErrorResponse: []const u8 = undefined;
var customNotFoundResponse: []const u8 = undefined;
var okResponse: []const u8 = undefined;
var argTestResponse: []const u8 = undefined;

fn stopAfter3s() !void {
	std.time.sleep(3 * std.time.ns_per_s);
	zap.stop();
}

fn stopAfter3sThread() !std.Thread {
	return try std.Thread.spawn(.{}, stopAfter3s, .{});
}

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

fn makeRequestThread(allocator: std.mem.Allocator, method: std.http.Method, url: []const u8, varPointer: *[]const u8) !std.Thread {
	return try std.Thread.spawn(.{}, makeRequest, .{ allocator, method, url, varPointer });
}

fn notFoundHandler(_: zouter.MatchedRoute, request: zap.Request) !void
{
	try request.sendBody("not found");
}

fn internalErrorHandler(_: zouter.MatchedRoute, request: zap.Request, _: anyerror) !void
{
	try request.sendBody("error!");
}

fn customNotFound(_: zouter.MatchedRoute, request: zap.Request) !void
{
	try request.sendBody("sorry, this page does not exists...");
}

fn customErrorHandler(_: zouter.MatchedRoute, request: zap.Request, _: anyerror) !void
{
	try request.sendBody("custom error!");
}

fn empty(_: zouter.MatchedRoute, _: zap.Request) !void
{
	unreachable;
}

fn ok(_: zouter.MatchedRoute, request: zap.Request) !void
{
	try request.sendBody("ok");
}

fn sendArgTest(route: zouter.MatchedRoute, request: zap.Request) !void
{
	try request.sendBody(route.params.get("argTest").?);
}

fn badlyMadeHandler(_: zouter.MatchedRoute, _: zap.Request) !void
{
	return error.HttpParseBody;
}

/// Setup test router.
fn setupTestRouter(allocator: std.mem.Allocator) !zouter.Router {
	var testRouter = try zouter.Router.init(allocator, .{
		.handleNotFound = &notFoundHandler,
		.handleError = &internalErrorHandler,
	});

	try testRouter.route(.{
		.path = "anything",
		.children = &[_]zouter.RouteDefinition{
			.{
				.path = ":argTest",
				.children = &[_]zouter.RouteDefinition{
					.{
						.path = "test",
						.handle = .{
							.get = &badlyMadeHandler,
							.delete = &ok,
							.patch = &sendArgTest,
						},
					}
				},
			}
		},
		.handleError = &customErrorHandler,
		.handleNotFound = &customNotFound,
	});

	try testRouter.route(.{
		.path = "error",
		.handle = .{
			.any = &badlyMadeHandler,
		},
	});

	return testRouter;
}

/// Run HTTP server with test router.
fn runHttp() !void {
	const allocator = std.testing.allocator;

	// Setup test router.
	var testRouter = try setupTestRouter(allocator);
	defer testRouter.deinit();

	// Setup HTTP listener.
	var listener = zap.HttpListener.init(.{
		.interface = "127.0.0.1",
		.port = 8112,
		.log = false,
		// Add zouter to the listener.
		.on_request = zouter.Router.onRequest,
	});
	zap.enableDebugLog();
	try listener.listen();

	const notFoundThread = try makeRequestThread(allocator, std.http.Method.GET, "http://127.0.0.1:8112/notfound/query", &notFoundResponse);
	defer notFoundThread.join();

	const errorThread = try makeRequestThread(allocator, std.http.Method.GET, "http://127.0.0.1:8112/error", &errorResponse);
	defer errorThread.join();

	const customErrorThread = try makeRequestThread(allocator, std.http.Method.GET, "http://127.0.0.1:8112/anything/test%20val/test", &customErrorResponse);
	defer customErrorThread.join();

	const customNotFoundThread = try makeRequestThread(allocator, std.http.Method.POST, "http://127.0.0.1:8112/anything/test%20val/test", &customNotFoundResponse);
	defer customNotFoundThread.join();

	const okThread = try makeRequestThread(allocator, std.http.Method.DELETE, "http://127.0.0.1:8112/anything/test%20val/test", &okResponse);
	defer okThread.join();

	const argTestThread = try makeRequestThread(allocator, std.http.Method.PATCH, "http://127.0.0.1:8112/anything/test%20val/test", &argTestResponse);
	defer argTestThread.join();

	const stopThread = try stopAfter3sThread();
	defer stopThread.join();

	// Start HTTP server workers.
	zap.start(.{
		.threads = 1,
		.workers = 1,
	});
}

test {
	try runHttp();

	try std.testing.expectEqualStrings("not found", notFoundResponse);
	try std.testing.expectEqualStrings("error!", errorResponse);
	try std.testing.expectEqualStrings("custom error!", customErrorResponse);
	try std.testing.expectEqualStrings("sorry, this page does not exists...", customNotFoundResponse);
	try std.testing.expectEqualStrings("ok", okResponse);
	try std.testing.expectEqualStrings("test val", argTestResponse);

	std.testing.allocator.free(notFoundResponse);
	std.testing.allocator.free(errorResponse);
	std.testing.allocator.free(customErrorResponse);
	std.testing.allocator.free(customNotFoundResponse);
	std.testing.allocator.free(okResponse);
	std.testing.allocator.free(argTestResponse);
}
