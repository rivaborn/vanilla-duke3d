# UTIL/CONVMAP6.C — Enhanced Analysis

## Architectural Role

This utility implements the **Map Format Converters** subsystem for Build engine map schema evolution. Specifically, it migrates map files from version 5 to version 6, handling structural migrations that arise from ongoing engine development. The converter operates as a standalone command-line tool, independent of the core engine (ENGINE.C) and editor (BUILD.C), enabling batch map updates without modifying source asset files.

## Key Cross-References

### Incoming (who depends on this)
- **No in-process dependencies**: This is a standalone executable with `main()`. It is not called by any other engine or editor subsystem. It exists as an independent CLI tool invoked by users for batch conversion.

### Outgoing (what this file depends on)
- **DOS/POSIX file I/O** (`open`, `read`, `write`, `close`): POSIX file operations for binary map I/O
- **DOS file search** (`_dos_findfirst`, `_dos_findnext`): wildcard file discovery for batch processing
- **Standard C library** (`strchr`, `strcat`, `strcmp`, `strcpy`, `memcpy`, `printf`, `exit`): string and memory utilities
- **sectorofwall()** (local helper): linear search to determine containing sector for a wall index
- **No dependency on BUILD.H globals**: Unlike the editor, this utility does NOT link against the engine's global sector/wall/sprite arrays—it uses its own static buffers (`sector[MAXSECTORS]`, `wall[MAXWALLS]`, `sprite[MAXSPRITES]`)

## Design Patterns & Rationale

### Field-by-Field Struct Migration
The converter explicitly copies each field from v5 to v6 structs rather than bulk-copying. This is necessary because:
- **Layout mismatch**: v5 `walltype` has redundant fields (`nextsector2`, `nextwall2`); v6 consolidates to single `nextsector`/`nextwall`
- **Type changes**: v5 `spritetype.cstat` is `char`; v6 promotes it to `short` for range
- **New fields**: v6 adds `pal`, `clipdist`, `xoffset`, `yoffset` to sprites; `pal` to walls

### Derived Field Computation (Schema Debt Resolution)
Rather than require user intervention, the converter automatically derives missing v6 fields from v5 data:
- **Wall palette** (new in v6): Inherited from containing sector's `floorpal` (line 229). Avoids manual per-wall annotation.
- **Sprite palette** (new in v6): Conditional logic checks sector's `ceilingstat` bit 0 (sky flag) to choose between ceiling or floor palette (lines 244–247). Maintains spatial coherence.
- **Sprite clipdist** (new in v6): Hard-coded to 32 pixels (line 249). File header comment notes this as a newly added field; value is a conservative default for collision radius.
- **Sprite offsets** (new in v6): Hard-coded to 0 (lines 250–251). Suggests these were added for future feature support (sprite scaling origins) but left unused in v5 maps.

### DOS-Era Batch Processing
The utility uses DOS file discovery (`_dos_findfirst`, `_dos_findnext`) with simple bubble-sort name collection. This pattern is idiomatic for 1990s command-line utilities before widespread use of glob libraries or file system abstraction layers. The `menuname[i][16]` field stores a type flag (0=file, 1=directory), enabling directory filtering.

## Data Flow Through This File

```
main(argv[1] = filespec)
  → getfilenames(filespec)  [populate menuname[] array via DOS search]
  → sortfilenames()          [bubble-sort alphabetically]
  → loop over menuname[]:
       convmap(filename)
         → loadoldboard(filename)
              [read v5 binary: mapversion check, then sector/wall/sprite arrays]
         → copy + transform:
              sector[i] → newsector[i]  [direct copy, all fields align]
              wall[i] → newwall[i]      [copy + derive pal from sector]
              sprite[i] → newsprite[i]  [copy + derive pal + set defaults for new fields]
         → savenewboard(filename)
              [write v6 binary: overwrite original file]
```

**Key observation**: The converted map **overwrites the original file**. There is no backup; this is destructive but intentional for batch processing workflows.

## Learning Notes

### 1. **Schema Versioning Without Abstraction**
This utility exemplifies pre-OOP, pre-framework map versioning: raw binary struct layout awareness and explicit migration logic. Modern engines (Unreal, Unity, Godot) use serialization frameworks (JSON, YAML, Protobuf) or versioned object graphs. The Build engine's approach is tightly coupled to C struct layout—any struct size change breaks forward/backward compatibility, necessitating these converter utilities.

### 2. **The "Missing Parent Pointer" Anti-Pattern**
The `sectorofwall()` function (lines 351–365) performs a linear O(N×M) search to find which sector owns a wall. This hints that v5 wall structs don't store a back-pointer to their owning sector—walls are just part of a global array, indexed only through sector's `wallptr` and `wallnum`. Modern engines would store `wall.owning_sector` directly. The converter needs this lookup only to inherit palette, suggesting v6 still doesn't add the back-pointer, relying on spatial locality.

### 3. **Palette as Engine-Level Concern**
The sprite and wall palette logic reveals the Build engine's palette-centric rendering model. Every drawable entity (wall, sprite, floor, ceiling) references a palette bank. Rather than per-pixel color data, surfaces reference a 256-color palette index. The converter's inheritance heuristics (sprite takes sector's palette; wall takes sector's floor palette) show that palette assignment was implicit in v5, requiring inference during migration to v6's explicit schema.

### 4. **Idiomatic 1990s DOS Tooling**
The use of DOS-specific header files (`<dos.h>`, `<io.h>`) and DOS API calls (`_dos_findfirst`, `_dos_findnext`) anchors this code to 16-bit DOS/Windows 3.x era. Modern cross-platform refactors would replace these with POSIX equivalents or higher-level file system libraries.

## Potential Issues

1. **Linear Sector Lookup Performance**  
   `sectorofwall()` scans all sectors per wall. For maps with 1000+ walls, this becomes O(1000000) comparisons during conversion. Acceptable for a batch tool but wasteful; could be precomputed once.

2. **No Validation of Wall-to-Sector Mapping**  
   The converter assumes every wall index falls within at least one sector's range. If a map has orphaned walls (index outside all sector ranges), `sectorofwall()` returns -1, but the converter does not check for this before using the result in array indexing (line 229).

3. **Hard-Coded Defaults May Not Suit All Content**  
   `clipdist=32` and `xoffset/yoffset=0` are shipped as-is to all sprites. If older maps had relied on implicit sprite behavior sensitive to these fields (unlikely, given they're newly added), the defaults might produce unintended visual or collision changes. The file header's comment suggests these are "added" features, implying v5 didn't use them.

4. **No Rollback or Dry-Run Mode**  
   The tool destructively overwrites the input file. A power loss or disk error during `savenewboard()` corrupts the map with no recovery mechanism.
