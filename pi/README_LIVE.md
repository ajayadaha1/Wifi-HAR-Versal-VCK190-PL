# WiFi-HAR VCK190 — v01.1 SD-boot image (live Raspberry-Pi CSI path)

This image adds the **last-mile fix** for the live Raspberry-Pi path: a `no-map`
reserved-memory **carve-out at `0x7000_0000`** so the PL DMA movers
(`s2mm` / `s2mm_meta`) can land CSI results/metadata in DDR **without panicking the
kernel** (root cause + fix: `docs/PROJECT_STATE.md` §25.5 / §26).

Validated on silicon — the kernel boot log now shows:
```
OF: reserved mem: 0x0000000070000000..0x00000000700fffff (1024 KiB) nomap non-reusable csi-meta@70000000
```

## Files

| File | Put on | What |
|---|---|---|
| `BOOT.BIN`    | SD FAT partition | PLM + PL PDI (eth + ILAs) + AIE CDO + u-boot |
| `image.ub`    | SD FAT partition | FIT: kernel + **fixed dtb (carve-out)** + full rootfs |
| `system.dtb`  | SD FAT partition | the fixed dtb (fallback for the separate-images boot path) |
| `boot.scr`    | SD FAT partition | u-boot loads `image.ub` (required for SD autoboot) |
| `live-tools/` | copy to board `/home/root` | live bring-up + streaming drain |

Serial console: **115200 8N1**, on the Versal **PS** UART (COM/`ttyUSB` for
interface 01) — *not* the System-Controller / BEAM port.

## 1. Boot & confirm the fix

Copy the four files to the FAT partition, set SW1 to SD boot, power on. After Linux
is up, confirm the carve-out took effect:
```sh
grep 7000 /proc/iomem            # -> a reserved (unnamed) hole at 70000000-700fffff
dmesg | grep -i "reserved mem"   # -> ...nomap... csi-meta@70000000
```

## 2. Live CSI drain (Pi on SFP0)

Cable the Raspberry Pi (running `nexmon_csi`, streaming UDP:5500) into **SFP0**
(the design GT is SFP0 = bank 105, GTY ch2 — there are two cages, use SFP0).

Copy `live-tools/` to `/home/root` and run:
```sh
cd /home/root
sh d2eth_live.sh                 # verify carve-out -> stop golden autorun ->
                                 # mac-init(force 1G, AN off) -> csi_mux=0(live) ->
                                 # parser + s2mm_meta on -> inline_reader stream drain
# dashboard instead of CSV:
DASH=1 sh d2eth_live.sh          # http://<board-ip>:8080
```

Notes:
- **Force 1G / autoneg OFF** is deliberate: a copper SFP speaks SGMII, so
  1000BASE-X clause-37 fiber autoneg never completes; `pl_mac.py check noan`
  disables AN and the 1.25G SerDes locks (`LINK=UP`).
- Do **not** run the golden one-shot `host` on the live mux — it stalls on a
  free-running stream (§25.6). `d2eth_live.sh` uses the correct streaming drain.
- If `d2eth_live.sh` reports it cannot confirm the carve-out, you are not on the
  v01.1 image — reflash `image.ub` (running the live drain without the carve-out
  will panic the kernel).

## Manual sequence (what d2eth_live.sh runs)
```sh
pkill -9 -f d2eth-ila-autorun.sh          # stop the golden autorun loop
python3 pl_mac.py check noan              # MAC init + link up (force 1G)
#   expect: PCS ... LINK=UP  and  RXWATCH d_bytes>0  (live CSI arriving)
# csi_mux MI0 -> 0 (live parser)          # (d2eth_live.sh pokes 0xA4060040=0, commit)
python3 pl_mac.py start                   # parser + s2mm_meta (SAFE on v01.1)
python3 inline_reader.py --arm --loop --decode --hz 10
```
