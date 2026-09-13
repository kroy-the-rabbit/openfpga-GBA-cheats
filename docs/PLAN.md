# Development work

## Remaining work

- Qualify physical SRAM/Flash writes, interrupted transfers and empty slots
  on hardware. Existing EEPROM saves and a Zero Mission write already pass.
- Route cartridge GPIO/RTC, solar and gyro if those features are added.
- Test Fast Burst on additional cartridges. It stays opt-in; Turnaround
  remains the default.
- Decode native Action Replay ROM-patch forms and encrypted codes if support
  is added. Current ROM patches use explicit raw CodeBreaker writes.

The cartridge controller is derived from Wokann/openfpga-GBA and has local
burst, timing and integration changes. Rai/openfpga-GBA informed the APF
declaration. The machine is MiSTer-devel/GBA_MiSTer through mincer-ray's
Pocket port; the overlay derives from the GBC fork. Attribution and the
original design references are preserved in the engineering history and source.


[Design studies and phase history](https://github.com/kroy-the-rabbit/pocket-engineering/blob/main/gba/docs/PLAN.md) (private).
