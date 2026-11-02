`timescale 1ns/1ps
module tb_chip8;
    logic clk = 0, rst = 1;
    logic [10:0] va = 0; logic vpx;
    logic beep;
    chip8_cpu dut (.clk(clk), .vclk(clk), .rst(rst), .ce(1'b1), .tick60(1'b0), .keys(16'h0), .vid_addr(va), .vid_px(vpx), .cap_addr(11'd0), .cap_px(), .dbg(),.beep(beep));
    always #5 clk = ~clk;
    integer f, i, r, c;
    reg [2047:0] img;
    initial begin
        repeat (4) @(posedge clk);
        rst <= 0;
        repeat (60000) @(posedge clk);
        for (i = 0; i < 2048; i++) begin
            va = i; repeat (2) @(posedge clk);
            img[i] = vpx;
        end
        f = $fopen("build/rtl_fb.txt", "w");
        for (r = 0; r < 32; r++) begin
            for (c = 0; c < 64; c++) $fwrite(f, "%s", img[r*64+c] ? "#" : ".");
            $fwrite(f, "\n");
        end
        $fclose(f);
        $finish;
    end
endmodule
