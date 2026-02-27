const std = @import("std");

pub fn parse(allocator: std.mem.Allocator, T: type) !T {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fields = @typeInfo(T).@"struct".fields;
    var seen = [_]bool{false} ** fields.len;
    var result: T = undefined;
    // TODO: An error when some of the fields are set but not others will
    // leave dangling pointers

    inline for (fields, &seen) |field, *seen_field| {
        if (field.defaultValue()) |default| {
            @field(result, field.name) = default;
            seen_field.* = true;
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
                if (std.ascii.eqlIgnoreCase(key, field.name)) {
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

    {
        const args = try std.process.argsAlloc(a);
        defer std.process.argsFree(a, args);
        var j: usize = 1;
        args: while (j < args.len) : (j += 1) {
            const raw_arg = args[j];
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
                if (std.ascii.eqlIgnoreCase(arg, field.name)) {
                    // TODO: Switch on field type and parse if applicable
                    j += 1;
                    // TODO: Fix possible memory leak
                    @field(result, field.name) = try allocator.dupe(u8, args[j]);
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
