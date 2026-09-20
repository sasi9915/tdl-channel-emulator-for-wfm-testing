set script_dir [file normalize [file dirname [info script]]]
set root_dir [file normalize [file join $script_dir ".."]]
set work_dir [file join $script_dir "xsim_irq_pending"]

file delete -force $work_dir
file mkdir $work_dir
cd $work_dir

xvhdl --2008 [file join $root_dir "src" "pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI.vhd"]
xvhdl --2008 [file join $root_dir "src" "pl_sequencer_axi_lite.vhd"]
xvhdl --2008 [file join $root_dir "tb" "tb_irq_pending_axi_lite.vhd"]
xelab tb_irq_pending_axi_lite -debug typical -s tb_irq_pending_axi_lite_sim
xsim tb_irq_pending_axi_lite_sim -runall
