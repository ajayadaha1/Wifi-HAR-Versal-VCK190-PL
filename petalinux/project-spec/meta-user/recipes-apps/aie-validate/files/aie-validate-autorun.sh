#!/bin/sh
# Boot-time DDR->AIE->DDR validation with self-diagnostics. Quiets the kernel
# console (the aie driver floods KERN_ERR "Tile is gated"), captures full detail
# to result.log, and echoes a CONCISE result to the console (com0) so the agent
# can read it without an interactive login.
LOG=/home/root/aie-validate/result.log
CON=/dev/console

# console_loglevel=1 -> only KERN_EMERG reaches com0 (suppress the aie spam)
echo 1 4 1 7 > /proc/sys/kernel/printk 2>/dev/null || true

{
  echo "===== AIE-VALIDATE BEGIN ====="
  cd /home/root/aie-validate || { echo "cd failed"; exit 1; }
  modprobe zocl 2>/dev/null || true
  sleep 5
  echo "--- lsmod aie/zocl ---"; lsmod | grep -iE 'aie|zocl' || true
  echo "--- /dev nodes ---"; ls -l /dev/dri /dev/aie* /dev/zocl* 2>&1 || true
  echo "--- xbutil examine ---"; xbutil examine 2>&1 | head -50 || true
  echo "--- host (timeout 60s) ---"
  timeout 60 ./host feature_graph.xclbin input.txt golden.txt
  echo "host_rc=$?"
  echo "--- dmesg aie/zocl tail ---"; dmesg 2>/dev/null | grep -iE 'aie|zocl|zyxclmm|xrt' | grep -viE 'is gated|failed to write to 0xc0|reg op 0 failed' | tail -20 || true
  echo "===== AIE-VALIDATE END ====="
} > "$LOG" 2>&1

# concise result to com0 (agent reads this)
{
  echo ""
  echo "##### AIE-VALIDATE RESULT #####"
  grep -E 'AIE result|golden:|max_abs_err|PASS|FAIL|host_rc=|xbutil|Devices|Shell|error|Error|terminate|what\(\)|not found|No such|Cannot|xclbin|/dev/' "$LOG" | tail -45
  echo "##### END RESULT #####"
} > "$CON" 2>&1
