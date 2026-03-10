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

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| palette | char array (768 bytes) | RGB palette data: 256 colors × 3 bytes per color |
| palookup | char array (256×256 bytes) | Shade lookup table: `[shade][color]` → closest palette index |
| transluc | char array (65536 bytes) | Translucency table: `[color1][color2]` → blended palette index |
| closestcol | char array (64×64×64 bytes) | Cache of closest palette colors for RGB tuples |
| colhead, colnext, colhere | arrays | Spatial grid acceleration: linked lists of colors per grid cell |
| rdist, gdist, bdist | long[129] | Precomputed squared distance tables (R, G, B channels) |
| colscan | long[27] | Scan pattern offsets for spatial priority search |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| numpalookups | long | static | Number of shade levels (1–256) |
| transratio | long | static | Translucency blend ratio (0=inverse, 128=50%, 256=opaque) |
| palettefilename | char[13] | static | Filename of palette data file |
| palette | char[768] | static | Current RGB palette |
| palookup, origpalookup | char[] | static | Shade tables (current and original) |
| transluc | char[65536] | static | Translucency lookup table |
| closestcol, colhead, colnext, colhere | arrays | static | Color quantization cache and grid |
| rdist, gdist, bdist, coldist | long/char[] | static | Distance metrics and offsets |

## Key Functions / Methods

### main
- Signature: `int main(short int argc, char **argv)`
- Purpose: Entry point; orchestrates palette loading, table generation, preview display, and optional save
- Inputs: `argc`, `argv` — command line: `transpal <numshades> <transratio> [r g b]`
- Outputs/Return: Program exit code
- Side effects: 
  - Reads `palette.dat` file
  - Sets VGA mode 0x13 (320×200, 256-color)
  - Writes directly to video memory at 0xa0000
  - Fills `palookup` and `transluc` global arrays
  - Optionally overwrites `palette.dat`
- Calls: `open`, `read`, `close`, `write`, `setvmode`, `koutpw`, `koutp`, `clearbuf`, `initfastcolorlookup`, `getpalookup`, `gettrans`, `drawpixel`, `getch`
- Notes: Uses VGA palette (0x3c8/0x3c9), sequencer (0x3c4), and CRTC (0x3d4) registers; SPACE restores original shade table while keeping new translucency table

### getpalookup
- Signature: `char getpalookup(char dashade, char dacol)`
- Purpose: Compute a darkened shade of a palette color
- Inputs: `dashade` (shade level 0–255), `dacol` (palette color index 0–255)
- Outputs/Return: Closest palette color index
- Side effects: None
- Calls: `divscale16`, `getclosestcol`
- Notes: Linear interpolation toward black; darkens by `(numpalookups - dashade) / numpalookups`

### gettrans
- Signature: `char gettrans(char dat1, char dat2, long datransratio)`
- Purpose: Blend two palette colors
- Inputs: `dat1`, `dat2` (color indices), `datransratio` (blend factor 0–256)
- Outputs/Return: Closest palette color for blended result
- Side effects: None
- Calls: `getclosestcol`
- Notes: Interpolates as `color1 + (color2 - color1) * ratio / 256`

### initfastcolorlookup
- Signature: `void initfastcolorlookup(long rscale, long gscale, long bscale)`
- Purpose: Build spatial grid acceleration structure for fast RGB-to-palette lookup
- Inputs: `rscale`, `gscale`, `bscale` (channel weight factors for perceptual distance)
- Outputs/Return: None
- Side effects: Fills `colhead`, `colnext`, `colhere`, `rdist`, `gdist`, `bdist`, `colscan`
- Calls: `clearbufbyte`
- Notes: Uses 8×8×8 spatial grid; precomputes weighted distance tables; initializes search scan order (27 neighbors, center last)

### getclosestcol
- Signature: `char getclosestcol(long r, long g, long b)`
- Purpose: Find closest palette color for arbitrary RGB value with spatial acceleration and caching
- Inputs: `r`, `g`, `b` (0–255 RGB components)
- Outputs/Return: Palette color index
- Side effects: Populates `closestcol` cache; propagates cached results to neighboring cells under certain conditions
- Calls: None
- Notes: 
  - Returns cached result if available (255 indicates uncached)
  - Uses 8×8×8 grid spatial hashing to limit search scope
  - Scans grid cells in priority order (nearest neighbors first)
  - Falls back to full palette brute-force if no nearby candidates found
  - Aggressive cache propagation to neighboring cells when adjacent colors match

## Control Flow Notes

**Initialization Phase:**
- Parse args and validate inputs
- Load palette and original shade table from file
- Enter VGA mode 0x13; initialize hardware palette registers
- Build fast color lookup acceleration structure

**Generation Phase:**
- Generate `palookup` table: nested loop over shades and colors, call `getpalookup`
- Generate `transluc` table: nested loop over color pairs, call `gettrans`
- Display both tables on screen via direct video memory writes

**Preview & Save Phase:**
- Block waiting for user keypress (ENTER/SPACE/ESC)
- ENTER: save both shade and translucency tables
- SPACE: save only translucency table; restore original shade table
- ESC: discard all changes
- Return to text mode and exit

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
