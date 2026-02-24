//! Naive, unoptimized HTTP client with .get and .post methods. Simple, and not
//! particularly efficient. Response bodies stay allocated for the lifetime of
//! the client.

const std = @import("std");

gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
client: std.http.Client,
bearer: []const u8,
last_request: ?i64 = null,

const Self = @This();
const Response = struct { []const u8, std.http.Status };
const KEEP_ALIVE_TIMEOUT: i64 = 16;

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

pub fn get(
    self: *Self,
    url: []const u8,
    headers: std.http.Client.Request.Headers,
    extra_headers: []const std.http.Header,
) !Response {
    var writer = try std.Io.Writer.Allocating.initCapacity(
        self.arena.allocator(),
        1024,
    );
    defer writer.deinit();
    const now = std.time.timestamp();
    const status = (try self.client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &writer.writer,
        .headers = headers,
        .extra_headers = extra_headers,
        // Work around failures from keep alive connections closing after
        // timeout and not being automatically reopened by Zig
        .keep_alive = if (self.last_request) |last|
            now - last > KEEP_ALIVE_TIMEOUT
        else
            true,
    })).status;
    self.last_request = now;
    return .{ try writer.toOwnedSlice(), status };
}

pub fn post(
    self: *Self,
    url: []const u8,
    body: []const u8,
    headers: std.http.Client.Request.Headers,
) !Response {
    var writer = try std.Io.Writer.Allocating.initCapacity(
        self.arena.allocator(),
        1024,
    );
    defer writer.deinit();
    const now = std.time.timestamp();
    const status = (try self.client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &writer.writer,
        .payload = body,
        .headers = headers,
        // Work around failures from keep alive connections closing after
        // timeout and not being automatically reopened by Zig
        .keep_alive = if (self.last_request) |last|
            now - last > KEEP_ALIVE_TIMEOUT
        else
            true,
    })).status;
    self.last_request = now;
    return .{ try writer.toOwnedSlice(), status };
}

const Query = struct {
    query: []const u8,
    variables: ?[]const u8,
};

pub fn graphql(
    self: *Self,
    body: []const u8,
    variables: ?[]const u8,
) !Response {
    var arena = std.heap.ArenaAllocator.init(self.arena.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();
    return try self.post(
        "https://api.github.com/graphql",
        try std.json.Stringify.valueAlloc(allocator, Query{
            .query = body,
            .variables = variables,
        }, .{}),
        .{
            .authorization = .{ .override = self.bearer },
            .content_type = .{ .override = "application/json" },
        },
    );
}

pub fn rest(
    self: *Self,
    url: []const u8,
) !Response {
    return try self.get(
        url,
        .{
            .authorization = .{ .override = self.bearer },
            .content_type = .{ .override = "application/json" },
        },
        &.{.{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" }},
    );
}
