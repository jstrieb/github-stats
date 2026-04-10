const std = @import("std");

pub fn isInstalled(gpa: std.mem.Allocator) bool {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const run = std.process.Child.run(.{
        .allocator = arena.allocator(),
        .argv = &.{ "git", "--version" },
    }) catch return false;
    return switch (run.term) {
        .Exited => |v| v == 0,
        else => false,
    };
}

pub fn currentCommit(gpa: std.mem.Allocator) ![]const u8 {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const run = try std.process.Child.run(.{
        .allocator = arena.allocator(),
        .argv = &.{ "git", "rev-parse", "HEAD" },
    });
    return try gpa.dupe(u8, run.stdout[0..8]);
}
