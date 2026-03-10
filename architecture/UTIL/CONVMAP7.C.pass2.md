# UTIL/CONVMAP7.C — Enhanced Analysis

## Architectural Role

CONVMAP7.C is a **forward-compatibility utility** in the Build Engine's map versioning pipeline, enabling existing level data (v6) to migrate to newer engine versions (v7). It sits at the boundary between persistent map storage and runtime representation: it reads binary map files that conform to the editor's output format, applies schema transformations that reflect changes in the engine's sector/wall/sprite struct layouts, and writes a new binary format that the engine's `loadboard()` (in CACHE1D.C) expects. This is essential during engine releases when struct padding or field reordering changes to maintain backward compatibility with legacy maps.

## Key Cross-References

### Incoming (who depends on this file)
- **User/Build system**: Invoked manually as a DOS command-line utility; not called by other engine code
- **Paired converters**: Mirrors the structure and logic of CONVMAP5.C, CONVMAP6.C (forward pipeline) and BACKMAP6.C (reverse pipeline)

### Outgoing (what this file depends on)
- **No engine subsystem calls**: This file is entirely standalone and self-contained
- **DOS file I/O**: `open()`, `read()`, `write()`, `close()` with MS-DOS flags (`O_BINARY`, `O_TRUNC`, `O_CREAT`, `O_WRONLY`)
- **DOS file search**: `_dos_findfirst()`, `_dos_findnext()`, `find_t` (non-portable API)
- **Standard libc**: `strchr()`, `strcat()`, `strcmp()`, `strcpy()`, `memcpy()`, `printf()` 
- **No external globals**: Does not reference SRC/BUILD.H's global arrays or state (defines its own parallel arrays)

## Design Patterns & Rationale

**Struct-Based Migration Pipeline**
- Defines both old and new struct layouts with explicit `#pragma pack(push,1)` alignment
- Field-by-field copying ensures fine-grained control over migration (enables field reordering, type promotion, or conditional transformations)
- This is safer than binary casting and documents what actually changed between versions

**Static Parallel Arrays (v6 ↔ v7)**
- Mirrors the engine's data model in SRC/BUILD.H (also uses static arrays: `sector[]`, `wall[]`, `sprite[]`)
- Dual-array pattern (`sector[]` + `newsector[]`, `wall[]` + `newwall[]`, `sprite[]` + `newsprite[]`) decouples read and write without dynamic allocation
- Batch transformation avoids intermediate I/O and is cache-friendly

**Height Value Transformation Logic**
```c
newsector[i].ceilingheinum = max(min(((long)sector[i].ceilingheinum)<<5,32767),-32768);
if ((sector[i].ceilingstat&2) == 0) newsector[i].ceilingheinum = 0;
```
- Left-shift by 5 bits (multiply by 32) increases precision: v6 used coarser height units, v7 uses finer increments
- Conditional zeroing when stat bit 2 is unset (ceiling/floor is *not* sloped) avoids storing meaningless heights
- Clamping to signed 16-bit range reflects a type change (byte → short)

**Version Validation**
- Reads version field first; rejects files that are already v7 or are neither v6 nor v7
- Fails safely rather than silently corrupting data

**Batch File Discovery & Sorting**
- `getfilenames()` discovers all matching files via DOS wildcards (`_dos_findfirst/findnext`)
- `sortfilenames()` uses naive O(n²) bubble sort for alphabetic ordering
- Ensures reproducible, ordered processing across different directory states

## Data Flow Through This File

```
[DOS filesystem]
    ↓
getfilenames() → menuname[] (file list)
    ↓
sortfilenames() → sorted menuname[]
    ↓
convmap(filename) ──→ for each file:
    ├─ loadoldboard()  → reads binary v6 format
    │                    sector[], wall[], sprite[] populated
    │                    mapversion validated
    ├─ conversion loop  → sector → newsector, wall → newwall, sprite → newsprite
    │                    height values left-shifted & clamped
    │                    struct field reordered, padding inserted
    └─ savenewboard()  → writes binary v7 format
    ↓
[Modified DOS filesystem: *.map files in v7 format]
```

**Key transformation**: v6 `ceilingheinum` (byte, 0–255) → v7 `ceilingheinum` (short, -32768–32767 after `<< 5`).

## Learning Notes

**Era-Specific Patterns**
- **DOS file API**: Open flags (`O_BINARY`, `O_CREAT`, `O_TRUNC`) and `_dos_findfirst/findnext` were standard for MS-DOS/early Windows development; utterly non-portable by modern standards
- **pragma pack(1)**: Used to enforce byte-aligned struct layouts for binary file format compatibility; critical for data interchange but fragile across compilers
- **Fixed memory pools**: No `malloc()` here; static arrays with compile-time limits (MAXSECTORS=1024, MAXWALLS=8192, MAXSPRITES=4096) match engine constraints
- **Manual field migration**: No reflection, serialization libraries, or schema versioning tools—each conversion is hand-coded

**Engine Architecture Insight**
- The struct layouts reveal the map data model's evolution: v6 had tighter packing, v7 added explicit padding for alignment or future expansion
- Version numbering (v5, v6, v7) suggests the engine went through multiple major iterations, with level compatibility being a *design concern* (not afterthought)
- The presence of both forward (CONVMAP) and reverse (BACKMAP) converters indicates users could downgrade maps if needed

**Idiomatic to Build Engine (vs. Modern Engines)**
- **No asset caching**: Each conversion is a fresh read/write; no delta compression or incremental updates
- **No metadata**: The map file contains only geometry, sprites, and player spawn; no build timestamps, converter version, or audit trail
- **Monolithic file format**: All map data in one binary blob, no separate textures/sounds/scripts (though engine later supported these via group files)

## Potential Issues

1. **Height Precision Assumption**: The `<< 5` transformation assumes v6 heights were in units where multiplying by 32 produces meaningful v7 values. If the original height semantics differed, maps could become geometrically distorted. No documentation validates this assumption is correct for all maps.

2. **Silent Truncation of Heights**: If a v6 ceiling/floor height exceeds the v7 signed-short range after left-shift, `max(min(...))` silently clamps. Maps with extreme heights could become unreliable without warning.

3. **Stat Bit 2 Semantics**: The code assumes bit 2 of `ceilingstat`/`floorstat` definitively means "is sloped." If the engine ever changed this flag's meaning or introduced new stat bits, the conditional zeroing could misbehave.

4. **No Rollback/Validation**: Once converted, the original v6 file is overwritten. There's no backup, checksum validation, or in-place conversion test. A failed conversion is destructive.

5. **Incomplete Version Compatibility Check**: The file only validates `mapversion == NEWMAPVERSION-1` (i.e., == 6). If a map is v7 already, it returns -2 but doesn't attempt idempotency. Re-running the converter on a v7 file will report "already map version 7" without doing work—this is safe but could surprise users expecting a no-op.

---

**Summary for a developer studying this engine:** CONVMAP7 exemplifies how 1990s game engines handled forward compatibility through procedural struct migration. It's a stripped-down ETL pipeline (Extract-Transform-Load) hardcoded for one schema change. Modern engines would use reflection, versioned serialization formats (JSON/Protobuf), or migration scripts, but for a DOS utility targeting level designers, this batch converter was pragmatic and transparent.
