const std = @import("std");
const PI = @import("./PI.zig");
const memory = @import("./memory.zig");

/// Writing to this register will cause the (emulated) IS-Viewer to
/// read the specified number of bytes from `ISViewer.buffer` and
/// display them in the emulator's text output.
pub const write_len: *volatile u32 = @ptrFromInt(0xb3ff0014);
/// Buffer to store text to be sent via (emulated) IS-Viewer to the
/// emulator.
pub const buffer: *align(4) [0x200]u8 = @ptrFromInt(0xb3ff0020);

/// If true, an IS-Viewer (or an emulation thereof) is available.
/// Otherwise, false.
pub fn present() bool {
    PI.wait();
    buffer[0] = 0x12;
    PI.wait();
    return (buffer[0] == 0x12);
}

/// Prints via the (emulated) IS-Viewer.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var scratch: [4096]u8 = undefined;
    var wrapper = std.io.fixedBufferStream(scratch[0..]);
    wrapper.writer().print(fmt, args) catch {};
    PI.writeBytes(buffer, scratch[0..wrapper.pos]);
    PI.writeWord(write_len, wrapper.pos);
}
