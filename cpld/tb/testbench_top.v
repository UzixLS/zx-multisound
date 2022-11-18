`timescale 1ns/1ps
module testbench_top();

reg rst_n;
reg clk32;

/* TOP ENTRY */
// zx_multisound zx_multisound0(
//     .rst_n(rst_n),
//     .clk32(clk32),
//     .cfg(5'b11111),
//     .a(16'hFFFF),
//     // .d(8'hFF),
//     .n_rd(1'b1),
//     .n_wr(1'b1),
//     .n_iorq(1'b1),
//     .n_mreq(1'b1),
//     .n_m1(1'b1),
//     .ga(16'hFFFF),
//     // .gd(8'hFF),
//     .n_grd(1'b1),
//     .n_gwr(1'b1),
//     .n_gm1(1'b1),
//     .n_gmreq(1'b1),
//     .n_giorq(1'b1)
// );

/* CLOCKS & RESET */
initial begin
    rst_n = 0;
    #50 rst_n = 1;
end

always begin
    clk32 = 0;
    #15.625 clk32 = 1;
    #15.625;
end


wire [15:0] sine_vol;
sine_dds sine_dds_vol(clk32, ~rst_n, 256, sine_vol);
wire [15:0] sine_dac;
sine_dds sine_dds_dac(clk32, ~rst_n, 1024, sine_dac);

// wire [5:0] volx = 6'h00;
// wire [5:0] volx = 6'h1F;
wire [5:0] volx = 6'h3F;
// wire [5:0] volx = sine_vol[15:10];
// reg [5:0] volx = 6'h3F;
// initial begin
//     #2_000_000 volx = 0;
//     #2_000_000 volx = 6'h1F;
//     #2_000_000 volx = 0;
//     #2_000_000 volx = 6'h3F;
// end

// wire [7:0] dacx = 8'h00;
// wire [7:0] dacx = 8'h80;
// wire [7:0] dacx = 8'hFF;
wire [7:0] dacx = sine_vol[15:8];


wire [7:0] dacx0 = dacx[7]? {~dacx[7],dacx[6:0]} : {dacx[7],~dacx[6:0]};
reg [5:0] volx_cnt;
reg [7:0] dacx_cnt;
wire volx_en = (volx_cnt < volx) || (&volx);
wire dacx_cnt7 = dacx_cnt[7];
wire dacx7 = dacx[7];
wire dacx_out = dacx_cnt[7]? dacx[7] : clk32;
always @(negedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
       volx_cnt <= 0;
       dacx_cnt <= 0;
    end
    else begin
        volx_cnt <= volx_cnt + 6'd31;
        if (volx_en)
            dacx_cnt <= dacx_cnt[6:0] + dacx0[6:0];
        else
            dacx_cnt[7] <= 0;
    end
end



/* TESTBENCH CONTROL */
integer fhandle;
initial begin
    fhandle = $fopen("testbench_pwl.txt","w");
    $timeformat(0, 10, "", 0);
    $dumpfile("testbench.vcd");
    $dumpvars;
    #10_000_000;
    $fclose(fhandle);
    $finish;
end

`define SCALE 3.3
always @(negedge clk32 or posedge clk32) begin
    $fwrite(fhandle, "%t %f\n", $time, dacx_out*`SCALE);
end

endmodule
