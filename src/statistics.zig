const std = @import("std");
const HttpClient = @import("http_client.zig");

repositories: []Repository,
user: []const u8,
name: []const u8,
repo_contributions: u32 = 0,
issue_contributions: u32 = 0,
commit_contributions: u32 = 0,
pr_contributions: u32 = 0,
review_contributions: u32 = 0,

const Statistics = @This();

const Repository = struct {
    name: []const u8,
    stars: u32,
    forks: u32,
    languages: ?[]Language,
    lines_changed: u32,
    views: u32,
    private: bool,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.languages) |languages| {
            for (languages) |language| {
                language.deinit(allocator);
            }
            allocator.free(languages);
        }
    }

    pub fn getLinesChanged(
        self: *@This(),
        arena: *std.heap.ArenaAllocator,
        client: *HttpClient,
        user: []const u8,
    ) !std.http.Status {
        std.log.debug(
            "Trying to get lines of code changed for {s}...",
            .{self.name},
        );
        const response, const status = try client.rest(
            try std.mem.concat(
                arena.allocator(),
                u8,
                &.{
                    "https://api.github.com/repos/",
                    self.name,
                    "/stats/contributors",
                },
            ),
        );
        if (status == .ok) {
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
            self.lines_changed = 0;
            for (authors) |o| {
                if (!std.mem.eql(u8, o.author.login, user)) {
                    continue;
                }
                for (o.weeks) |week| {
                    self.lines_changed += week.a;
                    self.lines_changed += week.d;
                }
            }
            std.log.info(
                "Got {d} line{s} changed by {s} in {s}",
                .{
                    self.lines_changed,
                    if (self.lines_changed != 1) "s" else "",
                    user,
                    self.name,
                },
            );
        }
        return status;
    }
};

const Language = struct {
    name: []const u8,
    size: u32,
    color: ?[]const u8 = null,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.color) |color| allocator.free(color);
    }
};

pub fn init(
    client: *HttpClient,
    allocator: std.mem.Allocator,
    max_backoff: usize,
) !Statistics {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var self: Statistics = try getRepos(allocator, &arena, client);
    errdefer self.deinit(allocator);
    try self.getLinesChanged(&arena, client, max_backoff);
    return self;
}

pub fn initFromJson(allocator: std.mem.Allocator, s: []const u8) !Statistics {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const parsed = try std.json.parseFromSliceLeaky(
        Statistics,
        arena.allocator(),
        s,
        .{ .ignore_unknown_fields = true },
    );
    return try deepcopy(allocator, parsed);
}

pub fn deinit(self: Statistics, allocator: std.mem.Allocator) void {
    for (self.repositories) |repository| {
        repository.deinit(allocator);
    }
    allocator.free(self.repositories);
    allocator.free(self.user);
    allocator.free(self.name);
}

fn getBasicInfo(
    client: *HttpClient,
    allocator: std.mem.Allocator,
) !struct { []u32, []const u8, ?[]const u8 } {
    std.log.info("Getting contribution years...", .{});
    const response, const status = try client.graphql(
        \\query {
        \\  viewer {
        \\    login
        \\    name
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
    const parsed = (try std.json.parseFromSliceLeaky(
        struct { data: struct { viewer: struct {
            login: []const u8,
            name: ?[]const u8,
            contributionsCollection: struct {
                contributionYears: []u32,
            },
        } } },
        allocator,
        response,
        .{ .ignore_unknown_fields = true },
    )).data.viewer;
    return .{
        parsed.contributionsCollection.contributionYears,
        parsed.login,
        parsed.name,
    };
}

fn getReposByYear(
    context: struct {
        allocator: std.mem.Allocator,
        arena: *std.heap.ArenaAllocator,
        client: *HttpClient,
        user: []const u8,
        result: *Statistics,
        seen: *std.StringHashMap(bool),
        repositories: *std.ArrayList(Repository),
    },
    year: usize,
    start_month: usize,
    months: usize,
) !void {
    std.log.info(
        "Getting {d} month{s} of data starting from {d}/{d}...",
        .{ months, if (months != 1) "s" else "", start_month + 1, year },
    );
    var response, var status = try context.client.graphql(
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
        \\          isPrivate
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
        .{
            .from = try std.fmt.allocPrint(
                context.arena.allocator(),
                "{d}-{d:02}-01T00:00:00Z",
                .{ year, start_month + 1 },
            ),
            .to = try std.fmt.allocPrint(
                context.arena.allocator(),
                "{d}-{d:02}-01T00:00:00Z",
                .{
                    year + (start_month + months) / 12,
                    (start_month + months) % 12 + 1,
                },
            ),
        },
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
                        isPrivate: bool,
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
        context.arena.allocator(),
        response,
        .{ .ignore_unknown_fields = true },
    )).data.viewer.contributionsCollection;
    std.log.info(
        "Parsed {d} total repositories from {d}",
        .{ stats.commitContributionsByRepository.len, year },
    );

    const limit = 100;
    if (stats.commitContributionsByRepository.len >= limit) {
        for (&[_]usize{ 2, 3 }) |factor| {
            if (months % factor == 0) {
                for (0..factor) |i| {
                    try getReposByYear(
                        context,
                        year,
                        start_month + (months / factor) * i,
                        months / factor,
                    );
                }
                return;
            }
        } else {
            std.log.warn(
                "More than {d} repos returned for {d}/{d}. " ++
                    "Some data may be omitted due to GitHub API limitations.",
                .{ limit, start_month + 1, year },
            );
        }
    }

    context.result.repo_contributions += stats.totalRepositoryContributions;
    context.result.issue_contributions += stats.totalIssueContributions;
    context.result.commit_contributions += stats.totalCommitContributions;
    context.result.pr_contributions += stats.totalPullRequestContributions;
    context.result.review_contributions +=
        stats.totalPullRequestReviewContributions;

    for (stats.commitContributionsByRepository) |x| {
        const raw_repo = x.repository;
        if (context.seen.get(raw_repo.nameWithOwner) orelse false) {
            std.log.debug(
                "Skipping {s} (seen)",
                .{raw_repo.nameWithOwner},
            );
            continue;
        }
        var repository = Repository{
            .name = try context.allocator.dupe(u8, raw_repo.nameWithOwner),
            .stars = raw_repo.stargazerCount,
            .forks = raw_repo.forkCount,
            .private = raw_repo.isPrivate,
            .languages = null,
            .views = 0,
            .lines_changed = 0,
        };
        errdefer repository.deinit(context.allocator);
        if (raw_repo.languages) |repo_languages| {
            if (repo_languages.edges) |raw_languages| {
                repository.languages = try context.allocator.alloc(
                    Language,
                    raw_languages.len,
                );
                errdefer {
                    context.allocator.free(repository.languages.?);
                    repository.languages = null;
                }
                for (
                    raw_languages,
                    repository.languages.?,
                    0..,
                ) |raw, *language, i| {
                    errdefer {
                        for (0..i, repository.languages.?) |_, l| {
                            context.allocator.free(l.name);
                            if (l.color) |c| context.allocator.free(c);
                        }
                    }
                    language.* = .{
                        .name = try context.allocator.dupe(u8, raw.node.name),
                        .size = raw.size,
                    };
                    errdefer context.allocator.free(language.name);
                    if (raw.node.color) |color| {
                        language.color = try context.allocator.dupe(u8, color);
                    }
                    errdefer if (language.color) |c| context.allocator.free(c);
                }
            }
        }

        std.log.info(
            "Getting views for {s}...",
            .{raw_repo.nameWithOwner},
        );
        response, status = try context.client.rest(
            try std.mem.concat(
                context.arena.allocator(),
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
                context.arena.allocator(),
                response,
                .{ .ignore_unknown_fields = true },
            )).count;
        } else {
            std.log.info(
                "Failed to get views for {s} ({?s})",
                .{ raw_repo.nameWithOwner, status.phrase() },
            );
        }

        _ = try repository.getLinesChanged(
            context.arena,
            context.client,
            context.user,
        );

        try context.seen.put(raw_repo.nameWithOwner, true);
        try context.repositories.append(context.allocator, repository);
    }
}

fn getRepos(
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    client: *HttpClient,
) !Statistics {
    var result: Statistics = .{
        .user = undefined,
        .name = undefined,
        .repositories = undefined,
    };
    var repositories: std.ArrayList(Repository) =
        try .initCapacity(allocator, 32);
    errdefer {
        for (repositories.items) |repo| {
            repo.deinit(allocator);
        }
        repositories.deinit(allocator);
    }
    var seen: std.StringHashMap(bool) = .init(arena.allocator());
    defer seen.deinit();

    const years, const user, const name =
        try getBasicInfo(client, arena.allocator());
    if (name) |n| {
        std.log.info("Getting data for {s} ({s})...", .{ n, user });
    } else {
        std.log.info("Getting data for user {s}...", .{user});
    }
    for (years) |year| {
        try getReposByYear(.{
            .allocator = allocator,
            .arena = arena,
            .client = client,
            .user = user,
            .result = &result,
            .seen = &seen,
            .repositories = &repositories,
        }, year, 0, 12);
    }

    result.repositories = try repositories.toOwnedSlice(allocator);
    errdefer {
        for (result.repositories) |repository| {
            repository.deinit(allocator);
        }
        allocator.free(result.repositories);
    }
    std.sort.pdq(Repository, result.repositories, {}, struct {
        pub fn lessThanFn(_: void, lhs: Repository, rhs: Repository) bool {
            if (rhs.views == lhs.views) {
                return rhs.stars + rhs.forks < lhs.stars + lhs.forks;
            }
            return rhs.views < lhs.views;
        }
    }.lessThanFn);

    result.user = try allocator.dupe(u8, user);
    errdefer allocator.free(result.user);
    result.name = try allocator.dupe(u8, name orelse user);
    errdefer allocator.free(result.name);
    return result;
}

fn getLinesChanged(
    self: *Statistics,
    arena: *std.heap.ArenaAllocator,
    client: *HttpClient,
    max_backoff: usize,
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
        if (repo.lines_changed > 0) {
            continue;
        }
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
        switch (try item.repo.getLinesChanged(arena, client, self.user)) {
            .ok => {},
            .accepted => {
                item.timestamp = std.time.timestamp() + item.delay;
                // Exponential backoff (in expectation) with jitter
                item.delay +=
                    std.crypto.random.intRangeAtMost(i64, 2, item.delay);
                item.delay = @min(item.delay, max_backoff);
                try q.add(item);
            },
            else => |status| {
                std.log.err(
                    "Failed to get contribution data for {s} ({?s})",
                    .{ item.repo.name, status.phrase() },
                );
                return error.RequestFailed;
            },
        }
    }
}

// May not correctly free memory if there are errors during copying
fn deepcopy(a: std.mem.Allocator, o: anytype) !@TypeOf(o) {
    return switch (@typeInfo(@TypeOf(o))) {
        .pointer => |p| switch (p.size) {
            .slice => v: {
                const result = try a.dupe(p.child, o);
                errdefer a.free(result);
                for (o, result) |src, *dest| {
                    dest.* = try deepcopy(a, src);
                }
                break :v result;
            },
            // Only slices in this struct
            else => comptime unreachable,
        },
        .@"struct" => |s| v: {
            var result = o;
            inline for (s.fields) |field| {
                @field(result, field.name) =
                    try deepcopy(a, @field(o, field.name));
            }
            break :v result;
        },
        .optional => if (o) |v| try deepcopy(a, v) else null,
        else => o,
    };
}
