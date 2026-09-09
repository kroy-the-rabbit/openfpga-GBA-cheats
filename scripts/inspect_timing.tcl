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
# 58 variable payload bits: data32, offset6, count16, flags4.
# The fixed marker nibble and low two address bits legitimately fold away.
set badword [get_registers {*header_check|bad_word[*]}]
set offset [get_registers {*header_check|bad_offset[*]}]
if {[get_collection_size $badword] < 32 || [get_collection_size $offset] < 6 ||
    [get_collection_size $captured] < 58 || [get_collection_size $published] < 58} {
    error "Header diagnostic requires its complete mismatch data/address and 58 variable snapshot bits"
}
puts "HEADER_REGISTERS data=[get_collection_size $badword] offset=[get_collection_size $offset] captured=[get_collection_size $captured] published=[get_collection_size $published]"
foreach corner [get_available_operating_conditions] {
    set_operating_conditions $corner
    update_timing_netlist
    report_timing -setup -npaths 20 -detail full_path -file $outdir/setup-$corner.txt
    # report_path reports physical data delay even between asynchronous clocks.
    # Do not remove clock groups just to make report_timing show this bundle.
    report_path -from $captured -to $published -npaths 1 -file $outdir/snapshot-$corner.txt
}
project_close
