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

fn years(client: *HttpClient) ![]u32 {
    const response = try client.graphql(
        \\query {
        \\  viewer {
        \\    contributionsCollection {
        \\      contributionYears
        \\    }
        \\  }
        \\}
    );
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const r = try std.json.parseFromSliceLeaky(
        struct { data: struct { viewer: struct {
            contributionsCollection: struct {
                contributionYears: []u32,
            },
        } } },
        arena.allocator(),
        response,
        .{ .ignore_unknown_fields = true },
    );
    return try allocator.dupe(
        u32,
        r.data.viewer.contributionsCollection.contributionYears,
    );
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    // TODO: Parse environment variables
    // TODO: Parse CLI flags

    var client: HttpClient = try .init(
        allocator,
        "TODO",
    );
    defer client.deinit();
    const y = try years(&client);
    defer allocator.free(y);
    std.debug.print("{any}\n", .{y});

    // TODO: Download statistics to populate data structures
    // TODO: Output images from templates
}
