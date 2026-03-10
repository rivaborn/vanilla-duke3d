# UTIL/BACKMAP6.C — Enhanced Analysis

## Architectural Role

BACKMAP6.C is a standalone format-migration utility within the **Map Format Converters** subsystem, implementing the v7→v6 backward path. While parallel converters (CONVMAP5→6, CONVMAP6→7) exist, BACKMAP6 serves developer workflows that need rollback capability—essential when testing new format features or recovering legacy maps. Unlike the runtime engine (which operates on a single fixed format), these converters form a bidirectional version control system where each utility embeds its own format-specific struct definitions, avoiding shared schema dependencies that would create maintenance coupling.

## Key Cross-References

### Incoming (who depends on this file)
- **No callers from engine/game code.** BACKMAP6 is a standalone CLI utility; its `main()` is an independent entry point (not called by BUILD.C, ENGINE.C, or any subsystem).
- The function patterns (`convmap`, `loadoldboard`, `savenewboard`, `getfilenames`, `sortfilenames`) are replicated across BACKMAP5, CONVMAP5, CONVMAP6, CONVMAP7 as per the cross-reference index—indicating deliberate code cloning rather than shared library functions.

### Outgoing (what this file depends on)
- **DOS file I/O** (low-level): `open()`, `read()`, `write()`, `close()` — called from `loadoldboard()` and `savenewboard()` with binary flags (`O_BINARY`, `O_TRUNC`, `O_RDWR`).
- **DOS file enumeration** (legacy API): `_dos_findfirst()`, `_dos_findnext()` — used by `getfilenames()` for wildcard expansion (`.` and `..` filtering in loop).
- **Standard string/mem** (libc): `strcpy()`, `strcmp()`, `memcpy()`, `strcat()`, `strchr()`, `printf()`, `exit()`.
- **No dependencies** on engine subsystems (CACHE1D, ENGINE, MULTI, KDMENG); format conversion is hermetic.

## Design Patterns & Rationale

**Struct Packing & Field Mirroring:**
- `#pragma pack(push,1)` / `#pragma pack(pop)` enforces byte-aligned binary layout, essential for loading raw on-disk binary formats into C structs without gaps.
- Dual struct definitions (`sectortype` v7 vs. `newsectortype` v6) allow explicit, side-by-side layout comparison—critical for human auditing of format changes. This is safer than a single struct with version fields.

**Manual Field-by-Field Transformation:**
- Conversion loops copy each field individually (e.g., `newsector[i].ceilingheinum = (((long)sector[i].ceilingheinum)>>5)`), not via `memcpy()`. This enables field-specific logic: height values are right-shifted 5 bits (presumably moving from 11-bit to 6-bit representation), while most others copy as-is.
- **Conditional cstat updates** (`if (newsector[i].ceilingheinum == 0) newsector[i].ceilingstat &= ~2`) show that derived fields are recomputed during migration—a pattern for schema upgrades.

**Batch Enumeration + Alphabetic Sort:**
- `getfilenames()` expands wildcards; `sortfilenames()` (bubble sort) alphabetizes the result. Deterministic ordering aids reproducibility in batch workflows.
- File type is encoded in `menuname[i][16]`—a loose appending pattern common in 1990s utilities before structured metadata was routine.

**Static Global Arrays (no dynamic allocation):**
- Compile-time limits (MAXSECTORS=1024, MAXWALLS=8192, MAXSPRITES=4096) pre-allocate dual struct arrays, avoiding malloc overhead in a simple CLI tool. This is practical for a one-shot utility.

## Data Flow Through This File

**Phase 1: Discovery**
1. User: `BACKMAP6.EXE *.map`
2. `main()` → `getfilenames("*.map")` scans filesystem, populates `menuname[]`, increments `menunamecnt`.
3. `sortfilenames()` reorders `menuname[]` alphabetically in-place.
4. If `menunamecnt == 0`, exit with "File not found" message.

**Phase 2: Conversion Loop**
For each matched filename:
5. `convmap(filename)`:
   - Appends `.map` extension if missing.
   - `loadoldboard()` → `open()` → `read()` (binary v7 format: 4-byte version tag, 10-byte player state, entity counts + arrays).
   - Validates `mapversion == NEWMAPVERSION+1` (i.e., v7). Return `-2` if mismatch; `-1` if file not found.
   - Populate global `sector[MAXSECTORS]`, `wall[MAXWALLS]`, `sprite[MAXSPRITES]` (v7 format).

**Phase 3: Transformation**
6. Three nested loops:
   - **Sectors:** Copy fields, right-shift `ceilingheinum` and `floorheinum` by 5 bits, conditionally clear cstat bit 1 if height is 0.
   - **Walls:** Straight copy (no field modifications).
   - **Sprites:** Straight copy.
   - Populate `newsector[]`, `newwall[]`, `newsprite[]` (v6 format).

**Phase 4: Write-Back**
7. `savenewboard()` → `open(O_BINARY|O_TRUNC|O_CREAT|O_WRONLY)` → `write()` (v6 binary layout) → `close()`.
8. Print success/failure to stdout.

## Learning Notes

**Era-Specific Architecture Decisions:**
- **No abstraction layer:** Direct binary struct I/O with `#pragma pack` and manual copying. Modern engines (Unreal, Unity) use versioned serialization frameworks or text-based formats (JSON).
- **Tight binary formats:** Version 6 and 7 differ in field sizes (e.g., height heinum bits), implying disk-space optimization was a design goal in the 1990s.
- **Cloned conversion code:** BACKMAP5, BACKMAP6, CONVMAP5, CONVMAP6, CONVMAP7 are largely copy-paste utilities, not a shared migration framework. This reduces coupling but increases maintenance burden.
- **No transaction semantics:** File is overwritten in-place; no rollback if conversion crashes midway. A modern tool would write to a temp file, validate, then atomic-rename.

**What Modern Engines Do Differently:**
- Versioned plugin architecture (Unreal: `FArchive` with version IDs embedded in binary).
- Automated field remapping (reflection-based or codegen).
- Bidirectional serialization (JSON load/save for human inspection).
- Incremental schema migration (run N-1 to N converter, not N+1 to N).

**Port Concepts to Current Codebase:**
- The **dual-struct pattern** (old format + new format) is idiomatic here and should be replicated consistently across all converters.
- The **field-by-field loop** approach makes format changes auditable: changes to height representation are explicit transformations, not implicit struct layout differences.

## Potential Issues

1. **Unsafe File I/O:**
   - `read()` calls do not check return values. If a file is truncated or unreadable, `numsectors`, `numwalls`, `numsprites` will reflect stale values, corrupting conversion.
   - No bounds check on `numsectors * sizeof(sectortype)`: if a malformed file claims 5000 sectors, `read()` will overflow the static array.

2. **Buffer Overflow in getfilenames:**
   - `menuname[menunamecnt][16] = type` writes to offset 16 of a 32-byte array. While this doesn't overflow, it co-opts field 16 for metadata, which is fragile if the struct layout ever changes.

3. **Lost Data on Interruption:**
   - `savenewboard()` uses `O_TRUNC`, discarding the original immediately. If the process dies or disk fills during `write()`, no backup exists.

4. **No Validation of Conversion:**
   - After `savenewboard()` succeeds, no sanity check (e.g., re-read and validate entity counts match) is performed.

---

**Cross-Cutting Insight:** BACKMAP6 is a **hermetic, stateless utility**—it does not integrate with the runtime engine, does not share memory with other subsystems, and does not persist state beyond stdout. This isolation makes it robust for batch processing but also means format bugs found at runtime (in BUILD.C or ENGINE.C) cannot be automatically fixed retroactively; backward converters must be manually maintained in parallel with forward ones.
