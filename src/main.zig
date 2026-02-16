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
        const response = try client.graphql(
            \\query {
            \\  viewer {
            \\    contributionsCollection {
            \\      contributionYears
            \\    }
            \\  }
            \\}
        , null);
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
    var repositories: std.ArrayList(Repository) = try .initCapacity(allocator, 32);
    var seen: std.StringHashMap(bool) = .init(arena.allocator());
    defer seen.deinit();

    for (try Statistics.years(client, arena.allocator())) |year| {
        const response = try client.graphql(
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
            \\          languages(first: 100, orderBy: { direction: DESC, field: SIZE }) {
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

        result.contributions += stats.totalRepositoryContributions;
        result.contributions += stats.totalIssueContributions;
        result.contributions += stats.totalCommitContributions;
        result.contributions += stats.totalPullRequestContributions;
        result.contributions += stats.totalPullRequestReviewContributions;

        // TODO: if there are 100 ore more repositories, we should subdivide
        // the date range in half

        for (stats.commitContributionsByRepository) |x| {
            const raw_repo = x.repository;
            if (seen.get(raw_repo.nameWithOwner) orelse false) continue;
            var repository = Repository{
                .name = try allocator.dupe(u8, raw_repo.nameWithOwner),
                .stars = raw_repo.stargazerCount,
                .forks = raw_repo.forkCount,
                .languages = null,
            };
            if (raw_repo.languages) |repo_languages| {
                if (repo_languages.edges) |raw_languages| {
                    repository.languages = try allocator.alloc(
                        Language,
                        raw_languages.len,
                    );
                    for (raw_languages, repository.languages.?) |raw, *language| {
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
            try repositories.append(allocator, repository);
            try seen.put(raw_repo.nameWithOwner, true);
        }
    }

    result.repositories = try repositories.toOwnedSlice(allocator);
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
        "TODO",
    );
    defer client.deinit();
    const stats = try get_repos(&client);
    defer stats.deinit();
    print(stats);

    // TODO: Download statistics to populate data structures
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
