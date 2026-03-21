const builtin = @import("builtin");
const std = @import("std");
const argparse = @import("argparse.zig");
const glob = @import("glob.zig");

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

const Args = struct {
    api_key: []const u8,
    json_output_file: ?[]const u8 = null,
    silent: bool = false,
    verbose: bool = false,

    pub fn deinit(self: @This()) void {
        allocator.free(self.api_key);
        if (self.json_output_file) |output| allocator.free(output);
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    const args = try argparse.parse(allocator, Args);
    defer args.deinit();
    if (args.silent) {
        log_level = .err;
    } else if (args.verbose) {
        log_level = .debug;
    }

    var client: HttpClient = try .init(allocator, args.api_key);
    defer client.deinit();
    const stats = try Statistics.init(&client, allocator);
    defer stats.deinit();

    if (args.json_output_file) |path| {
        const out =
            if (std.mem.eql(u8, path, "-"))
                std.fs.File.stdout()
            else
                try std.fs.cwd().createFile(path, .{});
        defer out.close();
        var write_buffer: [64 * 1024]u8 = undefined;
        var writer = out.writer(&write_buffer);

        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try writer.interface.writeAll(
            try std.json.Stringify.valueAlloc(
                arena.allocator(),
                stats,
                .{ .whitespace = .indent_2 },
            ),
        );
        try writer.interface.flush();
    }

    // TODO: Output images from templates
    _ = glob;
}

test {
    std.testing.refAllDecls(@This());
}
