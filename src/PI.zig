const std = @import("std");
const memory = @import("./memory.zig");

/// PI status register fields.
pub const Status = packed union {
    /// Values read from the PI status register.
    pub const Read = packed struct(u32) {
        /// If true, PI is busy handling a DMA operation.
        dma_busy: bool,
        /// If true, PI is busy handling an I/O operation.
        io_busy: bool,
        /// If true, the previous DMA request encountered an error.
        dma_error: bool,
        /// If true, the previous DMA request is complete.
        dma_complete: bool,
        /// Reserved.
        reserved: u28 = 0,
    };

    /// Values written to the PI status register.
    pub const Write = packed struct(u32) {
        /// If true, resets the DMA controller and stops any
        /// in-progress transfer.
        reset: bool,
        /// If true, clears any pending PI interrupt.
        clear: bool,
        /// Reserved.
        reserved: u30 = 0,
    };

    read: Read,
    write: Write,
};
pub const status: *volatile Status = @ptrFromInt(0xa4600010);

/// Waits until the PI is no longer busy processing an I/O or DMA
/// request.  Strongly recommended to run this before reading to or
/// writing from anything on the PI bus to avoid possible race
/// conditions and data corruption.
pub fn wait() void {
    while (status.read.io_busy or status.read.dma_busy) {}
}

pub inline fn writeBytes(dest: []align(4) u8, src: []const u8) void {
    memory.writeBytesToBus(.PI, dest, src);
}

/// Waits for the PI to be ready, then writes a word to a pointer.
pub inline fn writeWord(pointer: *volatile u32, data: u32) void {
    memory.writeWordToBus(.PI, pointer, data);
}

/// Waits for the PI to be ready, then reads a word from a
/// pointer.
pub inline fn readWord(pointer: *volatile u32) u32 {
    return memory.readWordFromBus(.PI, pointer);
}
