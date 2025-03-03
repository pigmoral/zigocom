const std = @import("std");
const options = @import("options");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const io = std.io;
const process = std.process;
const fmt = std.fmt;
const fs = std.fs;
const posix = std.posix;
const log = std.log;

const zig_serial = @import("serial");

const Term = @import("Term.zig");

const usage =
    \\Usage: zigocom [options] <port>
    \\
    \\Options:
    \\  -h, --help                    Print this help and exit
    \\  -b, --baudrate [baudrate]     Set the baudrate (default: 115200)
    \\
;

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    process.exit(1);
}

fn loop(serial: fs.File) !void {
    var buf: [256]u8 = undefined;

    const stdout = io.getStdOut();
    const stdin = io.getStdIn();

    var fds = [_]posix.pollfd{
        .{
            .fd = serial.handle,
            .events = posix.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = stdin.handle,
            .events = posix.POLL.IN,
            .revents = 0,
        },
    };

    while (true) {
        _ = posix.poll(&fds, -1) catch |err| {
            log.err("poll failed: {s}\n", .{@errorName(err)});
            break;
        };

        if (fds[0].revents & posix.POLL.IN != 0) {
            const count = serial.read(buf[0..]) catch 0;
            if (count == 0) break;
            _ = try stdout.write(buf[0..count]);
        }

        if (fds[1].revents & posix.POLL.IN != 0) {
            const count = stdin.read(buf[0..]) catch 0;
            if (count == 0) break;
            _ = try serial.write(buf[0..count]);
        }
    }
}

fn mainArgs(gpa: Allocator, arena: Allocator, args: []const []const u8) !void {
    _ = gpa;
    _ = arena;

    var opt_port: ?[]const u8 = null;
    var opt_baudrate: ?u32 = null;

    {
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (mem.startsWith(u8, arg, "-")) {
                if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                    const stdout = io.getStdOut().writer();
                    try stdout.writeAll(usage);
                    return process.cleanExit();
                } else if (mem.eql(u8, arg, "-b") or mem.eql(u8, arg, "--baudrate")) {
                    if (i + 1 >= args.len) fatal("expected argument after '{s}'", .{arg});
                    i += 1;
                    opt_baudrate = try fmt.parseInt(u32, args[i], 10);
                } else {
                    fatal("unrecognized parameter: '{s}'", .{arg});
                }
            } else if (opt_port != null) {
                fatal("unexpected extra parameter: '{s}'", .{arg});
            } else {
                opt_port = arg;
            }
        }
    }

    const port = opt_port orelse fatal("missing port argument", .{});

    const serial_config: zig_serial.SerialConfig = .{
        .baud_rate = opt_baudrate orelse 115200,
    };

    var serial = std.fs.cwd().openFile(port, .{ .mode = .read_write }) catch |err| {
        fatal("failed to open port '{s}', {s}", .{ port, @errorName(err) });
    };
    defer serial.close();

    if (options.locking) {
        const locked = serial.tryLock(.exclusive) catch |err| {
            fatal("failed to lock port '{s}', {s}", .{ port, @errorName(err) });
        };
        if (locked) {
            defer serial.unlock();
        } else fatal("failed to lock port '{s}', {s}", .{ port, "port is locked" });
    }

    try zig_serial.configureSerialPort(serial, serial_config);

    std.debug.print("port: {s}, baudrate: {d}\n", .{ port, serial_config.baud_rate });

    var term = try Term.init(io.getStdIn().handle);
    defer term.deinit();

    var lflag = term.getLFlag();
    lflag.ICANON = false;
    lflag.ECHO = false;
    try term.setLFlag(lflag);

    try loop(serial);
}

pub fn main() !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_instance.deinit();
    const gpa = gpa_instance.allocator();

    var arena_instance = std.heap.ArenaAllocator.init(gpa);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try process.argsAlloc(arena);
    defer process.argsFree(arena, args);

    return mainArgs(gpa, arena, args);
}
