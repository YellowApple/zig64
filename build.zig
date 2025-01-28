const std = @import("std");

pub fn build(b: *std.Build) void {
    const n64_target_query = std.Target.Query{
        .cpu_arch = std.Target.Cpu.Arch.mips,
        .cpu_model = .{.explicit = &std.Target.mips.cpu.mips3},
        .os_tag = std.Target.Os.Tag.freestanding,
        .abi = std.Target.Abi.none,
    };

    const n64tool = b.addExecutable(.{
        .name = "n64tool",
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    });
    n64tool.linkLibC();
    n64tool.addCSourceFiles(.{
        .files = &.{"vendor/n64tool/n64tool.c"},
        .flags = &.{
            "--std=c23", // Needed for typeof()
            "-Wall",
            "-Werror",
            "-Wno-unused-result",
            "-Wno-error=unknown-pragmas",
            "-Wno-sign-compare",
    }});
    b.installArtifact(n64tool);
    
    const elf = b.addExecutable(.{
        .name = "zig64.elf",
        .root_source_file = b.path("src/main.zig"),
        .target = b.resolveTargetQuery(n64_target_query),
        .optimize = .Debug,
    });
    elf.setLinkerScript(b.path("src/n64.ld"));
    b.installArtifact(elf);
    
    const makerom = b.addRunArtifact(n64tool);
    makerom.addArgs(&.{
        "--title",
        "Zig N64 Demo",
        "--header",
        "vendor/ipl3_dev.z64",
    });
    makerom.addArg("--output");
    const rom = makerom.addOutputFileArg("zig64.z64");
    makerom.addArgs(&.{"--align", "256"});
    makerom.addArtifactArg(elf);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(rom, .prefix, "zig64.z64").step);

    const sc64_upload = b.addSystemCommand(&.{"sc64deployer", "upload"});
    sc64_upload.addFileArg(rom);
    const sc64_upload_step = b.step(
        "sc64-upload",
        "Upload the ROM to a USB-connected Summercart 64"
    );
    sc64_upload_step.dependOn(&sc64_upload.step);

    const sc64_debug = b.addSystemCommand(&.{"sc64deployer", "debug"});
    sc64_debug.step.dependOn(&sc64_upload.step);
    
    const sc64_debug_step = b.step(
        "sc64-debug",
        "Open debug console on a USB-connected Summercart 64"
    );
    sc64_debug_step.dependOn(&sc64_debug.step);
}
