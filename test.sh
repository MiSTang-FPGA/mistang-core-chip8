#!/usr/bin/env bash
# Runs the RTL against the independent reference interpreter and renders the screenshot.
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/mktest.py rom/test.hex
iverilog -g2012 -o build/tb.vvp sim/tb_chip8.sv rtl/chip8_cpu.sv
vvp build/tb.vvp >/dev/null
python3 tools/ref8.py rom/test.hex 400 > build/ref_fb.txt
diff build/ref_fb.txt build/rtl_fb.txt && echo "PASS: RTL framebuffer == reference"
python3 tools/fb2png.py build/rtl_fb.txt docs/img/sim-selftest.png 10
