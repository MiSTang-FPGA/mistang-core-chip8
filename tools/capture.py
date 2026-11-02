#!/usr/bin/env python3
"""Screenshot from the board over the USB-UART: finds 'CH8F' + 256 bytes (64x32, 1 bit/px) and writes PNG via fb2png.
usage: capture.py /dev/cu.usbserial-XXXX out.png"""
import os, sys, termios, time, subprocess
fd = os.open(sys.argv[1], os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
a = termios.tcgetattr(fd); a[0]=0; a[1]=0; a[2]=termios.CS8|termios.CREAD|termios.CLOCAL; a[3]=0
a[4]=a[5]=termios.B115200; a[6][termios.VMIN]=0; a[6][termios.VTIME]=0; termios.tcsetattr(fd, termios.TCSANOW, a)
buf = b''; t = time.time()
while time.time() - t < 6:
    try: buf += os.read(fd, 4096)
    except BlockingIOError: time.sleep(0.02)
    i = buf.find(b'CH8F')
    while i >= 0 and len(buf) >= i + 262:
        pkt = buf[i+4:i+260]
        lines = [''.join('#' if (pkt[r*8+c//8] >> (7-c%8)) & 1 else '.' for c in range(64)) for r in range(32)]
        txt = os.path.splitext(sys.argv[2])[0] + '.txt'
        open(txt, 'w').write('\n'.join(lines) + '\n')
        subprocess.run([sys.executable, os.path.join(os.path.dirname(__file__), 'fb2png.py'), txt, sys.argv[2], '10'], check=True)
        print('captured; cpu state/pc = %04x' % ((buf[i+260]<<8)|buf[i+261])); sys.exit(0)
print('no frame, got', len(buf), 'bytes', buf[:16]); sys.exit(1)
