const std = @import("std");

// Since parse is the only public function, these variables can be set there and
// used globally.
var stdout: *std.Io.Writer = undefined;
var stderr: *std.Io.Writer = undefined;

pub fn parse(
    allocator: std.mem.Allocator,
    T: type,
    errorCheck: ?fn (args: T, stderr: *std.Io.Writer) anyerror!bool,
) !T {
    var stdout_writer = std.fs.File.stdout().writer(&.{});
    stdout = &stdout_writer.interface;
    var stderr_writer = std.fs.File.stderr().writer(&.{});
    stderr = &stderr_writer.interface;

    var arena: std.heap.ArenaAllocator = .init(allocator);
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

    const args = try std.process.argsAlloc(a);
    defer std.process.argsFree(a, args);
    try setFromCli(T, allocator, &arena, args, &seen, &result);
    try setFromEnv(T, allocator, &arena, &seen, &result);
    try setFromDefaults(T, allocator, &seen, &result);

    inline for (fields, seen) |field, seen_field| {
        if (!seen_field) {
            if (@typeInfo(strip_optional(field.type)) == .bool) {
                @field(result, field.name) = false;
            } else {
                try stderr.print(
                    "Missing required argument {s}\n",
                    .{field.name},
                );
                try printUsage(T, arena.allocator(), args[0]);
                std.process.exit(1);
            }
        }
    }

    if (errorCheck) |check| {
        if (!(try check(result, stderr))) {
            try printUsage(T, arena.allocator(), args[0]);
            std.process.exit(1);
        }
    }

    return result;
}

fn setFromCli(
    T: type,
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    args: []const []const u8,
    seen: []bool,
    result: *T,
) !void {
    const a = arena.allocator();
    var i: usize = 1;
    args: while (i < args.len) : (i += 1) {
        const raw_arg = args[i];
        if (std.mem.eql(u8, raw_arg, "-h") or
            std.mem.eql(u8, raw_arg, "--help"))
        {
            try printUsage(T, arena.allocator(), args[0]);
            std.process.exit(0);
        }

        // TODO: Handle one-letter arguments
        if (!std.mem.startsWith(u8, raw_arg, "--")) {
            try stderr.print("Unknown argument: '{s}'\n", .{raw_arg});
            try printUsage(T, arena.allocator(), args[0]);
            std.process.exit(1);
        }

        const arg = try a.dupe(u8, raw_arg[2..]);
        defer a.free(arg);
        std.mem.replaceScalar(u8, arg, '-', '_');
        inline for (@typeInfo(T).@"struct".fields, seen) |field, *seen_field| {
            if (!seen_field.* and std.ascii.eqlIgnoreCase(arg, field.name)) {
                const t = @typeInfo(strip_optional(field.type));
                if (t == .bool) {
                    @field(result, field.name) = true;
                } else {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print(
                            "Missing required value for argument {s} {s}\n",
                            .{ raw_arg, field.name },
                        );
                        try printUsage(T, arena.allocator(), args[0]);
                        std.process.exit(1);
                    }
                    switch (t) {
                        // TODO
                        .int, .float, .@"enum" => comptime unreachable,
                        .pointer => @field(
                            result,
                            field.name,
                        ) = try allocator.dupe(u8, args[i]),
                        .bool => comptime unreachable,
                        else => @compileError(
                            "Disallowed struct field type.",
                        ),
                    }
                }
                seen_field.* = true;
                continue :args;
            }
        }

        try stderr.print("Unknown argument: '{s}'\n", .{raw_arg});
        try printUsage(T, arena.allocator(), args[0]);
        std.process.exit(1);
    }
}

fn setFromEnv(
    T: type,
    allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    seen: []bool,
    result: *T,
) !void {
    const a = arena.allocator();
    var env = try std.process.getEnvMap(a);
    defer env.deinit();
    var iterator = env.iterator();
    while (iterator.next()) |entry| {
        const key = try a.dupe(u8, entry.key_ptr.*);
        defer a.free(key);
        std.mem.replaceScalar(u8, key, '-', '_');
        inline for (@typeInfo(T).@"struct".fields, seen) |field, *seen_field| {
            if (!seen_field.* and std.ascii.eqlIgnoreCase(key, field.name)) {
                switch (@typeInfo(strip_optional(field.type))) {
                    .bool => {
                        const value = try a.dupe(u8, entry.value_ptr.*);
                        defer a.free(value);
                        @field(result, field.name) = value.len > 0 and
                            !std.ascii.eqlIgnoreCase(value, "false");
                    },
                    // TODO
                    .int, .float, .@"enum" => comptime unreachable,
                    .pointer => @field(
                        result,
                        field.name,
                    ) = try allocator.dupe(u8, entry.value_ptr.*),
                    else => @compileError("Disallowed struct field type."),
                }
                seen_field.* = true;
            }
        }
    }
}

fn setFromDefaults(
    T: type,
    allocator: std.mem.Allocator,
    seen: []bool,
    result: *T,
) !void {
    inline for (@typeInfo(T).@"struct".fields, seen) |field, *seen_field| {
        if (!seen_field.*) {
            if (field.defaultValue()) |default| {
                switch (@typeInfo(strip_optional(field.type))) {
                    .bool, .int, .float, .@"enum" => {
                        @field(result, field.name) = default;
                    },
                    .pointer => @field(
                        result,
                        field.name,
                    ) = if (default) |p| try allocator.dupe(u8, p) else null,
                    else => @compileError("Disallowed struct field type."),
                }
                seen_field.* = true;
            }
        }
    }
}

fn printUsage(T: type, allocator: std.mem.Allocator, argv0: []const u8) !void {
    try stdout.print("Usage: {s} [options]\n\n", .{argv0});
    try stdout.print("Options:\n", .{});
    const fields = @typeInfo(T).@"struct".fields;
    inline for (fields) |field| {
        switch (@typeInfo(strip_optional(field.type))) {
            .bool => {
                const flag_version = try allocator.dupe(u8, field.name);
                defer allocator.free(flag_version);
                std.mem.replaceScalar(u8, flag_version, '_', '-');
                try stdout.print("--{s}\n", .{flag_version});
            },
            else => {
                const flag_version = try allocator.dupe(u8, field.name);
                defer allocator.free(flag_version);
                std.mem.replaceScalar(u8, flag_version, '_', '-');
                try stdout.print("--{s} {s}\n", .{ flag_version, field.name });
            },
        }
    }
}

fn strip_optional(T: type) type {
    const info = @typeInfo(T);
    if (info != .optional) return T;
    return strip_optional(info.optional.child);
}

fn free_field(allocator: std.mem.Allocator, field: anytype) void {
    switch (@typeInfo(@TypeOf(field))) {
        .pointer => allocator.free(field),
        .optional => if (field) |v| free_field(allocator, v),
        .bool, .int, .float, .@"enum" => {},
        else => @compileError("Disallowed struct field type."),
    }
}
