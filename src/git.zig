const std = @import("std");
const contribution_languages = @import("contribution_languages.zig");

pub const LanguageContribution = contribution_languages.LanguageContribution;

pub const ContributionStats = struct {
    lines_changed: u32,
    languages: []LanguageContribution,

    pub fn deinit(self: ContributionStats, allocator: std.mem.Allocator) void {
        for (self.languages) |language| language.deinit(allocator);
        allocator.free(self.languages);
    }
};

var is_installed: ?bool = null;

pub fn isInstalled(gpa: std.mem.Allocator, io: std.Io) bool {
    if (is_installed) |v| {
        return v;
    }
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const run = std.process.run(arena.allocator(), io, .{
        .argv = &.{ "git", "--version" },
    }) catch {
        is_installed = false;
        return is_installed.?;
    };
    is_installed = switch (run.term) {
        .exited => |v| v == 0,
        else => false,
    };
    return is_installed.?;
}

pub fn currentCommit(gpa: std.mem.Allocator, io: std.Io) ![]const u8 {
    if (!isInstalled(gpa, io)) return error.GitNotInstalled;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const run = try std.process.run(arena.allocator(), io, .{
        .argv = &.{ "git", "rev-parse", "HEAD" },
    });
    return try gpa.dupe(u8, run.stdout[0..8]);
}

pub fn getLinesChanged(
    gpa: std.mem.Allocator,
    io: std.Io,
    login: []const u8,
    token: []const u8,
    repo: []const u8,
    emails: []const []const u8,
) !u32 {
    const stats = try getContributionStats(gpa, io, login, token, repo, emails);
    defer stats.deinit(gpa);
    return stats.lines_changed;
}

pub fn getContributionLanguages(
    gpa: std.mem.Allocator,
    io: std.Io,
    login: []const u8,
    token: []const u8,
    repo: []const u8,
    emails: []const []const u8,
) ![]LanguageContribution {
    const stats = try getContributionStats(gpa, io, login, token, repo, emails);
    return stats.languages;
}

pub fn getContributionStats(
    gpa: std.mem.Allocator,
    io: std.Io,
    login: []const u8,
    token: []const u8,
    repo: []const u8,
    emails: []const []const u8,
) !ContributionStats {
    if (!isInstalled(gpa, io)) return error.GitNotInstalled;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const repo_path = try std.mem.replaceOwned(u8, allocator, repo, "/", "_");
    // GitHub ignores the username for token auth, but App installation tokens
    // are documented with x-access-token, and it works for user tokens too
    const repo_url = try std.fmt.allocPrint(
        allocator,
        "https://x-access-token:{s}@github.com/{s}.git",
        .{ token, repo },
    );
    const clone = try std.process.run(allocator, io, .{
        .argv = &.{
            "git",
            "clone",
            "--bare",
            "--filter=blob:limit=1m",
            "--no-tags",
            "--single-branch",
            repo_url,
            repo_path,
        },
    });
    switch (clone.term) {
        .exited => |v| if (v != 0) return error.CloneFailed,
        else => return error.CloneFailed,
    }
    defer std.Io.Dir.cwd().deleteTree(io, repo_path) catch {};

    return try contributionStatsFromRepoPath(gpa, io, repo_path, login, emails);
}

fn contributionStatsFromRepoPath(
    gpa: std.mem.Allocator,
    io: std.Io,
    repo_path: []const u8,
    login: []const u8,
    emails: []const []const u8,
) !ContributionStats {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const author_patterns = try buildAuthorPatterns(allocator, login, emails);
    const author_args = try allocator.alloc([]const u8, author_patterns.len * 2);
    for (author_patterns, 0..) |author, i| {
        author_args[i * 2] = "--author";
        author_args[i * 2 + 1] = author;
    }
    const log_args = try std.mem.concat(allocator, []const u8, &.{
        &.{
            "git",
            "-C",
            repo_path,
            "log",
            "--all",
            "--numstat",
            "--pretty=tformat:",
        },
        author_args,
    });
    const log = try std.process.run(allocator, io, .{ .argv = log_args });
    switch (log.term) {
        .exited => |v| if (v != 0) return error.LogFailed,
        else => return error.LogFailed,
    }

    const lines_changed = countChangedLines(log.stdout);
    const languages = try contribution_languages.parseNumstat(gpa, log.stdout);
    errdefer {
        for (languages) |language| language.deinit(gpa);
        gpa.free(languages);
    }
    return .{
        .lines_changed = lines_changed,
        .languages = languages,
    };
}

fn countChangedLines(numstat: []const u8) u32 {
    var lines_changed: u32 = 0;
    var lines = std.mem.tokenizeScalar(u8, numstat, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        var fields = std.mem.splitScalar(u8, line, '\t');
        const additions_text = fields.next() orelse continue;
        const deletions_text = fields.next() orelse continue;
        if (std.mem.eql(u8, additions_text, "-") or
            std.mem.eql(u8, deletions_text, "-"))
        {
            continue;
        }
        const additions = std.fmt.parseUnsigned(u32, additions_text, 10) catch continue;
        const deletions = std.fmt.parseUnsigned(u32, deletions_text, 10) catch continue;
        lines_changed += additions + deletions;
    }
    return lines_changed;
}

fn buildAuthorPatterns(
    allocator: std.mem.Allocator,
    login: []const u8,
    emails: []const []const u8,
) ![][]const u8 {
    var patterns = try std.ArrayList([]const u8).initCapacity(
        allocator,
        emails.len + 5,
    );
    for (emails) |email| {
        try appendUnique(allocator, &patterns, email);
    }

    try appendLoginPatterns(allocator, &patterns, login);
    const lower_login = try std.ascii.allocLowerString(allocator, login);
    if (!std.mem.eql(u8, lower_login, login)) {
        try appendLoginPatterns(allocator, &patterns, lower_login);
    }

    return try patterns.toOwnedSlice(allocator);
}

fn appendLoginPatterns(
    allocator: std.mem.Allocator,
    patterns: *std.ArrayList([]const u8),
    login: []const u8,
) !void {
    try appendUnique(allocator, patterns, login);
    try appendUnique(
        allocator,
        patterns,
        try std.fmt.allocPrint(
            allocator,
            "{s}@users\\.noreply\\.github\\.com",
            .{login},
        ),
    );
    try appendUnique(
        allocator,
        patterns,
        try std.fmt.allocPrint(
            allocator,
            "[0-9][0-9]*+{s}@users\\.noreply\\.github\\.com",
            .{login},
        ),
    );
}

fn appendUnique(
    allocator: std.mem.Allocator,
    patterns: *std.ArrayList([]const u8),
    pattern: []const u8,
) !void {
    for (patterns.items) |existing| {
        if (std.mem.eql(u8, existing, pattern)) return;
    }
    try patterns.append(allocator, pattern);
}

test "git integration attributes changed file languages to selected author emails" {
    if (!isInstalled(std.testing.allocator, std.testing.io)) {
        return error.SkipZigTest;
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "repo");
    const repo_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/repo",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(repo_path);

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try runGit(allocator, &.{ "git", "init", repo_path });
    try runGit(allocator, &.{ "git", "-C", repo_path, "config", "user.name", "Committer" });
    try runGit(allocator, &.{ "git", "-C", repo_path, "config", "user.email", "committer@example.com" });

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "repo/owned.zig",
        .data = "pub fn owned() void {}\nconst x = 1;\n",
    });
    try runGit(allocator, &.{ "git", "-C", repo_path, "add", "owned.zig" });
    try runGit(allocator, &.{
        "git",
        "-C",
        repo_path,
        "commit",
        "--author",
        "Selected <selected@example.com>",
        "-m",
        "selected zig",
    });

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "repo/README.md",
        .data = "# Notes\n",
    });
    try runGit(allocator, &.{ "git", "-C", repo_path, "add", "README.md" });
    try runGit(allocator, &.{
        "git",
        "-C",
        repo_path,
        "commit",
        "--author",
        "Selected <selected@example.com>",
        "-m",
        "selected docs",
    });

    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "repo/other.c",
        .data = "int other(void) { return 1; }\n",
    });
    try runGit(allocator, &.{ "git", "-C", repo_path, "add", "other.c" });
    try runGit(allocator, &.{
        "git",
        "-C",
        repo_path,
        "commit",
        "--author",
        "Other <other@example.com>",
        "-m",
        "other c",
    });

    const stats = try contributionStatsFromRepoPath(
        std.testing.allocator,
        std.testing.io,
        repo_path,
        "selected",
        &.{"selected@example.com"},
    );
    defer stats.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 3), stats.lines_changed);
    try std.testing.expectEqual(@as(usize, 1), stats.languages.len);
    try std.testing.expectEqualStrings("Zig", stats.languages[0].name);
    try std.testing.expectEqual(@as(u32, 2), stats.languages[0].lines_changed);
}

test "numstat line totals include unclassified text files" {
    try std.testing.expectEqual(
        @as(u32, 15),
        countChangedLines(
            "10\t2\tsrc/main.zig\n3\t0\tREADME.md\n-\t-\tassets/logo.png\n",
        ),
    );
}

test "author patterns include login and GitHub noreply variants" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const patterns = try buildAuthorPatterns(
        arena.allocator(),
        "SampleUser",
        &.{"real@example.com"},
    );

    try expectPattern(patterns, "real@example.com");
    try expectPattern(patterns, "SampleUser");
    try expectPattern(patterns, "SampleUser@users\\.noreply\\.github\\.com");
    try expectPattern(patterns, "[0-9][0-9]*+SampleUser@users\\.noreply\\.github\\.com");
    try expectPattern(patterns, "sampleuser");
    try expectPattern(patterns, "sampleuser@users\\.noreply\\.github\\.com");
    try expectPattern(patterns, "[0-9][0-9]*+sampleuser@users\\.noreply\\.github\\.com");
}

fn expectPattern(patterns: []const []const u8, expected: []const u8) !void {
    for (patterns) |pattern| {
        if (std.mem.eql(u8, pattern, expected)) return;
    }
    return error.ExpectedPatternMissing;
}

fn runGit(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    const run = try std.process.run(allocator, std.testing.io, .{ .argv = argv });
    switch (run.term) {
        .exited => |code| if (code != 0) return error.GitCommandFailed,
        else => return error.GitCommandFailed,
    }
}
