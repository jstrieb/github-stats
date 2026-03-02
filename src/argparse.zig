const std = @import("std");

fn strip_optional(T: type) type {
    const info = @typeInfo(T);
    if (info != .optional) return T;
    return strip_optional(info.optional.child);
}

fn free_field(allocator: std.mem.Allocator, field: anytype) void {
    switch (@typeInfo(@TypeOf(field))) {
        .array => allocator.free(field),
        .optional => free_field(allocator, field.?),
        .bool, .int, .float, .@"enum" => {},
        else => unreachable,
    }
}

pub fn parse(allocator: std.mem.Allocator, T: type) !T {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fields = @typeInfo(T).@"struct".fields;
    var seen = [_]bool{false} ** fields.len;
    var result: T = undefined;
    errdefer {
        inline for (fields, seen) |field, seen_field| {
            if (seen_field) {
                free_field(allocator, @field(result, field.name));
            }
        }
    }

    {
        const args = try std.process.argsAlloc(a);
        defer std.process.argsFree(a, args);
        var i: usize = 1;
        args: while (i < args.len) : (i += 1) {
            const raw_arg = args[i];
            if (std.mem.eql(u8, raw_arg, "-h") or
                std.mem.eql(u8, raw_arg, "--help"))
            {
                printUsage(T, args[0]);
                std.process.exit(0);
            }
            // TODO: Handle one-letter arguments
            if (!std.mem.startsWith(u8, raw_arg, "--")) {
                // TODO: Use actual printing
                std.debug.print("Unknown argument: '{s}'\n", .{raw_arg});
                printUsage(T, args[0]);
                std.process.exit(1);
            }
            const arg = try a.dupe(u8, raw_arg[2..]);
            defer a.free(arg);
            std.mem.replaceScalar(u8, arg, '-', '_');
            inline for (fields, &seen) |field, *seen_field| {
                if (!seen_field.* and std.ascii.eqlIgnoreCase(arg, field.name)) {
                    // TODO: Switch on field type and parse if applicable
                    i += 1;
                    // TODO: Fix possible memory leak
                    @field(result, field.name) = try allocator.dupe(u8, args[i]);
                    seen_field.* = true;
                    continue :args;
                }
            }
            // TODO: Use actual printing
            std.debug.print("Unknown argument: '{s}'\n", .{raw_arg});
            printUsage(T, args[0]);
            std.process.exit(1);
        }
    }

    {
        var env = try std.process.getEnvMap(a);
        defer env.deinit();
        var iterator = env.iterator();
        while (iterator.next()) |entry| {
            const key = try a.dupe(u8, entry.key_ptr.*);
            defer a.free(key);
            std.mem.replaceScalar(u8, key, '-', '_');
            inline for (fields, &seen) |field, *seen_field| {
                if (!seen_field.* and std.ascii.eqlIgnoreCase(key, field.name)) {
                    // TODO: Switch on field type and parse if applicable
                    @field(result, field.name) = try allocator.dupe(
                        u8,
                        entry.value_ptr.*,
                    );
                    seen_field.* = true;
                }
            }
        }
    }

    inline for (fields, &seen) |field, *seen_field| {
        if (!seen_field.*) {
            if (field.defaultValue()) |default| {
                // TODO: Switch on field type and duplicate if applicable
                @field(result, field.name) = default;
                seen_field.* = true;
            }
        }
    }

    inline for (fields, seen) |field, seen_field| {
        if (!seen_field) {
            std.log.err("Missing required argument {s}", .{field.name});
            return error.MissingArgument;
        }
    }

    return result;
}

pub fn printUsage(T: type, argv0: []const u8) void {
    // TODO: Improve
    std.debug.print("Usage: {s}\n", .{argv0});
    _ = T;
}
