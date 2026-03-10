# UTIL/BACKMAP6.C

## File Purpose
A map format converter utility for Ken Silverman's Build engine. Converts map files from version 7 to version 6 by loading old-format binary map data, transforming structures, and saving in the new format. Supports batch conversion of multiple files.

## Core Responsibilities
- Parse command-line arguments and locate matching map files
- Load binary map files in the old (version 7) format from disk
- Transform sector, wall, and sprite data structures from old to new format
- Apply format-specific conversions (e.g., bit-shifting height values)
- Write converted maps in new (version 6) binary format
- Maintain and sort a list of files to process

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `newsectortype` | struct | Version 6 sector format (ceiling/floor properties, 40 bytes) |
| `newwalltype` | struct | Version 6 wall format (position, texture, repeat values) |
| `newspritetype` | struct | Version 6 sprite format (position, angle, velocity, state) |
| `sectortype` | struct | Version 7 sector format (legacy, 40 bytes) |
| `walltype` | struct | Version 7 wall format (32 bytes) |
| `spritetype` | struct | Version 7 sprite format (44 bytes) |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `menuname` | `char[MAXMENUFILES][32]` | static | Filenames matched by wildcard pattern |
| `menunamecnt` | `long` | static | Count of files to process |
| `sector`, `wall`, `sprite` | Arrays (v7 format) | static | Loaded old-format map data |
| `newsector`, `newwall`, `newsprite` | Arrays (v6 format) | static | Converted map data pending write |
| `posx`, `posy`, `posz` | `long` | static | Player start position |
| `mapversion` | `long` | static | Version tag from map file |
| `ang`, `cursectnum` | `short` | static | Player start angle and sector |
| `numsectors`, `numwalls`, `numsprites` | `short` | static | Entity counts for current map |

## Key Functions / Methods

### main
- **Signature:** `main(int argc, char **argv)`
- **Purpose:** Entry point; validates arguments, scans for matching files, iterates conversion.
- **Inputs:** Command-line arguments (expects exactly 2: program name and file pattern)
- **Outputs/Return:** Exit code (0 on success)
- **Side effects:** Calls `getfilenames()`, `sortfilenames()`, `convmap()` for each file
- **Calls:** `getfilenames()`, `sortfilenames()`, `convmap()`, `exit()`, `printf()`
- **Notes:** Requires exactly one argument (file pattern); exits early if no files match.

### convmap
- **Signature:** `convmap(char *filename)`
- **Purpose:** Orchestrates conversion of a single map file.
- **Inputs:** Filename (string); auto-appends ".map" if no extension
- **Outputs/Return:** None (void); prints status to stdout
- **Side effects:** Loads map into global arrays, transforms data in-place, writes to disk
- **Calls:** `strchr()`, `strcat()`, `loadoldboard()`, `savenewboard()`, `printf()`
- **Notes:** Handles three error cases: file not found, wrong version, or unconvertible format. Transforms sector ceiling/floor height indices by right-shifting 5 bits.

### loadoldboard
- **Signature:** `loadoldboard(char *filename)`
- **Purpose:** Reads a version-7 binary map file into global arrays.
- **Inputs:** Filename string
- **Outputs/Return:** `0` on success, `-1` if file not found, `-2` if wrong version
- **Side effects:** Populates global `mapversion`, player state (`posx`, `posy`, `posz`, `ang`, `cursectnum`), and entity arrays
- **Calls:** `open()`, `read()`, `close()`
- **Notes:** Validates `mapversion == NEWMAPVERSION+1` (i.e., version 7). Uses `O_BINARY` flag for DOS-style binary I/O.

### savenewboard
- **Signature:** `savenewboard(char *filename)`
- **Purpose:** Writes converted (version 6) map data to disk in binary format.
- **Inputs:** Filename string
- **Outputs/Return:** `0` on success, `-1` on file I/O error
- **Side effects:** Overwrites or creates file; writes version tag, player state, and entity arrays in v6 format
- **Calls:** `open()`, `write()`, `close()`
- **Notes:** Uses `O_TRUNC` to overwrite; writes same player state as input but with converted entity structures.

### getfilenames
- **Signature:** `getfilenames(char *kind)`
- **Purpose:** Scans filesystem for files/directories matching a pattern using DOS APIs.
- **Inputs:** Pattern string (e.g., `"*.map"`); special case: `"SUBD"` for subdirectories
- **Outputs/Return:** `-1` on error (no files found), `0` otherwise
- **Side effects:** Populates `menuname[]` array and increments `menunamecnt`
- **Calls:** `strcmp()`, `strcpy()`, `_dos_findfirst()`, `_dos_findnext()`, `strcpy()`
- **Notes:** Filters out `.` and `..` entries. Stores file type (normal or subdir) in `menuname[i][16]`.

### sortfilenames
- **Signature:** `sortfilenames()`
- **Purpose:** Sorts the accumulated filename list alphabetically.
- **Inputs:** None (operates on global `menuname[]`)
- **Outputs/Return:** None (void; modifies global state)
- **Side effects:** Reorders `menuname[]` in-place using bubble sort
- **Calls:** `memcpy()`
- **Notes:** Simple bubble-sort algorithm; compares character-by-character until mismatch.

## Control Flow Notes
This utility runs as a standalone batch converter, not integrated into a runtime game loop. Flow: CLI → file enumeration → sort → loop-convert-each-file → exit. Each map conversion is independent; no persistent render or update cycles.

## External Dependencies
- **Standard includes:** `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>`
- **DOS/legacy APIs:** `_dos_findfirst()`, `_dos_findnext()`, `struct find_t`
- **I/O & string:** `open()`, `read()`, `write()`, `close()`, `strcpy()`, `strcmp()`, `memcpy()`, `strcat()`, `strchr()`
- **External symbols:** All functions defined in this file; data structures are internal.
