const std = @import("std");
const c = @cImport({
    @cInclude("sys/eventfd.h");
    @cInclude("signal.h");
    @cInclude("unistd.h");
    @cInclude("errno.h");
});
pub const quit: u8 = 1;
pub const resync: u8 = 2;
var fd: c_int = -1;
var pending: u8 = 0;

fn handler(signal: c_int) callconv(.c) void {
    const saved_errno = c.__errno_location().*;
    _ = @atomicRmw(u8, &pending, .Or, if (signal == c.SIGHUP) resync else quit, .monotonic);
    const one: u64 = 1;
    _ = c.write(fd, &one, @sizeOf(u64));
    c.__errno_location().* = saved_errno;
}
pub fn init() !c_int {
    fd = c.eventfd(0, c.EFD_CLOEXEC | c.EFD_NONBLOCK);
    if (fd < 0) return error.EventFdFailed;
    _ = c.signal(c.SIGTERM, handler);
    _ = c.signal(c.SIGINT, handler);
    _ = c.signal(c.SIGHUP, handler);
    return fd;
}
pub fn deinit() void {
    _ = c.signal(c.SIGTERM, c.SIG_DFL);
    _ = c.signal(c.SIGINT, c.SIG_DFL);
    _ = c.signal(c.SIGHUP, c.SIG_DFL);
    _ = c.close(fd);
}
pub fn take() u8 {
    var value: u64 = 0;
    _ = c.read(fd, &value, @sizeOf(u64));
    return @atomicRmw(u8, &pending, .Xchg, 0, .monotonic);
}
