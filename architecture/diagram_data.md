# SRC/A.ASM
## File Purpose

Core rendering engine for the Build Engine, containing highly-optimized x86 assembly routines for drawing horizontal/vertical lines, masked and translucent rendering, sprite operations, and slope-based texture mapping. Implements self-modifying code for runtime parameter injection and CPU-specific code overlays.

## Core Responsibilities

- Setup functions for line-drawing parameters (bit shifts, palette lookups, offsets)
- Horizontal line drawing with various optimizations (standard, masked, translucent)
- Vertical line drawing for single and multi-column texture mapping
- Masked vertical lines with transparent pixel skip logic
- Translucent/blended vertical lines using lookup tables
- Sprite rendering with texture sampling and palette translation
- Slope-based texture mapping for sloped surfaces
- CPU detection and runtime code patching (Pentium/Pentium II/MMX variants)
- Self-modifying code patches at runtime for dynamic parameter binding

## External Dependencies

- **Imported globals:** `_asm1`, `_asm2`, `_asm3`, `_asm4`, `_reciptable`, `_fpuasm`, `_globalx3`, `_globaly3`, `_ylookup`, `_vplce`, `_vince`, `_palookupoffse`, `_bufplce`, `_ebpbak`, `_espbak`, `_pow2char`, `_pow2long`
- **Self-modifying code patterns:** Patch offsets at fixed byte positions (e.g., `+1`, `+2`, `+3`) in instructions
- **Calling convention:** x86 register calling (parameters in `eax`, `ebx`, `ecx`, `edx`, `esi`, `edi`); some values via globals
- **Framebuffer model:** Linear 32-bit scanline-stride addressable; stride injected via `_asm1` or `fixchain*` patches

# SRC/BSTUB.C
## File Purpose

Extension stub module for the Build engine editor. Handles initialization, keyboard input, sprite rendering setup, and UI display/editing functions for map sectors, walls, and sprites. Acts as a bridge between the core Build engine and game-specific editor logic.

## Core Responsibilities

- Engine initialization/cleanup and configuration loading
- Per-frame keyboard input handling for editor navigation and viewing angles
- Sprite transformation and voxel loading for rendering pipeline
- Editor UI display functions for sector/wall/sprite properties
- Property editing callbacks for map elements (stubs for game-specific logic)
- Screen mode/resolution management via VESA modes
- Frame rate calculation and display
- FPS counter and horizontal viewing angle display

## External Dependencies

- **Core engine:** `build.h` (struct definitions, constants, array declarations)
- **Pragmas:** `pragmas.h` (inline assembly helpers: math, memory, video I/O)
- **Game constants:** `names.h` (sprite type IDs: PLAYER, BROWNMONSTER, etc.)
- **Engine functions (defined elsewhere):**
  - Video: `initgroupfile()`, `setgamemode()`, `setviewtotile()`, `setaspect()`, `setviewback()`, `clearmidstatbar16()`, `printext256()`, `printext16()`, `drawline16()`, `stretchhline()`
  - Input: `initmouse()`, `editinput()`
  - Rendering: `qloadkvx()`, `makepalookup()`
  - Timer: `inittimer42()`, `uninittimer42()`, `gettimer42()`
  - Resource: `initengine()`, `uninitgroupfile()`
  - UI: `getnumber16()`, `printmessage16()`
- **External symbols accessed:** `keystatus[]`, `sector[]`, `wall[]`, `sprite[]`, `tsprite[]`, `frameplace`, `xdimenscale`, `ydimen`, `waloff[]`, `walock[]`, `tilesizx[]`, `tilesizy[]`, `voxoff[][]`, `spritesortcnt`, `ylookup[]`, etc.

# SRC/BUILD.C
## File Purpose
Interactive map editor for the Build Engine, providing both 3D first-person editing mode and 2D overhead editor view. Manages user input, UI interactions, geometry editing, and file I/O for level design.

## Core Responsibilities
- Main application loop and mode switching (3D vs. 2D editor)
- 3D mode: camera control, in-world sprite/sector/wall editing with visual feedback
- 2D mode: overhead map view with wall/sector manipulation, grid snapping, sector highlighting
- Input handling: keyboard, mouse, and interrupt-driven input with buffering
- Tile/texture browser UI with search and zoom functionality
- Map file operations: load, save, and "save as" with file browsing
- Property display and editing for sectors, walls, and sprites via UI dialogs
- Geometry operations: sector splitting/joining, wall insertion/deletion, point snapping
- Lighting/shading adjustments for map elements

## External Dependencies
- **Rendering**: drawrooms(), drawmasks(), ExtAnalyzeSprites(), nextpage(), clearview(), draw2dscreen(), draw2dgrid(), fillsector(), drawline16(), plotpixel()
- **File I/O**: loadboard(), saveboard(), ExtLoadMap(), ExtSaveMap(), loadpics(), loadnames(), loadtile()
- **Property Display/Edit**: ExtShowSectorData(), ExtShowWallData(), ExtShowSpriteData(), ExtEditSectorData(), ExtEditWallData(), ExtEditSpriteData(), ExtGetSectorCaption(), ExtGetWallCaption(), ExtGetSpriteCaption()
- **Video/Graphics**: setgamemode(), setvmode(), qsetmode640480(), printext16(), printext256(), printmessage16(), printmessage256()
- **Input/Timer**: initkeys(), uninitkeys(), inittimer(), uninittimer(), getmousevalues(), _dos_getvect(), _dos_setvect(), _disable(), _enable()
- **Engine**: clipmove(), getzrange(), hitscan(), getceilzofslope(), getflorzofslope(), insertsprite(), deletesprite(), changespritesect(), setsprite(), updatesector(), sectorofwall(), lastwall(), inside(), loopnumofsector(), loopinside()
- **Math/Utilities**: mulscale*(), divscale*(), scale(), ksqrt(), getangle(), rotatepoint(), ksgn(), klabs(), min(), max()
- **System**: outpw(), outp(), kinp(), koutp(), _dos_findfirst(), _dos_findnext(), chdir(), open(), read(), close(), sprintf(), strcmp(), strcpy(), strcat(), strlen(), memcpy(), memset()
- **Data**: Global arrays: sector[], wall[], sprite[], palette[], sintable[], tilesizx[], tilesizy[], waloff[], headspritesect[], nextspritesect[], show2dsector[], show2dwall[], show2dsprite[]

# SRC/BUILD.H
## File Purpose
Core engine header defining the fundamental data structures (sector, wall, sprite), compile-time limits, and global state variables for the Build Engine. This is the central data model that all engine code references.

## Core Responsibilities
- Define MAXSECTORS, MAXWALLS, MAXSPRITES, MAXTILES, and other engine limits
- Define packed struct layouts for sector, wall, and sprite with detailed cstat bit flags
- Declare global game world state arrays (sectors, walls, sprites)
- Declare rendering state (viewport, video mode, screen dimensions)
- Declare timing and animation state (totalclock, numframes, sintable)
- Declare sprite linked lists for spatial and status-based queries
- Declare tile metadata and palette/lookup table pointers
- Provide automapping and visibility tracking bitfields

## External Dependencies
- Standard C library types (short, long, char, signed char, unsigned char)
- Macro EXTERN: defined as blank if ENGINE=1 (engine defines), else extern (game externs)
- `#pragma pack(push,1)`: Enforces tight byte-packing for structs (no alignment padding)


# SRC/CACHE1D.C
## File Purpose

Provides three major subsystems for the Build Engine: a linear memory cache with intelligent eviction, a group file system for reading bundled archives, and LZW compression/decompression for file I/O.

## Core Responsibilities

- **Cache management**: Allocate/deallocate memory from a pre-allocated buffer with locking semantics and age-based eviction
- **Group files**: Load and manage multiple files packed into single .GRP archive files with directory metadata
- **File I/O abstraction**: Unified interface (`kopen4load`, `kread`, etc.) supporting both raw files and group file entries
- **LZW compression**: Encode/decode game data streams using LZW algorithm with 16KB working buffers
- **Memory aging**: Periodically decrement lock counts on cached regions to enable eventual eviction

## External Dependencies

- **Includes:** `dos.h`, `stdio.h`, `pragmas.h` (custom inline x86 assembly macros), `fcntl.h`, `io.h`, `sys/types.h`, `sys/stat.h`
- **Defined elsewhere:** `mulscale32`, `copybufbyte`, `copybuf`, `clearbuf`, `kmalloc`, `kfree`, `reportandexit`, `setvmode`, `min`, `uncompress`, `compress`, `FP_OFF` (far pointer offset macro)
- **OS calls:** `open`, `read`, `close`, `lseek`, `filelength`, `fread`, `fwrite` (DOS/DPMI model)

# SRC/ENGINE.C
## File Purpose
Core rendering and spatial engine for the Build game engine. Implements a portal-based 3D renderer with sector/wall/sprite geometry, texture mapping, sprite rendering, collision detection, and palette/graphics management for DOS/VESA graphics.

## Core Responsibilities
- **3D Rendering Pipeline**: Portal-based visibility, wall/ceiling/floor/sprite drawing
- **Sector Geometry**: Recursive sector scanning, occlusion tracking via vertical clipping arrays
- **Texture Mapping**: Per-pixel texture lookup, perspective-correct mapping with fixed-point math
- **Sprite Rendering**: Billboard sprites, rotated sprites, masked (transparent) sprites with sorting
- **Collision Detection**: Hitscan (ray casting), clipmove (swept collision), getzrange (z-bounds queries)
- **Graphics Management**: Tile/art loading, palette lookups, voxel management, screen buffering
- **Input/Output**: Mouse setup, keyboard, VBE graphics mode setup, DOS interrupts

## External Dependencies
- **build.h**: sectortype, walltype, spritetype, extern arrays (sector, wall, sprite, sintable, palette, etc.)
- **pragmas.h**: Fixed-point math intrinsics (mulscale*, dmulscale*, divscale*, asm1/asm2/asm3/asm4 globals)
- **ves2.h**: VBE graphics adapter support, DOS DPMI int386 interface, screen/palette functions
- **DOS/x86**: int386()/int386x() for DOS interrupts; _enable()/_disable() for IRQs; FP_OFF/FP_SEG macros
- **External functions** (defined elsewhere): setupvlineasm(), vlineasm1(), vlineasm4(), hlineasm4(), prevlineasm1(), etc. (asm module), setpalookupaddress(), setuphlineasm4(), etc. (graphics module), getpalookup(), getzsofslope(), animateoffs(), etc. (core module)


# SRC/K.ASM
## File Purpose
x86-32 assembly code implementing the audio synthesis and PCM sample conversion engine for Duke3D. Contains four combinatorial synthesis functions (mono/stereo × low/high quality), PC timer interrupt handling for audio playback, and sample bounding/format conversion utilities (8-bit, 16-bit).

## Core Responsibilities
- **Comb filter synthesis** (four variants: monolocomb, monohicomb, stereolocomb, stereohicomb) for real-time audio generation
- **PC timer interrupt handling** (pctimerhandler_) for PCM playback scheduling and buffer management
- **Audio sample bounding and conversion** to char (8-bit) and short (16-bit) formats with saturation
- **Self-modifying code** to inject setup parameters into inner loops for performance optimization
- **Double-buffering management** via `_bufferside` flag and buffer pointer arithmetic
- **Interrupt chaining** to delegate to the original timer interrupt handler after processing

## External Dependencies
- **External variables (global):** `_kdmasm1`, `_kdmasm2`, `_kdmasm3`, `_kdmasm4`, `_chainbackcnt`, `_chainbackstart`, `_pcsndptr`, `_samplecount`, `_pcsndbufsiz`, `_oldpctimerhandler` (far), `_bufferside`
- **External functions (near calls):** `_qualookup`, `_pcsndlookup`, `_chain_intr_`, `__GETDS`, `preparesndbuf_`
- **I/O ports:** 0x20h (PIC interrupt control), 0x42h (PC speaker sample output)
- **Data segment:** DGROUP (established via `mov ax, DGROUP; mov ds, ax`)

# SRC/KDMENG.C
## File Purpose
Sound engine for the Build engine, supporting multi-channel digital audio playback, music sequencing, spatial effects, and multiple legacy sound cards (Sound Blaster, Pro Audio Spectrum, PC speaker). Handles real-time audio mixing, effects processing, and DMA-based hardware interaction.

## Core Responsibilities
- Sound card detection, initialization, and hardware configuration (SB, PAS, PC speaker)
- Wave sample loading (.KWV files) and memory management
- Music file loading (.KDM files) and note sequencing
- Real-time audio mixing and rendering (~120 Hz update rate)
- 16-channel sound effect mixing with effects (vibrato, tremolo, panning)
- Spatial audio effects (distance-based attenuation, listener-relative panning)
- DMA buffer management and interrupt handling
- Frequency/volume/panning effect envelopes
- Interrupt handler installation and restoration

## External Dependencies

**Notable includes:**
- `<malloc.h>` – memory allocation
- `<dos.h>` – DOS interrupts and hardware access
- `<io.h>`, `<fcntl.h>` – file I/O flags
- `<string.h>`, `<stdio.h>` – string and console functions

**External symbols (defined elsewhere):**
- `kopen4load()`, `kread()`, `kclose()` – Build engine file I/O
- `_dos_getvect()`, `_dos_setvect()`, `_disable()`, `_enable()` – DOS/compiler intrinsics
- `int386()`, `int386x()` – DPMI/DOS interrupt calls
- `monolocomb()`, `monohicomb()`, `stereolocomb()`, `stereohicomb()` – Watcom inline-asm mixing routines (also declared with `#pragma aux` calling conventions)
- `setuppctimerhandler()`, `pctimerhandler()` – PC timer real-mode handler setup
- `pcbound2char()`, `bound2char()`, `bound2short()` – Inline-asm sample conversion to DMA buffer
- `strupr()`, `strstr()`, `strcat()`, `strcpy()`, `strcmp()`, `memcpy()` – Standard C library

**Inline assembly helpers** (marked with `#pragma aux`):
- `fsin`, `klabs`, `mulscale16/24/30`, `dmulscale28`, `msqrtasm` – Fixed-point math
- `clearbuf`, `copybuf` – Fast buffer operations
- `kontp`, `kinp`, `koutpw` – Port I/O
- `resetsb`, `sbin`, `sbout`, `sbmixin`, `sbmixout` – Sound Blaster commands
- `findpas`, `convallocate`, `convdeallocate` – Hardware detection and DOS memory

# SRC/MMULTI.C
## File Purpose
Network multiplayer communication module for the Build engine. Handles packet buffering, transmission, reception, and validation between up to 16 players with CRC error detection and timeout-based packet resending.

## Core Responsibilities
- Initialize multiplayer mode and establish player connectivity graph
- Buffer outgoing packets per player with deduplication
- Batch and transmit packets through a driver interface (via `gcom`)
- Receive, validate, and reassemble incoming packets with CRC16 checks
- Implement reliable delivery via timeout detection and automatic resends
- Manage packet sequencing and error acknowledgment protocol

## External Dependencies
- **Includes:** `<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<dos.h>`, `<process.h>`, `<stdarg.h>`, `"pragmas.h"`
- **External symbols (defined elsewhere):** 
  - `totalclock` (global from game engine) — used for timeout calculation
  - `_argc`, `_argv` (standard C runtime) — command-line parsing
  - `int386()` (DOS interrupt wrapper, likely from runtime)
  - `strtok()`, `stricmp()`, `atol()` (standard C library)
  - `memcpy()` (standard C library)
  - `copybuf()` (defined in pragmas.h, likely asm utility)
  - `min()` (likely macro, standard)

# SRC/MULTI.C
## File Purpose
Multiplayer communication subsystem for the Build Engine, supporting both serial COM port connections and IPX network transport. Manages player connections, packet synchronization, and connection state across up to 16 players.

## Core Responsibilities
- Initialize/deinitialize COM and IPX network modes via `initmultiplayers()` / `uninitmultiplayers()`
- Manage player connection list and linked-list topology via `netinitconnection()` / `netuninitconnection()`
- Send outbound packets with framing, CRC, and retransmission via `sendpacket()` / `netsend()` / `comsend()`
- Receive and validate inbound packets, detecting errors and resending via `getpacket()` / COM interrupt handler
- Install/restore interrupt handlers for serial port via `installbicomhandlers()` / `uninstallbicomhandlers()`
- Simulate DOS/DPMI real-mode interrupts (0x7a IPX, 0x2f driver checks, 0x31 DPMI) via `simulateint()`
- Calculate and validate CRC-16 checksums via `initcrc()` / `getcrc()` for error detection

## External Dependencies
- **Includes:** `<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<dos.h>`, `<i86.h>` (Watcom C DOS/x86 headers)
- **DPMI/DOS calls:** INT 0x31 (DPMI), INT 0x21 (DOS generic), INT 0x2f (driver check), INT 0x7a (IPX/NetWare)
- **Real-mode code:** `rmbuffer` (COM handler asm), `rmnetbuffer` (IPX callback asm) embedded in data
- **External symbols (assumed defined elsewhere):**
  - `int386()`, `int386x()` — Watcom DPMI interrupt simulation
  - `_disable()`, `_enable()` — CPU interrupt enable/disable
  - `koutp()`, `kinp()` — Port I/O pragmas (inline x86 OUT/IN)
  - `processreservedmessage()` — Defined in this file; may call game-level handlers
  - `memcpy()` — Standard library
- **Hardware accessed:** Serial UART (3F8, 2F8, 3E8, 2E8), PIC interrupt controller (0x20, 0x21), BIOS data area (0x400)

# SRC/NAMES.H
## File Purpose
Defines numeric identifiers (tile/sprite type constants) for game entities in the Build engine. Used throughout the editor (Editart) and game code to reference specific sprite types, interactive objects, enemies, and environmental elements.

## Core Responsibilities
- Define sprite type constants for player, enemies, interactive objects, and environmental elements
- Provide human-readable names for numeric tile/sprite IDs used in level data
- Enable consistent entity type identification across the editor and game engine
- Map conceptual entity names to Build engine sprite indices

## External Dependencies
- No includes or external symbols
- Comment indicates file is parsed by `Editart` and `Build` tools (editor/engine introspection)

# SRC/PRAGMAS.H
## File Purpose
Header file defining inline x86 assembly pragmas for the Watcom C compiler. Provides optimized implementations of fixed-point math, VGA graphics operations, hardware I/O, memory manipulation, and timer functions critical to the Build Engine's real-time 3D rendering pipeline.

## Core Responsibilities
- Fixed-point arithmetic with variable-bit right shifts (multiply-scale, divide-scale)
- Double and triple multiply-accumulate operations for vector calculations
- VGA mode 13h and mode X (planar) pixel and line drawing
- Video memory operations (copy, fill, clear with alignment optimization)
- Memory buffer swapping and reversing
- Mouse and keyboard hardware interface
- 8253 PIT timer initialization and reading at 1MHz resolution
- Signed/unsigned min/max and utility math operations
- I/O port read/write wrappers

## External Dependencies
- **Compiler:** Watcom C `#pragma aux` directive
- **Hardware:** x86-32 (80386+), VGA (I/O ports 0x3ce, 0x3da; memory 0xa0000), 8253 PIT, PS/2 mouse (INT 33h), BIOS (INT 10h/5)
- **Symbols defined elsewhere:** None; all inline assembly

# SRC/VES2.H
## File Purpose
Implements VESA VBE 2.0 (Video Electronics Standards Association) support for the Build Engine, providing video mode detection, switching, page flipping, and palette management. Handles both linear framebuffer (LFB) and banked video modes through DPMI (DOS Protected Mode Interface) calls to INT 0x10.

## Core Responsibilities
- VESA VBE 2.0 mode enumeration, validation, and sorting by resolution
- Video mode switching with linear or banked framebuffer support
- Physical-to-linear address mapping via DPMI for LFB access
- Active and visual page management with dirty-region tracking for banked modes
- Palette (DAC) read/write operations
- DPMI real-mode interrupt calls and segment register management
- Buffer mode detection and fallback to software double-buffering

## External Dependencies
- **Includes:** `<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<conio.h>`, `<dos.h>`
- **Watcom/DOS functions:** `int386()`, `int386x()`, `segread()`, `_fmemcpy()`, `MK_FP()`, `FP_OFF()`, `koutp()`, `kinp()`, `atexit()`
- **Undefined symbols (defined elsewhere):**
  - `validmode[]`, `validmodexdim[]`, `validmodeydim[]`, `validmodecnt`: Mode list and dimension arrays
  - `faketimerhandler()`: Called to prevent timer starvation during long copies/flips
  - `startumost[]`, `startdmost[]`: Dirty-region scanline bounds
  - `ylookup[]`: Scanline byte offset lookup
  - `windowx1`, `windowy1`, `windowx2`, `windowy2`, `xdim`, `ydim`: Render window and screen dimensions
  - `stereomode`, `blackband`, `whiteband`, `vidoption`: Configuration flags

# SRC/drawing_routines/A.C
## File Purpose
Low-level rendering backend implementing texture-mapped primitive drawing for the game engine. Provides functions to draw horizontal lines (ceilings/floors), vertical lines (walls), sloped surfaces, and rotated sprites using palette lookups and fixed-point coordinate arithmetic.

## Core Responsibilities
- Manage rendering pipeline state (screen pitch, palette tables, translucence mode, texture coordinates)
- Implement ceiling/floor horizontal line drawing with perspective correction
- Implement wall/sprite vertical line drawing with texture lookups
- Support opaque, masked (color-key), and translucent rendering modes
- Handle sloped surface rendering with 3D perspective correction
- Implement scaled/rotated sprite rendering via fixed-point coordinate transforms
- Configure setup state before drawing operations

## External Dependencies
- `extern long asm1, asm2, asm3, asm4, fpuasm, globalx3, globaly3;` — External transformation registers or pre-computed values
- `extern void *reciptable;` — Reciprocal lookup table (declared but not used in visible code)
- `krecip()` — Reciprocal function (called in slopevlin, defined elsewhere)

# UTIL/BACKMAP5.C
## File Purpose
A utility program that batch-converts Build engine map files from version 6 to version 5 format. It reads version 6 maps (the "new" format), transforms them to version 5 (the "old" format), and writes them back to disk. Handles structural changes between map versions, including removal of dual-connectivity wall pointers and relocation of sprite/wall palette and offset fields.

## Core Responsibilities
- Parse command-line file patterns and enumerate matching files using DOS file search APIs
- Load and validate version 6 map files from disk, checking version field
- Transform sector, wall, and sprite structures from v6 to v5 layout
- Handle version-specific field migrations (e.g., consolidate `nextsector1`/`nextsector2` to `nextsector`)
- Write converted maps back to disk with v5 version number
- Provide user feedback on conversion success/failure for each file

## External Dependencies
- **Standard C / DOS APIs:** `fcntl.h`, `io.h`, `sys/types.h`, `sys/stat.h`, `dos.h`
- **File I/O:** `open()`, `read()`, `write()`, `close()` (DOS binary file I/O)
- **DOS Directory Listing:** `_dos_findfirst()`, `_dos_findnext()`, `find_t` struct (DOS-specific; not POSIX)
- **String/Memory:** `strchr()`, `strcat()`, `strcmp()`, `strcpy()`, `memcpy()` (C standard library)
- **I/O:** `printf()` (C standard library)
- **Struct Packing:** `#pragma pack` (compiler directive for binary layout control)

---

**Notes:**
- This is a **DOS-era utility** (early 1990s) targeting 16-bit DOS environments; uses obsolete DOS file APIs.
- The conversion is **backwards** in naming: it reads "new" (v6) data and writes "new" (v6) arrays, but saves as version 5. This is intentional—the utility downgrades maps.
- Dual wall connectivity (`nextsector1/2`, `nextwall1/2`) in v6 is collapsed to single pointers in v5; unused v6 pointers are hardcoded to `-1`.
- Sprite cstat is cast from v5 `short` to v6 `char`, losing upper byte precision.

# UTIL/BACKMAP6.C
## File Purpose
A map format converter utility for Ken Silverman's Build engine. Converts map files from version 7 to version 6 by loading old-format binary map data, transforming structures, and saving in the new format. Supports batch conversion of multiple files.

## Core Responsibilities
- Parse command-line arguments and locate matching map files
- Load binary map files in the old (version 7) format from disk
- Transform sector, wall, and sprite data structures from old to new format
- Apply format-specific conversions (e.g., bit-shifting height values)
- Write converted maps in new (version 6) binary format
- Maintain and sort a list of files to process

## External Dependencies
- **Standard includes:** `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>`
- **DOS/legacy APIs:** `_dos_findfirst()`, `_dos_findnext()`, `struct find_t`
- **I/O & string:** `open()`, `read()`, `write()`, `close()`, `strcpy()`, `strcmp()`, `memcpy()`, `strcat()`, `strchr()`
- **External symbols:** All functions defined in this file; data structures are internal.

# UTIL/CONVMAP6.C
## File Purpose
Map format converter utility that upgrades Build engine map files from version 5 to version 6. It reads old-format map structures, transforms them according to schema changes, and writes the new format back to disk. Includes file discovery and sorting utilities for batch conversion.

## Core Responsibilities
- Load map files in version 5 format and validate version numbers
- Transform sector, wall, and sprite structures from v5 to v6 schema
- Derive missing v6 fields from v5 data (e.g., sprite palette from sector, clipdist defaults)
- Write converted maps in version 6 format back to disk
- Discover and sort map files matching command-line filespec
- Handle error reporting for missing files or already-converted maps

## External Dependencies
- **DOS/System includes**: `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>` (file I/O, DOS file search)
- **Standard C**: `<stdio.h>` (implicit; `printf()`), string functions (`strchr`, `strcat`, `strcmp`, `strcpy`, `memcpy`)
- **External symbols used but not defined**: `open()`, `read()`, `write()`, `close()` (POSIX file I/O); `_dos_findfirst()`, `_dos_findnext()` (DOS); `printf()`, `exit()` (C stdlib)

# UTIL/CONVMAP7.C
## File Purpose
Utility to convert Build Engine map files from version 6 to version 7. Discovers all matching map files, loads old format structures, applies format-specific transformations (primarily height scaling), and writes the converted data in the new binary format.

## Core Responsibilities
- Parse command-line file specifications and discover matching `.map` files
- Sort discovered filenames alphabetically
- Load version 6 map structures (sectors, walls, sprites) from binary files
- Convert old struct layouts to new struct layouts with field reordering and alignment padding
- Apply height value transformations (left-shift by 5, clamp to signed 16-bit range)
- Write converted data to binary files in version 7 format
- Report success/failure and version compatibility checks

## External Dependencies

- **Headers:** `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>`
- **DOS API:** `_dos_findfirst()`, `_dos_findnext()`, `find_t` struct
- **Libc:** `open()`, `read()`, `write()`, `close()`, `strchr()`, `strcat()`, `strcmp()`, `strcpy()`, `memcpy()`, `printf()`, `exit()`
- **Macros/Functions defined elsewhere:** `max()`, `min()` (presumably from stdlib or custom)

# UTIL/EDITART.C
## File Purpose
Interactive tile and artwork editor for the Build engine. Allows editing, viewing, and managing tile graphics for Duke Nukem 3D, including palette management, animation configuration, and image capture from external files.

## Core Responsibilities
- Tile/artwork editing and pixel manipulation (drawing, filling, rotating, flipping)
- Loading and saving tile data from/to .ART files
- VGA graphics display and video mode control
- User interaction via keyboard and mouse
- Color palette management and lookup table generation
- Image format support (BMP, PCX, GIF) for importing artwork
- Tile browser/selector with zoom and tile swapping functionality
- Batch operations: tile insertion, deletion, resizing, metadata updates
- Map file synchronization when tiles are rearranged
- Screenshot/capture functionality to PCX files

## External Dependencies
- **DOS/DPMI**: Interrupt vectors (int 0x8 timer, int 0x31 DPMI, int 0x10 video, int 0x33 mouse)
- **Watcom C Runtime**: Standard file I/O (open, read, write, close, lseek), memory (malloc), process (chdir, printf), directory scanning (_dos_findfirst/_dos_findnext)
- **VGA Hardware**: Sequencer (0x3c4/0x3c5), CRTC (0x3d4/0x3d5), attribute controller (0x3c0/0x3c1), graphics controller (0x3ce/0x3cf), DAC (0x3c8/0x3c9), status (0x3da)
- **Inline Assembly**: Custom pragma operations (`scale`, `mulscale`, `divscale`, `setvmode`, `readmouse`, `setupmouse`, `clearbuf`, `drawpixel`, etc.) via Watcom C
- **Build Engine Structures**: Data type definitions (sectortype, walltype, spritetype) for map file I/O; no runtime calls to Build code

# UTIL/KEXTRACT.C
## File Purpose
A utility program that extracts files from Ken Silverman's proprietary group file archive format. It validates the group file, matches filenames using wildcard patterns (* and ?), and extracts matching files to disk.

## Core Responsibilities
- Validate group file format (magic header "KenSilverman")
- Parse group file metadata (file list, offsets, sizes)
- Support wildcard pattern matching for file selection
- Support @filename syntax to read extraction lists from external files
- Extract matched files from the group archive to disk

## External Dependencies
- **I/O:** `stdio.h` (printf), `fcntl.h`, `io.h` (open, read, write, lseek, close)
- **String:** `string.h` (strcpy, memset via loop)
- **File metadata:** `sys/types.h`, `sys/stat.h` (mode constants)
- **Legacy DOS:** `dos.h`, `conio.h` (minimal use; likely for DOS compatibility)
- **No internal dependencies:** All logic is self-contained within this file.

# UTIL/KGROUP.C
## File Purpose
A DOS utility that creates "group files" — uncompressed archives combining multiple game assets (art, maps, palettes, etc.) into a single container. Supports wildcard expansion and indirect file lists via response files.

## Core Responsibilities
- Parse command-line arguments (output filename and input file specs)
- Support response files (prefixed with `@`) containing lists of file patterns
- Recursively find files matching DOS wildcards via `_dos_findfirst`
- Serialize matched files into a group file with a fixed header format
- Stream large files through a 64KB buffer to avoid memory limits

## External Dependencies
- **Includes:** `<stdio.h>`, `<string.h>`, `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>`, `<conio.h>`
- **External symbols:** `_dos_findfirst()`, `_dos_findnext()` (DOS file API); `open()`, `read()`, `write()`, `close()` (POSIX-like I/O); `strcpy()`, `printf()`, `exit()`, `getch()` (standard C); `min()` macro (standard).

# UTIL/SETUP.C
## File Purpose
DOS-era interactive configuration utility for the Build Engine. Manages hardware settings (graphics, sound, input devices, communications) via a menu-driven TUI, with keyboard interrupt handling and persistent storage to `setup.dat`. Exclusively targets DOS/real-mode x86 architecture with direct hardware access.

## Core Responsibilities
- Present hierarchical menu system for hardware configuration selection
- Manage graphics modes (Chain, VESA, specialized chipsets)
- Configure digitized sound devices and playback parameters
- Set music, input devices (keyboard/mouse/joystick), and serial communications
- Custom keybinding capture via keyboard interrupt handler
- Save/restore VGA screen state during menu transitions
- Load and persist configuration to binary file
- Direct VGA text-mode rendering with box-drawing characters

## External Dependencies
- **DOS/BIOS:** `<dos.h>` — `_interrupt`, `_far`, `_disable()`, `_enable()`, `_dos_setvect()`, `_dos_getvect()`, `_asm` intrinsics
- **Console I/O:** `<conio.h>` — `getch()`, `outp()` (VGA direct I/O)
- **File I/O:** `<io.h>`, `<fcntl.h>`, `<sys/types.h>`, `<sys/stat.h>` — `open()`, `read()`, `write()`, `close()`
- **Stdio:** `<stdio.h>` — `printf()`, `strlen()`
- **Compiler-specific:** Watcom C pragmas (`#pragma aux`) for 386-optimized assembly; conditional `#if defined(__386__)` for architecture branching
- **Hardware:** Direct reads/writes to VGA text buffer (0xB8000/0xB8000000), keyboard controller (port 0x60), interrupt controller (port 0x20/0x21), and VGA CRTC (ports 0x3D4/0x3D5)

# UTIL/TRANSPAL.C
## File Purpose

Utility for generating and previewing palette lookup tables and translucency tables for the Build Engine. Reads a palette file, computes shaded and blended color variants, visualizes them on a VGA screen, and optionally saves the results back to the palette file.

## Core Responsibilities

- Parse command-line arguments (number of shade levels, translucency ratio, optional RGB scales)
- Load palette data and original lookup tables from `palette.dat`
- Generate shade lookup tables by darkening palette colors toward black
- Generate translucency blending tables by interpolating between two colors
- Initialize fast color quantization using spatial grid acceleration
- Display generated tables on VGA screen for visual preview
- Save updated tables based on user input (ENTER/SPACE/ESC)

## External Dependencies

**Includes / Pragmas:**
- `<fcntl.h>`, `<io.h>`: DOS file I/O operations
- `<sys\types.h>`, `<sys\stat.h>`: File mode constants
- `<dos.h>`: DOS I/O and interrupt access
- `<malloc.h>`, `<stdlib.h>`: Memory and string functions
- `"pragmas.h"`: Inline assembly wrappers (`divscale16`, `clearbuf`, `clearbufbyte`, `koutpw`, `koutp`, `drawpixel`, `setvmode`, `getch`)

**External Symbols (defined elsewhere):**
- `divscale16`: Fixed-point division (pragmas)
- `clearbuf`, `clearbufbyte`: Memory clear (pragmas)
- `koutpw`, `koutp`: VGA register write (pragmas)
- `drawpixel`: Video memory pixel write (pragmas)
- `setvmode`: VGA mode set (pragmas)
- `getch`: Keyboard input (stdlib)
- File I/O: `open`, `read`, `write`, `close` (io.h)
- String: `strcpy`, `atol` (stdlib.h)
- Math: `min`, `max` (intrinsic/pragmas)

**Notes:** This is a tight DOS-era utility coupled to VGA hardware registers and real-mode I/O, reliant on compiler pragmas for inline assembly functions.

# UTIL/WAD2ART.C
## File Purpose
Command-line utility that converts Doom IWAD files to the Build engine's ART tile format. Extracts graphics, palette data, and sprite metadata, generating `tiles000.art`, `palette.dat`, and `names.h` for use with the Build engine editor and runtime.

## Core Responsibilities
- Parse Doom WAD file directory structure and locate resource sections (L_START, S_START, P_START, F_START)
- Extract and convert 8-bit VGA palette (PLAYPAL) and color lookup table (COLORMAP) to Build format
- Decompress and reformat sprite graphics from Doom's column-based format to Build's scanline format
- Process flat (64×64) textures from F_START section
- Write ART file with proper header (version, tile count, dimensions, animation data)
- Generate C header file (`names.h`) defining sprite name constants for the Build editor
- Handle screen buffer management and video mode control for DOS environments

## External Dependencies
- **Includes:** `<dos.h>`, `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<string.h>`
- **DOS/x86 specifics:** `#pragma aux` for inline assembly (setvmode, drawpixel, clearbuf, copybuf); `int 0x10` BIOS video calls; video RAM at `0xa0000`; I/O port instructions (`outp`)
- **String functions:** `strnicmp()`, `strcpy()`, `strcat()`, `strchr()` (defined elsewhere)
- **I/O functions:** `open()`, `close()`, `read()`, `write()`, `lseek()`, `tell()` (POSIX/DOS standard library)
- **Video:** Direct access to VGA color registers (`outp(0x3c8/0x3c9)`) and video RAM

# UTIL/WAD2MAP.C
## File Purpose
Doom WAD to Build engine map converter. Reads Doom IWAD/PWAD files, extracts map geometry (sectors, walls, vertices, things), converts to Build engine format, applies optional script-based customizations, and outputs a .map file.

## Core Responsibilities
- Parse command-line arguments for IWAD, PWAD, map name, and optional conversion script
- Load and index WAD lumps (TEXTURE1, TEXTURE2, PNAMES, map data)
- Extract Doom map components (vertices, linedefs, sidedefs, sectors, things)
- Convert Doom map geometry to Build engine spatial representation
- Build sector-wall adjacency and connectivity
- Map Doom sprite types and textures to Build engine equivalents via lookup tables
- Parse optional script for custom field assignments and overrides
- Write binary Build .map output file

## External Dependencies

- **File I/O:** `open()`, `read()`, `write()`, `lseek()`, `close()`, `filelength()` (DOS/Watcom C)
- **String:** `stricmp()`, `strcpy()`, `strcat()`, `strchr()`, `atol()`
- **Memory:** `clearbufbyte()` (macro), `FP_OFF` (far pointer offset, DOS)
- **Math:** `klabs()`, `mulscale10()`, `ksqrtasm()` (inline ASM), `ksgn()`, `min()`, `max()`
- **Pragmas:** `#pragma aux` for inline ASM; `pragmas.h` defines build macros.
- **Includes:** `<fcntl.h>`, `<io.h>`, `<dos.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<string.h>`
- **Defined elsewhere:** `clearbufbyte()`, `ksqrtasm()`, `mulscale10()`, `klabs()`, `ksgn()` (likely in pragmas.h or linker).

