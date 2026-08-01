const std = @import("std");

// BEGIN MEMORY MAP STUFF

var dmem: *[4096]u8 = @ptrFromInt(0xa4000000);
var imem: *[4096]u8 = @ptrFromInt(0xa4001000);

/// See https://n64brew.dev/wiki/Peripheral_Interface for details.
const PI = struct {
    const Status = packed struct(u32) {
        reserved: u28,
        dma_complete: bool,
        dma_error: bool,
        io_busy: bool,
        dma_busy: bool,
    };
    var status: *volatile Status = @ptrFromInt(0xa4600010);

    inline fn wait() void {
        while (status.io_busy or status.dma_busy) {}
    }
};

/// See
/// https://github.com/Polprzewodnikowy/SummerCart64/blob/main/docs/01_memory_map.md
/// for details.
const SC64 = struct {
    const Registers = packed struct {
        const Status = packed struct(u32) {
            // I sure hope I got the bit order right...
            command_busy: bool,
            command_error: bool,
            button_irq_pending: bool,
            button_irq_mask: bool,
            command_irq_pending: bool,
            command_irq_mask: bool,
            usb_irq_pending: bool,
            usb_irq_mask: bool,
            aux_irq_pending: bool,
            aux_irq_mask: bool,
            reserved: u13 = 0,
            command_irq_request: bool,
            command_id: u8,
        };

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

        status: Status,
        data_0: u32,
        data_1: u32,
        identifier: u32,
        key: Key,
        irq: IRQ,
        aux: u32,
    };

    var data_buffer: *[8192]u8 = @ptrFromInt(0xbffe0000);
    var registers: *volatile Registers = @ptrFromInt(0xbfff0000);
};

// END MEMORY MAP STUFF

// BEGIN STAGE 0

/// N64 cartridge header.  See https://n64brew.dev/wiki/ROM_Header for
/// details on what these fields mean.
const ROMHeader = extern struct {
    pi_dom1_config: u32 align(1) = 0x80371240,
    clock_rate: u32 align(1) = 0x0000000f,
    boot_address: u32 align(1) = 0x80000400,
    sdk_version: u32 align(1) = 0x0000144c,
    checksum: u64 align(1) = 0,
    reserved1: u64 align(1) = 0,
    title: [20]u8 align(1) = "Zig N64 Demo        ".*,
    reserved2: [7]u8 align(1) = .{ 0, 0, 0, 0, 0, 0, 0 },
    gamecode: [4]u8 align(1) = "NZGA".*,
    rom_version: u8 align(1) = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == 64);
        std.debug.assert(@bitSizeOf(@This()) == 64 * 8);
    }
};

export var rom_header: ROMHeader linksection(".header") = .{
    // In the real world we'd probably be overriding some of the
    // defaults, at the very least `title` (and possibly `gamecode`
    // and `rom_version`).
};

// IPL3 boot trampoline from the "dev" version of libdragon's IPL3
// loader (boot/boot_trampoline.S).  Overwrites itself with proper
// hardware initialization code (a.k.a. the "real" IPL3) found at
// 0x10001000 in the ROM.  Also includes a magic number to make it
// pass the N64's checksum-based signature checking (i.e. the whole
// point of needing to bake an IPL3 into the ROM in the first place).
comptime {
    // I guess this is one way to find out if Zig/LLVM and GCC are
    // compatible when it comes to inline MIPS assembly...
    asm (
        \\    .set noreorder
        \\    .section .text.ipl3_trampoline
        \\IPL3Trampoline:
        \\    # addiu    $t2, $t3, .Lend-.Lstart-4
        \\    addiu    $t2, $t3, 36
        \\1:  lw       $ra, %lo(.Lstart-0xA4000040)($t3)
        \\    sw       $ra, %lo(0xA4000000-0xA4000040)($t3)
        \\    bne      $t3, $t2, 1b
        \\    addiu    $t3, 4
        \\    lui      $t1, 0xA400
        \\    lui      $t2, 0xB000
        \\    jr       $t1
        \\    addiu    $t3, $t2, 0xFC0
        \\.Lstart:
        \\2:  lw       $ra, 0x1040($t2)
        \\    sw       $ra, 0x0040($t1)
        \\    addiu    $t2, 4
        \\    bne      $t2, $t3, 2b
        \\    addiu    $t1, 4
        \\    or       $t1, $0, $0
        \\    addiu    $t2, $0, 0x40
        \\    addiu    $t3, $sp, 0xA4000040-0xA4001FF0
        \\    jr       $t3
        \\    addiu    $ra, $sp, 0xA4001550-0xA4001FF0
        \\.Lend:
        \\    .fill 0xFC0-(.Lend-IPL3Trampoline)-8, 1, 0
        \\    .quad 0x00030e413340ba87
    );
}

// iQue boot trampoline from the "dev" version of libdragon's IPL3
// loader (boot/ique_trampoline.S).  Overwrites itself with proper
// hardware initialization code.  iQues don't do the whole checksum
// checking shenanigans normal N64s do, so this is slightly less
// involved than the IPL3 boot trampoline.
comptime {
    asm (
        \\    .set noreorder
        \\    .section .text.ique_trampoline
        \\IQUETrampoline:
        \\    lui     $t2, 0xB000
        \\    lui     $t1, 0xA400
        \\    addiu   $t3, $t2, 0xFC0
        \\    addiu   $sp, $t1, 0x1FF0
        \\1:  lw      $ra, 0x0040($t2)
        \\    sw      $ra, 0x0040($t1)
        \\    addiu   $t2, 4
        \\    bne     $t2, $t3, 1b
        \\    addiu   $t1, 4
        \\    or      $t1, $0, $0
        \\    addiu   $t2, $0, 0x40
        \\    addiu   $t3, $sp, 0xA4000040-0xA4001FF0
        \\    jr      $t3
        \\    addiu   $ra, $sp, 0xA4001550-0xA4001FF0
        \\    .fill 0x40-(.-IQUETrampoline), 1, 0
    );
}

// END STAGE 0

// BEGIN STAGE 1

const dmem_stack_addr: u32 = 0xa4000000 + 4096 - 0x10;

/// Does nothing except setup a stack and jump to "Stage 1"
export fn prestage() linksection(".stage1.pre") callconv(.Naked) noreturn {
    // We don't have a stack yet, and Zig kinda sorta needs that, so
    // let's fix that first by using DMEM temporarily.

    asm volatile (
        \\li $sp, %[stk]
        :
        : [stk] "i" (dmem_stack_addr),
    );

    // In theory, due to linker magic, this should just fall through
    // to stage1 without an explicit jump.
}

/// "Stage 1" of the N64 boot process, mostly stolen - um, I mean,
/// "borrowed" - from libdragon's IPL3 loader (boot/ipl3.c).  Sets up
/// a temporary stack in DMEM, enables basic print-debugging if
/// available, kicks off RDRAM initialization, loads "Stage 2" into
/// RDRAM, and jumps to it.
export fn stage1() linksection(".stage1") noreturn {
    boot_debug_init();
    boot_debug_print("Zig IPL3 says bonjour");
    while (true) {
        boot_debug_print("hon hon hon");
    }
}

const BootDebugImpl = enum {
    Dummy,
    ISViewer,
    @"64Drive",
    SC64,
    IQue,
};

var boot_debug_impl: BootDebugImpl linksection(".data.boot") = .Dummy;

fn boot_debug_init() linksection(".text.boot") void {
    // FIXME: debug stuff probably won't fit in DMEM; leaving it here
    // temporarily for proof-of-concept purposes.
    boot_debug_impl = boot_debug_detect_impl();
    // There would normally be a switch here for various debug impls,
    // but I haven't added support for anything other than the SC64
    // yet.
}

inline fn boot_debug_detect_impl() BootDebugImpl {
    SC64.registers.key = SC64.Registers.Key.Reset;
    PI.wait();
    SC64.registers.key = SC64.Registers.Key.Unlock1;
    PI.wait();
    SC64.registers.key = SC64.Registers.Key.Unlock2;
    PI.wait();
    if (SC64.registers.identifier == 0x53437632) {
        return BootDebugImpl.SC64;
    }
    // TODO: implement ISViewer/64Drive/iQue debug implementations.
    return BootDebugImpl.Dummy;
}

fn boot_debug_print(text: []const u8) linksection(".text.boot") void {
    // FIXME: debug stuff probably won't fit in DMEM; leaving it here
    // temporarily for proof-of-concept purposes.
    var buffer = boot_debug_print_begin() orelse return;
    var len = text.len;
    if (len > buffer.len) {
        len = buffer.len;
    }
    len -= 4;
    for (buffer[0..len], text) |*dest, src| {
        dest.* = src;
    }
    // I don't know what 0x2020200a means
    for (buffer[len .. len + 4], [_]u8{ 0x20, 0x20, 0x20, 0x0a }) |*dest, src| {
        dest.* = src;
    }
    boot_debug_print_end(len + 4);
}

inline fn boot_debug_print_begin() ?*[8192]u8 {
    switch (boot_debug_impl) {
        .SC64 => return SC64.data_buffer,
        // TODO: implement ISViewer/64Drive/iQue debug implementations.
        else => return null,
    }
}

inline fn boot_debug_print_end(nbytes: usize) void {
    switch (boot_debug_impl) {
        .SC64 => {
            SC64.registers.data_0 = @intFromPtr(SC64.data_buffer);
            // TODO: create a packed struct for this instead of doing
            // a bunch of bit-fiddling.
            SC64.registers.data_1 = (nbytes & 0xffffff) | (0x01 << 24);
            SC64.registers.status.command_id = 'M'; // USB_WRITE
            PI.wait();
            while (SC64.registers.status.command_busy) {}
            // TODO: implement equivalent to usb_sc64_waitidle() so
            // that we stop trying to log debug messages if nobody's
            // listening on the other end of the USB cable.
        },
        else => {},
    }
}
