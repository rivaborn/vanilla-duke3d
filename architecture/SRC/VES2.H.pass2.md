# SRC/VES2.H — Enhanced Analysis

## Architectural Role

VES2.H is the **exclusive graphics abstraction layer** for the Build Engine, mediating all communication between the rendering pipeline (ENGINE.C) and DOS/x86 video hardware via VESA VBE 2.0 and DPMI. It detects and switches video modes, manages framebuffer addressing (linear LFB or banked windows), handles page flipping with dirty-region tracking, and provides palette I/O. By encapsulating DPMI complexity and the linear/banked dichotomy, it allows rendering code to assume a uniform `frameplace` pointer and `setactivepage`/`setvisualpage` API, hiding 1990s DOS hardware constraints from ENGINE.C.

## Key Cross-References

### Incoming (who depends on this file)
- **ENGINE.C**: Calls `setactivepage()` and `setvisualpage()` in per-frame rendering loop (implicit; referenced in first-pass as render target management)
- **BSTUB.C / SRC/BUILD.C**: Calls `setvesa(width, height)` at editor initialization to set video mode
- **UTIL/SETUP.C**: Calls `setvmode` (4 callers total per cross-ref: `VBE_getPalette`, `gettile`, `main`) during graphics menu and palette testing
- **UTIL/EDITART.C**: Calls `setvmode` in tile editor startup
- **UTIL/TRANSPAL.C**: Calls `setvmode` during palette lookup table generation

### Outgoing (what this file depends on)
- **PRAGMAS.H**: Uses `koutp`/`kinp` (VGA I/O port wrappers), `backupsegs`/`restoresegs` (segment register preservation macros), `setvmode` (INT 0x10 wrapper)
- **Watcom C runtime**: `int386`, `int386x` (DPMI INT 0x31), `segread` (segment query), `_fmemcpy` (far memory copy), `MK_FP`/`FP_OFF` (far pointer arithmetic), `atexit` (cleanup callback registration)
- **DOS BIOS/DPMI**: INT 0x10 (video BIOS), INT 0x31 (DPMI protected-mode calls)
- **BUILD.H globals** (implicit): Uses `waloff[]`, `activepagelookup[]`, `frameplace` (set by this file; read by rendering code)

## Design Patterns & Rationale

### 1. **Framebuffer Abstraction via Global Page Pointers**
The file exports `frameplace` (current draw target) and `setactivepage`/`setvisualpage` functions. Whether the GPU is linear-addressable or banked is hidden behind these globals. ENGINE.C writes pixels uniformly; VES2.H routes writes to LFB, a 64KB window, or software RAM depending on `linearmode` and `buffermode` flags.

**Rationale**: Decouples rendering from hardware details; allows runtime mode selection (linear LFB preferred, fallback to banked, then software buffering).

### 2. **Dirty-Region Tracking via ves2lastx[MAXYDIM]**
When in buffered banked mode, `ves2lastx[]` records the rightmost dirty pixel per scanline. In `setvisualpage()`, only scanlines with `ves2lastx[y] > 0` trigger copies from active to visual page. Combined with `startumost[]`/`startdmost[]` bounds, this avoids full-frame memcpy in modes where most scanlines are static.

**Rationale**: 320×200 banked modes require window bank switches per ~16 scanlines; dirty tracking amortizes the cost across frames where only a few scanlines change (e.g., static HUD, dynamic viewport center).

**Limitation**: Granularity is per-scanline, not per-region; a single pixel change marks the entire scanline dirty.

### 3. **Lazy DPMI Real-Mode Buffer Allocation**
`VESABuf_sel` and `VESABuf_rseg` allocated on first VBE call via DPMI INT 0x31 function 0x100 (allocate real-mode segment). Buffer reused for all subsequent VBE calls (0x4f00, 0x4f01, 0x4f09). Cleanup via `atexit()` handler.

**Rationale**: VBE BIOS calls expect real-mode-accessible data (e.g., mode info structures at ES:DI). DPMI requires allocation from real-mode memory; a 1KB buffer is sufficient for all VBE requests and avoids per-call overhead.

**Pattern**: Singleton-like initialization; non-reentrant.

### 4. **Protected-Mode Callback Extraction**
`setvesa()` calls VBE 0x4f0a to retrieve pointers to `setactiveentry`, `setvisualentry`, `setpaletteentry` — protected-mode function entry points in the VESA driver. These are then called directly (via `vesasetactive` etc. macros) instead of round-tripping through DPMI INT 0x31 for each page flip.

**Rationale**: Per-frame operations (page flipping) are performance-critical. Extracting function pointers once and calling them directly avoids DPMI switching overhead per flip.

**Complexity**: Requires parsing real-mode far pointers (`p = (short *)(((ptr & 0xffff0000) >> 12) + (ptr & 0xffff))`) and converting them to linear offsets within the mode info structure.

### 5. **Granularity Shift Lookup (davesapageshift)**
Banked modes specify window granularity (64K, 32K, 16K, 8K, 4K, 2K, 1K). The code converts granularity to a bit shift (0–6) for fast division: `bankoffset >> davesapageshift` instead of `bankoffset / granularity`.

```c
switch(modeInfo.WinGranularity) {
    case 64: davesapageshift = 0; break;  // >> 0
    case 32: davesapageshift = 1; break;  // >> 1
    ...
    case 1: davesapageshift = 6; break;   // >> 6
}
```

**Rationale**: Bit shifts are single-cycle on x86; divisions are ~30+ cycles. Critical path for banked mode rendering.

**Code smell**: Variable name "davesapageshift" suggests a developer name; likely an artifact of authorship or debugging.

### 6. **Segment Register Preservation Wrappers**
All DPMI INT 0x31 calls sandwiched with `backupsegs()` (save DS/ES/SS) and `restoresegs()` (restore). DPMI can clobber these registers; preserving them ensures C runtime (malloc, stdio, etc.) remains consistent.

**Rationale**: DPMI is a low-level service; C runtime assumes stable segment context. Loss of DS breaks global variable access.

**Pattern**: Assembly glue hiding CPU-level detail (segment registers don't exist in modern architectures).

## Data Flow Through This File

### Initialization (One-Time)
```
Engine startup calls setvesa(x, y)
  ├─ getvalidvesamodes() [cached; runs only once if vesachecked=0]
  │   ├─ VBE 0x4f00 → vgaInfo (controller signature, video mode list pointer)
  │   ├─ Parse real-mode video mode list pointer via MK_FP
  │   └─ For each mode: VBE 0x4f01 → modeInfo
  │       └─ Filter: ModeAttributes&1 (available), MemoryModel==4 (packed pixel), BitsPerPixel==8, Planes==1
  │       └─ Sort: first by Y resolution, then by X resolution
  │
  ├─ Search validmode[] for matching (x, y)
  │
  ├─ VBE 0x4f02 → set video mode (bx = mode | ((LFB flag) << 7))
  │
  ├─ If LFB supported (ModeAttributes&128):
  │   ├─ GetPtrToLFB(modeInfo.PhysBasePtr)
  │   │   ├─ DPMI 0x100: allocate selector
  │   │   ├─ DPMI 0x9: set access rights (data, 32-bit)
  │   │   ├─ DPMI 0x800: map physical address to linear (globlinplace)
  │   │   ├─ DPMI 0x7: set selector base
  │   │   └─ DPMI 0x8: set selector limit (4MB-1)
  │   ├─ Set linearmode=1, buffermode=(maxpages<=1)
  │   └─ Initialize activepagelookup[i] = globlinplace + i*imageSize
  │
  ├─ Else (banked):
  │   ├─ Convert WinGranularity → davesapageshift
  │   ├─ Special case 320×200 with ≥2 pages: buffermode=0 (direct window writes)
  │   ├─ Else: buffermode=1 (software double-buffer)
  │
  └─ VBE 0x4f0a → extract protected-mode callback pointers (setactiveentry, setvisualentry, setpaletteentry)
```

### Per-Frame Rendering Loop
```
Rendering phase:
  setactivepage(pagenum)
    └─ Set frameplace to target page (LFB page, banked window via setvesapage, or software buffer)
  
  ENGINE.C::drawrooms() / drawmasks() / etc.
    └─ Writes pixels to frameplace
  
Display flip:
  setvisualpage(pagenum)
    ├─ In buffered linear mode:
    │   └─ Copy dirty scanlines from active to visual page
    │       ├─ For y in [startumost[x]…startdmost[x]]:
    │       │   if (ves2lastx[y] > 0)  // Dirty
    │       │     copybufbyte(active_y, visual_y, ves2lastx[y])
    │       └─ Call faketimerhandler() periodically to prevent timer interrupt starvation
    │
    ├─ In banked mode:
    │   ├─ Set window to visual page via setvesapage()
    │   ├─ Copy scanlines with bank transitions (each 64KB window covers ~16-32 lines)
    │   └─ Call faketimerhandler() between banks
    │
    └─ In linear mode (no copy needed; direct writes to VRAM)
```

### Palette Updates
```
VBE_setPalette(start, num, palette_data)
  ├─ If setpaletteentry (protected-mode function available):
  │   └─ vesasetpalette(0x4f09, start, num, palette_data) → direct call
  │
  └─ Else:
      ├─ Try VBE 0x4f09 via VBE_callESDI()
      └─ Fallback: Direct VGA port I/O
          ├─ Wait for retrace (0x3da bit 0)
          ├─ outp(0x3c8, start) → set palette index
          └─ outp(0x3c9, R/G/B) × num → write palette entries
```

## Learning Notes

### Engine-Specific Patterns
- **DPMI abstraction**: All OS/hardware calls wrapped in DPMI INT 0x31 to maintain protected mode; BIOS remains in real mode
- **Selector management**: Memory addressable only through segment selectors; physical addresses converted to linear, then to selectors
- **Real-mode buffer marshaling**: Data structures copied to/from real-mode RAM for BIOS calls; hidden in `VBE_callESDI()`

### Idiomatic to 1990s DOS/x86
- **Page flipping as core animation**: Video memory large enough for 2–4 full frames; flip between them avoids tearing and allows double/triple buffering
- **Banked memory strategy**: VRAM limited (1–4MB); 64KB "window" swaps in different banks; granularity lookups avoid expensive divisions
- **Assembly for hardware I/O**: x86 IN/OUT instructions and segment registers can't be expressed in C; inline asm is unavoidable
- **Canned lookup tables**: Precomputed granularity shifts (instead of log₂ or division) are typical for real-time constraints
- **Interrupt-driven rendering pause**: `faketimerhandler()` calls prevent system timer starvation during long memory copies

### Modern Engines Do Differently
- **Unified flat memory**: 64-bit protected mode; no segments, no real-mode callbacks
- **GPU abstraction layers**: Vulkan/DirectX/Metal; no VESA or direct VGA access; vendor drivers handle hardware details
- **Hardware page flipping**: Scanline interrupts and triple-buffering built into GPU; no software page management
- **Dirty-region tracking obsolete**: VRAM bandwidth abundant; full-screen updates acceptable
- **No timer starvation**: OS preemption and modern CPU speeds eliminate concern for long copies

### Connections to Game Engine Concepts
- **Framebuffer abstraction** (analog to modern render targets): Decouples rendering from output device
- **Page flipping** (analog to SwapChain in modern APIs): Double-/triple-buffering for smooth animation
- **Dirty-region culling** (ancestor of viewport/scissor): Only update changed regions; early optimization for bandwidth-constrained hardware
- **Mode enumeration** (similar to GPU capability queries): Discover available resolutions; validate hardware support before use

## Potential Issues

### 1. **No Return Type Declarations**
Functions `GetPtrToLFB`, `getvalidvesamodes`, `setvesa` lack explicit return types. In C89, defaults to `int`, but modern compilers warn or reject. Makes error propagation unclear (setvesa returns -1 on failure, but callers may not check).

### 2. **Unguarded Exit in GetPtrToLFB**
DPMI selector/limit setup calls directly `exit(0)` on any failure. No error propagation; engine terminates without user-visible error message if LFB mapping fails.

### 3. **Dirty-Region State Not Preserved Across Mode Changes**
`ves2lastx[]` tracking is per-mode, but if `setvesa()` is called twice (mode change), old dirty state is discarded. Next `setvisualpage()` performs full-frame copy, even if only a single pixel changed.

### 4. **Stack Smashing Risk in copybufbyte Alignment Logic**
The inline asm tests `edi` for byte/word/dword alignment and adjusts `ecx` accordingly. If alignment tests are incorrect or `ecx` is already consumed, subsequent `rep movsX` can read/write past buffer bounds.

### 5. **Hardcoded Array Limits (64 Pages, 256 Modes)**
`visualpagelookup[64][2]`, `activepagelookup[64]`, and `modelist[256]` are fixed-size. High-resolution, high-color-depth modes, or unusual VESA implementations could exceed limits, causing silent buffer overflow.

### 6. **Selector Leak on Mode Reinitialization**
If `setvesa()` is called twice without `uninitvesa()` in between, the DPMI selector from the first call is lost (overwritten in `globlinplace`); DPMI resources are not freed.

### 7. **No Timeout on Timer Starvation Prevention**
`setvisualpage()` calls `faketimerhandler()` periodically during copies, but if rendering is slow enough that consecutive calls exceed timer period, subsequent timer interrupts are missed, and animations stall.

### 8. **Assumes 32-bit DPMI Registers**
DPMI call structures use 32-bit register fields (`eax`, `ebx`, etc.). If VES2.H is compiled for a hypothetical 16-bit protected-mode system, these register sizes are wrong, corrupting DPMI call parameters.

### 9. **Missing Null Check in Mode Info Parsing**
`setvesa()` parses mode info without verifying DPMI buffer was successfully allocated; `modeInfo` pointer is uninitialized if `VBE_callESDI()` fails silently.
