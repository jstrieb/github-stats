const builtin = @import("builtin");
const std = @import("std");

const HttpClient = @import("http_client.zig");
const Statistics = @import("statistics.zig");

pub const std_options: std.Options = .{
    .logFn = logFn,
};

var log_level: std.log.Level = switch (builtin.mode) {
    .Debug => .debug,
    else => .warn,
};
var allocator: std.mem.Allocator = undefined;
var user: []const u8 = undefined;

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

    var client: HttpClient = try .init(
        allocator,
        "",
    );
    user = "";
    defer client.deinit();
    const stats = try Statistics.init(&client, user, allocator);
    defer stats.deinit();
    print(stats);

    // TODO: Output images from templates
}

// TODO: Remove
fn print(x: anytype) void {
    if (builtin.mode != .Debug) {
        @compileError("Do not use JSON print in real code!");
    }
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    std.debug.print("{s}\n", .{
        std.json.Stringify.valueAlloc(
            arena.allocator(),
            x,
            .{ .whitespace = .indent_2 },
        ) catch unreachable,
    });
}
