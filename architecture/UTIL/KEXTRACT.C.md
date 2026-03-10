# UTIL/KEXTRACT.C

## File Purpose
A utility program that extracts files from Ken Silverman's proprietary group file archive format. It validates the group file, matches filenames using wildcard patterns (* and ?), and extracts matching files to disk.

## Core Responsibilities
- Validate group file format (magic header "KenSilverman")
- Parse group file metadata (file list, offsets, sizes)
- Support wildcard pattern matching for file selection
- Support @filename syntax to read extraction lists from external files
- Extract matched files from the group archive to disk

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `filelist[MAXFILES][16]` | char array | Stores null-terminated filenames from group file |
| `fileoffs[MAXFILES+1]` | long array | Byte offsets for each file within the group archive |
| `fileleng[MAXFILES]` | long array | Byte lengths of each file |
| `marked4extraction[MAXFILES]` | char array | Bitmap: 1 if file matches pattern, 0 otherwise |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `buf` | char[65536] | static | I/O buffer for reading/writing file data (64 KB) |
| `numfiles` | long | static | Count of files in the loaded group archive |
| `anyfiles4extraction` | long | static | Flag: 1 if any files matched pattern, 0 otherwise |

## Key Functions / Methods

### main
- **Signature:** `int main(short argc, char **argv)`
- **Purpose:** Entry point; orchestrates group file extraction workflow.
- **Inputs:** Command-line arguments: group file path, then file patterns or @list files.
- **Outputs/Return:** Exits program with status code.
- **Side effects:** Opens files, reads group header and metadata, writes extracted files to disk, closes file handles.
- **Calls:** `open()`, `read()`, `close()`, `lseek()`, `write()`, `findfiles()`, `exit()`.
- **Notes:** Exits early if argc < 3 (not enough arguments) or if no files match patterns. Errors on invalid group file magic header. Files are extracted in order, with 64 KB buffering.

### findfiles
- **Signature:** `void findfiles(char *dafilespec)`
- **Purpose:** Match a wildcard filespec against all files in the group; mark matches for extraction.
- **Inputs:** Wildcard pattern (e.g., "tiles*.art", "*.map").
- **Outputs/Return:** None (side effects only).
- **Side effects:** Sets `marked4extraction[i]` to 1 for matching files; sets `anyfiles4extraction` to 1 if at least one match found.
- **Calls:** None (self-contained).
- **Notes:** Supports * (matches rest of filename) and ? (single char wildcard). Case-insensitive matching. Pads filenames to 12 bytes (8 name + 4 extension) for consistent matching.

## Control Flow Notes

1. **Initialization:** Validate command-line arguments, open and read group file header, validate "KenSilverman" magic.
2. **Parsing:** Read file metadata (names, offsets, lengths) from first 16+(numfiles×16) bytes of group file.
3. **Pattern Matching:** Iterate through command-line arguments (or lines from @files); call `findfiles()` for each, marking files that match wildcards.
4. **Extraction:** For each marked file, seek to offset, read in 64 KB chunks, and write to a new file on disk.
5. **Shutdown:** Close input and output file handles; exit.

## External Dependencies
- **I/O:** `stdio.h` (printf), `fcntl.h`, `io.h` (open, read, write, lseek, close)
- **String:** `string.h` (strcpy, memset via loop)
- **File metadata:** `sys/types.h`, `sys/stat.h` (mode constants)
- **Legacy DOS:** `dos.h`, `conio.h` (minimal use; likely for DOS compatibility)
- **No internal dependencies:** All logic is self-contained within this file.
