#!/usr/bin/env python3
"""Builds rom/test.hex (own CHIP-8 test program): title, BCD/LD [I] check, carry, collision, clipping."""
import sys
G = {
 'M': ["10001","11011","10101","10001","10001"],
 'I': ["11111","00100","00100","00100","11111"],
 'S': ["01111","10000","01110","00001","11110"],
 'T': ["11111","00100","00100","00100","00100"],
 'A': ["01110","10001","11111","10001","10001"],
 'N': ["10001","11001","10101","10011","10001"],
 'G': ["01111","10000","10011","10001","01111"],
}
def row(s): return int(s.ljust(8,'0'),2)
prog = []          # list of (kind, value) ; instructions are 16-bit words
labels = {}
def op(w): prog.append(('w', w))
def data(b): prog.append(('b', b))
def label(n): labels[n] = sum(1 if k=='b' else 2 for k,_ in prog)
def ldi(n): prog.append(('ldi', n))
CLS=lambda: op(0x00E0)
LD=lambda x,k: op(0x6000|x<<8|k)
ADD=lambda x,y: op(0x8004|x<<8|y<<4)
DRW=lambda x,y,n: op(0xD000|x<<8|y<<4|n)
LDF=lambda x: op(0xF029|x<<8)
BCD=lambda x: op(0xF033|x<<8)
LDMEM=lambda x: op(0xF065|x<<8)
LDIDX=lambda x: op(0xF055|x<<8)

CLS()
x = 3
for ch in "MISTANG":
    ldi('g'+ch); LD(0,x); LD(1,2); DRW(0,1,5); x += 7
# BCD of 137 -> digits
LD(2,137); ldi('scratch'); BCD(2); LDMEM(2)
xx = 4
for r in (0,1,2):
    LDF(r); LD(3,xx); LD(4,12); DRW(3,4,5); xx += 6
# carry: 200+100 -> VF=1
LD(5,200); LD(6,100); ADD(5,6)
LDF(15); LD(3,40); LD(4,12); DRW(3,4,5)
# collision: draw T twice at same spot, VF of second draw saved
ldi('gT'); LD(0,50); LD(1,20); DRW(0,1,5); DRW(0,1,5); op(0x8700|15<<4)  # V7 = VF
DRW(0,1,5)
LDF(7); LD(3,58); LD(4,20); DRW(3,4,5)
# clipping: A at the bottom-right corner
ldi('gA'); LD(0,61); LD(1,28); DRW(0,1,5)
label('end'); prog.append(('jp','end'))
for ch,rows in G.items():
    label('g'+ch)
    for r in rows: data(row(r))
label('scratch'); data(0); data(0); data(0)

out=[]
for k,v in prog:
    if k=='w': out += [v>>8, v&255]
    elif k=='b': out.append(v)
    elif k=='ldi': a=labels[v]+0x200; out += [0xA0|a>>8, a&255]
    elif k=='jp': a=labels[v]+0x200; out += [0x10|a>>8, a&255]
open(sys.argv[1] if len(sys.argv)>1 else 'rom/test.hex','w').write('\n'.join('%02x'%b for b in out)+'\n')
open('rom/test.ch8','wb').write(bytes(out))
print(len(out),'bytes')
