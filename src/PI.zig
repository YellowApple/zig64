const std = @import("std");

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
pub const status: *volatile Status = @ptrFromInt(0xa4600010);

/// Waits until the PI is no longer busy processing an I/O or DMA
/// request.  Strongly recommended to run this before reading to or
/// writing from anything on the PI bus to avoid possible race
/// conditions and data corruption.
pub fn wait() void {
    while (status.io_busy or status.dma_busy) {}
}

/// Writes four bytes at a time from src to dest.  Mostly
/// "borrowed" from std.Progress.copyAtomicStore(), which just so
/// happens to do more or less the same thing.
pub fn writeBytes(dest: []align(4) u8, src: []const u8) void {
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
        writeWord(d, s);
    }
    const extra = bytesToWord(src[(chunked_len * 4)..]);
    writeWord(&dest_chunked[chunked_len], extra);
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
pub fn writeWord(pointer: *volatile u32, data: u32) void {
    wait();
    @atomicStore(u32, pointer, data, .monotonic);
}

/// Waits for the PI to be ready, then reads a word from a
/// pointer.
pub fn readWord(pointer: *volatile u32) u32 {
    wait();
    return @atomicLoad(u32, pointer, .monotonic);
}
