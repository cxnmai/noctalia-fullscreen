const std = @import("std");
const model = @import("state.zig");

pub const Commands = struct {
    executable: []const u8 = "noctalia",
    bar: []const u8 = "main",
    dry_run: bool = false,

    fn call(self: Commands, command: []const u8, value: []const u8, output: []const u8) !void {
        const argv = &[_][]const u8{ self.executable, "msg", command, value, self.bar, output };
        if (self.dry_run) {
            std.debug.print("{s} {s} {s} {s}\n", .{ command, value, self.bar, output });
            return;
        }
        const result = try std.process.Child.run(.{
            .allocator = std.heap.c_allocator,
            .argv = argv,
            .max_output_bytes = 64 * 1024,
        });
        defer std.heap.c_allocator.free(result.stdout);
        defer std.heap.c_allocator.free(result.stderr);
        const ok = switch (result.term) { .Exited => |code| code == 0, else => false };
        // Some CLI versions return success while printing an IPC error.
        if (!ok or std.mem.startsWith(u8, result.stdout, "error:") or
            std.mem.startsWith(u8, result.stderr, "error:")) {
            std.debug.print("Noctalia command failed: {s}{s}\n", .{ result.stdout, result.stderr });
            return error.NoctaliaCommandFailed;
        }
    }
    pub fn set(self: Commands, output: []const u8, fullscreen: bool) !void {
        if (fullscreen) {
            // Retract first, then move the edge trigger above fullscreen clients.
            try self.call("bar-auto-hide-set", "smart", output);
            try self.call("bar-layer-set", "overlay", output);
        } else {
            try self.call("bar-layer-set", "top", output);
            try self.call("bar-auto-hide-set", "off", output);
        }
    }
    pub fn sync(self: Commands, state: *model.State) !void {
        for (state.outputs.items) |*output| {
            const desired = state.desired(output.*);
            if (output.applied != null and output.applied.? == desired) continue;
            try self.set(output.name.slice(), desired);
            output.applied = desired;
            std.debug.print("{s}: {s}\n", .{ output.name.slice(), if (desired) "smart / overlay" else "off / top" });
        }
    }
    pub fn restore(self: Commands, state: *model.State) void {
        for (state.outputs.items) |output| {
            self.set(output.name.slice(), false) catch |err| {
                std.debug.print("Restore {s}: {s}\n", .{ output.name.slice(), @errorName(err) });
            };
        }
    }
};
