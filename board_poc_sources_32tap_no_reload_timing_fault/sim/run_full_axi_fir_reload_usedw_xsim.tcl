proc add_if_exists {path} {
    if {[file exists $path]} {
        puts "Adding: $path"
        add_files -norecurse $path
        if {[string match -nocase "*.vhd" $path]} {
            set_property file_type {VHDL 2008} [get_files -quiet $path]
        }
    } else {
        puts "Skipping missing file: $path"
    }
}

set script_dir [file normalize [file dirname [info script]]]
set root_dir [file normalize [file join $script_dir ".."]]
set work_dir [file join $script_dir "xsim_full_axi_fir"]
set project_dir [file join $work_dir "proj"]

file delete -force $work_dir
file mkdir $work_dir

create_project -force full_axi_fir_reload_usedw $project_dir -part xc7z020clg400-1
set_property target_language VHDL [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [list \
    [file join $root_dir "src" "pl_sequencer_axi_lite_slave_lite_v1_0_S00_AXI.vhd"] \
    [file join $root_dir "src" "pl_sequencer_axi_lite.vhd"] \
    [file join $root_dir "src" "xpm_fifo_sync_wrap.vhd"] \
    [file join $root_dir "src" "coeff_ping_pong_bram.vhd"] \
    [file join $root_dir "src" "coeff_ping_pong_buffer.vhd"] \
    [file join $root_dir "src" "coeff_reload_sequencer.vhd"] \
    [file join $root_dir "src" "complex_channel_emulator.vhd"] \
    [file join $root_dir "src" "channel_emulator_prefetch_top.vhd"] \
    [file join $root_dir "src" "channel_emulator_axi_top.vhd"] \
]

foreach rtl_file $rtl_files {
    add_if_exists $rtl_file
}

add_if_exists [file join $root_dir "tb" "tb_full_axi_fir_reload_usedw.vhd"]

set ip_files [glob -nocomplain [file join $root_dir "ip" "*" "*.xci"]]
if {[info exists ::env(TDL_FIR_IP_DIR)]} {
    set env_ip_files [glob -nocomplain [file join $::env(TDL_FIR_IP_DIR) "*" "*.xci"]]
    set ip_files [concat $ip_files $env_ip_files]
}

if {[llength $ip_files] == 0} {
    puts "WARNING: No FIR .xci files found."
    puts "Put FIR IP under $root_dir/ip/<ip_name>/<ip_name>.xci, or set TDL_FIR_IP_DIR to a folder containing the FIR IP directories."
}

foreach ip_file $ip_files {
    puts "Adding IP: $ip_file"
    add_files -norecurse $ip_file
}

set design_ips [get_ips -quiet]
if {[llength $design_ips] != 0} {
    upgrade_ip $design_ips
    generate_target simulation $design_ips
}

set_property top tb_full_axi_fir_reload_usedw [get_filesets sim_1]
set_property runtime all [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_simulation -simset sim_1 -mode behavioral
run all
close_sim
close_project
