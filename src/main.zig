const std = @import("std");
pub const os = @import("./os.zig");

// Required until https://github.com/ziglang/zig/issues/8508 is
// resolved.
comptime { _ = os.start; }

pub const panic = os.panic;

pub fn main() !void {
    var writer = os.Debug.writer(&.{});
    try writer.print("All your Nintendo 64 are belong to us.\n", .{});
    try writer.print("This is another message from Zig.\n", .{});
    const dmem_test_pat: [16]u8 align(4) = .{
        0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef,
        0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0xba, 0xbe
    };
    @memcpy(os.dmem[0..16], &dmem_test_pat);
    const c0_status_before_vi = os.cop0.Status.get();
    try writer.print("c0_status_before_vi = {}\n", .{c0_status_before_vi});
    try writer.print("Making a framebuffer...\n", .{});
    const pxl: os.VI.Pixel16 = .{ .r = 31, .g = 31, .b = 0, .a = 0 };
    const test_framebuffer: [320][240]os.VI.Pixel16 = .{.{pxl}**240}**320;
    try writer.print("Setting the framebuffer...\n", .{});
    os.VI.origin.* = @intFromPtr(&test_framebuffer);
    try writer.print("Turning on the VI...\n", .{});
    os.VI.setup(.{});
    const c0_status_after_vi = os.cop0.Status.get();
    try writer.print("c0_status_after_vi = {}\n", .{c0_status_after_vi});
    try writer.print("MI.mode = {}\n", .{os.MI.mode.read});
    try writer.print("MI.version = {}\n", .{os.MI.version});
    try writer.print("MI.interrupt = {}\n", .{os.MI.interrupt});
    try writer.print("MI.mask = {}\n", .{os.MI.mask.read});
    try writer.print("SI.status = {}\n", .{os.SI.status});
    @panic("the demo is over already :(");
}
