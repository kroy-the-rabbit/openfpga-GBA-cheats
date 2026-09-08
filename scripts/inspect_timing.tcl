# Run quartus_sta -t /work/scripts/inspect_timing.tcl from src/fpga/build
# after fitting. Reports use the existing SDC without changing exceptions.
package require ::quartus::project
package require ::quartus::sta
project_open ap_core
create_timing_netlist
read_sdc
set outdir /work/timing-paths
file mkdir $outdir
set captured [get_registers {*boot_debug|captured_debug[*]}]
set published [get_registers {*boot_debug|host_debug[*]}]
if {[get_collection_size $captured] == 0 || [get_collection_size $published] == 0} {
    error "Diagnostic snapshot registers were not found"
}
set pattern [get_registers {*|cart_debug_pattern[*]}]
if {[get_collection_size $pattern] < 64 ||
    [get_collection_size $captured] < 64 ||
    [get_collection_size $published] < 64} {
    error "Pattern experiment requires the full source and both 64-bit snapshot banks"
}
puts "PATTERN_REGISTERS source=[get_collection_size $pattern] captured=[get_collection_size $captured] published=[get_collection_size $published]"
foreach corner [get_available_operating_conditions] {
    set_operating_conditions $corner
    update_timing_netlist
    report_timing -setup -npaths 20 -detail full_path -file $outdir/setup-$corner.txt
    # report_path reports physical data delay even between asynchronous clocks.
    # Do not remove clock groups just to make report_timing show this bundle.
    report_path -from $captured -to $published -npaths 1 -file $outdir/snapshot-$corner.txt
}
project_close
