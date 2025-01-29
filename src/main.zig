const std = @import("std");

// BEGIN MEMORY MAP STUFF

var dmem: *align(4) [4096]u8 = @ptrFromInt(0xa4000000);
var imem: *align(4) [4096]u8 = @ptrFromInt(0xa4001000);

/// Peripheral Interface memory regions.  See
/// https://n64brew.dev/wiki/Peripheral_Interface for details.
const PI = struct {
    /// PI status register fields.
    const Status = packed struct(u32) {
        /// If true, PI is busy handling a DMA operation.
        dma_busy: bool,
        /// If true, PI is busy handling an I/O operation.
        io_busy: bool,
        /// If true, the previous DMA request encountered an error.
        dma_error: bool,
        /// If true, the previous DMA request is complete.
        dma_complete: bool,
        /// Reserved.
        reserved: u28,
    };
    var status: *volatile Status = @ptrFromInt(0xa4600010);

    /// Waits until the PI is no longer busy processing an I/O or DMA
    /// request.  Strongly recommended to run this before reading to
    /// or writing from anything on the PI bus to avoid possible race
    /// conditions and data corruption.
    fn wait() void {
        while (status.io_busy or status.dma_busy) {}
    }

    /// Writes four bytes at a time from src to dest.  Mostly
    /// "borrowed" from std.Progress.copyAtomicStore(), which just so
    /// happens to do more or less the same thing.
    fn writeBytes(dest: []align(4) u8, src: []const u8) void {
        // "But why not just use the built-in Zig functions to copy
        // between byte arrays?" I can already hear you asking.  Well,
        // it's because the RCP's implementation of the SysAd bus is
        // "simplified" such that it has no concept of an "access
        // size"; it can only read and write whole (32-bit) words.
        // Want to write a single byte?  lol no, fuck you, you're
        // writing 32 bits whether you like it or not, and which
        // byte-sized chunk of that word actually gets set (and which
        // bytes get entirely clobbered) is apparently
        // non-deterministic.
        //
        // Or at least that's my impression from reading through
        // https://n64brew.dev/wiki/Memory_map (see the section on RCP
        // registers), and that impression seems to be correct given
        // that this behaves approximately as expected (albeit very
        // unsafely) while byte-by-byte copies only manage to preserve
        // one of every four bytes (both on real hardware and on
        // bug-for-bug LLEs like Ares).
        std.debug.assert(dest.len >= src.len);
        const chunked_len = src.len / 4;
        std.debug.assert((dest.len / 4) + 1 >= chunked_len);
        const dest_chunked: []u32 = @as([*]u32, @ptrCast(dest))[0..chunked_len + 1];
        for (dest_chunked[0..chunked_len], 0..) |*d, i| {
            const s = bytesToWord(src[(i*4)..]);
            writeWord(d, s);
        }
        const extra = bytesToWord(src[(chunked_len * 4)..]);
        writeWord(&dest_chunked[chunked_len], extra);
    }

    /// Creates a u32 from the first four of the provided bytes,
    /// filling in with zeroes if there are less than four bytes.
    fn bytesToWord(bytes: []const u8) u32 {
        // FIXME: there's probably a much better way to do this.
        var buf: [4]u8 = .{0,0,0,0};
        if (bytes.len >= 1) buf[0] = bytes[0];
        if (bytes.len >= 2) buf[1] = bytes[1];
        if (bytes.len >= 3) buf[2] = bytes[2];
        if (bytes.len >= 4) buf[3] = bytes[3];
        return std.mem.readInt(u32, &buf, .big);
    }

    /// Waits for the PI to be ready, then writes a word to a pointer.
    fn writeWord(pointer: *volatile u32, data: u32) void {
        wait();
        @atomicStore(u32, pointer, data, .monotonic);
    }

    /// Waits for the PI to be ready, then reads a word from a
    /// pointer.
    fn readWord(pointer: *volatile u32) u32 {
        wait();
        return @atomicLoad(u32, pointer, .monotonic);
    }
};

/// SummerCart 64 memory map and helper functions.  See
/// https://github.com/Polprzewodnikowy/SummerCart64/blob/main/docs/01_memory_map.md
/// for details.
const SC64 = struct {
    /// SC64 status/command register fields.
    const Status = packed struct(u32) {
        // I sure hope I got the bit ordering right...
        /// ID of the command to execute.
        command_id: u8, // TODO: enum of valid command IDs
        /// If true, the SC64 will raise a cart interrupt when command
        /// execution finishes.
        command_irq_request: bool,
        /// Reserved; should be zero.
        reserved: u13 = 0,
        /// Read-only.  If true, "AUX not empty" interrupts are
        /// enabled.
        aux_irq_mask: bool,
        /// Read-only.  If true, an "AUX not empty" interrupt is
        /// pending.
        aux_irq_pending: bool,
        /// Read-only.  If true, "USB not empty" interrupts are
        /// enabled.
        usb_irq_mask: bool,
        /// Read-only.  If true, a "USB not empty" interrupt is
        /// pending.
        usb_irq_pending: bool,
        /// Read-only.  If true, "command finished" interrupts are
        /// enabled.
        command_irq_mask: bool,
        /// Read-only.  If true, a "command finished" interrupt is
        /// pending.
        command_irq_pending: bool,
        /// Read-only.  If true, "button pressed" interrupts are
        /// enabled.
        button_irq_mask: bool,
        /// Read-only.  If true, a "button pressed" interrupt is
        /// pending.
        button_irq_pending: bool,
        /// Read-only.  If true, the most recent command encountered
        /// an error.
        command_error: bool,
        /// Read-only.  If true, the SC64 is currently executing a
        /// command.
        command_busy: bool,
    };

    /// Magic values to enable or disable SC64-specific memory
    /// regions.  To enable SC64-specific memory regions, set
    /// `SC64.key` to `.Reset`, then `.Unlock1`, then `.Unlock2`.  To
    /// disable SC64-specific memory regions, set the key register to
    /// `.Lock`.
    const Key = enum(u32) {
        Reset = 0x00000000,
        Unlock1 = 0x5f554e4c, // _UNL
        Unlock2 = 0x4f434b5f, // OCK_
        Lock = 0xffffffff,
    };

    /// IRQ register fields.
    const IRQ = packed struct(u32) {
        /// Reserved.  Should be zero.
        reserved1: u8 = 0,
        /// If true, enable "AUX not empty" interrupts.
        enable_aux: bool,
        /// If true, enable "AUX not empty" interrupts.
        disable_aux: bool,
        /// If true, enable "USB not empty" interrupts.
        enable_usb: bool,
        /// If true, enable "USB not empty" interrupts.
        disable_usb: bool,
        /// Reserved.  Should be zero.
        reserved2: u16 = 0,
        /// If true, clear pending "AUX not empty" interrupt.
        clear_aux: bool,
        /// If true, clear pending "USB not empty" interrupt.
        clear_usb: bool,
        /// If true, clear pending "command finished" interrupt.
        clear_cmd: bool,
        /// If true, clear pending "button pressed" interrupt.
        clear_btn: bool,
    };

    /// General-purpose data buffer.  Useful for USB reads/writes.
    var data_buffer: *align(4) [8192]u8 = @ptrFromInt(0xbffe0000);

    const register_base: u32 = 0xbfff0000;
    /// Status/command register.  Writes control command execution.
    /// Reads provide info on command execution status and
    /// enabled/raised interrupts.  See the `SC64.Status` docs for
    /// more info.
    var status: *volatile Status = @ptrFromInt(register_base);
    /// Data register 0.  Stores the first result of the previous
    /// command or the first argument of the next command.
    var data_0: *volatile u32 = @ptrFromInt(register_base + 0x4);
    /// Data register 1.  Stores the second result of the previous
    /// command or the second argument of the next command.
    var data_1: *volatile u32 = @ptrFromInt(register_base + 0x8);
    /// Read-only.  Flashcart identifier.  If this equals `0x53437632`
    /// (ASCII `SCv2`), the SC64's registers are enabled.  Otherwise,
    /// the SC64's registers (except for `SC64.key` are disabled.  If
    /// entering the unlock sequence into `SC64.key` doesn't change
    /// this value to `0x53437672`, then the inserted cartridge is not
    /// a SummerCart 64.
    var identifier: *volatile u32 = @ptrFromInt(register_base + 0xc);
    /// Write-only.  To enable the SC64's registers:
    ///
    /// - `PI.wait(); SC64.key = .Reset;`
    /// - `PI.wait(); SC64.key = .Unlock1;`
    /// - `PI.wait(); SC64.key = .Unlock2;`
    ///
    /// To disable the SC64's registers:
    ///
    /// - `PI.wait(); SC64.key = .Lock;`
    var key: *volatile Key = @ptrFromInt(register_base + 0x10);
    /// Write-only.  Enables/disables interrupts and clears pending
    /// interrupts.  See `SC64.IRQ` for more details.
    var irq: *volatile IRQ = @ptrFromInt(register_base + 0x14);
    /// General-purpose data register.  If the cart has received an
    /// AUX signal from a host PC over USB, the value of that signal
    /// can be read from here.  Likewise, writing to this register
    /// will send an AUX signal via USB.  AUX values greater than or
    /// equal to `0xFF000000` are reserved for SC64 internal use.
    var aux: *volatile u32 = @ptrFromInt(register_base + 0x18);

    /// Attempts to enable SC64-specific memory registers.  Returns
    /// true if successful.  If false, then the inserted cartridge is
    /// not a SummerCart 64.
    fn present() bool {
        PI.writeWord(@ptrCast(SC64.key), @intFromEnum(SC64.Key.Reset));
        PI.writeWord(@ptrCast(SC64.key), @intFromEnum(SC64.Key.Unlock1));
        PI.writeWord(@ptrCast(SC64.key), @intFromEnum(SC64.Key.Unlock2));
        return PI.readWord(SC64.identifier) == 0x53437632;
    }

    /// Sends text via the SC64's USB port.  If the SC64 is connected
    /// to a PC and the PC is running `sc64deployer debug`, the text
    /// will display in the debug output.
    fn print(text: []const u8) void {
        PI.writeBytes(data_buffer, text);
        PI.writeWord(SC64.data_0, @intFromPtr(data_buffer));
        // TODO: packed struct instead of bitshift shenanigans?
        PI.writeWord(SC64.data_1, (text.len & 0xffffff) | (1 << 24));
        PI.wait();
        SC64.status.command_id = 'M';
        PI.wait();
        while (SC64.status.command_busy) {}
    }
};

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
const ISViewer = struct {
    /// Writing to this register will cause the (emulated) IS-Viewer
    /// to read the specified number of bytes from `ISViewer.buffer`
    /// and display them in the emulator's text output.
    var write_len: *volatile u32 = @ptrFromInt(0xb3ff0014);
    /// Buffer to store text to be sent via (emulated) IS-Viewer to
    /// the emulator.
    var buffer: *align(4) [0x200]u8 = @ptrFromInt(0xb3ff0020);

    /// If true, an IS-Viewer (or an emulation thereof) is available.
    /// Otherwise, false.
    fn present() bool {
        PI.wait();
        ISViewer.buffer[0] = 0x12;
        PI.wait();
        return (ISViewer.buffer[0] == 0x12);
    }

    /// Sends text via the (emulated) IS-Viewer.
    fn print(text: []const u8) void {
        PI.writeBytes(buffer, text);
        PI.writeWord(ISViewer.write_len, text.len);
    }
};

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

/// N64 ROM entry point.  Libdragon's IPL3 calls this function after
/// initializing RDRAM and loading our code into it.
pub export fn _start() linksection(".boot") noreturn {
    Debug.init();
    Debug.print("All your Nintendo 64 are belong to us.\n");
    const dmem_test_pat: [16]u8 align(4) = .{
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe
    };
    PI.writeBytes(dmem, &dmem_test_pat);
    while (true) {}
}

/// Just calls _start().  This seems redundant, but `zig build` seems
/// to complain about it being missing for some reason.
export fn __start() noreturn {
    _start();
    while (true) {}
}

// END EVERYTHING ELSE
