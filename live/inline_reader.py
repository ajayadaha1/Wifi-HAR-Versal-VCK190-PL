#!/usr/bin/env python3
r"""inline_reader.py - read the AI-Engine feature results + CSI metadata out of
DDR for the inline Arch-B design (work/hw/inline_eth_hw/inline.xsa).

The inline design is a plain Vivado design, NOT a Vitis platform: there is no
xclbin and XRT does not apply, so live_dashboard's "exec" source (which runs
./host_3br --stream) cannot drive it. Everything comes through /dev/mem instead.

    SFP0 -> axi_ethernet -> csi_udp_parser -> csi_mux -> AI Engine -> s2mm -> DDR
                                     \-> meta_out -> s2mm_meta -> DDR

Emitted line = the SAME CSV the "exec"/"fifo" sources already consume, with the
metadata record appended:

    mot0,mot1,mot2, brt0..brt32, phs0,phs1,phs2, seq,rssi,n_sub,chanspec,core_spatial

The 39 features come first and the field count is fixed, so a consumer that only
wants features can ignore the tail. `rssi` is what the dashboard turns into
element 7 of the ruview 8-feature vector, (rssi+100)/100 - see
work/csi_ref/features8.py, which owns that normalization.

Usage:
    python3 inline_reader.py --loop --hz 10             # on target, real hardware
    python3 inline_reader.py --loop --hz 10 --simulate  # anywhere, no hardware
    python3 inline_reader.py --arm --loop --decode      # also start the result s2mm

Register offsets and the HLS ap_ctrl_hs protocol mirror work/sw/csi_ctl.c, which
stays the authority for bring-up (mac-init / start / mux). This module only ever
reads, unless --arm is given.

Pure Python 3 standard library only (the target rootfs has no pip).
"""
import argparse
import collections
import math
import mmap
import os
import random
import struct
import sys
import time

# --- address map (PROJECT_STATE.md #12; identical to work/sw/csi_ctl.c) -------
PL_BASE       = 0xA4000000
PL_SPAN       = 0x00100000      # covers 0xA400_0000 .. 0xA40F_FFFF
OFF_MM2S      = 0x00000000
OFF_S2MM      = 0x00010000      # AIE feature-result writer
OFF_PARSER    = 0x00020000
OFF_S2MM_META = 0x00030000
OFF_CSI_MUX   = 0x00060000
OFF_ETH       = 0x00080000

# --- HLS ap_ctrl_hs control registers (parser, s2mm, s2mm_meta) --------------
HLS_AP_CTRL     = 0x00
AP_START        = 1 << 0
AP_DONE         = 1 << 1
AP_IDLE         = 1 << 2
AP_AUTO_RESTART = 1 << 7
S2MM_MEM_LO     = 0x10          # XS2MM_CONTROL_ADDR_MEM_DATA (64-bit)
S2MM_MEM_HI     = 0x14
S2MM_SIZE       = 0x1c          # XS2MM_CONTROL_ADDR_SIZE_DATA

# --- DDR landing zones --------------------------------------------------------
# Both live inside the 1 MB `no-map` reserved-memory carve-out at 0x7000_0000
# (work/petalinux/inline_extras.dtsi): s2mm/s2mm_meta are PL masters with no
# IOMMU and no driver, so the memory they write has to be memory Linux does not
# own. The metadata record is ONE packed 64-bit csi_meta_t at the base, rewritten
# per frame; the feature results sit 64 KB in so the two never share a page.
DEFAULT_META_PA    = 0x70000000
DEFAULT_RESULTS_PA = 0x70010000
META_WORDS         = 2          # one packed csi_meta_t = 64 bits

# --- AIE feature groups -------------------------------------------------------
# The validated 3-branch graph emits per window:
#   mot[3]  motion    : FIR->stats  -> mean, var, power
#   brt[33] breathing : windowed-DFT magnitude bins
#   phs[3]  phase-var : stats       -> mean, var, power
# The inline BD currently instantiates the 1-BRANCH graph (single AXIS in/out),
# so only `mot` is real today; the 3-branch inline BD is a planned follow-up.
# Hence `branches` is a parameter everywhere and missing groups read back as
# None (and are zero-filled on the wire) instead of being an error.
BRANCHES   = (("mot", 3), ("brt", 33), ("phs", 3))
N_FEATURES = sum(n for _, n in BRANCHES)        # 39
META_NAMES = ("seq", "rssi", "n_sub", "chanspec", "core_spatial")

Meta  = collections.namedtuple("Meta", "seq rssi n_sub chanspec core_spatial raw")
Frame = collections.namedtuple("Frame", "mot brt phs meta")


# --- metadata -----------------------------------------------------------------
def unpack_meta(raw):
    """Packed 64-bit csi_meta_t -> Meta.

    Layout from work/udp_parser/csi_udp_parser.hpp (csi_meta_pack):
      [15:0] seq  [23:16] rssi (signed 8-bit dBm)  [39:24] n_sub
      [55:40] chanspec  [63:56] core_spatial
    """
    rssi = (raw >> 16) & 0xFF
    if rssi >= 0x80:
        rssi -= 0x100                            # int8_t, dBm
    return Meta(seq=raw & 0xFFFF,
                rssi=rssi,
                n_sub=(raw >> 24) & 0xFFFF,
                chanspec=(raw >> 40) & 0xFFFF,
                core_spatial=(raw >> 56) & 0xFF,
                raw=raw)


# --- CSV interchange ----------------------------------------------------------
def branch_lists(frame):
    """Frame -> (mot[3], brt[33], phs[3]), missing branches zero-filled.

    This is the shape live_dashboard.derive_metrics expects, so a 1-branch
    bitstream degrades to "motion only" rather than crashing the dashboard.
    """
    out = []
    for name, n in BRANCHES:
        vals = list(getattr(frame, name) or [])[:n]
        out.append(vals + [0.0] * (n - len(vals)))
    return tuple(out)


def format_csv(frame):
    """Frame -> one CSV line (39 features, then the 5 metadata fields)."""
    vals = [v for group in branch_lists(frame) for v in group]
    line = ",".join("%.6g" % v for v in vals)
    if frame.meta is not None:
        line += "," + ",".join(str(getattr(frame.meta, n)) for n in META_NAMES)
    return line


def describe(frame):
    """Human-readable one-liner for --decode / bring-up (mirrors `csi_ctl meta`)."""
    mot, _brt, phs = branch_lists(frame)
    m = frame.meta
    txt = "mot={mean:.4g},{var:.4g},{pwr:.4g} phs_var={pv:.4g}".format(
        mean=mot[0], var=mot[1], pwr=mot[2], pv=phs[1])
    if m is not None:
        txt += (" | seq=%u rssi=%d dBm n_sub=%u chanspec=0x%04x core/spatial=0x%02x"
                " f7=%.4f" % (m.seq, m.rssi, m.n_sub, m.chanspec, m.core_spatial,
                              (m.rssi + 100) / 100.0))
    return txt


# --- /dev/mem plumbing --------------------------------------------------------
class _Window:
    """One mmap'd physical window; `skew` is the byte offset of the requested
    address inside the page-aligned mapping."""
    def __init__(self, mm, skew):
        self.mm, self.skew = mm, skew

    def u32(self, off):
        return struct.unpack_from("<I", self.mm, self.skew + off)[0]

    def u64(self, off):
        return struct.unpack_from("<Q", self.mm, self.skew + off)[0]

    def floats(self, off, n):
        return list(struct.unpack_from("<%df" % n, self.mm, self.skew + off))

    def write_u32(self, off, val):
        # 4-byte slice assignment lowers to a single 32-bit store, which is what
        # the AXI-Lite slaves need. csi_ctl.c remains the reference for writes.
        self.mm[self.skew + off:self.skew + off + 4] = struct.pack("<I", val & 0xFFFFFFFF)

    def close(self):
        self.mm.close()


class _DevMem:
    """Opens /dev/mem once and hands out page-aligned windows onto it."""
    def __init__(self, path="/dev/mem", writable=False):
        flags = (os.O_RDWR if writable else os.O_RDONLY) | os.O_SYNC
        try:
            self.fd = os.open(path, flags)
        except OSError as e:
            raise SystemExit("inline_reader: cannot open %s (%s) - this needs the target "
                             "board and root; use --simulate off-board" % (path, e.strerror))
        self.writable = writable
        self.windows = []

    def window(self, phys, span):
        page = mmap.PAGESIZE
        base = phys & ~(page - 1)
        skew = phys - base
        length = ((skew + span + page - 1) // page) * page
        prot = mmap.PROT_READ | (mmap.PROT_WRITE if self.writable else 0)
        w = _Window(mmap.mmap(self.fd, length, mmap.MAP_SHARED, prot, offset=base), skew)
        self.windows.append(w)
        return w

    def close(self):
        for w in self.windows:
            w.close()
        os.close(self.fd)


# --- readers ------------------------------------------------------------------
class InlineReader:
    """Reads the AIE feature results and the metadata record from DDR.

    branches       : how many of mot/brt/phs the bitstream actually produces
                     (1 today, 3 after the 3-branch inline BD lands).
    branch_stride  : bytes between branch result buffers. 0 = packed, i.e. one
                     s2mm writing all groups back to back, which is what a single
                     concatenated AIE output looks like. A 3-branch BD with three
                     s2mm instances would give each its own buffer - pass e.g.
                     0x1000 then.
    """
    def __init__(self, branches=1, meta_pa=DEFAULT_META_PA, results_pa=DEFAULT_RESULTS_PA,
                 branch_stride=0, pl_base=PL_BASE, devmem="/dev/mem", arm=False):
        self.groups = list(BRANCHES[:max(1, min(branches, len(BRANCHES)))])
        self.results_pa = results_pa
        self.branch_stride = branch_stride
        self.n_words = sum(n for _, n in self.groups)

        self.mem = _DevMem(devmem, writable=arm)
        self.pl = self.mem.window(pl_base, PL_SPAN)
        self.meta_w = self.mem.window(meta_pa, META_WORDS * 4)
        span = branch_stride * len(self.groups) if branch_stride else self.n_words * 4
        self.res_w = self.mem.window(results_pa, span)
        if arm:
            self.arm()

    def arm(self):
        """Program the AIE result s2mm: buffer address + word count, then
        ap_start|auto_restart so it rewrites the same buffer every window - the
        same recipe `csi_ctl start` uses for s2mm_meta. csi_ctl deliberately
        leaves this mover alone, so the reader can own it."""
        self.pl.write_u32(OFF_S2MM + S2MM_MEM_LO, self.results_pa & 0xFFFFFFFF)
        self.pl.write_u32(OFF_S2MM + S2MM_MEM_HI, self.results_pa >> 32)
        self.pl.write_u32(OFF_S2MM + S2MM_SIZE,   self.n_words)
        self.pl.write_u32(OFF_S2MM + HLS_AP_CTRL, AP_START | AP_AUTO_RESTART)

    def kernel_states(self):
        """{name: ap_ctrl} for the three HLS kernels - a cheap liveness check."""
        return {"parser":    self.pl.u32(OFF_PARSER + HLS_AP_CTRL),
                "s2mm":      self.pl.u32(OFF_S2MM + HLS_AP_CTRL),
                "s2mm_meta": self.pl.u32(OFF_S2MM_META + HLS_AP_CTRL)}

    def read_once(self):
        meta = unpack_meta(self.meta_w.u64(0))
        vals = {}
        off = 0
        for name, n in self.groups:
            vals[name] = self.res_w.floats(off, n)
            off = off + self.branch_stride if self.branch_stride else off + n * 4
        return Frame(mot=vals.get("mot"), brt=vals.get("brt"),
                     phs=vals.get("phs"), meta=meta)

    def close(self):
        self.mem.close()


class SimulatedReader:
    """Fabricate plausible frames with NO hardware, so the dashboard can be
    developed and demoed off-board. Cycles through empty / breathing / walking /
    fall so every card and chart on the dashboard actually moves.

    Note the breathing scenario only reads back as "stationary - breathing" for
    fs <~ 8 Hz: at fs=20 the dashboard's 0.1-0.6 Hz band is a single bin of the
    64-point DFT, so its peak/median SNR is 1.0 by construction and presence can
    then only come from motion. That is a property of the 64-sample breathing
    window, not of this simulator - `--fs 5` shows the breathing path working.
    """
    SCENARIOS = ("empty", "stationary-breathing", "walking", "fall")

    def __init__(self, branches=3, fs=20.0, scene_s=12.0, bpm=15.0, seed=None):
        self.groups = list(BRANCHES[:max(1, min(branches, len(BRANCHES)))])
        self.fs, self.scene_s, self.bpm = fs, scene_s, bpm
        self.rng = random.Random(seed)
        self.t0 = time.time()
        self.seq = self.rng.randrange(1 << 16)
        self.rssi = -42.0

    def scenario(self):
        t = time.time() - self.t0
        return self.SCENARIOS[int(t / self.scene_s) % len(self.SCENARIOS)], t % self.scene_s

    def read_once(self):
        scene, phase = self.scenario()
        j = lambda v, s=0.15: v * (1.0 + self.rng.uniform(-s, s))
        breathe = 0.5 * (1.0 + math.sin(2 * math.pi * (self.bpm / 60.0) * phase))

        if scene == "walking":
            power, pvar, peak = j(2.0e-2), j(1.5), 0.15
        elif scene == "stationary-breathing":
            power, pvar, peak = j(1.2e-3) * (0.4 + breathe), j(0.4), 1.0
        elif scene == "fall":
            # a spike then stillness - what live_dashboard's FALL_WIN heuristic looks for
            power, pvar, peak = (j(8.0e-2), j(2.0), 0.1) if phase < 1.0 else (j(1.5e-3), j(0.1), 0.2)
        else:                                    # empty
            power, pvar, peak = j(2.0e-4), j(0.05), 0.05

        # brt: 33 rfft magnitude bins of a 64-point window; put the breathing
        # peak in the bin nearest self.bpm so it lands inside the 0.1-0.6 Hz band.
        nfft = 2 * (BRANCHES[1][1] - 1)          # 64
        k = max(1, min(BRANCHES[1][1] - 1, int(round((self.bpm / 60.0) * nfft / self.fs))))
        brt = [j(0.02 + 0.05 / (1 + i)) for i in range(BRANCHES[1][1])]
        brt[k] += peak * (0.5 + breathe)

        mot = [j(1.0e-3, 0.5), j(power * 0.8), power]      # mean, var, power
        phs = [j(1.0e-2, 0.5), pvar, j(pvar * 1.2)]

        self.seq = (self.seq + 1) & 0xFFFF
        self.rssi = max(-70.0, min(-25.0, self.rssi + self.rng.uniform(-1.5, 1.5)))
        meta = Meta(seq=self.seq, rssi=int(round(self.rssi)), n_sub=256,
                    chanspec=0xE82B, core_spatial=0x01, raw=0)

        have = [n for n, _ in self.groups]
        return Frame(mot=mot if "mot" in have else None,
                     brt=brt if "brt" in have else None,
                     phs=phs if "phs" in have else None,
                     meta=meta)

    def kernel_states(self):
        return {"parser": AP_START | AP_AUTO_RESTART, "s2mm": AP_START | AP_AUTO_RESTART,
                "s2mm_meta": AP_START | AP_AUTO_RESTART}

    def close(self):
        pass


def make_reader(simulate=False, branches=None, **kw):
    """Factory used by both the CLI and live_dashboard's `inline` source.

    branches defaults to 1 on hardware (what the current inline BD builds) and to
    3 in --simulate, so an off-board demo shows the full dashboard.
    """
    if simulate:
        sim_kw = {k: kw[k] for k in ("fs", "scene_s", "bpm", "seed") if k in kw}
        return SimulatedReader(branches=3 if branches is None else branches, **sim_kw)
    hw_kw = {k: v for k, v in kw.items() if k in
             ("meta_pa", "results_pa", "branch_stride", "pl_base", "devmem", "arm")}
    return InlineReader(branches=1 if branches is None else branches, **hw_kw)


def frames(reader, hz=10.0, new_only=False):
    """Yield Frames at `hz`. new_only skips polls where the metadata sequence
    number has not moved (i.e. no new CSI frame reached the parser)."""
    period = 1.0 / hz if hz > 0 else 0.0
    last_seq = None
    while True:
        frame = reader.read_once()
        seq = frame.meta.seq if frame.meta is not None else None
        if not (new_only and seq is not None and seq == last_seq):
            last_seq = seq
            yield frame
        if period:
            time.sleep(period)


# --- CLI ----------------------------------------------------------------------
def _hexint(s):
    return int(s, 0)


def main():
    ap = argparse.ArgumentParser(description="inline Arch-B AIE result + metadata reader")
    ap.add_argument("--simulate", action="store_true",
                    help="fabricate plausible data, no hardware / no /dev/mem")
    ap.add_argument("--loop", action="store_true", help="keep reading (default: one line)")
    ap.add_argument("--hz", type=float, default=10.0, help="poll rate for --loop")
    ap.add_argument("--branches", type=int, default=None,
                    help="AIE branches present: 1 (current inline BD) or 3 "
                         "(default: 1 on hardware, 3 with --simulate)")
    ap.add_argument("--meta-buf", type=_hexint, default=DEFAULT_META_PA,
                    help="metadata physical address (default 0x%x)" % DEFAULT_META_PA)
    ap.add_argument("--results-buf", type=_hexint, default=DEFAULT_RESULTS_PA,
                    help="AIE result physical address (default 0x%x)" % DEFAULT_RESULTS_PA)
    ap.add_argument("--branch-stride", type=_hexint, default=0,
                    help="bytes between per-branch result buffers (0 = packed)")
    ap.add_argument("--pl-base", type=_hexint, default=PL_BASE)
    ap.add_argument("--devmem", default="/dev/mem")
    ap.add_argument("--arm", action="store_true",
                    help="program and free-run the AIE result s2mm before reading")
    ap.add_argument("--new-only", action="store_true",
                    help="only emit when the metadata sequence number advances")
    ap.add_argument("--decode", action="store_true",
                    help="also print a human-readable line to stderr")
    ap.add_argument("--fs", type=float, default=20.0, help="CSI frame rate [Hz] (--simulate)")
    ap.add_argument("--scene-s", type=float, default=12.0,
                    help="seconds per simulated scenario (--simulate)")
    args = ap.parse_args()

    reader = make_reader(simulate=args.simulate, branches=args.branches,
                         meta_pa=args.meta_buf, results_pa=args.results_buf,
                         branch_stride=args.branch_stride, pl_base=args.pl_base,
                         devmem=args.devmem, arm=args.arm,
                         fs=args.fs, scene_s=args.scene_s)
    try:
        src = frames(reader, args.hz, args.new_only) if args.loop else iter([reader.read_once()])
        for frame in src:
            print(format_csv(frame), flush=True)
            if args.decode:
                print(describe(frame), file=sys.stderr, flush=True)
    except KeyboardInterrupt:
        pass
    finally:
        reader.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
