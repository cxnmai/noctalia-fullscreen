const std = @import("std");
const ipc = @import("ipc.zig");
const model = @import("state.zig");
const events = @import("events.zig");
const Commands = @import("commands.zig").Commands;
const c = ipc.c;
var stopping: bool = false;
fn stop(_: c_int) callconv(.c) void { @atomicStore(bool, &stopping, true, .unordered); }

const help =
    \\Usage: noctalia-fullscreen [--bar NAME] [--noctalia PATH] [--dry-run] [--reset]
    \\Switch existing Noctalia auto-hide Off/Smart using Niri layout events.
    \\Requires reserve_space=true and a nonzero bar size; no polling.
    \\--dry-run  Log commands without changing the bar
    \\--reset    Restore Off/Top on connected monitors and exit
    \\--version  Print version
    \\
;

fn refreshOutputs(state: *model.State) !void {
    const reply = try ipc.outputs();
    defer reply.deinit();
    const outputs = model.get(model.get(reply.value, "Ok"), "Outputs");
    if (outputs == .null) return error.InvalidOutputsReply;
    try state.setOutputs(outputs);
}

fn run() !void {
    const allocator = std.heap.c_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    var commands = Commands{};
    var reset = false;
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}", .{help}); return;
        } else if (std.mem.eql(u8, arg, "--version")) {
            std.debug.print("noctalia-fullscreen 0.1.0\n", .{}); return;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            commands.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--reset")) {
            reset = true;
        } else if (std.mem.eql(u8, arg, "--bar") or std.mem.eql(u8, arg, "--noctalia")) {
            index += 1;
            if (index == args.len or args[index].len == 0) return error.MissingArgument;
            if (std.mem.eql(u8, arg, "--bar")) commands.bar = args[index] else commands.executable = args[index];
        } else return error.UnknownArgument;
    }
    var state = model.State{ .allocator = allocator };
    defer state.deinit();
    try refreshOutputs(&state);
    if (reset) {
        for (state.outputs.items) |output| try commands.set(output.name.slice(), false);
        return;
    }
    const fd = try ipc.connect();
    defer _ = c.close(fd);
    try ipc.send(fd, "\"EventStream\"\n");
    _ = c.signal(c.SIGTERM, stop);
    _ = c.signal(c.SIGINT, stop);
    defer commands.restore(&state);
    var buffer = ipc.Buffer{};
    defer buffer.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    while (!@atomicLoad(bool, &stopping, .unordered)) {
        var pollfd = c.struct_pollfd{ .fd = fd, .events = c.POLLIN, .revents = 0 };
        const ready = c.poll(&pollfd, 1, -1);
        if (ready < 0) {
            if (std.posix.errno(ready) == .INTR) continue;
            return error.PollFailed;
        }
        if (pollfd.revents & (c.POLLERR | c.POLLHUP | c.POLLNVAL) != 0) return error.Disconnected;
        var refresh = false;
        // Drain a complete available batch before applying, avoiding intermediate focus states.
        while (try buffer.receive(fd, c.MSG_DONTWAIT)) {
            while (buffer.line()) |line| {
                defer buffer.consume(line.len);
                const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), line, .{});
                defer _ = arena.reset(.{ .retain_with_limit = 64 * 1024 });
                if (model.get(parsed.value, "Err") != .null) return error.EventStreamRejected;
                refresh = try events.apply(&state, parsed.value) or refresh;
            }
        }
        if (refresh) try refreshOutputs(&state);
        try commands.sync(&state);
    }
}

pub fn main() void {
    run() catch |err| {
        std.debug.print("noctalia-fullscreen: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
