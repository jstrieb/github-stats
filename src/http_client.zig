//! Naive, unoptimized HTTP client with a .request method that wraps Zig's HTTP
//! client fetch. Simple, and not particularly efficient. Response bodies stay
//! allocated for the lifetime of the client.

const std = @import("std");

allocator: std.mem.Allocator,
client: std.http.Client,
bearer: []const u8,

const Self = @This();
const Response = struct {
    body: []const u8,
    status: std.http.Status,
};
const Request = struct {
    url: []const u8,
    body: ?[]const u8 = null,
    headers: std.http.Client.Request.Headers = .{},
    extra_headers: []const std.http.Header = &.{},
};

pub fn init(allocator: std.mem.Allocator, token: []const u8) !Self {
    return .{
        .allocator = allocator,
        .client = .{ .allocator = allocator },
        .bearer = try std.fmt.allocPrint(allocator, "Bearer {s}", .{token}),
    };
}

pub fn deinit(self: *Self) void {
    self.client.deinit();
    self.allocator.free(self.bearer);
}

pub fn fetch(self: *Self, request: Request, retries: isize) !Response {
    if (retries <= -1) {
        return error.TooManyRetries;
    }

    var writer =
        try std.Io.Writer.Allocating.initCapacity(self.allocator, 1024);
    errdefer writer.deinit();
    const status = (try (self.client.fetch(.{
        .location = .{ .url = request.url },
        .response_writer = &writer.writer,
        .payload = request.body,
        .headers = request.headers,
        .extra_headers = request.extra_headers,
    }) catch |err| switch (err) {
        error.HttpConnectionClosing => {
            // Handle a Zig HTTP bug where keep-alive connections are closed by
            // the server after a timeout, but the client doesn't handle it
            // properly. For now we nuke the whole client (and associated
            // connection pool) and make a new one, but there might be a better
            // way to handle this.
            std.log.debug(
                "Keep alive connection closed. Initializing a new client.",
                .{},
            );
            self.client.deinit();
            self.client = .{ .allocator = self.allocator };
            writer.deinit();
            return self.fetch(request, retries - 1);
        },
        else => err,
    })).status;
    return .{
        .body = try writer.toOwnedSlice(),
        .status = status,
    };
}

pub fn graphql(
    self: *Self,
    body: []const u8,
    variables: anytype,
) !Response {
    const serialized = try std.json.Stringify.valueAlloc(self.allocator, .{
        .query = body,
        .variables = variables,
    }, .{});
    defer self.allocator.free(serialized);
    return try self.fetch(.{
        .url = "https://api.github.com/graphql",
        .body = serialized,
        .headers = .{
            .authorization = .{ .override = self.bearer },
            .content_type = .{ .override = "application/json" },
        },
    }, 8);
}

pub fn rest(
    self: *Self,
    url: []const u8,
) !Response {
    return try self.fetch(.{
        .url = url,
        .headers = .{
            .authorization = .{ .override = self.bearer },
            .content_type = .{ .override = "application/json" },
        },
        .extra_headers = &.{
            .{ .name = "X-GitHub-Api-Version", .value = "2026-03-10" },
        },
    }, 8);
}
