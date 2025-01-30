const std = @import("std");
const posix = std.posix;

handle: posix.fd_t,
termios: posix.termios,
original_termios: posix.termios,

const Self = @This();

pub fn init(handle: posix.fd_t) !Self {
    const original_termios = try posix.tcgetattr(handle);

    return .{
        .handle = handle,
        .termios = original_termios,
        .original_termios = original_termios,
    };
}

pub fn deinit(self: *Self) void {
    posix.tcsetattr(self.handle, .FLUSH, self.original_termios) catch {};
}

pub fn getLFlag(self: *Self) posix.tc_lflag_t {
    return self.termios.lflag;
}

pub fn setLFlag(self: *Self, flag: posix.tc_lflag_t) !void {
    self.termios.lflag = flag;
    try posix.tcsetattr(self.handle, .FLUSH, self.termios);
}
