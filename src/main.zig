const builtin = @import("builtin");
const std = @import("std");
const version = @import("options").version;

const argparse = @import("argparse.zig");
const glob = @import("glob.zig");
const templateFill = @import("template.zig").fill;

const HttpClient = @import("http_client.zig");
const Statistics = @import("statistics.zig");

pub const std_options: std.Options = .{
    .logFn = logFn,
    // Even though we change it later, this is necessary to ensure that debug
    // logs aren't stripped in release builds.
    .log_level = .debug,
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

const embedded_overview_template = @embedFile("templates/overview.svg");
const embedded_languages_template = @embedFile("templates/languages.svg");

const Args = struct {
    access_token: ?[]const u8 = null,
    org_access_tokens: ?[]const u8 = null,
    json_input_file: ?[]const u8 = null,
    json_output_file: ?[]const u8 = null,
    silent: bool = false,
    debug: bool = false,
    verbose: bool = false,
    exclude_repos: ?[]const u8 = null,
    excluded: ?[]const u8 = null,
    exclude_langs: ?[]const u8 = null,
    excluded_langs: ?[]const u8 = null,
    exclude_private: bool = false,
    exclude_forked_repos: bool = false,
    owned_only_stars_forks: bool = false,
    overview_output_file: ?[]const u8 = null,
    languages_output_file: ?[]const u8 = null,
    overview_template: ?[]const u8 = null,
    languages_template: ?[]const u8 = null,
    max_retries: ?usize = 25,
    max_runtime_seconds: ?u64 = null,
    github_stats_max_runtime_seconds: ?u64 = null,
    repo_stats_cache_file: ?[]const u8 = null,
    version: bool = false,
    dump_overview_template: ?[]const u8 = null,
    dump_languages_template: ?[]const u8 = null,

    const Self = @This();

    pub fn init(main_init: std.process.Init) !Self {
        return try argparse.parse(main_init, Self, struct {
            fn errorCheck(a: Self, stderr: *std.Io.Writer) !bool {
                if ((a.access_token == null or a.access_token.?.len == 0) and
                    a.json_input_file == null and !a.version)
                {
                    try stderr.print(
                        "You must pass an input file or a GitHub token.\n",
                        .{},
                    );
                    return false;
                }
                return true;
            }
        }.errorCheck);
    }

    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        inline for (@typeInfo(Self).@"struct".fields) |field| {
            switch (@typeInfo(field.type)) {
                .optional => |optional| {
                    switch (@typeInfo(optional.child)) {
                        .pointer => |pointer| switch (pointer.size) {
                            .slice => if (@field(self, field.name)) |p|
                                allocator.free(p),
                            else => comptime unreachable,
                        },
                        .bool, .int => {},
                        else => comptime unreachable,
                    }
                },
                .pointer => |p| switch (p.size) {
                    .slice => allocator.free(@field(self, field.name)),
                    else => comptime unreachable,
                },
                .bool, .int => {},
                else => comptime unreachable,
            }
        }
    }
};

fn overview(
    arena: *std.heap.ArenaAllocator,
    stats: anytype,
    template: []const u8,
) ![]const u8 {
    const a = arena.allocator();
    return templateFill(a, template, stats);
}

fn languages(
    arena: *std.heap.ArenaAllocator,
    stats: anytype,
    template: []const u8,
) ![]const u8 {
    const a = arena.allocator();
    const progress = try a.alloc([]const u8, stats.languages.count());
    const lang_list = try a.alloc([]const u8, stats.languages.count());
    for (
        stats.languages.keys(),
        stats.languages.values(),
        progress,
        lang_list,
    ) |language, count, *progress_s, *lang_s| {
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
            \\<li>
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
        , .{ color orelse "#000", language, percent });
    }
    return templateFill(
        a,
        template,
        struct { lang_list: []const u8, progress: []const u8 }{
            .lang_list = try std.mem.concat(a, u8, lang_list),
            .progress = try std.mem.concat(a, u8, progress),
        },
    );
}

const AggregateStats = struct {
    languages: std.array_hash_map.String(u64),
    language_colors: std.array_hash_map.String([]const u8),
    contributions: usize,
    name: []const u8,
    languages_total: u64 = 0,
    stars: usize = 0,
    forks: usize = 0,
    lines_changed: usize = 0,
    views: usize = 0,
    repos: usize = 0,

    fn deinit(self: *AggregateStats, allocator: std.mem.Allocator) void {
        self.languages.deinit(allocator);
        self.language_colors.deinit(allocator);
    }
};

fn aggregateStats(
    allocator: std.mem.Allocator,
    stats: anytype,
    exclude_repos: []const []const u8,
    exclude_langs: []const []const u8,
    exclude_private: bool,
    owned_only_stars_forks: bool,
) !AggregateStats {
    var aggregate_stats: AggregateStats = .{
        .contributions = stats.repo_contributions +
            stats.issue_contributions +
            stats.commit_contributions +
            stats.pr_contributions +
            stats.review_contributions,
        .languages = try .init(allocator, &.{}, &.{}),
        .language_colors = try .init(allocator, &.{}, &.{}),
        .name = stats.name,
    };
    errdefer aggregate_stats.deinit(allocator);

    for (stats.repositories) |repository| {
        if (glob.matchAny(exclude_repos, repository.name) or
            (exclude_private and repository.private))
        {
            continue;
        }
        if (!owned_only_stars_forks or repository.owned) {
            aggregate_stats.stars += repository.stars;
            aggregate_stats.forks += repository.forks;
        }
        aggregate_stats.lines_changed += repository.lines_changed;
        aggregate_stats.views += repository.views;
        aggregate_stats.repos += 1;

        if (repository.contribution_languages) |langs| for (langs) |language| {
            try addAggregateLanguage(
                allocator,
                &aggregate_stats,
                exclude_langs,
                language.name,
                language.color,
                language.lines_changed,
            );
        };
    }

    aggregate_stats.languages.sort(struct {
        values: @TypeOf(aggregate_stats.languages.values()),
        pub fn lessThan(self: @This(), a: usize, b: usize) bool {
            // Sort in reverse order
            return self.values[a] > self.values[b];
        }
    }{ .values = aggregate_stats.languages.values() });
    return aggregate_stats;
}

fn addAggregateLanguage(
    allocator: std.mem.Allocator,
    aggregate_stats: *AggregateStats,
    exclude_langs: []const []const u8,
    name: []const u8,
    color: ?[]const u8,
    value: u64,
) !void {
    if (value == 0 or glob.matchAny(exclude_langs, name)) {
        return;
    }
    if (color) |c| {
        try aggregate_stats.language_colors.put(allocator, name, c);
    }
    var total = aggregate_stats.languages.get(name) orelse 0;
    total += value;
    try aggregate_stats.languages.put(allocator, name, total);
    aggregate_stats.languages_total += value;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    const args = try Args.init(init);
    defer args.deinit(allocator);
    if (args.silent) {
        log_level = .err;
    } else if (args.debug) {
        log_level = .debug;
    } else if (args.verbose) {
        log_level = .info;
    }

    if (args.version) {
        const stdout = std.Io.File.stdout();
        var writer = stdout.writer(io, &.{});
        try writer.interface.print(
            \\GitHub Stats version {s}
            \\https://github.com/jstrieb/github-stats
            \\Created by Jacob Strieb
            \\
        , .{version});
        return;
    }

    if (args.dump_overview_template) |path| {
        try writeFile(io, path, embedded_overview_template);
        return;
    }

    if (args.dump_languages_template) |path| {
        try writeFile(io, path, embedded_languages_template);
        return;
    }

    const exclude_repos =
        if (args.exclude_repos orelse args.excluded) |exclude|
            try splitList(allocator, exclude, " ,\t\r\n|\"'\x00")
        else
            null;
    defer if (exclude_repos) |exclude| allocator.free(exclude);
    const exclude_langs =
        if (args.exclude_langs orelse args.excluded_langs) |exclude|
            try splitList(allocator, exclude, ",\t\r\n|\"'\x00")
        else
            null;
    defer if (exclude_langs) |exclude| allocator.free(exclude);

    var stats: Statistics = if (args.json_input_file) |path| stats: {
        const data = try readFile(allocator, io, path);
        defer allocator.free(data);
        break :stats try Statistics.initFromJson(allocator, data);
    } else if (args.access_token) |access_token| stats: {
        std.log.info("Collecting statistics from GitHub API", .{});
        var client: HttpClient = try .init(allocator, io, access_token);
        defer client.deinit();

        const org_tokens =
            if (args.org_access_tokens) |tokens|
                try splitList(allocator, tokens, " ,\t\r\n")
            else
                try allocator.alloc([]const u8, 0);
        defer allocator.free(org_tokens);
        const org_clients = try allocator.alloc(HttpClient, org_tokens.len);
        defer allocator.free(org_clients);
        const org_client_pointers =
            try allocator.alloc(*HttpClient, org_tokens.len);
        defer allocator.free(org_client_pointers);
        var org_clients_initialized: usize = 0;
        defer for (org_clients[0..org_clients_initialized]) |*c| c.deinit();
        for (org_tokens, org_clients, org_client_pointers) |token, *c, *p| {
            c.* = try .init(allocator, io, token);
            org_clients_initialized += 1;
            p.* = c;
        }
        if (org_tokens.len > 0) {
            std.log.info(
                "Using {d} organization installation token{s}",
                .{ org_tokens.len, if (org_tokens.len != 1) "s" else "" },
            );
        }

        break :stats Statistics.init(
            &client,
            allocator,
            io,
            .{
                .max_retries = args.max_retries,
                .cache_file = args.repo_stats_cache_file orelse
                    "generated/repo_stats_cache.json",
                .max_runtime_seconds = args.max_runtime_seconds orelse
                    args.github_stats_max_runtime_seconds,
                .exclude_repos = exclude_repos orelse &.{},
                .exclude_forked_repos = args.exclude_forked_repos,
                .org_clients = org_client_pointers,
            },
        ) catch |err| switch (err) {
            error.TimeBudgetExceeded => {
                std.log.info(
                    "Stats generation time budget reached. Saved partial cache; exiting successfully.",
                    .{},
                );
                return;
            },
            else => return err,
        };
    } else unreachable;
    defer stats.deinit(allocator);

    if (args.json_output_file) |path| {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        try writeFile(
            io,
            path,
            try std.json.Stringify.valueAlloc(
                arena.allocator(),
                stats,
                .{ .whitespace = .indent_2 },
            ),
        );
    }

    var aggregate_stats = try aggregateStats(
        allocator,
        stats,
        exclude_repos orelse &.{},
        exclude_langs orelse &.{},
        args.exclude_private,
        args.owned_only_stars_forks,
    );
    defer aggregate_stats.deinit(allocator);

    {
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();

        try writeFile(
            io,
            args.overview_output_file orelse "overview.svg",
            try overview(
                &arena,
                aggregate_stats,
                if (args.overview_template) |template|
                    try readFile(arena.allocator(), io, template)
                else
                    embedded_overview_template,
            ),
        );

        try writeFile(
            io,
            args.languages_output_file orelse "languages.svg",
            try languages(
                &arena,
                aggregate_stats,
                if (args.languages_template) |template|
                    try readFile(arena.allocator(), io, template)
                else
                    embedded_languages_template,
            ),
        );
    }
}

test {
    std.testing.refAllDecls(@This());
}

test "language aggregation uses personal changed lines over repo byte totals" {
    const json =
        \\{
        \\  "repositories": [
        \\    {
        \\      "name": "owner/huge-c",
        \\      "stars": 0,
        \\      "forks": 0,
        \\      "languages": [
        \\        { "name": "C", "size": 1000000000, "color": "#555555" }
        \\      ],
        \\      "contribution_languages": [],
        \\      "lines_changed": 0,
        \\      "lines_changed_complete": true,
        \\      "views": 0,
        \\      "private": false
        \\    },
        \\    {
        \\      "name": "owner/small-zig",
        \\      "stars": 0,
        \\      "forks": 0,
        \\      "languages": [
        \\        { "name": "C", "size": 999999999, "color": "#555555" }
        \\      ],
        \\      "contribution_languages": [
        \\        { "name": "Zig", "color": "#ec915c", "lines_changed": 5 }
        \\      ],
        \\      "lines_changed": 5,
        \\      "lines_changed_complete": true,
        \\      "views": 0,
        \\      "private": false
        \\    }
        \\  ],
        \\  "user": "octo",
        \\  "name": "Octo",
        \\  "emails": ["octo@example.com"],
        \\  "repo_contributions": 0,
        \\  "issue_contributions": 0,
        \\  "commit_contributions": 0,
        \\  "pr_contributions": 0,
        \\  "review_contributions": 0
        \\}
    ;
    var stats = try Statistics.initFromJson(std.testing.allocator, json);
    defer stats.deinit(std.testing.allocator);

    var aggregate_stats = try aggregateStats(
        std.testing.allocator,
        stats,
        &.{},
        &.{},
        false,
        false,
    );
    defer aggregate_stats.deinit(std.testing.allocator);

    try std.testing.expect(aggregate_stats.languages.get("C") == null);
    try std.testing.expectEqual(@as(?u64, 5), aggregate_stats.languages.get("Zig"));
    try std.testing.expectEqual(@as(u64, 5), aggregate_stats.languages_total);
}

test "language aggregation leaves legacy JSON without personal language data empty" {
    const json =
        \\{
        \\  "repositories": [
        \\    {
        \\      "name": "owner/legacy",
        \\      "stars": 0,
        \\      "forks": 0,
        \\      "languages": [
        \\        { "name": "C", "size": 12, "color": "#555555" }
        \\      ],
        \\      "lines_changed": 1,
        \\      "lines_changed_complete": true,
        \\      "views": 0,
        \\      "private": false
        \\    }
        \\  ],
        \\  "user": "octo",
        \\  "name": "Octo",
        \\  "emails": ["octo@example.com"],
        \\  "repo_contributions": 0,
        \\  "issue_contributions": 0,
        \\  "commit_contributions": 0,
        \\  "pr_contributions": 0,
        \\  "review_contributions": 0
        \\}
    ;
    var stats = try Statistics.initFromJson(std.testing.allocator, json);
    defer stats.deinit(std.testing.allocator);

    var aggregate_stats = try aggregateStats(
        std.testing.allocator,
        stats,
        &.{},
        &.{},
        false,
        false,
    );
    defer aggregate_stats.deinit(std.testing.allocator);

    try std.testing.expect(aggregate_stats.languages.get("C") == null);
    try std.testing.expectEqual(@as(u64, 0), aggregate_stats.languages_total);
}

test "owned-only stars and forks exclude external repositories" {
    const json =
        \\{
        \\  "repositories": [
        \\    {
        \\      "name": "owner/primary",
        \\      "stars": 10,
        \\      "forks": 2,
        \\      "languages": [],
        \\      "contribution_languages": [],
        \\      "lines_changed": 5,
        \\      "lines_changed_complete": true,
        \\      "views": 1,
        \\      "private": false,
        \\      "owned": true
        \\    },
        \\    {
        \\      "name": "other/external",
        \\      "stars": 50,
        \\      "forks": 7,
        \\      "languages": [],
        \\      "contribution_languages": [],
        \\      "lines_changed": 3,
        \\      "lines_changed_complete": true,
        \\      "views": 4,
        \\      "private": false,
        \\      "owned": false
        \\    }
        \\  ],
        \\  "user": "octo",
        \\  "name": "Octo",
        \\  "emails": ["octo@example.com"],
        \\  "repo_contributions": 0,
        \\  "issue_contributions": 0,
        \\  "commit_contributions": 0,
        \\  "pr_contributions": 0,
        \\  "review_contributions": 0
        \\}
    ;
    var stats = try Statistics.initFromJson(std.testing.allocator, json);
    defer stats.deinit(std.testing.allocator);

    var aggregate_stats = try aggregateStats(
        std.testing.allocator,
        stats,
        &.{},
        &.{},
        false,
        true,
    );
    defer aggregate_stats.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 10), aggregate_stats.stars);
    try std.testing.expectEqual(@as(usize, 2), aggregate_stats.forks);
}

fn readFile(
    allocator: std.mem.Allocator,
    io: std.Io,
    path: []const u8,
) ![]const u8 {
    std.log.info("Reading data from '{s}'", .{path});
    const in =
        if (std.mem.eql(u8, path, "-"))
            std.Io.File.stdin()
        else
            try std.Io.Dir.cwd().openFile(io, path, .{});
    defer if (!std.mem.eql(u8, path, "-")) in.close(io);
    var read_buffer: [64 * 1024]u8 = undefined;
    var reader = in.reader(io, &read_buffer);
    return try (&reader.interface).allocRemaining(allocator, .unlimited);
}

fn writeFile(
    io: std.Io,
    path: []const u8,
    data: []const u8,
) !void {
    std.log.info("Writing data to '{s}'", .{path});
    const out =
        if (std.mem.eql(u8, path, "-"))
            std.Io.File.stdout()
        else
            try std.Io.Dir.cwd().createFile(io, path, .{});
    defer if (!std.mem.eql(u8, path, "-")) out.close(io);
    var write_buffer: [64 * 1024]u8 = undefined;
    var writer = out.writer(io, &write_buffer);
    try writer.interface.writeAll(data);
    try writer.interface.flush();
}

fn splitList(
    allocator: std.mem.Allocator,
    original: []const u8,
    separators: []const u8,
) ![][]const u8 {
    var list = try std.ArrayList([]const u8).initCapacity(allocator, 16);
    errdefer list.deinit(allocator);
    var iterator = std.mem.tokenizeAny(u8, original, separators);
    while (iterator.next()) |pattern| {
        try list.append(allocator, std.mem.trim(u8, pattern, " "));
    }
    return try list.toOwnedSlice(allocator);
}
