# Architecture Overview

## Repository Shape

- **SRC/**: Core engine and game modules
  - **A.ASM** — x86-32 assembly rendering primitives (line drawing, masking, translucence, sprites, slopes)
  - **K.ASM** — x86-32 assembly audio synthesis and PC timer interrupt handler
  - **BUILD.H** — Master header defining sector/wall/sprite structs, compile-time limits, global state arrays
  - **BUILD.C** — Interactive map editor (3D first-person + 2D overhead modes)
  - **BSTUB.C** — Editor stub module (keyboard input, sprite setup, UI bridges)
  - **ENGINE.C** — Portal-based 3D rendering, spatial engine, collision detection
  - **CACHE1D.C** — Memory cache, group file I/O, LZW compression/decompression
  - **KDMENG.C** — Multi-channel sound engine, sound card drivers, music/sample playback
  - **MULTI.C** — Serial COM + IPX network multiplayer (up to 16 players)
  - **MMULTI.C** — Packet buffering, CRC validation, timeout-based retransmission
  - **PRAGMAS.H** — Inline x86 assembly for fixed-point math, VGA I/O, hardware helpers
  - **VES2.H** — VESA VBE 2.0 framebuffer abstraction (linear/banked modes, palette)
  - **NAMES.H** — Sprite/tile type constants
  - **drawing_routines/A.C** — Wrapper functions for texture-mapped primitives

- **UTIL/**: Batch utilities and tools
  - **EDITART.C** — Interactive tile/artwork editor with palette management
  - **SETUP.C** — TUI configuration utility for hardware and game settings
  - **CONVMAP5.C, CONVMAP6.C, CONVMAP7.C** — Map format forward converters (v5→v6→v7)
  - **BACKMAP5.C, BACKMAP6.C** — Map format backward converters (v6→v5, v7→v6)
  - **WAD2ART.C** — Doom WAD to Build ART tile converter
  - **WAD2MAP.C** — Doom WAD to Build map converter
  - **KGROUP.C, KEXTRACT.C** — Group file archive creation and extraction
  - **TRANSPAL.C** — Palette lookup and translucency table generator

## Major Subsystems

### Core Rendering Engine
- **Purpose:** Portal-based 3D renderer with sector visibility, perspective-correct texture mapping, sprite rendering, and collision detection
- **Key directories / files:**
  - SRC/ENGINE.C, SRC/A.ASM, SRC/drawing_routines/A.C
- **Key responsibilities:**
  - Recursive sector scanning for portal visibility with occlusion tracking
  - Wall/ceiling/floor drawing with per-pixel texture lookup and fixed-point perspective correction
  - Sprite rendering (billboards, rotated, masked) with depth-based sorting
  - Collision detection (hitscan ray casting, clipmove swept collision, getzrange z-bounds)
  - Palette and graphics management; tile/voxel loading
  - Self-modifying x86 code patches for runtime parameter binding (stride, palette offsets, coordinates)
  - CPU detection and codec selection (Pentium/Pentium II/MMX variants)
- **Key dependencies:**
  - BUILD.H (sector[], wall[], sprite[] arrays; limits; global state)
  - PRAGMAS.H (mulscale*, divscale*, asm1/asm2/asm3/asm4 globals, video I/O)
  - VES2.H (framebuffer pointers, palette DAC)

### Data Model & Editor
- **Purpose:** Define engine data structures and provide interactive level editor with map file I/O
- **Key directories / files:**
  - SRC/BUILD.H, SRC/BUILD.C, SRC/BSTUB.C
- **Key responsibilities:**
  - Define MAXSECTORS, MAXWALLS, MAXSPRITES, MAXTILES engine limits
  - Declare global parallel arrays (no encapsulation): sector[], wall[], sprite[], palette[], sintable[], waloff[], etc.
  - 3D editor mode: in-world camera control, sprite/sector/wall editing with visual feedback
  - 2D editor mode: overhead map view with wall/sector manipulation, grid snapping, sector highlighting
  - Keyboard/mouse input with interrupt-driven buffering
  - Load/save map files in version-specific binary formats
  - Property dialogs and UI editing callbacks for geometry and sprites
  - Tile/texture browser with search and zoom
  - Geometry operations: sector splitting/joining, wall insertion/deletion, point snapping
- **Key dependencies:**
  - ENGINE.C (drawrooms, drawmasks, collision queries, sprite operations)
  - CACHE1D.C (loadboard, saveboard)
  - NAMES.H (sprite type constants)

### Resource Management
- **Purpose:** Centralized memory cache with LRU eviction, group file archiving, and asset decompression
- **Key directories / files:**
  - SRC/CACHE1D.C
- **Key responsibilities:**
  - Pre-allocated circular memory buffer with locking semantics and age-based eviction
  - Load files from raw disk or .GRP archive containers with directory metadata
  - LZW compress/decompress for asset streaming and storage
  - Tile graphics pointer management (waloff[] locks and unlocks)
  - Age decrement cycle for cache recycling on periodic calls
- **Key dependencies:**
  - DOS file I/O (open, read, close, lseek, filelength)
  - PRAGMAS.H (memory operations: copybufbyte, clearbuf, FP_OFF)

### Audio Subsystem
- **Purpose:** Multi-channel digital audio synthesis, PCM playback, and sound card hardware control
- **Key directories / files:**
  - SRC/K.ASM, SRC/KDMENG.C
- **Key responsibilities:**
  - Sound card detection and initialization (Sound Blaster, Pro Audio Spectrum, PC speaker)
  - Comb filter synthesis (four variants: mono/stereo × low/high quality) via K.ASM
  - Real-time audio mixing at ~120 Hz update rate
  - 16-channel sound effect mixing with vibrato, tremolo, panning effects
  - Spatial audio (distance-based attenuation, listener-relative panning)
  - .KWV sample file loading and .KDM music sequencing
  - DMA buffer management and double-buffering with ISA hardware
  - PC timer interrupt handler (INT 0x08) for sample-accurate playback
  - Sample format conversion and saturation (8-bit, 16-bit bounds)
- **Key dependencies:**
  - PRAGMAS.H (fixed-point math, port I/O intrinsics)
  - DOS interrupts (0x08 timer, 0x21 generic, sound card ISA ports)

### Multiplayer & Networking
- **Purpose:** Support up to 16-player serial COM and IPX network modes with reliable packet delivery
- **Key directories / files:**
  - SRC/MULTI.C, SRC/MMULTI.C
- **Key responsibilities:**
  - Initialize/deinitialize COM ports or IPX network via DOS interrupts (0x7a IPX, 0x2f driver check, 0x31 DPMI)
  - Install and restore interrupt handlers for serial input and IPX callbacks
  - Send/receive packets with CRC-16 validation (error detection)
  - Timeout-based packet retransmission for reliable delivery
  - Player connectivity graph management (adjacency, linked lists)
  - Real-mode code segment injection for COM/IPX interrupt handlers
  - Packet buffering and deduplication per player
  - Embedded asm real-mode buffers (rmbuffer, rmnetbuffer) for ISR callbacks
- **Key dependencies:**
  - DOS interrupts (0x7a, 0x31, 0x21, 0x2f, serial UART 3F8/2F8/3E8/2E8)
  - PRAGMAS.H (port I/O, memory operations)

### Graphics & Video Output
- **Purpose:** Framebuffer abstraction, video mode selection, palette management via VESA VBE 2.0
- **Key directories / files:**
  - SRC/VES2.H, SRC/PRAGMAS.H
- **Key responsibilities:**
  - VESA VBE 2.0 mode enumeration, validation, and sorting by resolution
  - Linear framebuffer (LFB) or banked video mode detection and switching
  - Physical-to-linear address mapping via DPMI for LFB access
  - Page flipping and dirty-region tracking for banked modes
  - DAC (palette) read/write operations
  - Fixed-point arithmetic (multiply-scale, divide-scale, double-multiply-accumulate)
  - VGA mode 13h and mode X pixel/line drawing with alignment optimization
  - Memory buffer operations (copy, fill, clear, reverse)
  - Mouse, keyboard, 8253 PIT timer hardware interface
- **Key dependencies:**
  - DOS DPMI (0x10 video mode setup, 0x31 memory mapping)
  - x86 hardware (VGA I/O 0x3c4–0x3cf, video RAM 0xa0000, 8253 timer, PS/2 mouse INT 0x33)

### Sprite & Tile Type Registry
- **Purpose:** Define numeric identifiers for game entities and provide human-readable names
- **Key directories / files:**
  - SRC/NAMES.H
- **Key responsibilities:**
  - Central sprite type constants (PLAYER, BROWNMONSTER, etc.)
  - Tile/sprite ID mapping for editor introspection
- **Key dependencies:**
  - None (passive header; included by editor and game code)

### Map Format Converters
- **Purpose:** Migrate map files between engine versions (v5 ↔ v6 ↔ v7)
- **Key directories / files:**
  - UTIL/CONVMAP5.C (v5→v6), UTIL/CONVMAP6.C (v6→v7), UTIL/CONVMAP7.C (forward pipeline)
  - UTIL/BACKMAP5.C (v6→v5), UTIL/BACKMAP6.C (v7→v6)
- **Key responsibilities:**
  - Load and validate old-format binary map structures
  - Transform struct layouts and field migrations (height left-shift, wall pointer consolidation, cstat conversions)
  - Derive missing fields in new format from old data
  - Write new-format binary map files
  - Batch file discovery and alphabetic sorting via DOS file search
- **Key dependencies:**
  - DOS file I/O (open, read, write, close)

### Tile & Artwork Editor
- **Purpose:** Interactive editor for tile graphics, palettes, and artwork
- **Key directories / files:**
  - UTIL/EDITART.C
- **Key responsibilities:**
  - Load/save .ART tile files and metadata
  - Tile browser with zoom, swap, and batch operations
  - Pixel-level drawing (brush, fill, rotate, flip)
  - Palette and lookup table management
  - Image import (BMP, PCX, GIF) with format conversion
  - Shade table and translucency table generation
  - Screenshot capture to PCX
  - VGA graphics mode control (sequencer, CRTC, attribute, graphics controller, DAC)
- **Key dependencies:**
  - VGA hardware (0x3c4–0x3cf ports, 0xa0000 video RAM)
  - DOS file I/O and directory scanning

### Configuration Utility
- **Purpose:** Interactive TUI for persistent hardware and game settings
- **Key directories / files:**
  - UTIL/SETUP.C
- **Key responsibilities:**
  - Hierarchical menu system for graphics, sound, input, networking, keybindings
  - Graphics mode selection (Chain4, VESA, chipset-specific)
  - Sound card and music device configuration
  - Input device setup (keyboard, mouse, joystick)
  - Serial communications parameters
  - Custom keybinding capture via keyboard interrupt handler
  - VGA screen state save/restore during menu transitions
  - Load/save binary `setup.dat` configuration file
- **Key dependencies:**
  - DOS BIOS (0x10 video, 0x09 keyboard interrupt)
  - VGA text buffer (0xb8000) for direct rendering
  - DOS file I/O

### Group File Archiving
- **Purpose:** Create and extract uncompressed asset archives with wildcard file selection
- **Key directories / files:**
  - UTIL/KGROUP.C (creation), UTIL/KEXTRACT.C (extraction)
- **Key responsibilities:**
  - Expand DOS wildcards (* and ?) and response file lists (@filename)
  - Serialize matched files into group container with fixed header ("KenSilverman") and directory metadata
  - Stream large files through 64KB buffer to accommodate DOS memory limits
  - Validate group file format and locate file entries by name
  - Extract matched files to disk with wildcard support
- **Key dependencies:**
  - DOS file I/O and directory scanning (_dos_findfirst, _dos_findnext)

### Palette & Lookup Table Generator
- **Purpose:** Generate and preview shade and translucency lookup tables
- **Key directories / files:**
  - UTIL/TRANSPAL.C
- **Key responsibilities:**
  - Load palette data and existing lookup tables from `palette.dat`
  - Generate shade tables by darkening palette colors toward black
  - Generate translucency/blending tables by interpolating color pairs
  - Initialize fast color quantization with spatial grid acceleration
  - Display preview on VGA screen
  - Save updated lookup tables back to `palette.dat`
- **Key dependencies:**
  - DOS file I/O (fcntl.h, io.h)
  - VGA hardware (color DAC 0x3c8–0x3c9, video RAM 0xa0000)
  - PRAGMAS.H (divscale16, memory operations)

### Doom WAD Converters
- **Purpose:** Convert Doom IWAD/PWAD files to Build engine format (graphics and maps)
- **Key directories / files:**
  - UTIL/WAD2ART.C (Doom WAD → Build ART tiles + palette)
  - UTIL/WAD2MAP.C (Doom WAD → Build map with optional scripting)
- **Key responsibilities:**
  - Parse Doom WAD file directory and locate resource sections (TEXTURE1/2, PNAMES, L_START/S_START/P_START/F_START)
  - Extract and convert 8-bit VGA palette (PLAYPAL) and color lookup table (COLORMAP)
  - Decompress Doom column-based sprite graphics to Build scanline format
  - Process flat (64×64) textures from F_START section
  - Extract map geometry (vertices, linedefs, sidedefs, sectors, things)
  - Convert Doom sprite types and textures to Build equivalents via lookup tables
  - Parse optional conversion scripts for custom field assignments
  - Write .ART file, `palette.dat`, and C header (`names.h`) for Build editor
  - Generate Build binary .map file with sector-wall adjacency
- **Key dependencies:**
  - DOS file I/O (open, read, close, lseek)
  - VGA hardware (for preview rendering)
  - PRAGMAS.H (fixed-point math, memory operations)

## Key Runtime Flows

### Initialization
1. **Engine startup:**
   - Call `initengine()` to allocate and initialize sector[], wall[], sprite[] arrays to MAXSECTORS/MAXWALLS/MAXSPRITES
   - Install interrupt handlers (timer INT 0x08, keyboard, mouse INT 0x33, serial for multiplayer)
   - CPU detection and A.ASM code patch injection (CPU-specific render codecs)

2. **Video initialization (VES2.H):**
   - Enumerate VESA VBE 2.0 modes via INT 0x10 AX=0x4F01
   - Select linear framebuffer (LFB) or banked video mode
   - Map physical video memory to linear address space via DPMI (INT 0x31)
   - Initialize palette DAC (INT 0x10 AX=0x1010)

3. **Resource loading (CACHE1D.C):**
   - Initialize group file directory and pre-allocated memory cache buffer
   - Load .GRP archives or raw tile/palette files
   - Decompress assets via LZW if needed

4. **Audio initialization (KDMENG.C):**
   - Detect sound card (probe SB, PAS, or default to PC speaker)
   - Initialize DMA channels and interrupt handlers
   - Load .KDM music and .KWV sample files from cache

5. **Multiplayer setup (MULTI.C):**
   - If multiplayer mode: initialize COM port (INT 0x14) or IPX (INT 0x7a) via DOS interrupt
   - Install serial/IPX interrupt handlers (0x0b for COM, 0x7a callback for IPX)
   - Establish player connectivity graph with up to 16 players

### Per-frame / Main Loop
1. **Input processing:**
   - Poll keystatus[] array (updated by keyboard INT 0x09 handler)
   - Query mouse position and buttons (updated by INT 0x33 handler)
   - Process user commands (camera movement, editing, game logic)

2. **Physics / game logic:**
   - Update sprite positions and animation frames
   - Perform collision checks (clipmove swept collision, hitscan ray casts)
   - Update spatial sector membership (updatesector)

3. **Rendering (ENGINE.C + A.ASM):**
   - Call `drawrooms()` to recursively scan visible sectors via portal traversal
   - For each visible sector: draw floor, ceiling, walls with perspective-correct texture mapping using A.ASM inner loops
   - Call `drawmasks()` to extract and sort translucent sprites by z-order (ExtAnalyzeSprites)
   - Render each sprite as textured quad using vlineasm*/hlineasm* assembly routines
   - Update frameplace pointer for framebuffer writes

4. **Audio update (KDMENG.C):**
   - Update comb filter synthesis state (~120 Hz update rate)
   - Mix 16 active sound channels with vibrato/tremolo/panning effects
   - Fill double-buffered DMA buffer for sound card playback

5. **Multiplayer sync (MULTI.C + MMULTI.C):**
   - Queue outbound player state packets (position, angle, sprite updates)
   - Receive and validate incoming packets via CRC-16
   - Detect timeout and trigger automatic retransmit of unacknowledged packets

6. **Framebuffer swap (VES2.H):**
   - For linear LFB: minimal overhead; hardware display follows frameplace automatically
   - For banked mode: copy active page to visual page via _fmemcpy(); track dirty regions to avoid full-frame copies
   - Update palette DAC if color table changed (INT 0x10 AX=0x1010)

### Shutdown
1. **Audio cleanup (KDMENG.C):**
   - Stop DMA playback
   - Restore original sound card interrupt handlers

2. **Multiplayer cleanup (MULTI.C):**
   - Disconnect all players and send goodbye packets
   - Restore serial/IPX interrupt handlers

3. **Video cleanup (VES2.H):**
   - Restore original VGA mode (mode 3 text) via INT 0x10 AX=0x0003
   - Restore original palette from saved DAC table

4. **Resource cleanup (CACHE1D.C):**
   - Close group files and raw file handles
   - Deallocate memory cache buffer

5. **Engine cleanup (ENGINE.C):**
   - Deallocate sector[], wall[], sprite[] arrays and voxel buffers
   - Restore interrupt handlers (timer, keyboard, mouse, serial if used)

## Data & Control Boundaries

### Global State (BUILD.H)
**Parallel-array data model (no struct nesting, everything is primitives):**
- `sector[MAXSECTORS]` — Portal/room containers with floor height, ceiling height, floor/ceiling slopes, z-height references, light level, sector effector type/sector, sprite list head pointer
- `wall[MAXWALLS]` — Boundary segments with texture tile IDs, facing direction, x/y coordinates, clipping flags (cstat), portal nextsector/nextwall, wall length, palette override
- `sprite[MAXSPRITES]` — Entities with x/y/z position, angle, tile/voxel ID, animation state (picnum, ang, xvel, yvel, zvel), collision radius (clipdist), status type, owner, sector membership

**Rendering state:**
- `frameplace` — Current framebuffer write pointer (LINEAR address, updated per frame or page flip)
- `xdim`, `ydim` — Screen dimensions (used by VES2.H and rendering math)
- `ylookup[2048]` — Scanline byte offset lookup table (indexed by y-coordinate)
- `waloff[MAXTILES]` — Tile graphics memory pointers (indexed by tile ID; locked in cache during rendering)
- `walock[MAXTILES]` — Lock count for tile cache entries (prevents eviction if > 0)
- `tilesizx[MAXTILES]`, `tilesizy[MAXTILES]` — Tile dimensions (8×8 to 255×255)
- `palette[768]` — 256-color palette (3 bytes per color: R, G, B)
- `voxoff[][MAXVOXELS]` — Voxel model memory pointers (indexed by voxel ID and orientation)

**Timing:**
- `totalclock` — Global frame counter (incremented by timer INT 0x08 handler, ~70 Hz on DOS)
- `numframes` — Render frame count (incremented per drawrooms call)
- `sintable[2048]` — Precomputed sine lookup (16-bit fixed point)

**Sprite linked lists (spatial coherence):**
- `headspritesect[MAXSECTORS]` — Head sprite index for each sector
- `nextspritesect[MAXSPRITES]` — Linked list next pointer (sprite within same sector)
- `prevspritesect[MAXSPRITES]` — Linked list prev pointer (sprite within same sector)
- `headspritestat[MAXSTATUS]` — Head sprite index for each status type
- `nextspritestat[MAXSPRITES]` — Linked list next pointer (sprite with same status)
- `prevspritestat[MAXSPRITES]` — Linked list prev pointer (sprite with same status)

**Editor automapping:**
- `show2dsector[MAXSECTORS/8]` — Bitfield for 2D map visibility
- `show2dwall[MAXWALLS/8]` — Bitfield for 2D wall visibility
- `show2dsprite[MAXSPRITES/8]` — Bitfield for 2D sprite visibility

### Resource Ownership & Lifetimes
- **Framebuffer:** Owned by video driver; engine writes via frameplace pointer (linear address or banked window)
- **Memory cache (CACHE1D.C):** Single pre-allocated circular buffer; assets evicted on demand with LRU policy and lock counting
- **Tile graphics:** waloff[] pointers reference cache-locked regions; walock[] prevents eviction during rendering; unlocked after frame complete
- **Audio buffers:** Two DMA buffers swapped every synthesis cycle (~120 Hz); ownership transferred between ISR and main loop via _bufferside flag
- **Network packets:** Buffered per-player with sequence numbers and CRC validation; resent on timeout (default 1 second)

### Memory Layout & Addressing
- **DOS protected mode (DPMI):** 32-bit linear addressable; engines runs in protected mode, but real-mode code segments injected for DOS calls and interrupt handlers
- **Far pointers (FP_OFF/FP_SEG macros):** Used for real-mode callback addresses (serial ISR, IPX handler, video BIOS segment:offset)
- **Self-modifying code (A.ASM):** Direct bytecode patching at fixed instruction offsets for runtime parameter binding
  - Examples: fixchain patches inject framebuffer stride, palette lookup table base address, texture u/v coordinates into inner loop instructions
- **Global variable addressing:** All engine code uses x86 calling convention (register parameters: eax, ebx, ecx, edx, esi, edi; stack for extra args) plus global variable references for shared state

### Communication & Interface Patterns
- **Game ↔ Engine:** Implicit; game code reads/writes global arrays (sector[], wall[], sprite[], palette[], etc.) defined in BUILD.H; no function-based interface
- **Editor ↔ Engine:** BSTUB.C bridge module acts as adapter; editor calls ENGINE.C functions (drawrooms, drawmasks, collision queries, sprite insertion/deletion)
- **Engine ↔ Assembly:** Parameters passed via global registers (asm1, asm2, asm3, asm4, globalx3, globaly3, vplce[], vince[], palookupoffse, etc.) and CPU registers
- **Driver ↔ Multiplayer:** Via gcom function pointer (injected at runtime; likely defined in game module)
- **Interrupt handlers ↔ Main loop:** Shared mutable state via global arrays (keystatus[], mouse position, sprite updates on status change)

## Notable Risks / Hotspots

### Performance-Critical Paths
- **Column/span rendering inner loops (A.ASM):** Self-modifying code with CPU-specific codepaths (Pentium/Pentium II/MMX). Cache-line invalidation or branch misprediction on fixchain patches costly; CPU detection and patching must be precise.
- **Texture mapping reciprocal lookup (_reciptable):** Fixed-point perspective-correct lookup used on every pixel in vertical line drawing; cache misses or false table initialization catastrophic for throughput.
- **Sprite sorting (ENGINE.C):** Depth-based sort of visible sprites every frame; O(n log n) worst-case with no spatial acceleration beyond sector bucketing; large sprite counts (e.g., particle effects) risk frame-time stalls.

### Memory Management Risks
- **Cache eviction deadlock (CACHE1D.C):** LRU policy with lock counting; over-locking assets in high-frame-rate scenes (e.g., many simultaneous on-screen tiles) can exhaust cache and force evictions mid-rendering, causing corruption or stalls. Lock count overflow not explicitly checked.
- **Global state mutation during traversal (BUILD.H):** Sector/wall/sprite indices remain valid only if geometry unchanged; if editor or physics deletes/reorders geometry during portal walking or sprite iteration, indices become dangling pointers. No transaction or versioning.
- **Stack overflow on recursive sector scan (ENGINE.C):** drawrooms() recursively traverses portals; pathological geometry (deeply nested sectors, circular portal references) can exhaust stack without explicit depth limit checks.

### Input/Output Risks
- **Interrupt handler reentrancy (keyboard, mouse, timer, serial):** Handlers modify keystatus[], mouse position, sprite lists, and totalclock without synchronization primitives. If main loop modifies same data while handler fires, race conditions cause memory corruption or dropped input. Timer handler increments totalclock while game logic may read it.
- **Multiplayer packet loss (MULTI.C):** Timeout-based retransmission without explicit sequence numbering or application-level acknowledgment; duplicate packets or out-of-order delivery possible on lossy links; no visible protocol recovery.
- **VESA mode fragility (VES2.H):** Banked mode with dirty-region tracking requires precise page-flipping sequencing; incorrect _fmemcpy() ordering, missing fence synchronization, or DMA conflicts can cause visual tearing, buffer corruption, or hardware lockup.

### DOS/x86 Legacy Risks
- **Real-mode callback segments (MULTI.C, KDMENG.C, SETUP.C):** Embedded real-mode code for interrupt handlers; FAR pointer segment arithmetic, register preservation in context switches, and DPMI segment-to-linear mappings error-prone; incorrect segment setup causes GP faults.
- **Hardware timing assumptions (K.ASM, KDMENG.C, PRAGMAS.H):** PC speaker and timer interrupt handlers assume fixed CPU clock (assumed ~70 Hz DOS timer) and DMA synchronization; modern emulators, dual-core contention, or high-load systems violate timing guarantees, causing audio glitches or stalls.
- **DOS file handle exhaustion:** Editor and utilities open files without explicit close in error paths (e.g., map load failure, WAD parse error); default DOS file handle limit (~20) easily exceeded with large map folders; subsequent file operations fail silently.
- **VGA register I/O ordering (PRAGMAS.H, VES2.H, EDITART.C):** Sequencer, CRTC, attribute controller, and graphics controller register sequences must respect strict ordering and timing constraints; incorrect sequences corrupt video memory, hang controller, or cause display artifacts.
