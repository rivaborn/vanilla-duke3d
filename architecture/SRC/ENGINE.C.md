# SRC/ENGINE.C

## File Purpose
Core rendering and spatial engine for the Build game engine. Implements a portal-based 3D renderer with sector/wall/sprite geometry, texture mapping, sprite rendering, collision detection, and palette/graphics management for DOS/VESA graphics.

## Core Responsibilities
- **3D Rendering Pipeline**: Portal-based visibility, wall/ceiling/floor/sprite drawing
- **Sector Geometry**: Recursive sector scanning, occlusion tracking via vertical clipping arrays
- **Texture Mapping**: Per-pixel texture lookup, perspective-correct mapping with fixed-point math
- **Sprite Rendering**: Billboard sprites, rotated sprites, masked (transparent) sprites with sorting
- **Collision Detection**: Hitscan (ray casting), clipmove (swept collision), getzrange (z-bounds queries)
- **Graphics Management**: Tile/art loading, palette lookups, voxel management, screen buffering
- **Input/Output**: Mouse setup, keyboard, VBE graphics mode setup, DOS interrupts

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `sectortype` | struct | Sector with ceiling/floor z, texture, palette, slope hints (from build.h) |
| `walltype` | struct | Wall segment with endpoints, portal link, texture, cstat flags (from build.h) |
| `spritetype` | struct | Actor/sprite with position, angle, tile, repeat, clip distance (from build.h) |
| `permfifotype` | struct | Persistent FIFO queue for delayed sprite/UI rendering across frames |
| `linetype` | struct | Axis-aligned line segment for polygon clipping |
| `VBE_vgaInfo`, `VBE_modeInfo` | struct | VBE BIOS graphics adapter info (from ves2.h) |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `globalposx`, `globalposy`, `globalposz` | long | global | Camera position (fixed-point) |
| `globalang`, `globalhoriz` | short/long | global | Camera angle (0-2047) and horizon center line |
| `sector[]`, `wall[]`, `sprite[]` | array | global | Map geometry and sprite arrays (from build.h) |
| `visualpage`, `activepage` | volatile long | global | Current display/render page (multi-buffering) |
| `xb1[], yb1[], xb2[], yb2[]` | short array | static | Screen-space bounds of wall segments (pixel x,y) |
| `umost[], dmost[]` | short array | global | Upper/lower screen occlusion bounds per x-column |
| `uplc[], dplc[]` | short array | global | Projected ceiling/floor clip bounds per x-column |
| `swall[], lwall[]` | long array | static | Texture u-coordinate and horizontal scale per x-pixel |
| `vplce[], vince[]` | long array | global | Vline texture v-coordinate and v-increment (per setup) |
| `palookupoffse[]`, `bufplce[]` | long array | global | Palette lookup offset and buffer base per vline setup |
| `palookup[]` | char* array | global | Palette lookup tables (256 entries × numpalookups) |
| `waloff[]` | long array | extern | Tile/art buffer memory offsets for each tile ID |
| `picanm[], picsiz[], tilefilenum[]` | long/short array | extern | Animation flags, tile dimensions, tile file indices |
| `totalclock` | volatile long | extern | 120 Hz master clock counter |
| `numbunches`, `smostwallcnt`, `maskwallcnt` | short | static | Portal/bunch count, masked wall/smost stack depth |
| `bunchfirst[], bunchlast[]` | short array | static | Portal wall range pointers for depth sorting |
| `permhead`, `permtail` | long | static | Persistent queue head/tail for multi-page sprite persistence |
| `frameplace` | long | extern | Current frame buffer base address |
| `globvis`, `globalshade`, `globalpal` | long | global | Visibility distance, shade level, palette number for rendering |
| `globalpicnum`, `globalorientation` | short/long | global | Current tile ID and texture orientation flags for rendering |
| `curbrightness`, `paletteloaded` | char/long | static | Brightness level, palette initialization state |

## Key Functions / Methods

### drawrooms
- **Signature:** `drawrooms(long daposx, long daposy, long daposz, short daang, long dahoriz, short dacursectnum)`
- **Purpose:** Main entry point; sets up camera state, visibility scaling, performs sector occlusion culling via scansector(), collects and sorts portals, renders walls and sprites
- **Inputs:** Camera position (x,y,z), angle, horizon line, starting sector
- **Outputs/Return:** None (renders to frameplace)
- **Side effects:** Modifies global camera state (globalpos*, globalang, globalhoriz), resets visibility tracking (umost/dmost, smostwallcnt, maskwallcnt), updates gotsector[] bitfield
- **Calls:** scansector(), bunchfront(), drawalls(), drawmasks(), getzsofslope(), updatesector()
- **Notes:** Sets stereomode handling for VR; validates kensmessage CRC as anti-cheat; initiates portal depth-sorting algorithm

### scansector
- **Signature:** `scansector(short sectnum)`
- **Purpose:** Recursively traverse portal graph; collect visible walls and sprites for a sector; track vertical occlusion; submit adjacent sectors for processing
- **Inputs:** Sector number
- **Outputs/Return:** None (populates global wall/sprite lists: xb1/xb2/yb1/yb2, numscans, spritesortcnt, bunchfirst/last)
- **Side effects:** Modifies gotsector[], numscans, spritesortcnt, bunchfirst[], bunchlast[], p2[]; updates sectorborder[] queue
- **Calls:** getzsofslope(), wallfront(), dmulscale6(), scale(), dmulscale32()
- **Notes:** Back-face culls walls; computes 2D projected bounds (xb1/xb2); skips portals already processed; connects wall chains via p2[]

### drawalls
- **Signature:** `drawalls(long bunch)`
- **Purpose:** Render walls and connected ceilings/floors for a portal bunch; handle masked walls and wall-to-sprite occlusion
- **Inputs:** Bunch index
- **Outputs/Return:** None (renders textured walls)
- **Side effects:** Modifies umost/dmost occlusion bounds, maskwall[] queue, smost[] occlusion stack, numhits
- **Calls:** wallmost(), ceilscan(), florscan(), grouscan(), prepwall(), wallscan(), getzsofslope(), maskwallscan(), transmaskwallscan()
- **Notes:** Handles 2-sided portals with height/slope checks; clips against adjacent sector heights; supports masked/one-way walls

### wallscan
- **Signature:** `wallscan(long x1, long x2, short *uwal, short *dwal, long *swal, long *lwal)`
- **Purpose:** Rasterize and texture-map wall quad from x1 to x2; read texture via u,v coordinates; apply palette lookup shading
- **Inputs:** x-range, vertical bounds arrays (uwal/dwal), texture u,v arrays (swal/lwal)
- **Outputs/Return:** None (writes to frameplace video memory)
- **Side effects:** Calls vlineasm1/vlineasm4, prevlineasm1, faketimerhandler()
- **Calls:** setgotpic(), loadtile(), setupvlineasm(), divscale12(), mulscale16(), getpalookup(), qinterpolatedown16()
- **Notes:** Unrolls 4-wide vline asm; handles x-alignment; skips transparent pixels; uses transluc[] for masked textures

### prepwall
- **Signature:** `prepwall(long z, walltype *wal)`
- **Purpose:** Compute per-scanline texture u-coordinates (lwall[]) and step-values (swall[]) for a wall quad via inverse perspective
- **Inputs:** Wall index z, wall pointer
- **Outputs/Return:** None (fills lwall[], swall[])
- **Side effects:** Modifies global lwall[], swall[]
- **Calls:** divscale12(), mulscale21(), mulscale18()
- **Notes:** Interpolates 4 pixels at a time; handles horizontal flipping via cstat&8

### ceilscan
- **Signature:** `ceilscan(long x1, long x2, long sectnum)`
- **Purpose:** Render ceiling texture (flat or parallax); set up per-pixel texture coordinates and shading
- **Inputs:** x-range, sector number
- **Outputs/Return:** None (renders)
- **Side effects:** Modifies globalx1/globalx2/globaly1/globaly2 texture basis vectors, calls hline() or slowhline() per scanline
- **Calls:** setpalookupaddress(), setgotpic(), loadtile(), sethlinesizes(), hline(), slowhline(), faketimerhandler()
- **Notes:** Handles orientation flags (4,10,20 bits = rotate/flip); parallax skies use pskyoff[] lookup; relative alignment mode transforms basis

### florscan
- **Signature:** `florscan(long x1, long x2, long sectnum)` 
- **Purpose:** Render floor texture; similar to ceilscan but for floor
- **Inputs:** x-range, sector number
- **Outputs/Return:** None (renders)
- **Side effects:** Same as ceilscan
- **Calls:** Same as ceilscan
- **Notes:** Back-face culls if player z > floorz; applies floorstat orientation

### drawsprite
- **Signature:** `drawsprite(long snum)`
- **Purpose:** Render a single sprite (billboard, wall-aligned, or floor-aligned); handle scaling, clipping, masked rendering
- **Inputs:** Sprite index in tspriteptr[] array
- **Outputs/Return:** None (renders to frameplace)
- **Side effects:** Modifies uwall/dwall occlusion buffers, transarea counter
- **Calls:** divscale19(), mulscale30(), mulscale14(), maskwallscan(), transmaskwallscan(), owallmost(), clippoly4(), ceilspritescan()
- **Notes:** Sprite cstat&48 selects face/wall/floor mode; cstat&2 = transparent; cstat&4/8 = x/y flip; handles yoffset and yrepeat

### getzrange
- **Signature:** `getzrange(long x, long y, long z, short sectnum, long *ceilz, long *ceilhit, long *florz, long *florhit, long walldist, unsigned long cliptype)`
- **Purpose:** Query ceiling/floor z-heights and hit objects at (x,y) location; used for collision and physics queries
- **Inputs:** Position, sector, clip distance, clip type flags
- **Outputs/Return:** None (fills ceilz/florz/ceilhit/florhit pointers)
- **Side effects:** Modifies ceilz, florz, ceilhit, florhit output parameters
- **Calls:** getzsofslope(), clipinsidebox(), clipinsideboxline(), nsqrtasm()
- **Notes:** Returns sector+16384 or sprite+49152 in hit pointers; clips against wall boundaries; checks 3 sprite cstat modes

### hitscan
- **Signature:** `hitscan(long xs, long ys, long zs, short sectnum, long vx, long vy, long vz, short *hitsect, short *hitwall, short *hitsprite, long *hitx, long *hity, long *hitz, unsigned long cliptype)`
- **Purpose:** Cast ray from (xs,ys,zs) in direction (vx,vy,vz); find first hit against walls/sprites; used for weapon traces
- **Inputs:** Ray origin, sector, direction vector, clip type
- **Outputs/Return:** -1 on success (fills hit* pointers)
- **Side effects:** Modifies hitsect, hitwall, hitsprite, hitx/y/z
- **Calls:** rintersect(), inside(), getzsofslope()
- **Notes:** Supports 3 sprite cstat modes; checks sloped ceilings/floors; clips against wall heights

### clipmove
- **Signature:** `clipmove(long *x, long *y, long *z, short *sectnum, long xvect, long yvect, long walldist, long ceildist, long flordist, unsigned long cliptype)`
- **Purpose:** Move (x,y) by velocity vector with collision; slide along walls; update sector; return collision object ID
- **Inputs:** Position pointer, sector pointer, velocity, clip distances, clip type
- **Outputs/Return:** Object ID (wall+32768, sprite+49152) or 0 if no collision (modifies x/y/z/sectnum in-place)
- **Side effects:** Updates *x, *y, *z, *sectnum
- **Calls:** clipinsidebox(), clipinsideboxline(), raytrace(), keepaway(), updatesector()
- **Notes:** Multi-iteration ray tracing; handles 3 sprite cstat modes; iterates up to clipmoveboxtracenum times

### loadtile
- **Signature:** `loadtile(short tilenume)`
- **Purpose:** Load tile art from disk into waloff[] cache; handle tile file switching
- **Inputs:** Tile number
- **Outputs/Return:** None (loads into cache)
- **Side effects:** Modifies artfil, artfilnum, artfilplc; allocates cache via allocache()
- **Calls:** kopen4load(), klseek(), kread(), allocache(), faketimerhandler()
- **Notes:** Lazy-loads tiles; caches file handle; supports multiple tile files

### initengine
- **Signature:** `initengine()`
- **Purpose:** One-time engine setup: initialize lookup tables, load palettes and voxels, reset sprite lists, set initial visibility
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:** Initializes sintable[], reciptable[], lowrecip[], voxoff[][], palookup[], all global state
- **Calls:** loadtables(), loadpalette(), initspritelists(), clearbuf(), setgotpic()
- **Notes:** Called once at startup

### rotatesprite
- **Signature:** `rotatesprite(long sx, long sy, long z, short a, short picnum, signed char dashade, char dapalnum, char dastat, long cx1, long cy1, long cx2, long cy2)`
- **Purpose:** Queue or immediately draw a rotated/scaled 2D sprite to screen; used for UI overlays
- **Inputs:** Screen position, zoom, angle, tile, shade, palette, flags, clip rect
- **Outputs/Return:** None (draws or queues)
- **Side effects:** Adds to permfifo[] queue if dastat&128; modifies permhead/permtail
- **Calls:** dorotatesprite()
- **Notes:** dastat bit 64 = non-masking; bit 128 = queue for persistence; handles aspect/window scaling

### dorotatesprite
- **Signature:** `dorotatesprite(long sx, long sy, long z, short a, short picnum, signed char dashade, char dapalnum, char dastat, long cx1, long cy1, long cx2, long cy2)`
- **Purpose:** Implementation of rotatesprite; compute rotation matrix, clip polygon, rasterize
- **Inputs:** Same as rotatesprite
- **Outputs/Return:** None
- **Side effects:** Calls setupvlineasm/setupmvlineasm, hlineasm4/vlineasm4
- **Calls:** clippoly4(), qinterpolatedown16(), hlineasm4(), vlineasm4(), msethlineshift(), tsethlineshift()
- **Notes:** Unrolled 4-wide vline asm; supports translucency (dastat&1); handles aspect scaling (dastat&2)

### hitsan / neartag / inside / updatesector
Various spatial queries and point-in-sector tests (see Notes section above)

## Control Flow Notes

**Initialization Phase:**
- initengine() loads tables, palettes, voxels, initializes all global state once

**Per-Frame Rendering:**
1. drawrooms(camera_x, camera_y, camera_z, angle, horiz, sectnum) — main entry
2. scansector(initial_sector) — recursively collect visible geometry via portal traversal
3. Sort portals by depth (bunchfront algorithm)
4. For each portal (nearest to farthest):
   - drawalls(bunch_index) — render walls, ceilings, floors
   - Clip vertices into occlusion arrays (umost/dmost)
5. drawmasks() — sort and render sprites, interleave with masked walls
6. nextpage() — page flip and buffer management

**Physics Queries (called by game logic, not renderer):**
- getzrange() — query sector z-bounds (for gravity, collision)
- clipmove() — swept collision with sliding
- hitscan() — ray casting (weapon traces, AI sight)
- updatesector() — find sector containing point

**Graphics Setup:**
- setgamemode() — set video mode, allocate screen buffer
- loadpalette() — load palette tables and color lookup
- rotatesprite() — queue UI overlays for nextpage()

**Rendering uses fixed-point (<<8 / >>8 shifts) and extensive asm intrinsics for performance.**

## External Dependencies
- **build.h**: sectortype, walltype, spritetype, extern arrays (sector, wall, sprite, sintable, palette, etc.)
- **pragmas.h**: Fixed-point math intrinsics (mulscale*, dmulscale*, divscale*, asm1/asm2/asm3/asm4 globals)
- **ves2.h**: VBE graphics adapter support, DOS DPMI int386 interface, screen/palette functions
- **DOS/x86**: int386()/int386x() for DOS interrupts; _enable()/_disable() for IRQs; FP_OFF/FP_SEG macros
- **External functions** (defined elsewhere): setupvlineasm(), vlineasm1(), vlineasm4(), hlineasm4(), prevlineasm1(), etc. (asm module), setpalookupaddress(), setuphlineasm4(), etc. (graphics module), getpalookup(), getzsofslope(), animateoffs(), etc. (core module)
