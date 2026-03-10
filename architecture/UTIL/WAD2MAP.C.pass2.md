# UTIL/WAD2MAP.C — Enhanced Analysis

## Architectural Role

WAD2MAP.C is a **content preprocessing tool** that bridges Doom's WAD asset format to the Build engine's native binary map format. It sits at the engine's content intake boundary: operators run this utility during development/asset production to convert Doom maps into Build maps that the editor (BUILD.C) and runtime (ENGINE.C) can load via CACHE1D.C. The file produces binary sector[], wall[], sprite[] structures on disk that match the in-memory layouts used by the rendering and game logic subsystems—establishing a **format contract** between asset pipeline and runtime engine.

## Key Cross-References

### Incoming (who depends on this file)
- **No incoming dependencies**: WAD2MAP.C is a standalone utility executable, never called by other modules
- Operators invoke it manually: `wad2map [pwad] iwad mapname [script.txt]`
- Its output (`.map` files) is consumed by BUILD.C (editor) via CACHE1D.C::`loadboard()`

### Outgoing (what this file depends on)
- **DOS file I/O**: `open()`, `read()`, `write()`, `lseek()`, `close()` — reads Doom WADs, writes Build .map files
- **String primitives**: `stricmp()`, `strcpy()`, `atol()` — case-insensitive WAD lump matching, command parsing
- **Math**: `mulscale10()`, `ksqrtasm()`, `klabs()` from PRAGMAS.H — fixed-point coordinate scaling and approximation
- **Memory**: `clearbufbyte()`, `FP_OFF()` from PRAGMAS.H — buffer initialization and DOS segment offset calculation
- **No engine subsystem calls**: Unlike BUILD.C, WAD2MAP does not invoke ENGINE.C, CACHE1D.C, or KDMENG.C; it only reads WAD files and writes structured binary output

## Design Patterns & Rationale

**Two-File WAD System** — Doom's IWAD+PWAD separation (base + patch) is handled gracefully:
- Detects file type from magic bytes (0x49574144 "IWAD" vs 0x50574144 "PWAD")
- Canonical texture/sprite definitions come from IWAD; map data from PWAD (if provided) or IWAD
- Rationale: enables mod creation without repackaging base game assets

**Static Global Arrays** — Mirrors BUILD.C/ENGINE.C memory model for DOS constraints:
- Contiguous `sector[MAXSECTORS]`, `wall[MAXWALLS]`, `sprite[MAXSPRITES]` in program data segment
- No dynamic allocation or pointer indirection
- Direct binary write to disk preserves memory layout without serialization code
- Rationale: 1990s DOS real-mode constraints (limited heap, segment-based addressing)

**Generic Field Accessor Pattern** — `getspritefield(index, fieldnum)` / `setspritefield(index, fieldnum, value)` decouple script logic from struct layout:
- Large switch statements map field IDs (0–21 for sprite, 32–53 for sector, 64–80 for wall) to struct fields
- Enables script-driven customization without recompilation
- Rationale: non-programmers can tweak conversions via `.txt` script sections (`[THINGTYPES]`, `[SECTORCONVERSIONS]`, etc.)

**Two-Phase Geometry Transformation** — Doom's linedef+sidedef model → Build's sector+wall hierarchy:
- Phase 1: Parse linedefs/sidedefs; for each sector, collect and order walls by vertex connectivity
- Phase 2: Establish Build sector → wall linked list via `point2` chaining; compute wall adjacency (`nextwall`, `nextsector`)
- Rationale: topological mismatch between engines requires explicit graph reconstruction

**Hardcoded Sprite Mapping Table** — `thinglist[]` array maps Doom entity types to Build sprite picture names:
- 123 entries covering Doom's standard creature/item types (e.g., thing type 3001 → "TROOA1")
- Lookups by type index; can be overridden by script `[THINGTYPES]` section
- Rationale: Doom and Build use incompatible numeric IDs; human-readable names are stable across asset versions

## Data Flow Through This File

```
Doom WAD (binary)
  ↓
WAD index tables (IWAD/PWAD lumps sorted by name)
  ↓
Lump lookups: TEXTURE1/TEXTURE2 → texture_offset_table[]
              PNAMES → pname[] (sprite pictures)
              Map lump → VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, THINGS
  ↓
Doom intermediate structs
  ├─ px[], py[] (vertex coords)
  ├─ line[] (Doom linedef)
  ├─ side[] (Doom sidedef + textures)
  ├─ sect[] (Doom sector)
  └─ thing[] (Doom entity)
  ↓
Geometry conversion
  ├─ For each Doom sector: collect linedefs, chain walls (Build sector → wall list)
  ├─ Texture lookup: sidedef name (e.g., "BRICK1") → TEXTURE1 entry → PNAMES index → WAD sprite picnum
  ├─ Sprite type mapping: Doom thing type → Build sprite picnum via thinglist[] or script override
  ├─ Coordinate transform: Doom (x, y) pixel space → Build fixed-point (centered, scaled)
  └─ Script customization: apply field operations (+=, |=, etc.) from parsed [THINGTYPES] / [SECTORCONVERSIONS] sections
  ↓
Build engine structs (all 3 arrays fully populated)
  ├─ sector[] (MAXSECTORS) — floor/ceiling pictures, heights, visibility, shade
  ├─ wall[] (MAXWALLS) — positions, textures, portal links (nextwall/nextsector), offsets
  └─ sprite[] (MAXSPRITES) — positions, types, angles, tags, per-sprite field overrides
  ↓
Binary .map file (disk)
```

Key insight: **coordinate origin is implicitly centered** (`cx`/`cy` computed as center of all vertices), and **all texture names are normalized to 8-char uppercase** to survive Doom's loose naming conventions.

## Learning Notes

1. **Pre-computed Fixed-Point Square Root**: `sqrtable[2048]` and `initksqrt()` demonstrate 1990s optimization strategy. Rather than calling `sqrt()` at runtime, the engine pre-computes a 10-bit fixed-point approximation table via Newton–Raphson. This is fast (table lookup + shift) but unusual by modern standards (would just call `std::sqrt()`).

2. **Implicit Coordinate Space Conversion**: Build uses **map units** (where ~1024 units ≈ one screen height); Doom uses **pixel units**. The center-and-scale logic (`cx = (minx+maxx)>>1 & 0xffffffc0`) is subtle—it's not just translating; it's aligning to a 64-unit boundary for numerical stability. This is characteristic of fixed-point engine design.

3. **Sector-Wall Hierarchy Reconstruction**: Doom represents geometry as **edges** (linedefs with two sided references); Build represents it as **containment** (sector owns wall linked list). WAD2MAP must invert this relationship: given a sector, find all edges touching it, then topologically sort them into a chain. This is a non-trivial graph algorithm buried in main's loop. Modern engines (using halfedge or face-edge meshes) would abstract this better.

4. **Script as Runtime Configuration**: The `parsescript()` function and field accessor pattern show pragmatic 1990s asset pipeline design. Non-technical level designers could edit a `.txt` file to adjust Doom→Build mappings without touching C code or recompiling. This predates data-driven engines but follows the same principle.

5. **No Explicit Error Recovery**: The file validates input minimally (WAD magic, lump existence) but reads arrays directly from disk with no bounds checking. A malformed WAD would corrupt global arrays silently. This was acceptable for **internal tooling** (assets controlled by developers), but not for shipped-product file loading.

## Potential Issues

1. **Silent Sprite Type Mismatches**: If a PWAD contains a custom Doom entity type not in `thinglist[]`, it won't be found; the sprite is created with type 0 (possibly invisible or default behavior). The script override mechanism is the documented fix, but undocumented types silently map wrong.

2. **Fixed Buffer Sizes with Untrusted Input**: Arrays like `px[MAXPOINTS]` and `line[MAXLINES]` are filled from WAD lumps without explicit bounds checks (relying on `dnumpoints = pwadlen[w] >> 2` truncation). An oversized PWAD could overflow static buffers. However, DOS-era tools typically assumed **trusted asset creation** (internal team), not user-submitted content.

3. **Struct Packing Assumptions**: The code reads `sizeof(linedeftype)`, `sizeof(sidedeftype)`, etc., directly from disk. If pragmas.h doesn't enforce `#pragma pack(1)`, struct padding could misalign field reads. This is brittle across compiler versions.

4. **Script Parser Single-Pass**: The script parser doesn't validate field indices or operation types at parse time; errors surface during sprite customization as silent no-ops. For example, typos in field names (e.g., `picnum2` instead of `picnum`) would be silently ignored.

5. **Implicit Texture Lookup Failure**: When a sidedef references a texture name (e.g., "BRICK1") that exists in Doom but not in the PNAMES WAD lump (possible for custom WINGs), `sidetoppic[z]` remains -1, and the wall is rendered with texture ID -1 (undefined behavior in ENGINE.C). Modern engines would log a warning and use a fallback texture; this silently corrupts.
