# mistang-core-chip8

CHIP-8 core for MiSTang (Sipeed Tang Nano 20K). Written from scratch.

- `rtl/chip8_cpu.sv`: the CPU (all 35 opcodes, 4 KiB RAM, 64x32 framebuffer, sprite clipping, 60 Hz timers).
- `tools/ref8.py`: a separate reference interpreter used to check the RTL.
- `tools/mktest.py`: builds the self-test ROM (title, BCD, carry, collision, clipping).
- `test.sh`: runs the RTL in iverilog, compares the whole frame with the reference, renders the screenshot.

![self-test frame from simulation](docs/img/sim-selftest.png)

Status: CPU verified in simulation. Video output and board build: in progress.
