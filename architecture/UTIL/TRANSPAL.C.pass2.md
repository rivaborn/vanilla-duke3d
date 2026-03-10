# UTIL/TRANSPAL.C — Enhanced Analysis

## Architectural Role

TRANSPAL is a build-time palette lookup table generator that bridges the 3D rendering engine's need for fixed RGB→palette color quantization with the game's 256-color hardware constraints. It generates two critical lookup tables—shade (darkening) and translucency (blending)—that enable the renderer to efficiently perform color space transformations without real-time computation. The tool serves the broader art pipeline by maintaining and validating `palette.dat`, which is shared with other editors (EDITART.C) and utilities.

## Key Cross-References

### Incoming (who depends on this file)
- **No direct callers** (standalone utility, invoked from command line)
- **Indirect consumers:**
  - EDITART.C reads/writes `palette.dat` and generates shade/translucency tables similarly
  - ENGINE.C (rendering) consumes `palookup[]` and `transluc[]` at runtime for palette lookups
  - Other utilities (CONVMAP*, WAD2ART) may reference palette data through CACHE1D

### Outgoing (what this file depends on)
- **File I/O:** Reads/writes `palette.dat` (shared with EDITART, loaded by CACHE1D)
- **Hardware I/O:** Calls pragmas (VGA sequencer 0x3c4, CRTC 0x3d4, DAC 0x3c8/0x3c9) for live preview
- **Color quantization:** Implements spatial grid acceleration similar to patterns in EDITART.C (`selectbox` also calls `getpalookup`, `getpaletteconversion`)
- **Fixed-point math:** Uses `divscale16` from PRAGMAS.H (same as ENGINE.C for perspective correction)

## Design Patterns & Rationale

**1. Spatial Grid Acceleration (getclosestcol)**
- The 8×8×8 grid partitions RGB space to avoid O(256) palette scans per color
- Pre-computes weighted distance metrics (rdist/gdist/bdist) to enable early termination
- Aggressive cache propagation fills neighboring cells when adjacent colors match—a memory/latency tradeoff favoring dense workloads
- **Why:** Color quantization is called ~256×numpalookups times; brute-force would be prohibitive

**2. Preview-Then-Save Workflow**
- Interactive VGA display (mode 0x13) shows shade and translucency tables side-by-side before committing
- SPACE key allows updating only translucency while reverting shade table—supports palette refinement iterations
- **Why:** Palette lookup quality is subjective (banding, color shifts); visual feedback before write prevents bad assets

**3. Dual Table Generation**
- `palookup[]`: Shade table for shadow/lighting effects (darkens toward black)
- `transluc[]`: Blending table for transparency effects (interpolates between two colors)
- Both use `getclosestcol()` to map arbitrary RGB back to palette indices
- **Why:** Renderer needs O(1) lookups; recompiling at runtime is infeasible on 1990s hardware

**4. Parametrizable RGB Weighting**
- CLI allows custom (rscale, gscale, bscale) to tune perceptual distance model
- Default 30:59:11 approximates human eye sensitivity (green > red > blue)
- **Why:** Different palettes optimize differently; allows per-project tuning

## Data Flow Through This File

1. **Load Phase:** `palette.dat` → `palette[]`, `origpalookup[]` (original shade table for fallback)
2. **Quantization Setup:** RGB scales → `initfastcolorlookup()` builds spatial grid
3. **Shade Generation:** 
   - For each shade level (0–numpalookups), for each color index:
     - `getpalookup()` darkens color by `(numpalookups - shade) / numpalookups`
     - `getclosestcol()` finds closest palette index → stores in `palookup[]`
4. **Translucency Generation:**
   - For each color pair (0–255, 0–255):
     - `gettrans()` interpolates by `(color2 - color1) * ratio / 256`
     - `getclosestcol()` quantizes blended RGB → stores in `transluc[]`
5. **Preview:** VGA mode 13h displays both tables; user inspects visual quality
6. **Save:** On ENTER, writes updated `palookup[]` + `transluc[]`; on SPACE, restores `origpalookup[]` and writes new `transluc[]` only

## Learning Notes

**What Developers Learn:**
- Palette lookups enable efficient color space transformations on hardware-constrained systems
- Spatial grid acceleration is a practical alternative to brute-force color search
- Interactive tools reduce iteration time for art asset production (visual feedback before commit)
- Perceptual color distance is not uniform (RGB weighting); tunable parameters matter

**Era-Specific Patterns (vs. Modern Engines):**
- **Modern engines** use dynamic shaders + floating-point; this tool bakes lookups into tables
- **Modern engines** use 24/32-bit color; Build uses 8-bit indexed + global palette
- **Modern engines** support real-time translucency; Build precomputes a 64K lookup table
- **No animation or filtering:** Tables are static; quality depends entirely on palette and quantization algorithm

**Engine Integration:**
- These lookup tables are loaded by CACHE1D during game startup (part of `palette.dat`)
- ENGINE.C uses `palookup[shade][color]` in hot rendering loops (per-pixel texture lookup)
- Audio synthesis (K.ASM) similarly uses lookup tables (`_qualookup`) to avoid runtime computation

## Potential Issues

1. **Spatial Grid Cell Boundary Artifacts:**
   - The grid divides RGB space by 8; colors near cell boundaries may quantize inconsistently
   - Aggressive cache propagation (lines 253–262) fills adjacent cells even when they contain different colors—may mask poor quantization in some regions

2. **256-Color Palette Bottleneck:**
   - Shade table assumes colors can darken monotonically; palettes with non-smooth gradients will show banding
   - Translucency table assumes linearity; perceptually non-linear palettes may produce muddy blends

3. **Cache Propagation Logic Unclear:**
   - Conditions like `ptr[(-2)<<12] == retcol` are cryptic pointer arithmetic; intent is to fill symmetric neighbors
   - If `closestcol` cache is corrupted or partially initialized, subsequent lookups silently return wrong colors

4. **No Validation of Generated Tables:**
   - Tool doesn't warn if shade levels collapse (many shades map to same color)
   - No check for translucency table monotonicity or color distribution quality
