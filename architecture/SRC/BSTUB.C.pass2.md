# SRC/BSTUB.C — Enhanced Analysis

## Architectural Role

BSTUB.C implements the **extension hook system** that bridges the main editor (BUILD.C) and core engine (ENGINE.C), providing game-specific customization points without modifying the editor core. It orchestrates three major subsystems: configuration/initialization (CACHE1D.C, device drivers), input/viewport transformation (keystatus polling, angle/aspect manipulation), and sprite rendering preparation (voxel loading, transform pre-computation). The file is intentionally a "stub" — games override these functions to inject custom sector/wall/sprite editing logic and decorative rendering effects (rotated view overlay, FPS display).

## Key Cross-References

### Incoming (who depends on this file)

- **BUILD.C** (main editor) calls:
  - `ExtInit/ExtUnInit`: startup/shutdown hooks
  - `ExtPreCheckKeys`: frame-start input (screen resize, view angle, aspect ratio)
  - `ExtCheckKeys`: frame-end input (rotated view overlay, FPS display, aspect keys)
  - `ExtAnalyzeSprites`: pre-render sprite transformation
  - `ExtShow*/ExtEdit*{Sector|Wall|Sprite}Data`: F5–F8 property display/edit callbacks
  - `ExtGet*Caption`: UI label generation for map elements

### Outgoing (what this file depends on)

- **ENGINE.C**: `drawrooms`, `drawmasks`, `setaspect`, `setviewback`, `setviewtotile`, `qloadkvx`, `scale`
- **CACHE1D.C**: `allocache`, `initgroupfile`, `uninitgroupfile` (resource system)
- **VES2.H** (VESA/video): `getvalidvesamodes`, `setgamemode`, `inittimer42`, `uninittimer42`
- **BUILD.C**: `editinput` (main editor input dispatch)
- **PRAGMAS.H**: `dmulscale1`, `divscale15`, `mulscale14`, `mulscale16`, `divscale16`, `scale`, `sintable[]` (fixed-point math)
- **Global state**: `keystatus[]`, `sector[]`, `wall[]`, `sprite[]`, `tsprite[]`, `qsetmode`, `frameplace`, `posx/posy/posz`, `horiz`, `ang`, `waloff[]`, `walock[]`, `tilesizx[]`, `tilesizy[]`, `voxoff[][]`, `totalclock`

## Design Patterns & Rationale

**Extension Hook Pattern**: The `Ext*` function set acts as a well-defined callback interface that BUILD.C invokes at specific frame phases. This decouples game-specific logic from the editor core and allows multiple games to reuse the engine with minimal modification.

**Stub/Placeholder Design**: Functions like `ExtEditSectorData` contain intentional no-ops ("Just a stupid example") and placeholder variables ("Nick's variable"). This teaches game developers what hooks are available without imposing constraints.

**Off-Screen Tile Buffering (tile 4094)**: The rotated view preview allocates a temporary tile via `allocache(&waloff[4094], ...)` and renders into it via `setviewtotile(4094)`. This demonstrates the engine's uniform tile-based memory model — off-screen surfaces are just tiles with high indices, same as texture tiles.

**Lazy Voxel Loading**: `ExtAnalyzeSprites` uses `if (!voxoff[0][0]) qloadkvx(...)` to load voxels on first encounter. This defers I/O until needed and integrates cleanly with CACHE1D.C's resource management (waloff/walock locking semantics).

**Interrupt-Driven State**: `keystatus[]` is populated by an interrupt handler (BUILD.C's `keyhandler` or hardware ISR); BSTUB polls it each frame rather than blocking. `totalclock` increments at ~120 Hz via timer interrupt (K.ASM's PC timer ISR). This allows responsive, non-blocking input.

**Fixed-Point Perspective Transforms**: Functions like `ExtPreCheckKeys` compute viewing angles and aspect ratios using integer multiply-scale and divide-scale operations (no floating-point). The calculations for `horizval1/2`, `daviewingrange`, `daaspect` derive from the 2D rotation matrix applied to the viewport in fixed-point.

## Data Flow Through This File

1. **Init Phase**: `ExtInit()` → reads `setup.dat` → loads config options, keybinds → calls `initgroupfile()` (CACHE1D) → `initmouse()` → `initengine()` → creates palette lookup table via `makepalookup()`.

2. **Per-Frame Input**: 
   - `keystatus[]` ← interrupt handler (asynchronous)
   - `ExtPreCheckKeys()` reads keystatus → adjusts `hang` angle, allocates tile 4094, calls `setaspect()`, `setviewtotile()` to prepare rotated viewport

3. **Sprite Preparation**: 
   - `tsprite[]` ← ENGINE.C's render queue
   - `ExtAnalyzeSprites()` iterates sprites, lazy-loads voxels via `qloadkvx()`, scales and applies sector shading
   - Modified sprites → ENGINE.C rendering pipeline

4. **Display**: 
   - If `hang != 0`, `ExtCheckKeys()` calls `stretchhline()` (A.ASM) to paint rotated view overlay to framebuffer
   - Calculates FPS from `totalclock` / `gettimer42()` delta, maintains rolling average in `frameval[]`

5. **UI Display (F5–F8)**:
   - `ExtShow*/ExtEdit*` functions format sector/wall/sprite data via `sprintf()` into `tempbuf`
   - Write to status bar via `printext16()`, `drawline16()`

## Learning Notes

**Extension Architecture in C**: BSTUB demonstrates a practical callback pattern — define a fixed set of entry points (`Ext*` functions), have the core loop call them at known phases, and let games override. No virtual function tables; just function pointers or direct calls.

**Parallel Array Data Model**: Geometry is stored as flat integer arrays (`sector[MAXSECTORS]`, `wall[MAXWALLS]`, `sprite[MAXSPRITES]`), not heap-allocated objects. This is cache-friendly and fits DOS era constraints, but requires disciplined index management.

**Tile-Centric Resource System**: The tile `waloff[]` array unifies texture memory, voxel memory, and scratch buffers. Tiles are 8×8 units up to 1024×1024 pixels; high indices (e.g., 4094) are reserved for temporary work. This is idiomatic to 1990s engines but would be encapsulated in a resource manager in modern code.

**Software Rendering Pipeline**: No GPU; rendering is done via self-modifying x86 code (`hlineasm4_`, `vlineasm1_`, `stretchhline`) parametrized at runtime. Lookup tables drive texture mapping, translucency, palette selection. BSTUB prepares sprite transforms; ENGINE.C and A.ASM do the pixel work.

**Hardware Precision**: Direct access to PC timer (8253 PIT) via `inittimer42()`/`gettimer42()` for frame-accurate FPS measurement. VESA mode-set disrupts timer state; code reinitializes it after `setgamemode()`.

**Voxel as Sprite Variant**: KVX voxels are not first-class 3D objects. They're loaded as 8-bit sprite frames, scaled, and billboarded like 2D sprites. Sprite type constants (PLAYER, BROWNMONSTER) map to voxel files by convention (hardcoded in `ExtAnalyzeSprites`).

**What modern engines do differently**: Encapsulate subsystems (no global arrays), use reference counting/GC for resources, delegate input to event loops, use GPUs for rendering, abstract hardware timing behind OS APIs.

## Potential Issues

**Tile 4094 Collision**: Hardcoded assumption that tile 4094 is free for temporary use. If a game's map uses high-index tiles for actual content, conflict occurs. No dynamic allocation or bounds checking.

**Hardcoded Sprite Types**: `ExtAnalyzeSprites` only handles PLAYER and BROWNMONSTER. New sprite types in a game won't receive voxel treatment; they silently degrade to 2D sprites. Requires code modification per game.

**No Input Bounds Validation**: `ExtEditSectorData` passes user input from `getnumber16()` directly to sector/sprite array indexing with no validation. Malicious sector numbers could corrupt adjacent sectors or crash.

**FPS Calculation Precision**: Assumes `totalclock` increments uniformly at 120 Hz and `gettimer42()` is coherent with it. VESA mode-set can cause skew; recovery relies on `inittimer42()` call completing before next frame (tight timing).

**tempbuf Reuse Risk**: Static 256-byte buffer reused by `sprintf` in multiple functions (captions, editing dialogs). Nested calls or concurrent access could overwrite data. Current code avoids nesting, but refactoring could introduce bugs.
