const std = @import("std");
const memory = @import("./memory.zig");

const base = 0xa4600000;

/// RDRAM address for RDRAM<->PI DMAs.  Hardcoded to be an even number
/// (i.e. LSB is hardcoded to zero).  Recommended to be a multiple of
/// eight (i.e. the three least significant bits are all zero,
/// i.e. should be 64-bit aligned).  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_0000_-_PI_DRAM_ADDR
/// for more details.
pub const dma_rdram_address: *volatile u32 = @ptrFromInt(base + 0x0); // u24

/// PI bus address for RDRAM<->PI DMAs.  Hardcoded to be an even
/// number (i.e. LSB is hardcoded to zero).  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_0004_-_PI_CART_ADDR
/// for more details.
pub const dma_pi_address: *volatile u32 = @ptrFromInt(base + 0x4); // u24

/// Number of bytes (minus one) to read from the PI bus (starting at
/// `PI.dma_pi_address`) into RDRAM (starting at
/// `PI.dma_rdram_address`).  Writing to this value starts the DMA
/// transfer.  Reading from this value always returns `0x7f`.  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_0008_-_PI_RD_LEN
/// for more details.
pub const dma_read_length: *volatile u32 = @ptrFromInt(base + 0x8); // u24

/// Number of bytes (minus one) to write to the PI bus (starting at
/// `PI.dma_pi_address`) from RDRAM (starting at
/// `PI.dma_rdram_address`).  Writing to this value starts the DMA
/// transfer.  Reading from this value always returns `0x7f`.  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_000C_-_PI_WR_LEN
/// for more details.
pub const dma_write_length: *volatile u32 = @ptrFromInt(base + 0xc); // u24

/// PI status register fields.  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_0010_-_PI_STATUS
/// for more details.
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
pub const status: *volatile Status = @ptrFromInt(base + 0x10);

/// Latch for PI Domain 1: number of RCP cycles (minus one) to wait
/// between sending an address (ALE_L high->low) and sending the data
/// to be read from / written to that address (/RD or /WR high->low).
/// See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00n4_-_PI_BSD_DOMn_LAT
/// for more details.
pub const latch_dom1: *volatile u32 = @ptrFromInt(base + 0x14);

/// Latch for PI Domain 2: number of RCP cycles (minus one) to wait
/// between sending an address (ALE_L high->low) and sending the data
/// to be read from / written to that address (/RD or /WR high->low).
/// See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00n4_-_PI_BSD_DOMn_LAT
/// for more details.
pub const latch_dom2: *volatile u32 = @ptrFromInt(base + 0x24);

/// Pulse width for PI Domain 1: number of RCP cycles (minus one) to
/// spend setting the value to read from / write to the PI (i.e. how
/// long to hold /RD or /WR low).  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00n8_-_PI_BSD_DOMn_PWD
/// for more details.
pub const pulse_width_dom1: *volatile u32 = @ptrFromInt(base + 0x18);

/// Pulse width for PI Domain 2: number of RCP cycles (minus one) to
/// spend setting the number of bytes to read from / write to the PI
/// (i.e. how long to hold /RD or /WR low).  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00n8_-_PI_BSD_DOMn_PWD
/// for more details.
pub const pulse_width_dom2: *volatile u32 = @ptrFromInt(base + 0x28);

/// Page size for PI Domain 1: determines the number of bytes to
/// transfer at a time via DMA, via the formula `2^(PI.page_size_dom1
/// + 2)`.  Minimum is 0 (4 bytes); maximum is 15 (128 kilobytes).
/// See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00nC_-_PI_BSD_DOMn_PGS
/// for more details.
pub const page_size_dom1: *volatile u32 = @ptrFromInt(base + 0x1c);

/// Page size for PI Domain 2: determines the number of bytes to
/// transfer at a time via DMA, via the formula `2^(PI.page_size_dom2
/// + 2)`.  Minimum is 0 (4 bytes); maximum is 15 (128 kilobytes).
/// See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00nC_-_PI_BSD_DOMn_PGS
/// for more details.
pub const page_size_dom2: *volatile u32 = @ptrFromInt(base + 0x2c);

/// Release for PI Domain 1: number of RCP cycles (minus one) to wait
/// between each 16-bit read or write (i.e. how long to hold /RD or
/// /WR high between each half-word to read or write).  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00n0_-_PI_BSD_DOMn_RLS
/// for more details.
pub const release_dom1: *volatile u32 = @ptrFromInt(base + 0x20);

/// Release for PI Domain 2: number of RCP cycles (minus one) to wait
/// between each 16-bit read or write (i.e. how long to hold /RD or
/// /WR high between each half-word to read or write).  See
/// https://n64brew.dev/wiki/Peripheral_Interface#0x0460_00n0_-_PI_BSD_DOMn_RLS
/// for more details.
pub const release_dom2: *volatile u32 = @ptrFromInt(base + 0x30);

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
