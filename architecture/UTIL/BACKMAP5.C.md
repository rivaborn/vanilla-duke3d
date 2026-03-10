# UTIL/BACKMAP5.C

## File Purpose
A utility program that batch-converts Build engine map files from version 6 to version 5 format. It reads version 6 maps (the "new" format), transforms them to version 5 (the "old" format), and writes them back to disk. Handles structural changes between map versions, including removal of dual-connectivity wall pointers and relocation of sprite/wall palette and offset fields.

## Core Responsibilities
- Parse command-line file patterns and enumerate matching files using DOS file search APIs
- Load and validate version 6 map files from disk, checking version field
- Transform sector, wall, and sprite structures from v6 to v5 layout
- Handle version-specific field migrations (e.g., consolidate `nextsector1`/`nextsector2` to `nextsector`)
- Write converted maps back to disk with v5 version number
- Provide user feedback on conversion success/failure for each file

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `newsectortype` | struct | Version 6 sector: ceiling/floor geometry, texturing, palette per surface |
| `newwalltype` | struct | Version 6 wall: dual next-wall pointers (`nextsector1/2`, `nextwall1/2`); textures and properties |
| `newspritetype` | struct | Version 6 sprite: position, angle, velocity, owner, status; no palette/clipdist |
| `sectortype` | struct | Version 5 sector: consolidated, no per-surface palette |
| `walltype` | struct | Version 5 wall: single next-wall pointer pair; adds `pal` field |
| `spritetype` | struct | Version 5 sprite: adds `pal` and `clipdist`; cstat is `short` instead of `char` |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `sector` | `sectortype[MAXSECTORS]` | static | Version 5 sector data (target format) |
| `wall` | `walltype[MAXWALLS]` | static | Version 5 wall data (target format) |
| `sprite` | `spritetype[MAXSPRITES]` | static | Version 5 sprite data (target format) |
| `newsector` | `newsectortype[MAXSECTORS]` | static | Version 6 sector data (source format) |
| `newwall` | `newwalltype[MAXWALLS]` | static | Version 6 wall data (source format) |
| `newsprite` | `newspritetype[MAXSPRITES]` | static | Version 6 sprite data (source format) |
| `posx`, `posy`, `posz` | `long` | static | Player spawn position |
| `ang`, `cursectnum` | `short` | static | Player spawn angle and starting sector |
| `numsectors`, `numwalls`, `numsprites` | `short` | static | Entity counts |
| `mapversion` | `long` | static | Current map version (v5 after conversion) |
| `menuname` | `char[MAXMENUFILES][32]` | static | List of matched filenames |
| `menunamecnt` | `long` | static | Count of matched files |

## Key Functions / Methods

### main
- **Signature:** `main(int argc, char **argv)`
- **Purpose:** Entry point; validates arguments, enumerates files matching the pattern, sorts them, and initiates conversion.
- **Inputs:** Command-line: program name and one file pattern (e.g., `*.map` or `SUBD`)
- **Outputs/Return:** Exit code (implicit); prints status to stdout
- **Side effects:** Populates `menuname[]` and `menunamecnt`; calls `convmap()` for each file
- **Calls:** `getfilenames()`, `sortfilenames()`, `convmap()`
- **Notes:** Exits if not exactly 2 arguments or no files found.

### convmap
- **Signature:** `convmap(char *filename)`
- **Purpose:** Converts a single map file from v6 to v5 format by reading, transforming, and writing.
- **Inputs:** Filename string (appends `.map` extension if missing)
- **Outputs/Return:** Void; writes converted file to disk; prints result message
- **Side effects:** Loads file into global sector/wall/sprite arrays; overwrites file with v5 data; sets `mapversion`
- **Calls:** `loadoldboard()`, `savenewboard()`
- **Notes:** Field-by-field copy from version 5 arrays to version 6 arrays; sets `nextsector2` and `nextwall2` to -1 (unused in v5).

### loadoldboard
- **Signature:** `loadoldboard(char *filename)`
- **Purpose:** Opens a version 6 map file, validates the version field, and reads all map data into global arrays.
- **Inputs:** Filename string
- **Outputs/Return:** `0` on success; `-1` if file not found; `-2` if version mismatch or already v5
- **Side effects:** Opens file handle; populates `mapversion`, player state (`posx`, `posy`, `posz`, `ang`, `cursectnum`), entity counts, and global arrays; closes file
- **Calls:** `open()` (DOS), `read()` (DOS), `close()` (DOS)
- **Notes:** Expects exactly version `NEWMAPVERSION+1` (i.e., 6). Uses binary file I/O with `O_BINARY` flag.

### savenewboard
- **Signature:** `savenewboard(char *filename)`
- **Purpose:** Opens or creates a file and writes the converted (version 5) map data.
- **Inputs:** Filename string (will be truncated and overwritten)
- **Outputs/Return:** `0` on success; `-1` if file creation fails
- **Side effects:** Opens/truncates file; writes version, player state, and all newsector/newwall/newsprite arrays; closes file
- **Calls:** `open()` (DOS), `write()` (DOS), `close()` (DOS)
- **Notes:** Writes binary format with `#pragma pack(1)` to ensure tight struct packing.

### getfilenames
- **Signature:** `getfilenames(char *kind)`
- **Purpose:** Enumerates files or subdirectories matching a DOS file pattern and populates the global `menuname` list.
- **Inputs:** File pattern string (e.g., `*.map` or special string `"SUBD"` for directories)
- **Outputs/Return:** `-1` if no matches; `0` otherwise
- **Side effects:** Populates `menuname[]` and increments `menunamecnt`; stores file type flag in `menuname[i][16]`
- **Calls:** `_dos_findfirst()`, `_dos_findnext()` (DOS API)
- **Notes:** Filters out `.` and `..` entries; caps at `MAXMENUFILES`; type flag (1 for directory, 0 for normal file) is stored in the 17th byte of the name string.

### sortfilenames
- **Signature:** `sortfilenames()`
- **Purpose:** Sorts the `menuname[]` array lexicographically using bubble sort.
- **Inputs:** None (operates on global `menuname` and `menunamecnt`)
- **Outputs/Return:** Void; modifies `menuname[]` in-place
- **Side effects:** Reorders filenames; uses temporary 32-byte buffer
- **Calls:** `memcpy()` (C standard library)
- **Notes:** Simple O(n²) bubble sort; preserves the type flag in byte 16.

## Control Flow Notes
1. **Initialization:** `main()` reads arguments, calls `getfilenames()` to enumerate files, and `sortfilenames()` to order them.
2. **Per-File Processing:** For each filename, `convmap()` is called:
   - `loadoldboard()` reads the v6 map from disk.
   - Field-by-field copying transforms v5 arrays into v6 arrays (note: the naming is reversed from conversion direction).
   - `savenewboard()` writes the v6 arrays back to disk as version 5.
3. **Shutdown:** Program exits after all files are processed; no explicit cleanup.

## External Dependencies
- **Standard C / DOS APIs:** `fcntl.h`, `io.h`, `sys/types.h`, `sys/stat.h`, `dos.h`
- **File I/O:** `open()`, `read()`, `write()`, `close()` (DOS binary file I/O)
- **DOS Directory Listing:** `_dos_findfirst()`, `_dos_findnext()`, `find_t` struct (DOS-specific; not POSIX)
- **String/Memory:** `strchr()`, `strcat()`, `strcmp()`, `strcpy()`, `memcpy()` (C standard library)
- **I/O:** `printf()` (C standard library)
- **Struct Packing:** `#pragma pack` (compiler directive for binary layout control)

---

**Notes:**
- This is a **DOS-era utility** (early 1990s) targeting 16-bit DOS environments; uses obsolete DOS file APIs.
- The conversion is **backwards** in naming: it reads "new" (v6) data and writes "new" (v6) arrays, but saves as version 5. This is intentional—the utility downgrades maps.
- Dual wall connectivity (`nextsector1/2`, `nextwall1/2`) in v6 is collapsed to single pointers in v5; unused v6 pointers are hardcoded to `-1`.
- Sprite cstat is cast from v5 `short` to v6 `char`, losing upper byte precision.
