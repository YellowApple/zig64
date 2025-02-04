const std = @import("std");
const PI = @import("./PI.zig");

/// SC64 status/command register fields.
const Status = packed struct(u32) {
    // I sure hope I got the bit ordering right...
    /// ID of the command to execute.
    command_id: u8, // TODO: enum of valid command IDs
    /// If true, the SC64 will raise a cart interrupt when command
    /// execution finishes.
    command_irq_request: bool,
    /// Reserved; should be zero.
    reserved: u13 = 0,
    /// Read-only.  If true, "AUX not empty" interrupts are enabled.
    aux_irq_mask: bool,
    /// Read-only.  If true, an "AUX not empty" interrupt is pending.
    aux_irq_pending: bool,
    /// Read-only.  If true, "USB not empty" interrupts are enabled.
    usb_irq_mask: bool,
    /// Read-only.  If true, a "USB not empty" interrupt is pending.
    usb_irq_pending: bool,
    /// Read-only.  If true, "command finished" interrupts are
    /// enabled.
    command_irq_mask: bool,
    /// Read-only.  If true, a "command finished" interrupt is
    /// pending.
    command_irq_pending: bool,
    /// Read-only.  If true, "button pressed" interrupts are enabled.
    button_irq_mask: bool,
    /// Read-only.  If true, a "button pressed" interrupt is pending.
    button_irq_pending: bool,
    /// Read-only.  If true, the most recent command encountered an
    /// error.
    command_error: bool,
    /// Read-only.  If true, the SC64 is currently executing a
    /// command.
    command_busy: bool,
};

/// Magic values to enable or disable SC64-specific memory regions.
/// To enable SC64-specific memory regions, set `SC64.key` to
/// `.Reset`, then `.Unlock1`, then `.Unlock2`.  To disable
/// SC64-specific memory regions, set the key register to `.Lock`.
const Key = enum(u32) {
    Reset = 0x00000000,
    Unlock1 = 0x5f554e4c, // _UNL
    Unlock2 = 0x4f434b5f, // OCK_
    Lock = 0xffffffff,
};

/// IRQ register fields.
const IRQ = packed struct(u32) {
    /// Reserved.  Should be zero.
    reserved1: u8 = 0,
    /// If true, enable "AUX not empty" interrupts.
    enable_aux: bool,
    /// If true, enable "AUX not empty" interrupts.
    disable_aux: bool,
    /// If true, enable "USB not empty" interrupts.
    enable_usb: bool,
    /// If true, enable "USB not empty" interrupts.
    disable_usb: bool,
    /// Reserved.  Should be zero.
    reserved2: u16 = 0,
    /// If true, clear pending "AUX not empty" interrupt.
    clear_aux: bool,
    /// If true, clear pending "USB not empty" interrupt.
    clear_usb: bool,
    /// If true, clear pending "command finished" interrupt.
    clear_cmd: bool,
    /// If true, clear pending "button pressed" interrupt.
    clear_btn: bool,
};

/// General-purpose data buffer.  Useful for USB reads/writes.
pub const data_buffer: *align(4) [8192]u8 = @ptrFromInt(0xbffe0000);

pub const register_base: u32 = 0xbfff0000;
/// Status/command register.  Writes control command execution.  Reads
/// provide info on command execution status and enabled/raised
/// interrupts.  See the `SC64.Status` docs for more info.
pub const status: *volatile Status = @ptrFromInt(register_base);
/// Data register 0.  Stores the first result of the previous command
/// or the first argument of the next command.
pub const data_0: *volatile u32 = @ptrFromInt(register_base + 0x4);
/// Data register 1.  Stores the second result of the previous command
/// or the second argument of the next command.
pub const data_1: *volatile u32 = @ptrFromInt(register_base + 0x8);
/// Read-only.  Flashcart identifier.  If this equals `0x53437632`
/// (ASCII `SCv2`), the SC64's registers are enabled.  Otherwise, the
/// SC64's registers (except for `SC64.key` are disabled.  If entering
/// the unlock sequence into `SC64.key` doesn't change this value to
/// `0x53437672`, then the inserted cartridge is not a SummerCart 64.
pub const identifier: *volatile u32 = @ptrFromInt(register_base + 0xc);
/// Write-only.  To enable the SC64's registers:
///
/// - `PI.wait(); SC64.key.* = .Reset;`
/// - `PI.wait(); SC64.key.* = .Unlock1;`
/// - `PI.wait(); SC64.key.* = .Unlock2;`
///
/// To disable the SC64's registers:
///
/// - `PI.wait(); SC64.key.* = .Lock;`
pub const key: *volatile Key = @ptrFromInt(register_base + 0x10);
/// Write-only.  Enables/disables interrupts and clears pending
/// interrupts.  See `SC64.IRQ` for more details.
pub const irq: *volatile IRQ = @ptrFromInt(register_base + 0x14);
/// General-purpose data register.  If the cart has received an AUX
/// signal from a host PC over USB, the value of that signal can be
/// read from here.  Likewise, writing to this register will send an
/// AUX signal via USB.  AUX values greater than or equal to
/// `0xFF000000` are reserved for SC64 internal use.
pub const aux: *volatile u32 = @ptrFromInt(register_base + 0x18);

/// Attempts to enable SC64-specific memory registers.  Returns true
/// if successful.  If false, then the inserted cartridge is not a
/// SummerCart 64.
pub fn present() bool {
    PI.writeWord(@ptrCast(key), @intFromEnum(Key.Reset));
    PI.writeWord(@ptrCast(key), @intFromEnum(Key.Unlock1));
    PI.writeWord(@ptrCast(key), @intFromEnum(Key.Unlock2));
    return PI.readWord(identifier) == 0x53437632;
}

/// USB write parameters.  This normally gets written to `SC64.data_1`
/// when performing USB writes (command ID `'M'`).
const USBWriteParams = packed struct(u32) {
    /// How many bytes to write (from the pointer in `SC64.data_0`) to
    /// USB.
    length: u24,
    /// What kind of data to send.  At this time, the only known valid
    /// value is `1`.
    datatype: u8 = 1,
};

/// Sends text via the SC64's USB port.  If the SC64 is connected to a
/// PC and the PC is running `sc64deployer debug`, the text will
/// display in the debug output.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var scratch: [4096]u8 = undefined;
    var wrapper = std.io.fixedBufferStream(scratch[0..]);
    wrapper.writer().print(fmt, args) catch {};
    PI.writeBytes(data_buffer, scratch[0..wrapper.pos]);
    PI.writeWord(data_0, @intFromPtr(data_buffer));
    const params: USBWriteParams = .{.length = @truncate(wrapper.pos)};
    PI.writeWord(data_1, @bitCast(params));
    PI.wait();
    status.command_id = 'M';
    PI.wait();
    var timeout: u8 = 0;
    while (usbBusy()) {
        if (timeout == 255) return;
        timeout += 1;
    }
}

/// USB write status results.  This normally gets read from
/// `SC64.data_0` when checking the status of a pending USB write
/// (command ID `'U'`).
const USBWriteStatus = packed struct(u32) {
    /// Entirely unknown.  No upstream documentation.
    unknown: u31,
    /// If true, the SC64 is currently processing a USB write command.
    busy: bool,
};

/// Returns true if the SC64 is currently processing a USB write
/// command.
pub fn usbBusy() bool {
    PI.wait();
    while (status.command_busy) {}
    status.command_id = 'U';
    PI.wait();
    while (status.command_busy) {}
    const result: USBWriteStatus = @bitCast(PI.readWord(data_0));
    return result.busy;
}
