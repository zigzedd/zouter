const std = @import("std");
const zap = @import("zap");
const routeManager = @import("route.zig");

/// Matched route structure.
pub const MatchedRoute = struct {
	route: ?*routeManager.RouteNode = null,
	params: routeManager.RouteParamsMap = undefined,
};

/// Route handler function.
pub const RouteHandler = *const fn (route: MatchedRoute, request: zap.Request) anyerror!void;

/// Route pre-handler function.
pub const RoutePreHandler = *const fn (route: MatchedRoute, request: zap.Request) anyerror!bool;

/// Error route handler function.
pub const ErrorRouteHandler = *const fn (route: MatchedRoute, request: zap.Request, err: anyerror) anyerror!void;

/// Route handler definition for each request method.
pub const RouteHandlerDefinition = struct {
	get: ?RouteHandler = null,
	post: ?RouteHandler = null,
	patch: ?RouteHandler = null,
	put: ?RouteHandler = null,
	delete: ?RouteHandler = null,
	any: ?RouteHandler = null,
};

/// Router root tree definition.
pub const RouterDefinition = struct {
	/// Not found function, called when a route was not found.
	handleNotFound: ?RouteHandler = null,

	/// Error function, called when a route encountered an error.
	handleError: ?ErrorRouteHandler = null,
};

/// Route definition object.
pub const RouteDefinition = struct {
	/// Route path.
	path: []const u8,

	/// Children routes: full path will be their path appended to the current route path.
	children: ?([]const RouteDefinition) = null,

	/// Handle function, called when this route is reached.
	handle: ?RouteHandlerDefinition = null,

	/// Not found function, called when a child route was not found.
	handleNotFound: ?RouteHandler = null,

	/// Error function, called when a child route encountered an error.
	handleError: ?ErrorRouteHandler = null,

	/// Pre-handler function, called before handling this route or any children.
	preHandle: ?RoutePreHandler = null,

	/// Post-handler function, called after handling this route or any children.
	postHandle: ?RouteHandler = null,
};

/// A router structure.
pub const Router = struct {
	const Self = @This();

	/// Internal static router instance.
	var routerInstance: Self = undefined;

	/// Root of the route tree.
	root: routeManager.RouteNode,

	/// Initialize a new router instance.
	pub fn init(allocator: std.mem.Allocator, definition: RouterDefinition) !Self
	{
		routerInstance = Self{
			.root = try routeManager.RouteNode.init(allocator, ""),
		};
		// Handle of the root tree is never used.
		routerInstance.root.handle = .{
			.any = &impossible,
		};
		routerInstance.root.handleNotFound = definition.handleNotFound orelse &defaultNotFoundHandler;
		routerInstance.root.handleError = definition.handleError orelse &defaultErrorHandler;
		return routerInstance;
	}

	/// Deinitialize the router instance.
	pub fn deinit(self: *Self) void
	{
		self.root.deinit();
		routerInstance = undefined;
	}

	/// Handle an error which happen in any handler.
	fn handleError(request: zap.Request, err: anyerror, routingResult: *routeManager.RoutingResult) void
	{
		// Run error handlers from the most specific to the least specific (reverse order of the array).
		var errorHandlersIterator = std.mem.reverseIterator(routingResult.errorHandlers.items);
		while (errorHandlersIterator.next()) |errorHandler|
		{ // For each error handler, try to run it with the given error.
			errorHandler(MatchedRoute{
				.route = routingResult.route,
				.params = routingResult.params,
			}, request, err) catch {
				// Error handler failed, we try the next one.
				continue;
			};
			return; // Error handler ran successfully, we can stop there.
		}
	}

	/// Handle an incoming request and call the right route.
	fn handle(self: *Self, request: zap.Request) void
	{
		// Split path in route parts.
		var path = std.mem.splitScalar(u8, std.mem.trim(u8, request.path.?, " /"), '/');
		// Try to match a route from its parts.
		const routingResult = self.root.newRoutingResult() catch |err| {
			// Run default error handler if something happens while building routing result.
			self.root.handleError.?(.{}, request, err) catch {};
			return;
		};
		defer routingResult.deinit();
		// Matching the requested route. Put the result in routingResult pointer.
		_ = self.root.match(request.methodAsEnum(), &path, routingResult) catch |err| {
			Self.handleError(request, err, routingResult);
			return;
		};

		// Try to run matched route handling.
		Self.runMatchedRouteHandling(routingResult, request)
			// Handle error in request handling.
			catch |err| Self.handleError(request, err, routingResult);
	}

	/// Run a matched route.
	fn runMatchedRouteHandling(routingResult: *routeManager.RoutingResult, request: zap.Request) !void
	{
		// Initialized route data passed to handlers from the routing result.
		const routeData = MatchedRoute{
			.route = routingResult.route,
			.params = routingResult.params,
		};

		for (routingResult.preHandlers.items) |preHandle|
		{ // Run each pre-handler. If a pre-handler returns false, handling must stop now.
			if (!try preHandle(routeData, request))
				return;
		}

		// Run matched route handler with result params.
		try routingResult.handler(routeData, request);

		for (routingResult.postHandlers.items) |postHandle|
		{ // Run each post-handler.
			try postHandle(routeData, request);
		}
	}

	/// Define a root route.
	pub fn route(self: *Self, definition: RouteDefinition) !void
	{
		try self.root.parse(definition);
	}

	/// The on_request function of the HTTP listener.
	pub fn onRequest(request: zap.Request) anyerror!void
	{
		// Call handle of the current router instance.
		routerInstance.handle(request);
	}
};

/// Impossible function.
fn impossible(_: MatchedRoute, _: zap.Request) !void
{
	unreachable;
}

/// Default not found handling.
fn defaultNotFoundHandler(_: MatchedRoute, request: zap.Request) !void
{
	try request.setContentType(zap.ContentType.TEXT);
	request.setStatus(zap.http.StatusCode.not_found);
	try request.sendBody("404: Not Found");
}

/// Default error handling.
fn defaultErrorHandler(_: MatchedRoute, request: zap.Request, _: anyerror) !void
{
	try request.setContentType(zap.ContentType.TEXT);
	request.setStatus(zap.http.StatusCode.internal_server_error);
	try request.sendBody("500: Internal Server Error");
}
