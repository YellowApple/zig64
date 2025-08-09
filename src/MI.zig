const base = 0xa4300000;

/// Configuration values controlling communication between the CPU and
/// RDRAM; reading and writing use different structures and field
/// definitions, so make sure you're always reading a Read and writing
/// a Write.  See
/// https://n64brew.dev/wiki/MIPS_Interface#0x0430_0000_-_MI_MODE for
/// more details.
pub const Mode = packed union {
    /// Values read from the MI's mode register.
    pub const Read = packed struct(u32) {
        /// How many bytes (minus 1) will repeat mode write?
        repeat_count: u7,
        /// Is repeat mode on?  If so, the next write to RDRAM will
        /// write repeat_count+1 bytes (up to 128 bytes) starting at
        /// the write's target address, and then repeat mode will
        /// automatically clear itself.  Used to quickly fill memory
        /// regions with patterns, and also during IPL3's
        /// initialization of RDRAM.
        repeat: bool,
        /// Is EBus mode on?  If so, 4 bits of EBus will reflect the
        /// read/written 32-bit word's lower 4 bits.  Used mainly to
        /// allow the CPU to access the "9th bit" that the RDP and VI
        /// see alongside each byte of memory they access.
        ebus: bool,
        /// Is Upper mode on?  If so, 32bit transfers are shifted into
        /// the 64bit bus' upper half (instead of the lower half
        /// during normal operation).  Used to access registers at odd
        /// offsets (whereas "normal" mode can access registers at
        /// even offsets).
        upper: bool,
        /// Unused.
        unused: u22 = 0,
    };

    /// Values written to the MI's mode register.
    pub const Write = packed struct(u32) {
        /// How many bytes (minus 1) will repeat mode write?
        repeat_count: u7,
        /// Turn off repeat mode for the next RDRAM operation.
        clear_repeat: bool,
        /// Turn on repeat mode for the next RDRAM operation.
        set_repeat: bool,
        /// Turn off EBus mode.
        clear_ebus: bool,
        /// Turn on EBus mode.
        set_ebus: bool,
        /// Clear the DP interrupt.
        clear_dp: bool,
        /// Turn off Upper mode.
        clear_upper: bool,
        /// Turn on Upper mode.
        set_upper: bool,
        /// Unused.
        unused: u18 = 0,
    };

    read: Read,
    write: Write,
};
pub const mode: *volatile Mode = @ptrFromInt(base + 0x0);

/// Hardware version information.  See
/// https://n64brew.dev/wiki/MIPS_Interface#0x0430_0004_-_MI_VERSION
/// for more details.
pub const Version = packed struct(u32) {
    /// IO hardware version.  Usually 0x02 on retail N64s or 0xB0 on
    /// retail iQues.
    io: u8,
    /// RAC hardware version.  Usually 0x01 on retail N64s or 0xB0 on
    /// retail iQues.
    rac: u8,
    /// RDP hardware version.  Usually 0x02 on retail N64s and iQues.
    rdp: u8,
    /// RSP hardware version.  Usually 0x02 on retail N64s and iQues.
    rsp: u8,
};
pub const version: *volatile Version = @ptrFromInt(base + 0x4);

/// Interrupt statuses for memory-mapped hardware.  See
/// https://n64brew.dev/wiki/MIPS_Interface#0x0430_0008_-_MI_INTERRUPT
/// for more details.
pub const Interrupt = packed struct(u32) {
    /// Has the RSP raised an interrupt?  Raised when either the RSP
    /// or CPU has set the "interrupt" flag in the RSP's status
    /// register, or when the "interrupt on break" flag in the RSP's
    /// status register is set and the RSP executes a BREAK
    /// instruction.
    sp: bool,
    /// Has the SI raised an interrupt?  Raised when a DMA operation
    /// to/from PIF RAM (via SI) finishes.
    si: bool,
    /// Has the AI raised an interrupt?  Raised when the AI is ready
    /// to queue up a new audio buffer.
    ai: bool,
    /// Has the VI raised an interrupt?  Raised when `VI.v_current ==
    /// VI.v_interrupt` (which is equivalent to a vertical blank
    /// interrupt if `VI.v_interrupt == 2`, as is the case with
    /// Zig64's default VI initialization code).
    vi: bool,
    /// Has the PI raised an interrupt?  Raised when a DMA operation
    /// to/from the PI finishes.
    pi: bool,
    /// Has the RDP raised an interrupt?  Raised when the RDP finishes
    /// a full sync in response to a SYNC_FULL command.
    dp: bool,
    /// Unused.
    unused: u26 = 0,
};
pub const interrupt: *volatile Interrupt = @ptrFromInt(base + 0x8);

/// Interrupt masks for memory-mapped hardware; reading and writing
/// use different structures and field definitions, so make sure
/// you're always reading a Read and writing a Write.  See
/// https://n64brew.dev/wiki/MIPS_Interface#0x0430_000C_-_MI_MASK for
/// more details.
pub const Mask = packed union {
    /// Values read from the MI's mask register.
    pub const Read = packed struct(u32) {
        /// Are (R)SP interrupts masked?
        sp: bool,
        /// Are SI interrupts masked?
        si: bool,
        /// Are AI interrupts masked?
        ai: bool,
        /// Are VI interrupts masked?
        vi: bool,
        /// Are PI interrupts masked?
        pi: bool,
        /// Are (R)DP interrupts masked?
        dp: bool,
        /// Unused.
        unused: u26 = 0,
    };

    /// Values written to the MI's mask register.
    pub const Write = packed struct(u32) {
        /// Unmask (R)SP interrupts.
        clear_sp: bool,
        /// Mask (R)SP interrupts.
        set_sp: bool,
        /// Unmask SI interrupts.
        clear_si: bool,
        /// Mask SI interrupts.
        set_si: bool,
        /// Unmask AI interrupts.
        clear_ai: bool,
        /// Mask AI interrupts.
        set_ai: bool,
        /// Unmask VI interrupts.
        clear_vi: bool,
        /// Mask VI interrupts.
        set_vi: bool,
        /// Unmask PI interrupts.
        clear_pi: bool,
        /// Mask PI interrupts.
        set_pi: bool,
        /// Unmask (R)DP interrupts.
        clear_dp: bool,
        /// Mask (R)DP interrupts.
        set_dp: bool,
        /// Unused.
        unused: u20 = 0,
    };

    read: Read,
    write: Write,
};
pub const mask: *volatile Mask = @ptrFromInt(base + 0xc);
