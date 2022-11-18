module sine_dds(
        input clk ,
        input reset,
        input [23:0] fcw,
        output [15:0] dds_sin,
        output dds_clk,
        output dds_stb
            );
reg [15:0] rom_memory [1023:0];
initial begin
    $readmemh("sine.mem", rom_memory);
end
   reg [23:0] accu;
   reg [1:0] fdiv_cnt;
   wire accu_en;
   reg accu_msb_q;
   wire [9:0] lut_index;

//process for frequency divider
always @(posedge clk)
begin
      if(reset == 1'b1)
         fdiv_cnt <= 0; //synchronous reset
      else if(accu_en == 1'b1)
         fdiv_cnt <= 0;
      else
         fdiv_cnt <= fdiv_cnt +1;
end
//logic for accu enable signal, resets also the frequency divider counter
assign accu_en = (fdiv_cnt == 2'd2) ? 1'b1 : 1'b0;
//process for phase accumulator
always @(posedge clk)
begin
      if(reset == 1'b1)
                accu <= 0; //synchronous reset
      else if(accu_en == 1'b1)
            accu <= accu + fcw;
end
//10 msb's of the phase accumulator are used to index the sinewave lookup-table
assign lut_index = accu[23:14];
//16-bit sine value from lookup table
assign dds_sin = rom_memory[lut_index];
endmodule
