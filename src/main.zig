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
    api_key: ?[]const u8 = null,
    json_input_file: ?[]const u8 = null,
    json_output_file: ?[]const u8 = null,
    silent: bool = false,
    verbose: bool = false,
    excluded_repos: ?[]const u8 = null,
    excluded_langs: ?[]const u8 = null,
    exclude_private: bool = false,

    pub fn deinit(self: @This()) void {
        if (self.api_key) |s| allocator.free(s);
        if (self.json_input_file) |s| allocator.free(s);
        if (self.json_output_file) |s| allocator.free(s);
        if (self.excluded_repos) |s| allocator.free(s);
        if (self.excluded_langs) |s| allocator.free(s);
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    const args = try argparse.parse(allocator, Args, struct {
        fn errorCheck(a: Args, stderr: *std.Io.Writer) !bool {
            if (a.api_key == null and a.json_input_file == null) {
                try stderr.print(
                    "You must pass either an input file or an API key.\n",
                    .{},
                );
                return false;
            }
            return true;
        }
    }.errorCheck);
    defer args.deinit();
    if (args.silent) {
        log_level = .err;
    } else if (args.verbose) {
        log_level = .debug;
    }
    const excluded_repos = if (args.excluded_repos) |excluded| excluded: {
        var list = try std.ArrayList([]const u8).initCapacity(allocator, 16);
        errdefer list.deinit(allocator);
        var iterator = std.mem.tokenizeAny(u8, excluded, ", \t\r\n|\"'\x00");
        while (iterator.next()) |pattern| {
            try list.append(allocator, pattern);
        }
        break :excluded try list.toOwnedSlice(allocator);
    } else null;
    defer if (excluded_repos) |excluded| allocator.free(excluded);
    const excluded_langs = if (args.excluded_langs) |excluded| excluded: {
        var list = try std.ArrayList([]const u8).initCapacity(allocator, 16);
        errdefer list.deinit(allocator);
        var iterator = std.mem.tokenizeAny(u8, excluded, ",\t\r\n|\"'\x00");
        while (iterator.next()) |pattern| {
            try list.append(allocator, std.mem.trim(u8, pattern, " "));
        }
        break :excluded try list.toOwnedSlice(allocator);
    } else null;
    defer if (excluded_langs) |excluded| allocator.free(excluded);

    var stats: Statistics = undefined;
    if (args.json_input_file) |path| {
        std.log.info("Reading statistics from '{s}'", .{path});
        const in =
            if (std.mem.eql(u8, path, "-"))
                std.fs.File.stdin()
            else
                try std.fs.cwd().openFile(path, .{});
        defer in.close();
        var read_buffer: [64 * 1024]u8 = undefined;
        var reader = in.reader(&read_buffer);
        // TODO: Create a scanner from the reader instead of reading the whole
        // file into memory
        const data =
            try (&reader.interface).allocRemaining(allocator, .unlimited);
        defer allocator.free(data);
        stats = try Statistics.initFromJson(allocator, data);
    } else if (args.api_key) |api_key| {
        std.log.info("Collecting statistics from GitHub API", .{});
        var client: HttpClient = try .init(allocator, api_key);
        defer client.deinit();
        stats = try Statistics.init(&client, allocator);
    } else unreachable;
    defer stats.deinit();

    if (args.json_output_file) |path| {
        std.log.info("Writing raw JSON data to '{s}'", .{path});
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

    var aggregate_stats: struct {
        languages: std.StringArrayHashMap(u64),
        contributions: usize,
        stars: usize = 0,
        forks: usize = 0,
        lines_changed: usize = 0,
        views: usize = 0,
        repos: usize = 0,
    } = .{
        .contributions = stats.repo_contributions +
            stats.issue_contributions +
            stats.commit_contributions +
            stats.pr_contributions +
            stats.review_contributions,
        .languages = .init(allocator),
    };
    defer aggregate_stats.languages.deinit();
    for (stats.repositories) |repository| {
        if (glob.matchAny(excluded_repos orelse &.{}, repository.name) or
            (args.exclude_private and repository.private))
        {
            continue;
        }
        aggregate_stats.stars += repository.stars;
        aggregate_stats.forks += repository.forks;
        aggregate_stats.lines_changed += repository.lines_changed;
        aggregate_stats.views += repository.views;
        aggregate_stats.repos += 1;
        if (repository.languages) |langs| for (langs) |language| {
            if (glob.matchAny(excluded_langs orelse &.{}, language.name)) {
                continue;
            }
            var total = aggregate_stats.languages.get(language.name) orelse 0;
            total += language.size;
            try aggregate_stats.languages.put(language.name, total);
        };
    }

    inline for (@typeInfo(@TypeOf(aggregate_stats)).@"struct".fields) |field| {
        if (!std.mem.eql(u8, field.name, "languages")) {
            std.debug.print("{s}: {any}\n", .{
                field.name,
                @field(aggregate_stats, field.name),
            });
        }
    }
    std.debug.print("\n", .{});

    for (
        aggregate_stats.languages.keys(),
        aggregate_stats.languages.values(),
    ) |key, value| {
        std.debug.print("{s}: {any}\n", .{ key, value });
    }
}

test {
    std.testing.refAllDecls(@This());
}
