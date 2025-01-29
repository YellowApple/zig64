const std = @import("std");

// BEGIN MEMORY MAP STUFF

var dmem: *align(4) [4096]u8 = @ptrFromInt(0xa4000000);
var imem: *align(4) [4096]u8 = @ptrFromInt(0xa4001000);

/// See https://n64brew.dev/wiki/Peripheral_Interface for details.
const PI = struct {
    const Status = packed struct(u32) {
        dma_busy: bool,
        io_busy: bool,
        dma_error: bool,
        dma_complete: bool,
        reserved: u28,
    };
    var status: *volatile Status = @ptrFromInt(0xa4600010);
    
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

    comptime {
        const bytes = "asdffdsa12344321";
        const i = 1;
        const result = bytes[(i*4)..((i*4)+4)];
        std.debug.assert(std.mem.eql(u8, result, "fdsa"));
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

    comptime {
        const bytes: [4]u8 = .{0x01, 0x23, 0x45, 0x67};
        const word: u32 = bytesToWord(&bytes);
        std.debug.assert(word == 0x01234567);
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
    const Status = packed struct(u32) {
        // I sure hope I got the bit ordering right...
        command_id: u8, // TODO: enum of valid command IDs
        command_irq_request: bool,
        reserved: u13 = 0,
        aux_irq_mask: bool,
        aux_irq_pending: bool,
        usb_irq_mask: bool,
        usb_irq_pending: bool,
        command_irq_mask: bool,
        command_irq_pending: bool,
        button_irq_mask: bool,
        button_irq_pending: bool,
        command_error: bool,
        command_busy: bool,
    };

    comptime {
        var status_struct: Status = .{
            .command_busy = false,
            .command_error = false,
            .button_irq_pending = false,
            .button_irq_mask = false,
            .command_irq_pending = false,
            .command_irq_mask = false,
            .usb_irq_pending = false,
            .usb_irq_mask = false,
            .aux_irq_pending = false,
            .aux_irq_mask = false,
            .command_irq_request = false,
            .command_id = 0,
        };
        var status_int: u32 = @bitCast(status_struct);
        std.debug.assert(status_int == 0);
        status_struct.command_busy = true;
        status_int = @bitCast(status_struct);
        std.debug.assert(status_int == (1 << 31));
        status_struct.command_busy = false;
        status_struct.command_id = 'M';
        status_int = @bitCast(status_struct);
        const command_int: u32 = @intCast('M');
        std.debug.assert(status_int == command_int);
    }

    const Key = enum(u32) {
        Reset = 0x00000000,
        Unlock1 = 0x5f554e4c,
        Unlock2 = 0x4f434b5f,
        Lock = 0xffffffff,
    };

    const IRQ = packed struct(u32) {
        button_clear: bool,
        command_clear: bool,
        usb_clear: bool,
        aux_clear: bool,
        reserved1: u16 = 0,
        usb_disable: bool,
        usb_enable: bool,
        aux_disable: bool,
        aux_enable: bool,
        reserved2: u8 = 0,
    };
    
    const Registers = packed struct {
        status: Status,
        data_0: u32,
        data_1: u32,
        identifier: u32,
        key: Key,
        irq: IRQ,
        aux: u32,
    };
    
    var data_buffer: *align(4) [8192]u8 = @ptrFromInt(0xbffe0000);
    var registers: *volatile Registers = @ptrFromInt(0xbfff0000);

    const register_base: u32 = 0xbfff0000;
    var status: *volatile Status = @ptrFromInt(register_base);
    var data_0: *volatile u32 = @ptrFromInt(register_base + 0x4);
    var data_1: *volatile u32 = @ptrFromInt(register_base + 0x8);
    var identifier: *volatile u32 = @ptrFromInt(register_base + 0xc);
    var key: *volatile Key = @ptrFromInt(register_base + 0x10);
    var irq: *volatile IRQ = @ptrFromInt(register_base + 0x14);
    var aux: *volatile u32 = @ptrFromInt(register_base + 0x18);

    fn present() bool {
        PI.writeWord(@ptrCast(SC64.key), @intFromEnum(SC64.Key.Reset));
        PI.writeWord(@ptrCast(SC64.key), @intFromEnum(SC64.Key.Unlock1));
        PI.writeWord(@ptrCast(SC64.key), @intFromEnum(SC64.Key.Unlock2));
        return PI.readWord(SC64.identifier) == 0x53437632;
    }

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

const ISViewer = struct {
    var write_len: *volatile u32 = @ptrFromInt(0xb3ff0014);
    var buffer: *align(4) [0x200]u8 = @ptrFromInt(0xb3ff0020);
    var buffer_unsafe: [*]u8 = @ptrFromInt(0xb3ff0020);
    const buffer_size = 0x200;

    fn present() bool {
        PI.wait();
        ISViewer.buffer[0] = 0x12;
        PI.wait();
        return (ISViewer.buffer[0] == 0x12);
    }

    fn print(text: []const u8) void {
        PI.writeBytes(buffer, text);
        PI.writeWord(ISViewer.write_len, text.len);
    }
};

// END MEMORY MAP STUFF

// BEGIN DEBUG STUFF

const Debug = struct {
    const Backend = enum {
        Dummy,
        ISViewer,
        SC64,
        ED64,
        @"64Drive",
        IQue,
    };
    var backend: Backend = .Dummy;

    fn detectBackend() Backend {
        if (SC64.present()) return .SC64;
        if (ISViewer.present()) return .ISViewer;
        // FIXME: implement ED64/64Drive/iQue
        return .Dummy;
    }

    fn init() void {
        backend = detectBackend();
    }

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
