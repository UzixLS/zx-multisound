export PATH:=/opt/modelsim201/modelsim_ase/bin:/cygdrive/c/Hwdev/modelsim181/modelsim_ase/win32aloem:/cygdrive/c/Hwdev/iverilog/bin/:/cygdrive/c/Hwdev/sjasmplus/:/cygdrive/c/Dev/srec/:${PATH}

all: testbench_top

testbench_top: IVFLAGS+=-I../rtl/
testbench_top: VSIMFLAGS+=+nowarn3722 +nowarn8822 +nowarn3017 +nowarn3155
testbench_top: testbench_top.v sine_dds.v

xtestbench_%:
	iverilog -g2005-sv ${IVFLAGS} -o $@.vvp $^
	vvp $@.vvp
	@rm $@.vvp

testbench_%:
	test ! -d work || rm -rf work
	vlib work
	test ! -n "$(filter %.v %.sv,$^)" || vlog -quiet -sv ${VLOGFLAGS} $(filter %.v %sv,$^)
	test ! -n "$(filter %.vhd %.vhdl,$^)" || vcom -quiet ${VCOMFLAGS} $(filter %.vhd %.vhdl,$^)
	vsim ${VSIMFLAGS} -batch -quiet -do 'run -all' $@
	test ! -r transcript || rm transcript

%.bin: %.asm
	sjasmplus $<

%.mem: %.bin
	srec_cat $< -binary -o $@ -vmem 8

clean:
	rm -rf ivl_vhdl_work/ work/ *.bin *.mem *.vcd

-include Makefile.local
