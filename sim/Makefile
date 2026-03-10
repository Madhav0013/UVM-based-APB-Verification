# sim/Makefile

TEST ?= apb_smoke_test

compile:
	vlib work
	vlog -sv +incdir+../tb \
	    -f filelist.f \
	    -l compile.log

run: compile
	vsim -c -do "run -all; quit" \
	    +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=UVM_MEDIUM \
	    tb_top \
	    -l run_$(TEST).log

run_all:
	$(MAKE) run TEST=apb_smoke_test
	$(MAKE) run TEST=apb_reg_test
	$(MAKE) run TEST=apb_invalid_test
	$(MAKE) run TEST=apb_random_test
	$(MAKE) run TEST=apb_full_test

clean:
	rm -rf work *.log *.vcd *.wlf transcript

.PHONY: compile run run_all clean
