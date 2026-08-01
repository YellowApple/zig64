const std = @import("std");

// FIXME: replace or wrap Foo(32,64) with a generic Foo (where Foo is
// a register type that has 32-bit and 64-bit variations) based on
// usize.  Right now Zig64 always compiles in 32-bit mode, following
// the precedent of most commercial games (it ain't like the N64's
// memory map is big enough to justify 64-bit addressing anyway), so
// the Foo32 variation is almost always going to be the one used, but
// that could change at some point.

/// 32-bit version of the Context register.  In the event of a TLB
/// miss, the hardware will populate `.bad_page` and `.pte_base`,
/// which the exception handler can use to load the missed translation
/// into the TLB.
pub const Context32 = packed struct(u32) {
    /// Must be zero.
    reserved: u4 = 0,
    /// Bits 31:13 of the virtual address that caused the TLB miss.
    /// Equivalently, the virtual address' page number, divided by
    /// two.
    bad_page: u19,
    /// Base address of the page table entry.
    pte_base: u9,

    /// Get COP0's (32-bit) Context register.
    pub inline fn get() Context32 {
        return asm volatile ("mfc0 %[c], $4"
            : [c] "=r" (-> Context32),
        );
    }

    /// Set COP0's (32-bit) Context register.
    pub inline fn set(context: Context32) void {
        asm volatile ("mtc0 %[c], $4"
            :
            : [c] "r" (context),
        );
    }
};

/// 64-bit version of the Context register.  In the event of a TLB
/// miss, the hardware will populate `.bad_page` and `.pte_base`, and
/// the exception handler can control the latter to load the missing
/// translation into the TLB.
pub const Context64 = packed struct(u64) {
    /// Must be zero.
    reserved: u4 = 0,
    /// Bits 31:13 of the virtual address that caused the TLB miss.
    /// Equivalently, the virtual address' page number, divided by
    /// two.
    bad_page: u19,
    /// Base address of the page table entry.
    pte_base: u41,

    /// Get COP0's (64-bit) Context register.
    pub inline fn get() Context64 {
        return asm volatile ("mfc0 %[c], $4"
            : [c] "=r" (-> Context64),
        );
    }

    /// Set COP0's (64-bit) Context register.
    pub inline fn set(context: Context64) void {
        asm volatile ("mtc0 %[c], $4"
            :
            : [c] "r" (context),
        );
    }
};

/// 32-bit version of the BadVAddr register.  This holds the most
/// recent virtual address that was invalid for translation or
/// triggered an addressing error.  Read-only.
pub const BadVAddr32 = struct {
    /// Get COP0's (32-bit) BadVAddr register.
    pub inline fn get() u32 {
        return asm volatile ("mfc0 %[a], $8"
            : [a] "=r" (-> u32),
        );
    }
};

/// 64-bit version of the BadVAddr register.  This holds the most
/// recent virtual address that was invalid for translation or
/// triggered an addressing error.  Read-only.
pub const BadVAddr64 = struct {
    /// Get COP0's (64-bit) BadVAddr register.
    pub inline fn get() u64 {
        return asm volatile ("mfc0 %[a], $8"
            : [a] "=r" (-> u64),
        );
    }
};

/// Count register.  Increments by one every two clock ticks.  On
/// overflow (i.e. incrementing past `0xFFFFFFFF`), rolls over back to
/// zero.  Useful for timers (see `Compare`).  Read-only.
pub const Count = struct {
    pub inline fn get() u32 {
        return asm volatile ("mfc0 %[c], $9"
            : [c] "=r" (-> u32),
        );
    }
};

/// Compare register.  When the Count register reaches this value,
/// this triggers Interrupt 7 (a.k.a. the timer interrupt).  Setting
/// this register clears Interrupt 7 as a side effect.
pub const Compare = struct {
    pub inline fn get() u32 {
        return asm volatile ("mfc0 %[c], $11"
            : [c] "=r" (-> u32),
        );
    }

    pub inline fn set(compare: u32) void {
        asm volatile ("mtc0 %[c], $11"
            :
            : [c] "r" (compare),
        );
    }
};

/// Status register.  Used to examine and control exception handling
/// and execution mode settings.
pub const Status = packed struct(u32) {
    pub const KSU = enum(u2) {
        kernel = 0,
        supervisor = 1,
        user = 2,
    };

    pub const InterruptMask = packed struct(u8) {
        /// Is Interrupt 0 (software) enabled?
        software0: bool,
        /// Is Interrupt 1 (software) enabled?
        software1: bool,
        /// Is Interrupt 2 (hardware, RCP) enabled?
        rcp: bool,
        /// Is Interrupt 3 (hardware, CART) enabled?
        cart: bool,
        /// Is Interrupt 4 (hardware, PRENMI) enabled?
        prenmi: bool,
        /// Is Interrupt 5 (hardware) enabled?
        hardware5: bool,
        /// Is Interrupt 6 (hardware) enabled?
        hardware6: bool,
        /// Is Interrupt 7 (hardware, timer) enabled?
        timer: bool,
    };

    pub const DiagnosticStatus = packed struct(u9) {
        /// Unused (VR4200 compat).
        de: bool,
        /// Unused (VR4200 compat).
        ce: bool,
        /// What COP0's condition?
        cop0_condition: bool,
        /// Unused; must be false.
        reserved0: bool = false,
        /// Has a Soft Reset or NMI occurred?
        soft_reset: bool,
        /// Has a TLB shutdown occurred?
        tlb_shutdown: bool,
        /// Are the TLB miss and general purpose instruction vectors
        /// in their bootstrap location?
        bootstrap_exception_vectors: bool,
        /// Unused; must be false.
        reserved1: bool = false,
        /// Is Instruction Trace Support enabled?
        instruction_trace_support: bool,
    };

    pub const CoprocessorUsability = packed struct(u4) {
        /// Is COP0 usable?
        cop0: bool,
        /// Is COP1 usable?
        cop1: bool,
        /// Is COP2 usable?
        cop2: bool,
        /// Is COP3 usable?
        cop3: bool,
    };

    /// Are interrupts enabled?
    interrupts_enabled: bool,
    /// Is there an unhandled exception?
    exception_level: bool,
    /// Is there an unhandled error?
    error_level: bool,
    /// Execution mode.
    execution_mode: KSU,
    /// Are 64-bit addresses and operations enabled in User mode?
    user_64bit: bool,
    /// Are 64-bit addresses and operations enabled in Supervisor
    /// mode?
    supervisor_64bit: bool,
    /// Are 64-bit addresses and operations enabled in Kernel mode?
    kernel_64bit: bool,
    /// Which interrupts are enabled?
    interrupt_mask: InterruptMask,
    /// Diagnostic status.
    diagnostic_status: DiagnosticStatus,
    /// Does User mode have reversed system endianness compared to
    /// Kernel/Supervisor modes?  For example, if Kernel/Supervisor
    /// modes are big-endian (the default on boot/reset), then User
    /// mode will be little-endian if this is true.
    reverse_endian: bool,
    /// Are additional floating point registers (32 v. 16) enabled?
    extra_fp_registers_enabled: bool,
    /// Are we in Low Power Mode (1/4 clock frequency)?
    low_power_mode: bool,
    /// Which coprocessors are usable?
    coprocessor_usable: CoprocessorUsability,

    /// Get COP0's Status register.
    pub inline fn get() Status {
        return asm volatile ("mfc0 %[s], $12"
            : [s] "=r" (-> Status),
        );
    }

    /// Set COP0's Status register.
    pub inline fn set(status: Status) void {
        asm volatile ("mtc0 %[s], $12"
            :
            : [s] "r" (status),
        );
    }
};

/// Cause register.  Describes the most recent exception.
pub const Cause = packed struct(u32) {
    pub const Exception = enum(u5) {
        /// Interrupt (i.e. not really an exception).
        interrupt = 0,
        /// TLB modified.
        tlb_modification = 1,
        /// TLB miss during a load or instruction fetch.
        tlb_miss_load = 2,
        /// TLB miss during a store.
        tlb_miss_store = 3,
        /// Address error during a load or instruction fetch.
        address_error_load = 4,
        /// Address error during a store.
        address_error_store = 5,
        /// Bus error during an instruction fetch.
        bus_error_instruction = 6,
        /// Bus error during a load or store.
        bus_error_data = 7,
        /// System call invoked.
        syscall = 8,
        /// Breakpoint reached.
        breakpoint = 9,
        /// Attempted to execute a reserved instruction.
        reserved_instruction = 10,
        /// Attempted to use an unusable coprocessor.
        coprocessor_unusable = 11,
        /// Performed an arithmetic operation that overflowed.
        overflow = 12,
        /// Trap instruction reached.
        trap = 13,
        /// Attempted an invalid floating-point operation.
        floating_point = 15,
        /// Watched value accessed.
        watch = 23,
    };

    pub const PendingInterrupts = packed struct(u8) {
        /// Is Interrupt 0 (software) pending?
        software0: bool,
        /// Is Interrupt 1 (software) pending?
        software1: bool,
        /// Is Interrupt 2 (hardware, RCP) pending?
        rcp: bool,
        /// Is Interrupt 3 (hardware, CART) pending?
        cart: bool,
        /// Is Interrupt 4 (hardware, PRENMI) pending?
        prenmi: bool,
        /// Is Interrupt 5 (hardware) pending?
        hardware5: bool,
        /// Is Interrupt 6 (hardware) pending?
        hardware6: bool,
        /// Is Interrupt 7 (hardware, timer) pending?
        timer: bool,
    };

    /// Must be zero.
    reserved0: u2 = 0,
    /// Most recent exception.
    exception: Exception,
    /// Are any interrupts pending?
    interrupts: PendingInterrupts,
    /// Must be zero.
    reserved1: u12 = 0,
    /// When `.exception = Exception.coprocessor_unusable`, the
    /// coprocessor that was unusable.
    coprocessor: u2,
    /// Must be false.
    reserved2: bool = false,
    /// Did the most recent exception happen while executing a branch
    /// delay slot?
    branch_delay: bool,

    /// Get COP0's Cause register.
    pub inline fn get() Cause {
        return asm volatile ("mfc0 %[c], $13"
            : [c] "=r" (-> Cause),
        );
    }

    /// Set COP0's Cause register.
    pub inline fn set(cause: Cause) void {
        asm volatile ("mtc0 %[c], $13"
            :
            : [c] "r" (cause),
        );
    }
};

/// 32-bit version of the Exception Program Counter (EPC) register.
/// Upon raising an exception, the hardware sets this register to the
/// address of the instruction that triggered the exception (so that
/// the handler can jump past it and resume normal execution after
/// handling and clearing the exception).  If the exception happened
/// while executing an instruction in a branch delay slot, EPC will
/// instead be the address of the preceding branch instruction (and
/// `Cause.branch_delay` will be `true`).
pub const EPC32 = struct {
    /// Get COP0's (32-bit) Exception Program Counter (EPC) register.
    pub inline fn get() u32 {
        return asm volatile ("mfc0 %[p], $14"
            : [p] "=r" (-> u32),
        );
    }
};

/// 64-bit version of the Exception Program Counter (EPC) register.
/// Upon raising an exception, the hardware sets this register to the
/// address of the instruction that triggered the exception (so that
/// the handler can jump past it and resume normal execution after
/// handling and clearing the exception).  If the exception happened
/// while executing an instruction in a branch delay slot, EPC will
/// instead be the address of the preceding branch instruction (and
/// `Cause.branch_delay` will be `true`).
pub const EPC64 = struct {
    /// Get COP0's (64-bit) Exception Program Counter (EPC) register.
    pub inline fn get() u64 {
        return asm volatile ("mfc0 %[p], $14"
            : [p] "=r" (-> u64),
        );
    }
};

/// Watch register.  Stores bits 31:3 of a physical address to watch.
/// If `Watch.read` is `true`, the hardware will raise a watch
/// exception upon any reads to the specified address.  If
/// `Watch.write` is true, the hardware will raise a watch exception
/// upon any writes to the specified address.
///
/// This is technically (in e.g. the VR4300 User's Manual) called
/// "WatchLo", and there is a corresponding "WatchHi" register to load
/// bits 35:32 of the address to monitor.  However, the VR4300 only
/// has a 32-bit physical address space (any bits outside of 31:0 are
/// ignored), so in practice you're only going to ever be using
/// WatchLo as "the" Watch register, since WatchHi serves no purpose
/// when specifically targeting the VR4300 like we are (WatchHi is
/// only present and "usable" for compatibility with the VR4400 and
/// VR4200).
pub const Watch = packed struct(u32) {
    /// Raise watch exception on write?
    write: bool,
    /// Raise watch exception on read?
    read: bool,
    /// Must be false.
    reserved: bool = false,
    /// Bits 31:3 of the physical address to monitor.
    address: u29,

    /// Get COP0's Watch register.
    pub inline fn get() Watch {
        return asm volatile ("mfc0 %[w], $18"
            : [w] "=r" (-> Watch),
        );
    }

    /// Set COP0's Watch register.
    pub inline fn set(watch: Watch) void {
        asm volatile ("mtc0 %[w], $18"
            :
            : [w] "r" (watch),
        );
    }
};

/// XContext register.  In the event of a TLB miss (in 64-bit
/// addressing mode), the hardware will populate `.bad_page` and
/// `.pte_base`, which the exception handler can use to load the
/// missed translation into the TLB.
pub const XContext = packed struct(u64) {
    pub const KSU = enum(u2) {
        user = 0,
        supervisor = 1,
        kernel = 3,
    };

    /// Must be zero.
    reserved: u4 = 0,
    /// Bits 39:13 of the virtual address that caused the TLB miss.
    /// Equivalently, the virtual address' page number, divided by
    /// two.
    bad_page: u27,
    /// Execution mode / address space identifier (Kernel, Supervisor,
    /// User).  Equivalently, bits 63:62 of the virtual address.
    space_identifier: KSU,
    /// Base address of the page table entry.
    pte_base: u31,

    /// Get COP0's XContext register.
    pub inline fn get() XContext {
        return asm volatile ("mfc0 %[c], $20"
            : [c] "=r" (-> XContext),
        );
    }

    /// Set COP0's XContext register.
    pub inline fn set(context: XContext) void {
        asm volatile ("mtc0 %[c], $20"
            :
            : [c] "r" (context),
        );
    }
};

/// 32-bit version of the Error Exception Program Counter (ErrorEPC)
/// register.  Similar to the EPC register, but for handling Cold/Soft
/// Resets and NMIs.  Unlike EPC, there is no branch delay slot
/// indicator for ErrorEPC.
pub const ErrorEPC32 = struct {
    /// Get COP0's (32-bit) Error Exception Program Counter (ErrorEPC)
    /// register.
    pub inline fn get() u32 {
        return asm volatile ("mfc0 %[p], $30"
            : [p] "=r" (-> u32),
        );
    }
};

/// 64-bit version of the Error Exception Program Counter (ErrorEPC)
/// register.  Similar to the EPC register, but for handling Cold/Soft
/// Resets and NMIs.  Unlike EPC, there is no branch delay slot
/// indicator for ErrorEPC.
pub const ErrorEPC64 = struct {
    /// Get COP0's (64-bit) Error Exception Program Counter (ErrorEPC)
    /// register.
    pub inline fn get() u64 {
        return asm volatile ("mfc0 %[p], $30"
            : [p] "=r" (-> u64),
        );
    }
};
