const ISViewer = @This();
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

fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) !usize {
    // This array-of-array and splat nonsense is too weird for me to
    // comprehend right now, so we're just gonna ignore the splat and
    // always only handle the data one string at a time.  Karl Seguin
    // says it's okay (https://www.openmymind.net/Zigs-New-Writer/) so
    // why not lmao
    _ = io_w;
    _ = splat;
    const len = if (data[0].len > buffer.len) buffer.len else data[0].len;
    PI.writeBytes(buffer, data[0][0..len]);
    PI.writeWord(write_len, len);
    return len;
}

/// Creates a std.Io.Writer wrapper around the (emulated) IS-Viewer.
pub fn writer(writer_buffer: []u8) std.Io.Writer {
    return .{
        .buffer = writer_buffer,
        .vtable = &.{ .drain = drain },
    };
}
