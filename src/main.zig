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
    overview_output_file: ?[]const u8 = null,
    languages_output_file: ?[]const u8 = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return try argparse.parse(allocator, Self, struct {
            fn errorCheck(a: Self, stderr: *std.Io.Writer) !bool {
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
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        if (self.api_key) |s| allocator.free(s);
        if (self.json_input_file) |s| allocator.free(s);
        if (self.json_output_file) |s| allocator.free(s);
        if (self.excluded_repos) |s| allocator.free(s);
        if (self.excluded_langs) |s| allocator.free(s);
        if (self.overview_output_file) |s| allocator.free(s);
        if (self.languages_output_file) |s| allocator.free(s);
    }
};

fn overview(arena: *std.heap.ArenaAllocator, stats: anytype) ![]const u8 {
    const a = arena.allocator();
    const template: []const u8 = @embedFile("templates/overview.svg");
    var out_data = template;
    inline for (@typeInfo(@TypeOf(stats)).@"struct".fields) |field| {
        switch (@typeInfo(field.type)) {
            .int => {
                out_data = try std.mem.replaceOwned(
                    u8,
                    a,
                    out_data,
                    "{{ " ++ field.name ++ " }}",
                    try decimalToString(a, @field(stats, field.name)),
                );
            },
            .pointer => {
                out_data = try std.mem.replaceOwned(
                    u8,
                    a,
                    out_data,
                    "{{ " ++ field.name ++ " }}",
                    @field(stats, field.name),
                );
            },
            .@"struct" => {},
            else => comptime unreachable,
        }
    }
    return out_data;
}

fn languages(arena: *std.heap.ArenaAllocator, stats: anytype) ![]const u8 {
    const a = arena.allocator();
    const template: []const u8 = @embedFile("templates/languages.svg");
    const progress = try a.alloc([]const u8, stats.languages.count());
    const lang_list = try a.alloc([]const u8, stats.languages.count());
    for (
        stats.languages.keys(),
        stats.languages.values(),
        progress,
        lang_list,
        0..,
    ) |language, count, *progress_s, *lang_s, i| {
        const color = stats.language_colors.get(language);
        const percent =
            100 * if (stats.languages_total == 0)
                0.0
            else
                @as(f64, @floatFromInt(count)) /
                    @as(f64, @floatFromInt(stats.languages_total));
        progress_s.* = try std.fmt.allocPrint(a,
            \\<span style="
            \\  background-color: {s}; 
            \\  width: {d:.3}%;
            \\" class="progress-item"></span>
        , .{ color orelse "#000", percent });
        lang_s.* = try std.fmt.allocPrint(a,
            \\<li style="animation-delay: {d}ms;">
            \\  <svg 
            \\      xmlns="http://www.w3.org/2000/svg" 
            \\      class="octicon"
            \\      style="fill: {s};" 
            \\      viewBox="0 0 16 16" 
            \\      version="1.1" 
            \\      width="16" 
            \\      height="16"
            \\  ><path 
            \\      fill-rule="evenodd" 
            \\      d="M8 4a4 4 0 100 8 4 4 0 000-8z"
            \\  ></path></svg>
            \\  <span class="lang">{s}</span>
            \\  <span class="percent">{d:.2}%</span>
            \\</li>
            \\
        , .{ (i + 1) * 150, color orelse "#000", language, percent });
    }
    return try std.mem.replaceOwned(u8, a, try std.mem.replaceOwned(
        u8,
        a,
        template,
        "{{ lang_list }}",
        try std.mem.concat(a, u8, lang_list),
    ), "{{ progress }}", try std.mem.concat(a, u8, progress));
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try Args.init(allocator);
    defer args.deinit(allocator);
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
        const data = try readFile(allocator, path);
        defer allocator.free(data);
        stats = try Statistics.initFromJson(allocator, data);
    } else if (args.api_key) |api_key| {
        std.log.info("Collecting statistics from GitHub API", .{});
        var client: HttpClient = try .init(allocator, api_key);
        defer client.deinit();
        stats = try Statistics.init(&client, allocator);
    } else unreachable;
    defer stats.deinit(allocator);

    if (args.json_output_file) |path| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try writeFile(
            path,
            try std.json.Stringify.valueAlloc(
                arena.allocator(),
                stats,
                .{ .whitespace = .indent_2 },
            ),
        );
    }

    var aggregate_stats: struct {
        languages: std.StringArrayHashMap(u64),
        language_colors: std.StringArrayHashMap([]const u8),
        contributions: usize,
        name: []const u8,
        languages_total: usize = 0,
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
        .language_colors = .init(allocator),
        .name = stats.name,
    };
    defer aggregate_stats.languages.deinit();
    defer aggregate_stats.language_colors.deinit();
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
            if (language.color) |color| {
                try aggregate_stats.language_colors.put(language.name, color);
            }
            var total = aggregate_stats.languages.get(language.name) orelse 0;
            total += language.size;
            try aggregate_stats.languages.put(language.name, total);
            aggregate_stats.languages_total += language.size;
        };
    }
    aggregate_stats.languages.sort(struct {
        values: @TypeOf(aggregate_stats.languages.values()),
        pub fn lessThan(self: @This(), a: usize, b: usize) bool {
            // Sort in reverse order
            return self.values[a] > self.values[b];
        }
    }{ .values = aggregate_stats.languages.values() });

    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        try writeFile(
            args.overview_output_file orelse "overview.svg",
            try overview(&arena, aggregate_stats),
        );

        try writeFile(
            args.languages_output_file orelse "languages.svg",
            try languages(&arena, aggregate_stats),
        );
    }
}

test {
    std.testing.refAllDecls(@This());
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    std.log.info("Reading data from '{s}'", .{path});
    const in =
        if (std.mem.eql(u8, path, "-"))
            std.fs.File.stdin()
        else
            try std.fs.cwd().openFile(path, .{});
    defer if (!std.mem.eql(u8, path, "-")) in.close();
    var read_buffer: [64 * 1024]u8 = undefined;
    var reader = in.reader(&read_buffer);
    return try (&reader.interface).allocRemaining(allocator, .unlimited);
}

fn writeFile(
    path: []const u8,
    data: []const u8,
) !void {
    std.log.info("Writing data to '{s}'", .{path});
    const out =
        if (std.mem.eql(u8, path, "-"))
            std.fs.File.stdout()
        else
            try std.fs.cwd().createFile(path, .{});
    defer if (!std.mem.eql(u8, path, "-")) out.close();
    var write_buffer: [64 * 1024]u8 = undefined;
    var writer = out.writer(&write_buffer);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

fn decimalToString(allocator: std.mem.Allocator, n: anytype) ![]const u8 {
    const info = @typeInfo(@TypeOf(n));
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Only implemented for unsigned integers.");
    }

    const s = try std.fmt.allocPrint(allocator, "{d}", .{n});
    defer allocator.free(s);
    const digits = s.len;
    const commas = (digits - 1) / 3;
    const result = try allocator.alloc(u8, digits + commas);
    errdefer comptime unreachable;

    var i: usize = result.len - 1;
    var j: usize = s.len - 1;
    while (true) {
        if ((result.len - i) % 4 == 0) {
            result[i] = ',';
            i -= 1;
        }
        result[i] = s[j];
        if (i == 0 and j == 0) {
            break;
        } else if (i > 0 and j > 0) {} else unreachable;
        i -= 1;
        j -= 1;
    }
    return result;
}
