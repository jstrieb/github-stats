const builtin = @import("builtin");
const std = @import("std");

const HttpClient = @import("http_client.zig");

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

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    // TODO: Parse environment variables
    // TODO: Parse CLI flags

    var client: HttpClient = try .init(allocator);
    defer client.deinit();
    std.log.debug("{s}\n", .{
        try client.get("https://jstrieb.github.io", .{}),
    });
    std.log.debug("{s}\n", .{
        try client.post(
            "https://httpbin.org/post",
            "{\"a\": 10, \"b\": [ 1, 2, 3 ]}",
            .{ .content_type = .{ .override = "application/json" } },
        ),
    });

    // TODO: Download statistics to populate data structures
    // TODO: Output images from templates
}
