const builtin = @import("builtin");
const std = @import("std");

pub const std_options: std.Options = .{
    .logFn = logFn,
};

var log_level = std.log.default_level;

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
    // TODO: Parse environment variables
    // TODO: Parse CLI flags
    // TODO: Download statistics to populate data structures
    // TODO: Output images from templates
}
