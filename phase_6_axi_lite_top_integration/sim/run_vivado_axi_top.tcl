set script_dir [file normalize [file dirname [info script]]]
set phase_dir [file normalize [file join $script_dir ".."]]
set project_file [file join $phase_dir "work_proj" "work_proj.xpr"]

if {![file exists $project_file]} {
    error "Vivado project not found: $project_file"
}

open_project $project_file

set ip_files [glob -nocomplain [file join $phase_dir "ip" "*" "*.xci"]]
foreach ip_file $ip_files {
    set ip_name [file rootname [file tail $ip_file]]
    if {[llength [get_ips -quiet $ip_name]] == 0 && [llength [get_files -quiet $ip_file]] == 0} {
        add_files -norecurse -fileset sources_1 $ip_file
    }
}

# The Vivado project was created with imported source copies under work_proj.srcs.
# Keep simulation on one copy only; duplicate direct src/ entries make it unclear
# which entity body was analyzed last.
set source_files [list \
    [file join $phase_dir "src" "pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI.vhd"] \
    [file join $phase_dir "src" "pl_sequencer_axi_lite.vhd"] \
    [file join $phase_dir "src" "xpm_fifo_sync_wrap.vhd"] \
    [file join $phase_dir "src" "coeff_ping_pong_bram.vhd"] \
    [file join $phase_dir "src" "coeff_ping_pong_buffer.vhd"] \
    [file join $phase_dir "src" "coeff_reload_sequencer.vhd"] \
    [file join $phase_dir "src" "complex_channel_emulator.vhd"] \
    [file join $phase_dir "src" "channel_emulator_prefetch_top.vhd"] \
    [file join $phase_dir "src" "channel_emulator_axi_top.vhd"] \
]

foreach source_file $source_files {
    set direct_entries [get_files -quiet $source_file]
    if {[llength $direct_entries] != 0} {
        remove_files $direct_entries
    }
}

set tb_file [file join $phase_dir "tb" "tb_channel_emulator_axi_top.vhd"]
set direct_tb_entries [get_files -quiet $tb_file]
if {[llength $direct_tb_entries] != 0} {
    remove_files $direct_tb_entries
}

set_property top tb_channel_emulator_axi_top [get_filesets sim_1]
set_property runtime all [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
