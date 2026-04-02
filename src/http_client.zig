//! Naive, unoptimized HTTP client with a .request method that wraps Zig's HTTP
//! client fetch. Simple, and not particularly efficient. Response bodies stay
//! allocated for the lifetime of the client.

const std = @import("std");

gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
client: std.http.Client,
bearer: []const u8,

const Self = @This();
const Response = struct { []const u8, std.http.Status };
const Request = struct {
    url: []const u8,
    body: ?[]const u8 = null,
    headers: std.http.Client.Request.Headers = .{},
    extra_headers: []const std.http.Header = &.{},
};

pub fn init(allocator: std.mem.Allocator, token: []const u8) !Self {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();
    return .{
        .gpa = allocator,
        .arena = arena,
        .client = .{ .allocator = a },
        .bearer = try std.fmt.allocPrint(a, "Bearer {s}", .{token}),
    };
}

pub fn deinit(self: *Self) void {
    self.client.deinit();
    self.arena.deinit();
    self.gpa.destroy(self.arena);
}

pub fn fetch(self: *Self, request: Request, retries: isize) !Response {
    if (retries <= -1) {
        return error.TooManyRetries;
    }

    var writer = try std.Io.Writer.Allocating.initCapacity(
        self.arena.allocator(),
        1024,
    );
    errdefer writer.deinit();
    const status = (try (self.client.fetch(.{
        .location = .{ .url = request.url },
        .response_writer = &writer.writer,
        .payload = request.body,
        .headers = request.headers,
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
            self.client = .{ .allocator = self.arena.allocator() };
            return self.fetch(request, retries - 1);
        },
        else => err,
    })).status;
    return .{ try writer.toOwnedSlice(), status };
}

pub fn graphql(
    self: *Self,
    body: []const u8,
    variables: anytype,
) !Response {
    var arena = std.heap.ArenaAllocator.init(self.arena.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    return try self.fetch(.{
        .url = "https://api.github.com/graphql",
        .body = try std.json.Stringify.valueAlloc(allocator, .{
            .query = body,
            .variables = variables,
        }, .{}),
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
