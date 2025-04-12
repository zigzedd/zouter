const std = @import("std");
const zap = @import("zap");
const router = @import("router.zig");

/// Route params map type.
pub const RouteParamsMap = std.StringHashMap([]u8);

/// Routing result.
pub const RoutingResult = struct {
	const Self = @This();

	allocator: std.mem.Allocator,
	route: *RouteNode,
	handler: router.RouteHandler,
	params: RouteParamsMap,
	preHandlers: std.ArrayList(router.RoutePreHandler),
	postHandlers: std.ArrayList(router.RouteHandler),
	notFoundHandler: router.RouteHandler,
	errorHandlers: std.ArrayList(router.ErrorRouteHandler),

	/// Add a URL-encoded param to the routing result.
	pub fn addHttpParam(self: *Self, key: []const u8, value: []const u8) !void
	{
		// Decoding URL-encoded value.
		var buffer = try self.allocator.alloc(u8, value.len);
		const decodedValue = std.Uri.percentDecodeBackwards(buffer, value);

		// Move bytes from the end to the beginning of the buffer.
		std.mem.copyForwards(u8, buffer[0..(decodedValue.len)], buffer[(buffer.len - decodedValue.len)..]);
		// Resize the buffer to free remaining bytes.
		if (self.allocator.resize(buffer, decodedValue.len))
		{ // The buffer could have been resized, change variable length.
			buffer = buffer[0..decodedValue.len];
		}
		else
		{ // Could not resize the buffer, allocate a new one and free the old one.
			const originalBuffer = buffer;
			defer self.allocator.free(originalBuffer);
			buffer = try self.allocator.dupe(u8, originalBuffer[0..decodedValue.len]);
		}

		// Add value to params.
		try self.params.put(try self.allocator.dupe(u8, key), buffer);
	}

	/// Add a param to the routing result.
	pub fn addParam(self: *Self, key: []const u8, value: []const u8) !void
	{
		// Add value to params.
		try self.params.put(try self.allocator.dupe(u8, key), try self.allocator.dupe(u8, value));
	}

	/// Clone the given result to a new result pointer.
	pub fn clone(self: *Self) !*Self
	{
		const cloned = try Self.init(self.allocator, self.route, self.handler);
		cloned.params = try self.params.clone();
		cloned.notFoundHandler = self.notFoundHandler;
		cloned.preHandlers = try self.preHandlers.clone();
		cloned.postHandlers = try self.postHandlers.clone();
		cloned.errorHandlers = try self.errorHandlers.clone();
		return cloned;
	}

	/// Initialize a routing result.
	pub fn init(allocator: std.mem.Allocator, route: *RouteNode, handler: router.RouteHandler) !*Self
	{
		const obj = try allocator.create(Self);
		obj.* = .{
			.allocator = allocator,
			.route = route,
			.handler = handler,
			.params = RouteParamsMap.init(allocator),

			.preHandlers = std.ArrayList(router.RoutePreHandler).init(allocator),
			.postHandlers = std.ArrayList(router.RouteHandler).init(allocator),
			.notFoundHandler = handler,
			.errorHandlers = std.ArrayList(router.ErrorRouteHandler).init(allocator),
		};
		return obj;
	}
	/// Deinitialize a routing result.
	pub fn deinit(self: *Self) void
	{
		// Free params map values.
		var paramsIterator = self.params.iterator();
		while (paramsIterator.next()) |param|
		{ // Free every param.
			self.allocator.free(param.key_ptr.*);
			self.allocator.free(param.value_ptr.*);
		}
		// Free params map.
		self.params.deinit();

		// Free handlers list.
		self.preHandlers.deinit();
		self.postHandlers.deinit();
		self.errorHandlers.deinit();

		// Free current object.
		self.allocator.destroy(self);
	}
};

/// Route tree node data structure.
pub const RouteNode = struct {
	const Self = @This();

	/// Static children map type.
	const StaticChildren = std.StringHashMap(*RouteNode);
	/// Dynamic children array type.
	const DynamicChildren = std.ArrayList(*RouteNode);

	/// The used allocator.
	allocator: std.mem.Allocator,

	/// Route path part.
	node: []const u8,

	/// Static children (static nodes).
	staticChildren: *StaticChildren,

	/// Dynamic children (variable nodes).
	dynamicChildren: *DynamicChildren,

	/// Handle function, called when this route is reached.
	handle: ?router.RouteHandlerDefinition = null,

	/// Not found function, called when a child route was not found.
	handleNotFound: ?router.RouteHandler = null,

	/// Error function, called when a child route encountered an error.
	handleError: ?router.ErrorRouteHandler = null,

	/// Pre-handler function, called before handling this route or any children.
	preHandle: ?router.RoutePreHandler = null,

	/// Post-handler function, called after handling this route or any children.
	postHandle: ?router.RouteHandler = null,

	/// Find out if the route is static or dynamic.
	pub fn isDynamic(self: Self) bool
	{
		return self.node.len > 0 and self.node[0] == ':';
	}
	/// Find out if the route is static or dynamic.
	pub fn isStatic(self: Self) bool
	{
		return !self.isDynamic();
	}

	/// Add a child to the static or dynamic children, depending on its type.
	pub fn addChild(self: *Self, child: *RouteNode) !void
	{
		if (child.isStatic())
			{ // The child is static, adding it to the static children.
				try self.staticChildren.put(child.node, child);
			}
		else
			{ // The child is dynamic, adding it to the dynamic children.
				try self.dynamicChildren.append(child);
			}
	}

	/// Initialize and add a new child to the current route tree with the given node.
	pub fn newChild(self: *Self, node: []const u8) !*RouteNode
	{
		// Initialize the new child.
		const child = try self.allocator.create(Self);
		child.* = try Self.init(self.allocator, node);
		// Add the new child to the tree.
		try self.addChild(child);
		return child; // Return initialized child tree.
	}

	/// Parse a given route definition and add the required routes to the tree.
	pub fn parse(self: *Self, definition: router.RouteDefinition) !void
	{
		// Get a node candidate from the definition path.
		const nodeCandidate = std.mem.trim(u8, definition.path, " /");

		// If the path contains a "/", we need to parse recursively.
		if (std.mem.indexOf(u8, nodeCandidate, "/")) |pos|
			{
				// Get current child node.
				const childNode = nodeCandidate[0..pos];

				// Get child tree from current child node.
				var childTree: *RouteNode = undefined;
				if (self.staticChildren.get(childNode)) |existingChildTree|
					{ // A tree already exists for this node.
						childTree = existingChildTree;
					}
				else
					{ // There is no tree for this current node, initializing one.
						childTree = try self.newChild(childNode);
					}

				// The path is the rest of the node candidate.
				try childTree.parse(.{
					.path = nodeCandidate[pos+1..],
					.children = definition.children,
					.handle = definition.handle,
					.handleNotFound = definition.handleNotFound,
					.handleError = definition.handleError,
					.preHandle = definition.preHandle,
					.postHandle = definition.postHandle,
				});
			}
		else
			{ // No '/' in the path, so the path is a valid tree node, setting its value.
				var childTree = try self.newChild(nodeCandidate);
				childTree.handle = definition.handle;
				childTree.handleNotFound = definition.handleNotFound;
				childTree.handleError = definition.handleError;
				childTree.preHandle = definition.preHandle;
				childTree.postHandle = definition.postHandle;

				if (definition.children) |children|
					{ // If there are children, recursively parse them.
						for (children) |child|
						{ // For each child, parse it.
							try childTree.parse(child);
						}
					}
			}
	}

	/// Get request handler depending on the request method.
	pub fn getMethodHandler(self: Self, requestMethod: zap.http.Method) ?router.RouteHandler
	{
		if (self.handle) |handle|
		{ // A handle object is defined, getting the right handler from it.
			return switch (requestMethod)
			{ // Return the defined request handler from the request method.
				zap.http.Method.GET => handle.get orelse handle.any,
				zap.http.Method.POST => handle.post orelse handle.any,
				zap.http.Method.PATCH => handle.patch orelse handle.any,
				zap.http.Method.PUT => handle.put orelse handle.any,
				zap.http.Method.DELETE => handle.delete orelse handle.any,
				else => handle.any,
			};
		}
		else
		{ // Undefined request handler, no matter the request method.
			return null;
		}
	}

	/// Add pre, post, error and not found handlers, if defined.
	pub fn addHandlers(self: *Self, result: *RoutingResult) !void
	{
		if (self.handleNotFound) |handleNotFound|
			// Setting defined not found handler.
			result.notFoundHandler = handleNotFound;
		if (self.preHandle) |preHandle|
			// Appending defined pre-handler.
			try result.preHandlers.append(preHandle);
		if (self.postHandle) |postHandle|
			// Appending defined post-handler.
			try result.postHandlers.append(postHandle);
		if (self.handleError) |handleError|
			// Appending defined error handler.
			try result.errorHandlers.append(handleError);
	}

	/// Initialize a new routing result for the given route.
	/// Should be called on a route with a not found handler.
	pub fn newRoutingResult(self: *Self) !*RoutingResult
	{
		// Initialize a new routing result with the not found handler.
		const result = try RoutingResult.init(self.allocator, self, self.handleNotFound.?);

		// Add pre, post, error and not found handlers, if defined.
		try self.addHandlers(result);

		// Return the initialized routing result.
		return result;
	}

	/// Try to find a matching handler in the current route for the given path.
	/// Return true when a route is matching the request correctly.
	pub fn match(self: *Self, requestMethod: zap.http.Method, path: *std.mem.SplitIterator(u8, std.mem.DelimiterType.scalar), result: *RoutingResult) !bool
	{
		// Add pre, post, error and not found handlers, if defined.
		try self.addHandlers(result);

		if (path.next()) |nextPath|
			{ // Trying to follow the path by finding a matching children.
				if (self.staticChildren.get(nextPath)) |child|
				{ // There is a matching static child, continue to match the path on it.
					return try child.match(requestMethod, path, result);
				}

				const currentIndex = path.index;
				// No matching static child, trying dynamic children.
				for (self.dynamicChildren.items) |child|
				{ // For each dynamic child, trying to match it.
					// If no path can be found, try the next one.
					// Initialize a child routing result with the not found handler.
					const childResult = try RoutingResult.init(self.allocator, self, result.notFoundHandler);
					defer childResult.deinit();
					if (try child.match(requestMethod, path, childResult))
					{ // Handler has been found, final result is found.

						// Add an HTTP param to the result.
						try result.addHttpParam(child.node[1..], nextPath);

						// Copy the child result in the main result.
						{
							// Set child handlers in the main result.
							result.handler = childResult.handler;
							result.notFoundHandler = childResult.notFoundHandler;

							// Add child pre-handlers to the main result.
							for (childResult.preHandlers.items) |preHandler| {
								try result.preHandlers.append(preHandler);
							}
							// Add child post-handlers to the main result.
							for (childResult.postHandlers.items) |postHandler| {
								try result.postHandlers.append(postHandler);
							}
							// Add child error handlers to the main result.
							for (childResult.errorHandlers.items) |errorHandler| {
								try result.errorHandlers.append(errorHandler);
							}

							{ // Copy child params to the main result.
								var childResultParams = childResult.params.iterator();
								while (childResultParams.next()) |param|
								{ try result.addParam(param.key_ptr.*, param.value_ptr.*); }
							}
						}

						return true;
					}
					// Otherwise, we try the next one (-> rollback iterator and result).
					path.index = currentIndex; // Reset iterator index.
				}

				// No child match the current path part, set a not found handler.
				result.route = self;
				result.handler = self.handleNotFound orelse result.notFoundHandler;
				return false;
			}
		else
		{ // Path has ended, pointing at the current route.
			result.route = self;
			if (self.getMethodHandler(requestMethod)) |handler|
			{ // There is a handler, set it in the result.
				result.handler = handler;
				return true;
			}
			else
			{ // There is no handler, set a not found handler.
				result.handler = self.handleNotFound orelse result.notFoundHandler;
				return false;
			}
		}
	}


	/// Initialize a new route tree and its children.
	pub fn init(allocator: std.mem.Allocator, node: []const u8) !Self
	{
		// Allocating static children.
		const staticChildren = try allocator.create(Self.StaticChildren);
		staticChildren.* = Self.StaticChildren.init(allocator);
		// Allocating dynamic children.
		const dynamicChildren = try allocator.create(Self.DynamicChildren);
		dynamicChildren.* = Self.DynamicChildren.init(allocator);

		return .{
			.allocator = allocator,
			.node = try allocator.dupe(u8, node),
			.staticChildren = staticChildren,
			.dynamicChildren = dynamicChildren,
		};
	}
	/// Deinitialize the route tree and its children.
	pub fn deinit(self: *Self) void
	{
		// Free all children.
		var staticChildrenIterator = self.staticChildren.valueIterator();
		while (staticChildrenIterator.next()) |value|
		{ value.*.deinit(); self.allocator.destroy(value.*); }
		for (self.dynamicChildren.items) |value|
		{ value.deinit(); self.allocator.destroy(value); }

		// Free node name.
		self.allocator.free(self.node);

		// Free children map and array.
		self.staticChildren.deinit();
		self.allocator.destroy(self.staticChildren);
		self.dynamicChildren.deinit();
		self.allocator.destroy(self.dynamicChildren);
	}
};
