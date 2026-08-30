# WiFi-HAR VCK190 — v1.2 SD-boot image (live Raspberry-Pi CSI path)

v1.2 fixes the live-drain **Async SError** that v01.1 still hit (PROJECT_STATE.md
#27). Root cause: physical DDR `0x7000_0000` sits in a **firewalled/reserved DDR
aperture** the Versal NoC rejects — so any transaction there (PL `s2mm_meta` DMA or
CPU `/dev/mem`) raises an asynchronous external abort → kernel panic. Adding a
`reserved-memory` node (v01.1) fixed the *boot* view of that RAM but not the
*bus* rejection.

**The v1.2 fix:** drain through **XRT-managed DDR buffers** (`bo.address()`, which
XRT allocates in a NoC-validated DDR bank — the exact mechanism the golden
`mm2s→AIE→s2mm` path uses with zero SError). The new `host_live` targets `s2mm`
(AIE features) and `s2mm_meta` (metadata) at XRT buffers. **No fixed `0x70000000`,
no `/dev/mem` DDR access.**

## Files

| File | Put on | What |
|---|---|---|
| `BOOT.BIN`   | SD FAT | PLM + PL PDI (eth + ILAs) + AIE CDO + u-boot |
| `image.ub`   | SD FAT | FIT: kernel + dtb (carve-out kept, harmless) + rootfs |
| `system.dtb` | SD FAT | dtb (fallback path) |
| `boot.scr`   | SD FAT | u-boot loads image.ub |
| `live-tools/`| board `/home/root` | `host_live` (the fix), `pl_mac.py`, `live_dashboard.py`, `d2eth_live.sh` |

Serial console: **115200 8N1** on the Versal **PS** UART (interface 01), not the
System-Controller/BEAM port.

## Live CSI (Pi on SFP0)

Cable the Pi (running `nexmon_csi`, UDP:5500) into **SFP0** (bank 105, GTY ch2 —
there are two cages, use SFP0). On the board:
```sh
cd /home/root/aie-d2eth-ila            # host_live + xclbin + input.txt + golden.txt ship here
# prove the XRT-bo drain works (no Pi needed):
./host_live --selftest inline_cogen_d2eth_ila.xclbin --in input.txt --gold golden.txt
#   -> "SELFTEST PASS (XRT-bo drain, no 0x70000000)"
# then the live drain:
sh /home/root/d2eth_live.sh            # link up (force 1G) -> csi_mux=0 -> host_live --live
DASH=1 sh /home/root/d2eth_live.sh     # same, but dashboard on http://<board-ip>:8080
```

`host_live --live` sets `csi_mux=0`, arms the parser + `s2mm_meta` (into an XRT
buffer, so it never SErrors and never backpressures the parser), and streams the
AIE feature triplet as CSV (`mot0,mot1,mot2,...`) per window.

## Notes
- Do **not** use the old `/dev/mem` fixed-`0x70000000` path (`inline_reader.py
  --arm`) on this design — that is what SErrors. `host_live` replaces it.
- Force 1G / autoneg OFF is required (copper SFP = SGMII; clause-37 fiber AN never
  completes).
- If `host_live --live` prints "waiting for AIE window", the Pi isn't streaming
  into SFP0 or the link is down — check `pl_mac.py check noan` shows `LINK=UP`.
