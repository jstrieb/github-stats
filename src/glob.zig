const std = @import("std");

/// Recursive-backtracking glob matching. Potentially very slow if there are a
/// lot of globs. Good enough for now, though. (If it's good enough for the GNU
/// glob function, it's good enough for me.)
///
/// Max recursion depth is the number of asterisks in the globbing pattern plus
/// one.
pub fn match(pattern: []const u8, s: []const u8) bool {
    if (std.mem.indexOfScalar(u8, pattern, '*')) |star_offset| {
        if (!std.mem.startsWith(u8, s, pattern[0..star_offset])) {
            return false;
        }
        const rest = pattern[star_offset + 1 ..];
        for (0..s.len + 1) |glob_end| {
            if (match(rest, s[glob_end..])) {
                return true;
            }
        }
        return false;
    } else {
        return std.mem.eql(u8, pattern, s);
    }
}

pub fn matchAny(patterns: []const []const u8, s: []const u8) bool {
    for (patterns) |pattern| {
        if (match(pattern, s)) {
            return true;
        }
    }
    return false;
}

test match {
    const testing = std.testing;

    try testing.expect(match("", ""));
    try testing.expect(match("*", ""));
    try testing.expect(match("**", ""));
    try testing.expect(match("***", ""));

    try testing.expect(match("*", "a"));
    try testing.expect(match("**", "a"));
    try testing.expect(match("***", "a"));

    try testing.expect(match("*", "abcd"));
    try testing.expect(match("**", "abcd"));
    try testing.expect(match("****", "abcd"));
    try testing.expect(match("****d", "abcd"));
    try testing.expect(match("a****", "abcd"));
    try testing.expect(match("a****d", "abcd"));
    try testing.expect(!match("****c", "abcd"));

    try testing.expect(match("abc", "abc"));
    try testing.expect(!match("abc", "abcd"));
    try testing.expect(!match("abc", "dabc"));
    try testing.expect(!match("abc", "dabcd"));

    try testing.expect(match("*abc", "dabc"));
    try testing.expect(!match("*abc", "dabcd"));

    try testing.expect(match("abc*", "abcd"));
    try testing.expect(!match("abc*", "dabcd"));

    try testing.expect(match("*abc*", "abc"));
    try testing.expect(match("*abc*", "dabc"));
    try testing.expect(match("*abc*", "abcd"));
    try testing.expect(match("*abc*", "dabcd"));

    try testing.expect(!match("*c*", "this is a test"));
    try testing.expect(match("*e*", "this is a test"));

    try testing.expect(match("som*thing", "something"));
    try testing.expect(match("som*thing", "someeeething"));
    try testing.expect(match("som*thing", "som thing"));
    try testing.expect(match("som*thing", "somabcthing"));
    try testing.expect(match("som*thing", "somthing"));

    try testing.expect(match("s*a*s*s*s*s*s*s*s*s", "sssssssssssssassssssssss"));
    try testing.expect(match("s*s*s*s*s*s*s*s*s*s", "sssssssssssssassssssssss"));
    try testing.expect(match("s*s*s*s*s*s*s*s*a*s", "sssssssssssssassssssssss"));

    // Globbing here doesn't separate on slashes like globbing in the shell
    try testing.expect(match("*", "///"));
    try testing.expect(match("*", "/asdf//"));
    try testing.expect(match("/*sdf/*/*", "/asdf//"));
    try testing.expect(match("/*sdf/*", "/asdf//"));
}
