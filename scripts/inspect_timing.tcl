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
# The snapshot carries the EEPROM abort word. Its marker nibble and the
# unused bits legitimately fold away; require the bank to stay mostly real.
if {[get_collection_size $captured] < 16 || [get_collection_size $published] < 16} {
    error "Diagnostic snapshot needs at least 16 variable bits in each bank"
}
puts "SNAPSHOT_BITS captured=[get_collection_size $captured] published=[get_collection_size $published]"


# The EEPROM bridge must survive as real logic. On 2026-09-09 constant
# propagation resolved a cycle through its fault latch and reduced the whole
# module to one ALM and two registers: no cartridge EEPROM access was ever
# issued and every read returned ones, while simulation passed throughout.
# These are the registers that must exist for the bridge to do anything.
foreach reg {transfer_open ctl_req command_active state} {
    set found [get_registers "*ee_bridge|$reg*"]
    if {[get_collection_size $found] == 0} {
        error "EEPROM bridge register '$reg' did not survive synthesis; the save path is not built"
    }
    puts "EEPROM_BRIDGE $reg=[get_collection_size $found]"
}
foreach corner [get_available_operating_conditions] {
    set_operating_conditions $corner
    update_timing_netlist
    report_timing -setup -npaths 20 -detail full_path -file $outdir/setup-$corner.txt
    # report_path reports physical data delay even between asynchronous clocks.
    # Do not remove clock groups just to make report_timing show this bundle.
    report_path -from $captured -to $published -npaths 1 -file $outdir/snapshot-$corner.txt
}
project_close
