const builtin = @import("builtin");
const std = @import("std");

const HttpClient = @import("http_client.zig");

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

const Language = struct {
    name: []const u8,
    size: u32,
    color: []const u8,

    pub fn deinit(self: @This()) void {
        allocator.free(self.name);
        allocator.free(self.color);
    }
};

const Repository = struct {
    name: []const u8,
    stars: u32,
    forks: u32,
    languages: ?[]Language,
    views: u32,
    lines_changed: u32,

    pub fn deinit(self: @This()) void {
        allocator.free(self.name);
        if (self.languages) |languages| {
            for (languages) |language| {
                language.deinit();
            }
            allocator.free(languages);
        }
    }
};

const Statistics = struct {
    contributions: u32,
    repositories: []Repository,

    const Self = @This();

    pub const empty = Self{
        .contributions = 0,
        .repositories = undefined,
    };

    pub fn deinit(self: Self) void {
        for (self.repositories) |repository| {
            repository.deinit();
        }
        allocator.free(self.repositories);
    }

    pub fn years(client: *HttpClient, alloc: std.mem.Allocator) ![]u32 {
        std.log.info("Getting contribution years...", .{});
        const response, const status = try client.graphql(
            \\query {
            \\  viewer {
            \\    contributionsCollection {
            \\      contributionYears
            \\    }
            \\  }
            \\}
        , null);
        if (status != .ok) {
            std.log.err(
                "Failed to get contribution years ({?s})",
                .{status.phrase()},
            );
            return error.RequestFailed;
        }
        const parsed = try std.json.parseFromSliceLeaky(
            struct {
                data: struct {
                    viewer: struct {
                        contributionsCollection: struct {
                            contributionYears: []u32,
                        },
                    },
                },
            },
            alloc,
            response,
            .{ .ignore_unknown_fields = true },
        );
        return parsed
            .data
            .viewer
            .contributionsCollection
            .contributionYears;
    }
};

fn get_repos(client: *HttpClient) !Statistics {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var result: Statistics = .empty;
    var repositories: std.ArrayList(Repository) =
        try .initCapacity(allocator, 32);
    var seen: std.StringHashMap(bool) = .init(arena.allocator());
    defer seen.deinit();

    for (try Statistics.years(client, arena.allocator())) |year| {
        std.log.info("Getting data from {d}...", .{year});
        var response, var status = try client.graphql(
            \\query ($from: DateTime, $to: DateTime) {
            \\  viewer {
            \\    contributionsCollection(from: $from, to: $to) {
            \\      totalRepositoryContributions
            \\      totalIssueContributions
            \\      totalCommitContributions
            \\      totalPullRequestContributions
            \\      totalPullRequestReviewContributions
            \\      commitContributionsByRepository(maxRepositories: 100) {
            \\        repository {
            \\          nameWithOwner
            \\          stargazerCount
            \\          forkCount
            \\          languages(
            \\              first: 100,
            \\              orderBy: { direction: DESC, field: SIZE }
            \\          ) {
            \\            edges {
            \\              size
            \\              node {
            \\                name
            \\                color
            \\              }
            \\            }
            \\          }
            \\        }
            \\      }
            \\    }
            \\  }
            \\}
        ,
            // NOTE: Replace with actual JSON serialization if using more
            // complex tyeps. This is fine as long as we're only using numbers.
            try std.fmt.allocPrint(
                arena.allocator(),
                \\{{
                \\  "from": "{d}-01-01T00:00:00Z",
                \\  "to": "{d}-01-01T00:00:00Z"
                \\}}
            ,
                .{ year, year + 1 },
            ),
        );
        if (status != .ok) {
            std.log.err(
                "Failed to get data from {d} ({?s})",
                .{ year, status.phrase() },
            );
            return error.RequestFailed;
        }
        const stats = (try std.json.parseFromSliceLeaky(
            struct { data: struct { viewer: struct {
                contributionsCollection: struct {
                    totalRepositoryContributions: u32,
                    totalIssueContributions: u32,
                    totalCommitContributions: u32,
                    totalPullRequestContributions: u32,
                    totalPullRequestReviewContributions: u32,
                    commitContributionsByRepository: []struct {
                        repository: struct {
                            nameWithOwner: []const u8,
                            stargazerCount: u32,
                            forkCount: u32,
                            languages: ?struct {
                                edges: ?[]struct {
                                    size: u32,
                                    node: struct {
                                        name: []const u8,
                                        color: ?[]const u8,
                                    },
                                },
                            },
                        },
                    },
                },
            } } },
            arena.allocator(),
            response,
            .{ .ignore_unknown_fields = true },
        )).data.viewer.contributionsCollection;
        std.log.info(
            "Parsed {d} total repositories from {d}",
            .{ stats.commitContributionsByRepository.len, year },
        );

        result.contributions += stats.totalRepositoryContributions;
        result.contributions += stats.totalIssueContributions;
        result.contributions += stats.totalCommitContributions;
        result.contributions += stats.totalPullRequestContributions;
        result.contributions += stats.totalPullRequestReviewContributions;

        // TODO: if there are 100 ore more repositories, we should subdivide
        // the date range in half

        for (stats.commitContributionsByRepository) |x| {
            const raw_repo = x.repository;
            if (seen.get(raw_repo.nameWithOwner) orelse false) {
                std.log.info(
                    "Skipping view count for {s} (seen)",
                    .{raw_repo.nameWithOwner},
                );
                continue;
            }
            var repository = Repository{
                .name = try allocator.dupe(u8, raw_repo.nameWithOwner),
                .stars = raw_repo.stargazerCount,
                .forks = raw_repo.forkCount,
                .languages = null,
                .views = 0,
                .lines_changed = 0,
            };
            if (raw_repo.languages) |repo_languages| {
                if (repo_languages.edges) |raw_languages| {
                    repository.languages = try allocator.alloc(
                        Language,
                        raw_languages.len,
                    );
                    for (
                        raw_languages,
                        repository.languages.?,
                    ) |raw, *language| {
                        language.* = .{
                            .name = try allocator.dupe(u8, raw.node.name),
                            .size = raw.size,
                            .color = "",
                        };
                        if (raw.node.color) |color| {
                            language.color = try allocator.dupe(u8, color);
                        }
                    }
                }
            }
            std.log.info(
                "Getting views for {s}...",
                .{raw_repo.nameWithOwner},
            );
            response, status = try client.rest(
                try std.mem.concat(
                    arena.allocator(),
                    u8,
                    &.{
                        "https://api.github.com/repos/",
                        raw_repo.nameWithOwner,
                        "/traffic/views",
                    },
                ),
            );
            if (status == .ok) {
                repository.views = (try std.json.parseFromSliceLeaky(
                    struct { count: u32 },
                    arena.allocator(),
                    response,
                    .{ .ignore_unknown_fields = true },
                )).count;
            } else {
                std.log.warn(
                    "Failed to get views for {s} ({?s})",
                    .{ raw_repo.nameWithOwner, status.phrase() },
                );
            }
            try repositories.append(allocator, repository);
            try seen.put(raw_repo.nameWithOwner, true);
        }
    }

    result.repositories = try repositories.toOwnedSlice(allocator);
    std.sort.pdq(Repository, result.repositories, {}, struct {
        pub fn lessThanFn(_: void, lhs: Repository, rhs: Repository) bool {
            if (rhs.views == lhs.views) {
                return rhs.stars + rhs.forks < lhs.stars + lhs.forks;
            }
            return rhs.views < lhs.views;
        }
    }.lessThanFn);

    const T = struct {
        repo: *Repository,
        delay: i64,
        timestamp: i64,
    };
    var q: std.PriorityQueue(T, void, struct {
        pub fn compareFn(_: void, lhs: T, rhs: T) std.math.Order {
            return std.math.order(lhs.timestamp, rhs.timestamp);
        }
    }.compareFn) = .init(arena.allocator(), {});
    defer q.deinit();
    for (result.repositories) |*repo| {
        try q.add(.{
            .repo = repo,
            .delay = 16,
            .timestamp = std.time.timestamp(),
        });
    }
    while (q.count() > 0) {
        var item = q.remove();
        const now = std.time.timestamp();
        if (item.timestamp > now) {
            std.Thread.sleep(
                @as(u64, @intCast(
                    item.timestamp - now,
                )) * std.time.ns_per_s,
            );
        }
        std.log.info(
            "Trying to get lines of code changed for {s}...",
            .{item.repo.name},
        );
        const response, const status = try client.rest(
            try std.mem.concat(
                arena.allocator(),
                u8,
                &.{
                    "https://api.github.com/repos/",
                    item.repo.name,
                    "/stats/contributors",
                },
            ),
        );
        switch (status) {
            .ok => {
                const authors = (try std.json.parseFromSliceLeaky(
                    []struct {
                        author: struct { login: []const u8 },
                        weeks: []struct {
                            a: u32,
                            d: u32,
                        },
                    },
                    arena.allocator(),
                    response,
                    .{ .ignore_unknown_fields = true },
                ));
                for (authors) |o| {
                    if (!std.mem.eql(u8, o.author.login, user)) {
                        continue;
                    }
                    for (o.weeks) |week| {
                        item.repo.lines_changed += week.a;
                        item.repo.lines_changed += week.d;
                    }
                }
                std.log.info(
                    "Got {d} lines changed by {s} in {s}",
                    .{ item.repo.lines_changed, user, item.repo.name },
                );
            },
            .accepted => {
                item.timestamp = std.time.timestamp() + item.delay;
                item.delay *= 2;
                try q.add(item);
            },
            else => {
                std.log.err(
                    "Failed to get contribution data for {s} ({?s})",
                    .{ item.repo.name, status.phrase() },
                );
                return error.RequestFailed;
            },
        }
    }

    return result;
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
    const stats = try get_repos(&client);
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
