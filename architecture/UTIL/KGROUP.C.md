# UTIL/KGROUP.C

## File Purpose
A DOS utility that creates "group files" — uncompressed archives combining multiple game assets (art, maps, palettes, etc.) into a single container. Supports wildcard expansion and indirect file lists via response files.

## Core Responsibilities
- Parse command-line arguments (output filename and input file specs)
- Support response files (prefixed with `@`) containing lists of file patterns
- Recursively find files matching DOS wildcards via `_dos_findfirst`
- Serialize matched files into a group file with a fixed header format
- Stream large files through a 64KB buffer to avoid memory limits

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| `find_t` | struct | DOS file search structure (defined elsewhere, from `<sys/types.h>`) |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `buf` | `char[65536]` | static | I/O buffer for file read/write operations |
| `numfiles` | `long` | static | Total count of files matched and added to group |
| `filespec` | `char[4096][128]` | static | Full paths of matched files |
| `filelist` | `char[4096][16]` | static | File metadata: 12-byte name + 4-byte size (little-endian) |
| `fileleng` | `long[4096]` | static | File sizes in bytes |

## Key Functions / Methods

### main
- **Signature:** `main(short argc, char **argv)`
- **Purpose:** Entry point; orchestrates group file creation.
- **Inputs:** Command-line arguments: `argv[1]` = output filename, `argv[2..]` = input files/specs or response files (prefixed `@`).
- **Outputs/Return:** Writes group file to disk; calls `exit(0)` on success or error.
- **Side effects:** Opens/reads response files, calls `findfiles()` for each spec, creates and writes output group file, performs disk I/O.
- **Calls:** `findfiles()`, `open()`, `read()`, `write()`, `close()`, `strcpy()`, `printf()`, `exit()`, `getch()`, `min()`.
- **Notes:** Exits on usage error (argc < 3), file I/O errors, or disk full. Group file format: 12-byte header ("KenSilverman") + 4-byte file count + `numfiles * 16` bytes of metadata + concatenated file contents.

### findfiles
- **Signature:** `findfiles(char *dafilespec)`
- **Purpose:** Matches files against a wildcard pattern and populates global file arrays.
- **Inputs:** `dafilespec` — DOS wildcard pattern (e.g., `*.art`).
- **Outputs/Return:** None (updates global state).
- **Side effects:** Increments `numfiles`; populates `filelist[]`, `fileleng[]`, `filespec[]` arrays. Calls DOS file search API.
- **Calls:** `_dos_findfirst()`, `_dos_findnext()`, `strcpy()`, `printf()`, `exit()`.
- **Notes:** Exits fatally if `numfiles > MAXFILES` (4096). Encodes file size into `filelist[n][12..15]` in little-endian format. Reconstructs full paths by prepending directory prefix from input spec.

## Control Flow Notes
1. **Init:** Parse argv; process response files and expand wildcards.
2. **Setup:** Create output group file; write header and file metadata.
3. **Main loop:** For each matched file, open, stream through 64KB buffer, and write to group file.
4. **Shutdown:** Close all files; print summary and exit.

## External Dependencies
- **Includes:** `<stdio.h>`, `<string.h>`, `<fcntl.h>`, `<io.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<dos.h>`, `<conio.h>`
- **External symbols:** `_dos_findfirst()`, `_dos_findnext()` (DOS file API); `open()`, `read()`, `write()`, `close()` (POSIX-like I/O); `strcpy()`, `printf()`, `exit()`, `getch()` (standard C); `min()` macro (standard).
