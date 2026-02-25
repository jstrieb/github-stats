const std = @import("std");
const HttpClient = @import("http_client.zig");

repositories: []Repository,
user: []const u8,
contributions: u32 = 0,

var allocator: std.mem.Allocator = undefined;
const Statistics = @This();

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

pub fn init(client: *HttpClient, a: std.mem.Allocator) !Statistics {
    allocator = a;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var self: Statistics = try get_repos(&arena, client);
    errdefer self.deinit();
    try self.get_lines_changed(&arena, client);
    return self;
}

pub fn deinit(self: Statistics) void {
    for (self.repositories) |repository| {
        repository.deinit();
    }
    allocator.free(self.repositories);
    allocator.free(self.user);
}

fn years(client: *HttpClient, alloc: std.mem.Allocator) ![]u32 {
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
        struct { data: struct { viewer: struct {
            contributionsCollection: struct {
                contributionYears: []u32,
            },
        } } },
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

fn get_repos(
    arena: *std.heap.ArenaAllocator,
    client: *HttpClient,
) !Statistics {
    var contributions: u32 = 0;
    var user: []const u8 = undefined;
    var repositories: std.ArrayList(Repository) =
        try .initCapacity(allocator, 32);
    errdefer {
        for (repositories.items) |repo| {
            repo.deinit();
        }
        repositories.deinit(allocator);
    }
    var seen: std.StringHashMap(bool) = .init(arena.allocator());
    defer seen.deinit();

    for (try Statistics.years(client, arena.allocator())) |year| {
        std.log.info("Getting data from {d}...", .{year});
        var response, var status = try client.graphql(
            \\query ($from: DateTime, $to: DateTime) {
            \\  viewer {
            \\    login
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
        const viewer = (try std.json.parseFromSliceLeaky(
            struct { data: struct { viewer: struct {
                login: []const u8,
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
        )).data.viewer;
        user = viewer.login;
        const stats = viewer.contributionsCollection;
        std.log.info(
            "Parsed {d} total repositories from {d}",
            .{ stats.commitContributionsByRepository.len, year },
        );

        contributions += stats.totalRepositoryContributions;
        contributions += stats.totalIssueContributions;
        contributions += stats.totalCommitContributions;
        contributions += stats.totalPullRequestContributions;
        contributions += stats.totalPullRequestReviewContributions;

        // TODO: if there are 100 ore more repositories, we should subdivide
        // the date range in half

        for (stats.commitContributionsByRepository) |x| {
            const raw_repo = x.repository;
            if (seen.get(raw_repo.nameWithOwner) orelse false) {
                std.log.debug(
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
                            // TODO: Add sensible default color
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
                std.log.info(
                    "Failed to get views for {s} ({?s})",
                    .{ raw_repo.nameWithOwner, status.phrase() },
                );
            }
            try repositories.append(allocator, repository);
            try seen.put(raw_repo.nameWithOwner, true);
        }
    }

    const list = try repositories.toOwnedSlice(allocator);
    std.sort.pdq(Repository, list, {}, struct {
        pub fn lessThanFn(_: void, lhs: Repository, rhs: Repository) bool {
            if (rhs.views == lhs.views) {
                return rhs.stars + rhs.forks < lhs.stars + lhs.forks;
            }
            return rhs.views < lhs.views;
        }
    }.lessThanFn);

    return .{
        .contributions = contributions,
        .user = try allocator.dupe(u8, user),
        .repositories = list,
    };
}

fn get_lines_changed(
    self: *Statistics,
    arena: *std.heap.ArenaAllocator,
    client: *HttpClient,
) !void {
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
    for (self.repositories) |*repo| {
        try q.add(.{
            .repo = repo,
            .delay = 8,
            .timestamp = std.time.timestamp(),
        });
    }
    while (q.count() > 0) {
        var item = q.remove();
        const now = std.time.timestamp();
        if (item.timestamp > now) {
            const delay: u64 = @intCast(item.timestamp - now);
            std.log.debug("Sleeping for {d}s. Waiting for {d} repo{s}.", .{
                delay,
                q.count() + 1,
                if (q.count() != 0) "s" else "",
            });
            std.Thread.sleep(delay * std.time.ns_per_s);
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
                    if (!std.mem.eql(u8, o.author.login, self.user)) {
                        continue;
                    }
                    for (o.weeks) |week| {
                        item.repo.lines_changed += week.a;
                        item.repo.lines_changed += week.d;
                    }
                }
                std.log.info(
                    "Got {d} line{s} changed by {s} in {s}",
                    .{
                        item.repo.lines_changed,
                        if (item.repo.lines_changed != 1) "s" else "",
                        self.user,
                        item.repo.name,
                    },
                );
            },
            .accepted => {
                item.timestamp = std.time.timestamp() + item.delay;
                // Exponential backoff (in expectation) with jitter
                item.delay += std.crypto.random.intRangeAtMost(
                    i64,
                    2,
                    item.delay,
                );
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
}
