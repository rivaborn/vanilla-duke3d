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

## Key Types / Data Structures
None.

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| bpl | long | static | Screen pitch (bytes per line) |
| transmode | long | static | Translucence blend mode (0=normal, 1=reverse) |
| glogx | long | static | Log2 of texture width (for bit-shift addressing) |
| glogy | long | static | Log2 of texture height |
| gbxinc | long | static | X texture coordinate step per pixel |
| gbyinc | long | static | Y texture coordinate step per pixel |
| gpinc | long | static | Screen buffer pitch for vertical traversal |
| gbuf | char* | static | Texture buffer pointer |
| gpal | char* | static | Palette lookup table pointer |
| ghlinepal | char* | static | Palette for horizontal line ops |
| gtrans | char* | static | Translucence blending lookup table (indexes: `[dst+(src<<8)]`) |

## Key Functions / Methods

### hlineasm4
- Signature: `hlineasm4(long cnt, long skiploadincs, long paloffs, unsigned long by, unsigned long bx, long p)`
- Purpose: Draw a textured horizontal line (ceiling/floor)
- Inputs: cnt=pixel count; skiploadincs=if false, load increments from asm1/asm2; paloffs=palette base; bx/by=texture coordinates (fixed-point); p=screen address
- Outputs/Return: void (writes pixels to screen buffer)
- Side effects: Conditionally loads gbxinc/gbyinc from extern asm1/asm2
- Calls: none
- Notes: Uses log-address: `((bx>>(32-glogx))<<glogy)+(by>>(32-glogy))` for 2D texture lookup; decrements bx/by each iteration

### slopevlin
- Signature: `slopevlin(long p, long i, long slopaloffs, long cnt, long bx, long by)`
- Purpose: Draw a perspective-corrected vertical line on a sloped surface
- Inputs: p=screen position; slopaloffs=array of palette ptrs; cnt=pixel count; bx/by=texture coords
- Outputs/Return: void
- Side effects: Reads extern asm1, asm3, globalx3, globaly3; modifies screen buffer
- Calls: `krecip()` (reciprocal lookup)
- Notes: Applies perspective correction via reciprocal; increments palette pointer per iteration (slopalptr--)

### vlineasm1 / mvlineasm1 / tvlineasm1
- Signature: `vlineasm1(long vinc, long paloffs, long cnt, unsigned long vplc, long bufplc, long p)` (masked/translucent variants similarly)
- Purpose: Draw textured vertical line; masked variant skips color 255; translucent variant blends via gtrans table
- Inputs: vinc=V increment; paloffs=palette; cnt=pixel count; vplc=V coordinate (16.16 fixed); bufplc=texture buffer; p=screen position
- Outputs/Return: void
- Side effects: Sets gbuf/gpal; modifies screen buffer
- Calls: none
- Notes: vlineasm1 unconditionally writes; mvlineasm1 checks `if (ch != 255)`; tvlineasm1 respects transmode for blend direction

### mhline / thline
- Signature: `mhline(long bufplc, unsigned long bx, long cntup16, long junk, unsigned long by, long p)` (translucent variant similar)
- Purpose: Draw masked/translucent horizontal line (floor sprites)
- Inputs: bufplc=texture buffer; bx/by=texture coords; cntup16=count in 16.16 fixed-point; p=screen position; junk=unused
- Outputs/Return: void
- Side effects: Uses extern asm1, asm2, asm3; modifies screen buffer
- Calls: none
- Notes: mhline skips 255; thline blends via gtrans with transmode control; increments via asm1/asm2

### spritevline / mspritevline / tspritevline
- Signature: `spritevline(long bx, long by, long cnt, long bufplc, long p)` (masked/translucent variants)
- Purpose: Draw vertical line for rotated/scaled sprites
- Inputs: bx/by=X/Y in 16.16 fixed-point; cnt=pixel count; bufplc=texture buffer; p=screen position
- Outputs/Return: void
- Side effects: Modifies screen buffer; uses gbxinc/gbyinc/glogy
- Calls: none
- Notes: Address formula: `(bx>>16)*glogy+(by>>16)` treats glogy as stride; masked variant checks 255; translucent variant uses gtrans

**Setup Functions** (trivial): `setvlinebpl`, `settransnormal`, `settransreverse`, `fixtransluscence`, `sethlinesizes`, `setpalookupaddress`, `setuphlineasm4`, `setupslopevlin`, `setupvlineasm`, `setupmvlineasm`, `setuptvlineasm`, `setupspritevline`, `msetupspritevline`, `tsetupspritevline`, `msethlineshift`, `tsethlineshift` — all configure static state variables.

## Control Flow Notes
This is a low-level rendering backend. The typical flow: setup functions configure state (palette, texture buffer, pitch), then draw functions execute pixel loops writing to a framebuffer. External callers (scanline renderers) invoke setup once per span, then draw per-pixel or per-scanline. The globals (asm1, asm3, globalx3, globaly3) are likely set externally per-frame for camera/transform state.

## External Dependencies
- `extern long asm1, asm2, asm3, asm4, fpuasm, globalx3, globaly3;` — External transformation registers or pre-computed values
- `extern void *reciptable;` — Reciprocal lookup table (declared but not used in visible code)
- `krecip()` — Reciprocal function (called in slopevlin, defined elsewhere)
