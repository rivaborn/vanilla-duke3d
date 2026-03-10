# SRC/BUILD.C — Enhanced Analysis

## Architectural Role

BUILD.C serves as the **interactive level editor frontend** and **primary application driver** for the Build Engine. It orchestrates a two-mode editor (3D first-person + 2D overhead) by mediating between the **rendering subsystem** (ENGINE.C), **data model** (sector/wall/sprite arrays in BUILD.H), **resource management** (CACHE1D.C for load/save), and **game-specific UI bridges** (BSTUB.C extension callbacks). The editor's main loop directly calls ENGINE.C's drawrooms/drawmasks for viewport rendering, while simultaneously managing geometry mutations (wall insertion, sector splitting) and property editing through the EXT* callback interface.

## Key Cross-References

### Incoming (who depends on this file)
- **BSTUB.C**: Calls `ExtLoadMap()`, `ExtSaveMap()`, and ExtXxx property display/edit functions defined here
- **Main application**: Entry point (main() is the only non-static entry point)
- **Interrupt handlers** (keyhandler, timerhandler): Write keystatus[] and totalclock that BUILD.C polls

### Outgoing (what this file depends on)
- **ENGINE.C**: `drawrooms()`, `drawmasks()`, `clipmove()`, `getzrange()`, `hitscan()`, `changespritesect()`, `updatesector()`—render 3D view and query spatial state
- **CACHE1D.C**: `loadboard()`, `saveboard()`, `loadtile()`—map file I/O and texture streaming
- **BSTUB.C**: `ExtInit()`, `ExtUnInit()`, `ExtPreCheckKeys()`, `ExtCheckKeys()`, `ExtShowSectorData()`, `ExtEditSectorData()`, etc.—game-specific UI hooks
- **PRAGMAS.H**: sintable[] (angle lookups), mulscale*(), min/max—fixed-point math for movement
- **VES2.H**: `setgamemode()`, `qsetmode640480()`—video mode setup
- **Global sector[], wall[], sprite[] arrays** (BUILD.H): Read/written here; also read by ENGINE.C render pipeline

## Design Patterns & Rationale

### 1. Interrupt-Driven Input with Polling State Machine
- **keyhandler()** (IRQ 9) captures raw scan codes into keystatus[256] atomically
- **timerhandler()** (IRQ 8, 120 Hz) updates vel/svel/angvel based on held keystatus
- **editinput()** and **overheadeditor()** poll keystatus[] and respond to state changes
- **Rationale**: DOS-era preemptive interrupt handling; 286/386 CPUs had reliable hardware timer but no event queue infrastructure; polling avoided complex event routing in real-mode.

### 2. Dual-Mode Editor with Shared Geometry
- Single sector/wall/sprite array used by both 3D and 2D views; mode switch via Enter key
- 3D mode (**editinput**): Camera-relative vel/svel/angvel physics, collision via clipmove
- 2D mode (**overheadeditor**): Grid-snapped point/wall manipulation, mouse drag, visual sector outline
- **Rationale**: Designers benefit from both views; shared data model (no sync overhead); mode separation allows orthogonal UI logic.

### 3. Velocity-Based Camera Control with Friction
- timerhandler() increments/decrements vel/svel/angvel at 120 Hz based on keystatus
- editinput() integrates velocities into position via clipmove (collision-aware physics)
- Deceleration when key released (natural inertia)
- **Rationale**: Matches first-person game feel; collision resolution built into movement, not post-hoc; 120 Hz update rate sufficient for smooth motion on Pentium-era hardware.

### 4. Extension Hooks for Game-Specific UI
- All sprite/sector/wall property dialogs go through ExtShowXxx/ExtEditXxx (BSTUB.C)
- Editor is **data-agnostic** about sprite types, sector meanings
- **Rationale**: Single editor codebase reusable across games (Duke3D, Shadow Warrior, etc.); game-specific interpretation (sprite capabilities, default values) lives in BSTUB.C.

### 5. Tile Frequency-Based Caching & Sorting
- gettile() maintains localartfreq[MAXTILES] (usage count per tile)
- Shell-sort tiles by frequency; V key filters to "recently used"
- **Rationale**: Level designers repeatedly apply 5–10 tiles; quick access improves ergonomics.

## Data Flow Through This File

### Map Load/Save Cycle
```
menuselect() → (file browser, user picks file)
  ↓
loadboard(filename) [CACHE1D.C]
  → sector[], wall[], sprite[] arrays populated from disk
  → posx, posy, posz, ang, cursectnum set to start state
  ↓
ExtLoadMap(filename) [BSTUB.C]
  → game-specific map initialization (sprites → game entities, etc.)
```

### 3D Render/Edit Loop (per-frame)
```
keystatus[] updated by keyhandler() interrupt asynchronously
  ↓
timerhandler() every ~8.3ms: updates vel, svel, angvel based on keystatus
  ↓
editinput() polls keystatus[], mouse state
  → clipmove(posx, posy, posz, cursectnum, xvect, yvect, ...) [ENGINE.C]
    collision detection + position integration
  → getzrange(posx, posy, posz, cursectnum, ...) [ENGINE.C]
    ceiling/floor bounds for z-clamping
  → hitscan(posx, posy, posz, ang, ...) [ENGINE.C]
    ray-cast for property editing (picking)
  ↓
drawrooms(posx, posy, posz, ang, horiz, cursectnum) [ENGINE.C]
  renders 3D view to frameplace
  ↓
drawmasks() [ENGINE.C]
  renders sprites over walls
  ↓
nextpage()
  flips framebuffer (page flip / dirty region copy depending on video mode)
```

### Geometry Editing (2D Overhead)
```
overheadeditor() main loop polls keystatus[], mouse
  ↓
(User clicks two points in overhead view)
  ↓
insertpoint() adds new wall, shifts wall pointers in sector
  ↓
deletesector() removes sector and all its walls
  ↓
copysector() duplicates sector attributes + sprites to new sector
  ↓
draw2dscreen()
  re-renders overhead view with grid, walls, sectors, sprites
```

### Sector Splitting (Complex State Machine)
```
User draws line through existing sector in 2D mode
  ↓
(newnumwalls accumulates new wall edges)
  ↓
On close: loopnumofsector() classifies inner/outer walls
  ↓
For each inner loop: whitelinescan() creates new sector
  ↓
checksectorpointer() O(n²): rebuilds nextwall/nextsector adjacency
```

## Learning Notes

### Idiomatic to 1990s Game Engines (vs. Modern)
1. **No ECS/Components**: Parallel arrays (sector[], wall[], sprite[]) instead of entity objects; inherent cache locality but poor for sparse properties
2. **Interrupt-Driven Polling**: Hardware interrupts populate keystatus[] array; main loop polls array (no event queue, no message pump)
3. **Static Allocation**: No malloc/free for level geometry (compile-time limits MAXSECTORS, MAXWALLS); central memory cache (CACHE1D.C) for textures
4. **Direct Framebuffer Drawing**: No retained-mode scene graph; immediate-mode plotting and tiling directly to video RAM (0xa0000)
5. **O(n²) Spatial Queries**: checksectorpointer() scans all walls to find adjacency; no spatial hashing or quadtree
6. **Portal-Based Rendering**: ENGINE.C uses sector visibility graph (red lines = portals); not rasterizer with occlusion buffers

### Connections to Engine Programming Concepts
- **Level Editor as Content Tool**: One of the first fully integrated in-engine editors (parallel to DOOM's external tools); allows real-time preview
- **Sector/Portal Paradigm**: Entire editor UI (2D view, highlighting, splitting) built around sector-centric world model (vs. modern voxel/mesh-based editors)
- **Fixed-Point Arithmetic**: Camera velocities and collision detection use 16.16 fixed-point for precision and speed (no FPU on 286; Pentium FPU slower than integer shifts)
- **Interrupt Safety via Atomic Access**: keystatus[] array written by IRQ handler; no spin-locks (assumed single-cycle atomic access on 286+)

### What Modern Engines Do Differently
- **Undo/Redo Stack**: This editor has no history (only "Save?" prompt); modern editors have unlimited undo
- **Incremental Compilation**: This editor directly edits sector/wall arrays; no intermediate representation or validation before write
- **Spatial Hashing for Point-in-Polygon**: loopinside() does O(n²) sprite checking during sector splitting; modern editors use cell-based or SAT algorithms
- **Event-Driven Input**: This editor polls keystatus[] in main loop; modern engines use event queues with priority/routing
- **Asset Streaming**: loadtile() loads entire tile to cache; modern engines support mip-maps and texture atlasing

## Potential Issues

### 1. Race Condition on keystatus[] Array
- keyhandler() writes keystatus[] without disabling interrupts in BUILD.C
- editinput()/overheadeditor() read keystatus[] without synchronization
- On 386+ with out-of-order execution, torn reads possible (unlikely in practice due to single-cycle per-byte access)
- **Impact**: Rare glitches; key presses might be missed or doubled under timing edge cases

### 2. Fixed-Size Array Overflow
- MAXSECTORS, MAXWALLS, MAXSPRITES are compile-time constants (no bounds checking in insertpoint/insertsprite)
- deletepoint() shifts wall[] entries but does not validate new count against MAXWALLS
- **Impact**: Level complexity capped; overflow → heap corruption (adjacent memory overwritten)

### 3. O(n²) Sector Splitting & Adjacency Rebuild
- checksectorpointer() full scan of all sectors/walls after every geometry mutation
- overheadeditor() sector splitting does nested loop over walls and sprites (loopinside)
- **Impact**: Perceptible UI lag on maps with 100+ sectors; potential frame rate drop on property edits

### 4. No Undo/Redo Mechanism
- All edits are immediate (writes to sector[]/wall[]/sprite[] arrays)
- Only asksave flag detects modifications; no transaction or rollback capability
- **Impact**: User loses work on accidental edits (e.g., delete sector, realize mistake)
