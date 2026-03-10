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

## Key Types / Data Structures

None.

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `_asm1`, `_asm2`, `_asm3`, `_asm4` | dword | global | Parameter passing; xinc, yinc, shade offsets, etc. |
| `_reciptable` | near (table) | global | Reciprocal lookup for slope calculations |
| `_fpuasm` | dword | global | FPU temporary storage for floating-point calculations |
| `_globalx3`, `_globaly3` | dword | global | Coordinate multipliers for slope mapping |
| `_ylookup` | near (table) | global | Scanline address lookup (vertical offset to framebuffer) |
| `_vplce` | near (array) | global | Vertical place values (4 columns) |
| `_vince` | near (array) | global | Vertical increment values (4 columns) |
| `_palookupoffse` | near (array) | global | Palette lookup base addresses (4 columns) |
| `_bufplce` | near (array) | global | Texture buffer place addresses (4 columns) |
| `_ebpbak`, `_espbak` | dword | global | Register backups for slope rendering |
| `_pow2char`, `_pow2long` | near (tables) | global | Power-of-2 lookup tables |

## Key Functions / Methods

### sethlinesizes_
- **Signature:** `void sethlinesizes_(al=xbits, bl=ybits, ecx=offset)`
- **Purpose:** Configure horizontal line drawing parameters by patching self-modifying code locations.
- **Inputs:** `al` (x-shift bits), `bl` (y-shift bits), `ecx` (buffer offset)
- **Outputs/Return:** None; modifies code in-place
- **Side effects:** Patches 24+ code locations with hardcoded shift amounts and masks
- **Calls:** None
- **Notes:** Self-modifying code; used before each hline batch to configure texture sample shifts and masks

### hlineasm4_
- **Signature:** `void hlineasm4_(esi=ypos, edx=xinc, edi=xpos, eax=count)`
- **Purpose:** Draw horizontal line (4-pixel unrolled loop) with texture sampling and palette lookup.
- **Inputs:** `eax` (pixel count), `esi` (y-position), `edx` (x-increment), `edi` (x-position), `_asm1`/`_asm2` (position increments)
- **Outputs/Return:** Updates framebuffer at destination
- **Side effects:** Writes to framebuffer; modifies `esi`, `edx` for next line
- **Calls:** (none visible; uses patched indirect references)
- **Notes:** Unrolls 4 pixels per iteration; handles 1, 2, and 4-byte aligned writes; uses dynamic bit shifts from setup

### setupvlineasm_
- **Signature:** `void setupvlineasm_(al=shy)`
- **Purpose:** Configure vertical line drawing bit shifts and masks.
- **Inputs:** `al` (shift amount for y-coordinate)
- **Outputs/Return:** Patches code locations
- **Side effects:** Writes to 12+ code patch sites
- **Calls:** None
- **Notes:** Computes `(1<<shy)-1` mask for multi-pixel vertical loops

### vlineasm1_
- **Signature:** `void vlineasm1_(eax=yinc, ebx=palookup, ecx=count, edx=ypos, esi=bufbase, edi=vidpos)`
- **Purpose:** Draw single-column vertical line with palette translation.
- **Inputs:** `eax` (y-increment), `ebx` (palette lookup table), `ecx` (pixel count), `edx` (y-position), `esi` (texture buffer), `edi` (video RAM address)
- **Outputs/Return:** Framebuffer updated at `edi`
- **Side effects:** Framebuffer write; clobbers general registers
- **Calls:** (none visible)
- **Notes:** Tight inner loop; uses fixed scanline stride (`fixchain1a` patches stride dynamically)

### vlineasm4_
- **Signature:** `void vlineasm4_(ecx=count, others via _vplce, _vince, _bufplce, _palookupoffse[])`
- **Purpose:** Draw 4 parallel vertical lines (columns) with simultaneous texture/palette lookup.
- **Inputs:** `ecx` (line count), `_ylookup[ecx*4]` (scanline address), arrays `_vplce[0..3]`, `_vince[0..3]`, `_bufplce[0..3]`, `_palookupoffse[0..3]`
- **Outputs/Return:** Writes 4 pixels per iteration to framebuffer
- **Side effects:** Heavy register usage; modifies `_vplce[0..3]` for next batch; I/O to framebuffer
- **Calls:** (indirect via patched references)
- **Notes:** Highly unrolled; exploits instruction-level parallelism; stores finalized `_vplce` values for continuation

### mvlineasm4_
- **Signature:** `void mvlineasm4_(ecx=count, ebx=y_or_x_param, others via global arrays)`
- **Purpose:** Masked vertical line (skip pixels where texture value is 255).
- **Inputs:** `ecx` (count), `ebx` (mask/control bits), global arrays `_vplce`, `_vince`, `_bufplce`, `_palookupoffse`
- **Outputs/Return:** Framebuffer writes (conditional)
- **Side effects:** Builds 4-pixel mask in `dl` and jumps to case table (16 branches)
- **Calls:** `mvcase0` through `mvcase15` (case table)
- **Notes:** Uses bitmask to select which of 4 pixels to write; highly branch-optimized

### prohlineasm4_
- **Signature:** `void prohlineasm4_(ecx, edx, esi, edi=vidpos, _asm1, _asm2)`
- **Purpose:** Pentium-optimized horizontal line (alternative to `hlineasm4_`)
- **Inputs:** `ecx` (y-increment), `edx` (x-fraction), `esi` (x-integer), `edi` (video position), `_asm1`/`_asm2` (increments)
- **Outputs/Return:** Framebuffer write
- **Side effects:** Modifies video position and counters
- **Calls:** (none)
- **Notes:** Branches dynamically; patched into `hlineasm4_` on Pentium II/Pro via CPU detection

### provlineasm4_
- **Signature:** `void provlineasm4_(similar to vlineasm4_ but Pentium-optimized)`
- **Purpose:** Pentium-optimized vertical 4-column rendering.
- **Inputs:** Global arrays `_vplce`, `_vince`, `_bufplce`, `_palookupoffse`, `_ylookup[ecx*4]`
- **Outputs/Return:** Framebuffer writes; updates `_vplce[0..3]`
- **Side effects:** Uses `movzx` for zero-extending palette lookups (Pentium-friendly)
- **Calls:** (none)
- **Notes:** Replaces `vlineasm4_` on Pentium II/Pro; improves instruction decode

### spritevline_
- **Signature:** `void spritevline_(eax, ebx=x, ecx=count, edx=y, esi=yplc, edi=p)`
- **Purpose:** Draw vertical sprite strip (single column) with texture sampling.
- **Inputs:** `ebx` (x position), `ecx` (pixel count), `edx` (y increment), `esi` (texture Y coordinate), `edi` (video address)
- **Outputs/Return:** Framebuffer updated
- **Side effects:** Self-modifying code patches (`smach1`–`smach5`)
- **Calls:** (none)
- **Notes:** Supports X/Y increments for scaled sprites; separate masked (`mspritevline_`) and translucent (`tspritevline_`) variants

### slopevlin_
- **Signature:** `void slopevlin_(eax=xbits, ah=ybits, al=xbits_neg, ebx=start_x, ecx=start_y, edx=ptr, esi=tptr, edi=pinc)`
- **Purpose:** Slope-based texture mapping for walls/floors (perspective-correct).
- **Inputs:** `eax`, `ah`, `al` (bit shifts), `ebx`/`ecx` (start coords), `edx`/`esi` (buffer pointers), `edi` (pitch), FPU stack value
- **Outputs/Return:** Framebuffer writes; updates FPU/global state
- **Side effects:** FPU operations; modifies `_globalx3`, `_globaly3`, `_asm1`, `_asm2`, `_fpuasm`; manipulates ESP
- **Calls:** (implicit FPU instructions)
- **Notes:** Uses reciprocal table (`_reciptable`) for perspective correction; heavily commented register layout

### mvlineasm1_, tvlineasm1_
- **Signature:** Similar to `vlineasm1_` but with masking/translucency
- **Purpose:** Masked and translucent variants of single-column vertical drawing
- **Inputs:** Same as `vlineasm1_` plus transparency/mask lookups
- **Outputs/Return:** Conditional/blended framebuffer writes
- **Side effects:** Optional writes based on transparency
- **Calls:** (none)
- **Notes:** `tvlineasm1_` uses `transrev0`–`transrev17` self-modifying patches for translucency table swapping

### mmxoverlay_
- **Signature:** `void mmxoverlay_(void)`
- **Purpose:** CPU detection and runtime code patching to select optimized code paths.
- **Inputs:** None (reads CPUID)
- **Outputs/Return:** Patches function entry points in-place
- **Side effects:** Modifies instructions at `sethlinesizes_`, `hlineasm4_`, `vlineasm4_`, etc. (JMP redirects)
- **Calls:** Indirect (CPUID instruction via `dw 0a20fh`)
- **Notes:** Detects Pentium II (with MMX), Pentium Pro, or generic Pentium; replaces standard routines with Pentium-specific variants if beneficial

## Control Flow Notes

**Initialization Phase:**
- `mmxoverlay_` runs at startup to patch function entry points based on CPU capabilities
- `setuphlineasm_`, `setupvlineasm_`, `setupmvlineasm_`, `setuptvlineasm_`, `setupspritevline_` patch code before drawing batches

**Rendering Frame Loop:**
- Horizontal lines drawn via `hlineasm4_` (standard) or `prohlineasm4_` (Pentium)
- Vertical lines drawn via `vlineasm4_` (unrolled 4-column) or `vlineasm1_` (single)
- Masked variants (`mvlineasm4_`) used when texture has transparency (value 255)
- Translucent variants (`tvlineasm4_`) used for blended rendering
- Sprite rendering (`spritevline_`) for sprite objects

**Slope Rendering:**
- `slopevlin_` used for perspective-correct texture mapping of sloped surfaces (walls, floors)
- Alternates with simpler linear `hlineasm4_` for flat surfaces

## External Dependencies

- **Imported globals:** `_asm1`, `_asm2`, `_asm3`, `_asm4`, `_reciptable`, `_fpuasm`, `_globalx3`, `_globaly3`, `_ylookup`, `_vplce`, `_vince`, `_palookupoffse`, `_bufplce`, `_ebpbak`, `_espbak`, `_pow2char`, `_pow2long`
- **Self-modifying code patterns:** Patch offsets at fixed byte positions (e.g., `+1`, `+2`, `+3`) in instructions
- **Calling convention:** x86 register calling (parameters in `eax`, `ebx`, `ecx`, `edx`, `esi`, `edi`); some values via globals
- **Framebuffer model:** Linear 32-bit scanline-stride addressable; stride injected via `_asm1` or `fixchain*` patches
