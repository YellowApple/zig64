const base = 0xa4100000;

/// On read, returns the last written value.  On write, stores the
/// starting address of a command list and sets
/// `RDP.status.read.start_pending` to `true`.  Address is either in
/// RDRAM or DMEM, depending on the value of
/// `RDP.status.read.read_from_dmem`.  Mapped to the RSP's COP0 as
/// register c8.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_0000_(c8)_-_DPC_START
/// for more details.
pub const start: *volatile u32 = @ptrFromInt(base + 0x0);

/// On read, returns the last written value.  On write, stores the
/// ending address of a command list (exclusively bound, meaning that
/// this should be the address *after* the end of the last command in
/// the list), then either starts a new transfer (if
/// `RDP.status.read.start_pending` is `true` and hasn't started yet),
/// modifies an existing transfer (if `RDP.status.read.start_pending`
/// is `false`), or queues the next transfer (if
/// `RDP.status.read.start_pending` is `true` and has already started;
/// this sets `RDP.status.read.end_pending` to `true` in the process).
/// Address is either in RDRAM or DMEM, depending on the value of
/// `RDP.status.read.read_from_dmem`.  Mapped to the RSP's COP0 as
/// register c9.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_0004_(c9)_-_DPC_END
/// for more details.
pub const end: *volatile u32 = @ptrFromInt(base + 0x4);

/// On read, returns the address after the last command transferred
/// via DMA, allowing a program to track the progress of an ongoing
/// DMA transfer.  Mapped to the RSP's COP0 as register c10.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_0008_(c10)_-_DPC_CURRENT
/// for more details.
pub const current: *volatile u32 = @ptrFromInt(base + 0x8);

/// Status flags.  Mapped to the RSP's COP0 as register c11.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_000C_(c11)_-_DPC_STATUS
/// for more details.
pub const Status = packed union {
    /// Values read from the status register.
    pub const Read = packed struct(u32) {
        /// Is the RDP configured to read commands from DMEM (as
        /// opposed to XBUS/RDRAM)?
        read_from_dmem: bool,
        /// Is the RDP currently frozen (i.e. set to not process
        /// commands)?
        frozen: bool,
        /// Is the RDP configured to flush all transfers
        /// (i.e. immediately terminate all new and in-progress
        /// transfers)?
        flushing: bool,
        /// Is the RDP currently loading bytes into TMEM?
        tmem_busy: bool,
        /// Is the RDP currently reading into its command pipeline?
        pipe_busy: bool,
        /// Is the RDP currently processing a command (i.e. internal
        /// command FIFO is non-empty)?
        cmd_busy: bool,
        /// Unknown.
        cbuf_ready: bool,
        /// Unknown,
        dma_busy: bool,
        /// Is there a pending end for a DMA transfer (i.e. because a
        /// write to `RDP.end` happened while a transfer was in
        /// progress and `RDP.status.read.start_pending` was `true`)?
        end_pending: bool,
        /// Is there a pending start for a DMA transfer (i.e. because
        /// a write to `RDP.start` happened and a corresponding write
        /// to `RDP.end` has not yet happened)?
        start_pending: bool,
        /// Unused.
        unused: u21,
    };

    /// Values written to the status register.
    pub const Write = packed struct(u32) {
        /// If true, sets `RDP.status.read.read_from_dmem` to `false`.
        read_from_xbus: bool,
        /// If true, sets `RDP.status.read.read_from_dmem` to `true`.
        read_from_dmem: bool,
        /// If true, sets `RDP.status.read.frozen` to `false`
        /// (resuming normal RDP operation).
        clear_frozen: bool,
        /// If true, sets `RDP.status.read.frozen` to `true` (halting
        /// the RDP).
        set_frozen: bool,
        /// If true, sets `RDP.status.read.flushing` to `false` (resuming
        /// normal RDP operation).
        clear_flushing: bool,
        /// If true, sets `RDP.status.read.flushing` to `true`
        /// (causing the RDP to instantly terminate all ongoing and
        /// new RDP transfers).
        set_flushing: bool,
        /// If true, resets `RDP.tmem_busy` to zero.
        clear_tmem_busy: bool,
        /// If true, resets `RDP.pipe_busy` to zero.
        clear_pipe_busy: bool,
        /// If true, resets `RDP.cmd_busy` (?; docs unclear) to zero.
        clear_buffer_busy: bool,
        /// If true, resets `RDP.clock` to zero.
        clear_clock: bool,
        /// Unused.
        unused: u22,
    };

    read: Read,
    write: Write,
};
pub const status: *volatile Status = @ptrFromInt(base + 0xc);

/// On read, returns the number of RCP clock cycles since boot (or
/// since the last clock reset via setting
/// `RDP.status.write.clear_clock` to `true`).  Mapped to the RSP's
/// COP0 as register c12.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_0010_(c12)_-_DPC_CLOCK
/// for more details.
pub const clock: *volatile u32 = @ptrFromInt(base + 0x10);

/// On read, returns the number of RCP cycles since boot (or since the
/// last clock reset via setting `RDP.status.write.clear_buffer_busy`
/// to `true`?) wherein the RDP was processing commands (i.e. the
/// command FIFO was non-empty).  Mapped to the RSP's COP0 as register
/// c13.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_0014_(c13)_-_DPC_CMD_BUSY
/// for more details.
pub const cmd_busy: *volatile u32 = @ptrFromInt(base + 0x14);

/// On read, returns the number of RCP cycles since boot (or since the
/// last clock reset via setting `RDP.status.write.clear_pipe_busy` to
/// `true`) wherein the RDP was receiving commands (i.e. between
/// receiving the first command and receiving a `SYNC_FULL` command).
/// Mapped to the RSP's COP0 as register c14.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_0018_(c14)_-_DPC_PIPE_BUSY
/// for more details.
pub const pipe_busy: *volatile u32 = @ptrFromInt(base + 0x18);

/// On read, returns the number of RCP cycles since boot (or since the
/// last clock reset via setting `RDP.status.write.clear_tmem_busy` to
/// `true`) wherein the RDP was reading texture data from TMEM
/// (excluding stalls while waiting for RDRAM).  Mapped to the RSP's
/// COP0 as register c15.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0410_001C_(c15)_-_DPC_TMEM_BUSY
/// for more details.
pub const tmem_busy: *volatile u32 = @ptrFromInt(base + 0x1c);

const test_base = 0xa4200000;

/// Unknown; presumably something to do with span buffer testing.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0420_0000_-_DPS_TBIST
/// for more details.
pub const Tbist = packed struct {
    /// Unknown.
    check: bool,
    /// Unknown.
    go: bool,
    /// Unknown.
    done: bool,
    /// Unknown.
    fail: u8,
    /// Unused.
    unused: u21,
};
pub const tbist: *volatile Tbist = @ptrFromInt(test_base + 0x0);

/// Span buffer testing controls.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0420_0004_-_DPS_TEST_MODE
/// for more details.
pub const TestMode = packed union {
    /// Values read from the buffer testing control register.
    pub const Read = packed struct(u32) {
        /// Is span buffer testing enabled?
        enabled: bool,
        /// Unknown, but the 2nd and 7th bits are allegedy always 1.
        unknown: u11,
        /// Depth span counter 1.
        zspan1: u4,
        /// Depth span counter 0.
        zspan0: u4,
        /// Color span counter 1.
        cspan1: u4,
        /// Color span counter 0.
        cspan0: u4,
        /// Always 0.
        zero: u4,
    };

    /// Values written to the buffer testing control register.
    pub const Write = packed struct(u32) {
        /// Should span buffer testing be enabled?
        enable: bool,
        /// Unused.
        unused: u31,
    };

    read: Read,
    write: Write,
};
pub const test_mode: *volatile TestMode = @ptrFromInt(test_base + 0x4);

/// Address of the word to use for span buffer testing.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0420_0008_-_DPS_BUFTEST_ADDR
/// for more details.
pub const buftest_addr: *volatile u32 = @ptrFromInt(test_base + 0x8);

/// Contents of the word to use for span buffer testing.  See
/// https://n64brew.dev/wiki/Reality_Display_Processor/Interface#0x0420_000C_-_DPS_BUFTEST_DATA
/// for more details.
pub const buftest_addr: *volatile u32 = @ptrFromInt(test_base + 0xc);
