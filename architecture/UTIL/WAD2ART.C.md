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

## Key Types / Data Structures
None.

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `wadata[MAXWADS]` | `char[8]` | static | WAD entry names (8-byte identifiers) |
| `wadplc` | `long[]` | static | File offset of each WAD entry |
| `wadlen` | `long[]` | static | Byte size of each WAD entry |
| `numwads` | `long` | static | Total number of WAD entries loaded |
| `tilesizx`, `tilesizy` | `short[]` | static | Width and height of each output tile |
| `picanm` | `long[]` | static | Animation data for each tile |
| `pal` | `char[768]` | static | 256-color VGA palette (3 bytes per color) |
| `palookup` | `char[8192]` | static | Doom colormaps (32 shades × 256 colors) |
| `screen`, `tempbuf` | `char[]` | static | Graphics buffers (65536 and 131072 bytes) |
| `xoffses`, `ylookup` | `long[]` | static | Sprite column offsets and scanline lookup table |
| `fil1`, `fil2` | `long` | static | File descriptors for input WAD and output ART |
| `frameplace` | `long` | static | Base address of screen buffer in DOS video memory |

## Key Functions / Methods

### main
- **Signature:** `main(short argc, char **argv)`
- **Purpose:** Entry point; orchestrates WAD-to-ART conversion pipeline
- **Inputs:** Command-line argument count and WAD file path
- **Outputs/Return:** Exit code (implicit; calls `exit()`)
- **Side effects:** Opens/closes files, sets video mode 0x13 (320×200 VGA), writes three output files
- **Calls:** `loadwadheader()`, `savenames()`, `convpalette()`, `showart()` (4 times), `setvmode()`
- **Notes:** Sets up `ylookup[]` scanline table; writes ART header after all tiles; restores video mode 0x3 (text) on completion

### loadwadheader
- **Signature:** `loadwadheader()`
- **Purpose:** Parse WAD directory; populate `wadata[]`, `wadplc[]`, `wadlen[]`, `numwads`
- **Inputs:** None (reads from `fil1` at position 0)
- **Outputs/Return:** None (modifies static arrays)
- **Side effects:** File seek and read operations on `fil1`
- **Calls:** `read()`, `lseek()`
- **Notes:** Manually unpacks little-endian multi-byte integers from binary data; standard Doom WAD format (4-byte count + offset + 16-byte directory entries)

### convpalette
- **Signature:** `convpalette()`
- **Purpose:** Extract PLAYPAL (palette) and COLORMAP from WAD; convert to Build format; save `palette.dat`
- **Inputs:** None (searches `wadata[]` for "PLAYPAL" and "COLORMAP")
- **Outputs/Return:** None (writes `palette.dat`)
- **Side effects:** Reads from `fil1`, writes palette to VGA port 0x3c8/0x3c9, creates `palette.dat`
- **Calls:** `strnicmp()`, `lseek()`, `read()`, `outp()`, `open()`, `write()`, `close()`
- **Notes:** Right-shifts palette values by 2 bits for VGA hardware; palookup is written with 32-shade count header

### saveart
- **Signature:** `saveart(short tilenum, short xlen, short ylen)`
- **Purpose:** Store a single tile's scanline data to ART file and record its dimensions
- **Inputs:** Tile index, width (xlen), height (ylen)
- **Outputs/Return:** None (writes to `fil2`; updates `tilesizx[]`, `tilesizy[]`)
- **Side effects:** Writes tile bitmap data to ART file; exit on disk full
- **Calls:** `copybuf()`, `write()`, `setvmode()`, `exit()`
- **Notes:** Copies video RAM (0xa0000) to `screen[]` buffer, then transposes sprite columns into scanline order for ART format

### savenames
- **Signature:** `savenames()`
- **Purpose:** Generate `names.h` with preprocessor defines for sprite names
- **Inputs:** None (iterates `wadata[]` and `numwads`)
- **Outputs/Return:** None (writes `names.h`)
- **Side effects:** Creates `names.h` in current directory
- **Calls:** `open()`, `strcpy()`, `write()`, `close()`
- **Notes:** Outputs `#define SPRITENAME <index>` lines; skips entries with null name; manually formats decimal index as ASCII

### showart
- **Signature:** `showart(char *part)`
- **Purpose:** Locate and process a sprite section (L_START, S_START, P_START) or flat section (F_START) from WAD
- **Inputs:** Section marker string ("L_START", "S_START", "P_START", "F_START")
- **Outputs/Return:** None (writes tile data via `saveart()`)
- **Side effects:** File seeks on `fil1`; decompresses and draws sprites to `screen[]` buffer; calls `saveart()` for each tile
- **Calls:** `strnicmp()`, `lseek()`, `read()`, `clearbuf()`, `saveart()`, `setvmode()`, `printf()`, `exit()`
- **Notes:** Two code paths: sprite/texture (variable-height) vs. flat (64×64 fixed). Sprite path handles Doom's column format (column offsets → posts of pixels); flat path is trivial 64×64 copy. Skip invalid sprites (dims ≤0 or >320×200)

## Control Flow Notes
Sequential command-line utility with implicit initialization and shutdown:
1. **Init:** Parse args, open files, set video mode
2. **Main:** Load WAD header → extract palette → process four sprite/flat sections (L_, S_, P_, F_START) → write ART header and close files
3. **Shutdown:** Restore text video mode (0x3), print success message

Not event-driven; single-pass linear execution.

## External Dependencies
- **Includes:** `<dos.h>`, `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<string.h>`
- **DOS/x86 specifics:** `#pragma aux` for inline assembly (setvmode, drawpixel, clearbuf, copybuf); `int 0x10` BIOS video calls; video RAM at `0xa0000`; I/O port instructions (`outp`)
- **String functions:** `strnicmp()`, `strcpy()`, `strcat()`, `strchr()` (defined elsewhere)
- **I/O functions:** `open()`, `close()`, `read()`, `write()`, `lseek()`, `tell()` (POSIX/DOS standard library)
- **Video:** Direct access to VGA color registers (`outp(0x3c8/0x3c9)`) and video RAM
