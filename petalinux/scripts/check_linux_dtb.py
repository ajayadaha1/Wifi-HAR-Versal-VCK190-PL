#!/usr/bin/env python3
"""check_linux_dtb.py - assert a generated Linux device tree will actually boot.

Run on the DECOMPILED form of the final dtb (`dtc -I dtb -O dts`), which is one
canonical tab-indented layout and so can be matched reliably - lopper's source
output still carries labels, references and arbitrary whitespace.

Every check here corresponds to a boot failure seen on real hardware during
bring-up of this design. The device tree is now produced by lopper (the
supported tool) rather than by hand, so these should never fire again - they
exist so that if the lopper invocation in build_inline_boot.sh is ever changed
or dropped, the resulting brick is caught at build time instead of costing a
15-minute JTAG boot cycle to rediscover.

  1. arm,pl390 (2026-08-17).  An SDT describes every domain, so it carries the
     RPU's GICv2 as well as the APU's GICv3, both at 0xf9000000. of_irq_init
     picks the pl390, Linux loads the GICv2 driver on a GICv3 part, and dies:
         GICv3 system registers enabled, broken firmware!
         WARNING: ... at drivers/irqchip/irq-gic.c:57 gic_cpu_init

  2. interrupt-multiplex / imux (2026-08-18).  A lopper construct whose
     interrupt-parent fans every IRQ to BOTH GICs. Linux has no driver for it,
     so all ~60 referring nodes - including /timer - resolve to nothing:
         arch_timer: No interrupt available, giving up
         Failed to initialize '/timer': -22
     Its interrupt-map is also wrong for the timer specifically: it would
     rewrite PPI 13 into SPI 13, because interrupt-map-mask discards the type
     cell. Hence checking not just that the node is gone, but that /timer
     points straight at the GIC. Resolved by lop-a72-imux.dts.

  3. non-DDR memory (2026-08-18).  The SDT lists OCM (memory@FFFC0000) because
     the R5 and PSM domains use it. bl31 executes at 0xFFFE0000, inside that
     range, so declaring it as system RAM lets Linux allocate over TF-A's own
     text. Boot survives until allocation reaches that far, then the next entry
     to EL3 runs corrupted code and lands in plat_panic_handler with DAIF
     masked - which looks like a silent CPU hang that ignores NMIs. The
     giveaway is an earlier, easily-missed line:
         sram fffc0000.memory: error -EBUSY: can't request region ...
     i.e. the sram driver was refused OCM because it was already System RAM.

     The bound is a WINDOW, not `>= 0xF0000000`: Versal's high DDR bank lives
     at 0x500_0000_0000 and a one-sided test would delete it and boot a machine
     with no memory.

Usage:  check_linux_dtb.py <decompiled.dts>
"""
import re
import sys

NON_DDR_LO = 0xF0000000
NON_DDR_HI = 0x100000000


def fail(msg):
    raise SystemExit(f"FAIL: {msg}")


def node_body(text, name):
    """Body of a top-level `name { ... };` node, or None."""
    m = re.search(r"^\t" + re.escape(name) + r"\s*\{(.*?)^\t\};", text, re.M | re.S)
    return m.group(1) if m else None


def main():
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    text = open(sys.argv[1]).read()
    checks = []

    # --- 1: exactly one interrupt controller, and it is the GICv3 -----------
    if "arm,pl390" in text:
        fail("arm,pl390 present - Linux will panic in gic_cpu_init")
    n_gic = text.count('compatible = "arm,gic-v3"')
    if n_gic != 1:
        fail(f"expected exactly one arm,gic-v3, found {n_gic}")
    checks.append("one gic-v3, no pl390")

    # --- 2: imux resolved, and /timer wired straight to the GIC -------------
    if re.search(r"^\s+(interrupt-multiplex|imux)\s*\{", text, re.M):
        fail("interrupt-multiplex/imux node survived - the timer will not probe")
    gic = re.search(r"interrupt-controller@f9000000\s*\{(.*?)^\t\t\};",
                    text, re.M | re.S)
    if not gic:
        fail("no interrupt-controller@f9000000")
    gm = re.search(r"phandle = <(0x[0-9a-fA-F]+)>", gic.group(1))
    if not gm:
        fail("the GIC has no phandle")
    gic_ph = gm.group(1)

    timer = node_body(text, "timer")
    if timer is None:
        fail("no /timer node")
    tm = re.search(r"interrupt-parent = <(0x[0-9a-fA-F]+)>", timer)
    if not tm:
        fail("/timer has no interrupt-parent")
    if tm.group(1) != gic_ph:
        fail(f"/timer interrupt-parent is {tm.group(1)}, expected the GIC {gic_ph}")
    checks.append("imux resolved, /timer -> GIC")

    # --- 3: only DDR is offered to Linux as system RAM ----------------------
    bad = ["memory@" + m.group(1)
           for m in re.finditer(r"^\tmemory@([0-9a-fA-F]+)\s*\{", text, re.M)
           if NON_DDR_LO <= int(m.group(1), 16) < NON_DDR_HI]
    if bad:
        fail(f"non-DDR memory node(s) {', '.join(bad)} - Linux would allocate over TF-A")
    if not re.search(r"^\tmemory@0+\s*\{", text, re.M):
        fail("the DDR memory node is gone - Linux would have no RAM")
    checks.append("DDR only, OCM excluded")

    # --- the APU view exists at all ----------------------------------------
    if not re.search(r"^\tcpus\s*\{", text, re.M):
        fail("no /cpus node - the SDT cluster was not reduced to the APU view")
    checks.append("/cpus present")

    for c in checks:
        print(f"  OK  {c}")


if __name__ == "__main__":
    main()
