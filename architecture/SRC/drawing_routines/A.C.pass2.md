# SRC/drawing_routines/A.C — Enhanced Analysis

## Architectural Role

This file is the **C wrapper interface for the core pixel-pushing rendering primitives** in the Build engine's portal renderer. It sits between the high-level scanline rasterization logic (in ENGINE.C's `drawrooms`, `drawmasks`, `dorotatesprite`) and the x86 assembly optimizations in A.ASM. The module abstracts texture lookup, palette indirection, and blending via configurable static state, allowing ENGINE.C to invoke the same tight loop functions across different contexts (walls, floors, ceilings, sprites) without parameter bloat.

## Key Cross-References

### Incoming (who depends on this file)

- **ENGINE.C** — Calls all major functions (`hlineasm4`, `slopevlin`, `vlineasm1`/`mvlineasm1`/`tvlineasm1`, `spritevline` variants, `mhline`/`thline`) during:
  - Wall scanning (`wallscan` → `vlineasm1`)
  - Ceiling/floor drawing (`ceilscan`, `florscan` → `hlineasm4`, `mhline`/`thline`)
  - Slope rendering (`slopevlin` for 3D-floor-like effects)
  - Sprite masking & rotation (`dorotatesprite` → `spritevline` variants)
- **A.ASM** — Provides x86-optimized assembly versions (e.g., `vlineasm1_`, `mvlineasm4_`, `slopevlin_`) that bypass the C loops entirely for performance. The C versions likely serve as fallback or reference implementations.

### Outgoing (what this file depends on)

- **Extern globals** (set by ENGINE.C or core render state):
  - `asm1`, `asm2` — Per-scanline texture coordinate deltas (set before drawing, used in `hlineasm4`, `mhline`, `thline`)
  - `asm3` — Palette pointer or palette base address
  - `globalx3`, `globaly3` — Camera/world-space transform vectors for perspective-corrected drawing in `slopevlin`
- **krecip()** — Reciprocal lookup/computation for perspective correction in slopes
- **VES2.H / PRAGMAS.H** — Fixed-point arithmetic conventions (implied via coordinate shifting patterns)

## Design Patterns & Rationale

### 1. **State Setup + Draw Pattern**
Every drawing family has a `setup*` function (`setupvlineasm`, `setupmvlineasm`, `setuptvlineasm`, `setupspritevline`, etc.) that configures static globals, followed by a `*vline` or `*hline` function that uses those globals. **Rationale:** In the 1990s, avoiding parameter passing in tight inner loops was critical for performance on 32-bit x86. The C code avoids register pressure and function call overhead by reading from globals instead of pushing arguments.

### 2. **Three-Mode Rendering (Opaque/Masked/Translucent)**
For each primitive type (vline, hline, sprite), three variants exist:
- **Opaque** (`vlineasm1`, `hline`) — Write every pixel unconditionally
- **Masked** (`mvlineasm1`, `mhline`) — Skip pixels where texture color = 255 (color-key transparency)
- **Translucent** (`tvlineasm1`, `thline`) — Blend via `gtrans` lookup table

**Rationale:** Duke3D uses these modes for walls, floor sprites, and translucent effects (glass, sprites, HUD). Having separate code paths avoids branching in the inner loop.

### 3. **Log-Address Bit Hacks**
```c
((bx>>(32-glogx))<<glogy)+(by>>(32-glogy))
```
This computes a 2D texture offset by treating texture dimensions as powers of 2, enabling bit-shifts instead of integer division. E.g., for a 256×256 texture (glogx=8, glogy=8):
- `bx >> 24` extracts the high 8 bits (X coordinate)
- `by >> 24` extracts the high 8 bits (Y coordinate)
- `(X << 8) + Y` is the linear texture offset

**Rationale:** Eliminates expensive `*` and `/` ops in the hot path on 1990s CPUs where register stalls from multiplication were severe.

### 4. **Perspective Correction via Reciprocal**
`slopevlin` calls `krecip()` on `asm3 >> 6` per pixel, then scales screen-to-world vectors (`globalx3`, `globaly3`) by the reciprocal. **Rationale:** This is the standard Quake/Build technique for perspective-correct texture mapping on sloped surfaces; pre-computed reciprocal table avoids division per pixel.

### 5. **Translucence Blending via 64KB Lookup**
```c
gtrans[((*((char *)p))<<8)+gpal[ch]];  // normal
gtrans[(*((char *)p))+(gpal[ch]<<8)];  // reverse
```
A 64KB table indexed by `(destination<<8) + source` (or vice versa for reverse mode) eliminates blend arithmetic. **Rationale:** Lookup tables were the standard pre-pixel-shader technique for real-time blending. The two modes (normal vs. reverse) support different visual effects (additive vs. subtractive blending approximation).

## Data Flow Through This File

### Wall/Ceiling Rendering (Horizontal Lines)
```
ENGINE.C: Calculate texture coords (bx, by) and palette (asm3)
  → setuphlineasm4(bxinc, byinc)  [configure deltas]
  → hlineasm4(..., bx, by, ...)    [rasterize scanline left-to-right]
  → Write pixels via gpal[gbuf[...]] lookup
```

### Wall Rendering (Vertical Lines)
```
ENGINE.C: Prepare texture V-coord (vplc), pitch (bpl), palette
  → setupvlineasm(glogy)  [configure texture height]
  → vlineasm1(vinc, paloffs, cnt, vplc, ...)  [draw column]
  → Read gpal[gbuf[vplc >> glogy]] per pixel
```

### Sloped Surface Rendering
```
ENGINE.C: Set asm1 (reciprocal increment), asm3 (palette array), camera vectors (globalx3/globaly3)
  → setupslopevlin(logylogx, gbuf, gpinc)
  → slopevlin(...)
  → Per pixel: reciprocal correction → world-space lookup → palette indirection
```

### Sprite Rendering (Rotated/Scaled)
```
ENGINE.C: Calculate bx/by in 16.16 fixed-point, deltas (gbxinc/gbyinc)
  → setupspritevline(paloffs, bxinc, byinc, ysiz)  [configure transform]
  → spritevline(...) [draw column of sprite]
  → Address: (bx>>16)*glogy + (by>>16)  [stride-based 2D lookup]
```

## Learning Notes

### What This File Teaches
1. **Fixed-Point Coordinate Arithmetic** — All coordinates use integer left-shifts for sub-pixel precision (16.16 format). Modern engines use floats; Build used integers to avoid FPU stalls on 386/486.
2. **Paletted Graphics Pipeline** — Texture lookup → palette indirection → blending lookup. Modern engines texture-sample directly in shaders; this was the DOS-era approach for fast pixel ops.
3. **Self-Modifying Code & State Machines** — The globals pattern enables runtime patching of assembly code without recompiling (though that's implicit here—A.ASM contains the patched versions).
4. **Performance Archaeology** — Every design choice (log-addressing, state setup, lookup tables, loop unrolling strategy) targets 1990s CPU bottlenecks (multiplication cost, register pressure, cache misses).

### Modern Parallels & Differences
- **ECS-style state** — The static globals mimic modern ECS component patterns (separate data layout for cache efficiency), though here it's just globals, not a true component system.
- **No vertex shaders/pixel shaders** — This is pure software rasterization with no GPU. Modern engines use vertex/fragment shaders in hardware.
- **No SIMD** — A.C uses scalar loops; A.ASM likely unrolls or uses 32-bit ops. Modern code uses SSE/AVX to rasterize 4+ pixels per iteration.

### Engine-Specific Idioms
- **Reciprocal-based perspective** — Standard in Build/Quake; many engines pre-computed `1/z` tables.
- **Translucence blending as lookup** — Duke3D has only 256 colors; a 64KB blend table was the only feasible approach.
- **Log-addresses for POT textures** — Required because VRAM was scarce and textures were often 64×64 or 128×128. Modern hardware handles arbitrary sizes.

## Potential Issues

1. **Undefined Behavior in Pointer Casts**
   - `(char *)p` and `(char *)bufplc` casts assume 8-bit pixel format, but screen pitch (`bpl`) might not match actual framebuffer layout. If `bpl ≠ width`, column iteration via `p += bpl` could read out-of-bounds or misaligned memory.
   - **Mitigation:** Assumes caller correctly sets `bpl` and ensures `p` points within bounds.

2. **No Bounds Checking on Texture Coordinates**
   - `gbuf[((bx>>(32-glogx))<<glogy)+(by>>(32-glogy))]` assumes `bx` and `by` remain within texture bounds. Malformed texture coordinates could read adjacent buffers.
   - **Mitigation:** Assumes texture setup functions and ENGINE.C validate coordinates.

3. **Global State Aliasing**
   - Multiple setup functions write overlapping globals (e.g., `setupvlineasm` and `setupmvlineasm` both set `glogy`). If ENGINE.C interleaves calls without coordination, state corruption is possible.
   - **Mitigation:** Likely only one rendering type active per frame phase.

4. **Transmode Control Inconsistency**
   - `settransreverse()` and `settransnormal()` are the only ways to toggle `transmode`, but ENGINE.C might not consistently set it between different sprite/wall types.
   - **Mitigation:** Probably set once per frame and never changed mid-render.

---

**File Role Summary:** A.C is the **C glue layer** between the high-level render loop and x86 assembly optimizations, using fixed-point math, paletted lookups, and global state to achieve 1990s software-rasterization performance.
