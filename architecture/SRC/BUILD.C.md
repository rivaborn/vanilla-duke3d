# SRC/BUILD.C

## File Purpose
Interactive map editor for the Build Engine, providing both 3D first-person editing mode and 2D overhead editor view. Manages user input, UI interactions, geometry editing, and file I/O for level design.

## Core Responsibilities
- Main application loop and mode switching (3D vs. 2D editor)
- 3D mode: camera control, in-world sprite/sector/wall editing with visual feedback
- 2D mode: overhead map view with wall/sector manipulation, grid snapping, sector highlighting
- Input handling: keyboard, mouse, and interrupt-driven input with buffering
- Tile/texture browser UI with search and zoom functionality
- Map file operations: load, save, and "save as" with file browsing
- Property display and editing for sectors, walls, and sprites via UI dialogs
- Geometry operations: sector splitting/joining, wall insertion/deletion, point snapping
- Lighting/shading adjustments for map elements

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| sectortype | struct | Sector data (from build.h): walls, floor/ceiling z, shading, textures |
| walltype | struct | Wall data (from build.h): coordinates, adjacent sectors, cstat flags |
| spritetype | struct | Sprite data (from build.h): position, angle, repeat, palette |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| keystatus[256] | char[] | global | Key press state for all 256 scan codes |
| keyfifo[KEYFIFOSIZ] | char[] | global | Buffered keyboard input from interrupt handler |
| posx, posy, posz | long | global | Editor camera position in map coordinates |
| ang, horiz | short/long | global | Editor camera angle and vertical view angle |
| vel, svel, angvel | long | global | Current movement/rotation velocities (frame-based) |
| zoom | long | global | 2D overhead view zoom factor (14-bit scale) |
| grid, gridlock | short | global | Grid spacing (0-6) and lock-to-grid toggle |
| showtags | short | global | Display sector/wall/sprite tags in 2D view |
| cursectnum | short | global | Current sector containing editor position |
| numsectors, numwalls, numsprites | short | global | Current map dimensions |
| sector[], wall[], sprite[] | array | global | Map data arrays (from build.h) |
| crctable[256] | long[] | static | CRC-16 lookup table for signature verification |
| kensig[24] | char[] | static | "BUILD by Ken Silverman" signature string |
| highlightsector[], highlight[] | array | static | Arrays tracking selected sectors/walls for batch operations |
| show2dwall[], show2dsprite[] | char[] | global | Bitmaps for automapping (which walls/sprites are revealed) |
| totalclock | long | global (extern) | Master timer incremented 120 times/sec |
| tempbuf[4096] | char[] | static | General-purpose I/O buffer |

## Key Functions / Methods

### main
- Signature: `main(short int argc, char **argv)`
- Purpose: Entry point; initializes editor, loads resources, runs main game loop
- Inputs: Command-line arguments (optional map filename)
- Outputs: Returns 0 on success; prints final memory status before exit
- Side effects: Initializes keyboard/timer handlers, loads tile art and names, enters interactive loop
- Calls: `ExtInit()`, `initkeys()`, `inittimer()`, `loadpics()`, `loadnames()`, `setgamemode()`, `drawrooms()`, `drawmasks()`, `nextpage()`, `ExtLoadMap()`, `saveboard()`, `ExtSaveMap()`, `uninitkeys()`, `uninittimer()`, `uninitengine()`
- Notes: Loads boardfilename from argv[1] or defaults to "newboard.map"; initializes extra field to -1 for all sectors/walls/sprites; toggles between 3D and 2D editor with Enter key; prompts to save on ESC

### editinput
- Signature: `editinput()`
- Purpose: Handles all 3D mode keyboard/mouse input: camera movement, property editing, sprite placement, shading adjustments
- Inputs: Global keystatus[] array, mouse position/button status, searchx/searchy (2D screen coords for picking)
- Outputs: Modifies global state: posx/posy/posz, ang, sector/wall/sprite properties, asksave flag
- Side effects: Updates brightness, captures screenshots, modifies sprite/wall/sector cstat, shade, pal, texture; manages temp buffers for copy/paste (somethingintab)
- Calls: `getmousevalues()`, `showmouse()`, `clipmove()`, `getzrange()`, `gettile()`, `hitscan()`, `changespritesect()`, `AutoAlignWalls()`, `ExtCheckKeys()`, `ExtShowSectorData()`, `ExtEditSectorData()`, `ExtEditWallData()`, etc.
- Notes: Uses keystatus[] table indexed by scan codes (0x3b–0xd3); interprets Ctrl/Alt/Shift modifiers for variant actions; updates sector visibility, wall blocking flags, sprite cstat; calls external ExtXxx functions for display/edit dialogs

### overheadeditor
- Signature: `overheadeditor()`
- Purpose: 2D overhead map editor; handles all editing in top-down view with wall/sector/sprite manipulation
- Inputs: Global posx/posy/ang/cursectnum, keystatus[], mouse input, highlightsectorcnt/highlight arrays
- Outputs: Modifies sector/wall/sprite geometry, selection state, UI messages
- Side effects: Major structural changes—inserts/deletes walls/points, splits sectors, joins sectors, duplicates sectors; manages newnumwalls construction state for partial sectors being drawn
- Calls: `getmousevalues()`, `getpoint()`, `getlinehighlight()`, `getpointhighlight()`, `draw2dscreen()`, `draw2dgrid()`, `drawline16()`, `fillsector()`, `insertpoint()`, `deletepoint()`, `deletesector()`, `clockdir()`, `flipwalls()`, `fixspritesectors()`, `menuselect()`, `loadboard()`, `saveboard()`, `menuname[]` access, etc.
- Notes: Large state machine with mode variables (newnumwalls, sectorhighlightstat, circlewall); handles drag operations, point snapping, and grid-locking; sector drawing mode accumulates points until closed; uses keystatus array for continuous key checks

### gettile
- Signature: `gettile(long tilenum)`
- Purpose: Interactive tile/texture picker UI—displays grid of tiles with zoom, search, goto-by-number input
- Inputs: tilenum (initial/fallback tile), global searchstat (determines which tiles to show), keystatus[]
- Outputs: Returns selected tile number; updates localartfreq/localartlookup based on usage frequency
- Side effects: Modifies keystatus[] entries; changes display state via drawtilescreen()
- Calls: `clearbuf()`, `drawtilescreen()`, `limitrate()`, `nextpage()`, `printtext256()`, `sprintf()`
- Notes: Uses localartfreq[] to sort tiles by usage (shell sort algorithm); supports V key to filter by usage; G key to goto numeric tile; zoom with * and / (keypad); returns otilenum on ESC, selected tile on Enter

### drawtilescreen
- Signature: `drawtilescreen(long pictopleft, long picbox)`
- Purpose: Renders tile picker UI—grid of tiles with frequency counts, selection box, tile name
- Inputs: pictopleft (scroll offset), picbox (selected tile index)
- Outputs: None
- Side effects: Draws to video memory (frameplace-based); loads tiles via loadtile() if not cached
- Calls: `clearview()`, `loadtile()`, `ylookup[]`, `plotpixel()`, `printext256()`, `sprintf()`
- Notes: Downsamples large tiles to fit 64×64 display cells; shows frequency counts in localartfreq[] if filtered view active

### overheadeditor / Sector Splitting (local logic)
- Purpose: Implement sector splitting when drawing a line through an existing sector boundary
- Key operations: Copies sector attributes to new sectors; rebuilds wall pointer chains; handles inner/outer loops; maintains sprite associations
- Notes: Complex nested loop logic with danumwalls tracking new wall count; uses loopnumofsector() and loopinside() to classify inner loops; reconstructs nextwall/nextsector pointers post-split

### keyhandler
- Signature: `void __interrupt __far keyhandler(void)`
- Purpose: Low-level keyboard interrupt handler (IRQ 9); captures raw scan codes and populates keystatus[] and keyfifo[]
- Inputs: Hardware keyboard port (0x60), status port (0x61)
- Outputs: Updates keystatus[256] and keyfifo[] atomically
- Side effects: Manages extended key flag (for E0/E1 sequences); sends EOI to PIC; disables/enables interrupts
- Calls: `kinp()`, `koutp()`, `_disable()`, `_enable()`
- Notes: oldreadch/readch/readch comparison filters key-repeat; handles extended keys; keystatus array indexed by scan code + extended flag (max 255)

### timerhandler
- Signature: `void __interrupt __far timerhandler(void)`
- Purpose: Timer interrupt handler (IRQ 8, 120 Hz); increments totalclock and calls keytimerstuff()
- Inputs: None (called by hardware timer)
- Outputs: Increments globalvoltotalclock
- Side effects: Updates velocity decay (vel/svel/angvel decelerate gradually); modifies keystatus[] for held keys
- Calls: `keytimerstuff()`, `outp()` (send EOI)
- Notes: Runs at 120 ticks/sec; must complete quickly to avoid missed ticks

### keytimerstuff
- Signature: `keytimerstuff()`
- Purpose: Update movement/rotation velocities based on held keys; apply friction/deceleration
- Inputs: Global keystatus[], buildkeys[] (9 key indices for movement)
- Outputs: Modifies vel, svel, angvel
- Side effects: Increments/decrements velocities by fixed amounts; applies decay when key released
- Calls: None
- Notes: Called from timerhandler at 120 Hz; buildkeys[0-1] = forward/back, [2-3] = turn L/R, [4] = shift (doubled speed), [5] = modifier, [12-13] = strafe L/R

### insertpoint / deletepoint / movewalls
- Purpose: Manage wall array mutations (inserting/deleting walls and updating all pointers)
- Notes: deletepoint() updates sector.wallnum; movewalls() shifts nextwall/point2 references; updatedsector pointers incremented for sectors after insertion; paired operations on red-line (two-sided walls) to maintain consistency

### checksectorpointer
- Signature: `checksectorpointer(short i, short sectnum)`
- Purpose: Rebuild wall[i].nextsector/nextwall by scanning all sectors for matching opposite wall
- Inputs: Wall index i, containing sector index
- Outputs: Sets wall[i].nextsector and wall[i].nextwall; updates corresponding opposite wall
- Side effects: Full O(n²) scan of all sectors/walls; modifies wall[] entries
- Notes: Called after geometry changes; handles case where two walls share same endpoints but different direction

### fixrepeats
- Signature: `fixrepeats(short i)`
- Purpose: Recalculate wall[i].xrepeat to match actual wall length and maintain texture scale
- Inputs: Wall index i
- Outputs: Sets wall[i].xrepeat = distance
- Side effects: None
- Notes: ksqrt(dx²+dy²) / mulscale10() for accurate texture repeat on stretched walls

### clockdir
- Signature: `clockdir(short wallstart)`
- Purpose: Determine if a sector's wall loop is clockwise (0) or counter-clockwise (1)
- Inputs: wallstart (index of any wall in the loop)
- Outputs: Returns 0 (CW) or 1 (CCW)
- Side effects: None
- Notes: Finds leftmost wall (minimum x) and checks cross-product; flipped sectors need flipwalls()

### whitelinescan
- Signature: `whitelinescan(short dalinehighlight)`
- Purpose: Extract inner loop formed by one-way walls (red lines) and create new sector from them
- Inputs: Red line wall index
- Outputs: Creates new sector[numsectors]; returns newnumwalls (new wall count)
- Side effects: Allocates sector and walls; links walls with nextwall/nextsector
- Notes: Used for "inner loop made into new sector" operation

### getnumber16 / getnumber256
- Purpose: Modal UI for entering numbers (typed digit-by-digit, backspace to undo)
- Notes: getnumber256() renders 3D view continuously; getnumber16() updates status bar only

### menuselect
- Signature: `menuselect()`
- Purpose: File browser UI for loading .MAP files; supports directory navigation
- Inputs: keystatus[], current menupath, file list
- Outputs: Returns selected menu index or -2 (no files found) or -1 (canceled)
- Side effects: Changes current directory; populates menuname[] array
- Calls: `getfilenames()`, `sortfilenames()`, `chdir()`, `fillscreen16()`, `printext16()`
- Notes: 36-line display window with arrow key navigation; Enter enters directories or selects files; ESC cancels

### copysector
- Signature: `copysector(short soursector, short destsector, short deststartwall, char copystat)`
- Purpose: Duplicate a sector's walls and optionally sprites to a new location
- Inputs: Source sector, destination sector index, destination wall index, copystat flag
- Outputs: Populates sector[destsector] and wall[] range; optionally duplicates sprites
- Side effects: Memcpy of sector/wall structures; calls insertsprite() and memcpy for sprites
- Notes: Adjusts point2 and nextwall/nextsector pointers relative to deststartwall offset

### AutoAlignWalls / AlignWalls / GetWallZPeg
- Purpose: Seamless texture alignment for wall textures across sector boundaries
- AutoAlignWalls: Recursive depth-first search to align connected walls of same texture
- AlignWalls: Align one wall to another's panning/repeat
- GetWallZPeg: Calculate reference z-coordinate based on wall cstat and neighboring sector heights
- Notes: visited[] array tracks processed walls to avoid infinite recursion; handles 1-sided vs. 2-sided wall logic; uses picsiz[] and tilesizy[] for dimension lookup

## Control Flow Notes
**Initialization (main):**
1. Parse command line for map filename
2. Call ExtInit(), initkeys(), inittimer()
3. Load tile art (tiles000.art) and names (names.h)
4. Set video mode (setgamemode)
5. Find brightest palette color for UI drawing (whitecol)
6. Load board or create blank (loadboard → initspritelists)
7. Store start position for 3D mode

**Main Loop (main):**
- Repeats until ESC pressed (quitflag = 1)
- Call ExtPreCheckKeys()
- Render: drawrooms() → ExtAnalyzeSprites() → drawmasks()
- Call ExtCheckKeys()
- nextpage() flips display buffer
- synctics tracks frame timing (totalclock - lockclock)

**3D Mode (editinput):**
- Called once per frame from main loop
- Polls keystatus[] for all input
- Updates posx/posy/posz based on vel/svel and angle (clipmove for collision)
- Handles property editing via F5-F8, Enter to copy/paste, V to pick tile, etc.
- Modal dialogs for numbers/tiles (getnumber256, gettile) block input until confirmed
- Enter key switches to 2D mode

**2D Mode (overheadeditor):**
- Sets video mode to 640×480 (qsetmode640480)
- Main input loop on keystatus[] and mouse (getmousevalues)
- Draw grid, walls, sectors, sprites; overlay tags if zoom >= 768
- Handles sector/wall highlighting with Shift (point mode) or Alt (sector mode)
- Space begins sector drawing (accumulates walls in newnumwalls)
- Backspace undoes last wall; Enter closes sector
- Mouse drag moves highlighted points/sectors
- Menu key (ESC) opens File menu (N)ew, (L)oad, (S)ave, (A)s, (Q)uit
- Enter key returns to 3D mode after validating position inside sector

**File Operations:**
- Load: menuselect() → loadboard() → initspritelists() → ExtLoadMap()
- Save: saveboard() → ExtSaveMap()
- Save As: Prompts for filename (typed character-by-character)

## External Dependencies
- **Rendering**: drawrooms(), drawmasks(), ExtAnalyzeSprites(), nextpage(), clearview(), draw2dscreen(), draw2dgrid(), fillsector(), drawline16(), plotpixel()
- **File I/O**: loadboard(), saveboard(), ExtLoadMap(), ExtSaveMap(), loadpics(), loadnames(), loadtile()
- **Property Display/Edit**: ExtShowSectorData(), ExtShowWallData(), ExtShowSpriteData(), ExtEditSectorData(), ExtEditWallData(), ExtEditSpriteData(), ExtGetSectorCaption(), ExtGetWallCaption(), ExtGetSpriteCaption()
- **Video/Graphics**: setgamemode(), setvmode(), qsetmode640480(), printext16(), printext256(), printmessage16(), printmessage256()
- **Input/Timer**: initkeys(), uninitkeys(), inittimer(), uninittimer(), getmousevalues(), _dos_getvect(), _dos_setvect(), _disable(), _enable()
- **Engine**: clipmove(), getzrange(), hitscan(), getceilzofslope(), getflorzofslope(), insertsprite(), deletesprite(), changespritesect(), setsprite(), updatesector(), sectorofwall(), lastwall(), inside(), loopnumofsector(), loopinside()
- **Math/Utilities**: mulscale*(), divscale*(), scale(), ksqrt(), getangle(), rotatepoint(), ksgn(), klabs(), min(), max()
- **System**: outpw(), outp(), kinp(), koutp(), _dos_findfirst(), _dos_findnext(), chdir(), open(), read(), close(), sprintf(), strcmp(), strcpy(), strcat(), strlen(), memcpy(), memset()
- **Data**: Global arrays: sector[], wall[], sprite[], palette[], sintable[], tilesizx[], tilesizy[], waloff[], headspritesect[], nextspritesect[], show2dsector[], show2dwall[], show2dsprite[]
