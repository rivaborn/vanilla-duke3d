# SRC/BUILD.H — Enhanced Analysis

## Architectural Role

BUILD.H is the **universal data contract** for the entire Build Engine—it defines the parallel-array world representation (sector[], wall[], sprite[]), compile-time limits, and global state that every subsystem reads and writes. It acts as the schema that bridges the interactive editor (BUILD.C), the 3D renderer (ENGINE.C), the resource cache (CACHE1D.C), audio (KDMENG.C), networking (MULTI.C), and all utility tools. No subsystem owns the data; all operate on this shared global state.

## Key Cross-References

### Incoming (who depends on this file)
- **Render engine** (ENGINE.C): Iterates sector[], wall[], sprite[] during recursive portal visibility; culls visible sprites into tsprite[] for per-frame rendering
- **Editor** (BUILD.C, BSTUB.C): Reads/writes sectors, walls, sprites directly; uses linked-list accessors for spatial queries
- **Resource cache** (CACHE1D.C): Loads map files that populate sector[], wall[], sprite[] arrays; manages palookup[], waloff[], picanm[]
- **Multiplayer** (MULTI.C, MMULTI.C): Uses sprite[] to represent player entities and network sync state
- **Audio** (KDMENG.C): Can infer 3D sound positioning from sprite[].x/y/z (listener position)
- **Utilities** (EDITART.C, TRANSPAL.C, WAD2MAP.C, etc.): Use struct layouts and constants for format conversion and asset management

### Outgoing (what this file depends on)
- **None directly**—BUILD.H declares data without dependencies. It depends only on standard C types and the pragma pack directive for memory layout control.

## Design Patterns & Rationale

**1. Extern Macro for Dual Compilation**  
The `#ifdef ENGINE ... #define EXTERN ... #else #define EXTERN extern` pattern allows one header to serve both the engine (which *defines* globals) and game code (which *externs* them). This is a pre-C++ way of enforcing single-definition without linker nightmares.

**2. Parallel Arrays (not OOP/ECS)**  
Sectors, walls, and sprites are stored as flat arrays indexed by ID, not as objects in containers. This 1990s pattern offered:
- Cache-friendly sequential memory access for iteration
- O(1) random access by entity ID
- Minimal memory overhead (no pointers, vtables, or heap fragmentation)
Modern engines use ECS or scene graphs; this engine uses data-oriented flat arrays.

**3. Bit-Packed Flag Fields (cstat)**  
Each sector/wall/sprite reserves a single `short` for flags, with documented bit meanings (blocking, masking, translucency, flips, rendering modes). This was memory-critical in the 1990s and avoids per-flag struct members. Cross-reference shows rendering code (ENGINE.C, A.ASM) masks and tests these bits directly.

**4. Sprite Linked Lists (Dual Indexing)**  
Sprites maintain two concurrent linked-list chains:
- **Sector chain** (`headspritesect[]`, `nextspritesect[]`, `prevspritesect[]`): Fast iteration of sprites in a specific spatial zone
- **Status chain** (`headspritestat[]`, `nextspritestat[]`, `prevspritestat[]`): Fast iteration of sprites with a specific state (e.g., "active enemies", "blood particles")

This dual-chain design avoids O(n²) lookups; used throughout ENGINE.C (spatially aware collision) and BUILD.C (editor sprite lists). The -1 sentinel terminates chains.

**5. Precomputed Lookup Tables**  
`sintable[2048]` provides fixed-point sine (-16383 to +16383 range, 2048 angles vs. 360°). The comment reveals the mathematical identity:  
```
sintable[ang & 2047] = sin(ang * (3.141592/1024)) * 16383
sintable[(ang+512) & 2047] = cos(ang * ...)  // 512 angles = 90°
```
This avoids floating-point math entirely—pure integer arithmetic for rotation and vectors.

**6. Bit-Packed Visibility Arrays**  
`show2dsector[(MAXSECTORS+7)>>3]` stores visibility per sector as 8 sprites/walls/sectors per byte (using `spritenum >> 3` for byte index, `1 << (spritenum & 7)` for bit). This is a space-optimized automapping system for the 2D editor.

## Data Flow Through This File

1. **Map Load** → CACHE1D.C::loadboard() populates sector[], wall[], sprite[] from disk; sets numsectors, numwalls
2. **Sprite Lifecycle**:
   - Sprites are inserted into sector and status chains via linkage pointers
   - Per-frame: ENGINE.C reads sprite[i].x/y/z/ang/xvel/yvel/zvel to update physics and culling
   - Visible sprites copied to tsprite[] and sorted by depth
   - Rendering: drawsprite() in ENGINE.C/A.ASM reads tsprite[].picnum, .shade, .pal, .xrepeat, .yrepeat, .cstat
3. **Editor Mutations**: BUILD.C modifies sector/wall/sprite fields in-place; automapping arrays track what was visible in 3D mode for 2D minimap reveal
4. **Frame Timing**: totalclock (volatile, incremented by interrupt handler at 120 Hz) drives animation and timing logic in gameplay

## Learning Notes

**Engine Design from the 1990s:**
- No object-oriented encapsulation; all entities are indices into flat arrays (game[i], sprite[i])
- No garbage collection; fixed pre-allocated pools with reuse
- Dual linked lists for spatial + behavioral queries show sophisticated data structure thinking despite simplicity

**Optimization Consciousness:**
- Packed structs (1-byte padding rule) and fixed-size arrays minimize memory footprint for the era's RAM constraints (~8–32 MB RAM)
- Precomputed sintable eliminates per-frame trig overhead
- Bit-packed flags and visibility arrays save orders of magnitude in memory for large maps
- Sprite linked lists avoid O(n²) spatial queries

**Differences from Modern Engines:**
- **No scene graph**: Direct array indexing, not hierarchical transforms
- **No ECS**: No component system; monolithic structs with hardcoded fields
- **No prefab/template system**: Every sprite is manually placed and edited
- **No material/shader abstraction**: Rendering state baked into cstat bit flags and palette lookups
- **No networking abstraction**: Multiplayer code directly modifies sprite state and sends deltas

**Idiomatic Practices:**
- Angle system (0–2047) is deeply baked in; functions assume this throughout
- Fixed-point math via precomputed tables is the norm
- Memory layout is explicit and hand-optimized (pragma pack)

## Potential Issues

1. **No bounds checking on array accesses**: Code uses sector[i], sprite[i] without validation that i < MAXSECTORS/MAXSPRITES. A corrupted map file or game bug can cause buffer overflows. Cross-references show ENGINE.C, BUILD.C assume arrays are valid.

2. **Global state mutation everywhere**: No transaction semantics or undo/redo mechanism at the data level. BUILD.C editor must manually track undo history.

3. **Fixed limits are hard limits**: If a map has >MAXWALLS walls, the engine silently fails or overwrites memory. No dynamic growth or reallocation.

4. **Sprite linked lists can become invalid**: If sprite removal (via deletesprite) is buggy, chain pointers can dangle. The editor and engine both assume chain invariants hold.

5. **Automapping bit-packing is implicit**: No bounds checking on show2dsector[] indexing; if a corrupt sprite index reaches the automapping code, it can write out-of-bounds.

---

**Deterministic nature**: This analysis is inferable from the struct definitions, global declarations, and the cross-reference evidence (e.g., ENGINE.C calls hitscan using sprite[] arrays; MULTI.C references sprite[].x/y/z for network sync). No speculative design choices are claimed here.
