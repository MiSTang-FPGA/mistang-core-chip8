// CHIP-8 CPU core for MiSTang. Original implementation.
// Multi-cycle FSM, one state per `ce`. 4 KiB RAM (sync read), 64x32 1-bit framebuffer.
module chip8_cpu #(
    parameter ROM_FILE = "rom/test.hex"
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        ce,          // CPU step enable (sets instruction speed)
    input  logic        tick60,      // 60 Hz timer tick
    input  logic [15:0] keys,        // pressed keys, bit n = key n
    // video read port (clk domain)
    input  logic [10:0] vid_addr,
    output logic        vid_px,
    output logic        beep
);
    // ---------------- memory ----------------
    logic [7:0]  ram [0:4095];
    logic [11:0] m_addr;
    logic [7:0]  m_wdata, m_rdata;
    logic        m_we;
    initial begin
        for (int i = 0; i < 4096; i++) ram[i] = 8'h00;
        $readmemh("rom/font.hex", ram, 0, 79);
        $readmemh(ROM_FILE, ram, 512);
    end
    always_ff @(posedge clk) begin
        if (m_we) ram[m_addr] <= m_wdata;
        m_rdata <= ram[m_addr];
    end

    logic        fb [0:2047];
    logic [10:0] f_addr;
    logic        f_we, f_wdata, f_rdata;
    initial for (int i = 0; i < 2048; i++) fb[i] = 1'b0;
    always_ff @(posedge clk) begin
        if (f_we) fb[f_addr] <= f_wdata;
        f_rdata <= fb[f_addr];
        vid_px  <= fb[vid_addr];
    end

    // ---------------- state ----------------
    typedef enum logic [4:0] {
        S_F0, S_F1, S_F2, S_EX,
        S_CLS, S_DA, S_DB, S_PR, S_PW,
        S_KEY, S_LA, S_LB, S_SW, S_BCD, S_STR
    } st_t;
    st_t st;

    logic [7:0]  V [0:15];
    logic [11:0] pc, I;
    logic [11:0] stack [0:15];
    logic [3:0]  sp;
    logic [7:0]  dt, sndt;
    logic [15:0] ir;
    logic [15:0] rng;
    logic [7:0]  hi;

    // draw / loop scratch
    logic [7:0]  spr;
    logic [3:0]  row, rows;
    logic [2:0]  col;
    logic [5:0]  x0;
    logic [4:0]  y0;
    wire  [6:0]  px = {1'b0, x0} + {4'd0, col};
    wire  [5:0]  py = {1'b0, y0} + {2'd0, row};
    wire         clip = px[6] | py[5];            // sprites clip at the right / bottom edge
    wire  [10:0] paddr = {py[4:0], px[5:0]};
    wire         pix_on  = spr[7 - col];
    wire         collide = pix_on & f_rdata & ~clip;
    logic [4:0]  cnt;
    logic [4:0]  last;
    logic        vf_acc;
    logic [10:0] clsa;
    logic [7:0]  bcd_v;

    wire [3:0] x = ir[11:8];
    wire [3:0] y = ir[7:4];
    wire [3:0] n = ir[3:0];
    wire [7:0] kk = ir[7:0];
    wire [11:0] nnn = ir[11:0];
    wire [7:0] vx = V[x];
    wire [7:0] vy = V[y];

    assign beep = (sndt != 0);

    // memory / framebuffer address mux
    always_comb begin
        m_addr = pc; m_we = 1'b0; m_wdata = 8'h00;
        f_addr = paddr; f_we = 1'b0; f_wdata = 1'b0;
        case (st)
            S_F0: m_addr = pc;
            S_F1: m_addr = pc + 12'd1;
            S_DA, S_DB: m_addr = I + {8'd0, row};
            S_LA, S_LB: m_addr = I + {7'd0, cnt};
            S_SW: begin m_addr = I + {7'd0, cnt}; m_we = 1'b1; m_wdata = V[cnt[3:0]]; end
            S_BCD: begin
                m_addr = I + {7'd0, cnt}; m_we = 1'b1;
                m_wdata = (cnt == 0) ? (bcd_v / 8'd100) : (cnt == 1) ? ((bcd_v / 8'd10) % 8'd10) : (bcd_v % 8'd10);
            end
            S_CLS: begin f_addr = clsa; f_we = 1'b1; f_wdata = 1'b0; end
            S_PR: f_addr = paddr;
            S_PW: begin f_addr = paddr; f_we = !clip; f_wdata = f_rdata ^ pix_on; end
            default: ;
        endcase
    end


    logic [8:0] sum9;
    always_ff @(posedge clk) begin
        rng <= {rng[14:0], rng[15] ^ rng[13] ^ rng[12] ^ rng[10]};
        if (rst) begin
            st <= S_F0; pc <= 12'h200; I <= 0; sp <= 0; dt <= 0; sndt <= 0;
            rng <= 16'hACE1;
            for (int i = 0; i < 16; i++) V[i] <= 8'h00;
        end else begin
            if (tick60) begin
                if (dt != 0) dt <= dt - 8'd1;
                if (sndt != 0) sndt <= sndt - 8'd1;
            end
            if (ce) case (st)
                S_F0: st <= S_F1;
                S_F1: begin hi <= m_rdata; st <= S_F2; end
                S_F2: begin ir <= {hi, m_rdata}; pc <= pc + 12'd2; st <= S_EX; end
                S_EX: begin
                    st <= S_F0;
                    case (ir[15:12])
                        4'h0: begin
                            if (ir == 16'h00E0) begin clsa <= 0; st <= S_CLS; end
                            else if (ir == 16'h00EE) begin sp <= sp - 4'd1; pc <= stack[sp - 4'd1]; end
                        end
                        4'h1: pc <= nnn;
                        4'h2: begin stack[sp] <= pc; sp <= sp + 4'd1; pc <= nnn; end
                        4'h3: if (vx == kk) pc <= pc + 12'd2;
                        4'h4: if (vx != kk) pc <= pc + 12'd2;
                        4'h5: if (vx == vy) pc <= pc + 12'd2;
                        4'h6: V[x] <= kk;
                        4'h7: V[x] <= vx + kk;
                        4'h8: begin
                            case (n)
                                4'h0: V[x] <= vy;
                                4'h1: V[x] <= vx | vy;
                                4'h2: V[x] <= vx & vy;
                                4'h3: V[x] <= vx ^ vy;
                                4'h4: begin sum9 = {1'b0, vx} + {1'b0, vy}; V[x] <= sum9[7:0]; V[15] <= sum9[8]; end
                                4'h5: begin V[x] <= vx - vy; V[15] <= (vx >= vy); end
                                4'h6: begin V[x] <= {1'b0, vx[7:1]}; V[15] <= vx[0]; end
                                4'h7: begin V[x] <= vy - vx; V[15] <= (vy >= vx); end
                                4'hE: begin V[x] <= {vx[6:0], 1'b0}; V[15] <= vx[7]; end
                                default: ;
                            endcase
                        end
                        4'h9: if (vx != vy) pc <= pc + 12'd2;
                        4'hA: I <= nnn;
                        4'hB: pc <= nnn + {4'd0, V[0]};
                        4'hC: V[x] <= rng[7:0] & kk;
                        4'hD: begin
                            x0 <= vx[5:0]; y0 <= vy[4:0]; row <= 0; rows <= n; col <= 0; vf_acc <= 0;
                            V[15] <= 0;
                            if (n == 0) st <= S_F0; else st <= S_DA;
                        end
                        4'hE: begin
                            if (kk == 8'h9E && keys[vx[3:0]]) pc <= pc + 12'd2;
                            if (kk == 8'hA1 && !keys[vx[3:0]]) pc <= pc + 12'd2;
                        end
                        4'hF: begin
                            case (kk)
                                8'h07: V[x] <= dt;
                                8'h0A: st <= S_KEY;
                                8'h15: dt <= vx;
                                8'h18: sndt <= vx;
                                8'h1E: I <= I + {4'd0, vx};
                                8'h29: I <= {4'd0, vx[3:0], 2'b00} + {8'd0, vx[3:0]};  // 5 bytes per glyph at 0
                                8'h33: begin bcd_v <= vx; cnt <= 0; st <= S_BCD; end
                                8'h55: begin cnt <= 0; last <= {1'b0, x}; st <= S_SW; end
                                8'h65: begin cnt <= 0; last <= {1'b0, x}; st <= S_LA; end
                                default: ;
                            endcase
                        end
                    endcase
                end
                S_CLS: begin
                    clsa <= clsa + 11'd1;
                    if (clsa == 11'd2047) st <= S_F0;
                end
                // --- draw ---
                S_DA: st <= S_DB;
                S_DB: begin spr <= m_rdata; col <= 0; st <= S_PR; end
                S_PR: st <= S_PW;
                S_PW: begin
                    if (col == 3'd7) begin
                        if (row + 4'd1 == rows) begin
                            V[15] <= {7'd0, vf_acc | collide};
                            st <= S_F0;
                        end else begin
                            if (collide) vf_acc <= 1'b1;
                            row <= row + 4'd1; st <= S_DA;
                        end
                    end else begin
                        if (collide) vf_acc <= 1'b1;
                        col <= col + 3'd1; st <= S_PR;
                    end
                end
                S_KEY: begin
                    for (int k = 0; k < 16; k++) if (keys[k]) begin V[x] <= k[7:0]; st <= S_F0; end
                end
                S_LA: st <= S_LB;
                S_LB: begin
                    V[cnt[3:0]] <= m_rdata;
                    if (cnt == last) st <= S_F0; else begin cnt <= cnt + 5'd1; st <= S_LA; end
                end
                S_SW: begin
                    if (cnt == last) st <= S_F0; else cnt <= cnt + 5'd1;
                end
                S_BCD: begin
                    if (cnt == 5'd2) st <= S_F0; else cnt <= cnt + 5'd1;
                end
                default: st <= S_F0;
            endcase
        end
    end
endmodule
