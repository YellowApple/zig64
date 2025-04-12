const root = @import("root");
const std = @import("std");

// BEGIN MEMORY MAP STUFF

pub const dmem: *align(4) [4096]u8 = @ptrFromInt(0xa4000000);
pub const imem: *align(4) [4096]u8 = @ptrFromInt(0xa4001000);

/// Peripheral Interface memory regions.  See
/// https://n64brew.dev/wiki/Peripheral_Interface for details.
pub const PI = @import("./PI.zig");

pub const VI = @import("./VI.zig");

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

    /// Sends text via the detected debug logging backend.
    pub fn print(comptime fmt: []const u8, args: anytype) void {
        switch (backend) {
            .Dummy => {},
            .ISViewer => ISViewer.print(fmt, args),
            .SC64 => SC64.print(fmt, args),
            .ED64 => {}, // FIXME: implement
            .@"64Drive" => {}, // FIXME: implement
            .IQue => {}, // FIXME: implement
        }
    }
};

// END DEBUG STUFF

// BEGIN EVERYTHING ELSE

pub const cop0 = @import("./cop0.zig");

/// N64 ROM entry point.  IPL3 calls this function after initializing
/// RDRAM and loading our code into it.
pub fn start() callconv(.C) noreturn {
    Debug.init();
    if (@hasDecl(root, "main"))
        root.main()
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
    Debug.print("PANIC: {s}\n", .{msg});
    Debug.print("trace = {?}\n", .{trace});
    Debug.print("addr = {x}\n", .{addr orelse @returnAddress()});
    while (true) {}
}

// END EVERYTHING ELSE
