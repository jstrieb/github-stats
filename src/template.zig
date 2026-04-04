const std = @import("std");

fn decimalToString(allocator: std.mem.Allocator, n: anytype) ![]const u8 {
    const info = @typeInfo(@TypeOf(n));
    if (info != .int or info.int.signedness != .unsigned) {
        @compileError("Only implemented for unsigned integers.");
    }

    const s = try std.fmt.allocPrint(allocator, "{d}", .{n});
    defer allocator.free(s);
    const digits = s.len;
    const commas = (digits - 1) / 3;
    const result = try allocator.alloc(u8, digits + commas);
    errdefer comptime unreachable;

    var i: usize = result.len - 1;
    var j: usize = s.len - 1;
    while (true) {
        if ((result.len - i) % 4 == 0) {
            result[i] = ',';
            i -= 1;
        }
        result[i] = s[j];
        if (i == 0 and j == 0) {
            break;
        } else if (i > 0 and j > 0) {} else unreachable;
        i -= 1;
        j -= 1;
    }
    return result;
}

pub fn fill(
    a: std.mem.Allocator,
    template: []const u8,
    o: anytype,
) ![]const u8 {
    var w = try std.Io.Writer.Allocating.initCapacity(a, template.len * 2);
    errdefer w.deinit();
    const writer = &(w.writer);

    var i: usize = 0;
    while (i < template.len) {
        if (std.mem.indexOfPos(u8, template, i, "{{")) |start| {
            if (std.mem.indexOfPos(u8, template, start + 2, "}}")) |end| {
                try writer.writeAll(template[i..start]);
                defer i = end + 2;
                const name = std.mem.trim(u8, template[start + 2 .. end], " ");
                inline for (
                    @typeInfo(@TypeOf(o)).@"struct".fields,
                ) |f| {
                    if (std.mem.eql(u8, f.name, name)) {
                        const field = @field(o, f.name);
                        switch (@typeInfo(@TypeOf(field))) {
                            .int => {
                                const s = try decimalToString(a, field);
                                defer a.free(s);
                                try writer.writeAll(s);
                            },
                            .pointer => |p| {
                                if (p.size != .slice or p.child != u8) {
                                    comptime unreachable;
                                }
                                try writer.writeAll(field);
                            },
                            .@"struct" => return error.InvalidField,
                            else => comptime unreachable,
                        }
                        break;
                    }
                } else {
                    return error.InvalidField;
                }
            } else {
                // If there is no closing }} treat the initial {{ as a literal
                try writer.writeAll(template[i..]);
                break;
            }
        } else {
            try writer.writeAll(template[i..]);
            break;
        }
    }

    return try w.toOwnedSlice();
}
