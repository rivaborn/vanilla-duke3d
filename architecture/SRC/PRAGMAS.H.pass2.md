# SRC/PRAGMAS.H — Enhanced Analysis

## Architectural Role

This header is the low-level performance substrate enabling real-time 3D rendering, spatial math, and hardware I/O across the entire Build Engine. It bridges C code and bare-metal x86-32 capabilities through Watcom compiler pragmas, making fixed-point arithmetic, memory operations, and hardware timing directly available. Every subsystem that touches performance-critical paths—the 3D renderer (ENGINE.C), audio synthesis (K.ASM), resource cache (CACHE1D.C), and graphics output (VES2.H)—depends on these pragmas.

## Key Cross-References

### Incoming (who depends on this file)

- **ENGINE.C** (3D rendering core): calls `mulscale*`, `divscale*`, `dmulscale*`, `boundmulscale` for perspective-correct texture mapping, coordinate transformation, and interpolation in `drawrooms`, `wallscan`, `ceilscan`, `florscan`; uses `limitrate` for frame-rate capping
- **CACHE1D.C** (resource management): calls `copybufbyte`, `clearbuf` in `allocache`/`dfread`/`dfwrite` for LRU eviction and buffer management; uses `mulscale32` in allocache boundary calculations
- **K.ASM** (audio synthesis): references `sqr`, `mulscale` variants implicitly in comb filter operations; reads `timeroffs1mhz` state
- **A.ASM** (rendering primitives): uses mulscale results embedded in self-modifying code patches for texture fetch and blending
- **VES2.H** (video abstraction): calls I/O intrinsics (`inl`, `outl`) for VESA mode setup and palette DAC control
- **UTIL/TRANSPAL.C** (palette generation): calls `divscale16` for color lookup scaling, `clearbuf` for lookup table initialization
- **MULTI.C / MMULTI.C** (networking): calls I/O intrinsics for serial COM port and IPX hardware access
- **UTIL/EDITART.C** (tile editor): calls `drawpixel*`, `outp` for direct VGA graphics operations

### Outgoing (what this file depends on)

- **Watcom C compiler:** `#pragma aux` directives (x86-specific, compiler-version-dependent)
- **x86-32 CPU:** imul, shrd, idiv, mov instructions; assumes 32-bit registers and 64-bit multiply results (edx:eax pairs)
- **VGA hardware:** I/O ports 0x3da (retrace status), 0x3ce–0x3cf (graphics controller), video RAM at 0xa0000
- **8253 PIT timer:** I/O port 0x40–0x43 for 1MHz counter initialization and readback
- **PS/2 keyboard:** hardware interrupt (INT 0x09) for scan-code capture in timer/mouse code
- **Globals (implicitly from other files):** `timeroffs1mhz` (static state modified by `inittimer1mhz`, read by `gettime1mhz`/`deltatime1mhz`)

## Design Patterns & Rationale

**Inline Assembly Wrapper Pattern:**
Each pragma wraps a small, register-constrained x86 operation, letting C callers invoke it like a function. Watcom's `parm`/`modify`/`value` syntax ensures the C compiler understands register usage, enabling interprocedural optimization.

**Unrolled Specialization for Shift Constants:**
The 32 variants of `mulscale` (N=1–32) avoid the `ecx` parameter for constant shifts. `mulscale(a, b, n)` requires `ecx=n` at runtime; `mulscale5(a, b)` hard-codes shift 5 in the instruction stream (faster, avoids `ecx` assignment). This is a classic 1990s optimization for tight inner loops.

**Fixed-Point Accumulation:**
The `dmulscale` (dual) and `tmulscale` (triple) families compute weighted sums with normalized right-shift: `(a×b + c×d) >> N`. This pattern underpins:
- Lighting blending (color weight + texture weight)
- Bilinear interpolation in texture mapping
- Spatial audio panning (dry + wet channel mixing)

The `adc` (add with carry) instruction chains EDX:EAX pairs, allowing 64-bit intermediate sums before final normalization.

**Register Pinning & Constraint Declarations:**
`nomemory` tells the compiler these operations don't read/write memory, permitting aggressive scheduling. `parm [eax][edx][...]` and `modify exact [eax edx ...]` explicitly constrain registers, preventing hidden assumptions.

**Rationale for Dual/Triple Accumulate:**
Rather than issuing three separate `mulscale` calls (loading eax, edx, imul, shrd three times), a single `dmulscale` or `tmulscale` batches the multiplies and adds, reducing instruction count and register spills. Critical for inner-loop performance in 1990s graphics.

## Data Flow Through This File

1. **Perspective Transform Pathway:**
   - Vertex coordinates (eax, edx) → `mulscale*` → fixed-point screen coordinates → `drawpixel*` to framebuffer

2. **Texture Mapping Pathway:**
   - World coordinates + camera depth → `divscale*` → normalized texture indices → LUT lookup → palette index → `drawpixel*`

3. **Bilinear Lighting Pathway:**
   - (Red₁ × weight₁ + Red₂ × weight₂) >> bits → `dmulscale*` → blended red channel
   - (Green₁ × weight₁ + Green₂ × weight₂) >> bits → `dmulscale*` → blended green
   - (Blue₁ × weight₁ + Blue₂ × weight₂) >> bits → `dmulscale*` → blended blue
   - Result → `drawpixel*` to framebuffer

4. **Memory Eviction Pathway:**
   - LRU age array (esi) → `clearbuf` loop decrement → `copybufbyte` old→new block

5. **Frame Synchronization:**
   - Main loop → `limitrate` → read VGA port 0x3da → block on retrace bit → resume rendering

## Learning Notes

**Era-Specific Idiom:**
This file embodies 1990s real-time graphics constraints:
- No dedicated FPU (Pentium had one, but not guaranteed); fixed-point math avoids floating-point stalls
- CPU-bound rendering on 486/Pentium; every cycle matters
- Single-threaded, interrupt-driven (timer, keyboard, serial, audio interrupt handlers)
- Bare-metal VGA access (no OS abstraction)
- Self-modifying code in A.ASM patches at runtime using mulscale results to minimize per-scanline setup

**Modern Comparison:**
- Modern engines use GPU rasterization (eliminates fixed-point math, V-sync is implicit)
- SIMD replaces unrolled specialization (one `mulscale` for all shift counts)
- Floating-point is cheap (FPU on every modern CPU; SSE/AVX normalize it)
- Memory bandwidth (not math) is the bottleneck; pragma-level hand-tuning is moot
- Clock-cycle counting per-instruction is obsolete (pipelined, out-of-order CPUs make it hard to predict)

**Connections to Engine Concepts:**
- **Fixed-point as substrate:** A hallmark of 1990s game engines (Doom, Build); stores coordinates/texture coords as scaled integers, avoiding FPU latency
- **Weighted accumulation:** Core to any interpolation or blending algorithm; here explicitly unrolled into dual/triple forms
- **Portal rendering:** Requires fast perspective-correct divisions (divscale) for per-pixel coordinate transforms
- **Sprite/voxel rendering:** dmulscale handles weighted blends for translucency and lighting

## Potential Issues

- **Watcom C dependency:** Pragmas are compiler-specific; code won't compile on GCC or MSVC without translation
- **x86-32 assumption:** Pragmas assume 32-bit registers, 64-bit multiply (imul), and specific I/O port addressing; non-portable to ARM, MIPS, etc.
- **Overflow in intermediate products:** Large multiplicands (e.g., texture coordinate × scale factor × lighting) can exceed 64-bit; dmulscale/tmulscale assume the sum fits in 64 bits before right-shift. No saturation or overflow flag check.
- **Timer wraparound:** gettime1mhz reads a 28-bit counter (0x40, 0x41, 0x42, 0x43 in 16-bit mode); no explicit handling of wraparound in the pragma itself (handled by caller, inferring from divscale patterns)
- **Hardware I/O timing:** limitrate busy-waits on port 0x3da bit 0 (retrace), assuming VGA controller is present; will loop forever on non-VGA hardware or if 0x3da is unimplemented
