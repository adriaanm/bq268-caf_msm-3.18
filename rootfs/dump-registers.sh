#!/bin/sh
# dump-registers.sh — Dump BIMC, GCC, and PMIC registers for comparison
# Run on both CAF 3.18 and mainline 6.19 to identify DDR stability differences
#
# Usage: dump-registers > /tmp/regdump-caf-3.18.txt
#
# Requires: devmem (busybox applet), /dev/mem access

echo "=== Register Dump: $(uname -r) ==="
echo "Date: $(date 2>/dev/null || echo unknown)"
echo ""

# Helper: read 32-bit register via /dev/mem
readreg() {
    addr=$1
    name=$2
    if command -v devmem >/dev/null 2>&1; then
        val=$(devmem "$addr" 32 2>/dev/null)
    elif command -v devmem2 >/dev/null 2>&1; then
        val=$(devmem2 "$addr" w 2>/dev/null | grep "Value at" | awk '{print $NF}')
    else
        val="NO_TOOL"
    fi
    printf "%-40s 0x%08x = %s\n" "$name" "$addr" "${val:-ERROR}"
}

echo "=== BIMC QoS Registers (base 0x00400000) ==="
echo "--- Port 0: CPU (apps_proc) ---"
readreg 0x0040C230 "M_PRIOLVL_OVERRIDE"
readreg 0x0040C240 "M_RD_CMD_OVERRIDE"
readreg 0x0040C250 "M_WR_CMD_OVERRIDE"
readreg 0x0040C300 "M_BKE_EN"
readreg 0x0040C304 "M_BKE_GP (grant period)"
readreg 0x0040C308 "M_BKE_GC (grant count)"
readreg 0x0040C320 "M_BKE_THH (threshold high)"
readreg 0x0040C324 "M_BKE_THM (threshold med)"
readreg 0x0040C328 "M_BKE_THL (threshold low)"
readreg 0x0040C340 "M_BKE_HEALTH_0"
readreg 0x0040C344 "M_BKE_HEALTH_1"
readreg 0x0040C348 "M_BKE_HEALTH_2"
readreg 0x0040C34C "M_BKE_HEALTH_3"
echo ""

echo "--- Port 2: GPU (oxili) ---"
readreg 0x00414230 "M_PRIOLVL_OVERRIDE"
readreg 0x00414240 "M_RD_CMD_OVERRIDE"
readreg 0x00414250 "M_WR_CMD_OVERRIDE"
readreg 0x00414300 "M_BKE_EN"
readreg 0x00414304 "M_BKE_GP"
readreg 0x00414308 "M_BKE_GC"
readreg 0x00414340 "M_BKE_HEALTH_0"
readreg 0x00414344 "M_BKE_HEALTH_1"
readreg 0x00414348 "M_BKE_HEALTH_2"
readreg 0x0041434C "M_BKE_HEALTH_3"
echo ""

echo "--- Port 3: SNOC-BIMC 0 ---"
readreg 0x00418300 "M_BKE_EN"
readreg 0x00418340 "M_BKE_HEALTH_0"
echo ""

echo "--- Port 4: SNOC-BIMC 1 ---"
readreg 0x0041C300 "M_BKE_EN"
readreg 0x0041C340 "M_BKE_HEALTH_0"
echo ""

echo "--- Port 5: TCU 0 ---"
readreg 0x00420230 "M_PRIOLVL_OVERRIDE"
readreg 0x00420300 "M_BKE_EN"
readreg 0x00420340 "M_BKE_HEALTH_0"
readreg 0x00420344 "M_BKE_HEALTH_1"
echo ""

echo "--- Port 6: TCU 1 ---"
readreg 0x00424230 "M_PRIOLVL_OVERRIDE"
readreg 0x00424300 "M_BKE_EN"
readreg 0x00424340 "M_BKE_HEALTH_0"
echo ""

echo "--- DDR Slave (S_DDR0) ---"
readreg 0x00448000 "S_DDR0_BASE"
readreg 0x00448100 "S_DDR0_SCMO_CFG"
readreg 0x00448200 "S_DDR0_DPE_CFG"
echo ""

echo "=== GCC Clock Registers (base 0x01800000) ==="
readreg 0x01831000 "GCC_BIMC_BCR"
readreg 0x01831004 "GCC_BIMC_MISC"
readreg 0x01831008 "GCC_BIMC_CMD_RCGR"
readreg 0x0183100C "GCC_BIMC_CFG_RCGR"
readreg 0x01831010 "GCC_BIMC_M"
readreg 0x01831014 "GCC_BIMC_N"
readreg 0x01831018 "GCC_BIMC_D"
readreg 0x0183101C "GCC_BIMC_CBCR"
readreg 0x01831024 "GCC_BIMC_APSS_AXI_CBCR"
readreg 0x01831030 "GCC_BIMC_GFX_CBCR"
echo ""

echo "--- GPLL0 (main PLL) ---"
readreg 0x01821000 "GPLL0_MODE"
readreg 0x01821004 "GPLL0_L_VAL"
readreg 0x01821008 "GPLL0_M_VAL"
readreg 0x0182100C "GPLL0_N_VAL"
readreg 0x01821010 "GPLL0_USER_CTL"
readreg 0x01821024 "GPLL0_STATUS"
echo ""

echo "--- GPLL1 ---"
readreg 0x01820000 "GPLL1_MODE"
readreg 0x01820004 "GPLL1_L_VAL"
readreg 0x01820024 "GPLL1_STATUS"
echo ""

echo "--- GPLL2 (BIMC PLL) ---"
readreg 0x0184C000 "GPLL2_MODE"
readreg 0x0184C004 "GPLL2_L_VAL"
readreg 0x0184C008 "GPLL2_M_VAL"
readreg 0x0184C00C "GPLL2_N_VAL"
readreg 0x0184C010 "GPLL2_USER_CTL"
readreg 0x0184C024 "GPLL2_STATUS"
echo ""

echo "=== APCS / CPU Registers ==="
readreg 0x0B011050 "APCS_ALIAS0_CMD_RCGR"
readreg 0x0B011054 "APCS_ALIAS0_CFG_RCGR"
readreg 0x0B011058 "APCS_ALIAS0_MISC"
echo ""

echo "=== Debugfs (if available) ==="
echo "--- Clock summary ---"
cat /sys/kernel/debug/clk/clk_summary 2>/dev/null || echo "(not available)"
echo ""

echo "--- RPM stats ---"
cat /sys/kernel/debug/rpm_stats 2>/dev/null || echo "(not available)"
echo ""

echo "--- RPM master stats ---"
cat /sys/kernel/debug/rpm_master_stats 2>/dev/null || echo "(not available)"
echo ""

echo "--- Regulator summary ---"
cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null || echo "(not available)"
echo ""

echo "--- Interconnect summary ---"
cat /sys/kernel/debug/interconnect/interconnect_summary 2>/dev/null || echo "(not available)"
echo ""

echo "=== Done ==="
