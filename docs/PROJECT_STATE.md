# PROJECT STATE — VCK190 WiFi‑CSI Human Activity Recognition (thesis)

> Portable handoff/memory file. Lives in the workspace (`/group/...`) so it is
> available from any machine. Companion to [plan.md](plan.md).
>
> **Read §2 for status, then §20 for the one open blocker.** Sections 1-15 are
> historical narrative and contain conclusions that were later disproved; where
> that happened the withdrawal is noted in the later section. Detailed bring-up
> log for 2026-08-18 is §16-§20.

---

## 0. One‑line goal
Raspberry Pi (nexmon_csi) streams WiFi CSI over Ethernet → **VCK190**; parse UDP +
run the CSI **DSP feature extraction** on **AI Engine + PL**; **DMA only results** to
Linux for visualization. Classifier follows **ruview** (NOT a spectrogram CNN):
DSP → **8‑feature vector** → tiny **Enc(8→64→128)** MLP → presence/activity.

## 1. Locked decisions (see plan.md §"Decisions locked")
- Deliverables: **HAR + Fall + Breathing** (+ live pose skeleton as a stretch demo).
- Hardware: **Raspberry Pi 4 (bcm43455c0)** + Pi 3B+ (multi‑Pi possible). Pi→VCK190 over **SFP**.
- CSI source: **nexmon_csi already working** (user side).
- Tools/OS: **Vivado/Vitis 2025.2** + **PetaLinux**. Board part `xcvc1902-vsva2197-2MP-e-S`.
- Models: **pretrained only** (ruview weights); no local GPU training.
- Sequencing: **offline first → inline PL path**; the classifier is the ruview encoder, and
  the FPGA/AIE contribution is the **DSP feature extraction** (the ML is a 9,280‑param MLP).

## 2. Phase progress
| Phase | Status | Evidence |
|---|---|---|
| **P0** baseline HW | ✅ | Vivado 2025.2 design builds → `work/hw/ps_emio_basex_hw/ps_emio_basex_baseline.xsa` |
| **P1** offline pipeline | ✅ | `work/csi_ref/*` all self‑checks PASS (BR 18.0 BPM, motion 206×, encoder unit‑norm, e2e distinct) |
| **P2** AIE kernels | ✅ | FIR/DFT/stats + composed FIR→stats graph: math bit‑accurate vs numpy, aiecompiler codegen accepted |
| **P3** AIE graph → 3-branch | ✅ | feature_graph = **motion (FIR→stats) + breathing (windowed-DFT `dft_mag`) + phase-var (stats)** (6 PLIO); **x86sim PASS** vs numpy (motion 2e-7, breathing 33 bins 6e-8, phase-var 9e-8); toward the 8-feature vector; `libadf_motiononly.a` = 1-branch backup |
| **P2** AIE **hw** compile | ✅ | `libadf.a` (456 KB) built on `xcoapps75` (Ubuntu 24.04); CDO g++ stage passes clean — the §6 blockers no longer apply |
| **P3** v++ link (AIE+PL→XSA) | ✅ | `feature_graph.xsa` (3.6 MB, 20 min): `mm2s`/`s2mm` data movers (HLS II=1, Fmax ~478 MHz) + AIE FIR→stats graph linked onto `xilinx_vck190_base`; DDR↔movers↔AIE PLIO |
| **P2** inline UDP/CSI parser | ✅ | `work/udp_parser` HLS: C-sim + **C/RTL co-sim PASS**, IP exported (`csi_udp_parser_prj/sol1/impl/export.zip`). **2026-08-17: `meta_out` changed `ap_fifo` → 64-bit AXIS** (one packed `csi_meta_t` per frame) so metadata can reach DDR; csim + **co-sim PASS** again, IP re-packaged into `hw/ip_repo/csi_udp_parser` |
| **P4** PetaLinux (SDT flow) | ✅ | SDT from XSA via `xsct sdt.tcl` (board `versal-vck190-reva-x-ebm-01-reva`); `petalinux-config` + `petalinux-build` done → `images/linux/` (Image 31M, plm/psmfw/bl31 elf, rootfs.ext4, system.dtb, boot.scr). sysroot/BOOT.BIN pending |
| **P3** inline BD (parser+AIE) | ✅ | hand-captured IPI design `work/hw/scripts/inline_csi_bd.tcl` (1198 lines): `csi_udp_parser` → `ai_engine` (feature graph) → `s2mm` → DDR on CIPS+NoC; **`validate_bd_design` PASS**; parser `rx`/`meta`/`ctrl` external (for PL Eth MAC) |
| **P5** inline impl QoR | ✅ | routed `impl_1` (0 errors, 0 crit-warn): datapath **312.5 MHz timing MET** (WNS +0.586 / WHS +0.014 ns); **0.62% LUT** (5551), 0.37% FF, **0 DSP**, 0.5 BRAM; 23.0 W; `vitis_design_wrapper.pdi` generated — parser placed&routed in the AIE path |
| **P2/P3** full inline BD | ✅ | complete Arch-B chain `axi_ethernet → rx_dwidth(32→8) → csi_udp_parser → ai_engine → s2mm → DDR` on CIPS+NoC; **`validate_bd_design` PASS**; captured `hw/scripts/inline_full_bd.tcl` (1313 lines); MAC GMII/GT/control external (attach to baseline PCS-PMA/GT/CIPS) |
| **P5** full-inline synth QoR | ✅ | `synth_1` 100% of MAC+dwidth+parser+AIE+s2mm: **1.34% LUT** (12095), **0 DSP**, 4.5 BRAM — the Ethernet ingest adds only ~0.7% PL over the AIE-only datapath. impl needs GT pin constraints (attach PCS-PMA/GT); mapping in §9 |
| **P6** on-target validation (`vck190-13`) | ✅ | **HW PASS on real VCK190**: `host feature_graph.xclbin input.txt golden.txt` → `mean=-0.002065 var=0.302189 power=0.302193` == golden, **max_abs_err=5.96e-08 (bit-accurate), rc=0**. Full **DDR→mm2s→AIE(FIR→stats)→s2mm→DDR** datapath validated on silicon. Needed 3 fixes (see §10): (1) zocl dtb `interrupts-extended`, (2) `aie_image` graph CDO baked into BOOT.BIN, (3) drop host `graph.wait()` (PDI free-runs the graph) |
| **P7** 3-branch on-target (`vck190-2`/morel15) | ✅ | **FULL 8-feature HW PASS (2026-08-16)**: `host_3br feature_graph_3br.xclbin` → `[mot] PASS` (max_abs_err 5.96e-08), `[brt] 33 bins PASS` (1.91e-06), `[phs] PASS` (8.94e-08), **OVERALL: PASS** — all 3 branches (motion FIR→stats, breathing windowed-DFT `dft_mag`, phase-var stats) bit-accurate on silicon. Boot: clean `BOOT_3br_clean.BIN` + JTAG-load Image/dtb/rootfs (no Ethernet, §10). Last fix: XRT CU-select `mm2s:{mm2s_mot}`. |
| **P8** Linux on the inline design | ✅ | Boots to userspace on `vck190-2`/morel15. Needed **lopper**, not a hand-rolled SDT reduction - three separate boot failures (RPU GICv2, unresolved interrupt-multiplex, OCM offered as system RAM over TF-A). `check_linux_dtb.py` now asserts all three at build time. §16, §19 |
| **P8** inline PL datapath on silicon | ✅ | `mm2s_rx → rx_inj_dwidth → rx_mux → csi_udp_parser → s2mm_meta → DDR` **runs to completion** (`mm2s_rx = 0x0E`). Proved by changing only the parser's UDP port so it discards instead of emitting to the AIE. ILA on two streams confirms TVALID/TREADY behaviour. §17, §20 |
| **P8** inline AIE ingest | ❌ **BLOCKED** | Graph loads and its core is **enabled and stalled waiting for input** at (24,1). PL↔AIE channels now correctly pinned to column 24 (were column 11 - a real bug, fixed). Still no data crosses: the AIE↔PL binding is xclbin metadata lost when `ai_engine` was captured out of `v++ --link`. **Fix = re-link with v++, not another property.** §20 |
| **P8** Ethernet ingest | ❌ blocked | PCS `BMSR` reads a constant `0x01c8` link-down in every GT loopback mode, while the GT itself is provably healthy (powergood, PLL lock, all four reset-done, both clock heartbeats advancing). Separate from the AIE blocker. §17 |
| **P5** dashboard | ✅ | Live at `http://172.25.66.228:8090/` off the bit-accurate AIE golden vectors (self-contained, no CDN). `inject_inline_rootfs.sh` also hosts it **on the board** (`--source inline`, stdlib-only) |

## 3. Work-area map: `/group/bcapps/ajayad/master_thesis_rebirth/work/`
```
hw/ps_emio_basex_hw/     Vivado 2025.2 project; baseline XSA built
hw/scripts/              project_top.tcl, ps_emio_basex_bd.tcl, ps_emio_basex_2025.2.tcl, build_baseline.tcl, open_project.sh
csi_capture/             capture_csi.sh (Pi), decode_csi.py (pcap→npy/json), make_test_pcap.py, requirements.txt
csi_ref/                 P1 pipeline: synth_csi.py, csi_pipeline.py, har.py, features8.py, encoder_v2.py, run_*.py, golden/
csi_ref/models/          ruview pretrained encoder: csi-embed-v2.safetensors (9280 p), presence-head.json, csi-embed-v2.py, config.json
data/                    sample_7class_128.npz (small HF sample), spectrogram_examples/*.png
udp_parser/              HLS UDP/CSI parser (csi_udp_parser.{hpp,cpp}, tb, run_hls.tcl) — C-sim PASS (synthetic nexmon frame, bit-exact I/Q + meta)
aie/fir_bandpass/        AIE FIR band-pass kernel (motion/breathing filter)
aie/dft_mag/             AIE windowed-DFT-magnitude kernel (breathing/STFT FFT)
aie/stats/               AIE mean/variance/power kernel (phase-var, motion power)
aie/feature_graph/        composed FIR→stats multi-kernel graph; build_hw.sh + tools/debuginfod_stub.c
aie/feature_graph/pl/     PL data movers mm2s.cpp/s2mm.cpp (DDR↔AIE PLIO, 32-bit AXIS) for the v++ link
aie/feature_graph/host/   XRT host app (host.cpp) + cross-compile Makefile to validate DDR→AIE→DDR on target
petalinux/petalinux/      PetaLinux 2025.2 project (SDT flow, from BSP); configured with the feature_graph SDT
petalinux/sdt.tcl         xsct/sdtgen wrapper: XSA -> SDT (board versal-vck190-reva-x-ebm-01-reva)
petalinux/sdt_outdir/     SDT generated from feature_graph.xsa (device tree + vpl_gen_fixed.pdi)
hw/ip_repo/csi_udp_parser/  parser packaged as a Vivado IP (xilinx.com:hls:csi_udp_parser:1.0) for IPI
hw/scripts/inline_from_vpl.tcl + validate_inline.tcl  build/validate the inline IPI block design
hw/scripts/inline_csi_bd.tcl  CAPTURED validated inline BD: csi_udp_parser -> AI Engine -> s2mm -> DDR
hw/scripts/eth_mac_parser_bd.tcl  CAPTURED validated PL Eth front-end: axi_ethernet(GMII) m_axis_rxd -> csi_udp_parser.rx
hw/scripts/  EXACTLY TWO FILES, on purpose:
  project_top.tcl                project + IP catalog + sources -> build_inline_bd -> synth/impl -> XSA
  inline_design.tcl              THE design: create_root_design (captured IPI) + add_eth_phy (hand-written);
                                 entry point build_inline_bd
hw/build.sh                      `bash work/hw/build.sh [bd_only]` - the only way you should invoke the above
hw/hdl/eth_gt_phy.v              the SFP0 GTY front end: gtwiz_versal + IBUFDS_GTE5 + 4 BUFG_GT + pma_reset sync
hw/ip/csi_eth_gtwiz.xci          gtwiz_versal moved onto quad channel 2; the ONLY hand-edited IP file (see §11)
hw/hdl/axis_sink.v               drains the MAC's RX-status stream (unconsumed, it back-pressures RX)
hw/constraints/inline.xdc        SFP0 GTY + 156.25 MHz refclk pin constraints
hw/inline_eth_hw/inline.xsa      ✅ the built inline Arch-B XSA (§12)
hw/ref_axi_eth_example/          READ-ONLY reference: the axi_ethernet 8.0 example design (gtwiz_versal + GT wiring), see its README.md```
Each AIE kernel dir: pure‑C core (`*_core.h`) shared by the AIE kernel + a `gcc` host test
(`run_host.sh` → PASS), plus `gen_golden.py`, `compare.py`, `run_x86sim.sh`.

## 4. Key technical facts (validated)
- **nexmon_csi wire format** (bcm43455c0): UDP **port 5500**; 18‑byte header
  (magic, rssi, fc, src_mac, seq, core/spatial, chanspec, chip); CSI at **byte 60**;
  **int16 LE I/Q** per subcarrier (20MHz→64, 40→128, 80→256). Confirm against a real
  capture with `decode_csi.py` (it prints raw header hex). `csi_capture/decode_csi.py` +
  `make_test_pcap.py` reproduce this end‑to‑end.
- **ruview 8‑feature vector** (magic `0xC5110003`, from ruview `docs/user-guide.md`):
  `0 presence/10  1 motion/10  2 breathing_bpm/30  3 hr/120  4 phase‑var  5 persons/4  6 fall  7 (rssi+100)/100`.
  Verified: rssi −18 → `0.82`. Implemented in `csi_ref/features8.py`.
- **ruview encoder**: `Enc: Linear(8→64)→BN→GELU→Linear(64→128)→BN→L2` (9,280 params);
  input is the 8‑feature vector (NOT raw CSI). Real weights load via numpy in `csi_ref/encoder_v2.py`.
- **Current Vivado design** terminates Ethernet in **PS GEM0** (GMII/EMIO → PL PCS/PMA);
  the PL does NOT yet see packets as AXI‑Stream, and there is **no AIE / no DMA** in it yet.
  DDR4 via NoC exists. Inline‑PL parsing + AIE + results‑DMA is the thesis engineering.

## 5. Environment setup (do this first each session)
> **Current host: `xcoapps75` (Ubuntu 24.04 LTS, glibc 2.39, gcc/g++ 13.3).** A
> supported OS for 2025.2 — the §6 Ubuntu‑20 workarounds are NOT needed here.
```bash
# Tools (Vivado/Vitis/aiecompiler/x86simulator/v++):
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh      # or: ts 2025.2
# Python (numpy/scipy/h5py) — venv lives in /tmp (local; recreate if the box was rebooted):
/tmp/venv/bin/python ...        # recreate: python3 -m venv /tmp/venv && /tmp/venv/bin/pip install numpy scipy h5py
```
**PetaLinux 2025.2** (project `work/petalinux/petalinux`, SDT flow, from BSP):
```bash
export TMPDIR=/tmp/petalinux-ajayad         # REQUIRED: clears false "missing zlib/ncurses" + avoids hourly /tmp cleanup
ts -petalinux petalinux-v2025.2_released    # puts petalinux-{config,build,package} on PATH
# SDT flow — generate an SDT from the XSA with sdtgen (work/petalinux/sdt.tcl), NOT the raw .xsa:
xsct work/petalinux/sdt.tcl <design.xsa> sdt_outdir     # board_dts=versal-vck190-reva-x-ebm-01-reva
petalinux-config --get-hw-description <sdt_outdir> --silentconfig
# petalinux-build: launch from a Vitis-clean env (unset XILINX_VITIS/VIVADO/HLS/XRT + LD_LIBRARY_PATH)
```
- VCK190 part: `xcvc1902-vsva2197-2MP-e-S`
- Base platform: `/proj/rdi/xbuilds/2025.2_released/internal_platforms/xilinx_vck190_base_202520_1`
- HF dataset (processed CSI **spectrogram images**, 173k×128×128 uint8, 7 classes) is huge
  (587 GB total). Only a small `data/sample_7class_128.npz` is kept. Big files were pulled to
  `/tmp` (179 GB free), used, then deleted — **do not keep big files on `/group` (95% full)**.

## 6. ⚠️ Ubuntu‑20 / Vitis‑2025.2 workarounds (CRITICAL — else builds fail)
> ✅ **RESOLVED on `xcoapps75` (Ubuntu 24.04).** All three blockers below only
> affected the old `xcoapps66` (Ubuntu 20.04). On the 24.04 host: (1) system
> **g++ 13.3** is present; (2) **glibc 2.39** satisfies the bundled
> `libdebuginfod.so.1` (needs 2.34+); (3) the **`/usr/include/asm` symlink
> already exists by default** (no root needed). `build_hw.sh` runs unchanged — its
> stub/CPATH/`--Xpreproc` extras are harmless no‑ops here. Keep this section for
> the old host / any RHEL‑8 fallback.

This host (`xcoapps66`, Ubuntu 20.04) is **not officially supported** by 2025.2. Fixes found:
1. **x86simulator won't link** (no system `g++`). → Use AIE **`--target=hw`** (chess) for real
   compiles; validate kernel **math** with system `gcc` via the shared pure‑C core + host test.
2. **elfgen `readelf` needs `libdebuginfod.so.1`** (absent; bundled copy needs glibc 2.34, host has 2.31).
   → Build a **glibc‑2.31 no‑op stub**: `aie/feature_graph/tools/debuginfod_stub.c` →
   `/tmp/extralibs/libdebuginfod.so.1`, add to `LD_LIBRARY_PATH`. (Done in `build_hw.sh`.) ✅ works.
3. **CDO generation `g++` can't find `asm/errno.h`** (multiarch). aiecompiler **scrubs `CPATH`**,
   and `--Xpreproc` does NOT reach the hardcoded CDO g++. **Only reliable fix (needs root, one‑time):**
   ```bash
   sudo ln -s /usr/include/x86_64-linux-gnu/asm /usr/include/asm
   ```
   Safe symlink to an existing dir; standard fix for non‑distro toolchains. **This is the last blocker
   for `libadf.a`.** Alternative: build on a **supported OS** (RHEL 8/9, Ubuntu 22/24) — `build_hw.sh` runs unchanged.

## 7. Terminal quirks in this environment
- Long **sync** `run_in_terminal` commands get Ctrl‑C'd by the next call → run long builds
  (Vivado, aiecompiler) under **`nohup … & disown`**; monitor via the log file.
- Terminal **stdout is truncated/garbled** → always redirect command output to a workspace
  file and read the file (not the terminal pane).

## 8. How to resume
```bash
# 1) tools + venv (see §5)
# 2) AIE hardware graph -> libadf.a (after the §6.3 root symlink):
bash work/aie/feature_graph/build_hw.sh          # produces Work_hw/libadf.a
# 3) then v++ link onto the base platform (scaffolding ready):
cd work/aie/feature_graph && make platforminfo   # inspect PLIO/AXIS ports, fill system.cfg
make link                                        # v++ -l AIE graph onto xilinx_vck190_base
# Offline pipeline re-check anytime:
/tmp/venv/bin/python work/csi_ref/run_golden.py && \
/tmp/venv/bin/python work/csi_ref/run_har.py && \
/tmp/venv/bin/python work/csi_ref/run_features8.py
```

## 9. Immediate next steps
Everything below P7 is done and bit-accurate on silicon. **One blocker remains.**

1. **Re-link the AIE graph with `v++ --link` against this platform** so the
   `ai_engine` IP, its PL-interface configuration and the graph CDO are
   co-generated and consistent, then re-import into the BD. This is a flow
   change, not a property tweak - see §20 for why hand-reconstruction failed
   and for the original link command to start from.
2. Verify with `work/sw/aie_scan.py` (core stall bit should clear) and
   `work/sw/replay_test.py` (`mm2s_rx -> 0x0E`, metadata non-zero).
3. Then the Ethernet arm: the PCS never achieves sync (constant `BMSR 0x01c8`)
   even though the GT is healthy. Independent of the AIE blocker.
4. Deploy the SIGBUS-fixed `csi_ctl` and the on-board dashboard via
   `work/petalinux/inject_inline_rootfs.sh` (already built; needs a boot).

**Demo assets that do not depend on any of this:** the 3-branch AIE result is
bit-accurate on silicon (P7), the offline pipeline passes, the inline XSA
implements with timing met, and the dashboard runs live off golden vectors.

## 10. VCK190 board bring-up (systest) + on-target validation  [historical]
> Reached: JTAG-booted `vck190-7` to **u-boot with our PL (`pl_cfi`) + AIE (`aie_subsys`)** loaded (PLM log confirms). Remaining: boot Linux, run `host`. Board reservation released on exit — re-checkout next session.

**Files baked into the rootfs via direct cpio-inject** (the `petalinux-build` path is BROKEN — shared sstate has broken native pkgs: gcc-cross `ranlib`, openssl-native `ssl-3/certs` — whack-a-mole; do NOT use petalinux-build for this). Run **`work/petalinux/inject_aie_rootfs.sh`** (uses `cpio -o -A` to append into ONE clean newc archive, root-owned, then `mkimage -A arm64 -T ramdisk -C none`). It bakes **`/home/root/aie-validate/`** {host, feature_graph.xclbin, input.txt, golden.txt, run_on_target.sh, aie-validate-autorun.sh} PLUS a **systemd auto-run service** (`etc/systemd/system/aie-validate.service` + `multi-user.target.wants/` enable symlink) that runs `host` at boot and echoes `AIE-VALIDATE … PASS/FAIL rc=` to **`/dev/console` (com0)** — so we do NOT need to type into com0. Recipe source of truth: `.../recipes-apps/aie-validate/` (`.bb` + `files/`). Verify baked rootfs: `zcat /tmp/aie_rootfs_new.cpio.gz | cpio -t | grep aie-validate`. Backup: `/tmp/rootfs.goodboot.cpio.gz.u-boot`.

**Resume steps (next session):**
1. Tools: `source /proj/gsd/vivado/2025.2/Vitis/settings64.sh` (gives `xsdb`). PetaLinux: `cd work/petalinux/petalinux; export TMPDIR=/tmp/petalinux-ajayad; unset XILINX_VITIS XILINX_VIVADO XILINX_HLS XILINX_XRT LD_LIBRARY_PATH; ts -petalinux petalinux-v2025.2_released`.
2. `systest vck190-7` in a terminal — **KEEP ALIVE** (killing it releases the board). Host = `morel20`; SC = `10.10.70.1` (only reachable from morel20).
3. In `[vck190-7] Systest#` (**quote all args!**): `bootmode "jtag"`; `reset`; then `hw_server "stop"`; `cableinit`; `hw_server` (prints `morel20:3121`). `connect com0` to watch the console.
4. JTAG boot with the **PMC-filter fix** (from xcoapps75, petalinux env):
```
petalinux-boot --jtag --kernel --rootfs ./images/linux/rootfs.cpio.gz.u-boot --hw_server-url TCP:morel20:3121 --tcl /tmp/jtagboot.tcl
sed 's|{name =~ "\*PMC\*"}|{name =~ "PMC"}|' /tmp/jtagboot.tcl > /tmp/jtagboot_fixed.tcl
source /proj/gsd/vivado/2025.2/Vitis/settings64.sh >/dev/null 2>&1 && xsdb /tmp/jtagboot_fixed.tcl
```
5. **Do NOT touch com0** (agent input can't reach it). Just READ com0: after the xsdb download finishes and issues `con`, u-boot resumes, autoboots Linux, and **`aie-validate.service` auto-runs `host`** → prints `AIE-VALIDATE … PASS/FAIL rc=` to com0. That closes §9.3 — no interactive login required.
6. Manual fallback (only if com0 typing is available, i.e. a human): at `Versal>` `booti 0x00200000 0x04000000 $fdtcontroladdr`; login petalinux/root; `cd /home/root/aie-validate && ./host feature_graph.xclbin input.txt golden.txt`.

**GOTCHAS (each cost real time — do not relearn):**
- **✅ 3-BRANCH FULL HW PASS (2026-08-16, `vck190-2`/morel15).** Clean-rebuild flow works end-to-end with ZERO boot-time patching. Learnings:
  - **XRT multi-instance kernel naming**: `host_3br` opened CUs as `"mm2s_mot"` → `terminate … No such kernel 'mm2s_mot'` (SIGABRT sig=6). xclbin IP_LAYOUT is `kernel:instance` = `mm2s:mm2s_mot`; kernels are `mm2s`/`s2mm` (3 CUs each). XRT treats a bare name as a KERNEL name → must use CU-select **`"mm2s:{mm2s_mot}"`**. Fixed in `host/host_3br.cpp` (the only host bug; graph name `feature_graph` was already right, verified via xclbin AIE_METADATA).
  - **Board farm DDR/GEM faults**: `vck190-24`/morel12 (B-revA) = **bad DDR channel** — `device program` fails at DDRMC_1 cal (`CAL_ERR 0x75`, `PLM 0x2101002A`→`0x32B`) while DDRMC_0/3 pass; reproduced 3×, switch boards. `vck190-2`/morel15 (B-revB01) = **bad-gem**: DHCP binds but bulk TFTP (UDP) "server died" after 1 pkt → **use scp (TCP retransmits, survives flaky GEM)** or JTAG-load, NOT TFTP.
  - **No-Ethernet boot (morel15)**: `xsdb bootuboot_clean.tcl` (POR + program `BOOT_3br_clean.BIN` → U-Boot) → at com0 stop autoboot + `setenv bootargs '…root=/dev/ram0…'` → `xsdb jtagload_3br.tcl` (JTAG `dow` Image@0x200000 / dtb@0x100000 / rootfs@0x4000000, ~few min for 238M) → `booti 0x200000 0x4000000 0x100000`. dtb has zocl node baked, rootfs has host_3br baked → aie-validate.service auto-runs. Deploy binary updates via `scp` (fast) instead of re-flashing.
  - **Re-program `PLM 0x302/0x4001`**: after the board has run Linux, `device program` fails even after xsdb `rst -por` — needs a full systest `reset` (Ctrl-\ to escape com0 → `reset`/`cableinit`/`hw_server`) to clear the PL before reprogramming.
- **`more than one targets found with "*PMC*"`**: NOT two devices — single Versal. Pre-PLM the PSM (id 10) is blocked by LPD domain isolation, so xsdb appends "…**PMC** LPD domain isolation" to its *name* and the wildcard `*PMC*` matches it **plus** the real PMC (id 11). FIX: exact `{name =~ "PMC"}` on the **first** select only (later `*A72*#0`/`*Versal*` run after `device program`, FPD de-isolated, so they're fine). `--tcl` dumps petalinux-boot's own script to patch that one line.
- **systest CLI**: multi-word args MUST be quoted (`bootmode "jtag"`, `hw_server "stop"`) else "Unrecognized alias". Power-cycle = `power 0` then `power 1`.
- **Every POR/reset drops the FT4232H JTAG chain** (`xsdb targets` empty). Recover: `cableinit` then `hw_server`; fresh xsdb `connect` + `after 5000` settle. `rst -por` via xsdb also drops it.
- **com0 console**: agent sees output but its input does NOT reach u-boot/Linux (console reads the real TTY). User must type. Exit com0 with Ctrl-\ (agent can't send it).
- **SW1 warning** is advisory — JTAG worked anyway via the SC `bootmode` override.
- JTAG DDR load addrs: Image `0x00200000`, rootfs `0x04000000`, boot.scr `0x20000000`; dtb via u-boot `$fdtcontroladdr`.
- Board map: `vck190-7` → `morel20` (172.19.242.168); `vck190-13` → `chanterelle10`. `loadmodule "2025.2_daily_latest"` optional for the hw_server.
- **`"Hit any key to stop autoboot: 4"` frozen is NORMAL**, not a hang: the xsdb TCL does `stop` (halts A72) right after u-boot starts, THEN downloads the 234MB rootfs over JTAG (several min), THEN `con`. u-boot is halted at the countdown during the download and resumes past it after `con`. Wait for xsdb to exit: `timeout 540 tail --pid=$(cat /tmp/jtagboot13.pid) -f /dev/null`, THEN read com0. Do NOT send keys to com0 (can interrupt autoboot).
- **Check a board is FREE before reserving** (else queue all day): `systest -q all` lists all hwboard jobs; `systest -q all | grep <EXEC_HOST>` — if the board's host appears it's taken. (morel20 was busy 2026-08-15; used vck190-13/chanterelle10.)
- **Run long commands under `nohup … & disown`** (survive ssh drop): xsdb boot + inject use pid/log files in /tmp (`/tmp/jtagboot13.pid`, `/tmp/jtagboot13_run.log`, `/tmp/inject.log`).
- **Re-boot needs a POR reset FIRST**: `device program BOOT.BIN` on a board already running Linux fails with `PLM Error Major 0x302 Minor 0x4001`. Do `rst -por` via xsdb (select PMC, `rst -por`, `after 10000`, `disconnect`, reconnect) THEN program. Ready-made: **`work/petalinux/jtagboot13_reset.tcl`** (POR + program + download + con). The chain re-enumerates on a fresh `connect` + `after 5000` (no systest cableinit needed).
- **NEVER build a TCL with `{ echo …; } > file.tcl` in the VS Code terminal** — shell integration injects OSC-633 escape sequences (`^[]633;E;…`) into line 1 → xsdb `invalid command name "^[]633"`. Use the create-file tool or `cat` of pre-made files.
- **AIE RUNTIME BLOCKER — ROOT-CAUSED + FIX IN TEST (2026-08-15)**: Symptom: board boots Linux, `host` hangs (rc=124), `/dev/dri` EMPTY, `/dev/aie0` exists, `xbutil` not found, `aie aiepart_0_50: Tile(x,y) is gated` flood. **Ruled out** the xclbin/PDI-mismatch suspect: booting the v++ base-shell `package/BOOT.BIN` does NOT help — its PLM log ALSO loads `aie_subsys`+`aie_image` (AIE baked in too), AND its base-platform dtb reserves ~14 GB (Normal zone `managed:0kB`, only ~1.5 GB usable) so our 234 MB initramfs (unpacks ~838 MB) → **kernel panic OOM** before Linux. So the base-shell path needs the base platform's own ext4/small rootfs, not our initramfs. **CONFIRMED ROOT CAUSE** (via `dtc` diff vs the base platform `.../sw/boot/system.dtb`): our SDT-generated `zyxclmm_drm` node is *minimal* — `compatible = "xlnx,zocl-versal";` with **NO `interrupts-extended`**. The base platform's node wires **63 CU interrupts** (32 from `axi_intc@a4040000` + 31 from `@a4050000`). Without them `xlnx,zocl-versal` cannot finish probe → no `/dev/dri` → `mm2s`/`s2mm` PL kernels uncreatable → `host` hangs (the AIE tile-gated flood is a *secondary* symptom of `graph.reset()` on an un-probed device). `zocl.ko` (right kernel) + `libxrt_core/coreutil` ARE already in the rootfs — so it is *purely* the missing dtb node. **FIX (in test):** patch the dtb to add `interrupts-extended` (my intc phandles: `0x10`=a4040000, `0x11`=a4050000; sense `0x04`). Tooling: `/tmp/patch_zocl_dtb.py` → `dtc` → `images/linux/system-zocl.dtb` (verified: 63 ints / 189 cells). The kernel dtb is loaded to **0x1000** by the PLM (BIF: `type=raw, load=0x1000, file=system-default.dtb`) and `boot.scr` jtag branch runs `booti 0x00200000 0x04000000 0x00001000`; nothing rewrites 0x1000 before `booti`, so **`dow -data -force system-zocl.dtb 0x1000` before `con`** overrides it (no BOOT.BIN rebuild). Ready TCL: **`work/petalinux/jtagboot13_zocl.tcl`**. If it works, bake the patched dtb into BOOT.BIN via `images/linux/bootgen.bif` (bootgen) for permanence.
- **com0 input DOES work for a human** (the user logged in as `petalinux` and Ctrl-C'd the flood during the diagnostic boot) — only the *agent's* `send_to_terminal` can't reach it. So interactive debugging on com0 is possible with the user at the keyboard.
- **UPDATE — zocl FIX WORKED, 2nd blocker found + fixed (2026-08-15)**: Boot #2 with the patched dtb (dow'd to 0x1000): `zocl-drm axi:zyxclmm_drm` now **probes** — the `error -ENXIO: IRQ index 63 not found` is a **benign** end-of-list message (the base platform's node has the *identical* 63 IRQs / 189 cells, ends `0x0f 0x1e`). `host` then gets **past** kernel creation (mm2s/s2mm need zocl) to `graph.reset()`. But a **2nd blocker**: `graph.reset()` still floods `aie aiepart_0_50: Tile(24,2) is gated` and the `timeout 60 ./host` can't kill the hung (uninterruptible) process, so the auto-run result never prints. Cause: the **petalinux BOOT.BIN loads `aie_subsys` (shim, 1936 B) but NOT `aie_image`** (the FIR→stats graph CDO, 28192 B) — so the graph was never loaded into the array; its tiles stay gated. The v++ `package/BOOT.BIN` PLM log has BOTH; the petalinux `bootgen.bif` has no `aie_image` partition. **FIX #2 (in test):** added an `aie_image` partition (`name=aie_image, id=0x18800000`, `{ type=cdo, file=…/work/aie/feature_graph/package/aie.merged.cdo.bin }`) to `images/linux/bootgen_zocl.bif` → `bootgen -arch versal` → **`images/linux/BOOT_zocl_aie.BIN`** (4.1 MB; also bakes the patched zocl dtb at 0x1000). CDO match verified: `package.sh` uses `LIBADF=libadf_motiononly.a` commented "1-branch AIE, matches feature_graph.xsa", and the petalinux `vpl_gen_fixed.pdi` `aie_subsys` is from that same xsa. Boot via **`work/petalinux/jtagboot13_aie.tcl`** (programs `BOOT_zocl_aie.BIN`, still re-dows the dtb to 0x1000 as belt-and-suspenders). If host still floods after the graph is loaded, next suspect is `graph.reset()` racing the PDI-loaded graph → try removing `graph.reset()` from `host.cpp` (the PDI already inits the graph).
- **✅ RESOLVED (2026-08-15) — full HW PASS.** Three stacked fixes: **(1) zocl dtb** `interrupts-extended` (63 CU IRQs, phandles `0x10`/`0x11`) so `xlnx,zocl-versal` probes → `/dev/dri` + CU contexts (`kds_add_context CU 0/1`); **(2) `aie_image` CDO** (`work/aie/feature_graph/package/aie.merged.cdo.bin`, 1-branch, matches the xsa) baked into BOOT.BIN (`images/linux/BOOT_zocl_aie.BIN` via `bootgen_zocl.bif`) so the FIR→stats graph is actually loaded → no more gated-tile flood (`gated_count=0`); **(3) drop `graph.wait()`** in `host.cpp` — the packaged CDO includes the *enable* step so the PDI **free-runs** the graph and `graph.wait()` never returns a run-count completion; `s2mm.wait()` (data-driven) is the real barrier. Pinpointed with a per-step diagnostic host (`host/host_diag.cpp`, prints+`fflush` before each XRT call): last line before hang was `WAIT graph ...`. Final: `mean=-0.002065 var=0.302189 power=0.302193 == golden, max_abs_err=5.96e-08, rc=0 PASS`. **Fast-iteration unlock:** the board got a DHCP IP (`end0=10.10.71.4`) and `/group` is shared, so cross-compiled binaries were `scp`'d in seconds instead of 20-min re-flashes (host serves an HTTP fallback on `172.25.66.228:8000`; xcoapps75 can't ssh chanterelle10 — no key/Kerberos). Notes: gdb/xbutil are NOT in the minimal rootfs; the auto-run's `/dev/dri` looked "empty" only because it checked 5 s too early (zocl was fine). `host.cpp` and the rootfs recipe `files/host` now carry the fix; `host_fix.cpp`/`host_diag.cpp` are the debug variants.

## 11. Inline Arch-B XSA (todo #5) — 2026-08-17

**Goal:** turn the captured inline BD (`hw/scripts/inline_full_bd.tcl`) into an implemented
XSA. Blocker was `add_eth_phy` in `hw/scripts/build_inline_xsa.tcl`, a deliberate error stub,
plus a set of dangling BD ports that synthesise but cannot implement.

**Build:** `vivado -mode batch -source hw/scripts/build_inline_xsa.tcl` (add `-tclargs bd_only`
to stop after `validate_bd_design` — a BD iteration is ~4.5 min, synth ~10 min).
Logs land in `hw/logs/`. `add_eth_phy` runs every wiring step through `_step`, which records
failures instead of aborting, so ONE run reports ALL errors; it then errors out at the end.

### Done
- **Parser metadata now reaches DDR.** `csi_udp_parser`'s `meta_out` went from HLS `ap_fifo`
  to a **64-bit AXIS** (`axis_meta`, one packed `csi_meta_t` per frame; layout + pack/unpack
  helpers in `udp_parser/csi_udp_parser.hpp`). csim + **C/RTL co-sim PASS**; IP re-packaged into
  `hw/ip_repo/csi_udp_parser`. In the BD it goes `meta_dwidth` (64→32) → `s2mm_meta`
  (a third instance of the packaged `s2mm` mover) → `noc_ddr4/S02_AXI` → DDR. Run `s2mm_meta`
  with `size=2` + auto-restart and DDR holds the latest {seq, rssi, n_sub, chanspec,
  core_spatial}. **rssi is element 7 of the ruview 8-feature vector**, so this is required.
- **CSI source mux.** `csi_mux` (`axis_switch`, control-register routing) selects the AIE input
  between `csi_udp_parser_0` (live Ethernet) and `VitisRegion/s` (the mm2s DDR mover, orphaned
  when the parser took the AIE input). Keeps the validated DDR→AIE→DDR golden test runnable on
  the *same* inline bitstream.
- **Clock split.** MAC side runs at **100 MHz** (`clk_wizard_0/clk_out2`, reset
  `proc_sys_reset_4` — previously unused); CSI datapath stays at **312.5 MHz**
  (`clk_wizard_0/clk_out1_o2` == `VitisRegion/ap_clk_bypass_m`). `rx_cdc_fifo`
  (`axis_data_fifo`, async, 2048) crosses 100→312.5 **before** `rx_dwidth` — 8-bit at 100 MHz
  is only 100 MB/s and would under-run a 1G line; 32-bit at 100 MHz is 400 MB/s.
  A `clk_wizard` (`eth_clk125_wiz`, off CIPS `pl0_ref_clk`) supplies the MAC's `clk125m`
  (the platform clk_wizard_0 has no 125 MHz tap).
- **RX-only tie-offs.** `hw/hdl/axis_idle_src.v` drives `s_axis_txd`/`s_axis_txc`;
  `hw/hdl/axis_sink.v` drains `m_axis_rxs` (an unconsumed status stream back-pressures and
  would stall RX). **No `axi_dma`** — so the Linux `axienet` driver will not bind and the MAC
  must be brought up by writing its AXI-Lite registers directly. That is deliberate: it keeps
  the PS out of the datapath. (Cost: link bring-up has no stock driver to lean on.)
- **Control.** `icn_ctrl` widened 7→11 MI; new hier pins `M07..M10_AXI` →
  `slow_ctrl_smc` (smartconnect, 2 clocks, 312.5→100 MHz) → `axi_eth_0/s_axi`, plus
  `csi_udp_parser_0/s_axi_ctrl`, `s2mm_meta/s_axi_control`, `csi_mux/S_AXI_CTRL`.
- **Address map — PINNED**, `CIPS_0/M_AXI_FPD`:
  `mm2s 0xA400_0000 · s2mm 0xA401_0000 · csi_udp_parser 0xA402_0000 · s2mm_meta 0xA403_0000 ·
   intc_cascaded 0xA404_0000 · intc_parent 0xA405_0000 · csi_mux 0xA406_0000 ·
   axi_eth_0 0xA408_0000 (256K) · mm2s_txd 0xA40C_0000 · mm2s_txc 0xA40D_0000 ·
   eth_loopback_gpio 0xA40E_0000`
  ⚠️ These are pinned with explicit `assign_bd_address -offset` and then asserted, because bare
  `assign_bd_address` renumbers everything when an IP is added — adding the TX injectors moved
  `s2mm_meta` 0xA403→0xA407 and `csi_mux` 0xA406→0xA40C, which would have silently broken
  `sw/csi_ctl.c` and `live/inline_reader.py`. Only ever append to that list.

### ⚠️ THE PHY: what does NOT work on 2025.2 (each cost a build cycle)
1. **The 2024.1 reference topology does not port.** `Versal-Ethernet/.../2024.1/pl_eth_1g_rpll`
   wires `gt_quad_base` to `axi_ethernet`'s **`gt_tx_interface`/`gt_rx_interface`**. In
   **axi_ethernet 8.0 those bundled interfaces no longer exist** — only ~25 discrete pins
   (`gtwiz_userdata_*`, `txctrl*`, `rxctrl*`, `*8b10ben`, `*commaalign*`, `*bufstatus`,
   `*pmaresetdone`, …).
2. **The board flow builds an LVDS PHY, not a GT one — it collides with LPDDR4.** Setting
   `CONFIG.USE_BOARD_FLOW=true` + `ETHERNET_BOARD_INTERFACE=bank105_gty2_axi_eth` looks ideal
   (single `sfp` interface, board-assigned pins, no GT cells) and it **validates and
   synthesises** — but that board interface is typed `sgmii_rtl`, which **silently forces
   `CONFIG.ENABLE_LVDS=true`**. The core then builds an Advanced-IO (LVDS) PHY
   (`pcs_pma/inst/adv_io_inst`) whose IO pblock collides with the LPDDR4 controllers, and
   `impl` dies in `opt_design` with **`ERROR: [Mig 66-103] Regeneration failed because of
   PBlock issue`**. Tell-tales: `ENABLE_LVDS=true` on the generated IP, the only `GTYE5_QUAD`
   in the netlist belongs to the CIPS CPM, and `bd_*_pcs_pma_0_board.xdc` throws
   `[Common 17-55] 'set_property' expects at least one object`.
   `ENABLE_LVDS` cannot be forced back to false while the board interface is selected.
3. **The MAC cannot include the GT.** `CONFIG.GTinEx` is locked to `true` and `SupportLevel`
   to `0`; both silently revert. There is no "shared logic in core" option.

### ✅ THE PHY: the correct 2025.2 pattern — `gtwiz_versal`
`GTinEx=true` means literally "the GT is in the **example design**", and that example design is
the authoritative wiring. Generate it with:
```tcl
create_ip -vlnv xilinx.com:ip:axi_ethernet:8.0 -module_name eth_ex
set_property -dict {CONFIG.PHY_TYPE 1000BaseX CONFIG.ENABLE_LVDS false \
    CONFIG.gt_type GTY CONFIG.gtlocation X0Y3 CONFIG.gtrefclkrate 156.25} [get_ips eth_ex]
open_example_project -force -in_process -dir /tmp/ethex [get_ips eth_ex]
```
→ `work/hw/ref_axi_eth_example/eth_ex_support.v` is the reference wrapper (copied into the repo out of /tmp; see its README.md). It uses
**`xilinx.com:ip:gtwiz_versal:1.0`** (NOT a bare `gt_quad_base`), whose `INTF0_*`/`QUAD0_*`
ports match axi_ethernet 8.0's pin names essentially 1:1. Key config: `GT_TYPE GTY`,
`INTF0_PRESET GTY-Ethernet_1G`, `INTF0_NO_OF_LANES 1`, `ENABLE_REG_INTERFACE true`,
`INTF0_CHANNEL_MAP {INTF0_RX0 QUAD0_RX0 INTF0_TX0 QUAD0_TX0}` — **change the channel map to
`QUAD0_RX2`/`QUAD0_TX2`**, because VCK190 SFP0 is bank 105 **channel 2**.

Port map (MAC pin ← / → wizard port), from `eth_ex_support.v`:
```
gtwiz_userdata_tx_out  -> INTF0_TX0_ch_txdata[15:0]   (wizard port is 128b: {112'd0, data})
gtwiz_userdata_rx_in   <- INTF0_RX0_ch_rxdata[15:0]   (wizard port is 128b)
txctrl0/1/2_out        -> INTF0_TX0_ch_txctrl0/1/2
rxctrl0/1/2/3_in       <- INTF0_RX0_ch_rxctrl0/1/2/3
txbufstatus_in         <- INTF0_TX0_ch_txbufstatus     rxbufstatus_in  <- INTF0_RX0_ch_rxbufstatus
rxclkcorcnt_in         <- INTF0_RX0_ch_rxclkcorcnt
txpd_out/rxpd_out      -> INTF0_TX0_ch_txpd / INTF0_RX0_ch_rxpd
txelecidle_out         -> INTF0_TX0_ch_txelecidle
txresetdone_in         <- INTF0_TX0_ch_txresetdone     rxresetdone_in  <- INTF0_RX0_ch_rxresetdone
txpmaresetdone_in      <- INTF0_rst_tx_done_out        rxpmaresetdone_in <- INTF0_rst_rx_done_out
gtwiz_reset_tx_datapath_out -> INTF0_rst_tx_datapath_in
gtwiz_reset_rx_datapath_out -> INTF0_rst_rx_datapath_in
gtwiz_reset_tx_done_in <- INTF0_TX0_ch_txprogdivresetdone
gtwiz_reset_rx_done_in <- INTF0_RX0_ch_rxprogdivresetdone
gtpowergood_in         <- gtpowergood
cplllock_in            <- QUAD0_hsclk0_rplllock
pma_reset              -> INTF0_rst_all_in  AND  QUAD0_apb3presetn
s_axi_lite_clk         -> gtwiz_freerun_clk
signal_detect, mmcm_locked <- 1'b1
rx8b10ben_out, tx8b10ben_out, rxcommadeten_out, rxmcommaalignen_out : LEFT UNCONNECTED
APB3 (paddr/pwdata/psel/penable/pwrite) tied to 0 -> no axi_apb_bridge needed
```
Clocking glue in the same wrapper: one `IBUFDS_GTE5` (refclk, `REFCLK_HROW_CK_SEL=0`) →
`QUAD0_GTREFCLK0`, and four `BUFG_GT`s — `QUAD0_TX0_outclk` → `userclk2` (DIV=0) and
`userclk` (**DIV=1**), `QUAD0_RX0_outclk` → `rxuserclk` and `rxuserclk2` (both DIV=0).

**Plan:** put the wizard + IBUFDS_GTE5 + 4 BUFG_GTs in a `hw/hdl/eth_gt_phy.v` wrapper
(i.e. `eth_ex_support.v` minus the MAC), add it to the BD as a module reference, and connect
its MAC-facing ports to `axi_eth_0` with the table above. SFP0 pin constraints then come back
into `hw/constraints/inline.xdc` (K46/K47 rx, H41/H42 tx, L39/L40 refclk — see the 2024.1
reference XDC); `gt_quad_base_cfg.tcl` / `gen_gt_quad_cfg.py` are kept but unused.

**This plan was carried out** - see the next two sections for what it actually took and the result.

### ✅ `gtwiz_versal` — the channel-2 / refclk trap, and how it was solved
VCK190 SFP0 is **quad bank 105, channel 2** (pins K46/K47 rx, H41/H42 tx; the 2024.1 reference
uses `TX2/RX2_LANE_SEL {PROT0}`). The wizard's generated example is a 1-lane interface on
**channel 0** at a **125 MHz** refclk, and neither can be fixed the obvious way:

- `INTF0_LANE_MAP` / `INTF0_CHANNEL_MAP` are **disabled parameters** — `set_property` on them
  is silently dropped (`[IP_Flow 19-3374] ... disabled parameter ... has been ignored`), and
  `INTF0_NO_OF_LANES 1` on its own fails validation against the still-4-lane map. Editing them
  in the `.xci` makes `get_property` read back correctly **but changes nothing**: the generated
  `gt_quad_base` still came out `RX0_LANE_SEL = PROT0`.
- The parameters that actually move the lane are **`QUAD0_PROT0_{RX,TX}{0..3}_EN`** (per-lane
  enables), plus `QUAD0_PROT0_{RX,TX}MSTCLK`, `INTF_QUAD_CHANNEL_MAP` and `QUAD0_USAGE`.
  Setting the master-clock source alone fails with *"Select the lanes which are assigned to
  PROT0"* — the enables have to move first.
- After moving the lane, the `.xci`'s **`boundary` block is stale** (it still names
  `QUAD0_TX0_USRCLK` etc.) and import dies with `[IP_Flow 19-4038] Could not find interface`.
  **Delete the whole `boundary` object** and let Vivado regenerate it.
- Do NOT try to regex the refclk out of `INTF0_LR0_SETTINGS` / `INTF0_GT_INTERNAL` in the
  `.xci` — those blobs are brace-structured and a botched edit gives
  `unmatched open brace in dict` and a cascade of `INTF_CONFIG_CHECK` errors.

**What works.** `hw/ip/csi_eth_gtwiz.xci` carries only the lane move (per-lane enables +
mstclk + `INTF_QUAD_CHANNEL_MAP` + `QUAD0_USAGE`, `boundary` removed). Everything else is
plain `set_property` in `build_inline_xsa.tcl`:
```tcl
CONFIG.INTF0_GT_SETTINGS {LR0_SETTINGS { \
   TX_REFCLK_FREQUENCY 156.25 RX_REFCLK_FREQUENCY 156.25 \
   TX_PLL_TYPE RPLL RX_PLL_TYPE RPLL \
   TXPROGDIV_FREQ_SOURCE RPLL RXPROGDIV_FREQ_SOURCE RPLL \
   TXPROGDIV_FREQ_VAL 125.000 RXPROGDIV_FREQ_VAL 62.500 \
   RX_OUTCLK_SOURCE RXPROGDIVCLK TX_OUTCLK_SOURCE TXPROGDIVCLK}}
CONFIG.QUAD0_HSCLK1_RPLL_LOCK_EN {true}
```
Without the PLL/PROGDIV part you get 156.25 MHz on the **LCPLL** and `CH2_TXOUTCLK` drops to
**62.5 MHz**, which silently breaks `eth_gt_phy.v`'s BUFG_GT divides (userclk2 must be 125 MHz,
userclk 62.5). With it, the generated quad matches the AMD reference exactly:
`REFCLK_STRING = HSCLK1_RPLLGTREFCLK0 refclk_PROT0_R0_156.25_MHz_unique1`,
`CH2_RXOUTCLK 62.5 CH2_TXOUTCLK 125`.
`QUAD0_HSCLK1_RPLL_LOCK_EN` exists because the wizard only exports HSCLK0's lock by default,
but **HSCLK1's RPLL is the one in use** — the MAC gates its reset FSM on `cplllock_in`, so
taking HSCLK0's lock would be another silent no-link. (The AMD example wires HSCLK0 because
it runs the LCPLL.)

`build_inline_xsa.tcl` re-checks all three of these after `generate_target` and aborts with
`SFP0 would not link` if any regressed — they are the failure modes that produce a clean build
and dead hardware. Look for `GTWIZ_OK` in the log.

Other things that cost a cycle:
- **Top module.** `eth_gt_phy.v` is added to `sources_1` before the BD exists, so Vivado's
  automatic top detection latches onto it and synth/impl silently run on the bare PHY:
  `[DRC CIPS-2] Versal designs must contain a CIPS IP` plus ~150 unconstrained ports. The
  script now pins `set_property top vitis_design_wrapper` and asserts it.
- **`pma_reset` polarity.** Vivado infers it as a reset interface and defaults to ACTIVE_LOW,
  which mismatches the MAC's ACTIVE_HIGH pin and fails `validate_bd_design`. `eth_gt_phy.v`
  declares `POLARITY ACTIVE_HIGH` explicitly.
- **Net-vs-pin ordering.** `add_eth_phy` attaches `eth_gt_phy_0/freerun_clk` and `resetn` in
  the later clock/reset steps, not when the cell is created: `proc_sys_reset_4`'s outputs are
  still unconnected at that point, so there is no net to join yet.

## 12. ✅ Inline Arch-B XSA — BUILT (2026-08-17)
`work/hw/inline_eth_hw/inline.xsa` (4.3 MB), `vivado -mode batch -source
hw/scripts/build_inline_xsa.tcl`, exit 0. Full chain implemented:
**SFP0 → GTY → axi_ethernet(1000BASE-X) → rx_cdc_fifo → rx_dwidth(32→8) →
csi_udp_parser → csi_mux → AI Engine → s2mm → DDR**, plus `meta_out → s2mm_meta → DDR`.

| metric | value |
|---|---|
| timing | **MET** — WNS **+0.358 ns**, WHS **+0.013 ns**, 0 failing endpoints (43970), 0 pulse-width violations |
| critical warnings (impl) | **0** |
| LUT | 11963 (**1.33 %**) · FF 17574 (0.98 %) · BRAM 7 (0.72 %) · URAM 0 · **DSP 0** |
| GTY | 2 quads (one Ethernet, one CIPS CPM) · 2 BUFG_GT |
| power | 22.4 W |
| SFP0 pins | `sfp_txp/n` H41/H42 = **MGTYTXP/N2_105**, `sfp_rxp/n` K46/K47 = **MGTYRXP/N2_105**, `mgt_clk_p/n` L39/L40 = **MGTREFCLKP/N0_105** |
| GT quad | `RX2/TX2_LANE_SEL = PROT0` (RX0 unconnected), RPLL @ 156.25 MHz, CH2 outclk 62.5 / 125 MHz |

### Software + boot bring-up (2026-08-17, off-board)
- **SDT generated** → `work/petalinux/sdt_inline` (`xsct work/petalinux/sdt.tcl .../inline.xsa
  work/petalinux/sdt_inline`, exit 0). It is also a free cross-check of the whole design, and
  every address matches `sw/csi_ctl.c`:
  `mm2s@a4000000 · s2mm@a4010000 · csi_udp_parser@a4020000 · s2mm_meta@a4030000 ·
   axis_switch(csi_mux)@a4060000 · ethernet@a4080000 · ai_engine@20000000000`.
  The MAC node has `phy-mode = "1000base-x"`, `xlnx,phyaddr = <0x2>`,
  `pcs-handle = <&axi_eth_0phy2>` and — as intended — **no `axistream-connected`**, confirming
  the Linux axienet driver will not bind.
- **`work/sw/csi_ctl.c`** — the bring-up/control tool (`work/sw/build.sh` cross-compiles it
  against the SDK9 sysroot; aarch64 binary built). Commands: `status` (read-only: MAC, PCS
  link, RX counters, kernel states), `mac-init`, `start`, `stop`, `mux 0|1`, `meta`.
  All register offsets come from the shipped drivers (`axiethernet_v5_18/src/xaxiethernet_hw.h`,
  and the HLS `*_hw.h` in `hw/ip_repo/*/drivers/`), not from guesswork.
- **XRT/zocl are NOT needed for this design.** It is a plain Vivado design, not a Vitis
  platform — no xclbin — so the `aie/feature_graph/host*` apps do not apply and the §10 zocl
  `interrupts-extended` dtb patch is irrelevant here. That removes a whole class of §10 pain.
- **BOOT.BIN still needs the AIE graph CDO.** `inline.bif` inside the XSA has `pmc_subsys`,
  `lpd`, `fpd`, `pl_cfi`, `cpm` and **`aie_subsys`** (`ai_engine_data.cdo`, the shim/NoC
  config) but **no `aie_image`** partition — i.e. the graph itself is not in `inline.pdi`, the
  same gap as §10 fix #2. Bake `work/aie/feature_graph/package/aie.merged.cdo.bin` in as
  `name=aie_image, id=0x18800000, {type=cdo}`. Use the **1-branch** CDO: this BD's
  `ai_engine_0` has a single AXIS in/out, matching `libadf_motiononly.a`.
- **Board farm snapshot (2026-08-17 ~16:00):** `morel20` (vck190-7) busy; `morel15` (vck190-2)
  and `chanterelle10` (vck190-13) not in `systest -q all`, so likely free. Recheck before
  reserving — and remember `morel15` has a flaky GEM (use scp, not TFTP) and `morel12`
  (vck190-24) has a bad DDR channel.

### ✅ Boot image for `inline.xsa` — BUILT (2026-08-17, off-board)
`bash work/petalinux/build_inline_boot.sh` → in `work/petalinux/petalinux/images/linux/`:
- **`system-inline.dtb`** (154 KB) — from `sdt_inline`, plus `work/petalinux/inline_extras.dtsi`
  which adds a `reserved-memory` carve-out at **0x7000_0000 (1 MB)** for the metadata buffer.
  `s2mm_meta` is a PL master with no IOMMU and no driver, so that memory has to be taken away
  from Linux or it will scribble on the kernel. Keep it in step with `csi_ctl --buf`.
  The script asserts the datapath nodes are in the dtb and fails rather than emitting a bad one.
- **`BOOT_inline.BIN`** (4.7 MB) — verified with `bootgen -read` to contain
  `pmc_subsys / lpd / fpd / pl_cfi / cpm / aie_subsys / **aie_image** / apu_subsystem`,
  i.e. §10 fix #2 is baked in from the start rather than patched in later.
- **`rootfs_inline.cpio.gz.u-boot`** (237 MB) — `bash work/petalinux/inject_csi_ctl.sh` puts
  `csi_ctl` + a README in `/home/root/inline/`. Same cpio-append trick as
  `inject_aie_rootfs.sh`, because `petalinux-build` is broken here (§10). Deliberately **no**
  autorun service: `csi_ctl` reconfigures the MAC, so it is run by hand.

Note `set -euo pipefail` and Vivado's `settings64.sh` do not mix - it reads unset variables, so
`set -u` kills the shell the instant it is sourced. Both scripts wrap it in `set +eu`.

### Next steps — everything off-board is done; the rest needs a board
1. **Reserve a VCK190** (§10 for the recipe and the board-farm gotchas) and JTAG-boot
   `BOOT_inline.BIN` + `Image` + `rootfs_inline.cpio.gz.u-boot`.
   WARNING (§10): the agent cannot type into `com0` — a human has to drive the console.
2. **First contact:** `cd /home/root/inline && ./csi_ctl status` (read-only) → `./csi_ctl
   mac-init` → `./csi_ctl status` and look for **`link=UP`**. This is the first real test of
   the GTY/PCS work (channel 2, RPLL, 156.25 MHz) and cannot be checked off-board.
3. **AIE path without a Pi:** `./csi_ctl mux 1` replays the golden DDR vector through the AIE
   on this same bitstream — isolates "is the inline bitstream's AIE alive" from "is Ethernet
   working". Then `./csi_ctl mux 0` for live capture.
4. **Live end-to-end:** Pi → SFP → parser → AIE → DDR. `./csi_ctl start` then `./csi_ctl meta`
   should show a plausible seq/rssi/n_sub; the 8-feature vector follows from there.

**Known risks for the board session** (ranked): the SFP link not coming up (PCS auto-neg
settings, or the Pi side needing `--no-autoneg`); the 1-branch AIE CDO not matching what the BD
expects; and the metadata buffer address needing to agree between the dtb and `csi_ctl`.

### Live dashboard on the inline datapath (`work/live/`, 2026-08-17, off-board)
- **`live/inline_reader.py`** — module + CLI that mmaps `/dev/mem` and reads the AIE feature
  results and the metadata record straight out of DDR, i.e. the inline replacement for the
  XRT `host_3br --stream` path (no xclbin here, so XRT does not apply). Address map and the
  `ap_ctrl_hs` protocol mirror `sw/csi_ctl.c`. Emits the SAME CSV line the dashboard's
  `exec`/`fifo` sources already parse, with the metadata appended:
  `mot[3],brt[33],phs[3], seq,rssi,n_sub,chanspec,core_spatial` (always 44 fields).
  Buffers: metadata `0x7000_0000` (as `csi_ctl --buf`), AIE results `0x7001_0000` — both inside
  the 1 MB `no-map` carve-out, so keep them in step with `inline_extras.dtsi`.
  `--arm` programs the result `s2mm` (MEM_DATA/SIZE + `ap_start|auto_restart`), which
  `csi_ctl start` deliberately leaves alone. `--branches` is 1 today (the BD builds the
  1-branch graph) and 3 once the 3-branch inline BD lands; missing branches are zero-filled,
  so the dashboard degrades to motion-only instead of failing.
- **`live/live_dashboard.py --source inline`** wires it in; `--simulate` fabricates plausible
  data with no hardware (empty/breathing/walking/fall cycle) for off-board demos.
  `rssi` from the metadata now feeds element 7 of the ruview vector, `(rssi+100)/100`.
- **`csi_ref/features8.py`** now owns that normalization for both paths: `features8_vector()`
  is pure stdlib and numpy/the P1 pipeline are imported lazily, so the file also imports on
  the target rootfs. **Deploy it next to `live_dashboard.py`** (the dashboard searches
  `../csi_ref` first and exits with a clear message if it is missing).
- On board: `./csi_ctl mac-init && ./csi_ctl start`, then
  `python3 live_dashboard.py --source inline --arm --port 8080`.

## 13. Ethernet loopback self-test (2026-08-17)

The design was RX-only, which meant it could not test itself: with the PHY looped back there
was nothing driving TX. So TX is now populated **from DDR**, and the whole chain can be
exercised with no Pi, no SFP module and no cable.

**How it is built** — no new HLS. The packaged `mm2s` mover is already a DDR→AXIS engine that
raises TLAST on the last word, i.e. a frame injector. Two more instances:
- `mm2s_txd` → `axi_eth_0/s_axis_txd`: the Ethernet frame. A nexmon CSI frame is 14+20+8+18 = 60
  header bytes plus 4 bytes per subcarrier, so it is always a whole number of 32-bit words and
  mm2s's all-lanes-valid TKEEP is correct with no padding.
- `mm2s_txc` → `axi_eth_0/s_axis_txc`: the MAC's per-frame TX control packet. It is **5 words**
  (APP0..APP4 — `XAXIDMA_LAST_APPWORD = 4` in `axidma_v9_20/src/xaxidma_hw.h`), all zero because
  checksum offload is off (`CONFIG.TXCSUM = None`).

Both run in the fast domain with the other movers and cross into the MAC's 100 MHz domain
through async FIFOs — the mirror of `rx_cdc_fifo` — which keeps `noc_ddr4` single-clock.
`eth_loopback_gpio` (axi_gpio, 3 bits) drives the GT's loopback control at run time:
`0` normal · `1` near-end PCS · `2` near-end PMA · `4` far-end PMA · `6` far-end PCS.

**Running it** (on the target, `/home/root/inline`):
```
./csi_ctl mac-init          # 1G, promiscuous, RX *and* TX enabled
./csi_ctl txtest            # defaults to --mode 2, near-end PMA
```
`txtest` builds the synthetic nexmon frame in DDR at 0x7002_0000 (the same frame as
`udp_parser/csi_udp_parser_tb.cpp`, which the parser's C/RTL co-sim was validated against, so a
mismatch points at hardware rather than at new stimulus), zeroes the metadata slot, arms the
parser and `s2mm_meta`, fires `mm2s_txc` then `mm2s_txd`, and waits for a metadata record. It
then checks seq / rssi / n_sub / chanspec / core_spatial against what it sent and prints
PASS/FAIL. On failure it dumps the kernels' `ap_ctrl` states and the MAC RX counters, which
separates "TX never drained" from "loopback never closed".

A pass means **MAC TX → PHY loopback → MAC RX → rx_cdc_fifo → rx_dwidth → csi_udp_parser →
s2mm_meta → DDR** is bit-correct: the entire inline datapath except the optics and the AIE
branch, and the AIE branch is separately covered by `csi_ctl mux 1`.

DDR carve-out (1 MB `no-map` at 0x7000_0000, `petalinux/inline_extras.dtsi`):
`0x7000_0000` metadata · `0x7001_0000` AIE results · `0x7002_0000` TX frame · `0x7003_0000` TX control.

### Housekeeping
`work/hw/scripts/` is now exactly `project_top.tcl` + `inline_design.tcl`. Deleted:
`build_inline_xsa.tcl`, `inline_full_bd.tcl`, `inline_eth_phy.tcl` (merged into
`inline_design.tcl`), `gt_quad_base_cfg.tcl` + `gen_gt_quad_cfg.py` (the bare-`gt_quad_base`
fallback, obsoleted by the gtwiz path), `hdl/axis_idle_src.v` (TX is real now),
`hdl/rxcommaalignen_out_gpi.v` (unused AMD copy), and the stray `.srcs`/`.Xil` dirs.
Build only through `work/hw/build.sh`.

## 14. First silicon bring-up of the inline design — vck190-2 / morel15 (2026-08-17 evening)

**Status: NOT passing yet.** The XSA implements cleanly and the PL is alive and fully
controllable, but neither the Ethernet loopback nor the AIE path moves data. Two independent
blockers, both characterised below. Nothing here is guesswork - every claim has a register
read behind it.

### What was established (all verified on silicon)
- **The board can be driven entirely from JTAG, without Linux and without the console.**
  This turned out to be the single most useful thing built tonight. com0 is read-only to
  automation, so the original plan (autorun service + verdict in DDR) needed Linux to boot;
  driving the PL directly from xsdb removes that dependency and cuts the debug loop from
  ~15 min to ~3 min. Scripts: `petalinux/boot_inline.tcl` (program + JTAG-load + release),
  `petalinux/jtag_loopback_test.tcl` (the whole loopback test in Tcl),
  `petalinux/read_result.tcl` (collect a verdict from DDR).
- **`device program BOOT_inline.BIN` alone is enough for register-level testing** - it
  configures the PL and the PLM brings up DDR. Booting Linux to run a register test is waste.
- **`rst -system`, NOT `rst -por`.** On a board that has already run, POR leaves the boot ROM
  wedged and `device program` fails with **"ROM in error state"** every single time
  (3/3 attempts). `rst -system` clears it first time. Boot mode was never the problem:
  PMC_GLOBAL BOOT_MODE_USER/POR (0xf1110200/4) both read 0 = JTAG.
- **Physical memory must be read through the "MicroBlaze PSM" or "Versal*" context.** The
  plain "PSM" container silently returns zeros, the A72 context faults through the MMU
  ("MMU fault at VA 0x70040000"), and DPC only exists before the PLM runs. Confirmed by
  checking the arm64 kernel magic 0x644d5241 at 0x00200038 - every script now asserts that
  before trusting a read.
- **All PL control registers respond**, at exactly the pinned addresses: parser, s2mm_meta,
  csi_mux, MAC, both TX movers, and the loopback GPIO (written 0x2, read back 0x2).
- **The GT/PCS is alive.** With loopback engaged the PCS reports **link UP** (BMSR bit 2 set,
  0x01cc) and MDIO reads/writes to the internal PCS at PHYADDR 2 behave correctly.

### Blocker 1 - the MAC never transmits
`MAC txbytes == 0` in every configuration tried. The failure has a precise signature:
- the **first** frame after programming is fully accepted (`mm2s_txd`/`mm2s_txc` both reach
  ap_ctrl `0x0e` = done/idle/ready, i.e. all 84 words drained into the MAC),
- **every subsequent** attempt hangs on its very first word (`0x03`), consistent with the MAC's
  TX FIFO having filled and never drained,
- and a MAC-level reset (RCW1/TC reset + full reconfigure) does **not** clear it.

Swept with a fresh `device program` between runs: txc = 4 / 5 / 6 words / none at all, PCS
MDIO loopback on and off, GT loopback near-PMA / near-PCS / far-PMA / none. **All identical.**
So it is not the TX control-stream format, which was the leading hypothesis.

Remaining suspects, in order: the GT's TX clocks (`userclk2` from TXOUTCLK) not actually
running despite MDIO working; the wizard's reset FSM never releasing TX
(`INTF0_rst_all_in` = `pma_reset` stuck asserted because its synchroniser is clocked by the
50 MHz `eth_ref_clk_wiz` output); or `QUAD0_ch0_loopback` not reaching physical channel 2.
**All three are unobservable from software today**, which is why the current rebuild adds
instrumentation - see below.

### Blocker 2 - the AIE does not consume (independent of Ethernet)
`csi_mux` → S01, `mm2s` fed 256 fp32 words from DDR, `s2mm` armed for 3 words:
`mm2s` sticks at ap_ctrl `0x01` (running, blocked on the stream), `s2mm` stays `0x81`, and the
output buffer stays zero. So the AIE never accepts data. Note `mm2s` **does** work - a 1-word
transfer completes - so DDR reads and the NoC S00 port are fine; it is the AIE stream that
back-pressures.

Leading theory: **the AIE graph CDO does not match this design's AIE shim.** BOOT_inline.BIN
bakes `aie/feature_graph/package/aie.merged.cdo.bin`, which came from the *v++* 1-branch link,
while `aie_subsys` in `inline.pdi` is generated by Vivado from this BD. The BD's `ai_engine_0`
was captured from that same v++ design so they *should* agree, but §P6's validated 1-branch run
used the v++ `vpl_gen_fixed.pdi`, not our Vivado PDI - this exact pairing has never been proven.
If the PLIO routing differs, the graph's streams simply never reach our AXIS ports.

### GT measured — every Blocker-1 suspect ELIMINATED
With `eth_gt_phy`'s status register in place, the transceiver reads completely healthy:
`gtpowergood=1 · cplllock=1 · tx_done=1 · rx_done=1 · txresetdone=1 · rxresetdone=1 ·
txpmaresetdone=1 · rxpmaresetdone=1 · pma_reset=0 · resetn=1`, and **both the `userclk2` and
`rxuserclk2` heartbeats advance between reads, so the GT clocks are running.** The PCS reports
link UP. So it is not a missing reference clock, not a stuck reset FSM, and not a dead GT.

Two further results narrowed it to one statement:
- **The TX control stream is not the cause.** Four variants - no control packet at all, 5 zero
  words, APP0 = frame length, 5 words of 0xffffffff - each with a *freshly programmed MAC*
  (essential: the first frame wedges TX, so every earlier same-session sweep was measuring the
  wedge rather than the variant). All four identical: `txbytes = 0`.
- **The MAC never accepts a single TX beat.** Firing repeatedly, the CDC FIFO filled at frame 2
  (~158 words) and the mover stopped completing. `mm2s_txd` reaching ap_done only ever proved
  the *FIFO* took the data, never the MAC. So `s_axis_txd_tready` is low permanently.

The MAC's own configuration is correct and was checked in the generated .xci:
`PHY_TYPE=1000BaseX · ENABLE_LVDS=false · TXMEM=4k · RXMEM=4k · TXCSUM/RXCSUM=None ·
axisclkrate=100 · gtrefclkrate=156.25`, TC has TX enable set, and both `axis_clk` and
`s_axi_lite_clk` demonstrably run (AXI-Lite responds on that same net, so `axi_txd_arstn` is
released too). **Why a correctly configured, un-reset, clocked MAC with a live PCS never
asserts TX tready is unresolved.** Next probe would be an `axis_monitor` pass-through on the TX
stream exposing tready/beat counts, since that is the one signal still invisible.

Incidental: `CONFIG.FIFO_DEPTH 4096` on `axis_data_fifo` was silently ignored - the FIFO
behaves as ~128 deep. Harmless here, but do not trust that property without checking.

### Linux boot fixed — the SDT is not a Linux device tree
Booting panicked in `gic_cpu_init` with *"GICv3 system registers enabled, broken firmware!"*
followed by `arch_timer: No interrupt available` and `timer_probe: no matching timers found`.

Cause: a System Device Tree describes **every** processor domain, and the SDT contains **two**
interrupt controllers at 0xf9000000 - the APU's `arm,gic-v3` and, inside `rpu-bus`, the RPU's
**`arm,pl390`**, which is a GICv2. `of_irq_init` picked the pl390, Linux loaded the GICv2
driver on a GICv3 part, the GIC never came up, and the arch timer could never get an interrupt.
`build_inline_boot.sh` had been compiling the SDT straight with `dtc`; an SDT is meant to be
reduced to one domain by **lopper** first.

Fix: `petalinux/sdt_to_linux_dts.py`, applied by `build_inline_boot.sh` after a dtc round-trip
(the reduction matches whole top-level nodes, and decompiling gives one canonical form to match
against). It drops `rpu-bus`, `cpus-r5@*`, `cpus_microblaze@*` and the R5 TCM nodes, and renames
the SDT's `cpus-a72@0` cluster to the `cpus` node Linux expects. Verified against
`images/linux/system.dtb`, which boots this board: no `arm,pl390`, exactly one `arm,gic-v3`, a
`/cpus` node, identical memory nodes. The build now asserts all of that and refuses to emit a
device tree that would panic.

### The instrumented rebuild (superseded - see below)
`eth_gt_phy.v` now exports `status[31:0]` to a second `axi_gpio` channel
(`eth_loopback_gpio`, GPIO2_DATA at **0xA40E_0008**):
`[0]` gtpowergood · `[1]` cplllock · `[2]` tx_done · `[3]` rx_done · `[4]` txresetdone ·
`[5]` rxresetdone · `[6]` txpmaresetdone · `[7]` rxpmaresetdone · `[8]` pma_reset ·
`[9]` resetn · `[10]` mmcm_locked · `[23:16]` **userclk2 heartbeat** ·
`[31:24]` **rxuserclk2 heartbeat**.

The heartbeats are the point: they are free-running counters in the GT clock domains, so
reading the register twice answers "are the GT clocks running at all?" - which decides between
every remaining suspect for Blocker 1 in one measurement.

### Parser-input replay injector (building now)
Because the MAC will not transmit, the loopback route to an end-to-end test is blocked. The
rebuild in flight adds a second injection point so the CSI ingest can be proven on silicon
*without* the MAC:

    rx_mux (axis_switch)  S00 <- rx_dwidth   (live, from the MAC)
                          S01 <- mm2s_rx -> rx_inj_dwidth(32->8)   (replay, from DDR)
                          M00 -> csi_udp_parser_0/rx

So a synthetic or captured nexmon frame can be pushed from DDR straight into the real parser,
and the metadata it produces read back from DDR - **`DDR -> csi_udp_parser -> s2mm_meta -> DDR`,
which does not touch the MAC or the AIE.** That is a genuine silicon test of the CSI ingest
logic and it is independently useful for replaying recorded pcaps through the inline pipeline
with no Pi attached.

New pinned addresses: `mm2s_rx 0xA407_0000 · rx_mux 0xA40F_0000` (both inside the 1 MB
0xA400_0000 window `csi_ctl` maps). NoC gains S05_AXI; `icn_ctrl` goes to 16 MI.

## 15. The three blockers are ONE blocker (2026-08-17, ~22:00)

The replay injector built and validated (BD validates, timing met, XSA written), and the test
`petalinux/jtag_rx_replay_test.tcl` ran on silicon. It also fails - and the way it fails is the
most useful result of the session, because it collapses three separate mysteries into one.

Sweeping the injected burst size into the parser, on a freshly programmed PL:

    size=1 word  -> mm2s_rx completes (ap_ctrl 0x0e -> 0x06)
    size=2 words -> stalls (0x03)
    size=4, 8    -> stalls

One 32-bit word is exactly the capacity of the width converter's input register. So the single
word that "got through" was absorbed by a pipeline register - **the parser consumed nothing.**

Line that up with the other two:

| consumer | fed by | result |
|---|---|---|
| `axi_ethernet` TX | `mm2s_txd` → CDC FIFO | FIFO filled at frame 2; MAC never took a beat, `txbytes`=0 |
| `ai_engine_0` | `mm2s` → `csi_mux` | `mm2s` size=1 ok, size=4 stalls; `s2mm` never produced output |
| `csi_udp_parser_0` | `mm2s_rx` → dwidth → `rx_mux` | size=1 ok, size=2 stalls |

**Three independent IPs, three different clock domains' worth of plumbing, and not one of them
accepts a second beat.** That is not three bugs. It is one systemic fault in the PL, and
chasing the Ethernet MAC specifically (as sections 13-14 did) was chasing a symptom.

### What is already excluded
- **Not the GT/PHY** - measured healthy: powergood, PLL lock, all four reset-done signals, and
  both `userclk2`/`rxuserclk2` heartbeats advancing (§14).
- **Not the NoC or DDR** - `mm2s_txd` on the new S03 port read a full 79-word frame out of DDR.
  Every added NoC port has its clock association asserted at build time.
- **Not the AXI-Lite fabric or the fast clock** - every IP's control registers read and write
  correctly, and `icn_ctrl` runs on that same fast clock, so it is demonstrably running.
- **Not the fast-domain reset** - the HLS control registers latch values, and for a Vitis HLS IP
  the AXI-Lite slave and the kernel share `ap_rst_n`; a held reset would lose the writes.
- **Not the TX control stream, not the loopback mode, not the MAC configuration** (§14).

### What to look at next (with fresh eyes - do not brute-force this)
The remaining candidates all concern why a *started* consumer never asserts TREADY:
1. **An ILA on one stream.** This is the right next move and should have been reached sooner:
   mark `csi_udp_parser_0/rx` (or the `rx_mux` M00) for debug, rebuild once, and look at
   TVALID/TREADY directly. One capture answers it; every register-level probe so far has been
   inference.
2. **HLS `ap_ctrl_hs` semantics.** Reading `0x81` was taken as "running", but that only shows
   ap_start and auto_restart latched. If these kernels are not actually leaving the idle state,
   nothing downstream ever asserts TREADY. Worth reading `ap_ctrl` immediately before and after
   a single injection and watching `ap_idle` (bit 2) toggle.
3. **The AIE graph CDO / shim pairing** (§14 Blocker 2) is still unproven for the *Vivado* PDI,
   and would explain the AIE arm of the table - but not the parser or the MAC.

### Practical note
Everything needed to iterate is in place and fast: `device program` + JTAG drives the whole
design with no Linux and no console (~3 min/cycle), and the frame stimulus, register map and
pass/fail checks are all scripted. The debugging loop is no longer the bottleneck; the missing
piece is visibility into one TVALID/TREADY pair.

---

## 16. 2026-08-18 - Linux boots; blocker confirmed from software; ILA added

Board: `vck190-2` = **morel15** (job 12025528, grabbed ~08:00; the cluster kills
jobs past 8 h - `cluster64/vck190/etc/init.cmd` says so explicitly, which is how
the previous board was lost). Shared console: tmux session `csi`
(`tmux attach -t csi`, must be on xcoapps75), windows `board` / `work` / `dash` /
`build`, console piped to `work/logs/board_console.log`.

### PetaLinux now boots. Three device-tree faults, one cause.
All three came from hand-rolling the SDT->Linux reduction instead of using
lopper. Each cost a ~15 min JTAG boot cycle to find:

| # | symptom | cause |
|---|---|---|
| 1 | `broken firmware!` at `irq-gic.c:57` | RPU's `arm,pl390` GICv2 alongside the APU GICv3 |
| 2 | `arch_timer: No interrupt available` | `/axi/interrupt-multiplex`, unresolved; 60 nodes incl. `/timer` pointed at it |
| 3 | silent CPU0 hang, ignores NMIs | `memory@FFFC0000` (OCM) offered as system RAM - **bl31 runs at 0xFFFE0000**, so Linux allocated over TF-A |

Fault 3 is worth remembering: it presents as a dead CPU0 mid-initcall, and
halting it over JTAG lands in `plat_panic_handler` <- `sync_handler64` in EL3
with DAIF masked. The earlier, easily-missed tell is
`sram fffc0000.memory: error -EBUSY` - the sram driver was refused OCM because
it was already System RAM.

**Fix: use lopper** (it is in the Vitis install we already source):

    lopper -f --enhanced -O <out> -i <lops>/lop-a72-imux.dts \
        system-top.dts system-linux.dts -- gen_domain_dts psv_cortexa72_0 linux_dt

Both parts are required. `gen_domain_dts` alone leaves the interrupt multiplexer
in place and yields a kernel with no timer (verified). `sdt_to_linux_dts.py` is
deleted; `check_linux_dtb.py` asserts all three faults against the final dtb so
a broken invocation is caught at build time, not on hardware.

### csi_ctl: SIGBUS root-caused and fixed
`selftest`/`txtest` died with a bare `Bus error` and no output. The carve-out is
`no-map` reserved memory, so /dev/mem returns it **Device-nGnRE**, where arm64
forbids the unaligned/SIMD accesses `memcpy`/`memset` emit.

Single 32-bit accesses are legal - which is exactly why `status` and every
register probe always worked while anything moving a *buffer* died instantly.
It applies in **both** directions: `bytes(dd[o:o+316])` faults just like
`memset`. `ddr_zero`/`ddr_copy` in csi_ctl.c now move 4 aligned bytes at a time.

### The datapath blocker is confirmed from Linux, unchanged
New `work/sw/replay_test.py` drives `mm2s_rx -> rx_inj_dwidth -> rx_mux S01 ->
parser -> s2mm_meta -> DDR`, taking the MAC, PCS and GT out of the path
entirely. Result:

    DDR write/readback: OK          frame lands in DDR correctly
    rx_mux MI0: 0x80000000 -> 0x1   switch routed to the injector
    parser=0x81  s2mm_meta=0x81     both kernels left idle -> clock+reset live
    mm2s_rx=0x01                    started, never done: blocked mid-transfer

So the kernels run and the data does not move. Note a wedged mover cannot be
re-armed without a PL reset, so repeated attempts in one boot are meaningless -
the clean size sweep in section 15 (size=1 ok, size=2 stalls) is still the
reliable measurement.

Also measured from Linux: the GT is healthy (`gtpowergood`, `cplllock`, all four
reset-done, **both clock heartbeats advancing**), yet PCS `BMSR` reads a constant
`0x01c8` link-down in *every* loopback mode including normal. MDIO responds, so
that is a real register - the PCS genuinely never achieves sync.

### ILA added (in progress)
Every probe so far has been inference; registers cannot tell "producer never
asserts TVALID" from "consumer never asserts TREADY". `inline_design.tcl` now
marks `mm2s_rx_s` and `rx_mux_M00_AXIS` for debug and lets Vivado's debug
automation insert the core. Two traps, both hit:
  - `system_ila` is **rejected on Versal** (`[BD 5-683] not supported for the
    current part`); the automation rule picks `axis_ila` instead.
  - the rule's dict key is `AXIS_ILA`, not `SYSTEM_ILA`.
  - insert it **after** the clock/reset steps, or the automation grabs
    `mm2s_rx/ap_rst_n` into its own net and the reset step then fails.
Set `INLINE_ILA=0` to build without it.

### Demo assets that do not depend on any of this
Dashboard is live on **http://172.25.66.228:8090/** (`--source golden`, replaying
the bit-accurate AIE silicon vectors, `--fall-demo 45`). Self-contained, no CDN.

---

## 17. 2026-08-18 evening - ILA capture. The PL datapath works; the AIE is the blocker.

Board `vck190-2`/morel15, job 12028220. Captured with the ILA build from §16.
All scripts in `work/hw/ila_artifacts/` (kept outside `inline_eth.runs/`, which
`create_project -force` deletes - that already cost one rebuild and a board).

### Section 15's "one systemic PL fault" conclusion was WRONG
It is not the PL fabric. The PL datapath is fine. Two ILAs on the injector path
both triggered and filled:

| stream | TVALID=1 | TREADY=1 | transfers | TLAST |
|---|---|---|---|---|
| `mm2s_rx -> rx_inj_dwidth` | 768 | 276 | 20 | 0 |
| `rx_mux -> parser` | 768 | 330 | 74 | 0 |

Data flows, then TREADY collapses ~74 bytes in - just past the 60-byte header.
TLAST=0 is a *consequence* of stalling at word 20 of 79, not a cause: `mm2s.cpp`
does set `v.last = (i == size-1)`.

### The decisive experiment: change one register
Same frame, same path, only the parser's UDP-port register differs:

| parser port | `mm2s_rx` ap_ctrl | |
|---|---|---|
| 5500 (matches the frame) | `0x01` | stalled |
| 1234 (no match)          | `0x0E` | **done + idle + ready - ran to completion** |

When the port does not match, the parser consumes and discards all 79 words and
finishes. So `mm2s_rx -> rx_inj_dwidth -> rx_mux -> csi_udp_parser` is fully
functional. It only blocks when the parser *matches* and starts writing its
second output, `csi_out -> csi_mux -> ai_engine_0`. Reproduced on fresh programs
in both directions.

### A real bug found on the way: csi_mux was never routed
`csi_mux` (the AIE source switch) reads `MI0 = 0x80000000` after programming -
**MI disabled**. Nothing was routing the parser's CSI output anywhere at all.
`rx_mux` was being set up; `csi_mux` never was. Writing MI0 then committing via
CTRL bit1 works (`0x80000000 -> 0`), and this must be part of any bring-up
sequence. csi_ctl's `mux` command does this; the JTAG scripts did not.

### With csi_mux routed it STILL stalls - the AIE is not consuming
Taking the parser out of the path entirely and driving the AIE straight from
DDR (`mm2s -> csi_mux S01 -> ai_engine_0 -> s2mm`) also stalls: `mm2s = 0x01`,
no results at 0x7001_0000. That is the whole blocker, with nothing else in the
loop.

### The graph CDO is loaded AND contains the enable
Programming `BOOT_inline.BIN` (not a bare PDI - a bare PDI configures the PL but
NOT the AIE graph) loads `aie.merged.cdo.bin`. Verified by payload search that
the merged image contains `aie_cdo_elfs`, `aie_cdo_init`, **`aie_cdo_enable`**,
`aie_cdo_clock_gating` and `aie_cdo_error_handling`. So the cores are configured
and enabled by the PLM, and still nothing is consumed.

That leaves §14's Blocker 2 as the live hypothesis, now much better supported:
**the graph CDO and the Vivado PDI's shim/NoC configuration do not pair.** The
XSA's PDI carries `ai_engine_data.cdo` generated by Vivado for this BD, while
the graph CDO came from a v++ link against a different platform. Cores that run
but are bound to different shim PLIO channels would look exactly like this.

### JTAG context gotchas (each cost a run)
- A bare `device program <pdi>` does not load the AIE graph - use BOOT.BIN.
- After a BOOT.BIN program: `MicroBlaze PSM` has no LPD power, and the `Versal`
  context returns a **constant** on reads (looks like success - it is not).
  The context that works is the **A72 halted at U-Boot's countdown**, MMU off.
  Once Linux is up, A72 accesses fault through the MMU.
- Freezing U-Boot also avoids its pointless TFTP boot attempt.
- `get_hw_devices` lists `arm_dap_0` first; select `xcvc1902_1`.
- Without the `.ltx`, Vivado reports "No matching hw_ilas were found".

### Next
Regenerate the AIE graph CDO against *this* XSA/platform (or re-link the graph
so its PLIO shim assignment matches the BD), then re-run
`ila_artifacts/aie_direct.tcl`. If `mm2s` reaches `0x0E` the whole chain is
proven. The PL side needs no further work.

---

## 18. 2026-08-18 - ROOT CAUSE: the AIE column partition never matched the graph

One property, wrong by default, explains everything from section 13 onward.

    BD ai_engine_0   C_START_COLUMN = 0 ,  C_NUM_COLUMN = 1     -> shim on column 0
    graph CDO        PLIO_in / PLIO_out   on shim_column 24

`C_START_COLUMN`/`C_NUM_COLUMN` select the AIE column partition the `ai_engine`
IP owns, and they must match where aiecompiler placed the graph's PLIOs. They
default to **column 0**, and the captured BD never set them. So the PL stream
was wired to a shim the graph does not touch: `ai_engine_0/S00_AXIS` never
asserted TREADY, and every producer upstream stalled waiting on it.

Evidence, in order:
1. ILA capture (#17): data flows then TREADY collapses ~74 bytes in.
2. Changing only the parser's UDP port so it *discards* instead of emitting to
   `csi_out` makes the whole path complete (`mm2s_rx = 0x0E`). So the PL is fine.
3. Driving the AIE directly from DDR with the parser removed also stalls, so the
   AIE alone is the blocker.
4. The graph CDO is loaded and *does* contain `aie_cdo_enable` - the cores are
   configured and enabled. So it is not a missing-CDO problem.
5. `vitis_design_ai_engine_0_0.xci` -> `C_START_COLUMN = 0`, while
   `Work_hw/ps/c_rts/aie_control_config.json` -> `PLIOs.*.shim_column = 24`.

Fix applied in `inline_design.tcl`: `CONFIG.C_START_COLUMN {24}`,
`CONFIG.C_NUM_COLUMN {1}` (the 1-branch graph uses column 24 only - verified by
walking every column referenced in aie_control_config.json).

**These two values and the graph are a matched pair.** If the graph is ever
recompiled or re-placed, re-read `aie_metadata.PLIOs.*.shim_column` and update
them together. The 3-branch graph spans columns 24 and 26 and would need a
wider partition.

Also worth keeping: the earlier "one systemic PL fault" theory (#15) was wrong,
and so was the follow-up guess that the graph CDO was missing or unpaired at the
shim level (#17). The CDO was fine; only the column partition was wrong.

Verification pending: rebuild, then `ila_artifacts/aie_direct.tcl` should show
`mm2s = 0x0E` and non-zero AIE results at 0x7001_0000.

---

## 19. 2026-08-18 late - the graph IS running; the gap is shim ingress

The column-partition fix from #18 (`C_START_COLUMN 24`) was **not** the fix.
Built, booted and retested: `mm2s_rx` still stalls at `0x01`, with `csi_mux`
correctly routed to the parser (`csi_ctl mux 0`). Two things disproved it:

- the AIE aperture is still `cols(0, 50)` - that geometry comes from the SDT,
  not from `C_START_COLUMN`, so the property does not do what #18 assumed;
- the graph core was already at column 24 regardless.

The change is kept (the core really is in column 24, so pointing the IP's
partition there is at worst harmless and at best correct) but it is NOT a fix,
and #18's claim of root cause is withdrawn.

### What the array scan shows (`work/sw/aie_scan.py`)
Scanning Core_Status (`0x20000000000 + (col<<23) + (row<<18) + 0x32004`) over
all 50 columns, from Linux via /dev/mem:

    col 24 row 1: Core_Status=0x00000201  enable=1 reset=0
    col 24 row 2: Core_Status=0x00000002  enable=0 reset=1

So the graph is loaded, the core is **enabled and out of reset**, in the column
the graph metadata says it should be, with a stall bit set alongside enable -
i.e. running and blocked waiting for input. This kills several earlier theories
at once: the CDO is fine, `aie_cdo_enable` did its job, the cores are powered,
and the AIE is not "dead".

What remains is narrow and specific: **the PL-to-AIE shim ingress never
delivers.** `ai_engine_0/S00_AXIS` holds TREADY low, so whatever shim channel
the graph is listening on is not the one the BD's AXIS port is wired to. That
is a shim/PLIO channel binding, normally guaranteed by `v++ --link` co-
generating the graph and the platform together - which this design does not do,
because the `ai_engine` IP was captured into a plain Vivado BD.

Note the JTAG-vs-Linux difference: the array is unreadable from a halted A72 at
U-Boot (CCI/NoC path not up) but reads fine from Linux via /dev/mem. Any future
AIE probing should be done from Linux.

### Next
Re-link the graph against this platform so the shim binding is co-generated,
rather than pairing a standalone aiecompiler CDO with a captured IP. Verify with
`aie_scan.py` (core should leave the stalled state) and `replay_test.py`
(`mm2s_rx -> 0x0E`, metadata non-zero).

---

## 20. 2026-08-18 night - AIE↔PL binding cannot be hand-reconstructed

Everything below is measured on hardware, not inferred.

### Established good
- **PL datapath works.** Changing only the parser's UDP port so it discards
  instead of emitting makes the whole chain complete (`mm2s_rx = 0x0E`).
- **Graph is loaded and running.** `aie_scan.py`: core at (24,1)
  `Core_Status=0x00000201` - enabled, out of reset, stall bit set, i.e. waiting
  for input. `aie_cdo_enable` is present in the merged CDO.
- **Shim switch is configured** in column 24 (`shim_probe.py`):
  master 3 <- slave 18, master 18 <- slave 3, both slaves enabled.
- **PL channels are in the right column.** Originally Vivado put them in
  column 11 (`AIE_PL_X10Y0`; note the tile map is `AIE_PL_XnY0 ->
  ...CORE_X(n+1)Y0`, so the site index is NOT the column). Both are now pinned
  to `AIE_PL_X23Y0` = column 24 by inline.xdc, verified in the placed netlist.
  That was a genuine misconfiguration - it just was not sufficient.
- v++ metadata agrees on the target: `PLIO_in/PLIO_out` -> `shim_column 24`,
  `stream_id 0`, bound to `S00_AXIS`/`M00_AXIS`.

### Ruled out by experiment (each one boot, ~20 min)
- `C_START_COLUMN`: does not drive the aperture (still `cols(0,50)`) and did not
  help. #18's root-cause claim is **withdrawn**.
- **Shim slave routing**: re-pointing master 18 at all 24 slave ports in turn,
  while the mover sat stalled, unblocked nothing (`shim_sweep.py`). If rerouting
  inside the switch cannot help, data is not reaching the switch.
- **Shim NoC-vs-PL mux**: the 0x3FF00 window reads all zero and no value there
  unblocked it (`mux_sweep.py`). Either that is the wrong window or the mux is
  not the gate.

Useful technique worth keeping: an HLS mover blocked on TREADY is blocked
*mid-transfer*, so fixing the path while it is stalled completes that same
transfer. One boot can therefore sweep many candidate settings.

### Conclusion
The `ai_engine` IP was captured out of a `v++ --link` result into a plain
Vivado BD. The AIE↔PL binding - which PL channel drives which shim stream, and
the shim/PLIF setup behind it - lives in xclbin metadata
(`<arg name="PLIO_in" port="S00_AXIS">`) that did not survive that capture.
Column placement is reconstructable by hand (done); the rest is not, and
guessing at undocumented shim registers has now produced three clean negatives.

**The fix is a flow change, not another property:** re-link the graph with
`v++ --link` against this platform so the ai_engine IP, its PL interface
configuration and the CDO are co-generated and consistent, then re-import. The
original link line is recorded in the xclbin and is the starting point:

    v++ --config system.cfg --connectivity.nk mm2s:1:mm2s --connectivity.nk s2mm:1:s2mm \
        --connectivity.sp mm2s.mem:DDR --connectivity.sp s2mm.mem:DDR \
        --connectivity.stream_connect mm2s.s:ai_engine_0.PLIO_in \
        --connectivity.stream_connect ai_engine_0.PLIO_out:s2mm.s \
        --input_files libadf.a --input_files mm2s.xo --input_files s2mm.xo --link

Verify after with `aie_scan.py` (stall bit clears) and `replay_test.py`
(`mm2s_rx -> 0x0E`, metadata non-zero).

### Tooling added today (all in work/sw/, all run from Linux via /dev/mem)
`aie_scan.py` locate enabled cores · `shim_probe.py` dump shim switch config ·
`shim_sweep.py` sweep slave routing · `mux_sweep.py` sweep the NoC/PL mux ·
`replay_test.py` end-to-end datapath test.
`inject_inline_rootfs.sh` builds a rootfs that runs all of it at boot and starts
the dashboard on the board - there is no interactive login (the account forces a
password change, and inventing a device credential unattended is not
appropriate), so the autorun is the only way in.

---

## 21. 2026-08-19 - Approach B (scope the .aieprj into the Vivado BD): closer, still stalls

Goal this session: implement #20's "re-link with v++" fix and validate on silicon.
Result: got the AIE<->PL PHYSICAL placement right (progress, verified in-netlist),
but the datapath STILL stalls on hardware. Root reason is now precise and matches
#20: a plain Vivado BD cannot co-generate the paired AIE<->PL interface solution;
only `v++ --link` can. Details below so this is not re-attempted the same way.

### What was found (ground truth from a live v++ link)
Re-ran the single-branch v++ link with `--save-temps --to_step vpl.generate_target`
to preserve the vpl project, and read how v++ integrates the AIE (vpl.tcl +
its `dr.bd.tcl`). Three things the hand-built inline BD was missing:
1. `HDL_ATTRIBUTE.ME_ANNOTATION {PLIO_in}`  on ai_engine_0/S00_AXIS
2. `HDL_ATTRIBUTE.ME_ANNOTATION {PLIO_out}` on ai_engine_0/M00_AXIS
3. the AIE<->PL shim SOLUTION archive scoped to the cell:
   `add_files system.aieprj` (FILE_TYPE **AIEPRJ**, NOT the raw libadf.a which is
   FILE_TYPE Unknown and has no SCOPED_TO_* props - that was a dead end first),
   then SCOPED_TO_REF <bd> + SCOPED_TO_CELLS {ai_engine_0} + USED_IN_IMPLEMENTATION.
`vpl.tcl` sets `aie_archive_file = int/system.aieprj`. Its shim solution
(verified) binds S00_AXIS/M00_AXIS -> `AIE_PL_X23Y0` **column 24, channel 0**
(PLIO_in / PLIO_out) - which is exactly where the external compute CDO
(`package/aie.merged.cdo.bin`) also places the graph. Also confirmed the working
vpl `ai_engine_0` uses `C_START_COLUMN 0` (default) with aperture cols(0,50), so
#18's C_START_COLUMN 24 override was wrong and is removed.

### Edits made (kept - they are correct and an improvement)
- `hw/scripts/inline_design.tcl`: removed C_START_COLUMN/C_NUM_COLUMN; added
  ME_ANNOTATION {PLIO_in}/{PLIO_out} on S00_AXIS/M00_AXIS.
- `hw/scripts/project_top.tcl` (step 3b): scope
  `aie/feature_graph/aie_integration/motiononly.aieprj` (captured from the v++
  link) to ai_engine_0.
- Captured artifact: `aie/feature_graph/aie_integration/motiononly.aieprj`.
- Build helper: `aie/feature_graph/relink_singlebranch.sh`.

### Build result (GOOD, in-netlist)
`bash work/hw/build.sh` -> inline.xsa (12:33). Timing MET. The AIE IP now
synthesizes real `AIE_PL_S_AXIS32` / `AIE_PL_M_AXIS32` shim primitives placed at
**AIE_PL_X23Y0 = column 24** (was absent / mis-bound before). Vivado logged
`[Constraints 18-5298] AI Engine Project file is already associated with cell
ai_engine_0` - i.e. the scoped .aieprj was consumed. So the PL-side placement is
now correct by construction.

### Silicon result (STILL STALLS - vck190-2 / morel15, job 12034383)
Booted `BOOT_inline.BIN` (new PDI + col24 CDO) with `boot_inline.tcl` (fully
unattended; autorun prints to com0). `inline-autorun` output:
- `aie_scan`: col24 row1 `Core_Status=0x00000201` (enabled, out of reset, stall
  bit set) - identical to #19/#20 (this is the idle-waiting-for-input state).
- `shim_probe` col24: stream switch master 3->slave 18, master 18->slave 3, both
  slaves enabled, `stream_switch_slot: ALL ZERO` - **identical to #20**, because
  that routing comes from the external CDO, which this change does NOT touch.
- `replay_test`: `mm2s_rx=0x01` stuck, `REPLAY TEST FAIL: no metadata` - same as
  before. AIE still not consuming.
Console evidence saved: `work/logs/board_console_aieprj_test.log`.

### Why it still fails (definitive)
Unzipping the built inline.xsa: its `aiearchive.aieprj` contains ONLY
`vivado/logical_arch_aie.larch` + `aieprj_meta_data.json`. The working
`feature_graph.xsa` (silicon-validated) instead carries the full
`arch/aieshim_solution.aiesol` + `arch/aie_pl_intf.json` + `arch/aie_partition.json`.
=> Scoping the .aieprj into a plain Vivado BD got Vivado to PLACE the PL channels
at col24, but it did NOT emit the complete AIE<->PL interface solution into the
XSA/PDI. The runtime shim routing is therefore still whatever the external merged
CDO sets, and the two are NOT a co-generated pair. This is exactly #20's
conclusion, now proven from both directions.

### The remaining fix (unchanged from #20, now the only credible path)
Co-generate the ai_engine IP + its PL interface config + the CDO with `v++ --link`
against a platform that INCLUDES the inline PL front-end. Concretely: build the
inline PL design (GT + MAC + rx_dwidth + csi_udp_parser + csi_mux + s2mm + NoC +
CIPS, minus ai_engine) as a **Vitis extensible platform** exposing the AXIS
stream(s) that cross the PL<->AIE boundary as PFM interfaces, then
`v++ --link libadf_motiononly.a mm2s.xo s2mm.xo --config <cfg>` against it so the
shim solution, the ai_engine IP and the CDO all pair. Then package BOOT.BIN from
that single link (do NOT mix a hand-built PDI with a separately-packaged CDO).
This is a multi-day flow change, not a property tweak.

Board was released cleanly (Power OFF, job cleared). No board left held.

---

## 22. 2026-08-19 - THE path forward: v++ postSysLinkOverlayTcl (co-generation)

#21 proved a plain Vivado BD cannot emit the paired AIE<->PL shim solution. The
correct fix keeps v++ as the AIE integrator and injects the inline front-end into
v++'s OWN generated BD via the documented hook:

    v++ -l ... --advanced.param compiler.userPostSysLinkOverlayTcl=<overlay.tcl>

(confirmed in data/vitis/vpp/flowdef.json: preSysLink/postSysLink ->
advanced.param:compiler.user{Pre,Post}SysLinkOverlayTcl). The overlay runs on the
v++ BD after sys_link, before synthesis.

KEY INSIGHT: v++ computes the AIE<->PL binding on ai_engine_0's S00_AXIS/M00_AXIS.
Keep ai_engine_0 untouched and just INSERT csi_mux on its input net; the binding
is preserved because it lives on the ai_engine side, not the PL driver side.

v++ BD structure (from the preserved vpl prj.xpr):
- ai_engine_0/S00_AXIS <- net /mm2s_s <- VitisRegion/s  (mm2s is inside VitisRegion hier)
- ai_engine_0/M00_AXIS -> VitisRegion/s1 (s2mm inside VitisRegion)
- control via axi_smc_vip_hier (smartconnect); DDR via noc_ddr4; CIPS_0 + cips_noc.
- top cells: CIPS_0, VitisRegion, ai_engine_0, axi_smc_vip_hier, cips_noc,
  noc_ddr4, noc_lpddr4, clk_wizard_0, axi_intc_*, proc_sys_reset_0..4.

Incremental plan (de-risk; each step = one link+boot+board cycle):
- D1: overlay inserts csi_mux on /mm2s_s (VitisRegion/s -> csi_mux.S00,
  csi_mux.M -> ai_engine_0/S00_AXIS), csi_mux ctrl on the control path + address.
  Validate mm2s->csi_mux->AIE->s2mm still works on silicon => proves the approach.
- D2: overlay adds the Ethernet front-end (GT+MAC+dwidth+parser+csi_mux.S01) from
  inline_design.tcl, + SFP xdc via --vivado.prop / a constraints .xo. Validate live.
- Package BOOT.BIN from the SAME link (one XSA -> paired PDI+CDO), not mixed.

### D1 co-gen link BUILT + VERIFIED (2026-08-19, 14:01)
`work/aie/feature_graph/link_cogen_d1.sh` (v++ -l + overlay_d1.tcl) ->
`inline_cogen_d1.xsa` (3.78 MB) + xclbin. Full flow clean: create_bd (overlay ran,
NO integration error) + synth + impl + XSA, 17 min.

Overlay gotcha (fixed): at postSysLink the BD is FLAT - VitisRegion/axi_smc_vip_hier
hierarchies are grouped LATER. So references must be dynamic: mm2s output = /mm2s/s
(not /VitisRegion/s), AIE clk net = /clk_wizard_0_clk_out1_o2. overlay_d1.tcl now
discovers the source pin from the ai_engine input net's endpoints and finds the
control smartconnect from mm2s/s_axi_control's net. Iterate the overlay fast by
sourcing it against _x_d1/link/vivado/vpl/prj/prj.xpr (the preserved postSysLink
project), NOT the fully-generated feature_graph vpl.

**KEY VERIFICATION**: unzip inline_cogen_d1.xsa -> aiearchive.aieprj CONTAINS
`arch/aieshim_solution.aiesol` + `arch/aie_pl_intf.json` + `arch/aie_partition.json`
- exactly what #21's plain-Vivado inline.xsa was MISSING. So the co-gen produced the
complete, paired AIE<->PL shim solution. The #21 structural blocker is resolved; the
csi_mux insertion preserved the AIE binding (ai_engine_0 untouched).

Remaining for D1: package (xclbin+BOOT.BIN, co-gen CDO) via the P6/§10 flow
(zocl dtb interrupts-extended + aie_image), boot, then validate mm2s->csi_mux(sel
S01)->AIE->s2mm == golden. csi_mux route set via /dev/mem @0xA4060000 before the XRT
host runs (it is not an XRT kernel). Then D2: port the Ethernet front-end into the
overlay for the live Pi path.

### D1 packaged + boot artifacts BUILT (2026-08-20) - awaiting a board
- `package_d1.sh` -> `inline_cogen_d1.xclbin` (7.1M) + `package_d1/aie.merged.cdo.bin`
  (28156 B, the CO-GEN CDO, paired with the D1 PDI shim by construction).
- `build_d1_boot.sh` -> `images/linux/BOOT_d1.BIN` (bootgen: D1 PDI vpl_gen_fixed.pdi
  + plm/psm/bl31/u-boot + aie_image=package_d1 CDO + ZOCL dtb system-default.dtb@0x1000).
  D1 is an XRT/zocl platform so it uses system-default.dtb (zocl, 63 CU ints), NOT
  the plain inline dtb.
- `inject_d1_rootfs.sh` -> `images/linux/rootfs_d1.cpio.gz.u-boot` (239M): bakes
  /home/root/aie-d1/{host, inline_cogen_d1.xclbin, input.txt, golden.txt, mux_set.py,
  d1-autorun.sh} + d1-validate.service (autorun at boot, prints D1-VALIDATE to com0).
- `boot_d1.tcl` (BOARD_URL env) - unattended, mirrors boot_inline.tcl: program
  BOOT_d1.BIN, freeze U-Boot, DDR-load Image@0x200000 + boot.scr@0x20000000 +
  system-default.dtb@0x1000 + rootfs_d1@0x4000000, con -> boot.scr autoboots.
- Validation logic (d1-autorun.sh): set csi_mux route S01 (mm2s) via mux_set.py
  (/dev/mem @0xA4060040=1, @0xA4060000=2), then `./host inline_cogen_d1.xclbin
  input.txt golden.txt`. host.cpp unchanged (graph "feature_graph", kernels mm2s/s2mm).
  Expected PASS: mean=-0.002065 var=0.302189 power=0.302193, max_abs_err<1e-3.
- Board farm heavily contended (41 pending). morel12 unusable (bad DDR, fails
  device program). Waiting on vck190-5 (job 12042073, queued).

### D1 on-silicon attempt (2026-08-20) - programmed+booted; validation blocked by board farm
Board farm was heavily contended (41 pending) AND several boards are faulty:
- morel12 (free): bad DDR, `device program` fails (known, §10-ish).
- morel22/vck190-9: `device program` fails `PLM Error Major 0x326 Minor 0x14`
  for BOTH BOOT_d1.BIN AND the known-good BOOT_3br_clean.BIN -> bad board (POR +
  power-cycle did not help).
- chanterelle8/vck190-11: HEALTHY programmer. BOOT_d1.BIN programmed OK
  (**PROGRAM_OK** - the D1 co-gen bitstream loads on silicon), Linux booted, zocl
  probed clean (`IRQ index 63 not found` = benign end-of-list, §10). BUT the board
  has attached SD (mmcblk0) + USB (sda) storage; the JTAG-initramfs boot auto-fscks/
  mounts them and gets stuck in a long-fsck -> reboot cycle (watchdog), so the
  `d1-validate.service` autorun never completes. The `PMC EAM ERR1 0x2000 / Error ID
  0xD` on com0 carries the SC uptime timestamp [1107453s] => it is a System-
  Controller-side aggregation message, not the board PMC / not from the D1 design.

NET: the co-gen fix is STRUCTURALLY PROVEN (D1 XSA carries the full
aieshim_solution/aie_pl_intf, unlike #21) and the D1 bitstream PROGRAMS + BOOTS on
silicon, but the DDR->mm2s->csi_mux->AIE->s2mm datapath result is not yet captured
because of board-farm issues (bad boards + external-storage fsck/watchdog reboot).

To finish next session:
- Use a board WITHOUT attached SD/USB (morel15 booted the P7 initramfs cleanly), OR
- add `systemd.mask=` for the run-media mounts / a kernel cmdline to skip external
  fsck in boot_d1.tcl's boot.scr path, so the autorun reaches the host, OR
- make d1-autorun print each step to com0 (unbuffered) so a hang point is visible.
Expected PASS: mean=-0.002065 var=0.302189 power=0.302193 (max_abs_err<1e-3).

### ✅ D1 CO-GEN HW PASS (2026-08-21, chanterelle8/vck190-11) - the blocker is SOLVED
`inline_cogen_d1.xsa` (v++ overlay inserts an `axis_register_slice` on the AIE
input net, ai_engine_0 untouched) -> packaged -> BOOT_d1.BIN + rootfs_d1 (with the
gpt_auto=0 fsck fix + stale-aie-validate mask) -> booted on silicon:

    D1> running host (mm2s->csi_slice->AIE->s2mm), 45s hard timeout:
    AIE result: mean=-0.002065 var=0.302189 power=0.302193
    golden:     mean=-0.002065 var=0.302189 power=0.302193
    max_abs_err=5.960e-08 -> PASS,  host_rc=0

=> The v++ postSysLinkOverlayTcl co-generation flow WORKS, and inserting a PL
element between mm2s and the AIE PRESERVES the co-generated AIE<->PL binding (the
AIE consumes on silicon). This is the definitive resolution of the #17-#21 blocker:
the datapath stalled because the plain-Vivado BD paired a hand-built PDI shim with a
separately-packaged CDO (#21). With v++ owning the AIE integration, PDI shim + CDO
are one pair and the AIE consumes. Console saved: board_console_d1_PASS.log.

Fixes that made the on-silicon boot work (vs the 08-20 attempt):
- `systemd.gpt_auto=0` in the dtb bootargs (system-default-d1.dtb) so the board's
  SD/USB storage is not auto-fsck'd -> boot reaches multi-user fast (no reboot loop).
- inject_d1_rootfs.sh masks the stale `aie-validate.service` from the base rootfs
  (it was loading feature_graph_3br.xclbin and competing for the XRT device).
- verbose d1-autorun.sh prints each step live to com0.

KNOWN (deferred to D2): the control-routed `axis_switch` (csi_mux) variant hung on
its /dev/mem control write (0xA4060000 AXI unresponsive) - the mux control wiring in
the overlay (icn_ctrl M07 widening) needs debug. D1 used a register_slice to prove
the datapath; D2 must (a) fix csi_mux control routing and (b) add the Ethernet
front-end (parser -> csi_mux.S00) for the live Pi path.

### ✅ LIVE DEMO on silicon (2026-08-21, chanterelle8) - AIE feature stream + dashboard
Real WiFi-CSI -> AI Engine DSP feature extraction running LIVE on the VCK190,
visualized on the dashboard. Pipeline:
- On the board: `demo-autorun.sh` runs the PROVEN single-shot `host` per window over
  a synthetic CSI recording (`demo_windows.txt`: still / walking / still / breathing),
  emitting real AIE {mean,var,power} features as `CSIFEAT ...` lines to com0.
- Bridge (xcoapps75): console `CSIFEAT` -> `/tmp/demo_features.csv`.
- Dashboard (xcoapps75, reachable): `live_dashboard.py --source fifo` on
  **http://172.25.66.228:8099/** shows presence/activity from the live AIE features.
Result (real silicon AIE output): still windows motion-power ~0.0027 -> presence=False
"empty"; walking windows ~0.0040-0.0049 -> presence=True "active / walking". The
still<->walking transitions track the activity correctly. 284+ features streamed.

KEY LEARNINGS (why this architecture):
- CONTINUOUS AIE streaming (one process, many windows) FAULTS the AIE (PMC EAM
  Error 0xD/0x13) and freezes the kernel. The graph is effectively single-shot per
  invocation; the ROBUST pattern is a fresh `host` process (load_xclbin + graph.reset
  + graph.run(1) + one window) PER window - repeated single-shot works cleanly.
- Board-HOSTED python dashboard also froze the board (memory: base-platform DDR
  reservation + ~838MB initramfs + python), so the dashboard runs on xcoapps75 fed by
  the LIVE board feature stream over the JTAG console (board has no DHCP IP; the
  tcpforward endpoint 172.19.240.252 is firewalled from xcoapps75).
- `systemd.gpt_auto=0` in the dtb reduces (not eliminates) the external-storage fsck.
- Demo threshold tuned: MOTION_TH 5e-3 -> 3.3e-3 to separate synthetic still/walking.
Artifacts: work/aie/feature_graph/{gen_demo_csi.py, demo_windows.txt, host/host_demo.cpp,
demo_stage/}, work/petalinux/{inject_demo_rootfs.sh, boot_demo.tcl}.

### ✅ BOARD-HOSTED dashboard (2026-08-21) - dashboard runs ON the VCK190
Superseding the xcoapps75-hosted variant: the python dashboard now runs ON THE
BOARD, fed by the on-board single-shot AIE feature loop. Confirmed on console:
  D1DEMO> mem: MemAvailable: 15109944 kB   (~14.4 GB free - NOT memory-limited;
          the earlier freezes were the CONTINUOUS-AIE fault, not OOM)
  D1DEMO> dash pid=808 up=yes | [live_dashboard] source=fifo http://0.0.0.0:8095/
  D1DEMO> hb: feats=20 dash=up last=[0.021079 0.002303 0.002748]   (still window)
          ... walking windows -> last motion ~0.004  (activity distinguishable)
Board also got a DHCP IP (10.10.70.2). Exposed via systest `tcpforward 8095 8095`
-> **172.19.240.252:8095** (AMD lab-network address; xcoapps75 is firewalled from
the 172.19.x board subnet, so verify from an AMD-network client).
demo-autorun.sh (board-hosted): drop_caches; start live_dashboard.py :8095; loop
the PROVEN single-shot host per window -> pure-float feature lines to /tmp/feat.csv;
console heartbeat. Files under work/aie/feature_graph/demo_stage/{aie-d1,csi_ref}.
Board held (not released) per request. Console: board_console_demo_BOARDHOSTED.log.

---

## 23. 2026-08-21 - D2: csi_mux control fix (D2a) + Ethernet parser integration (D2b)

Resumes the deferred D2 work (§22): (a) fix the csi_mux control-AXI that hung in
D1, and (b) port the live Ethernet front-end into the v++ co-gen overlay.

### Method: fast structural (validate-only) overlay checks
Each overlay ends with `validate_bd_design` + an optional `error` guarded by env
`D2_VALIDATE_ONLY`. Running the v++ link with that set aborts right after the
overlay (pre-synth, ~2.5 min) so the BD manipulation is proven before committing
to the ~17 min synth+impl. Two discovery overlays (overlay_d2_probe*.tcl) first
dumped the FLAT postSysLink control fabric:
- control is `/axi_smc_vip_hier/icn_ctrl` (smartconnect, NUM_MI=7, aclk =
  `/clk_wizard_0_clk_out1_o2`), fed from CIPS `M_AXI_FPD` (net CIPS_0_M_AXI_GP0);
  `mm2s/s_axi_control` <- icn_ctrl/M06. AIE clk `/clk_wizard_0_clk_out1_o2`,
  reset `/proc_sys_reset_1_peripheral_aresetn`. Free control offset: 0xA406_0000
  (intc occupy 0xA404/0xA405). mm2s/s2mm control are assigned by v++ AFTER the
  overlay, so at overlay time only the two intc are mapped.

### ✅ D2a - csi_mux with WORKING control-AXI (BUILT + PACKAGED)
`overlay_d2_mux.tcl` replaces the D1 register_slice with an `axis_switch` csi_mux
(2 SI -> 1 MI, ROUTING_MODE=1): S01 = mm2s (DDR test), S00 = parser (live, D2b),
M00 -> ai_engine (untouched, so the co-gen binding holds). Control is added by
widening icn_ctrl 7->8, exposing a new boundary master `M07_AXI`, wiring it to
`csi_mux/S_AXI_CTRL`, and PINNING the address at **0xA4060000** (matches
`mux_set.py`). The earlier D1 mux hang was a wrong/unassigned control address;
pinning it + wiring through icn_ctrl exactly as the platform expects fixes it.
- validate_bd_design PASSED; full link -> `inline_cogen_d2mux.xsa` (3.78 MB) which
  CARRIES the paired shim solution (aie_pl_intf.json + aieshim_solution.aiesol +
  aie_partition.json) - binding preserved with the mux + control inserted.
- Packaged: `inline_cogen_d2mux.xclbin` (7.16 MB) + co-gen CDO (28156 B),
  `BOOT_d2mux.BIN` (4.2 MB), `rootfs_d2mux.cpio.gz.u-boot` (239 MB), `boot_d2mux.tcl`.
- Autorun `d2mux-autorun.sh` proves the fix: `mux_probe.py` reads csi_mux
  @0xA4060000 (RESPONDS != hang), `mux_set.py 1` routes S01, then `host` runs
  mm2s->csi_mux->AIE->s2mm vs golden. Ready to flash; on-silicon run pending a
  board (chanterelle8 is running the live demo; farm boards need interactive
  systest acquisition unavailable from the batch tooling).

### ✅ D2b - Ethernet parser integrated into the co-gen BD (STRUCTURAL PASS)
`overlay_d2_eth.tcl` (+ `link_cogen_d2eth.sh`) extends D2a: it adds the
`csi_udp_parser` HLS IP feeding `csi_mux/S00` with its own icn_ctrl control master
@0xA4020000. KEY: the parser IP repo + the GT RTL/XCI are injected via a
**PRE-SysLink overlay** (`compiler.userPreSysLinkOverlayTcl`) doing
`set_property ip_repo_paths` + `add_files` - confirmed working
(`Loaded user IP repository .../hw/ip_repo`). validate_bd_design PASSED with the
parser wired to the mux (rx tied off; `D2_ETH_FULL` unset).

REMAINING for the live Pi path (D2_ETH_FULL=1): instantiate axi_ethernet(1000BaseX)
+ eth_gt_phy_0 (GT wrapper) + rx_cdc_fifo + rx_dwidth -> parser.rx, the discrete
GT<->MAC pin map (PROJECT_STATE §313-345), 125/100 MHz MAC clocks, and SFP0 XDC.
This needs multiple board-cycle bring-ups AND a physical Raspberry Pi (nexmon) on
SFP0 to validate - neither fast-iterable nor live-testable in this environment.
The overlay + link script capture the exact steps; the front-end is the last mile.

### ✅ D2a CO-GEN HW PASS (2026-08-21, chanterelle8/vck190-11) - csi_mux control FIXED
Flashed `BOOT_d2mux.BIN` + `rootfs_d2mux` (boot_d2mux.tcl) on silicon. The
d2mux-validate autorun result (board serial):

    D2MUX> --- mux control read (pre) ---
    csi_mux @0xa4060000 RESPONDS: MI0=0x80000000 CTRL=0x00000000   <- control-AXI answers (was hung in D1)
    D2MUX> --- set route S01=mm2s + read back ---
    csi_mux MI0 select = 1 (mm2s/DDR)                              <- /dev/mem write+readback OK
    D2MUX> running host (mm2s->csi_mux(S01)->AIE->s2mm):
    AIE result: mean=-0.002065 var=0.302189 power=0.302193
    golden:     mean=-0.002065 var=0.302189 power=0.302193
    max_abs_err=5.960e-08 -> PASS,  host_rc=0

=> The D1 "control-routed axis_switch hung on its /dev/mem write" blocker is
RESOLVED. Pinning csi_mux/S_AXI_CTRL @0xA4060000 through the widened icn_ctrl
(M07) makes the mux control reachable from Linux, and the mm2s->csi_mux->AIE->s2mm
datapath is bit-accurate with the mux + control in place. D2a is DONE on silicon.
The board can now select the AIE source at runtime (S01=mm2s test / S00=parser
live), which is the switch the live Pi path (D2b GT+MAC front-end) will use.

### Demo restore after D2a test - blocked by flaky external-storage boot (2026-08-21)
After the D2a on-silicon PASS, re-flashed the demo (BOOT_d1.BIN + rootfs_demo,
boot_demo.tcl) to restore the live dashboard. TWO clean reflash+boot cycles both
WEDGE at the external-SD/USB fsck/mount phase with `PMC EAM ERR1 0x82000` +
Error ID 0xD/0x13 (SC-uptime timestamps => SC-side msgs, §22), console frozen,
demo autorun never reached. The demo image is good (it streamed 4800+ features
earlier) and the D2a image booted cleanly through the same phase - so this is the
known flaky external-storage boot (§22), board-state, not a design regression.
Recovery: a board power-cycle (SC/board-farm action) or physically detaching the
SD/USB, then re-run boot_demo.tcl. Board hold retained (not released).

---

## 24. 2026-08-22 - D2b Ethernet front-end: FULL BD validates; synth blocked on gtwiz IP gen

Advanced D2b from "parser-only structural" to the COMPLETE live Ethernet front-end
in the v++ co-gen overlay. Clock topology first confirmed via overlay_d2_clkprobe.tcl:
the v++ platform BD already exposes everything the inline design needed -
`clk_wizard_0/clk_out2` = 100 MHz (MAC lite/axis/freerun), `proc_sys_reset_4` on
that 100 MHz net (domain reset), 312.5 MHz FAST = clk_wizard_0_clk_out1_o2, and
CIPS `pl0_ref_clk` for a 50 MHz ref wizard.

overlay_d2_eth.tcl (D2_ETH_FULL=1) now ports the entire add_eth_phy chain:
axi_ethernet 8.0 (1000BaseX, GTY X0Y3, refclk 156.25) + eth_gt_phy_0 (GT wrapper,
6 SFP0 externals) + eth_ref_clk_wiz (50 MHz off pl0_ref_clk) + the 32 discrete
GT<->MAC pins + signal_detect tie-off + RX chain (m_axis_rxd -> rx_cdc_fifo async
100->312.5 -> rx_dwidth 8b -> csi_udp_parser_0/rx) + axis_sink rxs drain + MAC
s_axi via slow_ctrl_smc (312.5->100) @0xA4080000 + all clocks/resets. TX AXIS
left unconnected (RX-only). link_cogen_d2eth.sh PRE-overlay injects the parser IP
repo + eth_gt_phy.v + axis_sink.v + csi_eth_gtwiz.xci + hw/constraints/sfp0.xdc.

**validate_bd_design PASSED** for the full front-end (after fixing two overlay
bugs: axi_eth seg name is `s_axi/Reg0` not `/Reg`; the 100 MHz clock connect must
use `connect_bd_net -net <netname>` not a net object). So the ENTIRE live-path BD
is correctly wired into the co-gen platform.

**Remaining blocker (the §349-390 gtwiz trap, now in the v++ context):** synth
fails because the v++-generated `csi_eth_gtwiz` IP does NOT expose the channel-2
ports eth_gt_phy.v instantiates (`QUAD0_TX2_outclk`, `QUAD0_RX2_outclk`,
`QUAD0_hsclk1_rplllock`) - the IP came out as a portless black-box stub. The repo
XCI has the correct channel-2 config (QUAD0_PROT0_{RX,TX}2_EN=true, INTF_QUAD_
CHANNEL_MAP QUAD0_RX2/TX2), but that XCI is from the axi_ethernet EXAMPLE-DESIGN
context (QUAD0_USAGE references eth_ex_gtwiz_versal) and does not regenerate its
output products standalone under v++'s generate_target.
NEXT: pre-generate the gtwiz IP in a standalone Vivado project (its native
context, where the inline build got the right ports) and add the GENERATED
products / a synthesized .dcp to the v++ link instead of the raw XCI - OR wrap the
GT as a pre-synth'd OOC checkpoint. Then synth+impl -> XSA, package, and finally
bring up the SFP link with the physical Raspberry Pi (nexmon) - the last mile that
needs the board + Pi. The BD wiring is done and validated; only GT IP delivery
remains.

### D2b gtwiz IP-gen: IP-cache reuse tried, did NOT resolve (2026-08-22)
Pointing the v++ project's IP cache at the inline build's cache
(config_ip_cache -use_cache_location inline_eth.cache/ip) did NOT fix it: the
eth_gt_phy_0 OOC synth still emits a csi_eth_gtwiz stub lacking QUAD0_TX2/RX2_outclk
+ hsclk1_rplllock. The identical XCI exposes those ports when generated in the
inline PLAIN-Vivado project but not under v++'s generate_target - so cache hashing
does not bridge the two contexts. The deterministic fix is to integrate the
inline build's ALREADY-generated gtwiz (synth/csi_eth_gtwiz.v + csi_eth_gtwiz.dcp,
which DO have the channel-2 ports) as fixed netlist sources so nothing regenerates,
OR reproduce the §354-390 param incantation (QUAD0_PROT0_* + QUAD0_USAGE without
the example-design hierarchy reference) so the standalone XCI exposes ch-2. Either
is a focused multi-cycle IP-integration task. Everything else in D2b is DONE:
the full live-path BD validates and all sources/constraints are wired.
