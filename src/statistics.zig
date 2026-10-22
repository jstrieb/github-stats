const std = @import("std");
const Cache = @import("cache.zig");
const contribution_languages = @import("contribution_languages.zig");
const git = @import("git.zig");
const glob = @import("glob.zig");
const HttpClient = @import("http_client.zig");

repositories: []Repository,
user: []const u8,
name: []const u8,
emails: [][]const u8,
repo_contributions: u32 = 0,
issue_contributions: u32 = 0,
commit_contributions: u32 = 0,
pr_contributions: u32 = 0,
review_contributions: u32 = 0,

const Statistics = @This();

const Repository = struct {
    cache_key: []const u8 = "",
    pushed_at: []const u8 = "",
    name: []const u8,
    stars: u32,
    forks: u32,
    languages: ?[]Language,
    contribution_languages: ?[]ContributionLanguage = null,
    lines_changed: u32,
    lines_changed_complete: bool = true,
    views: u32,
    private: bool,
    owned: bool = true,
    // Index of the client that discovered this repository: 0 is the user
    // token, and the rest are organization installation tokens
    client_index: usize = 0,

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.cache_key);
        allocator.free(self.pushed_at);
        allocator.free(self.name);
        if (self.languages) |languages| {
            for (languages) |language| {
                language.deinit(allocator);
            }
            allocator.free(languages);
        }
        if (self.contribution_languages) |languages| {
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
        const response = try client.rest(
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
        defer client.allocator.free(response.body);
        if (response.status == .ok) {
            self.lines_changed = 0;
            const authors = std.json.parseFromSliceLeaky(
                []struct {
                    author: struct { login: []const u8 },
                    weeks: []struct {
                        a: u32,
                        d: u32,
                    },
                },
                arena.allocator(),
                response.body,
                .{ .ignore_unknown_fields = true },
            ) catch {
                // TODO: Replace with proper exception propagation when GitHub
                // gets their shit together and stops breaking this endpoint
                std.log.info(
                    "Skipping lines changed by {s} in {s} due to invalid " ++
                        "response from GitHub.",
                    .{ user, self.name },
                );
                return response.status;
            };
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
        } else if (response.status == .no_content) {
            self.lines_changed = 0;
            std.log.info(
                "No contributor stats for {s}; treating as 0 lines changed by {s}",
                .{ self.name, user },
            );
        }
        return response.status;
    }
};

fn linesChangedComplete(status: std.http.Status) bool {
    return switch (status) {
        .ok, .no_content => true,
        else => false,
    };
}

test linesChangedComplete {
    try std.testing.expect(linesChangedComplete(.ok));
    try std.testing.expect(linesChangedComplete(.no_content));
    try std.testing.expect(!linesChangedComplete(.accepted));
}

pub const InitOptions = struct {
    max_retries: ?usize = 25,
    cache_file: ?[]const u8 = null,
    max_runtime_seconds: ?u64 = null,
    exclude_repos: []const []const u8 = &.{},
    exclude_forked_repos: bool = false,
    // Clients using GitHub App installation tokens for organizations the user
    // token cannot see
    org_clients: []const *HttpClient = &.{},
};

const TimeBudget = struct {
    io: std.Io,
    deadline_seconds: ?i64,
    stop_buffer_seconds: i64 = 5,

    fn init(io: std.Io, max_runtime_seconds: ?u64) TimeBudget {
        const seconds = max_runtime_seconds orelse return .{
            .io = io,
            .deadline_seconds = null,
        };
        return .{
            .io = io,
            .deadline_seconds = std.Io.Clock.awake.now(io).toSeconds() +
                @as(i64, @intCast(seconds)),
        };
    }

    fn check(self: TimeBudget) !void {
        const deadline = self.deadline_seconds orelse return;
        if (std.Io.Clock.awake.now(self.io).toSeconds() >=
            deadline - self.stop_buffer_seconds)
        {
            return error.TimeBudgetExceeded;
        }
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

const ContributionLanguage = contribution_languages.LanguageContribution;

const RawRepository = struct {
    id: []const u8,
    nameWithOwner: []const u8,
    pushedAt: ?[]const u8,
    owner: struct { login: []const u8 },
    stargazerCount: u32,
    forkCount: u32,
    isPrivate: bool,
    isFork: bool,
    languages: ?struct {
        edges: ?[]struct {
            size: u32,
            node: struct {
                name: []const u8,
                color: ?[]const u8,
            },
        },
    },
};

const RestUser = struct {
    id: u64,
    email: ?[]const u8 = null,
};

const RestEmail = struct {
    email: []const u8,
};

const RepoContext = struct {
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    client: *HttpClient,
    client_index: usize = 0,
    cache: *Cache,
    budget: TimeBudget,
    user: []const u8,
    exclude_repos: []const []const u8,
    exclude_forked_repos: bool,
    result: *Statistics,
    seen: *std.StringHashMap(bool),
    repositories: *std.ArrayList(Repository),
};

pub fn init(
    client: *HttpClient,
    allocator: std.mem.Allocator,
    io: std.Io,
    options: InitOptions,
) !Statistics {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var cache = try Cache.init(allocator, io, options.cache_file);
    defer cache.deinit();
    const budget = TimeBudget.init(io, options.max_runtime_seconds);
    const clients = try allocator.alloc(*HttpClient, options.org_clients.len + 1);
    defer allocator.free(clients);
    clients[0] = client;
    @memcpy(clients[1..], options.org_clients);

    var self: Statistics = try getRepos(
        allocator,
        &arena,
        client,
        &cache,
        budget,
        options,
    );
    errdefer self.deinit(allocator);
    self.getLinesChanged(
        allocator,
        &arena,
        io,
        clients,
        &cache,
        budget,
        options.max_retries,
    ) catch |err| {
        if (err == error.TimeBudgetExceeded) {
            cache.save(io) catch {};
        }
        return err;
    };
    self.getContributionLanguages(
        allocator,
        io,
        clients,
        &cache,
        budget,
    ) catch |err| {
        if (err == error.TimeBudgetExceeded) {
            cache.save(io) catch {};
        }
        return err;
    };
    try cache.save(io);
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
    for (self.emails) |email| {
        allocator.free(email);
    }
    allocator.free(self.emails);
}

fn appendUniqueEmail(
    allocator: std.mem.Allocator,
    emails: *std.ArrayList([]const u8),
    email: []const u8,
) !void {
    if (email.len == 0) return;
    for (emails.items) |existing| {
        if (std.mem.eql(u8, existing, email)) return;
    }
    try emails.append(allocator, email);
}

fn appendNoreplyEmails(
    allocator: std.mem.Allocator,
    emails: *std.ArrayList([]const u8),
    login: []const u8,
    user_id: ?u64,
) !void {
    try appendUniqueEmail(
        allocator,
        emails,
        try std.fmt.allocPrint(
            allocator,
            "{s}@users.noreply.github.com",
            .{login},
        ),
    );
    if (user_id) |id| {
        try appendUniqueEmail(
            allocator,
            emails,
            try std.fmt.allocPrint(
                allocator,
                "{d}+{s}@users.noreply.github.com",
                .{ id, login },
            ),
        );
    }
}

fn appendGitHubAccountEmails(
    allocator: std.mem.Allocator,
    emails: *std.ArrayList([]const u8),
    login: []const u8,
    user_id: ?u64,
    public_email: ?[]const u8,
) !void {
    if (public_email) |email| {
        try appendUniqueEmail(allocator, emails, email);
    }

    try appendNoreplyEmails(allocator, emails, login, user_id);
    const lower_login = try std.ascii.allocLowerString(allocator, login);
    if (!std.mem.eql(u8, lower_login, login)) {
        try appendNoreplyEmails(allocator, emails, lower_login, user_id);
    }
}

test "GitHub account email fallbacks include public and noreply identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var emails: std.ArrayList([]const u8) = .empty;
    try appendUniqueEmail(allocator, &emails, "public@example.com");
    try appendGitHubAccountEmails(
        allocator,
        &emails,
        "SampleUser",
        12345,
        "public@example.com",
    );

    try std.testing.expectEqual(@as(usize, 5), emails.items.len);
    try expectEmail(emails.items, "public@example.com");
    try expectEmail(emails.items, "SampleUser@users.noreply.github.com");
    try expectEmail(emails.items, "12345+SampleUser@users.noreply.github.com");
    try expectEmail(emails.items, "sampleuser@users.noreply.github.com");
    try expectEmail(emails.items, "12345+sampleuser@users.noreply.github.com");
}

fn expectEmail(emails: []const []const u8, expected: []const u8) !void {
    for (emails) |email| {
        if (std.mem.eql(u8, email, expected)) return;
    }
    return error.ExpectedEmailMissing;
}

fn getBasicInfo(client: *HttpClient, arena: *std.heap.ArenaAllocator) !struct {
    years: []u32,
    user: []const u8,
    name: ?[]const u8,
    emails: [][]const u8,
} {
    std.log.info("Getting contribution years...", .{});
    const response = try client.graphql(
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
    defer client.allocator.free(response.body);
    if (response.status != .ok) {
        std.log.err(
            "Failed to get contribution years ({?s})",
            .{response.status.phrase()},
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
        arena.allocator(),
        response.body,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    )).data.viewer;

    std.log.info("Getting authenticated user metadata...", .{});
    const user_response = try client.rest("https://api.github.com/user");
    defer client.allocator.free(user_response.body);
    var user_id: ?u64 = null;
    var public_email: ?[]const u8 = null;
    if (user_response.status == .ok) {
        if (std.json.parseFromSliceLeaky(
            RestUser,
            arena.allocator(),
            user_response.body,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        )) |user_info| {
            user_id = user_info.id;
            public_email = user_info.email;
        } else |err| {
            std.log.info(
                "Could not parse authenticated user metadata: {s}",
                .{@errorName(err)},
            );
        }
    } else {
        std.log.info(
            "Could not get authenticated user metadata ({?s})",
            .{user_response.status.phrase()},
        );
    }

    std.log.info("Getting contributor emails...", .{});
    const email_response =
        try client.rest("https://api.github.com/user/emails");
    defer client.allocator.free(email_response.body);
    var emails: std.ArrayList([]const u8) = .empty;
    if (email_response.status == .ok) {
        const parsed_emails = (try std.json.parseFromSliceLeaky(
            []RestEmail,
            arena.allocator(),
            email_response.body,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        ));
        for (parsed_emails) |src| {
            try appendUniqueEmail(arena.allocator(), &emails, src.email);
        }
    } else {
        std.log.info(
            "Could not get private account emails ({?s}); using public " ++
                "and GitHub noreply identities.",
            .{email_response.status.phrase()},
        );
    }
    try appendGitHubAccountEmails(
        arena.allocator(),
        &emails,
        parsed.login,
        user_id,
        public_email,
    );

    return .{
        .years = parsed.contributionsCollection.contributionYears,
        .user = parsed.login,
        .name = parsed.name,
        .emails = try emails.toOwnedSlice(arena.allocator()),
    };
}

fn getReposByYear(
    context: RepoContext,
    year: usize,
    start_month: usize,
    months: usize,
) !void {
    try context.budget.check();
    std.log.info(
        "Getting {d} month{s} of data starting from {d}/{d}...",
        .{ months, if (months != 1) "s" else "", start_month + 1, year },
    );
    const response = try context.client.graphql(
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
        \\          id
        \\          nameWithOwner
        \\          pushedAt
        \\          owner {
        \\            login
        \\          }
        \\          stargazerCount
        \\          forkCount
        \\          isPrivate
        \\          isFork
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
    defer context.client.allocator.free(response.body);
    if (response.status != .ok) {
        std.log.err(
            "Failed to get data from {d} ({?s})",
            .{ year, response.status.phrase() },
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
                    repository: RawRepository,
                },
            },
        } } },
        context.arena.allocator(),
        response.body,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    )).data.viewer.contributionsCollection;
    std.log.info(
        "Parsed {d} total repositories from {d}",
        .{ stats.commitContributionsByRepository.len, year },
    );

    const limit = 100;
    // This slightly convoluted logic subdivides the months range for the
    // current call. It assumes the initial months range is 12, and subdivides
    // by increasingly large prime factors of 12. If it cannot divide by any
    // prime factors of 12, the size of the range is 1. In that case, it emits a
    // warning and proceeds with processing the data.
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
        try appendRepository(context, x.repository);
    }
}

fn appendRepository(context: RepoContext, raw_repo: RawRepository) !void {
    try context.budget.check();
    if (context.seen.get(raw_repo.nameWithOwner) orelse false) {
        std.log.debug(
            "Skipping {s} (seen)",
            .{raw_repo.nameWithOwner},
        );
        return;
    }
    if (glob.matchAny(context.exclude_repos, raw_repo.nameWithOwner)) {
        std.log.debug("Skipping {s} (excluded)", .{raw_repo.nameWithOwner});
        try context.seen.put(raw_repo.nameWithOwner, true);
        return;
    }
    if (context.exclude_forked_repos and raw_repo.isFork) {
        std.log.debug(
            "Skipping {s} (fork)",
            .{raw_repo.nameWithOwner},
        );
        try context.seen.put(raw_repo.nameWithOwner, true);
        return;
    }

    const pushed_at = raw_repo.pushedAt orelse "";
    const owned = std.mem.eql(u8, raw_repo.owner.login, context.user);
    const raw_cache_key = Cache.keyForRepo(raw_repo.id, raw_repo.nameWithOwner);
    var repository = Repository{
        .cache_key = try context.allocator.dupe(u8, raw_cache_key[0..]),
        .pushed_at = try context.allocator.dupe(u8, pushed_at),
        .name = try context.allocator.dupe(u8, raw_repo.nameWithOwner),
        .stars = raw_repo.stargazerCount,
        .forks = raw_repo.forkCount,
        .private = raw_repo.isPrivate,
        .owned = owned,
        .client_index = context.client_index,
        .languages = null,
        .contribution_languages = null,
        .views = 0,
        .lines_changed = 0,
        .lines_changed_complete = false,
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

    if (context.cache.getViews(
        repository.cache_key,
        repository.pushed_at,
    )) |views| {
        repository.views = views;
        std.log.info("Using cached views for {s}", .{raw_repo.nameWithOwner});
    } else {
        try context.budget.check();
        std.log.info(
            "Getting views for {s}...",
            .{raw_repo.nameWithOwner},
        );
        const response2 = try context.client.rest(
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
        defer context.client.allocator.free(response2.body);
        if (response2.status == .ok) {
            repository.views = (try std.json.parseFromSliceLeaky(
                struct { count: u32 },
                context.arena.allocator(),
                response2.body,
                .{ .ignore_unknown_fields = true },
            )).count;
            try context.cache.putViews(
                repository.cache_key,
                repository.pushed_at,
                repository.views,
            );
            try context.cache.save(context.io);
        } else {
            std.log.info(
                "Failed to get views for {s} ({?s})",
                .{ raw_repo.nameWithOwner, response2.status.phrase() },
            );
        }
    }

    if (context.cache.getLinesChanged(
        repository.cache_key,
        repository.pushed_at,
    )) |lines_changed| {
        repository.lines_changed = lines_changed;
        repository.lines_changed_complete = true;
        std.log.info(
            "Using cached lines changed for {s}",
            .{raw_repo.nameWithOwner},
        );
    } else {
        try context.budget.check();
        const status = try repository.getLinesChanged(
            context.arena,
            context.client,
            context.user,
        );
        if (linesChangedComplete(status)) {
            repository.lines_changed_complete = true;
            try context.cache.putLinesChanged(
                repository.cache_key,
                repository.pushed_at,
                repository.lines_changed,
            );
            try context.cache.save(context.io);
        }
    }

    try context.seen.put(raw_repo.nameWithOwner, true);
    try context.repositories.append(context.allocator, repository);
}

fn getAllRepos(context: RepoContext) !void {
    var cursor: ?[]const u8 = null;
    var page: usize = 1;
    while (true) {
        try context.budget.check();
        std.log.info("Getting repository page {d}...", .{page});
        const response = try context.client.graphql(
            \\query ($after: String) {
            \\  viewer {
            \\    repositories(
            \\      first: 100,
            \\      after: $after,
            \\      affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
            \\      orderBy: { direction: DESC, field: PUSHED_AT }
            \\    ) {
            \\      pageInfo {
            \\        hasNextPage
            \\        endCursor
            \\      }
            \\      nodes {
            \\        id
            \\        nameWithOwner
            \\        pushedAt
            \\        owner {
            \\          login
            \\        }
            \\        stargazerCount
            \\        forkCount
            \\        isPrivate
            \\        isFork
            \\        languages(
            \\            first: 100,
            \\            orderBy: { direction: DESC, field: SIZE }
            \\        ) {
            \\          edges {
            \\            size
            \\            node {
            \\              name
            \\              color
            \\            }
            \\          }
            \\        }
            \\      }
            \\    }
            \\  }
            \\}
        ,
            .{ .after = cursor },
        );
        defer context.client.allocator.free(response.body);
        if (response.status != .ok) {
            std.log.err(
                "Failed to get repository page {d} ({?s})",
                .{ page, response.status.phrase() },
            );
            return error.RequestFailed;
        }

        const page_data = (try std.json.parseFromSliceLeaky(
            struct { data: struct { viewer: struct {
                repositories: struct {
                    pageInfo: struct {
                        hasNextPage: bool,
                        endCursor: ?[]const u8,
                    },
                    nodes: []?RawRepository,
                },
            } } },
            context.arena.allocator(),
            response.body,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        )).data.viewer.repositories;
        std.log.info(
            "Parsed {d} repositor{s} from repository page {d}",
            .{
                page_data.nodes.len,
                if (page_data.nodes.len == 1) "y" else "ies",
                page,
            },
        );

        for (page_data.nodes) |maybe_raw_repo| {
            if (maybe_raw_repo) |raw_repo| {
                try appendRepository(context, raw_repo);
            }
        }

        if (!page_data.pageInfo.hasNextPage) break;
        if (page_data.pageInfo.endCursor) |end_cursor| {
            cursor = end_cursor;
        } else {
            std.log.warn(
                "GitHub indicated another repository page without an end cursor.",
                .{},
            );
            break;
        }
        page += 1;
    }
}

/// List every repository visible to a GitHub App installation token. The
/// installation's bot is the GraphQL viewer, so repositories are listed through
/// REST and then looked up by node ID.
fn getInstallationRepos(context: RepoContext) !void {
    const per_page = 100;
    var page: usize = 1;
    while (true) {
        try context.budget.check();
        std.log.info("Getting installation repository page {d}...", .{page});
        const response = try context.client.rest(try std.fmt.allocPrint(
            context.arena.allocator(),
            "https://api.github.com/installation/repositories?per_page={d}&page={d}",
            .{ per_page, page },
        ));
        defer context.client.allocator.free(response.body);
        if (response.status != .ok) {
            std.log.err(
                "Failed to get installation repository page {d} ({?s})",
                .{ page, response.status.phrase() },
            );
            return error.RequestFailed;
        }

        const page_data = try std.json.parseFromSliceLeaky(
            struct { repositories: []struct { node_id: []const u8 } },
            context.arena.allocator(),
            response.body,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        );
        const ids = try context.arena.allocator().alloc(
            []const u8,
            page_data.repositories.len,
        );
        for (ids, page_data.repositories) |*id, repository| {
            id.* = repository.node_id;
        }
        if (ids.len > 0) try getReposByIds(context, ids);

        if (page_data.repositories.len < per_page) break;
        page += 1;
    }
}

fn getReposByIds(context: RepoContext, ids: []const []const u8) !void {
    try context.budget.check();
    const response = try context.client.graphql(
        \\query ($ids: [ID!]!) {
        \\  nodes(ids: $ids) {
        \\    ... on Repository {
        \\      id
        \\      nameWithOwner
        \\      pushedAt
        \\      owner {
        \\        login
        \\      }
        \\      stargazerCount
        \\      forkCount
        \\      isPrivate
        \\      isFork
        \\      languages(
        \\          first: 100,
        \\          orderBy: { direction: DESC, field: SIZE }
        \\      ) {
        \\        edges {
        \\          size
        \\          node {
        \\            name
        \\            color
        \\          }
        \\        }
        \\      }
        \\    }
        \\  }
        \\}
    ,
        .{ .ids = ids },
    );
    defer context.client.allocator.free(response.body);
    if (response.status != .ok) {
        std.log.err(
            "Failed to get installation repositories ({?s})",
            .{response.status.phrase()},
        );
        return error.RequestFailed;
    }

    const nodes = (try std.json.parseFromSliceLeaky(
        struct { data: struct { nodes: []?RawRepository } },
        context.arena.allocator(),
        response.body,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    )).data.nodes;
    for (nodes) |maybe_raw_repo| {
        if (maybe_raw_repo) |raw_repo| {
            try appendRepository(context, raw_repo);
        }
    }
}

fn getRepos(
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    client: *HttpClient,
    cache: *Cache,
    budget: TimeBudget,
    options: InitOptions,
) !Statistics {
    var result: Statistics = .{
        .user = undefined,
        .name = undefined,
        .emails = undefined,
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

    const info = try getBasicInfo(client, arena);
    if (info.name) |n| {
        std.log.info("Getting data for {s} ({s})...", .{ n, info.user });
    } else {
        std.log.info("Getting data for user {s}...", .{info.user});
    }

    result.user = try allocator.dupe(u8, info.user);
    errdefer allocator.free(result.user);
    result.name = try allocator.dupe(u8, info.name orelse info.user);
    errdefer allocator.free(result.name);

    result.emails = try allocator.alloc([]const u8, info.emails.len);
    errdefer allocator.free(result.emails);
    for (result.emails, info.emails, 0..) |*dest, src, i| {
        errdefer {
            for (result.emails[0..i]) |email| {
                allocator.free(email);
            }
        }
        dest.* = try allocator.dupe(u8, src);
    }
    errdefer {
        for (result.emails) |email| {
            allocator.free(email);
        }
    }

    const context: RepoContext = .{
        .allocator = allocator,
        .arena = arena,
        .io = budget.io,
        .client = client,
        .cache = cache,
        .budget = budget,
        .user = info.user,
        .exclude_repos = options.exclude_repos,
        .exclude_forked_repos = options.exclude_forked_repos,
        .result = &result,
        .seen = &seen,
        .repositories = &repositories,
    };

    try getAllRepos(context);
    for (info.years) |year| {
        try getReposByYear(context, year, 0, 12);
    }
    for (options.org_clients, 1..) |org_client, i| {
        var org_context = context;
        org_context.client = org_client;
        org_context.client_index = i;
        try getInstallationRepos(org_context);
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

    return result;
}

fn getLinesChanged(
    self: *Statistics,
    repository_allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    io: std.Io,
    clients: []const *HttpClient,
    cache: *Cache,
    budget: TimeBudget,
    max_retries: ?usize,
) !void {
    const queue_allocator = arena.allocator();
    const T = struct {
        repo: *Repository,
        delay: i64,
        timestamp: i64,
        retries: usize,
    };
    var q: std.PriorityQueue(T, void, struct {
        pub fn compareFn(_: void, lhs: T, rhs: T) std.math.Order {
            return std.math.order(lhs.timestamp, rhs.timestamp);
        }
    }.compareFn) = .empty;
    defer q.deinit(queue_allocator);
    for (self.repositories) |*repo| {
        if (repo.lines_changed_complete) {
            continue;
        }
        try q.push(queue_allocator, .{
            .repo = repo,
            .delay = 0,
            .timestamp = std.Io.Clock.real.now(io).toSeconds(),
            .retries = 0,
        });
    }
    while (q.pop()) |_item| {
        try budget.check();
        var item = _item;
        const now = std.Io.Clock.real.now(io).toSeconds();
        if (item.timestamp > now) {
            const delay = item.timestamp - now;
            std.log.debug("Sleeping for {d}s. Waiting for {d} repo{s}.", .{
                delay,
                q.count() + 1,
                if (q.count() + 1 != 0) "s" else "",
            });
            try io.sleep(.fromSeconds(delay), .real);
            try budget.check();
        }
        const client = clients[item.repo.client_index];
        const status = try item.repo.getLinesChanged(arena, client, self.user);
        if (linesChangedComplete(status)) {
            item.repo.lines_changed_complete = true;
            try cache.putLinesChanged(
                item.repo.cache_key,
                item.repo.pushed_at,
                item.repo.lines_changed,
            );
            try cache.save(io);
            continue;
        }
        switch (status) {
            // If we're hitting rate limits on this API, just clone the repo
            // locally to compute lines changed
            // https://docs.github.com/en/rest/using-the-rest-api/troubleshooting-the-rest-api?apiVersion=2026-03-10#rate-limit-errors
            .accepted, .forbidden, .too_many_requests => {
                item.timestamp =
                    std.Io.Clock.real.now(io).toSeconds() + item.delay;
                // Note: this actually works way better with a very short delay,
                // hence no exponential backoff
                const random: std.Random.IoSource = .{ .io = io };
                item.delay = random.interface().intRangeAtMost(i64, 0, 4);
                item.retries += 1;
                if (max_retries) |max| {
                    if (item.retries <= max) {
                        try q.push(queue_allocator, item);
                    } else {
                        std.log.info(
                            "Cloning {s} to get lines changed...",
                            .{item.repo.name},
                        );
                        const maybe_contribution_stats: ?git.ContributionStats = git.getContributionStats(
                            repository_allocator,
                            io,
                            self.user,
                            client.token,
                            item.repo.name,
                            self.emails,
                        ) catch |e| switch (e) {
                            error.GitNotInstalled,
                            error.CloneFailed,
                            error.LogFailed,
                            => null,
                            else => return e,
                        };
                        if (maybe_contribution_stats) |contribution_stats| {
                            item.repo.lines_changed = contribution_stats.lines_changed;
                            item.repo.contribution_languages = contribution_stats.languages;
                            try cache.putContributionLanguages(
                                item.repo.cache_key,
                                item.repo.pushed_at,
                                item.repo.contribution_languages.?,
                            );
                        } else {
                            item.repo.lines_changed = 0;
                        }
                        item.repo.lines_changed_complete = true;
                        try cache.putLinesChanged(
                            item.repo.cache_key,
                            item.repo.pushed_at,
                            item.repo.lines_changed,
                        );
                        try cache.save(io);
                        std.log.info("Got {d} line{s} changed by {s} in {s}", .{
                            item.repo.lines_changed,
                            if (item.repo.lines_changed != 1) "s" else "",
                            self.user,
                            item.repo.name,
                        });
                    }
                } else {
                    try q.push(queue_allocator, item);
                }
            },
            else => |failed_status| {
                std.log.info(
                    "Failed to get contribution data for {s} ({?s})",
                    .{ item.repo.name, failed_status.phrase() },
                );
                std.log.err(
                    "Request failed with response {?s}",
                    .{failed_status.phrase()},
                );
                return error.RequestFailed;
            },
        }
    }
}

fn getContributionLanguages(
    self: *Statistics,
    allocator: std.mem.Allocator,
    io: std.Io,
    clients: []const *HttpClient,
    cache: *Cache,
    budget: TimeBudget,
) !void {
    for (self.repositories) |*repo| {
        try budget.check();
        if (repo.contribution_languages != null) {
            continue;
        }

        if (cache.getContributionLanguages(
            repo.cache_key,
            repo.pushed_at,
        )) |cached_languages| {
            repo.contribution_languages = try contribution_languages.dupeAll(
                allocator,
                cached_languages,
            );
            std.log.info(
                "Using cached contribution languages for {s}",
                .{repo.name},
            );
            continue;
        }

        if (repo.lines_changed == 0) {
            repo.contribution_languages = try allocator.alloc(ContributionLanguage, 0);
            try cache.putContributionLanguages(
                repo.cache_key,
                repo.pushed_at,
                repo.contribution_languages.?,
            );
            try cache.save(io);
            continue;
        }

        std.log.info(
            "Cloning {s} to get contribution languages...",
            .{repo.name},
        );
        repo.contribution_languages = git.getContributionLanguages(
            allocator,
            io,
            self.user,
            clients[repo.client_index].token,
            repo.name,
            self.emails,
        ) catch |e| switch (e) {
            error.GitNotInstalled,
            error.CloneFailed,
            error.LogFailed,
            => empty: {
                std.log.warn(
                    "Could not get contribution languages for {s}: {s}",
                    .{ repo.name, @errorName(e) },
                );
                break :empty try allocator.alloc(ContributionLanguage, 0);
            },
            else => return e,
        };
        try cache.putContributionLanguages(
            repo.cache_key,
            repo.pushed_at,
            repo.contribution_languages.?,
        );
        try cache.save(io);
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
