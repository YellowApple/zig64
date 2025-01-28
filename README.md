# Zig Nintendo 64 Demo

## What?

It's a self-contained sample Zig codebase capable of building a
Nintendo 64 ROM.  Nothing shows up on the screen (yet), but it'll
nonetheless run on real hardware (with debug output via USB on a
[SummerCart 64](https://summercart64.dev/)) or on low-level emulators
like [Ares](https://ares-emu.net/) (with debug output if the emulator
supports ISViewer-based debug logging).

## Why?

I like Zig, I like the Nintendo 64, I want to write homebrew in Zig
for the Nintendo 64, and as far as I can tell nobody else has done
this (or at least nobody else has posted anything online indicating
that they've done this).

## How?

I ~~stole~~ "borrowed" the `n64tool` source code, `n64.ld` linker
script, and "dev" IPL3 from [libdragon](https://libdragon.dev/).  The
included `build.zig` compiles `n64tool`, compiles a MIPS3 ELF
executable (using `src/main.zig` and `src/n64.ld`), and uses the
compiled `n64tool` to append the resulting `zig64.elf` to libdragon's
IPL3 (`vendor/ipl3_dev.z64`) and produce a `zig64.z64`.  All this
happens automatically when running `zig build`.

There's also `zig build sc64-upload` (which uploads the ROM to a
USB-connected [SummerCart 64](https://summercart64.dev/)) and `zig
build sc64-debug` (which opens a debug console via the SummerCart's
USB serial interface).  Both of these require the [`sc64-deployer`
tool](https://github.com/Polprzewodnikowy/SummerCart64/releases) to
already be installed on your local machine to work; they're just thin
wrappers around `sc64-deployer upload zig-out/zig64.z64` and
`sc64-deployer debug` (respectively), though since they're integrated
into `build.zig` they'll automatically trigger rebuilding the ELF and
ROM as necessary.

## Can I use it?

Yes!  See `COPYING` for details, but long story short, this demo code
is effectively public-domain (zero-clause BSD), as are the pieces
copied over from Libdragon (Unlicense).
