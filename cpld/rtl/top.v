module zx_multisound(
    input rst_n,
    input clk32,
    input clkx,

    input [4:0] cfg,

    input [15:0] zxa,
    inout [7:0] zxd,
    input zxrd_n,
    input zxwr_n,
    input zxiorq_n,
    input zxmreq_n,
    input zxm1_n,
    output zxwait_n,
    output zxiorqge_n,
    input zxdos_n,
    input zxiodos_n,

    output aa0,
    inout [7:0] ad,
    output rstout_n,
    output ard_n,
    output awr_n,
    output ym_m,
    output ym1_cs_n,
    output ym2_cs_n,
    output reg fm1_ena,
    output reg fm2_ena,
    output saa_cs_n,
    output saa_clk,
    output midi_clk,

    input [15:0] ga,
    inout [7:0] gd,
    output grst_n,
    output gclk,
    output reg gint_n,
    input grd_n,
    input gwr_n,
    input gm1_n,
    input gmreq_n,
    input giorq_n,
    output grom_n,
    output gram1_n,
    output gram2_n,
    output gram3_n,
    output gram4_n,
    output [18:15] gma,

    output dac0_out,
    output dac1_out,
    output dac2_out,
    output dac3_out
);

assign rstout_n = rst_n;

// iorq_n are useless in zxevo :(
// so we're detecting iorq_n cycle by rd_n/wr_n signal asserted without m1_n/mreq_n
reg ioreq, ioreq_prev;
always @(negedge clk32) begin
    ioreq_prev <= ioreq;
    // ioreq <= zxiorq_n == 1'b0 && zxm1_n == 1'b1 && zxdos_n == 1'b1 && zxiodos_n == 1'b1;
    ioreq <= zxm1_n == 1'b1 && zxmreq_n == 1'b1 && (zxrd_n == 1'b0 || zxwr_n == 1'b0);
end
wire ioreq_rd = ioreq && zxrd_n == 1'b0;
wire ioreq_wr = ioreq && zxwr_n == 1'b0;

// dos_n are useless in zxevo :(
// so we're just lock some ports access when instruction has been fetched from rom
reg rom_m1_access;
always @(negedge clk32 or negedge rst_n) begin
    if (!rst_n)
        rom_m1_access <= 0;
    else if (zxm1_n == 0)
        rom_m1_access <= zxa[15:14] == 2'b00;
end



/* CONFIGURATION */
wire ym_ena  = cfg[0];
wire saa_ena = cfg[1];
wire gs_ena  = cfg[2];
wire sd_ena  = cfg[3];


/* CLOCKS */
reg [5:0] clk3_5_cnt = 0;
reg [1:0] clk8_cnt   = 0;
reg [2:0] clk12_cnt  = 0;
always @(posedge clk32) clk3_5_cnt <= clk3_5_cnt + 6'd7;
always @(posedge clk32) clk8_cnt   <= clk8_cnt   + 1'b1;
always @(posedge clk32) clk12_cnt  <= clk12_cnt  + 3'd3;
wire clk3_5 = clk3_5_cnt[5];
wire clk8   = clk8_cnt[1];
wire clk12  = clk12_cnt[2];
wire clk16  = clk8_cnt[0];


/* TURBO SOUND FM */
wire port_bffd      = zxa[15:14] == 2'b10  && zxa[3:0] == 4'b1101 && ym_ena;
wire port_fffd      = zxa[15:14] == 2'b11  && zxa[3:0] == 4'b1101 && ym_ena;
wire port_fffd_full = zxa[15:13] == 3'b111 && zxa[3:0] == 4'b1101 && ym_ena; // required for compatibility with #dffd port
reg ym_chip_sel, ym_get_stat;
wire ym_a0 = (~zxrd_n & zxa[14] & ~ym_get_stat) | (~zxwr_n & ~zxa[14]);
assign ym1_cs_n = ~(~ym_chip_sel && (port_bffd || port_fffd));
assign ym2_cs_n = ~( ym_chip_sel && (port_bffd || port_fffd));

always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        ym_chip_sel <= 0;
        ym_get_stat <= 0;
        fm1_ena <= 0;
        fm2_ena <= 0;
    end
    else if (port_fffd && ioreq_wr && zxd[7:4] == 4'b1111) begin
        ym_chip_sel <= zxd[0];
        ym_get_stat <= ~zxd[1];
        fm1_ena <= zxd[2]? 1'b0 : 1'bz;
        fm2_ena <= zxd[2]? 1'b0 : 1'bz;
    end
end

assign ym_m = clk3_5;


/* SAA1099 */
wire port_ff = zxa[7:0] == 8'hFF && saa_ena && !rom_m1_access;
assign saa_cs_n = ~(port_ff && ioreq_wr);
wire saa_a0 = zxa[8];

wire port_fffd_saa = zxa[15:14] == 2'b11 && zxa[3:0] == 4'b1101 && saa_ena;
reg saa_clk_en;
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n)
        saa_clk_en <= 0;
    else if (port_fffd_saa && ioreq_wr && zxd[7:4] == 4'b1111)
        saa_clk_en <= ~zxd[3];
end

assign saa_clk = saa_clk_en? clk8 : 1'b0;


/* MIDI */
assign midi_clk = clk12;


/* GENERAL SOUND */
assign gclk = clk16;
assign grst_n = rstout_n;

reg gioreq, gioreq_prev;
always @(posedge clk32) begin
    gioreq_prev <= gioreq;
    gioreq <= giorq_n == 1'b0 && gm1_n == 1'b1;
end

reg [8:0] g_int_cnt;
wire g_int_reload = g_int_cnt[8:6] == 4'b101;
always @(posedge clk12 or negedge rst_n) begin
    if (!rst_n) begin
        g_int_cnt <= 0;
        gint_n <= 1'b1;
    end
    else begin
        if (g_int_reload)
            g_int_cnt <= 0;
        else
            g_int_cnt <= g_int_cnt + 1'b1;

        if (g_int_reload)
            gint_n <= 1'b0;
        else if (g_int_cnt[5])
            gint_n <= 1'b1;
    end
end

/* GS EXTERNAL REGISTERS */
reg [7:0] gs_regdata, gs_regcmd;
wire port_b3 = zxa[7:0] == 8'hB3 && gs_ena;
wire port_bb = zxa[7:0] == 8'hBB && gs_ena;
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        gs_regdata <= 0;
        gs_regcmd <= 0;
    end
    else begin
        if (port_b3 && ioreq_wr)
            gs_regdata <= zxd;
        if (port_bb && ioreq_wr)
            gs_regcmd <= zxd;
    end
end

/* GS INTERNAL REGISTERS */
reg [7:0] gs_reg00, gs_reg_out;
wire [6:0] gs_page = gs_reg00[6:0];
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        gs_reg00 <= 0;
        gs_reg_out <= 0;
    end
    else if (~giorq_n && ~gwr_n) begin
        if (ga[3:0] == 4'h0) gs_reg00 <= gd;
        if (ga[3:0] == 4'h3) gs_reg_out <= gd;
    end
end

/* GS DAC REGISTERS */
reg gs_vol0_cs; always @(posedge clk32) gs_vol0_cs = ~giorq_n && ga[3:0] == 4'h6;
reg gs_vol1_cs; always @(posedge clk32) gs_vol1_cs = ~giorq_n && ga[3:0] == 4'h7;
reg gs_vol2_cs; always @(posedge clk32) gs_vol2_cs = ~giorq_n && ga[3:0] == 4'h8;
reg gs_vol3_cs; always @(posedge clk32) gs_vol3_cs = ~giorq_n && ga[3:0] == 4'h9;
reg gs_dac0_cs; always @(posedge clk32) gs_dac0_cs = ~gmreq_n && ga[15:13] == 3'b011 && ga[9:8] == 2'd0;
reg gs_dac1_cs; always @(posedge clk32) gs_dac1_cs = ~gmreq_n && ga[15:13] == 3'b011 && ga[9:8] == 2'd1;
reg gs_dac2_cs; always @(posedge clk32) gs_dac2_cs = ~gmreq_n && ga[15:13] == 3'b011 && ga[9:8] == 2'd2;
reg gs_dac3_cs; always @(posedge clk32) gs_dac3_cs = ~gmreq_n && ga[15:13] == 3'b011 && ga[9:8] == 2'd3;
wire gs_vol0_wr = gs_vol0_cs && ~gwr_n;
wire gs_vol1_wr = gs_vol1_cs && ~gwr_n;
wire gs_vol2_wr = gs_vol2_cs && ~gwr_n;
wire gs_vol3_wr = gs_vol3_cs && ~gwr_n;
wire gs_dac0_wr = gs_dac0_cs && ~grd_n;
wire gs_dac1_wr = gs_dac1_cs && ~grd_n;
wire gs_dac2_wr = gs_dac2_cs && ~grd_n;
wire gs_dac3_wr = gs_dac3_cs && ~grd_n;

/* GS STATUS REGISTER */
reg gs_flag_cmd, gs_flag_data;
wire [7:0] gs_status = {gs_flag_data, 6'b111111, gs_flag_cmd};

always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n)
        gs_flag_data <= 1'b0;
    else if (ioreq_rd && !ioreq_prev && port_b3)
        gs_flag_data <= 1'b0;
    else if (ioreq_wr && !ioreq_prev && port_b3)
        gs_flag_data <= 1'b1;
    else if (gioreq && !gioreq_prev && ga[3:0] == 4'h2)
        gs_flag_data <= 1'b0;
    else if (gioreq && !gioreq_prev && ga[3:0] == 4'h3)
        gs_flag_data <= 1'b1;
    else if (gioreq && !gioreq_prev && ga[3:0] == 4'hA)
        gs_flag_data <= ~gs_reg00[0];
end

always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n)
        gs_flag_cmd <= 1'b0;
    else if (ioreq_wr && !ioreq_prev && port_bb)
        gs_flag_cmd <= 1'b1;
    else if (gioreq && !gioreq_prev && ga[3:0] == 4'h5)
        gs_flag_cmd <= 1'b0;
    else if (gioreq && !gioreq_prev && ga[3:0] == 4'hB)
        gs_flag_cmd <= vol3[5];
end

/* GS BUS CONTROLLER */
assign grom_n = (~gmreq_n && ((ga[15:14] == 2'b00) || (ga[15] && gs_page == 0)))? 1'b0 : 1'b1;
`ifdef GS_RAM_2MB
    assign gram1_n = (~gmreq_n && grom_n && ((gs_page[5:4] == 2'd0) || ~ga[15]))? 1'b0 : 1'b1;
    assign gram2_n = (~gmreq_n && grom_n &&  (gs_page[5:4] == 2'd1) &&  ga[15] )? 1'b0 : 1'b1;
    assign gram3_n = (~gmreq_n && grom_n &&  (gs_page[5:4] == 2'd2) &&  ga[15] )? 1'b0 : 1'b1;
    assign gram4_n = (~gmreq_n && grom_n &&  (gs_page[5:4] == 2'd3) &&  ga[15] )? 1'b0 : 1'b1;
`else
    assign gram1_n = (~gmreq_n && grom_n && (~gs_page[4] || ~ga[15]))? 1'b0 : 1'b1;
    assign gram2_n = (~gmreq_n && grom_n &&   gs_page[4] &&  ga[15] )? 1'b0 : 1'b1;
    assign gram3_n = 1'b1;
    assign gram4_n = 1'b1;
`endif
assign gma = (ga[15] == 1'b0)? 4'b0001 : gs_page[3:0];
assign gd =
    (~giorq_n && ~grd_n && ga[3:0] == 4'h4)? gs_status :
    (~giorq_n && ~grd_n && ga[3:0] == 4'h2)? gs_regdata :
    (~giorq_n && ~grd_n && ga[3:0] == 4'h1)? gs_regcmd :
    (~giorq_n && (~grd_n || ~gm1_n))?        {8{1'b1}} :
                                             {8{1'bz}} ;


/* SOUNDRIVE */
wire port_xf = sd_ena && zxa[7] == 1'b0 && zxa[5] == 1'b0 && zxa[3:0] == 4'hF && !rom_m1_access;
wire [1:0] port_xf_chn = {zxa[6],zxa[4]};
reg sd_dac0_cs; always @(posedge clk32) sd_dac0_cs = ioreq && port_xf && port_xf_chn == 2'd0;
reg sd_dac1_cs; always @(posedge clk32) sd_dac1_cs = ioreq && port_xf && port_xf_chn == 2'd1;
reg sd_dac2_cs; always @(posedge clk32) sd_dac2_cs = ioreq && port_xf && port_xf_chn == 2'd2;
reg sd_dac3_cs; always @(posedge clk32) sd_dac3_cs = ioreq && port_xf && port_xf_chn == 2'd3;
wire sd_dac0_wr = sd_dac0_cs && ~zxwr_n;
wire sd_dac1_wr = sd_dac1_cs && ~zxwr_n;
wire sd_dac2_wr = sd_dac2_cs && ~zxwr_n;
wire sd_dac3_wr = sd_dac3_cs && ~zxwr_n;


/* DAC */
reg [5:0] vol0, vol1, vol2, vol3;
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        vol0 <= 0;
        vol1 <= 0;
        vol2 <= 0;
        vol3 <= 0;
    end
    else begin
        if      (sd_dac0_wr) vol0 <= 6'b111111;
        else if (gs_vol0_wr) vol0 <= gd[5:0];
        if      (sd_dac1_wr) vol1 <= 6'b111111;
        else if (gs_vol1_wr) vol1 <= gd[5:0];
        if      (sd_dac2_wr) vol2 <= 6'b111111;
        else if (gs_vol2_wr) vol2 <= gd[5:0];
        if      (sd_dac3_wr) vol3 <= 6'b111111;
        else if (gs_vol3_wr) vol3 <= gd[5:0];
    end
end

reg [7:0] dac0, dac1, dac2, dac3;
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        dac0 <= 0;
        dac1 <= 0;
        dac2 <= 0;
        dac3 <= 0;
    end
    else begin
        // quartus bug(?): without second condition inside "IF" expression incorrect design may be generated
        if (sd_dac0_wr && !gs_dac0_wr) dac0 <= (zxd[7]? zxd : {zxd[7],~zxd[6:0]});
        else if           (gs_dac0_wr) dac0 <= ( gd[7]? gd  : { gd[7],~gd[6:0]});
        if (sd_dac1_wr && !gs_dac1_wr) dac1 <= (zxd[7]? zxd : {zxd[7],~zxd[6:0]});
        else if           (gs_dac1_wr) dac1 <= ( gd[7]? gd  : { gd[7],~gd[6:0]});
        if (sd_dac2_wr && !gs_dac2_wr) dac2 <= (zxd[7]? zxd : {zxd[7],~zxd[6:0]});
        else if           (gs_dac2_wr) dac2 <= ( gd[7]? gd  : { gd[7],~gd[6:0]});
        if (sd_dac3_wr && !gs_dac3_wr) dac3 <= (zxd[7]? zxd : {zxd[7],~zxd[6:0]});
        else if           (gs_dac3_wr) dac3 <= ( gd[7]? gd  : { gd[7],~gd[6:0]});
    end
end

reg vol0_en, vol1_en, vol2_en, vol3_en;
reg [5:0] vol_cnt;
reg [7:0] dac0_cnt, dac1_cnt, dac2_cnt, dac3_cnt;
assign dac0_out = dac0_cnt[7]? dac0[7] : clk32;
assign dac1_out = dac1_cnt[7]? dac1[7] : clk32;
assign dac2_out = dac2_cnt[7]? dac2[7] : clk32;
assign dac3_out = dac3_cnt[7]? dac3[7] : clk32;
always @(posedge clk32) begin
    vol_cnt <= vol_cnt + 6'd31;
    vol0_en <= (vol_cnt < vol0) || (&vol0);
    vol1_en <= (vol_cnt < vol1) || (&vol1);
    vol2_en <= (vol_cnt < vol2) || (&vol2);
    vol3_en <= (vol_cnt < vol3) || (&vol3);
    if (vol0_en) dac0_cnt <= dac0_cnt[6:0] + dac0[6:0]; else dac0_cnt[7] <= 0;
    if (vol1_en) dac1_cnt <= dac1_cnt[6:0] + dac1[6:0]; else dac1_cnt[7] <= 0;
    if (vol2_en) dac2_cnt <= dac2_cnt[6:0] + dac2[6:0]; else dac2_cnt[7] <= 0;
    if (vol3_en) dac3_cnt <= dac3_cnt[6:0] + dac3[6:0]; else dac3_cnt[7] <= 0;
end


/* BUS CONTROLLER */
assign ard_n = ~ioreq_rd;
assign awr_n = ~ioreq_wr;
assign aa0 = zxa[1]? saa_a0 : ym_a0 ;
assign ad = ioreq_wr && (port_fffd || port_bffd || port_ff)? zxd : 8'bzzzzzzzz;

assign zxwait_n = 1'bz;
assign zxiorqge_n = (zxm1_n && (port_fffd_full || port_bffd || port_b3 || port_bb))? 1'b0 : 1'b1;
assign zxd =
    ioreq_rd && port_fffd? ad :
    ioreq_rd && port_b3? gs_reg_out :
    ioreq_rd && port_bb? gs_status :
    8'bzzzzzzzz;


endmodule
