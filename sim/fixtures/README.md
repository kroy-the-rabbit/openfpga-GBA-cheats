# BMXE header fixture

`bmxe-header.hex` contains the first 192 bytes (48 little-endian DWORDs)
of the user's verified Metroid Zero Mission BMXE cartridge dump. It contains
no save data or game body. Source archive:
`../pocket-cartridge/build/card-verified-250d/ZEROMISSIONE.gba` (8,388,608 bytes).

- Full dump SHA256: `fc94f65380b65b870a30b9b04b39cca1dc63d6e46a4a373d3904adc0912ebc37`
- 192 binary header bytes SHA256: `581e4b24db4b3ac6d0e49d3e74894e15912ddcb6b2158265cd6408e068f4fc60`

The hardware reference in `cart_header_check.sv` groups the same little-endian
bytes into 24 aligned 64-bit pairs. Simulation uses this separate fixture to
check every reference word through both response orders and access widths.
Other game codes/revisions need their own verified reference; the top-level
checker is enabled only for the observed CG `424D5845`.
