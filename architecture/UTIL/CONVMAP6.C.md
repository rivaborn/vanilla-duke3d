# UTIL/CONVMAP6.C

## File Purpose
Map format converter utility that upgrades Build engine map files from version 5 to version 6. It reads old-format map structures, transforms them according to schema changes, and writes the new format back to disk. Includes file discovery and sorting utilities for batch conversion.

## Core Responsibilities
- Load map files in version 5 format and validate version numbers
- Transform sector, wall, and sprite structures from v5 to v6 schema
- Derive missing v6 fields from v5 data (e.g., sprite palette from sector, clipdist defaults)
- Write converted maps in version 6 format back to disk
- Discover and sort map files matching command-line filespec
- Handle error reporting for missing files or already-converted maps

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| `sectortype` | struct | Version 5 sector layout (includes separate `nextsector1`/`nextwall1` fields) |
| `walltype` | struct | Version 5 wall layout (includes redundant `nextsector2`/`nextwall2` fields) |
| `spritetype` | struct | Version 5 sprite layout (no `pal`, `clipdist`, `xoffset`, `yoffset`) |
| `newsectortype` | struct | Version 6 sector layout (identical to v5 in this conversion) |
| `newwalltype` | struct | Version 6 wall layout (consolidated to single `nextsector`/`nextwall`, added `pal`) |
| `newspritetype` | struct | Version 6 sprite layout (adds `pal`, `clipdist`, `xoffset`, `yoffset`; `cstat` promoted to short) |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `sector` | `sectortype[MAXSECTORS]` | static | Version 5 sector data buffer |
| `wall` | `walltype[MAXWALLS]` | static | Version 5 wall data buffer |
| `sprite` | `spritetype[MAXSPRITES]` | static | Version 5 sprite data buffer |
| `newsector` | `newsectortype[MAXSECTORS]` | static | Version 6 sector data buffer |
| `newwall` | `newwalltype[MAXWALLS]` | static | Version 6 wall data buffer |
| `newsprite` | `newspritetype[MAXSPRITES]` | static | Version 6 sprite data buffer |
| `posx, posy, posz` | `long` | static | Player spawn position |
| `mapversion` | `long` | static | Map version number |
| `ang, cursectnum` | `short` | static | Player spawn angle and starting sector |
| `numsectors, numwalls, numsprites` | `short` | static | Entity counts |
| `menuname` | `char[MAXMENUFILES][32]` | static | Discovered filenames buffer |
| `menunamecnt` | `long` | static | Count of discovered files |

## Key Functions / Methods

### main
- Signature: `main(int argc, char **argv)`
- Purpose: Entry point; validates command-line arguments, discovers files, and dispatches conversion.
- Inputs: `argc`, `argv` (expects `argv[1]` to be a file pattern like `"*.map"`)
- Outputs/Return: None (exits process)
- Side effects: Calls `getfilenames()`, `sortfilenames()`, `convmap()` for each file; prints status
- Calls: `getfilenames()`, `sortfilenames()`, `convmap()`, `printf()`, `exit()`

### convmap
- Signature: `convmap(char *filename)`
- Purpose: Core conversion routine; loads v5 map, transforms all structures field-by-field, and saves v6 format.
- Inputs: `filename` (map file path; `.map` extension added if missing)
- Outputs/Return: None (void)
- Side effects: Modifies global `newsector`, `newwall`, `newsprite` arrays; writes file to disk; prints results
- Calls: `strchr()`, `strcat()`, `loadoldboard()`, `sectorofwall()`, `savenewboard()`, `printf()`
- Notes: Derives wall palette from containing sector's floor palette; sprite palette from sector ceiling/floor based on `ceilingstat` bit 0; sets `clipdist=32` and offsets to 0 for all sprites

### loadoldboard
- Signature: `loadoldboard(char *filename)`
- Purpose: Reads version 5 map file and populates global sector/wall/sprite arrays.
- Inputs: `filename`
- Outputs/Return: 0 on success, -1 if file not found, -2 if wrong version
- Side effects: Populates global `sector`, `wall`, `sprite` arrays and scalar state (`posx`, `posy`, `mapversion`, etc.)
- Calls: `open()`, `read()`, `close()`
- Notes: Opens in read-only binary mode; validates `mapversion == NEWMAPVERSION-1` (expects 5)

### savenewboard
- Signature: `savenewboard(char *filename)`
- Purpose: Writes version 6 map data to disk in binary format.
- Inputs: `filename`
- Outputs/Return: 0 on success, -1 if file open fails
- Side effects: Truncates/creates file; writes global state and all `newsector`/`newwall`/`newsprite` arrays
- Calls: `open()`, `write()`, `close()`
- Notes: Opens in binary write mode with O_TRUNC|O_CREAT

### sectorofwall
- Signature: `sectorofwall(short theline)`
- Purpose: Utility to find which sector owns a given wall index.
- Inputs: `theline` (wall index)
- Outputs/Return: Sector index, or -1 if not found
- Side effects: None
- Calls: None (inline loop over `numsectors`)
- Notes: Linear search; unused if wall already references containing sector

### getfilenames
- Signature: `getfilenames(char *kind)`
- Purpose: DOS file discovery; populates `menuname` array with files matching pattern or subdirectories.
- Inputs: `kind` (pattern like `"*.map"` or special string `"SUBD"`)
- Outputs/Return: -1 if no files found, 0 otherwise
- Side effects: Populates `menuname` and `menunamecnt`; stores type flag in `menuname[i][16]`
- Calls: `_dos_findfirst()`, `_dos_findnext()`, `strcmp()`, `strcpy()`
- Notes: DOS-specific; filters out `.` directory entry

### sortfilenames
- Signature: `sortfilenames()`
- Purpose: Sorts accumulated filenames lexicographically.
- Inputs: None (uses global `menuname`, `menunamecnt`)
- Outputs/Return: None (void)
- Side effects: Reorders `menuname` array in-place
- Calls: `memcpy()`
- Notes: Bubble sort; simple string comparison

## Control Flow Notes
**Initialization / Batch Processing**: `main()` → file discovery → sorting → loop.
**Per-File Conversion**: `convmap()` → `loadoldboard()` → field-by-field copy with transformations → `savenewboard()` → result reporting.
No explicit render or update loops; this is a command-line batch utility.

## External Dependencies
- **DOS/System includes**: `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>` (file I/O, DOS file search)
- **Standard C**: `<stdio.h>` (implicit; `printf()`), string functions (`strchr`, `strcat`, `strcmp`, `strcpy`, `memcpy`)
- **External symbols used but not defined**: `open()`, `read()`, `write()`, `close()` (POSIX file I/O); `_dos_findfirst()`, `_dos_findnext()` (DOS); `printf()`, `exit()` (C stdlib)
