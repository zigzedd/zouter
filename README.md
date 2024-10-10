<h1 align="center">
	Zouter
</h1>

<h4 align="center">
	<a href="https://code.zeptotech.net/zedd/zouter">Documentation</a>
|
	<a href="https://zedd.zeptotech.net/zouter/api">API</a>
</h4>

<p align="center">
	Zig HTTP router library
</p>

Zouter is part of [_zedd_](https://code.zeptotech.net/zedd), a collection of useful libraries for zig.

## Zouter for zap

_Zouter_ is an HTTP router library for Zig **zap** HTTP server. It's made to ease the use of **zap** to build REST APIs.

## Versions

Zouter 0.1.0 is made for zig 0.13.0 and tested with zap 0.8.0.

## How to use

### Install

In your project directory:

```shell
$ zig fetch --save https://code.zeptotech.net/zedd/zouter/archive/v0.1.0.tar.gz
```

In `build.zig`:

```zig
// Add zouter dependency.
const zouter = b.dependency("zouter", .{
	.target = target,
	.optimize = optimize,
});
exe.root_module.addImport("zouter", zdotenv.module("zouter"));
```

### Example

Here is a quick example of how to set up a router. It is an extract from the full test code at [`example.zig`](https://code.zeptotech.net/zedd/zouter/src/branch/main/tests/example.zig). You may want to have a look to [`simple_routes.zig`](https://code.zeptotech.net/zedd/zouter/src/branch/main/tests/simple_routes.zig) which shows more advanced features.

```zig
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
```

### Route definition

A route only has one mandatory field: its path. If any part of a path starts with a `':'`, the value is taken as a dynamic variable, retrievable later with `Route.params` `HashMap`.

A route can have:

- **Children**: sub-routes definitions, with a `'/'` between the parent and the child. It's useful to prefix a list of routes with the same path / variable.
- **Handle object**: you can define a handle function for each HTTP basic request method. If you don't care about the request method, there is an `any` field which will be used for all undefined request methods.
- **Handle not found / error**: you can define a custom functions to handle errors or not found pages inside this path.
- **Pre-handle / post-handle**: these functions are started before and after the request handling in this path. It looks like middlewares and can assume the same role as most of them (e.g. a pre-handle function to check for authentication under a specific path).

Full details about route definition fields can be found in the [API reference](https://zedd.zeptotech.net/zouter/api).
