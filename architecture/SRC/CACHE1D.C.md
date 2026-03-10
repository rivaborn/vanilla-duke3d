# SRC/CACHE1D.C

## File Purpose

Provides three major subsystems for the Build Engine: a linear memory cache with intelligent eviction, a group file system for reading bundled archives, and LZW compression/decompression for file I/O.

## Core Responsibilities

- **Cache management**: Allocate/deallocate memory from a pre-allocated buffer with locking semantics and age-based eviction
- **Group files**: Load and manage multiple files packed into single .GRP archive files with directory metadata
- **File I/O abstraction**: Unified interface (`kopen4load`, `kread`, etc.) supporting both raw files and group file entries
- **LZW compression**: Encode/decode game data streams using LZW algorithm with 16KB working buffers
- **Memory aging**: Periodically decrement lock counts on cached regions to enable eventual eviction

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `cactype` | struct | Cache entry: pointer handle, length, lock pointer |
| `cac[MAXCACHEOBJECTS]` | array | Static cache block table (up to 9216 entries) |
| `lockrecip[200]` | array | Precomputed reciprocals `(1<<28)/(200-i)` for lock-based eviction scoring |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `cachesize`, `cachestart` | long | static | Cache buffer bounds |
| `cacnum`, `agecount`, `cachecount` | long | static | Current blocks, aging pointer, allocation counter |
| `zerochar` | char | static | Sentinel unlock marker |
| `groupfil[MAXGROUPFILES]` | long[] | static | Open file handles for group files |
| `gfilelist`, `gfileoffs` | char*[], long*[] | static | Group file directory and offset tables |
| `filehan[MAXOPENFILES]`, `filegrp[]` | long[], char[] | static | Open file handles and group membership |
| `lzwbuf1–5`, `lzwbuflock[]` | char*, short*, short*, char[] | static | LZW compression work buffers and lock flags |
| `toupperlookup[256]` | char[] | static | Case-insensitive filename lookup table |

## Key Functions / Methods

### initcache
- **Signature:** `initcache(long dacachestart, long dacachesize)`
- **Purpose:** Initialize cache system with pre-allocated memory buffer
- **Inputs:** Cache buffer start address and size in bytes
- **Outputs/Return:** None
- **Side effects:** Initializes `cac[0]`, sets `cacnum=1`, precomputes `lockrecip` lookup table
- **Calls:** None (inline state setup)
- **Notes:** Must be called before `allocache`; lock reciprocal table is used for eviction heuristics

### allocache
- **Signature:** `allocache(long *newhandle, long newbytes, char *newlockptr)`
- **Purpose:** Allocate cache space, evicting lower-priority blocks if needed
- **Inputs:** Pointer to handle location, requested size (rounded to 16-byte alignment), lock flag pointer
- **Outputs/Return:** Sets `*newhandle` to allocated memory address
- **Side effects:** Updates `cac[]` table, zeroes evicted handle pointers, increments `cachecount`
- **Calls:** `mulscale32`, `copybufbyte`, `reportandexit`
- **Notes:** Finds best fit by scanning blocks and computing lock-weighted eviction cost; non-zero lock prevents removal

### suckcache
- **Signature:** `suckcache(long *suckptr)`
- **Purpose:** Manually free a cache block and merge adjacent empty blocks
- **Inputs:** Pointer to handle being freed
- **Outputs/Return:** None
- **Side effects:** Sets block lock to zero, zeros handle, merges with neighboring unlocked blocks
- **Calls:** `copybuf`
- **Notes:** Handles invalid pointers gracefully (scans all blocks)

### agecache
- **Signature:** `agecache(void)`
- **Purpose:** Decrement lock counts on cached blocks to reduce their eviction resistance
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:** Decrements ~1/16th of blocks per call, cycles through blocks using `agecount`
- **Calls:** None
- **Notes:** Lock values 1–199 are valid; values ≥200 prevent aging; provides soft pressure for eviction

### initgroupfile
- **Signature:** `initgroupfile(char *filename)`
- **Purpose:** Load a group file (.GRP) archive and populate file directory
- **Inputs:** Path to group file
- **Outputs/Return:** File handle (≥0) on success, -1 on failure
- **Side effects:** Opens file, allocates and reads directory metadata, populates `gfilelist[]` and `gfileoffs[]`
- **Calls:** `open`, `read`, `close`, `kmalloc`, `printf`, `exit`
- **Notes:** Expects "KenSilverman" 12-byte header + 4-byte file count; validates format before allocating

### uninitgroupfile
- **Signature:** `uninitgroupfile(void)`
- **Purpose:** Close all open group files and free directory memory
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:** Closes all open group file handles, frees `gfilelist` and `gfileoffs` arrays
- **Calls:** `kfree`, `close`

### kopen4load
- **Signature:** `kopen4load(char *filename, char searchfirst)`
- **Purpose:** Open file from filesystem or group archives with case-insensitive search
- **Inputs:** Filename, search mode (0=check filesystem first, non-zero=search groups first)
- **Outputs/Return:** File handle (0–63) on success, -1 on failure
- **Side effects:** Sets `filehan[]`, `filegrp[]`, `filepos[]` entries; marks group with 255 for raw files
- **Calls:** `open`
- **Notes:** Scans all group files for case-insensitive match using `toupperlookup` table

### kread
- **Signature:** `kread(long handle, void *buffer, long leng)`
- **Purpose:** Read from open file (raw or group)
- **Inputs:** File handle, destination buffer, byte count
- **Outputs/Return:** Bytes actually read
- **Side effects:** Updates `filepos[]` and `groupfilpos[]`; seeks group file if position mismatch
- **Calls:** `read`, `lseek`
- **Notes:** Clamps read to end of file within group; raw files use native `read()`

### klseek
- **Signature:** `klseek(long handle, long offset, long whence)`
- **Purpose:** Seek within file (supports SEEK_SET, SEEK_CUR, SEEK_END)
- **Inputs:** File handle, offset, seek mode
- **Outputs/Return:** New file position
- **Side effects:** Updates `filepos[]`
- **Calls:** `lseek` (raw files only)
- **Notes:** Group files are seeked virtually via `filepos[]`; raw files delegate to OS

### kfilelength
- **Signature:** `kfilelength(long handle)`
- **Purpose:** Get file size
- **Inputs:** File handle
- **Outputs/Return:** File size in bytes
- **Side effects:** None
- **Calls:** `filelength` (raw files only)

### kclose
- **Signature:** `kclose(long handle)`
- **Purpose:** Close file and mark handle unused
- **Inputs:** File handle
- **Outputs/Return:** None
- **Side effects:** Closes OS file handle if raw file; zeros `filehan[]`
- **Calls:** `close` (if applicable)

### compress
- **Signature:** `compress(char *lzwinbuf, long uncompleng, char *lzwoutbuf)`
- **Purpose:** LZW compression of input buffer
- **Inputs:** Uncompressed data, uncompressed length, output buffer
- **Outputs/Return:** Compressed length; stores uncompressed size and table size in first 4 bytes of output
- **Side effects:** Uses `lzwbuf1–3` for LZW table; outputs bitpacked codes with adaptive code width
- **Calls:** None
- **Notes:** Falls back to uncompressed copy if compression expands data; uses 9–12-bit codes up to 4096 table entries

### uncompress
- **Signature:** `uncompress(char *lzwinbuf, long compleng, char *lzwoutbuf)`
- **Purpose:** LZW decompression
- **Inputs:** Compressed data, compressed length, output buffer
- **Outputs/Return:** Uncompressed length (from header)
- **Side effects:** Uses `lzwbuf1–3` for decompression state; reconstructs dictionary on-the-fly
- **Calls:** `copybuf`
- **Notes:** Reads table size from header; if zero, data is uncompressed copy

### kdfread, dfread
- **Signature:** `kdfread(void *buffer, size_t dasizeof, size_t count, long fil)` / `dfread(..., FILE *fil)`
- **Purpose:** Read and decompress streamed data (like fread but with LZW decompression)
- **Inputs:** Destination, element size, element count, file handle
- **Outputs/Return:** None
- **Side effects:** Allocates LZW buffers on demand via `allocache`; locks buffers during I/O
- **Calls:** `allocache`, `kread`/`fread`, `uncompress`, `copybufbyte`, `min`
- **Notes:** Stores first element uncompressed; subsequent elements use delta encoding (byte differences)

### dfwrite
- **Signature:** `dfwrite(void *buffer, size_t dasizeof, size_t count, FILE *fil)`
- **Purpose:** Write compressed stream (inverse of dfread)
- **Inputs:** Source buffer, element size, element count, file handle
- **Outputs/Return:** None
- **Side effects:** Allocates LZW buffers on demand; compresses and writes to file
- **Calls:** `allocache`, `compress`, `fwrite`, `copybufbyte`
- **Notes:** First element stored as-is; subsequent elements delta-encoded; flushes when buffer exceeds threshold

## Control Flow Notes

- **Initialization:** `initcache()` → optional `initgroupfile()` calls
- **File I/O:** `kopen4load()` → `kread()`/`klseek()` loop → `kclose()`
- **Compressed I/O:** `dfread()`/`dfwrite()` call lower-level functions; buffers are cached and locked during operation
- **Cache aging:** `agecache()` intended to be called periodically (e.g., per frame) to gradually unlock old cache blocks
- **Shutdown:** `uninitgroupfile()` to clean up group files

## External Dependencies

- **Includes:** `dos.h`, `stdio.h`, `pragmas.h` (custom inline x86 assembly macros), `fcntl.h`, `io.h`, `sys/types.h`, `sys/stat.h`
- **Defined elsewhere:** `mulscale32`, `copybufbyte`, `copybuf`, `clearbuf`, `kmalloc`, `kfree`, `reportandexit`, `setvmode`, `min`, `uncompress`, `compress`, `FP_OFF` (far pointer offset macro)
- **OS calls:** `open`, `read`, `close`, `lseek`, `filelength`, `fread`, `fwrite` (DOS/DPMI model)
