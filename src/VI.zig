const base = 0xa4400000;

const AAMode = enum(u2) {
    EnabledAlwaysFetch = 0,
    Enabled = 1,
    Disabled = 2,
    DisabledNoResampling = 3,
};

const PixelFormat = enum(u2) {
    Off = 0,
    Reserved = 1,
    Depth16 = 2,
    Depth32 = 3,
};

pub const Pixel16 = packed struct(u16) {
    a: u1,
    b: u5,
    g: u5,
    r: u5,
};

pub const Pixel32 = packed struct(u32) {
    r: u8,
    g: u8,
    b: u8,
    a: u8,
};

const Control = packed struct(u32) {
    pixel_format: PixelFormat,
    enable_gamma_dither: bool,
    enable_gamma: bool,
    enable_divot: bool,
    enable_vbus_clock: bool = false,
    serrate: bool,
    test_mode: bool,
    aa_mode: AAMode,
    reserved1: bool = false,
    kill_we: bool,
    pixel_advance: u4,
    enable_dedither: bool,
    reserved2: u15 = 0,
};
pub const control: *volatile Control = @ptrFromInt(base + 0x0);

pub const origin: *volatile u32 = @ptrFromInt(base + 0x4); // u24

pub const width: *volatile u32 = @ptrFromInt(base + 0x8); // u12

pub const v_interrupt: *volatile u32 = @ptrFromInt(base + 0xc); // u10

const VCurrent = packed struct(u32) {
    field: bool,
    half_line: u9,
    reserved: u22,
};
pub const v_current: *volatile VCurrent = @ptrFromInt(base + 0x10);

const Burst = packed struct(u32) {
    hsync_width: u8,
    burst_width: u8,
    vsync_height: u4,
    burst_start: u10,
    reserved: u2 = 0,
};
pub const burst: *volatile Burst = @ptrFromInt(base + 0x14);

pub const v_total: *volatile u32 = @ptrFromInt(base + 0x18); // u10

const HTotal = packed struct(u32) {
    total: u12,
    reserved1: u4 = 0,
    leap: u5,
    reserved2: u11 = 0,
};
pub const h_total: *volatile HTotal = @ptrFromInt(base + 0x1c);

const HTotalLeap = packed struct(u32) {
    b: u12,
    reserved1: u4 = 0,
    a: u12,
    reserved2: u4 = 0,
};
pub const h_total_leap: *volatile HTotalLeap = @ptrFromInt(base + 0x1c);

const HVideo = packed struct(u32) {
    end: u10,
    reserved1: u6 = 0,
    start: u10,
    reserved2: u6 = 0,
};
pub const h_video: *volatile HVideo = @ptrFromInt(base + 0x24);

const VVideo = packed struct(u32) {
    end: u10,
    reserved1: u6 = 0,
    start: u10,
    reserved2: u6 = 0,
};
pub const v_video: *volatile VVideo = @ptrFromInt(base + 0x28);

const VBurst = packed struct(u32) {
    end: u10,
    reserved1: u6 = 0,
    start: u10,
    reserved2: u6 = 0,
};
pub const v_burst: *volatile VBurst = @ptrFromInt(base + 0x2c);

const XScale = packed struct(u32) {
    scale: u12,
    reserved1: u4 = 0,
    offset: u12,
    reserved2: u4 = 0,
};
pub const x_scale: *volatile XScale = @ptrFromInt(base + 0x30);

const YScale = packed struct(u32) {
    scale: u12,
    reserved1: u4 = 0,
    offset: u10,
    unused: u2 = 0,
    reserved2: u4 = 0,
};
pub const y_scale: *volatile YScale = @ptrFromInt(base + 0x34);

pub const test_addr: *volatile u32 = @ptrFromInt(base + 0x38); // u6

pub const staged_data: *volatile u32 = @ptrFromInt(base + 0x3c);

// -----

const VideoMode = enum {
    NTSC,
    PAL,
    MPAL,
};

const SetupOptions = struct {
    mode: VideoMode = .NTSC,
    format: PixelFormat = .Depth16,
    width: u12 = 320,
    height: u12 = 240,
    interlace: bool = false,
    antialias: bool = false,
    resample: bool = false,
    dedither: bool = false,
    gamma_dither: bool = false,
    gamma: bool = false,
    ique: bool = false,
};

pub fn setup(opts: SetupOptions) void {
    // Defaults based on guidance in
    // https://n64brew.dev/wiki/Video_Interface
    width.* = opts.width;
    v_interrupt.* = 2;
    burst.* = switch (opts.mode) {
        // FIXME: does PAL-M use NTSC or PAL values here?  Or a mix of
        // both?  The n64brew wiki doesn't specify.  Assuming it uses
        // NTSC values since it's supposed to use NTSC dimensions with
        // PAL colors.  If any Brazilians could test this out and make
        // sure this works as expected, that'd be great.
        .NTSC, .MPAL => .{
            .hsync_width = 57,
            .burst_width = 34,
            .vsync_height = 5,
            .burst_start = 62,
        },
        .PAL => .{
            .hsync_width = 58,
            .burst_width = 35,
            .vsync_height = 4,
            .burst_start = 64,
        },
    };
    v_total.* = switch (opts.mode) {
        .NTSC, .MPAL => if (opts.interlace) 524 else 525,
        .PAL => if (opts.interlace) 624 else 625,
    };
    h_total.* = switch (opts.mode) {
        .NTSC => .{
            .total = 3093,
            .leap = 0,
        },
        .PAL => .{ .total = 3177, .leap = 0x15 },
        // FIXME: should PAL-M leap be 0x15 or 0?
        .MPAL => .{
            .total = 3090,
            .leap = 0,
        },
    };
    if (opts.mode == .PAL) h_total_leap.* = .{ .a = 3182, .b = 3183 };
    h_video.* = switch (opts.mode) {
        .NTSC, .MPAL => .{ .start = 108, .end = 748 },
        .PAL => .{ .start = 128, .end = 768 },
    };
    v_video.* = switch (opts.mode) {
        .NTSC, .MPAL => .{ .start = 0x025, .end = 0x1ff },
        .PAL => .{ .start = 0x05f, .end = 0x239 },
    };
    v_burst.* = switch (opts.mode) {
        .NTSC, .MPAL => .{ .start = 0x00e, .end = 0x204 },
        .PAL => .{ .start = 0x009, .end = 0x26b },
    };
    // n64brew wiki doesn't go into much detail on these...
    x_scale.* = .{
        .scale = 0x100,
        .offset = 0,
    };
    y_scale.* = .{
        .scale = 0x100,
        .offset = 0,
    };
    // This was working perfectly fine a couple months ago when put at
    // the start of this function, but now all of a sudden this causes
    // Ares to freeze unless it's put at the *end* of this function.
    // Haven't tested on real hardware yet.
    control.* = .{
        .pixel_format = opts.format,
        .enable_gamma_dither = opts.gamma_dither,
        .enable_gamma = opts.gamma,
        .enable_divot = opts.antialias,
        .enable_vbus_clock = false,
        .serrate = opts.interlace,
        .test_mode = false,
        .aa_mode = if (opts.dedither) .EnabledAlwaysFetch else .Disabled,
        .kill_we = false,
        .pixel_advance = if (opts.ique) 1 else 3,
        .enable_dedither = opts.dedither,
    };
}
