# SRC/BUILD.H

## File Purpose
Core engine header defining the fundamental data structures (sector, wall, sprite), compile-time limits, and global state variables for the Build Engine. This is the central data model that all engine code references.

## Core Responsibilities
- Define MAXSECTORS, MAXWALLS, MAXSPRITES, MAXTILES, and other engine limits
- Define packed struct layouts for sector, wall, and sprite with detailed cstat bit flags
- Declare global game world state arrays (sectors, walls, sprites)
- Declare rendering state (viewport, video mode, screen dimensions)
- Declare timing and animation state (totalclock, numframes, sintable)
- Declare sprite linked lists for spatial and status-based queries
- Declare tile metadata and palette/lookup table pointers
- Provide automapping and visibility tracking bitfields

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| sectortype | struct (40 bytes) | Represents a sector: ceiling/floor heights, textures, parallax flags, visibility, and metadata (tags, extra). |
| walltype | struct (32 bytes) | Represents a wall: position, texture, clipping flags, neighbor references (point2, nextwall, nextsector). |
| spritetype | struct (44 bytes) | Represents a sprite/actor: 3D position, rotation, velocity, texture, clipping, physics flags, and metadata. |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| sector | sectortype[MAXSECTORS] | extern | Sector definitions for the loaded map |
| wall | walltype[MAXWALLS] | extern | Wall definitions for the loaded map |
| sprite | spritetype[MAXSPRITES] | extern | All sprites in the world |
| tsprite | spritetype[MAXSPRITESONSCREEN] | extern | Visible sprites culled for rendering (sorted) |
| spritesortcnt | long | extern | Count of visible sprites in tsprite |
| totalclock | volatile long | extern | Master tick counter, incremented 120/sec; elapsed_seconds = totalclock / 120 |
| numframes | long | extern | Number of render calls since init; frame_rate = numframes * 120 / totalclock |
| xdim, ydim | long | extern | Screen/viewport pixel dimensions |
| ylookup | long[MAXYDIM+1] | extern | Scanline offset lookup table for video memory |
| sintable | short[2048] | extern | Precomputed sine table (range: -16383 to 16383, 2048 angles) |
| palette | char[768] | extern | 256-color palette (3 bytes RGB per color) |
| palookup | char*[MAXPALOOKUPS] | extern | Shading palette lookup tables |
| headspritesect, headspritestat | short[MAXSECTORS+1/MAXSTATUS+1] | extern | Linked list heads: first sprite in each sector/status |
| nextspritesect, nextspritestat | short[MAXSPRITES] | extern | Linked list next pointers for sector/status traversal |
| prevspritesect, prevspritestat | short[MAXSPRITES] | extern | Linked list prev pointers |
| tilesizx, tilesizy | short[MAXTILES] | extern | Per-tile width and height in pixels |
| waloff | long[MAXTILES] | extern | Memory offset pointers to tile bitmap data |
| picanm | long[MAXTILES] | extern | Per-tile animation flags |
| show2dsector, show2dwall, show2dsprite | char[] (bitfields) | extern | Automapping visibility per sector/wall/sprite (bit-packed) |
| automapping | char | extern | Automapping enable flag (0=off, 1=auto-reveal) |
| startumost, startdmost | short[MAXXDIM] | extern | Top/bottom clipping bounds per screen column |
| windowx1, windowy1, windowx2, windowy2 | long | extern | Clipping window for rendering operations |

## Key Functions / Methods
None — this is a header file with struct definitions and extern declarations only.

## Control Flow Notes
This file does not contain executable code; it defines the data model used across all engine lifecycle phases:
- **Init**: World arrays (sector, wall, sprite) populated from map file
- **Frame**: totalclock incremented, visible sprites culled into tsprite
- **Render**: Camera transforms using xdim/ydim, viewport bounds; tsprite sorted and drawn
- **Gameplay**: Sprite state updated via velocity fields; sector/wall state modified

## External Dependencies
- Standard C library types (short, long, char, signed char, unsigned char)
- Macro EXTERN: defined as blank if ENGINE=1 (engine defines), else extern (game externs)
- `#pragma pack(push,1)`: Enforces tight byte-packing for structs (no alignment padding)

## Notes
- Detailed bit-flag documentation for cstat fields (sprite/wall/sector state bits: blocking, translucency, flipping, masking, etc.)
- Sprite linked lists use -1 as terminator; supports both sector-based and status-based iteration
- Automapping arrays are bit-packed for memory efficiency (spritenum >> 3, 1 << (spritenum & 7))
- Coordinate system: angles 0–2047 (not 0–360°); z increases downward
- timing reference: totalclock / 120 = seconds elapsed
