# SRC/ENGINE.C — Enhanced Analysis

## Architectural Role

ENGINE.C is the **central hub** of the Build engine's rendering and spatial subsystems, bridging the geometry data model (BUILD.H) with low-level graphics primitives (A.ASM, VES2.H) and resource management (CACHE1D.C). It implements a portal-based visibility algorithm that recursively traverses the sector graph, maintains occlusion state (umost/dmost arrays), and coordinates texture mapping, sprite sorting, and collision detection. The file is the primary consumer of fixed-point math (PRAGMAS.H) and directly patches x86 rasterization routines at runtime.

## Key Cross-References

### Incoming (who depends on this file)

- **BUILD.C (editor)**: Calls `drawrooms()` to render 3D view; calls `drawmasks()` for sprite overlay; calls `rotatesprite()` for UI
- **Game code (external)**: Calls `drawrooms()` for per-frame rendering; calls `getzrange()`, `clipmove()`, `hitscan()` for physics and collision
- **BSTUB.C (editor interface)**: Calls rendering functions indirectly via BUILD.C
- **nextpage() call chain**: Implicit consumer of frame state (visualpage, activepage, frameplace set by ENGINE.C)

### Outgoing (what this file depends on)

- **CACHE1D.C**: `loadtile()` called from wallscan/ceilscan/florscan/drawsprite to ensure texture data in memory before rasterization
- **A.ASM (drawing primitives)**: `vlineasm1/vlineasm4`, `prevlineasm1` for texture-mapped wall rasterization; `hlineasm4` for flat-shaded ceilings/floors; `setupvlineasm`, `setup*hlineasm4` to bind parameters at runtime
- **VES2.H (video/framebuffer)**: `setactivepage()`, `setvisualpage()` for page flipping; `frameplace` global read for buffer base address
- **PRAGMAS.H (fixed-point math)**: `mulscale*()`, `divscale*()`, `dmulscale*()` for all coordinate transforms and perspective correction
- **BUILD.H (data model)**: Reads `sector[]`, `wall[]`, `sprite[]` arrays; reads `sintable[]` for angle lookup; reads `waloff[]`, `picsiz[]`, `picanm[]` for texture metadata
- **KDMENG.C (inferred)**: Distance-based attenuation for spatial audio (called via game logic in collision queries, not direct)

## Design Patterns & Rationale

**1. Portal-Based Rendering with Occlusion Culling**
- Recursively traverses sector portals (walls); skips sectors already visible. Maintains vertical occlusion bounds (umost/dmost) per x-pixel to avoid redundant overdraw.
- **Rationale**: DOS hardware has extremely limited bandwidth; culling invisible pixels is essential for 320×200 real-time performance.

**2. Self-Modifying x86 Assembly Code**
- `setupvlineasm()`, `setuphlineasm4()`, etc. patch register/memory operands into asm routines before calling them.
- **Rationale**: Watcom C++ intrinsics are limited; self-modifying code allows parameter binding without function-call overhead or register spills. High-performance necessity on 90s hardware.
- **Tradeoff**: Non-portable, non-debuggable, prone to cache coherency issues on later CPUs.

**3. Separation: High-Level vs. Low-Level Rasterization**
- ENGINE.C owns clipping, perspective math, texture coordinate setup; A.ASM owns per-pixel writes.
- **Rationale**: Keeps C code maintainable while asm focus is narrow and optimizable.

**4. Immediate-Mode Rendering**
- Draws directly to framebuffer; no command buffer or display list. Stereo rendering (VR mode) is inline.
- **Rationale**: Reduces memory allocations and complexity; acceptable for single-threaded DOS.

**5. Persistent Sprite Queue (permfifo)**
- UI overlays (rotatesprite with dastat&128) persist across page flips via circular FIFO.
- **Rationale**: Simplifies multi-page sprite lifecycle without extra per-sprite state.

## Data Flow Through This File

**Rendering Pipeline (per-frame):**
```
drawrooms(pos, ang, sector)
  → scansector(sector) [recursive portal traversal]
      → [collect walls, ceilings, floors, sprites into xb*/yb* arrays]
      → bunchfront() [depth sort portals]
  → For each bunch (nearest to farthest):
      → drawalls(bunch)
          → wallscan(x1,x2, uwal,dwal, swal,lwal)
              → loadtile() [ensure texture in cache]
              → setupvlineasm() [bind texture offset, palette]
              → vlineasm1/vlineasm4() [write pixels to frameplace]
          → ceilscan(x1,x2, sector) [flat/parallax ceiling]
              → hlineasm4() [scanline fill]
          → florscan(x1,x2, sector) [flat/parallax floor]
  → drawmasks() [transparent sprites, masked walls]
      → drawsprite(snum)
          → maskwallscan() / transmaskwallscan()
  → [game code calls nextpage() to page-flip and render queued permfifo[] sprites]
```

**Collision Queries (on-demand):**
```
getzrange(x, y, z, sect) → [traverse sector/wall/sprite, return z-bounds and hit object]
clipmove(x,y,z,sect, vx,vy) → [raytrace with iteration, return collision object]
hitscan(xs,ys,zs,sect, vx,vy,vz) → [cast ray, return first hit]
```

**Resource Lifecycle:**
- Tiles loaded on-demand by `loadtile()` (called during rasterization) into CACHE1D.C heap.
- walock[] reference counting prevents eviction of in-use tiles.
- Per-frame call to `agecache()` (external) ages unused entries for eviction.

## Learning Notes

**What a Developer Studies Here:**
1. **Portal Rendering**: How to traverse a graph of sectors/portals and maintain visibility state without redundant work. The umost/dmost technique is elegant: a single per-pixel array tracks the "open" screen region, avoiding Z-buffer cost.
2. **Fixed-Point Perspective Correction**: No floating-point; all coordinates are `<<16` or `<<20` for subpixel precision. Division by distance uses precomputed reciprocal tables (reciptable[]).
3. **x86 Assembly Integration**: How to patch asm routines at runtime to bind parameters; how to unroll loops (4-wide vline operations) for throughput.
4. **Sprite Sorting**: Breadth-first bucket sort by depth (numbunches), interleaved with masked wall rendering to maintain painter's algorithm correctness.
5. **Cache Locality**: Explicit tile locking (walock[]) and aging strategy; awareness that disk I/O is the bottleneck, not CPU.

**Idiomatic to 1990s Game Engines (not Modern):**
- No ECS, no scene graph, no GPU. All data is parallel arrays (sector[], wall[], sprite[]) with integer indices. Physics and rendering are tightly coupled.
- No occlusion queries or Z-prepass; painter's algorithm via portal depth ordering + per-pixel occlusion arrays.
- No unified resource system; tiles are baked into .ART files, sprites are indexed by 16-bit IDs, palettes are lookup tables.
- Self-modifying code and explicit asm intrinsics are the norm for performance.

## Potential Issues

1. **Portal Graph Integrity**: If walls are mis-winded or portals are not bidirectional, rendering can miss entire sectors or leak into adjacent rooms. No validation at draw time.

2. **Array Bounds**: `sector[]`, `wall[]`, `sprite[]` have hard limits (MAXSECTORS, MAXWALLS, MAXSPRITES). No bounds checking; overflow silently corrupts adjacent data.

3. **Fixed-Point Overflow**: Division and multiplication don't check overflow. Large coordinates or scaling can silently wrap.

4. **Self-Modifying Code Cache Coherency**: On modern CPUs with speculative execution, patching asm routines while they're in flight can cause undefined behavior. Works on 386/486/Pentium by accident; dangerous assumption.

5. **gotsector[] Bitfield Overflow**: `clearbufbyte((long)(&gotsector[0]),(long)((numsectors+7)>>3),0L)` assumes gotsector[] is large enough; no validation.

6. **Interrupt Handler Reentrancy**: If `drawrooms()` is interrupted by a timer handler that modifies global state (totalclock, sprite positions), corruption is possible. No mutual exclusion.

---

**Under ~1500 tokens as requested.**
