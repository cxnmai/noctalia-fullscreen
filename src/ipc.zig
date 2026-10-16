const std = @import("std");
pub const c = @cImport({
    @cInclude("sys/socket.h");
    @cInclude("sys/un.h");
    @cInclude("sys/time.h");
    @cInclude("unistd.h");
    @cInclude("poll.h");
    @cInclude("signal.h");
    @cInclude("errno.h");
});
const allocator = std.heap.c_allocator;
const max_line = 8 * 1024 * 1024;

pub fn connect() !c_int {
    const path = std.posix.getenv("NIRI_SOCKET") orelse return error.MissingNiriSocket;
    var address = std.mem.zeroes(c.struct_sockaddr_un);
    address.sun_family = c.AF_UNIX;
    if (path.len >= address.sun_path.len) return error.SocketPathTooLong;
    @memcpy(@as([*]u8, @ptrCast(&address.sun_path))[0..path.len], path);
    const fd = c.socket(c.AF_UNIX, c.SOCK_STREAM | c.SOCK_CLOEXEC, 0);
    if (fd < 0) return error.SocketFailed;
    errdefer _ = c.close(fd);
    if (c.connect(fd, @ptrCast(&address), @sizeOf(@TypeOf(address))) != 0) return error.ConnectFailed;
    return fd;
}

pub fn send(fd: c_int, bytes: []const u8) !void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const n = c.send(fd, bytes[offset..].ptr, bytes.len - offset, c.MSG_NOSIGNAL);
        if (n <= 0) return error.SendFailed;
        offset += @intCast(n);
    }
}

pub const Buffer = struct {
    bytes: std.ArrayList(u8) = .empty,
    pub fn deinit(self: *Buffer) void {
        self.bytes.deinit(allocator);
    }
    pub fn receive(self: *Buffer, fd: c_int, flags: c_int) !bool {
        var chunk: [8192]u8 = undefined;
        const n = c.recv(fd, &chunk, chunk.len, flags);
        if (n == 0) return error.Disconnected;
        if (n < 0) {
            const err = std.posix.errno(n);
            if (err == .AGAIN or err == .INTR) return false;
            return error.ReceiveFailed;
        }
        if (self.bytes.items.len + @as(usize, @intCast(n)) > max_line) return error.MessageTooLarge;
        try self.bytes.appendSlice(allocator, chunk[0..@intCast(n)]);
        return true;
    }
    pub fn line(self: *Buffer) ?[]const u8 {
        const end = std.mem.indexOfScalar(u8, self.bytes.items, '\n') orelse return null;
        return self.bytes.items[0..end];
    }
    pub fn consume(self: *Buffer, len: usize) void {
        const remaining = self.bytes.items.len - len - 1;
        std.mem.copyForwards(u8, self.bytes.items[0..remaining], self.bytes.items[len + 1 ..]);
        self.bytes.shrinkRetainingCapacity(remaining);
    }
};

pub fn outputs() !std.json.Parsed(std.json.Value) {
    const fd = try connect();
    defer _ = c.close(fd);
    const timeout = c.struct_timeval{ .tv_sec = 3, .tv_usec = 0 };
    _ = c.setsockopt(fd, c.SOL_SOCKET, c.SO_RCVTIMEO, &timeout, @sizeOf(@TypeOf(timeout)));
    try send(fd, "\"Outputs\"\n");
    var buffer = Buffer{};
    defer buffer.deinit();
    while (buffer.line() == null) {
        if (!try buffer.receive(fd, 0)) return error.OutputRequestTimeout;
    }
    return std.json.parseFromSlice(std.json.Value, allocator, buffer.line().?, .{ .allocate = .alloc_always });
}
