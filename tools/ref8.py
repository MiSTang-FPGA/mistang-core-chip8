#!/usr/bin/env python3
"""Independent reference CHIP-8 interpreter: runs a ROM for N instructions, prints the framebuffer (32 lines of 64 chars)."""
import sys
def run(rom, font, steps):
    m = bytearray(4096); m[:len(font)] = font; m[0x200:0x200+len(rom)] = rom
    V=[0]*16; I=0; pc=0x200; st=[]; fb=[[0]*64 for _ in range(32)]
    for _ in range(steps):
        o=(m[pc]<<8)|m[pc+1]; pc+=2
        a=o>>12; x=(o>>8)&15; y=(o>>4)&15; n=o&15; kk=o&255; nn=o&0xFFF
        if o==0xE0: fb=[[0]*64 for _ in range(32)]
        elif o==0xEE: pc=st.pop()
        elif a==1: pc=nn
        elif a==2: st.append(pc); pc=nn
        elif a==3 and V[x]==kk: pc+=2
        elif a==4 and V[x]!=kk: pc+=2
        elif a==5 and V[x]==V[y]: pc+=2
        elif a==6: V[x]=kk
        elif a==7: V[x]=(V[x]+kk)&255
        elif a==8:
            vx,vy=V[x],V[y]
            if n==0: V[x]=vy
            elif n==1: V[x]=vx|vy
            elif n==2: V[x]=vx&vy
            elif n==3: V[x]=vx^vy
            elif n==4: t=vx+vy; V[x]=t&255; V[15]=t>>8
            elif n==5: V[x]=(vx-vy)&255; V[15]=int(vx>=vy)
            elif n==6: V[x]=vx>>1; V[15]=vx&1
            elif n==7: V[x]=(vy-vx)&255; V[15]=int(vy>=vx)
            elif n==14: V[x]=(vx<<1)&255; V[15]=vx>>7
        elif a==9 and V[x]!=V[y]: pc+=2
        elif a==0xA: I=nn
        elif a==0xB: pc=nn+V[0]
        elif a==0xD:
            V[15]=0; x0=V[x]%64; y0=V[y]%32
            for r in range(n):
                for c in range(8):
                    if y0+r<32 and x0+c<64 and (m[I+r]>>(7-c))&1:
                        if fb[y0+r][x0+c]: V[15]=1
                        fb[y0+r][x0+c]^=1
        elif a==0xF:
            if kk==0x1E: I+=V[x]
            elif kk==0x29: I=V[x]%16*5
            elif kk==0x33: m[I]=V[x]//100; m[I+1]=V[x]//10%10; m[I+2]=V[x]%10
            elif kk==0x55:
                for i in range(x+1): m[I+i]=V[i]
            elif kk==0x65:
                for i in range(x+1): V[i]=m[I+i]
    return fb
if __name__=='__main__':
    rom=bytes(int(l,16) for l in open(sys.argv[1]).read().split())
    font=bytes(int(l,16) for l in open('rom/font.hex').read().split())
    fb=run(rom,font,int(sys.argv[2]))
    print('\n'.join(''.join('#' if p else '.' for p in r) for r in fb))
