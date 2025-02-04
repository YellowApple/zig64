const std = @import("std");
const PI = @import("./PI.zig");

pub const Bus = enum {
    RDRAM,
    RCP,
    PI,
    SI,

    /// Identifies which bus/device (RDRAM, RCP, PI, SI) corresponds
    /// to the given address.  This matters because different memory
    /// regions have different behaviors:
    ///
    /// - RDRAM and RCP are synchronous; PI and SI are asynchronous
    ///
    /// - RDRAM allows non-32-bit writes; RCP, PI, and SI only allow
    ///   32-bit writes
    pub fn identify(ptr: *anyopaque) Bus {
        var addr = @intFromPtr(ptr);
        // First, convert virtual addresses to physical addresses.
        // FIXME: there's probably a better way to do this, but my
        // bitwise arithmetic is a bit rusty and this is easier to
        // reason about.
        if (addr >= 0xe0000000) addr -= 0xe0000000;
        if (addr >= 0xc0000000) addr -= 0xc0000000;
        if (addr >= 0xa0000000) addr -= 0xa0000000;
        if (addr >= 0x80000000) addr -= 0x80000000;
        // Now we have an actual physical address to map to a physical
        // bus.
        if (0x00000000 <= addr and addr <= 0x03ffffff) return .RDRAM;
        if (0x04000000 <= addr and addr <= 0x04ffffff) return .RCP;
        if (0x05000000 <= addr and addr <= 0x1fbfffff) return .PI;
        if (0x1fc00000 <= addr and addr <= 0x1fcfffff) return .SI;
        if (0x1fd00000 <= addr and addr <= 0x7fffffff) return .PI;
        // Physical address 0x80000000 and beyond is mapped to
        // nothing.  Writes are ignored, and reads will stall the RCP
        // and therefore the CPU.  We've already guaranteed above that
        // we'll never make it to this point (because `addr` should
        // always be less than 0x80000000 after the virtual→physical
        // conversion), hence the `unreachable`.
        unreachable;
    }
};

/// Based on which bus handles the given pointer's physical address,
/// dispatches to a bus-specific wait mechanism (if one is
/// applicable).
pub inline fn wait(bus: Bus) void {
    switch (bus) {
        .RDRAM => {},
        .RCP => {},
        .PI => PI.wait(),
        .SI => {}, // FIXME: implement
    }
}

/// Writes four bytes at a time from src to dest.  Mostly
/// "borrowed" from std.Progress.copyAtomicStore(), which just so
/// happens to do more or less the same thing.
pub fn writeBytes(bus: Bus, dest: []align(4) u8, src: []const u8) void {
    // "But why not just use the built-in Zig functions to copy
    // between byte arrays?" I can already hear you asking.  Well,
    // it's because the RCP's implementation of the SysAd bus is
    // "simplified" such that it has no concept of an "access size";
    // it can only read and write whole (32-bit) words.  Want to write
    // a single byte?  lol no, fuck you, you're writing 32 bits
    // whether you like it or not, and which byte-sized chunk of that
    // word actually gets set (and which bytes get entirely clobbered)
    // is apparently non-deterministic.
    //
    // Or at least that's my impression from reading through
    // https://n64brew.dev/wiki/Memory_map (see the section on RCP
    // registers), and that impression seems to be correct given that
    // this behaves approximately as expected (albeit very unsafely)
    // while byte-by-byte copies only manage to preserve one of every
    // four bytes (both on real hardware and on bug-for-bug LLEs like
    // Ares).
    std.debug.assert(dest.len >= src.len);
    const chunked_len = src.len / 4;
    std.debug.assert((dest.len / 4) + 1 >= chunked_len);
    const dest_chunked: []u32 = @as([*]u32, @ptrCast(dest))[0..chunked_len + 1];
    for (dest_chunked[0..chunked_len], 0..) |*d, i| {
        const s = bytesToWord(src[(i*4)..]);
        writeWord(bus, d, s);
    }
    const extra = bytesToWord(src[(chunked_len * 4)..]);
    writeWord(bus, &dest_chunked[chunked_len], extra);
}

/// Creates a u32 from the first four of the provided bytes, filling
/// in with zeroes if there are less than four bytes.
pub fn bytesToWord(bytes: []const u8) u32 {
    // FIXME: there's probably a much better way to do this.
    var buf: [4]u8 = .{0,0,0,0};
    if (bytes.len >= 1) buf[0] = bytes[0];
    if (bytes.len >= 2) buf[1] = bytes[1];
    if (bytes.len >= 3) buf[2] = bytes[2];
    if (bytes.len >= 4) buf[3] = bytes[3];
    return std.mem.readInt(u32, &buf, .big);
}

/// Waits for the PI to be ready, then writes a word to a pointer.
pub fn writeWord(bus: Bus, pointer: *volatile u32, data: u32) void {
    wait(bus);
    @atomicStore(u32, pointer, data, .monotonic);
}

/// Waits for the PI to be ready, then reads a word from a
/// pointer.
pub fn readWord(bus: Bus, pointer: *volatile u32) u32 {
    wait(bus);
    return @atomicLoad(u32, pointer, .monotonic);
}
