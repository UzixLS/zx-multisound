module zx_multisound(
    input rst_n,
    input clk32,
    input clkx,

    input [4:0] cfg,

    input [15:0] a,
    inout [7:0] d,
    input n_rd,
    input n_wr,
    input n_iorq,
    input n_mreq,
    input n_m1,
    output n_wait,
    output n_iorqge,

    input n_dos,
    input n_iodos,

    output aa0,
    inout [7:0] ad,
    output n_rstout,
    output n_ard,
    output n_awr,
    output ym_m,
    output n_ym1_cs,
    output n_ym2_cs,
    output reg fm1_ena,
    output reg fm2_ena,
    output n_saa_cs,
    output saa_clk,
    output midi_clk,

    input [15:0] ga,
    inout [7:0] gd,
    output n_grst,
    output gclk,
    output reg n_gint,
    input n_grd,
    input n_gwr,
    input n_gm1,
    input n_gmreq,
    input n_giorq,
    output n_grom,
    output n_gram1,
    output n_gram2,
    output [18:15] gma,

    output dac0_out,
    output dac1_out,
    output dac2_out,
    output dac3_out
);

assign n_rstout = rst_n;

// n_iorq are useless in zxevo :(
// so we're detecting n_iorq cycle by n_rd/n_wr signal asserted without n_m1/n_mreq
reg ioreq;
always @(negedge clk32) begin
    // ioreq <= n_iorq == 1'b0 && n_m1 == 1'b1 && n_dos == 1'b1 && n_iodos == 1'b1;
    ioreq <= n_m1 == 1'b1 && n_mreq == 1'b1 && (n_rd == 1'b0 || n_wr == 1'b0);
end
wire ioreq_rd = ioreq && n_rd == 1'b0;
wire ioreq_wr = ioreq && n_wr == 1'b0;

// n_dos are useless in zxevo :(
// so we're just lock some ports access when instruction has been fetched from rom
reg rom_m1_access;
always @(negedge clk32 or negedge rst_n) begin
    if (!rst_n)
        rom_m1_access <= 0;
    else if (n_m1 == 0)
        rom_m1_access <= a[15:14] == 2'b00;
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
wire port_bffd      = a[15:14] == 2'b10  && a[1:0] == 2'b01 && ym_ena;
wire port_fffd      = a[15:14] == 2'b11  && a[1:0] == 2'b01 && ym_ena;
wire port_fffd_full = a[15:13] == 3'b111 && a[1:0] == 2'b01 && ym_ena; // required for compatibility with #dffd port
reg ym_chip_sel, ym_get_stat;
wire ym_a0 = (~n_rd & a[14] & ~ym_get_stat) | (~n_wr & ~a[14]);
assign n_ym1_cs = ~(~ym_chip_sel && (port_bffd || port_fffd));
assign n_ym2_cs = ~( ym_chip_sel && (port_bffd || port_fffd));

always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        ym_chip_sel <= 0;
        ym_get_stat <= 0;
        fm1_ena <= 0;
        fm2_ena <= 0;
    end
    else if (port_fffd && ioreq_wr && d[7:4] == 4'b1111) begin
        ym_chip_sel <= ~d[0];
        ym_get_stat <= ~d[1];
        fm1_ena <= d[2]? 1'b0 : 1'bz;
        fm2_ena <= d[2]? 1'b0 : 1'bz;
    end
end

assign ym_m = clk3_5;


/* SAA1099 */
wire port_ff = a[7:0] == 8'hFF && saa_ena && !rom_m1_access;
assign n_saa_cs = ~(port_ff && ioreq_wr);
wire saa_a0 = a[8];

wire port_fffd_saa = a[15:14] == 2'b11 && a[1:0] == 2'b01 && saa_ena;
reg saa_clk_en;
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n)
        saa_clk_en <= 0;
    else if (port_fffd_saa && ioreq_wr && d[7:4] == 4'b1111)
        saa_clk_en <= ~d[3];
end

assign saa_clk = saa_clk_en? clk8 : 1'b0;


/* MIDI */
assign midi_clk = clk12;


/* GENERAL SOUND */
assign gclk = clk16;
assign n_grst = n_rstout;

reg [8:0] g_int_cnt;
wire g_int_reload = g_int_cnt[8:6] == 4'b101;
always @(posedge clk12 or negedge rst_n) begin
    if (!rst_n) begin
        g_int_cnt <= 0;
        n_gint <= 1'b1;
    end
    else begin
        if (g_int_reload)
            g_int_cnt <= 0;
        else
            g_int_cnt <= g_int_cnt + 1'b1;

        if (g_int_reload)
            n_gint <= 1'b0;
        else if (g_int_cnt[5])
            n_gint <= 1'b1;
    end
end

/* GS EXTERNAL REGISTERS */
reg [7:0] gs_regdata, gs_regcmd;
wire port_b3 = a[7:0] == 8'hB3 && gs_ena;
wire port_bb = a[7:0] == 8'hBB && gs_ena;
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        gs_regdata <= 0;
        gs_regcmd <= 0;
    end
    else begin
        if (port_b3 && ioreq_wr)
            gs_regdata <= d;
        if (port_bb && ioreq_wr)
            gs_regcmd <= d;
    end
end

/* GS INTERNAL REGISTERS */
reg [7:0] gs_reg00, gs_reg_out;
wire [5:0] gs_page = gs_reg00[5:0];
always @(posedge clk32 or negedge rst_n) begin
    if (!rst_n) begin
        gs_reg00 <= 0;
        gs_reg_out <= 0;
    end
    else if (~n_giorq && ~n_gwr) begin
        if (ga[3:0] == 4'h0) gs_reg00 <= gd;
        if (ga[3:0] == 4'h3) gs_reg_out <= gd;
    end
end

/* GS DAC REGISTERS */
reg gs_vol0_cs; always @(posedge clk32) gs_vol0_cs = ~n_giorq && ga[3:0] == 4'h6;
reg gs_vol1_cs; always @(posedge clk32) gs_vol1_cs = ~n_giorq && ga[3:0] == 4'h7;
reg gs_vol2_cs; always @(posedge clk32) gs_vol2_cs = ~n_giorq && ga[3:0] == 4'h8;
reg gs_vol3_cs; always @(posedge clk32) gs_vol3_cs = ~n_giorq && ga[3:0] == 4'h9;
reg gs_dac0_cs; always @(posedge clk32) gs_dac0_cs = ~n_gmreq && ga[15:13] == 3'b011 && ga[9:8] == 2'd0;
reg gs_dac1_cs; always @(posedge clk32) gs_dac1_cs = ~n_gmreq && ga[15:13] == 3'b011 && ga[9:8] == 2'd1;
reg gs_dac2_cs; always @(posedge clk32) gs_dac2_cs = ~n_gmreq && ga[15:13] == 3'b011 && ga[9:8] == 2'd2;
reg gs_dac3_cs; always @(posedge clk32) gs_dac3_cs = ~n_gmreq && ga[15:13] == 3'b011 && ga[9:8] == 2'd3;
wire gs_vol0_wr = gs_vol0_cs && ~n_gwr;
wire gs_vol1_wr = gs_vol1_cs && ~n_gwr;
wire gs_vol2_wr = gs_vol2_cs && ~n_gwr;
wire gs_vol3_wr = gs_vol3_cs && ~n_gwr;
wire gs_dac0_wr = gs_dac0_cs && ~n_grd;
wire gs_dac1_wr = gs_dac1_cs && ~n_grd;
wire gs_dac2_wr = gs_dac2_cs && ~n_grd;
wire gs_dac3_wr = gs_dac3_cs && ~n_grd;

/* GS STATUS REGISTER */
reg gs_flag_cmd, gs_flag_data;
wire [7:0] gs_status = {gs_flag_data, 6'b111111, gs_flag_cmd};

always @(posedge clk32) begin
    if ((~n_giorq && n_gm1 && ga[3:0] == 4'h2) || (ioreq_rd && port_b3))
        gs_flag_data <= 1'b0;
    else if ((~n_giorq && n_gm1 && ga[3:0] == 4'h3) || (ioreq_wr && port_b3))
        gs_flag_data <= 1'b1;
    else if (~n_giorq && n_gm1 && ga[3:0] == 4'hA)
        gs_flag_data <= ~gs_reg00[0];
end

always @(posedge clk32) begin
    if (~n_giorq && n_gm1 && ga[3:0] == 4'h5)
        gs_flag_cmd <= 1'b0;
    else if (ioreq_wr && port_bb)
        gs_flag_cmd <= 1'b1;
    else if (~n_giorq && n_gm1 && ga[3:0] == 4'hB)
        gs_flag_cmd <= vol3[5];
end

/* GS BUS CONTROLLER */
assign n_grom = (~n_gmreq && ((ga[15:14] == 2'b00) || (ga[15] && gs_page == 0)))? 1'b0 : 1'b1;
assign n_gram1 = (~n_gmreq && n_grom && (~gs_page[4] || ~ga[15]))? 1'b0 : 1'b1;
assign n_gram2 = (~n_gmreq && n_grom &&   gs_page[4] &&  ga[15] )? 1'b0 : 1'b1;
assign gma = (ga[15] == 1'b0)? 4'b0001 : gs_page[3:0];
assign gd =
    (~n_giorq && ~n_grd && ga[3:0] == 4'h4)? gs_status :
    (~n_giorq && ~n_grd && ga[3:0] == 4'h2)? gs_regdata :
    (~n_giorq && ~n_grd && ga[3:0] == 4'h1)? gs_regcmd :
    (~n_giorq && (~n_grd || ~n_gm1))?        {8{1'b1}} :
                                             {8{1'bz}} ;


/* SOUNDRIVE */
wire port_xf = sd_ena && a[7] == 1'b0 && a[5] == 1'b0 && a[3:0] == 4'hF && !rom_m1_access;
wire [1:0] port_xf_chn = {a[6],a[4]};
reg sd_dac0_cs; always @(posedge clk32) sd_dac0_cs = ioreq && port_xf && port_xf_chn == 2'd0;
reg sd_dac1_cs; always @(posedge clk32) sd_dac1_cs = ioreq && port_xf && port_xf_chn == 2'd1;
reg sd_dac2_cs; always @(posedge clk32) sd_dac2_cs = ioreq && port_xf && port_xf_chn == 2'd2;
reg sd_dac3_cs; always @(posedge clk32) sd_dac3_cs = ioreq && port_xf && port_xf_chn == 2'd3;
wire sd_dac0_wr = sd_dac0_cs && ~n_wr;
wire sd_dac1_wr = sd_dac1_cs && ~n_wr;
wire sd_dac2_wr = sd_dac2_cs && ~n_wr;
wire sd_dac3_wr = sd_dac3_cs && ~n_wr;


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
        if (sd_dac0_wr && !gs_dac0_wr) dac0 <= ( d[7]?  d : { d[7], ~d[6:0]});
        else if           (gs_dac0_wr) dac0 <= (gd[7]? gd : {gd[7],~gd[6:0]});
        if (sd_dac1_wr && !gs_dac1_wr) dac1 <= ( d[7]?  d : { d[7], ~d[6:0]});
        else if           (gs_dac1_wr) dac1 <= (gd[7]? gd : {gd[7],~gd[6:0]});
        if (sd_dac2_wr && !gs_dac2_wr) dac2 <= ( d[7]?  d : { d[7], ~d[6:0]});
        else if           (gs_dac2_wr) dac2 <= (gd[7]? gd : {gd[7],~gd[6:0]});
        if (sd_dac3_wr && !gs_dac3_wr) dac3 <= ( d[7]?  d : { d[7], ~d[6:0]});
        else if           (gs_dac3_wr) dac3 <= (gd[7]? gd : {gd[7],~gd[6:0]});
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
assign n_ard = ~ioreq_rd;
assign n_awr = ~ioreq_wr;
assign aa0 = a[1]? saa_a0 : ym_a0 ;
assign ad = ioreq_wr && (port_fffd || port_bffd || port_ff)? d : 8'bzzzzzzzz;

assign n_wait = 1'bz;
assign n_iorqge = (n_m1 && (port_fffd_full || port_bffd || port_b3 || port_bb || port_ff || port_xf))? 1'b0 : 1'b1;
assign d =
    ioreq_rd && port_fffd? ad :
    ioreq_rd && port_b3? gs_reg_out :
    ioreq_rd && port_bb? gs_status :
    8'bzzzzzzzz;


endmodule
