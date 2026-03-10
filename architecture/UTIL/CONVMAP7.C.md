# UTIL/CONVMAP7.C

## File Purpose
Utility to convert Build Engine map files from version 6 to version 7. Discovers all matching map files, loads old format structures, applies format-specific transformations (primarily height scaling), and writes the converted data in the new binary format.

## Core Responsibilities
- Parse command-line file specifications and discover matching `.map` files
- Sort discovered filenames alphabetically
- Load version 6 map structures (sectors, walls, sprites) from binary files
- Convert old struct layouts to new struct layouts with field reordering and alignment padding
- Apply height value transformations (left-shift by 5, clamp to signed 16-bit range)
- Write converted data to binary files in version 7 format
- Report success/failure and version compatibility checks

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `sectortype` | struct | Version 6 format: sector with ceiling/floor properties; 56+ bytes |
| `walltype` | struct | Version 6 format: wall with texture and navigation data; ~26 bytes |
| `spritetype` | struct | Version 6 format: sprite with position, velocity, and tags; ~34 bytes |
| `newsectortype` | struct | Version 7 format: sector optimized; 40 bytes (reordered fields, padding) |
| `newwalltype` | struct | Version 7 format: wall optimized; 32 bytes (reordered fields) |
| `newspritetype` | struct | Version 7 format: sprite optimized; 44 bytes (reordered, padding) |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `sector[]` | `sectortype[MAXSECTORS]` | static | Loaded old format sectors (1024 max) |
| `wall[]` | `walltype[MAXWALLS]` | static | Loaded old format walls (8192 max) |
| `sprite[]` | `spritetype[MAXSPRITES]` | static | Loaded old format sprites (4096 max) |
| `newsector[]` | `newsectortype[MAXSECTORS]` | static | Converted new format sectors |
| `newwall[]` | `newwalltype[MAXWALLS]` | static | Converted new format walls |
| `newsprite[]` | `newspritetype[MAXSPRITES]` | static | Converted new format sprites |
| `posx, posy, posz` | `long` | static | Player spawn position |
| `ang, cursectnum` | `short` | static | Player spawn angle and sector |
| `numsectors, numwalls, numsprites` | `short` | static | Counts of loaded entities |
| `mapversion` | `long` | static | Map version (set to NEWMAPVERSION=7 after conversion) |
| `menuname[]` | `char[MAXMENUFILES][32]` | static | Discovered filenames (1024 max) |
| `menunamecnt` | `long` | static | Count of discovered files |

## Key Functions / Methods

### main
- **Signature:** `main(int argc, char **argv)`
- **Purpose:** Entry point; validate arguments, discover and sort files, invoke conversion on each
- **Inputs:** `argc`, `argv` (expects exactly 2: program name + filespec)
- **Outputs/Return:** Exit status (0 on completion)
- **Side effects:** Calls `getfilenames()`, `sortfilenames()`, `convmap()` for each file; prints usage/error messages
- **Calls:** `getfilenames()`, `sortfilenames()`, `convmap()`, `printf()`, `exit()`
- **Notes:** Exits early if no files found or argc != 2

### convmap
- **Signature:** `convmap(char *filename)`
- **Purpose:** Load old map, convert all structures field-by-field, save as new format
- **Inputs:** Filename (may lack `.map` extension)
- **Outputs/Return:** None (void); prints success/error message
- **Side effects:** Populates `newsector[]`, `newwall[]`, `newsprite[]` arrays; modifies `mapversion`; performs file I/O via `loadoldboard()` and `savenewboard()`
- **Calls:** `strchr()`, `strcat()`, `loadoldboard()`, `savenewboard()`, `max()`, `min()`, `printf()`
- **Notes:** Height values are scaled: `((long)old_heinum) << 5` clamped to `[-32768, 32767]`; height scaling only applied if stat bit 2 is set, else height = 0

### loadoldboard
- **Signature:** `loadoldboard(char *filename)`
- **Purpose:** Open and deserialize a version 6 map file
- **Inputs:** Filename
- **Outputs/Return:** 0 on success, -1 if file not found, -2 if wrong version or unreadable
- **Side effects:** Populates global `posx, posy, posz, ang, cursectnum, mapversion, numsectors, numwalls, numsprites, sector[], wall[], sprite[]`; opens/closes file
- **Calls:** `open()`, `read()`, `close()`
- **Notes:** Reads version check first; rejects if `mapversion != NEWMAPVERSION-1` (i.e., != 6)

### savenewboard
- **Signature:** `savenewboard(char *filename)`
- **Purpose:** Serialize converted version 7 structures to binary file
- **Inputs:** Filename
- **Outputs/Return:** 0 on success, -1 if file creation fails
- **Side effects:** Creates/truncates file; writes all converted map data; closes file
- **Calls:** `open()`, `write()`, `close()`
- **Notes:** Writes version (7), player state, then sector/wall/sprite counts and data

### getfilenames
- **Signature:** `getfilenames(char *kind)`
- **Purpose:** Discover files matching DOS filespec using `_dos_findfirst/_dos_findnext`
- **Inputs:** Filespec (e.g., `"*.map"`); special case `"SUBD"` searches for subdirectories
- **Outputs/Return:** 0 on completion (or -1 if no match found initially)
- **Side effects:** Populates `menuname[]` and increments `menunamecnt`; stores file type (0=normal, 1=directory) in byte 16 of each name
- **Calls:** `strcmp()`, `strcpy()`, `_dos_findfirst()`, `_dos_findnext()`
- **Notes:** Filters out `.` entries; caps at MAXMENUFILES

### sortfilenames
- **Signature:** `sortfilenames()`
- **Purpose:** Sort discovered filenames alphabetically (bubble sort)
- **Inputs:** None (operates on global `menuname[]` and `menunamecnt`)
- **Outputs/Return:** None
- **Side effects:** Reorders `menuname[]` in place
- **Calls:** `memcpy()`
- **Notes:** Naive O(n²) bubble sort; preserves type byte at offset 16 during swaps

## Control Flow Notes

**Initialization:** `main()` validates args and discovers files.

**Processing Loop:** For each discovered file, `convmap()` is called, which:
1. Calls `loadoldboard()` to read version 6 data
2. Iterates through each sector, wall, sprite, copying and transforming fields
3. Calls `savenewboard()` to write version 7 data

**Exit:** Program terminates after all files processed.

## External Dependencies

- **Headers:** `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>`
- **DOS API:** `_dos_findfirst()`, `_dos_findnext()`, `find_t` struct
- **Libc:** `open()`, `read()`, `write()`, `close()`, `strchr()`, `strcat()`, `strcmp()`, `strcpy()`, `memcpy()`, `printf()`, `exit()`
- **Macros/Functions defined elsewhere:** `max()`, `min()` (presumably from stdlib or custom)
