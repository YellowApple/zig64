const memory = @import("./memory.zig");

const base = 0xa4800000;

/// PIF ROM.  Usually this is locked down, such that attempting to
/// read values from these addresses will simply return 0.  However,
/// this *is* readable if you use `cop0.Watch.set()` (or otherwise set
/// the MIPS COP0 WatchLo register) to set a breakpoint at `0xbfc00000`,
/// register a breakpoint interrupt handler, and kick off a soft
/// reset; the interrupt handler will then be able to read
/// `SI.pif_rom` (and save it elsewhere, e.g. DMEM).  See
/// https://n64brew.dev/wiki/Serial_Interface#Mapped_PIF-ROM_and_PIF-RAM
/// for more details.
pub const pif_rom: *align(4) [1984]u8 = @ptrFromInt(0xbfc00000);

/// PIF RAM.  Reads are synchronous (and will automatically wait for
/// any pending writes to complete); writes are asynchronous.  See
/// https://n64brew.dev/wiki/Serial_Interface#Mapped_PIF-ROM_and_PIF-RAM
/// for more details.
pub const pif_ram: *align(4) [64]u8 = @ptrFromInt(0xbfc007c0);

/// RDRAM address to use when reading from / writing to the SI via
/// DMA.  During a DMA transfer, the SI updates this to reflect the
/// last-accessed RDRAM address.  See
/// https://n64brew.dev/wiki/Serial_Interface#0x0480_0000_-_SI_DRAM_ADDR
/// for more details.
pub const dma_rdram_address: *volatile u32 = @ptrFromInt(base + 0x0);

/// On write, starts a 64-byte DMA transfer from PIF (starting at the
/// provided address) to RDRAM (starting at `SI.dma_rdram_address`).
/// The lowest two bits are fixed to zero, i.e. the PIF address is
/// aligned to 8 bytes / a multiple of 8.  See
/// https://n64brew.dev/wiki/Serial_Interface#0x0480_0004_-_SI_PIF_AD_RD64B
/// for more details.
pub const dma_read_64: *volatile u32 = @ptrFromInt(base + 0x4);

/// On read, returns the most recent 32-bit word sent or received via
/// SI.  On write, asynchronously writes the written value to whatever
/// PIF address the SI considers to be "current" (i.e. most recently
/// read or written PIF address).  This is pointless to use, given
/// that directly writing to `SI.pif_ram` accomplishes the exact same
/// thing much more straightforwardly, but if for some reason you
/// really want to use this, then see
/// https://n64brew.dev/wiki/Serial_Interface#0x0480_0008_-_SI_PIF_AD_WR4B
/// for more details.
pub const dma_write_4: *volatile u32 = @ptrFromInt(base + 0x8);

/// Currently undocumented; I assume it's supposed to be the "write"
/// equivalent of `SI.dma_read_64`.  Caveat emptor.  See
/// https://n64brew.dev/wiki/Serial_Interface#0x0480_0010_-_SI_PIF_AD_WR64B
/// for more details (if any are added in the future).
pub const dma_write_64: *volatile u32 = @ptrFromInt(base + 0x10);

/// On read, returns the most recent 32-bit word sent or received via
/// SI.  On write, reads a value from whatever PIF address the SI
/// considers to be "current" (i.e. most recently read or written PIF
/// address).  This is pointless to use, given that directly reading
/// from `SI.pif_ram` (or `SI.pif_rom`) accomplishes the exact same
/// thing much more straightforwardly, but if for some reason you
/// really want to use this, then see
/// https://n64brew.dev/wiki/Serial_Interface#0x0480_0014_-_SI_PIF_AD_RD4B
/// for more details.
pub const dma_read_4: *volatile u32 = @ptrFromInt(base + 0x14);

/// Status information.  Writing any value marks any raised interrupts
/// as acknowledged.  See
/// https://n64brew.dev/wiki/Serial_Interface#0x0480_0018_-_SI_STATUS
/// for more details.
pub const Status = packed struct(u32) {
    /// Is there a DMA transfer or IO write in progress?
    dma_busy: bool,
    /// Is there a direct memory write in progress?
    io_busy: bool,
    /// Unknown.
    read_pending: bool,
    /// Was there a DMA error (i.e. overlapping DMA requests or a
    /// write to a misaligned address)?
    dma_error: bool,
    /// If greater than zero, there is activity on the internal PIF
    /// channel.
    pch_state: u4,
    /// If greater than zero, there is DMA transfer activity.
    dma_state: u4,
    /// Is there a pending SI interrupt (i.e. DMA transfer or direct
    /// write has finished)?
    interrupt: bool,
    /// Unused.
    unused: u19,
};
pub const status: *volatile Status = @ptrFromInt(base + 0x18);

/// Waits until the SI is no longer busy processing an I/O or DMA
/// request.  Strongly recommended to run this before writing to
/// anything on the SI bus to avoid possible race conditions and data
/// corruption (reading should be fine, since it's synchronous and
/// already waits for any pending write requests to complete, but it
/// doesn't hurt to explicitly wait anyway).
pub fn wait() void {
    while (status.io_busy or status.dma_busy) {}
}

/// Waits for the SI to be ready, then writes bytes (four at a time)
/// to a (32-bit aligned) pointer.
pub inline fn writeBytes(dest: []align(4) u8, src: []const u8) void {
    memory.writeBytesToBus(.SI, dest, src);
}

/// Waits for the SI to be ready, then writes a word to a pointer.
pub inline fn writeWord(pointer: *volatile u32, data: u32) void {
    memory.writeWordToBus(.SI, pointer, data);
}

/// Waits for the SI to be ready, then reads a word from a pointer.
pub inline fn readWord(pointer: *volatile u32) u32 {
    return memory.readWordFromBus(.SI, pointer);
}
