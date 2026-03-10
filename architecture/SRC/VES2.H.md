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

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| `VBE_vgaInfo` | struct | VBE 2.0 controller information (signature, version, pointers to mode list and vendor names) |
| `VBE_modeInfo` | struct | VBE mode attributes (resolution, color depth, memory model, window info, LFB base address) |
| `RMREGS` | union | Real-mode register access (word form: ax/bx/cx/dx/si/di/cflag, byte form: al/ah/bl/bh/cl/ch/dl/dh) |
| `RMSREGS` | struct | Real-mode segment registers (es, cs, ss, ds) |
| `_RMREGS` | struct | 32-bit real-mode register structure for DPMI calls |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `VESABuf_sel`, `VESABuf_rseg` | long/short | global | DPMI real-mode buffer selector and segment; allocated on first VBE call |
| `modelist[256]` | short[] | global | Array of VESA mode codes enumerated from BIOS |
| `screen` | char* | static | Software framebuffer pointer (used in buffered modes) |
| `vesachecked` | char | static | Flag to prevent redundant VESA enumeration |
| `xres`, `yres`, `bytesperline` | long | global | Current video mode dimensions and scanline byte width |
| `frameplace`, `imageSize`, `maxpages` | long | global | Active framebuffer address, single-page size, max page count |
| `buffermode`, `linearmode`, `origbuffermode` | long | global | Flags: buffered (0) vs direct (1), linear (1) vs banked (0), original buffer mode |
| `setactiveentry`, `setvisualentry`, `setpaletteentry` | long | global | Protected-mode function pointers from VBE 0x4f0a |
| `permanentupdate` | char | global | Full-screen update flag (bypasses dirty-region tracking) |
| `vgacompatible` | char | global | Mode supports VGA-compatible page flipping |
| `visualpagelookup[64][2]`, `activepagelookup[64]` | short[]/long[] | global | Page-to-address lookup tables (visual: X/Y coords, active: linear address) |
| `ves2lastx[MAXYDIM]` | long[] | static | Dirty-region tracking: last X coordinate updated per scanline |
| `vgaInfo` | VBE_vgaInfo | static | Cached VBE controller information |
| `globlinplace`, `backlinaddress` | long | global/static | Linear framebuffer address; backlinaddress saved for DPMI free |
| `davesapageshift` | long | static | Granularity shift for banked mode window switching |

## Key Functions / Methods

### DPMI_int86
- Signature: `long DPMI_int86(long intno, RMREGS *in, RMREGS *out)`
- Purpose: Issue a real-mode INT call via DPMI (INT 0x31) while in protected mode
- Inputs: Interrupt number, input register structure, output register pointer
- Outputs/Return: Copies modified registers to output structure; returns AX value
- Side effects: Calls `backupsegs()` / `restoresegs()` to preserve segment registers during DPMI call
- Calls: `segread()`, `int386x()`, `backupsegs()`, `restoresegs()`
- Notes: Used for BIOS calls (INT 0x10); only word registers modified

### DPMI_int86x
- Signature: `long DPMI_int86x(long intno, RMREGS *in, RMREGS *out, RMSREGS *sregs)`
- Purpose: Real-mode INT call with segment register preservation and output
- Inputs: Interrupt number, register structures, segment register structure
- Outputs/Return: Modifies output registers and segment registers; returns AX
- Side effects: Saves/restores all segment registers (ES, CS, SS, DS)
- Calls: `segread()`, `int386x()`, `backupsegs()`, `restoresegs()`
- Notes: Required for VBE 0x4f0a (get protected-mode entry points)

### VBE_callESDI
- Signature: `void VBE_callESDI(RMREGS *regs, void *buffer, long size)`
- Purpose: Execute VBE INT 0x10 call with buffer data passed via real-mode ES:DI
- Inputs: Register structure, data buffer, buffer size
- Outputs/Return: Modifies registers in-place; buffer may be modified by BIOS
- Side effects: Allocates 1KB DPMI real-mode buffer on first call (registered for cleanup via `atexit()`)
- Calls: `int386()`, `_fmemcpy()`
- Notes: Handles buffer transfer to/from real-mode segment; caches selector for reuse

### VBE_getModeInfo
- Signature: `long VBE_getModeInfo(long mode, VBE_modeInfo *modeInfo)`
- Purpose: Query VBE mode information via INT 0x10 / 0x4f01
- Inputs: VESA mode code, pointer to mode info structure
- Outputs/Return: Returns 1 on success (mode available and 8-bit packed pixel), 0 on failure
- Side effects: Calls `VBE_callESDI()` which modifies DPMI real-mode buffer
- Calls: `VBE_callESDI()`
- Notes: Validates ModeAttributes bit 0 (available) and memory model (8-bit packed pixel only)

### GetPtrToLFB
- Signature: `GetPtrToLFB(long physAddr)` (no return type declared)
- Purpose: Map physical LFB address to protected-mode linear address via DPMI
- Inputs: Physical address from mode info
- Outputs/Return: Sets `globlinplace` and `backlinaddress` globals; no explicit return
- Side effects: Allocates DPMI selector, maps physical address, sets selector base and limit
- Calls: `int386()`, `backupsegs()`, `restoresegs()`
- Notes: Allocates 4MB-1 byte limit; saves address for later DPMI free; exits on failure

### getvalidvesamodes
- Signature: `getvalidvesamodes()` (no return type/params declared)
- Purpose: Enumerate all VESA modes, filter for 8-bit packed-pixel modes, sort by resolution
- Inputs: None (uses global `vesachecked` flag)
- Outputs/Return: Populates `modelist[]`, `validmode[]`, `validmodexdim[]`, `validmodeydim[]`, `validmodecnt`
- Side effects: Sets `vesachecked` flag to avoid re-enumeration; calls VBE 0x4f00 and 0x4f01
- Calls: `VBE_callESDI()`, `VBE_getModeInfo()`
- Notes: Two-pass sort: by Y resolution, then by X; terminates on first enumeration

### setvesa
- Signature: `setvesa(long x, long y)` (no return type declared)
- Purpose: Set video mode to specified resolution; configure linear or banked framebuffer
- Inputs: X and Y resolution
- Outputs/Return: Returns 0 on success, -1 if mode not found; sets global video state
- Side effects: Calls VBE 0x4f01 and 0x4f02; calls `GetPtrToLFB()` for linear modes; sets frame buffers and lookup tables
- Calls: `getvalidvesamodes()`, `VBE_callESDI()`, `DPMI_int86()`, `DPMI_int86x()`, `GetPtrToLFB()`
- Notes: Searches `validmode[]` list for matching resolution; extracts protected-mode function pointers from VBE 0x4f0a; handles linear vs. banked granularity setup

### setdacbits
- Signature: `setdacbits(long newdacbits)`
- Purpose: Set DAC (palette) color depth (6 or 8 bits) via VBE 0x4f08
- Inputs: Desired DAC bit width
- Outputs/Return: Returns current DAC bits (from BH register)
- Side effects: Calls DPMI INT 0x10
- Calls: `DPMI_int86()`
- Notes: Only functions if VBE supports it (Capabilities bit 0); returns 6 on unsupported

### setactivepage
- Signature: `void setactivepage(long dapagenum)`
- Purpose: Set the page used for drawing (target framebuffer)
- Inputs: Page index
- Outputs/Return: Updates `frameplace` global
- Side effects: In banked 320x200 mode, calls `setvesapage()` to switch window
- Calls: `setvesapage()` macro, `DPMI_int86()`
- Notes: Buffered or linear modes set frameplace to software buffer or LFB; banked mode switches window

### setvisualpage
- Signature: `void setvisualpage(long dapagenum)`
- Purpose: Set visible page and perform dirty-region copy from active to visual framebuffer
- Inputs: Page index (negative bit 31 for skip timer handler)
- Outputs/Return: None (modifies video memory)
- Side effects: Performs `copybufbyte()` operations; calls `setvesapage()` in banked mode; calls `faketimerhandler()` periodically
- Calls: `setvesapage()`, `DPMI_int86()`, `copybufbyte()`, `faketimerhandler()`, `qlimitrate()`
- Notes: Complex logic: in linear buffered mode, uses dirty region (`ves2lastx[]`, `startumost[]`, `startdmost[]`) to copy only changed pixels; in banked mode, handles window bank transitions

### uninitvesa
- Signature: `uninitvesa()` (no return type/params declared)
- Purpose: Clean up VESA/DPMI resources on shutdown
- Inputs: None
- Outputs/Return: None
- Side effects: Frees physical address mapping and DPMI buffer selector
- Calls: `int386()`, `backupsegs()`, `restoresegs()`
- Notes: Resets `backlinaddress`, `VESABuf_sel`, and `vesachecked` for reinit

### VBE_setPalette
- Signature: `VBE_setPalette(long start, long num, char *dapal)`
- Purpose: Update palette entries via VBE 0x4f09 or direct VGA port I/O
- Inputs: Starting palette index, number of entries, palette data (RGBA format)
- Outputs/Return: Returns 1 on success, 0 on VBE failure
- Side effects: Writes to VGA I/O ports (0x3c8, 0x3c9, 0x3da) or calls `vesasetpalette()` protected-mode function
- Calls: `vesasetpalette()`, `VBE_callESDI()`, `DPMI_int86()`, `koutp()`, `kinp()`
- Notes: Handles stereo mode band color overrides; fallback to VGA port I/O for compatibility

### VBE_getPalette
- Signature: `VBE_getPalette(long start, long num, char *dapal)`
- Purpose: Read palette entries via VBE 0x4f09 or direct VGA port I/O
- Inputs: Starting palette index, number of entries, palette data buffer
- Outputs/Return: Returns 1 on success, 0 on VBE failure
- Side effects: Reads VGA I/O ports or calls VBE
- Calls: `VBE_callESDI()`, `koutp()`, `kinp()`
- Notes: Output format is RGBA; mirrors setPalette fallback logic

**Notes on trivial helpers:**
- `qlimitrate`: Inline asm to wait for VGA retrace
- `backupsegs`, `restoresegs`, `setvmode`: Segment and BIOS call wrappers
- `copybufbyte`: Optimized aligned/unaligned memory copy
- `vesasetactive`, `vesasetvisual`, `vesasetpalette`: Protected-mode function call wrappers
- `setvesapage()`: Macro to set window in banked mode

## Control Flow Notes
**Init:** Engine calls `setvesa(width, height)` → `getvalidvesamodes()` enumerates modes → VBE 0x4f02 sets mode → `GetPtrToLFB()` maps LFB in protected mode → page lookup tables initialized.

**Per-frame:** 
1. `setactivepage()` selects drawing target (buffered: software buffer, linear: LFB page, banked: sets window)
2. Rendering writes pixels
3. `setvisualpage()` flips to visible buffer: in buffered/linear mode, copies dirty pixels via `copybufbyte()`; in banked mode, switches window and copies scanline-by-scanline with bank transitions

**Shutdown:** `uninitvesa()` frees DPMI selector and address mapping.

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
