#!/usr/bin/env python3
# Graft the zocl (zyxclmm_drm) node onto the freshly-compiled 3-branch SDT dts.
# The node references the STATIC axi_intc controllers by label (same base
# platform as 1-branch): 32 lines from axi_intc_cascaded_1 (@a4040000) + 31 from
# axi_intc_parent (@a4050000) = 63 CU IRQs, sense 4 (matches the 1-branch patch).
ie = []
for n in range(32):
    ie.append(f"&axi_intc_cascaded_1 {n} 4")
for n in range(31):
    ie.append(f"&axi_intc_parent {n} 4")
snippet = (
    "\n&{/} {\n"
    "    zyxclmm_drm {\n"
    '        compatible = "xlnx,zocl-versal";\n'
    "        interrupts-extended = < " + " ".join(ie) + " >;\n"
    "    };\n"
    "};\n"
)
with open("/tmp/system-3br.pp.dts") as f:
    base = f.read()
with open("/tmp/system-zocl-3br.dts", "w") as f:
    f.write(base + snippet)
print("wrote /tmp/system-zocl-3br.dts; interrupts-extended entries:", len(ie))
