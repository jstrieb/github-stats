const builtin = @import("builtin");
const std = @import("std");

pub const std_options: std.Options = .{
    .logFn = logFn,
};

var log_level = std.log.default_level;
var allocator: std.mem.Allocator = undefined;

fn logFn(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (@intFromEnum(message_level) <= @intFromEnum(log_level)) {
        std.log.defaultLog(message_level, scope, format, args);
    }
}

/// Naive, unoptimized HTTP client with .get and .post methods. Simple, and not
/// particularly efficient.
const Client = struct {
    client: std.http.Client,

    const Self = @This();

    pub fn init() Self {
        return .{
            .client = .{ .allocator = allocator },
        };
    }

    pub fn deinit(self: *Self) void {
        self.client.deinit();
    }

    pub fn get(
        self: *Self,
        url: []const u8,
        headers: ?std.http.Client.Request.Headers,
    ) ![]u8 {
        var writer = try std.Io.Writer.Allocating.initCapacity(allocator, 1024);
        defer writer.deinit();
        _ = try self.client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &writer.writer,
            .headers = headers orelse .{},
        });
        return try writer.toOwnedSlice();
    }

    pub fn post(
        self: *Self,
        url: []const u8,
        body: []const u8,
        headers: ?std.http.Client.Request.Headers,
    ) ![]u8 {
        var writer = try std.Io.Writer.Allocating.initCapacity(allocator, 1024);
        defer writer.deinit();
        _ = try self.client.fetch(.{
            .location = .{ .url = url },
            .response_writer = &writer.writer,
            .payload = body,
            .headers = headers orelse .{},
        });
        return try writer.toOwnedSlice();
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    // TODO: Parse environment variables
    // TODO: Parse CLI flags

    var client: Client = .init();
    defer client.deinit();
    var body = try client.get("https://jstrieb.github.io", null);
    std.log.debug("{s}\n", .{body[0..100]});
    allocator.free(body);

    body = try client.post(
        "https://httpbin.org/post",
        "{\"a\": 10, \"b\": [ 1, 2, 3 ]}",
        .{ .content_type = .{ .override = "application/json" } },
    );
    defer allocator.free(body);
    std.log.debug("{s}\n", .{body});

    // TODO: Download statistics to populate data structures

    // TODO: Output images from templates
}
