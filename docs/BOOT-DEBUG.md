# Diagnostic pattern experiment

This build isolates the menu snapshot from the CPU and cartridge buses.
It uses the `417a55f` game engine with its CPU debug outputs disconnected.
The menu contains **Pattern Lo** (0xF4000010) and **Pattern Hi** (0xF4000014).
These are test data, not a program counter or CPU state.

A 64-bit register starts at `D1A65EED4B3C2907` and rotates left by one bit
on every system clock. Its 64 rotations are distinct. A changing pattern
keeps the capture path active; a constant would let synthesis remove it.
The pattern adds its own 64 source registers, so this is an isolation
experiment rather than an equal-area comparison with live CPU diagnostics.

Open the OS/core menu to capture both halves together. Join **Pattern Hi**
followed by **Pattern Lo**, each padded to eight hex digits. The resulting
64-bit word must be one of the rotations of `D1A65EED4B3C2907`. Values stay
stable while the menu is open. Closing and reopening captures another
sample; it may repeat because the pattern cycles every 64 system clocks.
Before the first capture the readouts are zero.

The existing toggle handshake crosses from clk_sys to clk_74a and holds
the payload stable through acknowledgment. GBA reset does not reset the
pattern or its snapshot. Post-fit analysis must find the pattern source
and full 64-bit capture/publication banks, pass all timing categories, and
keep the snapshot's raw data delay below the watcher's 20 ns budget.

The previous IRQ / DMA and Save Bus addresses return zero. CG/CS and Save
Fault retain their usual meaning. This pattern cannot locate Zero Mission's
CPU stall; a passing build would show that this snapshot implementation can
meet timing with a local pattern source. Restoring live observations would
still require a separate fit and validation.

The previous compact CPU PC/CPU State encoding is preserved in
`git show 3f7ae09:docs/BOOT-DEBUG.md` for reference; it does not describe this
pattern package.
