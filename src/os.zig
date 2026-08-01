const root = @import("root");
const std = @import("std");

// BEGIN MEMORY MAP STUFF

pub const dmem: *align(4) [4096]u8 = @ptrFromInt(0xa4000000);
pub const imem: *align(4) [4096]u8 = @ptrFromInt(0xa4001000);

/// Peripheral Interface memory regions.  See
/// https://n64brew.dev/wiki/Peripheral_Interface for details.
pub const PI = @import("./PI.zig");

pub const VI = @import("./VI.zig");

pub const MI = @import("./MI.zig");

pub const RI = @import("./RI.zig");

pub const SI = @import("./SI.zig");

/// SummerCart 64 memory map and helper functions.  See
/// https://github.com/Polprzewodnikowy/SummerCart64/blob/main/docs/01_memory_map.md
/// for details.
pub const SC64 = @import("./SC64.zig");

/// IS-Viewer memory map and helper functions.  This operates in
/// "libdragon" style rather than "libultra" style - meaning that this
/// will probably misbehave with an actual IS-Viewer cartridge and
/// software.  Instead, this is intended for emulators which advertise
/// "IS-Viewer-compatible" debug messaging support; known to work with
/// Ares, and Cen64 and Simple64 should work with it in theory (but
/// this is untested).  The SummerCart 64 also apparently has
/// IS-Viewer compatibility, though this is disabled by default (and
/// redundant anyway, given that Zig64 already natively supports the
/// SC64 via the `SC64` namespace).
pub const ISViewer = @import("./ISViewer.zig");

pub const memory = @import("./memory.zig");

comptime {
    std.debug.assert(memory.Bus.identify(SC64.data_buffer) == .PI);
    std.debug.assert(memory.Bus.identify(dmem) == .RCP);
}

// END MEMORY MAP STUFF

// BEGIN DEBUG STUFF

/// Debug helper functions.
pub const Debug = struct {
    /// Available backends for debug output.
    const Backend = enum {
        /// Disable debug logging entirely; calling `Debug.print()`
        /// will do nothing.
        Dummy,
        /// Send debug messages to an emulator's text console output
        /// (via an approximate emulation of an IS-Viewer cartridge).
        /// Probably won't work with real IS-Viewer cartridges.
        ISViewer,
        /// Send debug messages to a connected PC via the SummerCart
        /// 64's USB port.
        SC64,
        /// Not yet implemented.
        ED64,
        /// Not yet implemented.
        @"64Drive",
        /// Not yet implemented.
        IQue,
    };
    /// Backend to use for debug logging.
    var backend: Backend = .Dummy;

    /// Detects the available backend.
    fn detectBackend() Backend {
        if (SC64.present()) return .SC64;
        if (ISViewer.present()) return .ISViewer;
        // FIXME: implement ED64/64Drive/iQue
        return .Dummy;
    }

    /// Detects and sets the available backend.
    pub fn init() void {
        backend = detectBackend();
    }

    fn dummyDrain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
        _ = io_w;
        _ = splat;
        return data[0].len;
    }

    fn dummyWriter(buffer: []u8) std.Io.Writer {
        return .{
            .buffer = buffer,
            .vtable = &.{.drain = dummyDrain},
        };
    }

    /// Creates a std.Io.Writer that proxies writes to the configured
    /// backend.
    pub fn writer(buffer: []u8) std.Io.Writer {
        switch (backend) {
            .Dummy => return dummyWriter(buffer),
            .ISViewer => return ISViewer.writer(buffer),
            .SC64 => return SC64.writer(buffer),
            .ED64 => return dummyWriter(buffer), // FIXME: implement
            .@"64Drive" => return dummyWriter(buffer), // FIXME: implement
            .IQue => return dummyWriter(buffer), // FIXME: implement
        }
    }
};

// END DEBUG STUFF

// BEGIN EVERYTHING ELSE

pub const cop0 = @import("./cop0.zig");

/// N64 ROM entry point.  IPL3 calls this function after initializing
/// RDRAM and loading our code into it.
pub fn start() callconv(.c) noreturn {
    Debug.init();
    if (@hasDecl(root, "main"))
        root.main() catch @panic("main() returned an error")
    else
        @panic("no main(); nothing to do");
    @panic("main() returned");
}

comptime {
    @export(&start, .{
        .name = "__start",
        .linkage = .strong,
        .section = ".boot",
    });
}

/// Panic handler.  Stack traces are WIP.
pub fn panic(
    msg: []const u8,
    trace: ?*std.builtin.StackTrace,
    addr: ?usize
) noreturn {
    var writer = Debug.writer(&.{});
    writer.print("PANIC: {s}\n", .{msg}) catch unreachable;
    writer.print("trace = {any}\n", .{trace}) catch unreachable;
    writer.print("addr = {x}\n", .{addr orelse @returnAddress()}) catch unreachable;
    while (true) {}
}

// END EVERYTHING ELSE
