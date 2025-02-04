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

/// Waits for the given bus to be ready for a new I/O operation.
pub inline fn wait(bus: Bus) void {
    switch (bus) {
        .RDRAM => {},
        .RCP => {},
        .PI => PI.wait(),
        .SI => {}, // FIXME: implement
    }
}

/// Writes four bytes at a time from src to dest, automatically
/// detecting the bus to use.
pub fn writeBytes(dest: []align(4) u8, src: []const u8) void {
    const bus = Bus.identify(dest);
    writeBytesToBus(bus, dest, src);
}

/// Writes four bytes at a time from src to dest, manually specifying
/// the bus to use.
pub fn writeBytesToBus(
    bus: Bus,
    dest: []align(4) u8,
    src: []const u8
) void {
    // "But why not just use @memcpy or std.mem.copyForward?" I can
    // already hear you asking.  Well, two reasons for that:
    //
    // 1. The RCP only respects the access size parameter in SysCMD
    // when handling CPU←→RDRAM I/O.  For CPU←→(RDRAM/PI/SI) I/O, it
    // uses a "simplified" interface that ignores the access size and
    // always reads/writes 32-bits.  For reads that's fine as long as
    // it's 32-bits or less (the CPU can ignore unneeded bytes), but
    // for writes that means they *have* to be four bytes at a time.
    // Want to write a single byte to RDRAM/PI/SI addresses?  No, fuck
    // you, four bytes are getting written whether you like it or not.
    //
    // 2. Writes to the PI and SI are asynchronous, and each can only
    // handle one I/O operation at a time, so we gotta wait between
    // each four-byte chunk or else we'll end up writing garbled
    // nonsense.
    //
    // These factors combined mean you can't do the byte-by-byte
    // writes that std.mem likes to do by default.  Even if you're
    // dealing in arrays/slices of 32-bit items instead of 8-bit
    // items, std.mem's functions assume writes are synchronous and
    // there's no way to tell them otherwise.  @memcpy seems to be
    // okay for RCP-mapped addresses (like DMEM and IMEM, and most
    // interface registers), but if the start/end addresses don't line
    // up with word boundaries then you're probably gonna be
    // corrupting data.
    //
    // Speaking of start/end addresses, a FIXME: be able to properly
    // handle writes that don't start and/or end on 32-bit boundaries.
    // If `dest` starts mid-word, it should be possible to read the
    // existing word, merge it with the actual bytes to be written,
    // then go word-by-word.  Likewise, if `dest` ends mid-word, it
    // should be possible to read the existing word and merge it with
    // the actual bytes to be written.  As it stands, this code
    // type-constraints `dest` to `align(4)`, and forcibly pads a
    // partial-word ending with nulls.  Once this FIXME is addressed,
    // it'll be possible to write
    // `std.io.(Reader/Writer/SeekableStream)` wrappers around
    // non-RDRAM addresses without having to worry so much about
    // clobbers from partial-word writes.
    std.debug.assert(dest.len >= src.len);
    const chunked_len = src.len / 4;
    std.debug.assert((dest.len / 4) + 1 >= chunked_len);
    const dest_chunked: []u32 = @as([*]u32, @ptrCast(dest))[0..chunked_len + 1];
    for (dest_chunked[0..chunked_len], 0..) |*d, i| {
        const s = bytesToWord(src[(i*4)..]);
        writeWordToBus(bus, d, s);
    }
    const extra = bytesToWord(src[(chunked_len * 4)..]);
    writeWordToBus(bus, &dest_chunked[chunked_len], extra);
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

/// Waits for the given pointer's bus to be ready, then writes a word
/// to it.
pub fn writeWord(pointer: *volatile u32, data: u32) void {
    writeWordToBus(Bus.identify(pointer), pointer, data);
}

/// Waits for the given pointer's bus to be ready, then reads a word
/// from it.
pub fn readWord(pointer: *volatile u32) u32 {
    return readWordFromBus(Bus.identify(pointer), pointer);
}

/// Waits for the given bus to be ready, then writes a word to a
/// pointer.
pub fn writeWordToBus(bus: Bus, pointer: *volatile u32, data: u32) void {
    wait(bus);
    @atomicStore(u32, pointer, data, .monotonic);
}

/// Waits for the given bus to be ready, then reads a word from a
/// pointer.
pub fn readWordFromBus(bus: Bus, pointer: *volatile u32) u32 {
    wait(bus);
    return @atomicLoad(u32, pointer, .monotonic);
}
