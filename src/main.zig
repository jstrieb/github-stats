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

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    // TODO: Parse environment variables
    // TODO: Parse CLI flags

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();
    var writer = std.Io.Writer.Allocating.init(allocator);
    defer writer.deinit();
    _ = try client.fetch(.{
        .location = .{ .url = "https://jstrieb.github.io" },
        .response_writer = &writer.writer,
    });
    const body = try writer.toOwnedSlice();
    defer allocator.free(body);

    // TODO: Download statistics to populate data structures

    // TODO: Output images from templates
}
