# UTIL/EDITART.C

## File Purpose
Interactive tile and artwork editor for the Build engine. Allows editing, viewing, and managing tile graphics for Duke Nukem 3D, including palette management, animation configuration, and image capture from external files.

## Core Responsibilities
- Tile/artwork editing and pixel manipulation (drawing, filling, rotating, flipping)
- Loading and saving tile data from/to .ART files
- VGA graphics display and video mode control
- User interaction via keyboard and mouse
- Color palette management and lookup table generation
- Image format support (BMP, PCX, GIF) for importing artwork
- Tile browser/selector with zoom and tile swapping functionality
- Batch operations: tile insertion, deletion, resizing, metadata updates
- Map file synchronization when tiles are rearranged
- Screenshot/capture functionality to PCX files

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| sectortype | struct | Map sector with ceiling/floor texture and height properties |
| walltype | struct | Map wall segment with texture and properties |
| spritetype | struct | Map sprite entity with position and animation |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| pic | char* | static | Main tile graphics buffer (allocated dynamically, rest of memory) |
| buf | unsigned char[512K] | static | Working buffer for current tile being edited |
| buf2 | char* | static | Clipboard/temporary buffer for copy/paste operations |
| xdim, ydim | long | static | Dimensions of currently loaded tile |
| tilesizx, tilesizy | short[MAXTILES] | static | Lookup table of all tile widths/heights |
| waloff | long[MAXTILES] | static | Tile memory offsets within pic buffer |
| picanm | long[MAXTILES] | static | Animation/picture properties (type, frames, offsets) |
| names | char[MAXTILES][17] | static | Tile name strings |
| palette, palette2 | char[768] | static | Active and secondary color palettes (RGB triplets) |
| palookup | char[32][256] | static | Palette lookup tables for darkness/shade effects |
| picnum | long | static | Current tile number being edited |
| curtilefile | long | static | Index of currently active .ART file |
| totpicsiz, totpicmem | long | static | Total picture data used and available memory |
| mousx, mousy, bstatus | short | static | Mouse position and button status |
| totalclock | long | static | Timer counter for animation playback |
| xfillbuf, yfillbuf | short[4096] | static | Flood fill algorithm work buffers |
| textfont | char[128][8] | static | Font bitmap data for text rendering |
| blackmasklookup | char[256] | static | Transparency/masking lookup table |

## Key Functions / Methods

### main
- Signature: `main(short argc, char **argv)`
- Purpose: Entry point and primary event loop; handles all UI interaction and tile editing commands
- Inputs: Optional ART filename prefix argument
- Outputs/Return: 0 on clean exit
- Side effects: Initializes VGA mode 0x13, loads all data files, manages video state, modifies global tile and palette state
- Calls: `setvmode`, `loadtables`, `setupmouse`, `loadpics`, `loadwall`, `drawmainscreen`, `getch`, `kbhit`, `readmouse`, `savewall`, `savepics`, `savenames`, `updatemaps`, dozens of editing/rendering functions
- Notes: Monolithic ~2000-line state machine; integrates all keyboard commands (arrow keys, alphanumerics, function keys); mouse drag-drawing support

### loadpics
- Signature: `loadpics(long dapicnum)`
- Purpose: Load tile metadata and pixel data from .ART file containing specified tile
- Inputs: Tile number to load
- Outputs/Return: 0 success, -1 invalid version, 0 create empty file if none exists
- Side effects: Reads .ART file; updates tilesizx/tilesizy/picanm/waloff arrays; switches curtilefile
- Calls: `open`, `read`, `close`
- Notes: Manages multi-file tile sets (tiles000.art, tiles001.art, etc.); allocates pic buffer on first load

### savepics
- Signature: `savepics()`
- Purpose: Write modified tile data back to active .ART file
- Inputs: None (uses global state)
- Outputs/Return: 0 success, -1 write error
- Side effects: Writes .ART file with updated headers and pixel data
- Calls: `open`, `write`, `close`, `printmessage`
- Notes: Prompts user before saving if asksave flag set; rebuilds entire file

### loadwall / savewall
- Signature: `loadwall(char *bufptr, long wallnum)` / `savewall(char *bufptr, long wallnum)`
- Purpose: Transfer single tile between memory and working buffer
- Inputs: Buffer pointer, tile number
- Outputs/Return: 0 on success
- Side effects: loadwall copies tile pixels to buf; updates xdim/ydim/asksave; savewall prompts user and marks file dirty
- Calls: `clearbuf`, `updatepanning`, `resizetile`
- Notes: loadwall bounds-checks cursor position; savewall handles tile resize if dimensions changed

### showall
- Signature: `showall(char *bufptr)`
- Purpose: Render current tile to screen with status information (dimensions, animation type, name)
- Inputs: Buffer pointer
- Outputs/Return: 0
- Side effects: Clears text area; renders animation mode/frame count; calls copywalltoscreen
- Calls: `cleartopbox`, `cleartext`, `printext256`, `copywalltoscreen`

### copywalltoscreen
- Signature: `copywalltoscreen(char *bufptr, long dapicnum, char maskmode)`
- Purpose: Copy tile pixels to VGA video memory with planar mode writes and optional color 255 masking
- Inputs: Buffer, tile number, mask mode (0=normal, 1=color 255 is transparent)
- Outputs/Return: (void)
- Side effects: Direct VGA register I/O; writes to 0xa0000 video memory
- Notes: Uses 16-pixel-wide batch writes for performance; handles panning offsets and tile centering

### gettile
- Signature: `gettile(long tilenum)`
- Purpose: Interactive tile browser showing grid of tiles; allows tile selection, zoom, swap, insert, delete, and marked region operations
- Inputs: Current tile number
- Outputs/Return: Selected tile number, or original tile if cancelled
- Side effects: Switches display mode; manipulates tile ordering via `swapwalls`; toggles `picanm` flags
- Calls: `setvmode`, `drawtilescreen`, `drawxorbox`, `getch`, `kbhit`, `limitrate`, `reportmaps`, `swapwalls`, `resizetile`, `savepics`, `updatescript`, `open`, `read`, `close`
- Notes: Supports zoom levels (gettilezoom); space toggles tile registration flag or initiates swap; Alt-R shows tile usage; Alt-D deletes all registered tiles

### fillregion
- Signature: `fillregion(long x, long y, char col, char bound)`
- Purpose: Flood fill algorithm starting from (x,y); fills with col until hitting bound color
- Inputs: Starting coordinates, fill color, boundary color
- Outputs/Return: -1 if already at boundary, 0 otherwise
- Side effects: Modifies buf pixels; uses xfillbuf/yfillbuf work queues
- Notes: Implements scanline fill with 4-way connectivity

### loadbmp / loadpcx / loadgif
- Signature: `loadbmp/pcx/gif(char *filename)`
- Purpose: Load external image file to VGA video memory for tile capture
- Inputs: Filename
- Outputs/Return: 0 success, -1 file not found
- Side effects: Reads image file; writes to 0xa0000 video RAM; updates xres/yres; loads palette
- Calls: `open`, `read`, `close`, `outp`
- Notes: PCX uses RLE decompression; GIF uses LZW decompression with custom lookup tables

### resizetile
- Signature: `resizetile(long picnume, long oldx, long oldy, long newx, long newy)`
- Purpose: Allocate new memory for resized tile; move surrounding tile data to accommodate
- Inputs: Tile number, old dimensions, new dimensions
- Outputs/Return: 0 success, -1 out of memory
- Side effects: Modifies pic buffer memory; updates waloff offsets for all subsequent tiles; updates totpicsiz
- Notes: Uses reverse-iteration for size increases to avoid data corruption; handles both expansion and shrinkage

### swapwalls
- Signature: `swapwalls(long swapwall1, long swapwall2)`
- Purpose: Exchange tile data and all properties between two tile slots
- Inputs: Two tile numbers
- Outputs/Return: 1 if successful, 0 if same tile
- Side effects: Massive memory copy operations; swaps tilesizx/tilesizy/picanm/waloff/tilookup/names arrays; sets allasksave
- Calls: `outp`, `resizetile` (indirectly via memory operations)
- Notes: Temporarily uses buf as scratch; handles case where swap sizes differ

### updatemaps
- Signature: `updatemaps()`
- Purpose: Scan all .MAP files and update tile references using tilookup2 mapping (for when tiles are rearranged)
- Inputs: None (reads from disk)
- Outputs/Return: (void)
- Side effects: Updates all .MAP files; modifies sectortype/walltype/spritetype tile numbers
- Calls: `_dos_findfirst`, `_dos_findnext`, `open`, `read`, `write`, `close`, `lseek`, `printf`, `getch`
- Notes: Supports Build format (0x00000007) and 2Draw format (version 1); skips Polytex format (version 2)

### selectbox
- Signature: `selectbox(long *dax1, long *day1, long *dax2, long *day2)`
- Purpose: Interactive region selection tool for capturing image areas; allows moving and resizing rectangle with keyboard/mouse
- Inputs: Pointers to corner coordinates (0x80000000 = auto-center)
- Outputs/Return: 1 if confirmed, 0 if cancelled
- Side effects: Modifies coordinate parameters; renders XOR box to screen; may call `updatepalette`
- Calls: `outp`, `getch`, `kbhit`, `readmouse`, `drawxorbox`, `limitrate`, `printext256`, `updatepanningforumode`, `getpaletteconversion`, `getpalookup`
- Notes: Mouse or keyboard driven; supports palette swap (P key); space key enables color conversion

### captureit
- Signature: `captureit(long x1, long y1, long x2, long y2, long datilenum, char *dafilename, char capfilmode)`
- Purpose: Extract rectangle from loaded image and store as tile; optionally record operation in capfil.txt script
- Inputs: Bounding box, destination tile number, source filename, script recording flag
- Outputs/Return: (void)
- Side effects: Modifies buf/xdim/ydim; writes capfil.txt if mode=1; updates asksave
- Calls: `outp`, `open`, `read`, `write`, `close`, `lseek`, `sprintf`, `getpixel`, `eof`
- Notes: Auto-crops empty borders (color 255); applies palookupe color conversion

## Control Flow Notes

**Initialization**:
1. Parse arguments; construct .ART filename template
2. Set VGA mode 0x13 (320x200x256); configure panning
3. Load tables.dat (sine table, font), palette.dat, names.h
4. Scan for all .ART files; load metadata
5. Load first tile (picnum=0)
6. Initialize mouse
7. Display main screen

**Main Loop (in main)**:
- Poll keyboard: process single character commands (0-9, +/-, [], etc.) and extended keys (arrow, PgUp/PgDn, function keys, Alt+key)
- Poll mouse: track movement and draw with held button
- Handle modal dialogs: tile naming (N), size entry (S), goto (G), tile browser (V), palette swap (P key in selectbox)
- Call drawing/editing functions based on command
- Update display via showall
- Set asksave/allasksave flags on modifications

**Shutdown**:
1. Confirm quit (ESC twice)
2. Save modified tile and all tile files
3. Save tile names
4. Update all .MAP files if tiles rearranged
5. Return to text mode (0x3)

## External Dependencies
- **DOS/DPMI**: Interrupt vectors (int 0x8 timer, int 0x31 DPMI, int 0x10 video, int 0x33 mouse)
- **Watcom C Runtime**: Standard file I/O (open, read, write, close, lseek), memory (malloc), process (chdir, printf), directory scanning (_dos_findfirst/_dos_findnext)
- **VGA Hardware**: Sequencer (0x3c4/0x3c5), CRTC (0x3d4/0x3d5), attribute controller (0x3c0/0x3c1), graphics controller (0x3ce/0x3cf), DAC (0x3c8/0x3c9), status (0x3da)
- **Inline Assembly**: Custom pragma operations (`scale`, `mulscale`, `divscale`, `setvmode`, `readmouse`, `setupmouse`, `clearbuf`, `drawpixel`, etc.) via Watcom C
- **Build Engine Structures**: Data type definitions (sectortype, walltype, spritetype) for map file I/O; no runtime calls to Build code
