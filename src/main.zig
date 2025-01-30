const std = @import("std");

// BEGIN MEMORY MAP STUFF

const dmem: *align(4) [4096]u8 = @ptrFromInt(0xa4000000);
const imem: *align(4) [4096]u8 = @ptrFromInt(0xa4001000);

/// Peripheral Interface memory regions.  See
/// https://n64brew.dev/wiki/Peripheral_Interface for details.
const PI = @import("./PI.zig");

const VI = @import("./VI.zig");

/// SummerCart 64 memory map and helper functions.  See
/// https://github.com/Polprzewodnikowy/SummerCart64/blob/main/docs/01_memory_map.md
/// for details.
const SC64 = @import("./SC64.zig");

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
const ISViewer = @import("./ISViewer.zig");

// END MEMORY MAP STUFF

// BEGIN DEBUG STUFF

/// Debug helper functions.
const Debug = struct {
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
    fn init() void {
        backend = detectBackend();
    }

    /// Sends text via the detected debug logging backend.
    fn print(text: []const u8) void {
        switch (backend) {
            .Dummy => {},
            .ISViewer => ISViewer.print(text),
            .SC64 => SC64.print(text),
            .ED64 => {}, // FIXME: implement
            .@"64Drive" => {}, // FIXME: implement
            .IQue => {}, // FIXME: implement
        }
    }
};

// END DEBUG STUFF

// BEGIN EVERYTHING ELSE

/// N64 ROM entry point.  IPL3 calls this function after initializing
/// RDRAM and loading our code into it.
export fn __start() linksection(".boot") noreturn {
    Debug.init();
    Debug.print("All your Nintendo 64 are belong to us.\n");
    Debug.print("This is another message from Zig.\n");
    const dmem_test_pat: [16]u8 align(4) = .{
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe
    };
    PI.writeBytes(dmem, &dmem_test_pat);
    const pxl: VI.Pixel16 = .{ .r = 31, .g = 31, .b = 0, .a = 0 };
    const test_framebuffer: [320][240]VI.Pixel16 = .{.{pxl} ** 240} ** 320;
    VI.origin.* = @intFromPtr(&test_framebuffer);
    VI.setup(.{});
    while (true) {}
}

pub fn panic(
    msg: []const u8,
    _: ?*std.builtin.StackTrace,
    _: ?usize
) noreturn {
    Debug.print("PANIC: ");
    Debug.print(msg);
    Debug.print("\n");
    while (true) {}
}

// END EVERYTHING ELSE
