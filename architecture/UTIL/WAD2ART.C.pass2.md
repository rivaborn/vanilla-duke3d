# UTIL/WAD2ART.C — Enhanced Analysis

## Architectural Role

WAD2ART is a bridge converter that translates Doom's WAD asset format into the Build engine's ART tile and palette subsystems. It operates as a standalone command-line utility (analogous to WAD2MAP.C, CONVMAP*.C, TRANSPAL.C) that pre-processes external game data into Build-compatible formats. The outputs—`tiles000.art`, `palette.dat`, `names.h`—feed directly into the rendering pipeline (ENGINE.C loads tiles via CACHE1D.C), the editor (BUILD.H includes names.h), and the artwork editor (EDITART.C manipulates ART files).

## Key Cross-References

### Incoming (who depends on this file)
- **No engine code depends on WAD2ART's functions** (utility is standalone)
- **But the utility's outputs are consumed by:**
  - ENGINE.C: calls `loadtile()` → CACHE1D.C → reads `tiles000.art` 
  - BUILD.H: includes `names.h` → sprite type constants for editor and game
  - CACHE1D.C (`initcache`, `kopen4load`): loads ART file metadata and tile bitmaps
  - EDITART.C (`loadpics`, `savepics`): reads/writes ART file headers and tile data
  - VES2.H: palette DAC functions consume `palette.dat` colormaps

### Outgoing (what this file depends on)
- **DOS/POSIX file I/O:** `open()`, `close()`, `read()`, `write()`, `lseek()`, `tell()`
- **String utilities:** `strnicmp()`, `strcpy()`, `strcat()`, `strchr()`
- **Assembly intrinsics (PRAGMAS.H):** `clearbuf()`, `copybuf()` (optimized buffer ops)
- **VGA hardware:** `setvmode()` (INT 0x10 video mode switch), `outp()` (palette DAC port 0x3c8/0x3c9)
- **Standard library:** `exit()`, `printf()`
- **No subsystem dependencies** (no ENGINE, CACHE1D, or KDMENG linkage)

## Design Patterns & Rationale

**Format Conversion Pipeline:** Three-stage linear flow—parse source, transform, write destination. Typical of 90s asset preprocessing tools with no runtime interaction.

**Graphics Format Impedance Mismatch:** The utility exposes a key engine design tradeoff:
- **Doom (input):** Column-based sprite encoding with offsets and run-length posts (compact storage, complex decompression)
- **Build (output):** Raw scanline-major pixel arrays (simple rendering, cache-friendly, wastes space)

The `showart()` function's two code paths exemplify this: sprite decompression (variable-height, column offsets) vs. flat tiles (64×64 fixed, simple memcpy). Build chose scanline storage to accelerate 3D sprite rasterization.

**Palette Hardware Adaptation:** `convpalette()` right-shifts palette values by 2 bits before writing VGA DAC (0x3c8/0x3c9), adapting Doom's 6-bit-per-channel format to VGA's 6-bit intensity. The COLORMAP extraction (8192 bytes = 32 shades × 256 colors) encodes lighting/distance attenuation precomputed by Doom; Build reuses this for shadow/fade effects.

**Static Buffer Pre-Allocation:** Large globals (`screen[65536]`, `tempbuf[131072]`) preallocated at link time. No dynamic allocation—typical DOS constraint. The `frameplace = FP_OFF(screen)` assignment caches the buffer address for use by assembly macros.

## Data Flow Through This File

1. **Parse WAD header** → extract entry count, directory offset
2. **Load directory** → populate `wadata[]` (names), `wadplc[]` (offsets), `wadlen[]` (sizes), `numwads` (count)
3. **Extract PLAYPAL** → 768-byte RGB palette → right-shift by 2 → send to VGA DAC port
4. **Extract COLORMAP** → 8192-byte shade table → write to `palette.dat` with shade count header
5. **Iterate sprite sections** (L_START, S_START, P_START, F_START):
   - For each Doom sprite: read from `fil1` → decompress column format into `tempbuf[]` → transpose to scanline format in `screen[]` buffer → call `saveart()` → write to `fil2`
   - For each flat: read 4096-byte (64×64) buffer → transpose to scanline → call `saveart()`
6. **Write ART file header** → version, tile count, tile dimensions, animation data at file offset 0
7. **Generate names.h** → emit `#define SPRITENAME <numeric_id>` for each sprite

## Learning Notes

**Idiomatic to 90s game engines:**
- Direct VGA video memory manipulation (0xa0000)
- Hard-coded video mode (0x13 = 320×200 8-bit indexed color)
- Inline x86 assembly for performance-critical sections (PRAGMAS.H macros)
- No abstraction layers; tools tightly coupled to target hardware

**Graphics pipeline idioms:**
- Palette = 256 RGB triplets (3 bytes/color)
- Colormaps = precomputed shade tables (light simulation at load time, not runtime)
- Sprite storage = metadata header + scanline-major pixel data (simple pointer arithmetic during rendering)

**Modern engines would instead:**
- Use versioned binary asset formats with validation
- Lazy-load and stream assets asynchronously
- Abstract texture/sprite format from storage (DXT, BC, ASTC compression)
- Precompute GPU-ready data (mipmaps, bind groups) at conversion time
- Use structured serialization (protobuf, msgpack) instead of hand-rolled binary parsing

**Doom→Build bridging insights:**
- Shows how engines absorb external asset formats during development
- The column-to-scanline transposition in `showart()` is computationally cheap but semantically important for rendering performance
- Palette color reduction (VGA 6-bit) and shade table extraction illustrate per-hardware asset adaptation

## Potential Issues

1. **Bounds & Error Handling:**
   - `while (strnicmp(wadata[z],"PLAYPAL",7) != 0) i++` can infinite-loop if "PLAYPAL" not in `wadata[]`
   - No validation of WAD magic bytes (could process corrupted/non-WAD files silently)
   - Fixed array `MAXWADS=4096` could overflow if WAD has more entries

2. **Graphics Assumptions:**
   - Hard-coded 320×200 screen; `ylookup[]` and `xoffses[]` assume this resolution
   - Column decompression in `showart()` trusts Doom's format (yoff=255 sentinel) without bounds checks
   - No validation that tile dims fit in ART header fields (`short tilesizx[]`, `tilesizy[]`)

3. **I/O Robustness:**
   - Disk-full error check only in `saveart()`, not for header writes
   - No partial-read recovery; assumes all bytes returned by `read()`
   - File descriptor `fil1` never validated (checked only after `open()` succeeds)

4. **Format Coupling:**
   - Tightly dependent on Doom IWAD structure (PLAYPAL/COLORMAP marker names, column format)
   - Would require code changes for PWAD support or other WAD variants
   - Assumes 768-byte palette and 8192-byte colormap (no version-agnostic parsing)
