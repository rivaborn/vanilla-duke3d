# UTIL/EDITART.C — Enhanced Analysis

## Architectural Role

EDITART.C is an **isolated standalone tool** with no runtime dependency on the main engine (ENGINE.C, A.ASM). Unlike the editor (BUILD.C), which integrates closely with the rendering pipeline, EDITART communicates with the engine ecosystem only through disk I/O: it reads/writes .ART tile files and updates .MAP files when tiles are rearranged. This decoupling allows it to operate independently while maintaining consistency with map tile references—a pragmatic DOS-era design for content pipeline tooling.

## Key Cross-References

### Incoming (who depends on this file)
- **None** — EDITART functions are never called by other modules. It is a standalone executable entry point.

### Outgoing (what this file depends on)
- **DOS file I/O subsystem**: `open`, `read`, `write`, `close`, `lseek` for .ART, .MAP, image files
- **DOS BIOS & hardware**: `setvmode` (VGA mode switching), `outp` (VGA register I/O), mouse INT 0x33, keyboard interrupts, 8253 timer
- **Local utilities** (all inline): image decoders (PCX RLE, GIF LZW), flood fill, palette conversion
- **Data structure definitions**: Redefines `sectortype`, `walltype`, `spritetype` locally (does NOT include BUILD.H)
- **No calls to**: ENGINE.C, A.ASM, drawing primitives, or rendering functions

## Design Patterns & Rationale

**Local Data Structure Copies**: EDITART redefines sector/wall/sprite types instead of sharing BUILD.H. This allows independent compilation and version flexibility for tools, at the cost of maintaining two definitions.

**Monolithic Event Loop**: The 2000-line `main()` function implements a classic DOS-tool pattern: poll input → dispatch command → update display. No state machine abstraction, all logic inline. This was pragmatic in 1996: simple to debug, minimal function call overhead on 386/486 hardware.

**Lazy Tile Loading**: `loadpics()` only loads one .ART file at a time into the main `pic` buffer. The cross-reference shows this is called multiple times (from `main`, `gettile`, `selectbox`), managing memory by swapping files rather than loading all tiles at once.

**Map Update via Disk Scanning**: `updatemaps()` does a full filesystem scan and rewrite of all .MAP files when tiles are rearranged. No in-memory map state; changes are persisted immediately. Reflects the era's assumption that file I/O was acceptable for offline tools.

## Data Flow Through This File

```
Input → Keyboard/Mouse (polled)
       → .ART files (tile data, metadata)
       → Image files (BMP/PCX/GIF via selectbox → captureit)
       → .MAP files (via updatemaps for tile reference sync)
       
Transform → Draw pixels to buf, apply palette, manipulate dimensions
          → Resize tiles (reallocate pic buffer, shift offsets)
          → Swap/delete tiles (reorder waloff array)
          → Update palookup tables (shade effects)
          → Transcode image formats to 256-color indexed
          
Output → Write modified .ART files (savepics)
       → Write .MAP files with updated tile references (updatemaps)
       → PCX screenshots (capfilmode in captureit)
       → VGA video RAM for interactive display
```

**Key state transitions**:
- Load tile → Edit pixels → Save to .ART
- Select image area → Resize/place → Captureit → Save to tile slot
- Swap/resize tiles → Call updatemaps → Propagate changes to all .MAP files

## Learning Notes

**Idiomatic 1990s DOS Patterns**:
- Direct VGA register manipulation (Sequencer, CRTC, Graphics Controller) via `outp()`
- Inline x86 assembly pragmas for hardware-level operations (`#pragma aux setvmode`, `clearbuf`, `drawpixel`)
- Global state arrays (no encapsulation; `static` for linkage, not privacy)
- Interrupt handler installation for timer (`timerhandler`) and mouse polling
- Cooperative multitasking via `limitrate` (waits for vertical retrace to avoid tearing)

**Modern Game Engines Do Differently**:
- Would use a library abstraction (SDL, DirectX, Vulkan) instead of raw VGA I/O
- Would load all assets into memory at startup or use a streaming cache
- Would share data structures via headers/libraries, not duplicate definitions
- Would use structured serialization (JSON, Protocol Buffers) instead of binary formats
- Would separate UI from file I/O via an event system

**Interesting Design Insights**:
- The **palette system** is sophisticated: `palookup[32][256]` provides 32 shade levels per color, enabling distance fog and darkness without per-pixel lookups (cacheable on 1990s CPUs). Function `updatepanningforumode` applies palette shifting for lighting effects.
- **Image import pipeline**: BMP/PCX/GIF decoders are self-contained; `selectbox` allows interactive region selection with palette swap (P key), making it easy to extract game-ready tiles from artwork.
- **Tile metadata**: `picanm[MAXTILES]` encodes animation type, frame count, and offsets. The tool manages this, not the engine.
- **Cross-tool compatibility**: EDITART works alongside BUILD.C (the editor) because both respect the same .ART/.MAP formats. The `updatescript` call in `gettile` suggests integration with batch conversion pipelines.

## Potential Issues

**Data Consistency Risk**: `updatemaps()` rewrites all .MAP files when tiles are rearranged. If interrupted mid-write, maps could be corrupted. No atomic commits or backups visible in the code.

**Memory Fragmentation**: `resizetile()` reallocates the entire `pic` buffer and shuffles tile offsets. On a system with limited memory (16 MB in 1996), repeated resize operations could exhaust contiguous free space.

**Duplicate Data Definitions**: Local copies of sector/wall/sprite structs mean changes to BUILD.H won't automatically propagate to EDITART. Build/test discipline required to keep them in sync.

**No Runtime Bounds Checking**: Functions like `gettile()` trust user input and array dimensions without defensive checks. Clicking outside a valid region could access invalid memory.
