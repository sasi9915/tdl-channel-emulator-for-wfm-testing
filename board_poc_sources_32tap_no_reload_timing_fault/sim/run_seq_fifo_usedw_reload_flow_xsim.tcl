set script_dir [file normalize [file dirname [info script]]]
set root_dir [file normalize [file join $script_dir ".."]]
set work_dir [file join $script_dir "xsim_seq_fifo"]

file delete -force $work_dir
file mkdir $work_dir
cd $work_dir

xvhdl --2008 [file join $root_dir "tb" "xpm_fifo_sync_wrap_sim.vhd"]
xvhdl --2008 [file join $root_dir "src" "coeff_reload_sequencer.vhd"]
xvhdl --2008 [file join $root_dir "tb" "tb_seq_fifo_usedw_reload_flow.vhd"]
xelab tb_seq_fifo_usedw_reload_flow -debug typical -s tb_seq_fifo_usedw_reload_flow_sim
xsim tb_seq_fifo_usedw_reload_flow_sim -runall
