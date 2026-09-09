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
# Fail if the area-saving ROM was implemented as logic or disappeared.
# Read the actual fitted memory table, not an HDL attribute or total RAM count.
set report_file [open output_files/ap_core.fit.rpt r]
fconfigure $report_file -encoding iso8859-1
set m10k_column -1
set header_m10ks 0
foreach line [split [read $report_file] "\n"] {
    set fields {}
    foreach field [split $line ";"] {lappend fields [string trim $field]}
    set column [lsearch -exact $fields "M10K blocks"]
    if {$column >= 0} {set m10k_column $column}
    if {$m10k_column >= 0 && [string match {*header_check*header_rom*} [lindex $fields 1]] &&
        [lindex $fields 2] eq "M10K"} {
        set blocks [lindex $fields $m10k_column]
        if {[string is integer -strict $blocks]} {incr header_m10ks $blocks}
    }
}
close $report_file
if {$header_m10ks < 1} {error "Header diagnostic requires the reference ROM in M10K memory"}
puts "HEADER_REFERENCE_M10K blocks=$header_m10ks"
foreach corner [get_available_operating_conditions] {
    set_operating_conditions $corner
    update_timing_netlist
    report_timing -setup -npaths 20 -detail full_path -file $outdir/setup-$corner.txt
    # report_path reports physical data delay even between asynchronous clocks.
    # Do not remove clock groups just to make report_timing show this bundle.
    report_path -from $captured -to $published -npaths 1 -file $outdir/snapshot-$corner.txt
}
project_close
