#!/usr/bin/env python3
"""Generate the A03 patch series from a pristine xnu-12377.121.6 tree.

The tree is never modified: this script keeps an in-memory copy of each file,
applies the edits for one patch at a time, and writes unified diffs that can be
fed to `git apply`. Run with:

    python3 xnu/tools/gen_a03_patches.py
"""

from pathlib import Path
import argparse
import difflib
import os

HERE = Path(__file__).resolve().parent
ROOT = Path(os.environ.get("A03_XNU_ROOT", str(HERE.parent.parent / "xnu-src")))
OUT = Path(os.environ.get("A03_PATCH_OUT", str(HERE.parent / "patches-a03")))
OUT.mkdir(parents=True, exist_ok=True)


class State:
    def __init__(self):
        self.files = {}

    def read(self, rel):
        if rel not in self.files:
            self.files[rel] = (ROOT / rel).read_text(encoding="utf-8", errors="surrogateescape")
        return self.files[rel]

    def patch(self, name, edits):
        """edits: list of (relative path, old text, new text); old == '' creates a file.

        When generating against a donor-patched tree, an edit whose context is
        already absent (or whose file already exists) is skipped with a warning:
        Bergamota may have applied the equivalent change for SWEET already.
        """
        order = []
        grouped = {}
        for rel, old, new in edits:
            if rel not in grouped:
                grouped[rel] = []
                order.append(rel)
            grouped[rel].append((old, new))

        chunks = []
        for rel in order:
            exists = (ROOT / rel).exists()
            original = self.read(rel) if exists else ""
            current = original
            applied = 0
            for old, new in grouped[rel]:
                if old == "":
                    if exists or rel in self.files and (ROOT / rel).exists():
                        print(f"  skip {name}: {rel} already exists (donant)")
                        continue
                elif old not in current:
                    print(f"  skip {name}: context absent in {rel}")
                    continue
                current = current.replace(old, new, 1) if old else new
                applied += 1
            self.files[rel] = current
            if applied == 0:
                continue
            header = f"diff --git a/{rel} b/{rel}\n"
            if original == "":
                header += "new file mode 100644\n"
                diff = difflib.unified_diff(
                    [], current.splitlines(True),
                    fromfile="/dev/null", tofile=f"b/{rel}", n=3, lineterm="\n")
            else:
                diff = difflib.unified_diff(
                    original.splitlines(True), current.splitlines(True),
                    fromfile=f"a/{rel}", tofile=f"b/{rel}", n=3, lineterm="\n")
            chunks.append(header + "".join(diff))
        text = "".join(chunks)
        (OUT / name).write_text(text, encoding="utf-8")
        print(f"{name}: {len(chunks)} file(s), {len(text)} bytes")


s = State()

# ---------------------------------------------------------------------------
# 0001: teach the build system about MACHINE_CONFIG=A03.
# ---------------------------------------------------------------------------
s.patch("0001-a03-machine-config.patch", [
    ("makedefs/MakeInc.def",
     "SUPPORTED_ARM64_MACHINE_CONFIGS = T6000 T6020 T6030 T6031 T6041 T6050 T8101 T8103 T8112 T8122 T8132 T8142 VMAPPLE SWEET",
     "SUPPORTED_ARM64_MACHINE_CONFIGS = T6000 T6020 T6030 T6031 T6041 T6050 T8101 T8103 T8112 T8122 T8132 T8142 VMAPPLE SWEET A03"),

    ("makedefs/MakeInc.def",
     "MACHINE_FLAGS_ARM64_SWEET = -DARM64_BOARD_CONFIG_SWEET                -march=armv8.2-a+crypto\n",
     "MACHINE_FLAGS_ARM64_SWEET = -DARM64_BOARD_CONFIG_SWEET                -march=armv8.2-a+crypto\n"
     "MACHINE_FLAGS_ARM64_A03 = -DARM64_BOARD_CONFIG_A03                -march=armv8.2-a+crypto\n"),

    # Cortex-A75/A55 have no pointer authentication: keep the Mach-O slice as plain arm64.
    # Bergamota already special-cases SWEET here; add A03 to that condition.
    ("makedefs/MakeInc.def",
     "# sweet's Cortex-A76/A55 have no pointer authentication: stay plain arm64\n"
     "ifneq ($(CURRENT_MACHINE_CONFIG),SWEET)\n",
     "# sweet/a03 have no pointer authentication: stay plain arm64\n"
     "ifeq ($(filter SWEET A03,$(CURRENT_MACHINE_CONFIG)),)\n"),

    # No closed KDK SoC archive exists for a Unisoc board; A03 builds the
    # open-source asm/pmap instead (see MASTER.arm64.a03).
    ("makedefs/MakeInc.def",
     "ifeq ($(filter NONE SWEET,$(CURRENT_MACHINE_CONFIG)),)\n",
     "ifeq ($(filter NONE SWEET A03,$(CURRENT_MACHINE_CONFIG)),)\n"),

    # Tightbeam is arm64e/Apple-only and A03 has no exclaves.
    ("makedefs/MakeInc.def",
     "ifneq ($(CURRENT_MACHINE_CONFIG),SWEET)\nifneq ($(wildcard $(SDKROOT)/usr/local/lib/kernel/platform/libTightbeam.a),)\n",
     "ifeq ($(filter SWEET A03,$(CURRENT_MACHINE_CONFIG)),)\n"
     "ifneq ($(wildcard $(SDKROOT)/usr/local/lib/kernel/platform/libTightbeam.a),)\n"),
    ("makedefs/MakeInc.def",
     "endif # !SWEET\n",
     "endif # !SWEET/A03\n"),
])

# ---------------------------------------------------------------------------
# 0002: board header and build wiring.
# ---------------------------------------------------------------------------
A03_H = r'''/*
 * Board config for the Samsung Galaxy A03 (SM-A035M), Unisoc T606 / UMS9230:
 * 4x Cortex-A75 + 4x Cortex-A55, ARMv8.2-A, no PAC, GICv3, architected timer.
 *
 * This is a generic ARM64 platform, not an Apple ARM64 family: none of the
 * Apple implementation-defined system registers exist here. Like VMAPPLE we
 * use the architected timer and GICv3; unlike VMAPPLE the GIC has two security
 * states, so Group 0 belongs to TrustZone and everything we own is Group 1 NS.
 */

#ifndef _PEXPERT_ARM64_A03_H
#define _PEXPERT_ARM64_A03_H

#define A03                       1

#define NO_MONITOR                1
#define NO_ECORE                  1

#define ARM_ARCH_TIMER
#define __ARM_ARCH__              8
#define __ARM_VMSA__              8
#define __ARM_VFP__               4
#define __ARM_COHERENT_CACHE__    1
#define __ARM_DEBUG__             7
#define __ARM_ENABLE_SWAP__       1
#define __ARM_V8_CRYPTO_EXTENSIONS__ 1
#define __ARM_PAN_AVAILABLE__     1
#define __ARM_16K_PG__            1

#define HAS_GIC_V3                1

/* apple_arm64_cpu.h is included unconditionally by several arm64 files. */
#define MPIDR_CORETYPE_SHIFT      (16)
#define MPIDR_CORETYPE_WIDTH      (3)
#define MPIDR_CORETYPE_MASK       ((1ULL << MPIDR_CORETYPE_WIDTH) - 1)
#define MPIDR_CORETYPE_ACC_E      (0ULL)
#define MPIDR_CORETYPE_ACC_P      (1ULL)
#define MPIDR_CORETYPE_ACC_M      (4ULL)

#ifndef ASSEMBLER
#define PLATFORM_PANIC_LOG_DISABLED
#endif /* !ASSEMBLER */

/* DTB: timer interrupts = 13,14,11,10 => virtual timer is PPI 11 => INTID 27. */
#define A03_VTIMER_INTID          27
#define A03_IPI_SGI               1

#define GIC_SPURIOUS_IRQ          1023
#define GICR_PE_SIZE              0x20000

/* GICv3 register offsets (Arm IHI 0069G). */
#define GICD_CTLR                 0x0
#define GICD_CTLR_ENABLEGRP1      0x1
#define GICD_CTLR_ENABLEGRP1A     0x2
#define GICD_CTLR_ARE_NS          0x10
#define GICD_CTLR_RWP             0x80000000

#define GICR_TYPER                0x08
#define GICR_WAKER                0x14
#define GICR_IGROUPR0             0x10080
#define GICR_ISENABLER0           0x10100
#define GICR_IPRIORITYR0          0x10400

#define GICR_TYPER_AFFINITY_VALUE_SHIFT 32
#define GICR_TYPER_LAST           0x10
#define GICR_WAKER_PROCESSORSLEEP 0x2
#define GICR_WAKER_CHILDRENASLEEP 0x4

#define ICC_CTLR_EOIMODE          0x2
#define ICC_SRE_SRE               0x1

/* Calibrated boot framebuffer: 32bpp BGRA, A=0xff, stride 2880 bytes. */
#define A03_FB_PHYS               0x9E000000u
#define A03_FB_WIDTH              720u
#define A03_FB_HEIGHT             1600u
#define A03_FB_STRIDE             2880u

#endif /* !_PEXPERT_ARM64_A03_H */
'''

s.patch("0002-a03-board-header.patch", [
    ("pexpert/pexpert/arm64/A03.h", "", A03_H),

    ("pexpert/pexpert/arm64/board_config.h",
     "#ifdef ARM64_BOARD_CONFIG_VMAPPLE\n#include <pexpert/arm64/VMAPPLE.h>\n",
     "#ifdef ARM64_BOARD_CONFIG_A03\n"
     "#include <pexpert/arm64/A03.h>\n\n"
     "#define MAX_L2_CLINE                   6\n"
     "#define MAX_CPUS                       8\n"
     "#define MAX_CPU_CLUSTERS               1\n"
     "\n"
     "#define CORE_NCTRS                     8 /* Placeholder; KPC is not enabled for this target */\n"
     "\n"
     "#endif  /* ARM64_BOARD_CONFIG_A03 */\n\n\n\n"
     "#ifdef ARM64_BOARD_CONFIG_VMAPPLE\n#include <pexpert/arm64/VMAPPLE.h>\n"),

    ("pexpert/pexpert/arm64/Makefile",
     "\tH17.h \\\n\tVMAPPLE.h \\\n\tSWEET.h",
     "\tH17.h \\\n\tVMAPPLE.h \\\n\tSWEET.h \\\n\tA03.h"),

    ("osfmk/arm64/proc_reg.h",
     "#elif defined (VMAPPLE)\n\n/* I-Cache. */\n",
     "#elif defined (A03)\n\n"
     "/* Cortex-A75/A55: 64-byte I and D cache lines. */\n"
     "#define MMU_I_CLINE 6\n"
     "#define MMU_CLINE   6\n\n"
     "#elif defined (VMAPPLE)\n\n/* I-Cache. */\n"),
])

# ---------------------------------------------------------------------------
# 0003: GICv3 Group 1 routing and timer INTID.
# ---------------------------------------------------------------------------
s.patch("0003-a03-gic-v3-timer.patch", [
    ("pexpert/arm/pe_fiq.c",
     "\t// Configure timers and legacy FIQ to be group 0\n"
     "\tgicr_write32(GICR_IGROUPR0, 0x81FFFFFF);\n\n"
     "\t// Enable PPI 27\n"
     "\tgicr_write32(GICR_ISENABLER0, (1 << 27));\n",
     "#if defined(A03)\n"
     "\t/*\n"
     "\t * TrustZone owns Group 0 on the T606; non-secure writes to it are\n"
     "\t * ignored. Our timer and SGIs are Group 1 NS and arrive as IRQs.\n"
     "\t */\n"
     "\tgicr_write32(GICR_IGROUPR0, 0xFFFFFFFF);\n"
     "\tfor (unsigned int i = 0; i < 32; i += 4) {\n"
     "\t\tgicr_write32(GICR_IPRIORITYR0 + i, 0xA0A0A0A0);\n"
     "\t}\n"
     "\tgicr_write32(GICR_ISENABLER0,\n"
     "\t    (1U << A03_VTIMER_INTID) | (1U << A03_IPI_SGI));\n"
     "#else\n"
     "\t// Configure timers and legacy FIQ to be group 0\n"
     "\tgicr_write32(GICR_IGROUPR0, 0x81FFFFFF);\n\n"
     "\t// Enable PPI 27\n"
     "\tgicr_write32(GICR_ISENABLER0, (1 << 27));\n"
     "#endif /* A03 */\n"),

    ("pexpert/arm/pe_fiq.c",
     "\t__builtin_arm_wsr64(\"ICC_BPR0_EL1\", 0);\n",
     "#if defined(A03)\n"
     "\t__builtin_arm_wsr64(\"ICC_BPR1_EL1\", 0);\n"
     "#else\n"
     "\t__builtin_arm_wsr64(\"ICC_BPR0_EL1\", 0);\n"
     "#endif /* A03 */\n"),

    ("pexpert/arm/pe_fiq.c",
     "\t// Enable the forwarding of the vtimer interrupt\n"
     "\tuint32_t gicd_ctlr = gicd_read32(GICD_CTLR);\n"
     "\tgicd_ctlr |= GICD_CTLR_ENABLEGRP0;\n"
     "\tgicd_write32(GICD_CTLR, gicd_ctlr);\n"
     "\t__builtin_arm_wsr64(\"ICC_IGRPEN0_EL1\", 1);\n"
     "\t__builtin_arm_isb(ISB_SY);\n",
     "#if defined(A03)\n"
     "\t/* LK/ABL leaves only ARE_NS set; enable both non-secure groups. */\n"
     "\tuint32_t gicd_ctlr = gicd_read32(GICD_CTLR);\n"
     "\tgicd_ctlr |= GICD_CTLR_ARE_NS | GICD_CTLR_ENABLEGRP1A | GICD_CTLR_ENABLEGRP1;\n"
     "\tgicd_write32(GICD_CTLR, gicd_ctlr);\n"
     "\twhile (gicd_read32(GICD_CTLR) & GICD_CTLR_RWP) {\n"
     "\t\t;\n"
     "\t}\n"
     "\t__builtin_arm_wsr64(\"ICC_IGRPEN1_EL1\", 1);\n"
     "\t__builtin_arm_isb(ISB_SY);\n"
     "#else\n"
     "\t// Enable the forwarding of the vtimer interrupt\n"
     "\tuint32_t gicd_ctlr = gicd_read32(GICD_CTLR);\n"
     "\tgicd_ctlr |= GICD_CTLR_ENABLEGRP0;\n"
     "\tgicd_write32(GICD_CTLR, gicd_ctlr);\n"
     "\t__builtin_arm_wsr64(\"ICC_IGRPEN0_EL1\", 1);\n"
     "\t__builtin_arm_isb(ISB_SY);\n"
     "#endif /* A03 */\n"),

    ("osfmk/arm64/sleh.c",
     "#include <arm/trap_internal.h> /* for IS_ARM_GDB_TRAP() et al */\n",
     "#include <arm/trap_internal.h> /* for IS_ARM_GDB_TRAP() et al */\n"
     "#include <arm/machine_cpu.h>\n"),

    ("osfmk/arm64/sleh.c",
     "\tsleh_interrupt_handler_prologue(state, DBG_INTR_TYPE_OTHER);\n\n"
     "#if USE_APPLEARMSMP\n",
     "#if defined(A03)\n"
     "\t/* GIC Group 1 NS: timer, SGIs and every device interrupt land here. */\n"
     "\tuint64_t iar = __builtin_arm_rsr64(\"ICC_IAR1_EL1\");\n"
     "\tuint32_t intid = (uint32_t)(iar & 0xFFFFFF);\n\n"
     "\tif (intid >= 1020 && intid <= 1023) {\n"
     "\t\treturn;\n"
     "\t}\n"
     "\tif (intid == A03_VTIMER_INTID) {\n"
     "\t\tsleh_interrupt_handler_prologue(state, DBG_INTR_TYPE_TIMER);\n"
     "\t\tcdp->cpu_decrementer = -1; /* Large */\n"
     "\t\tml_interrupt_masked_debug_start(rtclock_intr, DBG_INTR_TYPE_TIMER);\n"
     "\t\trtclock_intr(TRUE);\n"
     "\t\tml_interrupt_masked_debug_end();\n"
     "\t\t__builtin_arm_wsr64(\"ICC_EOIR1_EL1\", iar);\n"
     "\t} else if (intid < 16) {\n"
     "\t\tsleh_interrupt_handler_prologue(state, DBG_INTR_TYPE_IPI);\n"
     "\t\t/* Ack first so a second SGI raised meanwhile is not lost. */\n"
     "\t\t__builtin_arm_wsr64(\"ICC_EOIR1_EL1\", iar);\n"
     "\t\t__builtin_arm_isb(ISB_SY);\n"
     "\t\tcpu_signal_handler();\n"
     "\t} else {\n"
     "\t\tsleh_interrupt_handler_prologue(state, DBG_INTR_TYPE_OTHER);\n"
     "\t\tif (cdp->interrupt_handler) {\n"
     "\t\t\tcdp->interrupt_handler(cdp->interrupt_target,\n"
     "\t\t\t    cdp->interrupt_refCon,\n"
     "\t\t\t    cdp->interrupt_nub,\n"
     "\t\t\t    intid);\n"
     "\t\t}\n"
     "\t\t__builtin_arm_wsr64(\"ICC_EOIR1_EL1\", iar);\n"
     "\t}\n"
     "\t__builtin_arm_isb(ISB_SY);\n"
     "#else\n"
     "\tsleh_interrupt_handler_prologue(state, DBG_INTR_TYPE_OTHER);\n\n"
     "#if USE_APPLEARMSMP\n"),

    ("osfmk/arm64/sleh.c",
     "\t    cdp->interrupt_source);\n"
     "#endif\n"
     "#endif /* SWEET */\n\n"
     "\tentropy_collect();\n",
     "\t    cdp->interrupt_source);\n"
     "#endif\n"
     "#endif /* A03 */\n"
     "#endif /* SWEET */\n\n"
     "\tentropy_collect();\n"),

    ("osfmk/arm64/start.s",
     "#if !VMAPPLE && !defined(SWEET)\n"
     "\tMOV64\tx1, SCTLR_EL1_DEFAULT\n"
     "\tcmp\t\tx0, x1\n"
     "\tbne\t\t.\n"
     "#endif /* !VMAPPLE && !SWEET */\n",
     "#if !VMAPPLE && !defined(SWEET) && !defined(A03)\n"
     "\tMOV64\tx1, SCTLR_EL1_DEFAULT\n"
     "\tcmp\t\tx0, x1\n"
     "\tbne\t\t.\n"
     "#endif /* !VMAPPLE && !SWEET && !A03 */\n"),
])

# ---------------------------------------------------------------------------
# 0004: MASTER config for the open-source arm64 asm/pmap.
# ---------------------------------------------------------------------------
master = s.read("config/MASTER.arm64.MacOSX")
master = ("# A03 (Unisoc T606) bring-up config.\n"
          "# MASTER.arm64.MacOSX with the KDK's closed SoC objects replaced by\n"
          "# the open-source arm64 asm/pmap and with Apple PMU counters removed.\n"
          + master)
master = master.replace(
    "config_requires_u32_munging config_delay_idle_sleep config_proc_udata_storage config_uexc config_darkboot ARM_EXTRAS_BASE ]",
    "config_requires_u32_munging config_delay_idle_sleep config_proc_udata_storage config_uexc config_darkboot nos_arm_asm nos_arm_pmap ARM_EXTRAS_BASE ]", 1)
master = master.replace(
    "#  CPU_COUNTERS_BASE = [ config_cpu_counters config_pervasive_cpi config_pervasive_energy ]",
    "#  CPU_COUNTERS_BASE = [ ]", 1)
master = master.replace(
    "config_voucher_deprecated PARAVIRT_BASE ]",
    "config_voucher_deprecated PARAVIRT_BASE config_ledger_interval_max ]", 1)
# SWEET pulls in the page-granular zone allocator; without it several VM
# counters and pmap symbols stay undefined at link time.
master = master.replace(
    "#  VM_DEV =         [ VM_BASE dynamic_codesigning VM_EXTRA_DEV ]",
    "#  VM_DEV =         [ VM_BASE dynamic_codesigning pgzalloc VM_EXTRA_DEV ]", 1)
master = master.replace(
    "#  VM_DEBUG =       [ VM_BASE dynamic_codesigning VM_EXTRA_DEV ]",
    "#  VM_DEBUG =       [ VM_BASE dynamic_codesigning pgzalloc VM_EXTRA_DEV ]", 1)
for line in ("#  SECURITY_RELEASE = [ SECURITY_BASE ]",
             "#  SECURITY_DEV   =   [ SECURITY_BASE ]",
             "#  SECURITY_DEBUG =   [ SECURITY_BASE ]"):
    master = master.replace(line, line[:-1] + " config_bti_telemetry ]", 1)

s.patch("0004-a03-master-config.patch", [
    ("config/MASTER.arm64.a03", "", master),

    # Bergamota's continuous-splash framebuffer is SWEET/Qualcomm-specific:
    # it hardcodes another panel and uses boot args we do not provide. Keep it
    # out of the A03 slice; our own early console draws at 0x9E000000.
    ("iokit/conf/files.arm64",
     "iokit/Kernel/arm/SweetFramebuffer.cpp                            optional iokitcpp\n",
     "iokit/Kernel/arm/SweetFramebuffer.cpp                            optional sweet_iokit\n"),

    # The OSS tag lists this file but does not publish it.
    ("osfmk/conf/files.arm64",
     "osfmk/arm64/amcc_rorgn_pv_ctrr.c optional nos_arm_asm\n",
     "# A03: amcc_rorgn_pv_ctrr.c (Apple paravirtualized CTRR) is not published in xnu-12377.121.6\n"
     "# osfmk/arm64/amcc_rorgn_pv_ctrr.c optional nos_arm_asm\n"),

    ("osfmk/conf/files.arm64",
     "osfmk/arm64/arm_vm_init.c\toptional config_pmap_ppl\n",
     "osfmk/arm64/arm_vm_init.c\toptional config_pmap_ppl\n"
     "osfmk/arm64/a03_early.c\t\tstandard\n"),
])

# ---------------------------------------------------------------------------
# 0005: early framebuffer console, valid while bootstrap TTBR0 is live.
# ---------------------------------------------------------------------------
A03_EARLY_H = r'''/* Early screen diagnostics, valid only while the bootstrap TTBR0 is live. */
#ifndef _ARM64_A03_EARLY_H_
#define _ARM64_A03_EARLY_H_

#include <pexpert/arm64/board_config.h>
#include <stdarg.h>

#if defined(A03)
void a03_early_mark(unsigned int stage, const char *label);
void a03_early_putc(char c);
void a03_early_panic(const char *fmt, va_list *args);
void a03_early_disable(void);
#else
static inline void a03_early_mark(unsigned int stage, const char *label)
{
	(void)stage;
	(void)label;
}
static inline void a03_early_disable(void) {}
#endif

#endif /* !_ARM64_A03_EARLY_H_ */
'''

A03_EARLY_C = r'''/*
 * A03 bootstrap console. No allocation, locks, DT parsing or per-CPU state:
 * panic() can reach this before a current thread exists. start.s maps the boot
 * framebuffer VA=PA as Normal Non-Cacheable; this mapping dies with TTBR0.
 */
#include <arm64/a03_early.h>

#if defined(A03)
#include <stdint.h>
#include <kern/misc_protos.h>

#define EARLY_FB         ((volatile uint32_t *)(uintptr_t)A03_FB_PHYS)
#define EARLY_WIDTH      A03_FB_WIDTH
#define EARLY_HEIGHT     A03_FB_HEIGHT
#define EARLY_STRIDE     (A03_FB_STRIDE / 4)
#define EARLY_SCALE      2u
#define EARLY_CELL_W     (8u * EARLY_SCALE)
#define EARLY_CELL_H     (16u * EARLY_SCALE)
#define EARLY_TOP        (EARLY_HEIGHT - 32u)
#define EARLY_ROWS       (EARLY_TOP / EARLY_CELL_H)
#define EARLY_COLS       (EARLY_WIDTH / EARLY_CELL_W)

#define EARLY_FG         0xffffffffu   /* BGRA: white, A=0xff */
#define EARLY_BG         0xff000000u   /* BGRA: black, A=0xff */

extern unsigned char iso_font[256 * 16];

static unsigned int early_row, early_col;
static unsigned int early_started, early_disabled, early_panicking;

static void
a03_early_clear_row(void)
{
	for (unsigned int y = 0; y < EARLY_CELL_H; y++) {
		volatile uint32_t *line = EARLY_FB + (early_row * EARLY_CELL_H + y) * EARLY_STRIDE;
		for (unsigned int x = 0; x < EARLY_WIDTH; x++) {
			line[x] = EARLY_BG;
		}
	}
}

void
a03_early_putc(char c)
{
	if (early_disabled) {
		return;
	}
	if (!early_started) {
		early_started = 1;
		a03_early_clear_row();
	}
	if (c == '\r') {
		early_col = 0;
		return;
	}
	if (c == '\n' || early_col == EARLY_COLS) {
		early_col = 0;
		early_row = (early_row + 1) % EARLY_ROWS;
		a03_early_clear_row();
		if (c == '\n') {
			return;
		}
	}
	const unsigned char *glyph = iso_font + (unsigned char)c * 16;
	for (unsigned int gy = 0; gy < 16; gy++) {
		for (unsigned int sy = 0; sy < EARLY_SCALE; sy++) {
			volatile uint32_t *line = EARLY_FB +
			    (early_row * EARLY_CELL_H + gy * EARLY_SCALE + sy) * EARLY_STRIDE +
			    early_col * EARLY_CELL_W;
			for (unsigned int gx = 0; gx < 8; gx++) {
				uint32_t pixel = (glyph[gy] & (1u << gx)) ? EARLY_FG : EARLY_BG;
				for (unsigned int sx = 0; sx < EARLY_SCALE; sx++) {
					line[gx * EARLY_SCALE + sx] = pixel;
				}
			}
		}
	}
	early_col++;
	__asm__ volatile("dsb sy" ::: "memory");
}

static void
a03_early_string(const char *str)
{
	while (*str) {
		a03_early_putc(*str++);
	}
}

void
a03_early_mark(unsigned int stage, const char *label)
{
	if (early_disabled || stage > 8) {
		return;
	}
	uint32_t color = 0xff00ff00u | (stage * 28u << 16);
	for (unsigned int y = EARLY_TOP; y < EARLY_HEIGHT; y++) {
		for (unsigned int x = stage * 80u; x < (stage + 1) * 80u; x++) {
			EARLY_FB[y * EARLY_STRIDE + x] = color;
		}
	}
	a03_early_string("A03 EARLY ");
	a03_early_putc((char)('0' + stage));
	a03_early_string(": ");
	a03_early_string(label);
	a03_early_putc('\n');
}

void
a03_early_panic(const char *fmt, va_list *args)
{
	if (early_disabled || early_panicking) {
		return;
	}
	early_panicking = 1;
	a03_early_string("\nA03 EARLY PANIC: ");
	va_list copy;
	va_copy(copy, *args);
	_doprnt(fmt, &copy, a03_early_putc, 16);
	va_end(copy);
	a03_early_putc('\n');
	__asm__ volatile("dsb sy" ::: "memory");
}

void
a03_early_disable(void)
{
	a03_early_mark(8, "leaving bootstrap TTBR0");
	early_disabled = 1;
	__asm__ volatile("dsb sy" ::: "memory");
}
#endif /* A03 */
'''

def a03_band(stage, color):
    """Straight-line framebuffer band for start.s (no stack, no C, no macros)."""
    return (
        f"\t/* A03 progress band {stage}: bottom row, 80x32 px. */\n"
        f"\tMOV64\tx0, (0x9e000000 + 1568 * 2880 + {stage * 320})\n"
        f"\tMOV64\tx1, {color}\n"
        f"\tmov\t\tx2, #32\n"
        f"La03_b{stage}_row:\n"
        f"\tmov\t\tx3, #80\n"
        f"\tmov\t\tx5, x0\n"
        f"La03_b{stage}_pix:\n"
        f"\tstr\t\tw1, [x5], #4\n"
        f"\tsubs\tx3, x3, #1\n"
        f"\tb.ne\tLa03_b{stage}_pix\n"
        f"\tadd\t\tx0, x0, #2880\n"
        f"\tsubs\tx2, x2, #1\n"
        f"\tb.ne\tLa03_b{stage}_row\n"
        f"\tdsb\t\tsy\n"
    )


s.patch("0005-a03-early-framebuffer.patch", [
    ("osfmk/arm64/a03_early.h", "", A03_EARLY_H),
    ("osfmk/arm64/a03_early.c", "", A03_EARLY_C),

    # Stage 0/1: before any page tables, VBAR or stacks are touched.
    ("osfmk/arm64/start.s",
     "\tmov\t\tx20, x0\n\tmov\t\tx21, #0\n\n#if defined(SWEET)\n",
     "\tmov\t\tx20, x0\n\tmov\t\tx21, #0\n\n"
     "#if defined(A03)\n"
     + a03_band(0, "0xffff00ff")      # magenta: entry
     + a03_band(1, "0xffff0000")      # red: boot args saved
     + "#endif /* A03 */\n\n"
     "#if defined(SWEET)\n"),

    # Stage 2: boot args read, stacks set, just before bootstrap page tables.
    ("osfmk/arm64/start.s",
     "\tmov\t\tx4, x0\n\tmov\t\tx14, x22\n\tmov\t\tx15, x23\n",
     "#if defined(A03)\n"
     + a03_band(2, "0xffffff00")      # yellow: stacks ready
     + "#endif /* A03 */\n"
     "\tmov\t\tx4, x0\n\tmov\t\tx14, x22\n\tmov\t\tx15, x23\n"),

    # Stage 3: common_start reached (TCR/TTBR/MAIR still ahead).
    ("osfmk/arm64/start.s",
     "common_start:\n\n#if HAS_NEX_PG\n",
     "common_start:\n\n"
     "#if defined(A03)\n"
     + a03_band(3, "0xff00ffff")      # cyan: common_start
     + "#endif /* A03 */\n\n"
     "#if HAS_NEX_PG\n"),

    # Stage 4: immediately before SCTLR_EL1 (MMU still off).
    ("osfmk/arm64/start.s",
     "\t// Enable caches, MMU, ROP and JOP\n",
     "#if defined(A03)\n"
     + a03_band(4, "0xff0000ff")      # blue: about to enable MMU
     + "#endif /* A03 */\n"
     "\t// Enable caches, MMU, ROP and JOP\n"),

    # Stage 5: after SCTLR_EL1 (MMU on). 0x9e000000 is in the V=P map.
    ("osfmk/arm64/start.s",
     "\tMSR_SCTLR_EL1_X0\n\tisb\t\tsy\n",
     "\tMSR_SCTLR_EL1_X0\n\tisb\t\tsy\n"
     "#if defined(A03)\n"
     + a03_band(5, "0xffffffff")      # white: MMU enabled
     + "#endif /* A03 */\n"),

    # Add the framebuffer to the existing V=P L2 table. RAM and FB share L1.
    ("osfmk/arm64/start.s",
     "\tcreate_bootstrap_mapping x14, x15, x5, x3, x2, x9, x10, x11, x12, x13\n\n#if defined(SWEET)\n",
     "\tcreate_bootstrap_mapping x14, x15, x5, x3, x2, x9, x10, x11, x12, x13\n\n"
     "#if defined(A03)\n"
     "\t/*\n"
     "\t * Splash FB: one Normal-NC block in the existing V=P L2 table.\n"
     "\t * 0x9e000000 and RAM below 4GB share the first V=P L1 entry; calling\n"
     "\t * create_bootstrap_mapping again would replace the RAM L2 table. With\n"
     "\t * 16K pages that table is bootstrap_pagetables + 2*PGBYTES.\n"
     "\t */\n"
     "\tMOV64\tx10, 0x9e000000\n"
     "\tMOV64\tx11, (ARM_TTE_TYPE_BLOCK | ARM_TTE_VALID | ARM_TTE_BLOCK_SH(SH_OUTER_MEMORY) | ARM_TTE_BLOCK_ATTRINDX(CACHE_ATTRINDX_WRITECOMB) | ARM_TTE_BLOCK_AF | ARM_TTE_BLOCK_PNX | ARM_TTE_BLOCK_NX)\n"
     "\torr\t\tx11, x11, x10\n"
     "\tand\t\tx12, x10, #(ARM_TT_L2_INDEX_MASK)\n"
     "\tlsr\t\tx12, x12, #(ARM_TT_L2_SHIFT)\n"
     "\tadd\t\tx13, x25, #(2 * PGBYTES)\n"
     "\tstr\t\tx11, [x13, x12, lsl #TTE_SHIFT]\n"
     "#endif /* A03 */\n\n"
     "#if defined(SWEET)\n"),

    ("osfmk/arm/arm_init.c",
     "#include <arm64/proc_reg.h>\n",
     "#include <arm64/proc_reg.h>\n#include <arm64/a03_early.h>\n"),

    ("osfmk/arm/arm_init.c",
     "\tDTEntry chosen = NULL;\n\tunsigned int dt_entry_size = 0;\n\n\tarm_slide_rebase_and_sign_image();\n",
     "\tDTEntry chosen = NULL;\n\tunsigned int dt_entry_size = 0;\n\n"
     "\ta03_early_mark(1, \"arm_init entered (MMU on)\");\n\n"
     "\tarm_slide_rebase_and_sign_image();\n"),

    ("osfmk/arm/arm_init.c",
     "\tPE_init_platform(FALSE, args); /* Get platform expert set up */\n",
     "\tPE_init_platform(FALSE, args); /* Get platform expert set up */\n"
     "\ta03_early_mark(2, \"PE_init_platform done\");\n"),

    ("osfmk/arm/arm_init.c",
     "\tml_parse_cpu_topology();\n",
     "\tml_parse_cpu_topology();\n\ta03_early_mark(3, \"ml_parse_cpu_topology done\");\n"),

    ("osfmk/arm/arm_init.c",
     "\tcpu_bootstrap();\n\n\trtclock_early_init();\n",
     "\tcpu_bootstrap();\n\ta03_early_mark(4, \"cpu_bootstrap done\");\n\n\trtclock_early_init();\n"),

    ("osfmk/arm/arm_init.c",
     "\tkernel_startup_bootstrap();\n",
     "\tkernel_startup_bootstrap();\n\ta03_early_mark(5, \"kernel_startup_bootstrap done\");\n"),

    ("osfmk/arm/arm_init.c",
     "\tcpu_init();\n\n\tprocessor_bootstrap();\n",
     "\tcpu_init();\n\ta03_early_mark(6, \"cpu_init done\");\n\n\tprocessor_bootstrap();\n"),

    ("osfmk/arm/arm_init.c",
     "\tarm_vm_init(xmaxmem, args);\n",
     "\ta03_early_mark(7, \"entering arm_vm_init\");\n\tarm_vm_init(xmaxmem, args);\n"),

    ("osfmk/arm64/arm_vm_init.c",
     "#include <arm64/lowglobals.h>\n",
     "#include <arm64/lowglobals.h>\n#include <arm64/a03_early.h>\n"),

    ("osfmk/arm64/arm_vm_init.c",
     "\tml_enable_monitor();\n\n\tset_mmu_ttb(invalid_ttep & TTBR_BADDR_MASK);\n",
     "\tml_enable_monitor();\n\n"
     "\t/* The FB VA=PA mapping belongs to the outgoing TTBR0. */\n"
     "\ta03_early_disable();\n"
     "\tset_mmu_ttb(invalid_ttep & TTBR_BADDR_MASK);\n"),

    ("osfmk/kern/debug.c",
     "#include <console/serial_protos.h>\n",
     "#include <console/serial_protos.h>\n"
     "#if defined(__arm64__)\n#include <arm64/a03_early.h>\n#endif\n"),

    ("osfmk/kern/debug.c",
     "    uint64_t panic_options_mask, void *panic_data_ptr, unsigned long panic_caller, const char *panic_initiator)\n"
     "{\n"
     "#pragma clang diagnostic pop\n",
     "    uint64_t panic_options_mask, void *panic_data_ptr, unsigned long panic_caller, const char *panic_initiator)\n"
     "{\n"
     "#pragma clang diagnostic pop\n\n"
     "#if defined(A03)\n"
     "\t/* No CPU/thread/debugger state is needed for this first panic copy. */\n"
     "\ta03_early_panic(panic_format_str, panic_args);\n"
     "#endif /* A03 */\n"),
])

# ---------------------------------------------------------------------------
# 0006: stubs for Apple-internal headers absent from the OSS drop.
# ---------------------------------------------------------------------------
SART_H = r'''/*
 * Apple's SART (IOMMU for NVMe/ANS) header is not in the open source drop.
 * There is no SART on the T606; bootstrap is a no-op.
 */
#ifndef _ARM64_PPL_SART_H_
#define _ARM64_PPL_SART_H_

static inline void
sart_bootstrap(void)
{
}

#endif /* _ARM64_PPL_SART_H_ */
'''

UAT_H = r'''/*
 * Apple's UAT (GPU unified address translator) header is not in the open
 * source drop. There is no UAT on the T606; bootstrap is a no-op.
 */
#ifndef _ARM64_PPL_UAT_H_
#define _ARM64_PPL_UAT_H_

static inline void
uat_bootstrap(void)
{
}

#endif /* _ARM64_PPL_UAT_H_ */
'''

TUNABLES_S = r'''/*
 * Apple's per-SoC CPU tunables (implementation-defined HID/ACC register
 * settings applied in start.s) are not in the open source drop and do not
 * exist on Cortex-A75/A55. APPLY_TUNABLES does nothing.
 */
.macro APPLY_TUNABLES midr, tmp1, tmp2
.endmacro
'''

s.patch("0006-a03-stub-apple-internal-headers.patch", [
    ("osfmk/arm64/ppl/sart.h", "", SART_H),
    ("osfmk/arm64/ppl/uat.h", "", UAT_H),
    ("osfmk/arm64/tunables/tunables.s", "", TUNABLES_S),
])


def drop_lines(rel, needles):
    """Return (whole_file, file_with_matching_lines_removed)."""
    text = s.read(rel)
    filtered = "".join(
        line for line in text.splitlines(True)
        if not any(needle in line for needle in needles)
    )
    return rel, text, filtered


# ---------------------------------------------------------------------------
# 0007: do not export symbols that only exist in closed Apple SoC libraries.
# ---------------------------------------------------------------------------
s.patch("0007-a03-drop-apple-soc-exports.patch", [
    drop_lines("config/Private.arm64.exports", [
        "_pmap_iommu", "_nvme_ppl_get_desc", "_sart_get_desc",
        "_t8020dart_", "_t6000dart_", "_t8110dart_", "_sptm_gen3dart_",
        "_ml_amcc_error_inject_register", "_ml_dcs_error_inject_register",
        "_ml_mem_fault_report_enable_register", "_uat_get_desc",
        "IOUnifiedAddressTranslator",
    ]),
    drop_lines("config/Private.exports", [
        "_pmap_has_iofilter_protected_write", "_pmap_cs_configuration",
    ]),
])

# ---------------------------------------------------------------------------
# 0008: minimal device-tree platform expert.
# ---------------------------------------------------------------------------
A03_PE = r'''/*
 * Minimal device-tree platform expert for the Galaxy A03 (sprd,ums9230).
 * Uses XNU's normal platform and nub initialization. Interrupt and power
 * management services come from separate drivers.
 */
#include <pexpert/arm64/board_config.h>

#if defined(A03)
#include <IOKit/IOPlatformExpert.h>
#include <IOKit/IODeviceTreeSupport.h>
#include <IOKit/IOLib.h>

class A03PlatformExpert : public IODTPlatformExpert {
	OSDeclareDefaultStructors(A03PlatformExpert);

public:
	bool start(IOService *provider) APPLE_KEXT_OVERRIDE;
	void processTopLevel(IORegistryEntry *root) APPLE_KEXT_OVERRIDE;
	const char *deleteList(void) APPLE_KEXT_OVERRIDE;
	const char *excludeList(void) APPLE_KEXT_OVERRIDE;
	bool getTargetName(char *name, int maxLength) APPLE_KEXT_OVERRIDE;
	bool getProductName(char *name, int maxLength) APPLE_KEXT_OVERRIDE;
};

OSDefineMetaClassAndStructors(A03PlatformExpert, IODTPlatformExpert);

bool
A03PlatformExpert::start(IOService *provider)
{
	IOLog("A03: starting device-tree platform expert\n");
	if (!IODTPlatformExpert::start(provider)) {
		return false;
	}
	registerService();
	IOLog("A03: platform expert registered\n");
	return true;
}

const char *
A03PlatformExpert::deleteList(void)
{
	return "()";
}

const char *
A03PlatformExpert::excludeList(void)
{
	return "('chosen', 'defaults', 'cpus', 'options')";
}

void
A03PlatformExpert::processTopLevel(IORegistryEntry *root)
{
	/* No Apple NVRAM /options node on this board: publish the DT nodes as-is. */
	IORegistryEntry *cpus = root->childFromPath("cpus", gIODTPlane);
	if (cpus != NULL) {
		createNubs(this, IODTFindMatchingEntries(cpus, kIODTExclusive, NULL));
		cpus->release();
	}
	createNubs(this, IODTFindMatchingEntries(root, kIODTExclusive, excludeList()));
}

bool
A03PlatformExpert::getTargetName(char *name, int maxLength)
{
	if (name == NULL || maxLength <= 0) {
		return false;
	}
	strlcpy(name, "a03", (size_t)maxLength);
	return true;
}

bool
A03PlatformExpert::getProductName(char *name, int maxLength)
{
	if (name == NULL || maxLength <= 0) {
		return false;
	}
	strlcpy(name, "Galaxy A03", (size_t)maxLength);
	return true;
}
#endif /* A03 */
'''

s.patch("0008-a03-device-tree-platform-expert.patch", [
    ("iokit/Kernel/arm/A03PlatformExpert.cpp", "", A03_PE),
    ("iokit/KernelConfigTables.cpp",
     "const char * gIOKernelConfigTables =\n    \"(\"\n",
     "const char * gIOKernelConfigTables =\n    \"(\"\n"
     "#if defined(ARM64_BOARD_CONFIG_A03)\n"
     "    \"   {\"\n"
     "    \"     'IOClass'         = A03PlatformExpert;\"\n"
     "    \"     'IOProviderClass' = IOPlatformExpertDevice;\"\n"
     "    \"     'IONameMatch'     = 'sprd,ums9230';\"\n"
     "    \"     'IOProbeScore'    = 10000:32;\"\n"
     "    \"   },\"\n"
     "#endif\n"),
    ("iokit/conf/files.arm64",
     "iokit/Kernel/arm/AppleARMSMP.cpp    \t\t\t\t\toptional iokitcpp\n",
     "iokit/Kernel/arm/AppleARMSMP.cpp    \t\t\t\t\toptional iokitcpp\n"
     "# A03 device-tree platform (empty translation unit on other boards)\n"
     "iokit/Kernel/arm/A03PlatformExpert.cpp                         optional iokitcpp\n"),
])

# ---------------------------------------------------------------------------
# 0009: ramdisk-root fixes needed by mockfs without IOStorageFamily.
# ---------------------------------------------------------------------------
s.patch("0009-a03-ramdisk-root-fixes.patch", [
    ("bsd/miscfs/mockfs/mockfs_fsnode.c",
     "\t*fsnpp = kalloc_type(mockfs_fsnode_t, Z_WAITOK | Z_ZERO | Z_NOFAIL);\n",
     "\t*fsnpp = kalloc_type(struct mockfs_fsnode, Z_WAITOK | Z_ZERO | Z_NOFAIL);\n"),
    ("bsd/miscfs/mockfs/mockfs_fsnode.c",
     "\tkfree_type(mockfs_fsnode_t, fsnp);\n",
     "\tkfree_type(struct mockfs_fsnode, fsnp);\n"),
    ("iokit/Kernel/IOService.cpp",
     "\tioblockstoragedriverClass = OSMetaClass::getMetaClassWithName(gIOBlockStorageDriverKey);\n"
     "\tassert(ioblockstoragedriverClass);\n",
     "\tioblockstoragedriverClass = OSMetaClass::getMetaClassWithName(gIOBlockStorageDriverKey);\n"
     "#if defined(ARM64_BOARD_CONFIG_A03)\n"
     "\t/* No IOStorageFamily here: a RAM-disk root is not block media. */\n"
     "\tif (!ioblockstoragedriverClass) {\n"
     "\t\troot = NULL;\n"
     "\t}\n"
     "#else\n"
     "\tassert(ioblockstoragedriverClass);\n"
     "#endif\n"),
])

# ---------------------------------------------------------------------------
# 0010: machine routines normally supplied by the closed KDK SoC archive.
# ---------------------------------------------------------------------------
A03_STUBS = r'''/*
 * Machine routines that xnu-12377 expects from Apple's closed per-SoC support
 * library (KernelSupport/lib<SoC>.os.<config>.a), which A03 does not link.
 */
#include <arm/machine_routines.h>

#if defined(ARM64_BOARD_CONFIG_A03)
/* hw.features sysctl: no Apple fuses on this board. */
boolean_t
ml_device_is_prod_fused(void)
{
	return FALSE;
}
#endif /* ARM64_BOARD_CONFIG_A03 */
'''

s.patch("0010-a03-platform-stubs.patch", [
    ("osfmk/arm64/a03_platform_stubs.c", "", A03_STUBS),
    ("osfmk/conf/files.arm64",
     "osfmk/arm64/a03_early.c\t\tstandard\n",
     "osfmk/arm64/a03_early.c\t\tstandard\n"
     "osfmk/arm64/a03_platform_stubs.c\tstandard\n"),
    ("osfmk/kern/exclaves.c",
     "#if __has_include(<Tightbeam/tightbeam.h>)\n",
     "/* A03: the KDK headers exist, but libTightbeam is not linked here. */\n"
     "#if __has_include(<Tightbeam/tightbeam.h>) && !defined(ARM64_BOARD_CONFIG_A03)\n"),
    ("osfmk/kern/exclaves.c",
     "#if __has_include(<Tightbeam/tightbeam.h>) && !defined(ARM64_BOARD_CONFIG_SWEET)\n",
     "#if __has_include(<Tightbeam/tightbeam.h>) && !defined(ARM64_BOARD_CONFIG_SWEET) && !defined(ARM64_BOARD_CONFIG_A03)\n"),
    # Bergamota's process sampler lives in a SWEET-only block of exception.c;
    # its caller in bsd/dev/sweet_sample.c is compiled for every board.
    ("osfmk/kern/exception.c",
     "#if defined(ARM64_BOARD_CONFIG_SWEET)\n",
     "#if defined(ARM64_BOARD_CONFIG_SWEET) || defined(ARM64_BOARD_CONFIG_A03)\n"),
    # Bergamota stubs ml_enable_monitor() only for SWEET; arm_vm_init() calls it
    # on every board. A03 has no PPL/monitor either, so reuse the empty stub.
    ("osfmk/arm64/machine_routines.c",
     "#if defined(SWEET)\n/*\n * sweet: arm_vm_init() calls this unconditionally;",
     "#if defined(SWEET) || defined(ARM64_BOARD_CONFIG_A03)\n/*\n * sweet/A03: arm_vm_init() calls this unconditionally;"),
])
