# PROJECT STATE — VCK190 WiFi‑CSI Human Activity Recognition (thesis)

> Portable handoff/memory file. Lives in the workspace (`/group/...`) so it is
> available from any machine. Companion to [plan.md](plan.md). Last updated after
> migrating to a new build host (`xcoapps75`, Ubuntu 24.04) that clears the AIE
> hardware‑compile blockers — see §6.

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
| **P2** inline UDP/CSI parser | ✅ | `work/udp_parser` HLS: C-sim + **C/RTL co-sim PASS**, IP exported (`csi_udp_parser_prj/sol1/impl/export.zip`) |
| **P4** PetaLinux (SDT flow) | ✅ | SDT from XSA via `xsct sdt.tcl` (board `versal-vck190-reva-x-ebm-01-reva`); `petalinux-config` + `petalinux-build` done → `images/linux/` (Image 31M, plm/psmfw/bl31 elf, rootfs.ext4, system.dtb, boot.scr). sysroot/BOOT.BIN pending |
| **P3** inline BD (parser+AIE) | ✅ | hand-captured IPI design `work/hw/scripts/inline_csi_bd.tcl` (1198 lines): `csi_udp_parser` → `ai_engine` (feature graph) → `s2mm` → DDR on CIPS+NoC; **`validate_bd_design` PASS**; parser `rx`/`meta`/`ctrl` external (for PL Eth MAC) |
| **P5** inline impl QoR | ✅ | routed `impl_1` (0 errors, 0 crit-warn): datapath **312.5 MHz timing MET** (WNS +0.586 / WHS +0.014 ns); **0.62% LUT** (5551), 0.37% FF, **0 DSP**, 0.5 BRAM; 23.0 W; `vitis_design_wrapper.pdi` generated — parser placed&routed in the AIE path |
| **P2/P3** full inline BD | ✅ | complete Arch-B chain `axi_ethernet → rx_dwidth(32→8) → csi_udp_parser → ai_engine → s2mm → DDR` on CIPS+NoC; **`validate_bd_design` PASS**; captured `hw/scripts/inline_full_bd.tcl` (1313 lines); MAC GMII/GT/control external (attach to baseline PCS-PMA/GT/CIPS) |
| **P5** full-inline synth QoR | ✅ | `synth_1` 100% of MAC+dwidth+parser+AIE+s2mm: **1.34% LUT** (12095), **0 DSP**, 4.5 BRAM — the Ethernet ingest adds only ~0.7% PL over the AIE-only datapath. impl needs GT pin constraints (attach PCS-PMA/GT); mapping in §9 |
| **P6** on-target validation (`vck190-13`) | ✅ | **HW PASS on real VCK190**: `host feature_graph.xclbin input.txt golden.txt` → `mean=-0.002065 var=0.302189 power=0.302193` == golden, **max_abs_err=5.96e-08 (bit-accurate), rc=0**. Full **DDR→mm2s→AIE(FIR→stats)→s2mm→DDR** datapath validated on silicon. Needed 3 fixes (see §10): (1) zocl dtb `interrupts-extended`, (2) `aie_image` graph CDO baked into BOOT.BIN, (3) drop host `graph.wait()` (PDI free-runs the graph) |

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
hw/scripts/inline_full_bd.tcl  CAPTURED validated FULL inline: axi_ethernet -> rx_dwidth(32->8) -> csi_udp_parser -> ai_engine -> s2mm -> DDR```
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
1. ✅ **AIE hw datapath linked**: `feature_graph.xsa` (mm2s→AIE FIR→stats→s2mm on `xilinx_vck190_base`). XRT host app ready (`host/host.cpp`).
2. ✅ **PetaLinux + SDK + package done**: `images/linux/` (Image/plm/psmfw/bl31/rootfs.cpio.gz.u-boot/system.dtb); SDK9 sysroot **with XRT 2.20.0** built (`images/linux/sdk.sh -d /tmp/vck190-sdk -y`); `host/host.cpp` cross-compiled → aarch64 `host/host`; `v++ --package` (`work/aie/feature_graph/package.sh`) → `feature_graph.xclbin` + `BOOT.BIN` + `sd_card.img`.
3. ✅ **Validated DDR→AIE→DDR on real VCK190** (`vck190-13`/chanterelle10): `host` output == golden, **max_abs_err=5.96e-08, rc=0 PASS** (bit-accurate). Three fixes were needed (zocl dtb `interrupts-extended` + `aie_image` CDO baked into BOOT.BIN + drop `graph.wait()`); full story + gotchas in **§10**.
4. Extend the composed graph to the **full 8‑feature** graph (add DFT branch + phase‑var branch).
5. ✅ **Full inline IPI BD captured + validated** (`hw/scripts/inline_full_bd.tcl`): `axi_ethernet → rx_dwidth(32→8) → csi_udp_parser → ai_engine → s2mm → DDR`. TODO: attach the MAC's GMII/GT to the baseline `gig_ethernet_pcs_pma`+`gt_quad_base`, wire `s_axi` to CIPS, then synth/impl.
6. PetaLinux app + **dashboard** (P4/P5).

## 10. VCK190 board bring-up (systest) + on-target validation — RESUME HERE
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
