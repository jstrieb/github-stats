const std = @import("std");

var is_installed: ?bool = null;

pub fn isInstalled(gpa: std.mem.Allocator) bool {
    if (is_installed) |v| {
        return v;
    }
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const run = std.process.Child.run(.{
        .allocator = arena.allocator(),
        .argv = &.{ "git", "--version" },
    }) catch {
        is_installed = false;
        return is_installed.?;
    };
    is_installed = switch (run.term) {
        .Exited => |v| v == 0,
        else => false,
    };
    return is_installed.?;
}

pub fn currentCommit(gpa: std.mem.Allocator) ![]const u8 {
    if (!isInstalled(gpa)) return error.GitNotInstalled;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const run = try std.process.Child.run(.{
        .allocator = arena.allocator(),
        .argv = &.{ "git", "rev-parse", "HEAD" },
    });
    return try gpa.dupe(u8, run.stdout[0..8]);
}

pub fn getLinesChanged(
    gpa: std.mem.Allocator,
    login: []const u8,
    token: []const u8,
    repo: []const u8,
    emails: []const []const u8,
) !u32 {
    if (!isInstalled(gpa)) return error.GitNotInstalled;
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const repo_path = try std.mem.replaceOwned(u8, allocator, repo, "/", "_");
    const repo_url = try std.fmt.allocPrint(
        allocator,
        "https://{s}:{s}@github.com/{s}.git",
        .{ login, token, repo },
    );
    const clone = try std.process.Child.run(.{
        .allocator = allocator,
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
        .Exited => |v| if (v != 0) return error.CloneFailed,
        else => return error.CloneFailed,
    }
    defer std.fs.cwd().deleteTree(repo_path) catch {};

    const email_args = try allocator.alloc([]const u8, emails.len * 2);
    for (emails, 0..) |email, i| {
        email_args[i * 2] = "--author";
        email_args[i * 2 + 1] = email;
    }
    const log_args = try std.mem.concat(allocator, []const u8, &.{
        &.{
            "git",
            "-C",
            repo_path,
            "log",
            "--numstat",
            "--pretty=tformat:",
        },
        email_args,
    });
    const log = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = log_args,
        .max_output_bytes = @min(
            64 * 1024 * 1024 * 1024,
            std.math.maxInt(usize),
        ),
    });
    switch (log.term) {
        .Exited => |v| if (v != 0) return error.LogFailed,
        else => return error.LogFailed,
    }

    var lines_changed: u32 = 0;
    var lines = std.mem.tokenizeScalar(u8, log.stdout, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const additions =
            std.fmt.parseUnsigned(u32, parts.next().?, 10) catch 0;
        const deletions =
            std.fmt.parseUnsigned(u32, parts.next().?, 10) catch 0;
        lines_changed += additions + deletions;
    }
    return lines_changed;
}
