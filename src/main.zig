const std = @import("std");
pub const os = @import("./os.zig");

// Required until https://github.com/ziglang/zig/issues/8508 is
// resolved.
comptime { _ = os.start; }

pub fn main() void {
    os.Debug.print("All your Nintendo 64 are belong to us.\n", .{});
    os.Debug.print("This is another message from Zig.\n", .{});
    const dmem_test_pat: [16]u8 align(4) = .{
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe
    };
    @memcpy(os.dmem[0..16], &dmem_test_pat);
    const c0_status_before_vi = os.cop0.Status.get();
    os.Debug.print("c0_status_before_vi = {}\n", .{c0_status_before_vi});
    const pxl: os.VI.Pixel16 = .{ .r = 31, .g = 31, .b = 0, .a = 0 };
    const test_framebuffer: [320][240]os.VI.Pixel16 = .{.{pxl}**240}**320;
    os.VI.origin.* = @intFromPtr(&test_framebuffer);
    os.VI.setup(.{});
    const c0_status_after_vi = os.cop0.Status.get();
    os.Debug.print("c0_status_after_vi = {}\n", .{c0_status_after_vi});
    // @panic("the demo is over already :(");
}
