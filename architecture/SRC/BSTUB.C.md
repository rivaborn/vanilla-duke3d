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

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `spritetype` | struct | Sprite entity data (imported from build.h) |
| `sectortype` | struct | Sector/room data (imported from build.h) |
| `walltype` | struct | Wall segment data (imported from build.h) |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `tempbuf` | `char[256]` | static | Temporary buffer for string formatting (labels, messages) |
| `hang` | `long` | static | Horizontal viewing angle rotation in editor (for 3D tilt) |
| `vesares` | `long[13][2]` | static | VESA video mode resolution table (320×200 to 1600×1200) |
| `option` | `char[NUMOPTIONS]` | static | Config array: vidoption, resolution index, etc. |
| `keys` | `char[NUMKEYS]` | static | Scan codes for editor keybinds |
| `keystatus` | `char[256]` | extern | Global keyboard state array |
| `qsetmode` | `long` | extern | Video mode flag (200=3D, 350/480=2D) |
| `frameplace` | `long` | extern | Frame buffer memory address |
| `totalclock` | `long volatile` | extern | Global frame counter (120 ticks/sec) |
| `ofinetotalclock`, `ototalclock` | `long` | extern | FPS calculation state |
| `averagefps` | `long` | extern | Smoothed FPS display value |
| `frameval` | `long[AVERAGEFRAMES]` | static | Ring buffer of per-frame FPS samples |
| `daviewingrange`, `daaspect`, `horizval1/2` | `long` | static | 3D view geometry for rotated display |

## Key Functions / Methods

### ExtInit
- **Signature:** `void ExtInit(void)`
- **Purpose:** Initialize engine, load configuration, set up palette and voxel management.
- **Inputs:** None (reads from file system: `setup.dat`, `stuff.dat`)
- **Outputs/Return:** None (modifies global state)
- **Side effects:** Loads configuration from disk, initializes mouse/engine, sets video mode, creates palette lookup table for sector shading, allocates voxel cache.
- **Calls:** `initgroupfile()`, `open()`, `read()`, `memcpy()`, `initmouse()`, `initengine()`, `makepalookup()`, `inittimer42()`
- **Notes:** Configuration failure is silent (file optional). Remap palette trick for screwy palette sectors.

### ExtUnInit
- **Signature:** `void ExtUnInit(void)`
- **Purpose:** Clean up timer and group file on shutdown.
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:** Halts timer2 hardware, closes groupfile.
- **Calls:** `uninittimer42()`, `uninitgroupfile()`

### ExtPreCheckKeys
- **Signature:** `void ExtPreCheckKeys(void)`
- **Purpose:** Handle keyboard input before frame logic (screen resize, viewing angle adjustments).
- **Inputs:** Reads `keystatus[]` array
- **Outputs/Return:** None (modifies view state)
- **Side effects:** Changes video mode, updates `hang` angle, allocates/writes tile 4094 for rotated display, calls `setviewtotile()`, modifies aspect ratio and horizon.
- **Calls:** `getvalidvesamodes()`, `setgamemode()`, `inittimer42()`, `allocache()`, `setviewtotile()`, `setaspect()`, `scale()`, `dmulscale1()`, `divscale15()`
- **Notes:** F4 cycles VESA modes. Shift-held arrow keys rotate view more slowly. Numeric keypad del/home tilt view, numeric 5 resets. Tile 4094 is temporary buffer for perspective-rotated view rendering.

### ExtCheckKeys
- **Signature:** `void ExtCheckKeys(void)`
- **Purpose:** Per-frame input processing in 3D mode: render rotated view overlay, update FPS display, handle aspect ratio adjustment keys.
- **Inputs:** Reads `keystatus[]`, `totalclock`, `gettimer42()`, `qsetmode`
- **Outputs/Return:** None (modifies UI/graphics and frame statistics)
- **Side effects:** Writes stretched line to frame buffer if `hang != 0`, updates FPS counter history, calls `editinput()` for main editor input.
- **Calls:** `stretchhline()`, `setviewback()`, `dmulscale1()`, `mulscale14()`, `divscale16()`, `ylookup[]`, `sprintf()`, `printext256()`, `inittimer42()`, `setaspect()`, `editinput()`
- **Notes:** FPS calculation uses 32-frame rolling window. Aspect ratio adjustment tied to numeric keys a-d. Timer initialization required here because VESA mode-set disrupts timer2.

### ExtAnalyzeSprites
- **Signature:** `void ExtAnalyzeSprites(void)`
- **Purpose:** Transform and prepare sprites for rendering (load voxels, adjust scale/appearance).
- **Inputs:** `tsprite[]` array from render queue, `spritesortcnt`
- **Outputs/Return:** None (modifies sprite data in place)
- **Side effects:** Loads KVX voxel files on demand (`qloadkvx()`), scales sprite repeat/size, modifies cstat and shade, accesses `sector[]` for shading inheritance.
- **Calls:** `qloadkvx()`, `scale()`
- **Notes:** Hardcoded for two sprite types (PLAYER→voxel000.kvx, BROWNMONSTER→voxel001.kvx). Inherits ceiling/floor shade from containing sector.

### ExtGetSectorCaption, ExtGetWallCaption, ExtGetSpriteCaption
- **Signature:** `const char *ExtGet{Sector|Wall|Sprite}Caption(short {sectnum|wallnum|spritenum})`
- **Purpose:** Return formatted label string for map elements (hitag,lotag).
- **Inputs:** Sector/wall/sprite index
- **Outputs/Return:** Pointer to static `tempbuf` with formatted string or empty
- **Side effects:** Writes to `tempbuf`
- **Calls:** `sprintf()`
- **Notes:** Returns empty string if both tags are zero. Uses format `"%hu,%hu"` for unsigned short display.

### ExtShowSectorData, ExtShowWallData, ExtShowSpriteData
- **Signature:** `void ExtShow{Sector|Wall|Sprite}Data(short {sectnum|wallnum|spritenum})`
- **Purpose:** Display element properties in 2D editor mode status bar (stub implementations).
- **Inputs:** Element index
- **Outputs/Return:** None (renders to screen)
- **Side effects:** Clears/writes to status bar region.
- **Calls:** `clearmidstatbar16()`, `printext16()`, `drawline16()`
- **Notes:** Only functional in 2D mode (`qsetmode != 200`). SectorData demo draws a house shape. Wall/Sprite versions are minimal stubs.

### ExtEditSectorData, ExtEditWallData, ExtEditSpriteData
- **Signature:** `void ExtEdit{Sector|Wall|Sprite}Data(short {sectnum|wallnum|spritenum})`
- **Purpose:** Edit properties for map elements (stubs with example implementations).
- **Inputs:** Element index
- **Outputs/Return:** None
- **Side effects:** In 3D mode: modifies sector ceiling/floor properties (example only). In 2D mode: displays input dialog via `getnumber16()`.
- **Calls:** `getnumber16()`, `printmessage16()`, `ExtShow*Data()`
- **Notes:** 3D mode examples increment ceiling picnum, floor shade (placeholder). 2D mode prompts for "Nick's variable" (developer reference, non-functional).

## Control Flow Notes

**Initialization phase:**
- `ExtInit()` called at startup; loads config, sets video mode, initializes palette/mouse/engine.

**Per-frame execution:**
1. `ExtPreCheckKeys()` – handle screen resize, viewing angle, aspect ratio before main logic.
2. Main render loop calls `ExtAnalyzeSprites()` to prepare sprites for 3D rendering.
3. `ExtCheckKeys()` – display rotated view overlay (if tilting), update FPS, handle aspect ratio keys, delegate to `editinput()` for main editor input.
4. Editor UI functions (`ExtShow*/ExtEdit*`) called by main loop on F5–F8 keypresses.

**Shutdown phase:**
- `ExtUnInit()` cleans up timer and group file.

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
