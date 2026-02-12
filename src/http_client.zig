//! Naive, unoptimized HTTP client with .get and .post methods. Simple, and not
//! particularly efficient. Response bodies stay allocated for the lifetime of
//! the client.

const std = @import("std");

gpa: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
client: std.http.Client,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) !Self {
    const arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();
    return .{
        .gpa = allocator,
        .arena = arena,
        .client = .{ .allocator = a },
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
) ![]u8 {
    var writer = try std.Io.Writer.Allocating.initCapacity(
        self.arena.allocator(),
        1024,
    );
    defer writer.deinit();
    _ = try self.client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &writer.writer,
        .headers = headers,
    });
    return try writer.toOwnedSlice();
}

pub fn post(
    self: *Self,
    url: []const u8,
    body: []const u8,
    headers: std.http.Client.Request.Headers,
) ![]u8 {
    var writer = try std.Io.Writer.Allocating.initCapacity(
        self.arena.allocator(),
        1024,
    );
    defer writer.deinit();
    _ = try self.client.fetch(.{
        .location = .{ .url = url },
        .response_writer = &writer.writer,
        .payload = body,
        .headers = headers,
    });
    return try writer.toOwnedSlice();
}
