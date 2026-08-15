# WiFi-CSI Human Activity Recognition on Versal VCK190 (PL + AI Engine)

Hardware/software co-design that streams WiFi **Channel-State-Information (CSI)**
from a Raspberry Pi (nexmon) over Ethernet into an AMD **Versal VCK190**, parses
the UDP/CSI stream in the **Programmable Logic (PL)**, runs the DSP feature
extraction on the **AI Engine (AIE) array + PL**, and DMAs only the compact
results to Linux on the Arm Cortex-A72 for visualization.

> The AIE/PL contribution is the **DSP feature extraction**; the classifier is a
> tiny pretrained MLP (ruview encoder). See [`docs/plan.md`](docs/plan.md) for the
> full thesis plan and [`docs/PROJECT_STATE.md`](docs/PROJECT_STATE.md) for the
> detailed build log, decisions, and gotchas.

---

## Status — validated on real silicon

The **DDR → mm2s → AIE (FIR→stats) → s2mm → DDR** datapath has been validated
**bit-accurate on a real VCK190**:

```
AIE result: mean=-0.002065 var=0.302189 power=0.302193
golden:     mean=-0.002065 var=0.302189 power=0.302193
max_abs_err=5.96e-08 -> PASS
```

Three integration fixes were required (details in `docs/PROJECT_STATE.md` §10):
1. add `interrupts-extended` (63 CU IRQs) to the `zyxclmm_drm` **zocl** dtb node,
2. bake the **`aie_image`** graph CDO into `BOOT.BIN`,
3. drop `graph.wait()` in the host (the packaged CDO free-runs the graph).

---

## Repository layout

| Path | Contents |
|---|---|
| `hw/scripts/` | Vivado **IP-Integrator TCL** to rebuild the PL designs (baseline Ethernet + inline parser/AIE/DMA) |
| `hw/constraints/`, `hw/hdl/` | XDC constraints and HDL wrappers |
| `hw/ip_repo/` | packaged `csi_udp_parser` HLS IP (used by the inline BD) |
| `aie/src/` | AIE **feature graph**: FIR band-pass, mean/var/power stats, windowed-DFT magnitude, `graph.cpp` |
| `aie/pl/` | PL data movers `mm2s.cpp` / `s2mm.cpp` (DDR ↔ AIE PLIO) |
| `aie/host/` | XRT host apps (`host.cpp` 1-branch, `host_3br.cpp` 3-branch) + cross-compile Makefile |
| `aie/*.sh`, `aie/*.cfg` | `build_hw.sh`, `system.cfg`, `package.sh` (v++ link/package flow) |
| `hls/` | Vitis HLS UDP/CSI parser (`csi_udp_parser.*`, testbench, `run_hls.tcl`) |
| `petalinux/project-spec/` | PetaLinux **project-spec** (recipes + configs), source only |
| `docs/` | `plan.md`, `PROJECT_STATE.md` |

---

## Required tools / hardware

- **VCK190** Prod eval board (part `xcvc1902-vsva2197-2MP-e-S`)
- **Vivado / Vitis 2025.2** + **PetaLinux 2025.2**
- Vitis base platform `xilinx_vck190_base_202520_1`
- (for the live path) 1000BASE-X SFP + Raspberry Pi 4 running `nexmon_csi`

---

## Build instructions

### 1. PL design in Vivado

```bash
cd hw/scripts
# Baseline 1G Ethernet bring-up (reference-style):
vivado -source project_top.tcl              # builds into ../Hardware/ps_emio_basex_hw
# Inline HAR pipeline (Ethernet -> parser -> AIE -> s2mm -> DDR):
#   create a project, add hw/ip_repo to the IP repo, then source the BD:
#   vivado -mode batch -source inline_full_bd.tcl
```

### 2. AIE feature graph + PL data movers (v++)

```bash
cd aie
source /path/to/Vitis/2025.2/settings64.sh
./build_hw.sh                                # aiecompiler: src/graph.cpp -> libadf.a
# compile the PL movers to .xo:
v++ -c -t hw --platform <base>.xpfm -k mm2s pl/mm2s.cpp -o mm2s.xo
v++ -c -t hw --platform <base>.xpfm -k s2mm pl/s2mm.cpp -o s2mm.xo
# link AIE + movers into an XSA (1-branch shown; use system_3br.cfg for 3-branch):
v++ -l -t hw --platform <base>.xpfm --config system.cfg libadf.a mm2s.xo s2mm.xo \
    -o feature_graph.xsa
./package.sh                                 # -> feature_graph.xclbin (+ BOOT.BIN)
```

### 3. HLS UDP/CSI parser

```bash
cd hls
vitis_hls -f run_hls.tcl                     # C-sim + C/RTL co-sim + export IP
```

### 4. PetaLinux (Linux image for the A72)

```bash
petalinux-create --type project --template versal --name plnx
cd plnx
petalinux-config --get-hw-description=<path-to>/feature_graph.xsa   # import HW
# overlay the tracked project-spec (recipes + configs) from this repo:
cp -r /path/to/repo/petalinux/project-spec/* project-spec/
petalinux-config --silentconfig
petalinux-build                              # -> images/linux/{Image,rootfs,...}
```

### 5. Host validation on target

```bash
cd aie/host
make SYSROOT=<petalinux>/images/linux/sdk/sysroots/cortexa72-cortexa53-*-linux
# on the board:
./host feature_graph.xclbin input.txt golden.txt        # -> PASS vs golden
```

---

## Known issues / notes

- The SDT/PetaLinux flow does **not** auto-add the zocl CU `interrupts-extended`
  or the `aie_image` CDO; both must be injected into the dtb/BOOT.BIN (see
  `docs/PROJECT_STATE.md` §10 for the exact patch + `bootgen` recipe).
- The packaged AIE CDO enables (free-runs) the graph, so the host must **not**
  call `graph.wait()` — drain `s2mm` instead.
- `docs/` captures the full phase-by-phase build log and every debugged gotcha.

---

### License
Licensed under the Apache License, Version 2.0 — see [`LICENSE`](LICENSE).
