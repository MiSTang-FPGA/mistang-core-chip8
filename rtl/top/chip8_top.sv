// MiSTang CHIP-8: 720p60 HDMI (64x32 at 16x, centred), UART screenshot stream, LED = sound.
module chip8_top #(parameter int CE_DIV = 500) (
    input  logic       sys_clk,
    output logic [1:0] led,
    output logic       uart_tx,
    input  logic       uart_rx,
    output logic       tmds_clk_p, tmds_clk_n,
    output logic [2:0] tmds_d_p, tmds_d_n
);
    logic clk_p5, clk_p, hdmi_lock;
    pll_hdmi u_pll (.clock_in(sys_clk), .clock_out(clk_p5), .locked(hdmi_lock));
    CLKDIV #(.DIV_MODE("5")) u_div5 (.CLKOUT(clk_p), .HCLKIN(clk_p5), .RESETN(hdmi_lock), .CALIB(1'b0));

    logic [3:0] rst_cnt = 0; logic reset = 1;
    always_ff @(posedge clk_p) begin
        if (!hdmi_lock) rst_cnt <= 0; else if (rst_cnt != 4'hf) rst_cnt <= rst_cnt + 1'd1;
        reset <= rst_cnt != 4'hf;
    end

    logic [10:0] cx; logic [9:0] cy; logic [23:0] rgb;

    // CPU
    // the CPU runs on the 27 MHz board clock (its longest path is ~23 ns); video and UART stay on the pixel clock
    logic [7:0] cpu_rst_cnt = 0; logic cpu_rst = 1;
    always_ff @(posedge sys_clk) begin
        if (cpu_rst_cnt != 8'hff) cpu_rst_cnt <= cpu_rst_cnt + 1'd1;
        cpu_rst <= (cpu_rst_cnt != 8'hff);
    end
    logic [9:0] ce_cnt = 0; logic ce;
    always_ff @(posedge sys_clk) begin ce <= (ce_cnt == CE_DIV - 1); ce_cnt <= (ce_cnt == CE_DIV - 1) ? 10'd0 : ce_cnt + 10'd1; end
    // 60 Hz timer tick: 27 MHz / 450000
    logic [18:0] t60_cnt = 0; logic tick60;
    always_ff @(posedge sys_clk) begin tick60 <= (t60_cnt == 19'd449999); t60_cnt <= (t60_cnt == 19'd449999) ? 19'd0 : t60_cnt + 19'd1; end

    wire [10:0] xs = cx + 11'd2 - 11'd128;           // pixel position for the pipelined read
    wire [9:0]  ys = cy - 10'd104;
    wire        in_box = (cx + 11'd2 >= 11'd128) && (cx + 11'd2 < 11'd1152) && (cy >= 10'd104) && (cy < 10'd616);
    wire [10:0] vaddr = {ys[8:4], xs[9:4]};
    logic vpx, beep; logic [15:0] dbg;
    logic [10:0] cap_addr; logic cap_px;
    chip8_cpu u_cpu (.clk(sys_clk), .vclk(clk_p), .rst(cpu_rst), .ce(ce), .tick60(tick60), .keys(16'h0),
                     .vid_addr(vaddr), .vid_px(vpx), .cap_addr(cap_addr), .cap_px(cap_px), .dbg(dbg), .beep(beep));

    logic [1:0] box_d, edge_d;
    wire edge_now = (xs[3:0] == 0) || (ys[3:0] == 0);
    always_ff @(posedge clk_p) begin
        box_d <= {box_d[0], in_box}; edge_d <= {edge_d[0], edge_now};
        rgb <= !box_d[1] ? 24'h000000 : edge_d[1] ? 24'h161616 : vpx ? 24'hE8E8E8 : 24'h0B0B0B;
    end

    logic [2:0] tmds; logic tmds_clock; logic [15:0] silence [1:0];
    initial begin silence[0] = 0; silence[1] = 0; end
    logic [10:0] aud_div = 0; logic clk_audio = 0;
    always_ff @(posedge clk_p) if (aud_div == 11'd773) begin aud_div <= 0; clk_audio <= ~clk_audio; end else aud_div <= aud_div + 1'd1;
    hdmi #(.VIDEO_ID_CODE(4), .DVI_OUTPUT(0), .VIDEO_REFRESH_RATE(60.0), .AUDIO_RATE(48000), .AUDIO_BIT_WIDTH(16),
           .VENDOR_NAME({"MiSTang", 8'd0}), .PRODUCT_DESCRIPTION({"TangNano20K", 40'd0})) u_hdmi (
        .clk_pixel_x5(clk_p5), .clk_pixel(clk_p), .clk_audio(clk_audio), .reset(reset),
        .rgb(rgb), .audio_sample_word(silence), .tmds(tmds), .tmds_clock(tmds_clock),
        .cx(cx), .cy(cy), .frame_width(), .frame_height(), .screen_width(), .screen_height());
    TLVDS_OBUF u_obuf [3:0] (.I({tmds_clock, tmds}), .O({tmds_clk_p, tmds_d_p}), .OB({tmds_clk_n, tmds_d_n}));

    // UART screenshot: "CH8F" + 256 bytes (row-major, 8 px per byte, MSB first), repeated
    logic [7:0] tx_data; logic tx_start, tx_busy; logic tx_line;
    uart_tx #(.DIV(234)) u_tx (.clk(sys_clk), .data(tx_data), .start(tx_start), .busy(tx_busy), .tx(tx_line));
`ifdef UART_DIAG
    logic [21:0] hb2 = 0; always_ff @(posedge sys_clk) hb2 <= hb2 + 1'd1;
    assign uart_tx = hb2[21];   // ~6 Hz square wave
`else
    assign uart_tx = tx_line;
`endif
`ifdef UART_DIAG
    always_ff @(posedge sys_clk) begin tx_start <= 1'b0; if (!tx_busy && !tx_start) begin tx_data <= 8'h41; tx_start <= 1'b1; end end
`else
    typedef enum logic [2:0] {U_HDR, U_RD, U_LAT, U_ACC, U_SEND, U_T0, U_T1} u_t;
    u_t us = U_HDR; logic [1:0] hi = 0; logic [7:0] bi = 0; logic [2:0] pi = 0; logic [7:0] acc = 0; logic [1:0] lat = 0;
    wire tx_ready = !tx_busy && !tx_start;
    always_ff @(posedge sys_clk) begin
        tx_start <= 1'b0;
        case (us)
            U_HDR: if (tx_ready) begin
                tx_data <= (hi == 0) ? "C" : (hi == 1) ? "H" : (hi == 2) ? "8" : "F"; tx_start <= 1'b1;
                hi <= hi + 2'd1;
                if (hi == 2'd3) begin bi <= 0; pi <= 0; us <= U_RD; end
            end
            U_RD: begin cap_addr <= {bi, pi}; lat <= 0; us <= U_LAT; end
            U_LAT: begin lat <= lat + 2'd1; if (lat == 2'd2) us <= U_ACC; end
            U_ACC: begin
                acc <= {acc[6:0], cap_px};
                if (pi == 3'd7) us <= U_SEND; else begin pi <= pi + 3'd1; us <= U_RD; end
            end
            U_SEND: if (tx_ready) begin
                tx_data <= acc; tx_start <= 1'b1; pi <= 0; bi <= bi + 8'd1;
                if (bi == 8'd255) us <= U_T0; else us <= U_RD;
            end
            U_T0: if (tx_ready) begin tx_data <= dbg[15:8]; tx_start <= 1'b1; us <= U_T1; end
            U_T1: if (tx_ready) begin tx_data <= dbg[7:0];  tx_start <= 1'b1; us <= U_HDR; end
            default: us <= U_HDR;
        endcase
    end
`endif
    logic [24:0] hb = 0; always_ff @(posedge sys_clk) hb <= hb + 1'd1;
    assign led = {~hdmi_lock, ~hb[24]};   // led[0] lit = HDMI PLL locked, led[1] blinks = 27 MHz clock alive
endmodule
