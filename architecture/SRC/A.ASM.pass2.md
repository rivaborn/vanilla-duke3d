# SRC/A.ASM — Enhanced Analysis

## Architectural Role

A.ASM is the **critical rendering path** of the Build Engine. It implements all pixel-writing primitives that ENGINE.C calls during portal-based 3D rendering. The file exemplifies 1990s x86 optimization: self-modifying code injects frame-specific parameters (stride, palette offsets, texture coordinates) into tight inner loops, eliminating branch mispredictions and parameter-passing overhead. The `mmxoverlay_` function patches entry points at runtime based on CPU detection (Pentium/Pentium II/MMX), enabling single-binary distribution across different x86 variants.

## Key Cross-References

### Incoming (who depends on this file)
- **SRC/drawing_routines/A.C**: Wraps `hlineasm4_`, `vlineasm1_`, `vlineasm4_`, `spritevline_` and related functions; provides C-callable interfaces with parameter validation
- **SRC/ENGINE.C**: Calls wrapped drawing routines during `drawrooms()`, `drawwalls()`, `drawsprite()`, and `florscan()/ceilscan()/wallscan()` per-frame loops
- **Globals consumed by setup functions**:
  - `_asm1`, `_asm2`, `_asm3`, `_asm4` (read/written by ENGINE.C between setup calls)
  - `_ylookup` (read during vline rendering; computed by ENGINE.C)
  - `_vplce`, `_vince`, `_palookupoffse`, `_bufplce` (arrays holding per-column state for parallel 4-column rendering)

### Outgoing (what this file depends on)
- **Globals from PRAGMAS.H and BUILD.H**: `_asm1`, `_asm2`, `_asm3`, `_asm4`, `_ebpbak`, `_espbak`, `_pow2char`, `_pow2long`
- **Globals from ENGINE.C**: `_ylookup` (scanline address lookup), `_vplce`, `_vince`, `_palookupoffse`, `_bufplce`
- **Globals from CACHE1D.C**: `_reciptable` (reciprocal table for slope perspective-correction)
- **Hardware**: Framebuffer writes via `edi`; FPU for slope calculations in `slopevlin_`

## Design Patterns & Rationale

### Self-Modifying Code for Parameter Injection
**Pattern**: Setup functions (`sethlinesizes_`, `setupvlineasm_`, `setupmvlineasm_`, `setuptvlineasm_`, `setupspritevline_`) patch literal operands (typically at offsets +1, +2, +3) in subsequent drawing routines before they execute.

**Rationale**: Eliminates per-pixel parameter reads. Instead of `mov eax, [ebx+offset]` in the inner loop, the offset is hardcoded in the instruction at setup time. This saves instruction fetch/decode cycles in the inner loop and keeps register pressure low. Typical parameters patched: bit shifts (xbits, ybits), palette offsets, buffer offsets.

**Trade-off**: Code maintainability vs. speed. Self-modifying code is hard to debug, profile, and extend, but was a critical technique for 1990s real-time graphics.

### CPU-Specific Code Overlays
**Pattern**: `mmxoverlay_` runs at engine init, detects CPU via CPUID (inline `dw 0a20fh`), and patches function entry points with `jmp` instructions to alternative implementations.

**Variants**:
- **Generic Pentium**: `hlineasm4_`, `vlineasm4_`, etc. (base path)
- **Pentium II/Pro**: `prohlineasm4_` (better throughput, uses `movzx` for 0-extension instead of separate zero ops), `provlineasm4_`
- **Pentium + MMX**: (placeholder; may patch other functions or enable SIMD hints)

**Rationale**: Different x86 microarchitectures have different instruction latencies and throughput. Pentium II/Pro benefit from fewer register stalls (e.g., `movzx` decode vs. separate zero/shift). MMX could theoretically accelerate 4-pixel-wide operations, though this file doesn't appear to use packed instructions.

### Batch-Oriented Parameter Model
Drawing happens in batches:
1. **Setup phase** (once per batch): Call `sethlinesizes_()`, `setupvlineasm_()` to patch code.
2. **Draw phase** (multiple calls): Call `hlineasm4_()`, `vlineasm4_()` with per-line parameters in registers/globals.
3. **Globals carry state**: `_vplce[4]` arrays maintain per-column texture coordinates across multiple calls to `vlineasm4_()`, allowing continuation without re-initialization.

**Rationale**: Amortizes setup overhead; reduces function-call frequency in the inner loop.

## Data Flow Through This File

### Horizontal Line Rendering (`hlineasm4_` / `prohlineasm4_`)
1. **Input**: 
   - `eax` = pixel count
   - `esi` = y-position (fixed-point)
   - `edx` = x-increment per pixel
   - `edi` = framebuffer position
   - Global `_asm1`, `_asm2` = position increments for next line
   - Patched shifts (hxsiz*, hysiz*, hmach*) inject xbits, ybits

2. **Inner Loop**:
   - Texture coordinate lookup: `shr eax, xbits; shld eax, edx, ybits` → 2D index into texture map
   - Palette lookup: `[eax+offset] → palette index`
   - Palette translation: `[paloffset+index] → 8-bit color`
   - Write to framebuffer
   - Decrement coordinates and pixel count

3. **Output**: Framebuffer at `[edi]` updated; `esi`/`edx` modified for next line

### Vertical 4-Column Rendering (`vlineasm4_` / `provlineasm4_`)
1. **Input**:
   - `ecx` = scanline count
   - `_ylookup[ecx*4]` = array of 4 scanline addresses
   - `_vplce[0..3]` = per-column texture y-coordinates (fixed-point)
   - `_vince[0..3]` = per-column y-increments
   - `_bufplce[0..3]` = per-column texture buffer base pointers
   - `_palookupoffse[0..3]` = per-column palette lookup table offsets

2. **Unrolled Loop** (highly parallel to exploit CPU execution units):
   - Each of 4 columns:
     - Lookup texture: `_bufplce[i] + (_vplce[i] >> shift) → color`
     - Lookup palette: `_palookupoffse[i] + color → output`
     - Write to scanline: `_ylookup[line*4+i] + i`
     - Increment `_vplce[i]` by `_vince[i]`
   - Repeat for all scanlines

3. **Output**: Framebuffer updated; `_vplce[0..3]` updated for next batch; allows continuation across multiple calls

### Masked & Translucent Variants
- **mvlineasm4_**: Skips pixels where texture value is 255 (transparency)
- **tvlineasm4_**: Looks up blended output via translucency table (secondary palette lookup)
- **Mechanism**: Same texture/palette pipeline, but with conditional writes or extra lookup stages

### Slope-Based Texture Mapping (`slopevlin_`)
1. **Input**: FPU stack value, bit shifts in registers, buffer/screen pointers
2. **Process**:
   - FPU converts floating-point screen coordinates to fixed-point texture coordinates
   - Uses reciprocal table for perspective-correct slope calculation
   - Updates globals `_globalx3`, `_globaly3`, `_asm1`, `_asm2` for ENGINE to use in subsequent line calculations
3. **Output**: Framebuffer writes; FPU state modified; globals updated for continuation

## Learning Notes

### Idiomatic to 1990s Rendering
- **Self-modifying code**: Now considered an anti-pattern (cache invalidation, branch prediction interference), but was essential before JIT and when code cache misses dominated. Modern engines use dynamic dispatch or code generation instead.
- **Register calling convention**: All parameters in `eax`–`edi` (no stack frames) maximizes CPU pipeline efficiency for inner-loop critical paths. Modern code prioritizes readability and stack frame unwinding (debugger support).
- **Fixed-point arithmetic**: Texture coordinates stored as 32-bit integers with implicit fractional bits (e.g., top 16 bits = integer, bottom 16 bits = fraction). Modern engines use floats or normalized coordinates, relying on FPU/SIMD.
- **Inline assembly macros disguised as code**: Functions like `setuphlineasm4_` are not really "functions"—they're code generators. The CPU detection pattern (`mmxoverlay_`) is a runtime linker.

### Architecture vs. Modern Practices
| 1990s Build Engine | Modern Engine |
|---|---|
| Self-modifying code for parameter injection | JIT compilation, template specialization, or dynamic dispatch |
| CPU detection via CPUID patch | Runtime dispatch to SIMD paths (AVX-512, NEON, etc.) |
| Register-constrained calling convention | ABI-compliant calling conventions; caller/callee-save semantics |
| Global state for batch parameters | Push/pop stack frames or thread-local structures |
| 8-bit palette + lookup table rendering | 32-bit direct RGBA with multi-channel swizzling |
| Unrolled manual loops (4 pixels at a time) | SIMD pack operations, compiler auto-vectorization |
| Pentium/Pentium II microarchitecture tuning | Portable IR (LLVM, MIR) with late-stage codegen |

### Connections to Game Engine Concepts
- **Perspective-correct texture mapping**: `slopevlin_` implements the reciprocal-based perspective correction seen in Quake and early 3D engines. Modern engines use hardware-accelerated GPUs (automatic perspective interpolation).
- **Portal visibility + software rasterization**: Unique to portal engines (Build, Doom, early Quake); combines BFS sector traversal with pixel-by-pixel drawing.
- **Batch-oriented rendering**: Similar to modern GPU command buffers—setup once, execute many times. Shows awareness of performance-critical batching even in 1990s software rendering.

## Potential Issues

1. **CPU Detection Hackery**: The inline CPUID opcode (`dw 0a20fh`) is fragile. Modern x86 detection uses proper instruction intrinsics or OS-level feature detection.
2. **Self-Modifying Code + Multicore**: On modern x86 (x86-64), self-modifying code requires careful cache invalidation (CLFLUSH). A Pentium 4 hyperthreading or modern multi-core CPU could see stale instruction fetches. This code assumes single-core or cooperative execution.
3. **Register Saturation**: The calling convention exhausts all general-purpose registers (eax–edi). Adding new features (e.g., per-pixel lighting) requires register spilling or significant refactoring.
4. **Hardcoded Framebuffer Stride**: Setup functions patch stride into instructions; changing resolution at runtime is expensive (requires re-patching all drawing routines).
5. **No Type Safety**: Assembly code provides no bounds checking or type guarantees. Buffer overflows in globals like `_vplce[4]` can corrupt arbitrary memory.
