# UTIL/WAD2MAP.C

## File Purpose
Doom WAD to Build engine map converter. Reads Doom IWAD/PWAD files, extracts map geometry (sectors, walls, vertices, things), converts to Build engine format, applies optional script-based customizations, and outputs a .map file.

## Core Responsibilities
- Parse command-line arguments for IWAD, PWAD, map name, and optional conversion script
- Load and index WAD lumps (TEXTURE1, TEXTURE2, PNAMES, map data)
- Extract Doom map components (vertices, linedefs, sidedefs, sectors, things)
- Convert Doom map geometry to Build engine spatial representation
- Build sector-wall adjacency and connectivity
- Map Doom sprite types and textures to Build engine equivalents via lookup tables
- Parse optional script for custom field assignments and overrides
- Write binary Build .map output file

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `linedeftype` | struct | Doom linedef: connects two vertices, references sidedefs, special/tag |
| `sidedeftype` | struct | Doom sidedef: textures and sector assignment for one side of a wall |
| `secttype` | struct | Doom sector: floor/ceiling pics, heights, shade, type, tag |
| `thingtype` | struct | Doom thing (entity): position, angle, type (enemy/item/spawn), options |
| `sectortype` | struct | Build engine sector: walls, ceiling/floor heights, pics, shading |
| `walltype` | struct | Build engine wall: position, link to next wall, sector, textures, cstat |
| `spritetype` | struct | Build engine sprite: position, sector, picture, angle, velocity, tags |
| `thinglisttype` | struct | Sprite type mapping: Doom thing ID → Build sprite name |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `iwadata[]`, `pwadata[]` | char[MAXWADS][9] | static | WAD lump names (IWAD/PWAD) |
| `iwadplc[]`, `iwadlen[]` | long[] | static | Lump offsets and sizes in IWAD |
| `pwadplc[]`, `pwadlen[]` | long[] | static | Lump offsets and sizes in PWAD |
| `sector[]` | sectortype[] | static | Build engine sectors (MAXSECTORS) |
| `wall[]` | walltype[] | static | Build engine walls (MAXWALLS) |
| `sprite[]` | spritetype[] | static | Build engine sprites (MAXSPRITES) |
| `line[]`, `side[]`, `sect[]`, `thing[]` | linedeftype[], sidedeftype[], secttype[], thingtype[] | static | Doom map data arrays |
| `px[]`, `py[]` | short[] | static | Doom vertex coordinates |
| `sqrtable[]` | unsigned short[2048] | static | Integer square root lookup table |
| `thinglookup[]` | short[MAXTHINGTYPES] | static | Maps Doom thing type → Build sprite picnum |
| `texturelookup[]` | short[4096] | static | Maps Doom texture index → Build texture index |
| `sectspri[][]` | short[MAXSECTS][8] | static | Per-sector sprite slots for tag-based entities |
| Script state variables | Various | static | `definemode`, `thingtypemode`, `texturelookupmode`, `tagtypemode`, `sectypemode` and associated arrays |

## Key Functions / Methods

### main
- **Signature:** `main(short argc, char **argv)`
- **Purpose:** Entry point; orchestrates entire WAD-to-MAP conversion pipeline.
- **Inputs:** Command-line arguments: `(PWAD) IWAD MapName [ScriptName]`
- **Outputs/Return:** Exits with status 0 on success; writes .map file to disk.
- **Side effects:** Opens/closes files, allocates/fills global sector/wall/sprite arrays, calls `parsescript()`.
- **Calls:** `open()`, `read()`, `lseek()`, `close()`, `initksqrt()`, `parsescript()`, `getwadindex()`, `inside()`, `getspritefield()`, `setspritefield()`, `getsectorfield()`, `setsectorfield()`, `getwallfield()`, `setwallfield()`, `ksqrtasm()`, `mulscale10()`, `write()`
- **Notes:** Handles both single-file (IWAD only) and two-file (PWAD + IWAD) configurations. Converts Doom linedefs/sidedefs to Build walls via sector-wise wall collection and point2 linking. Applies texture lookup and script-defined overrides.

### parsescript
- **Signature:** `parsescript()`
- **Purpose:** Parses optional conversion script (.txt) with sections for `#define`, `[THINGTYPES]`, `[TEXTURELOOKUPS]`, `[TAGCONVERSIONS]`, `[SECTORCONVERSIONS]` to customize map properties.
- **Inputs:** Reads from `scriptname` file (global).
- **Outputs/Return:** Populates global lookup/override tables (`thinglookup`, `texturelookup`, `thingfield[]`, `thingop[]`, `thingval[]`, etc.).
- **Side effects:** Opens/closes script file, modifies global parsing state variables.
- **Calls:** `open()`, `readline()`, `readbyte()`, `atol()`, `stricmp()`, `close()`, `clearbufbyte()`
- **Notes:** Comma-separated format; ignores comments (`;`). Supports range syntax (`1-5`). Field operations: `=`, `+=`, `-=`, `|=`, `&=`, `^=`. Encodes sprite/wall/sector field indices and operations for bulk customization at sprite creation.

### inside
- **Signature:** `inside(long x, long y, short sectnum)`
- **Purpose:** Ray-cast point-in-polygon test to determine if (x,y) is inside a sector.
- **Inputs:** Point coordinates (x, y) and sector index.
- **Outputs/Return:** Non-zero if inside, 0 if outside.
- **Side effects:** None.
- **Calls:** Uses global `sector[]` and `wall[]` arrays.
- **Notes:** Cross-product parity logic; used to locate sprite sectors during sprite-position fixup.

### initksqrt
- **Signature:** `initksqrt()`
- **Purpose:** Precompute fixed-point square root table for fast approximation.
- **Inputs:** None.
- **Outputs/Return:** Fills `sqrtable[]`.
- **Side effects:** Modifies `sqrtable[]`.
- **Calls:** `klabs()`
- **Notes:** Newton–Raphson iteration with rounding; output is 10-bit fixed-point.

### getwadindex
- **Signature:** `getwadindex(char *nam)`
- **Purpose:** Binary search for WAD lump by name in pre-sorted IWAD index.
- **Inputs:** Lump name (8-char null-padded string).
- **Outputs/Return:** Lump index in `slist[]` array, or -1 if not found.
- **Side effects:** None.
- **Calls:** `stricmp()`
- **Notes:** Assumes `slist[]` is pre-sorted; used for O(log n) texture/sprite type lookups.

### readline, readbyte
- **Signature:** `readline()`, `readbyte()`
- **Purpose:** Stream-based script line reading; handles comment stripping and whitespace normalization.
- **Inputs:** `readbyte()` reads from open file; `readline()` assembles lines.
- **Outputs/Return:** `readbyte()` returns char or -1; `readline()` returns line length or 0 on EOF.
- **Side effects:** Updates `filpos` file position pointer.
- **Calls:** `read()`
- **Notes:** Replaces spaces/tabs with commas; skips trailing commas; semicolon starts comment.

### Sprite/Wall/Sector field accessors
- **Signature:** `getspritefield(long i, long fieldnum)`, `setspritefield(long i, long fieldnum, long newval)` (and wall/sector variants)
- **Purpose:** Generic field getter/setter for script-driven customization without hardcoded field names.
- **Inputs:** Sprite/wall/sector index, field enum (0–21 for sprite, 64–80 for wall, 32–53 for sector), value.
- **Outputs/Return:** Field value or unit for assignment.
- **Side effects:** Modifies global sprite/wall/sector array element.
- **Calls:** None.
- **Notes:** Large switch statements; field IDs match script parser expectations. Enables dynamic field updates from script rules.

## Control Flow Notes

**Initialization phase:** Load IWAD/PWAD tables, sort by lump name, parse optional script.

**Geometry conversion phase:** Iterate sectors; for each, collect linedefs whose sidedefs reference it, order walls by connectivity (point2 chaining), populate Build `sector[].wallptr` and `wallnum`.

**Coordinate/texture assignment phase:** Convert vertex coords from Doom (x,y) to Build (scaled/centered), lookup texture picnums, assign wall repeat/panning from sidedef offsets.

**Entity phase:** Convert Doom things to Build sprites; apply script-defined sprite field overrides; create tag-based synthetic sprites for line/sector specials; locate player spawn point (thing type 1) for map header.

**Output phase:** Write .map binary file with header (mapversion, player pos/angle/sector), sectors array, walls array, sprites array.

## External Dependencies

- **File I/O:** `open()`, `read()`, `write()`, `lseek()`, `close()`, `filelength()` (DOS/Watcom C)
- **String:** `stricmp()`, `strcpy()`, `strcat()`, `strchr()`, `atol()`
- **Memory:** `clearbufbyte()` (macro), `FP_OFF` (far pointer offset, DOS)
- **Math:** `klabs()`, `mulscale10()`, `ksqrtasm()` (inline ASM), `ksgn()`, `min()`, `max()`
- **Pragmas:** `#pragma aux` for inline ASM; `pragmas.h` defines build macros.
- **Includes:** `<fcntl.h>`, `<io.h>`, `<dos.h>`, `<sys/types.h>`, `<sys/stat.h>`, `<string.h>`
- **Defined elsewhere:** `clearbufbyte()`, `ksqrtasm()`, `mulscale10()`, `klabs()`, `ksgn()` (likely in pragmas.h or linker).
