# SRC/CACHE1D.C — Enhanced Analysis

## Architectural Role

CACHE1D.C is the engine's **unified resource management layer**, mediating all asset access across three dimensions: memory allocation, file abstraction, and compression. It sits at a critical junction: the renderer (ENGINE.C) and editor (BUILD.C) depend on its cache for tile graphics, while audio (KDMENG.C) and compressed archives require its LZW codecs. By unifying raw-file and group-archived I/O through `k*` functions, it enables transparent asset distribution and loading without changing caller code.

## Key Cross-References

### Incoming (who depends on this file)
- **ENGINE.C** — Calls `allocache` (indirectly via `loadtile` waloff[] locking); reads tiles via `kopen4load`/`kread`
- **BUILD.C** — Editor: `loadboard`/`saveboard` use `kopen4load`, `kread`, `klseek` for map I/O
- **KDMENG.C** — Audio engine: may call `allocache` for sound sample buffers; possibly uses `dfread` for compressed audio
- **CACHE1D.C itself** — `kdfread`/`dfread` call `allocache` for LZW working buffers; `allocache` uses `mulscale32` from PRAGMAS.H
- **Initialization callers** (indirect) — Engine startup must call `initcache()` before any asset loading

### Outgoing (what this file depends on)
- **PRAGMAS.H** — `mulscale32`, `copybufbyte`, `copybuf`, `clearbuf`, `min` macro
- **DOS/DPMI layer** — `open`, `read`, `close`, `lseek`, `filelength` (via fcntl.h, io.h)
- **Error handling** — `reportandexit`, `setvmode`, `printf` (for crash dumps)
- **Memory allocation** — `kmalloc`, `kfree` (must be defined elsewhere; used for group file directory)

## Design Patterns & Rationale

### 1. **Lock-Based LRU Variant**
The cache doesn't use strict LRU. Instead, each block has a lock pointer (`*lockptr`) referencing a byte:
- **Lock = 0**: Unlocked, eligible for eviction  
- **Lock = 1–199**: Weakly locked; `lockrecip[lock]` precomputes `(1<<28)/(200-lock)` as an eviction cost  
- **Lock ≥ 200**: Strongly locked, never evicted; fails allocation if no space (`"CACHE SPACE ALL LOCKED UP!"`)

**Rationale**: Allows fine-grained control per asset. A texture actively being rendered (lock=200) won't be evicted; a recently-used tile (lock=50) gradually becomes eligible as `agecache()` decrements it. This is more flexible than vanilla LRU for games where hotness varies per frame.

### 2. **Age-Based Decay**
`agecache()` decrements ~1/16th of blocks per call (using circular `agecount` pointer). Designed for **frequent polling** (e.g., per frame).  
**Rationale**: Soft pressure on cache without hard decisions. Avoids "cliff" evictions when a single large allocation arrives.

### 3. **Weighted Fit Scoring**
In `allocache`, the "best fit" isn't spatial—it's weighted by overlapping block lock values:
```c
daval += mulscale32(cac[zz].leng+65536,lockrecip[*cac[zz].lock]);
```
Prefers regions with weakly-locked neighbors over tightly-locked ones.  
**Rationale**: Maximizes the chance of success by evicting only what's truly recyclable.

### 4. **Unified File I/O Abstraction**
The `k*` functions (`kopen4load`, `kread`, `klseek`, `kfilelength`, `kclose`) abstract raw files vs. group archives:
- **Raw files**: `filegrp[handle] == 255`; delegated directly to OS  
- **Group files**: `filegrp[handle] < MAXGROUPFILES`; virtual seek via `filepos[handle]` buffer offset

**Rationale**: Asset distribution can switch from loose files to .GRP archives without rebuilding the game or changing load code.

### 5. **Compressed Asset Streaming**
`kdfread`/`dfread` and `dfwrite` use **delta encoding**: first element uncompressed, subsequent elements stored as byte-wise deltas from the previous. Compressed chunks are ~16KB chunks with length prefixes.  
**Rationale**: Reduces disk I/O and cache memory footprint; typical for game resource streaming in the 1990s.

### 6. **Group File Directory in RAM**
After `initgroupfile()`, the entire directory (`gfilelist`, `gfileoffs`) is held in memory. No eviction or lazy-load of metadata.  
**Rationale**: Fast file lookup by index; group files are assumed to be permanent (loaded at startup). Trades memory for speed.

## Data Flow Through This File

```
┌─ User Code (ENGINE, BUILD, KDMENG)
│
├─→ initcache(buffer, size)
│   └─→ Precomputes lockrecip[]; sets up cac[0] as one big free block
│
├─→ initgroupfile(filename)  [optional, 0–4 times]
│   └─→ Opens .GRP, reads directory, allocates gfilelist/gfileoffs
│
├─→ kopen4load(filename, searchfirst)
│   └─→ Searches filesystem (if searchfirst==0) or group files
│   └─→ Returns handle (0–63) mapped to raw file OR group file index
│
├─→ [per read]  kread(handle, buf, len)
│   └─→ Raw file: OS read()
│   └─→ Group file: lseek() group file, read from directory-indexed offset
│
├─→ [per seek]  klseek(handle, offset, whence)
│   └─→ Raw file: OS lseek()
│   └─→ Group file: updates virtual filepos[]
│
├─→ kclose(handle)
│   └─→ Closes underlying file, zeros filehan[]
│
├─→ [compressed]  dfread/dfwrite  (or  kdfread)
│   └─→ On first call: allocache() 5 LZW work buffers, lock them at priority 200
│   └─→ Loop: read/write 2-byte length prefix + compressed chunk
│   └─→ uncompress()/compress() with delta decoding/encoding
│
├─→ [periodic]  agecache()
│   └─→ Scans ~1/16 of cache blocks, decrements lock counts (soft pressure for eviction)
│
└─→ [on demand]  allocache(handle_ptr, size, lock_ptr)
    └─→ Scans all blocks, finds best-fit region with lowest lock-weighted cost
    └─→ Evicts (zeros) lower-lock blocks to make room
    └─→ Returns allocated address via handle_ptr
```

## Learning Notes

### For Engine Architecture
1. **Cache as coordination layer**: The cache is not just memory management—it's the hub where file I/O, compression, and memory pressure converge. Any asset bottleneck goes through here.

2. **Lock as soft commitment**: Unlike hard mutexes, locks are *suggestions* (1–199 range). A block with lock=50 might be evicted if pressure is high; lock=200 is immune. This lets the engine express confidence rather than binary ownership.

3. **Group files as distribution mechanism**: The .GRP format + abstraction layer enabled Duke 3D to ship thousands of assets in a single file without recompiling the engine or changing load paths. Modern engines use .PAK/.ZIP; same concept.

4. **Periodic decay for fairness**: `agecache()` is a background task, not triggered on allocation. This is different from modern LRU caches that evict on demand. Decoupling eviction pressure from allocation gives more predictable frame times.

### Idiomatic to 1990s Game Engines
- **No exceptions/error handling**: Failures call `reportandexit()` (crash dump to screen, exit to DOS). Recovery is not an option.
- **Linear memory model**: Assumes flat 32-bit address space with pre-allocated buffers. No fragmentation worries (contiguous buffer only).
- **Case-insensitive file lookup**: DOS convention; `toupperlookup[]` is a tiny optimization (256-byte lookup vs. tolower() calls).
- **Self-managed virtual file positioning**: Group file seeking is done in userspace (`filepos[]`), not via OS. Reduces syscalls.

### Modern Comparison
- **Modern engines** (Unreal, Unity): Virtual memory + streaming with async I/O. CACHE1D is synchronous and blocking.
- **Modern caching**: LRU/LFU with statistical eviction, not weighted scoring. No explicit "aging" cycle.
- **Compression**: Integrated into resource pipeline (offline compress, runtime streaming decompression), not baked into I/O layer.

## Potential Issues

### 1. **Lock Reciprocal Table Precision** (Subtle)
`lockrecip[i] = (1<<28)/(200-i)` precomputes with 28-bit precision. At i=199, divisor is 1, so reciprocal is 2^28. At i=1, divisor is 199, reciprocal is ~1.36M. When multiplied via `mulscale32()`, there's potential for overflow if block length is large. The `+65536` bias in the score calculation may compensate, but **no bounds checking** is visible.

### 2. **LZW Buffer Lock Contention** (Performance)
`kdfread`/`dfread` allocate 5 buffers on first call and lock them at priority 200 (permanent). If multiple reads happen concurrently or in rapid succession, the cache may refuse new allocations due to these 5 highly-locked buffers. **Workaround**: ensure LZW buffers are pre-allocated before intensive I/O phases.

### 3. **Group File Directory Memory Leak** (if misused)
`initgroupfile()` allocates `gfilelist[k]` and `gfileoffs[k]` with no way to unload a single group (only `uninitgroupfile()` closes all). If a level loads 10 different .GRP files and never unloads, memory accumulates.

### 4. **Filename Comparison Vulnerability** (if untrusted input)
`kopen4load()` does case-insensitive comparison for 13 bytes only (`for(j=0;j<13;j++)`). No null termination check within the group filename list; relies on callers providing null-terminated strings. **Risk**: buffer overrun if malformed group file.

### 5. **Synchronous I/O**
All reads/writes are blocking. On slow media (floppy, CD-ROM) or large group files, stalls are inevitable. No async or threaded I/O.
