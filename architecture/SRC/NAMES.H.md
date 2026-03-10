# SRC/NAMES.H

## File Purpose
Defines numeric identifiers (tile/sprite type constants) for game entities in the Build engine. Used throughout the editor (Editart) and game code to reference specific sprite types, interactive objects, enemies, and environmental elements.

## Core Responsibilities
- Define sprite type constants for player, enemies, interactive objects, and environmental elements
- Provide human-readable names for numeric tile/sprite IDs used in level data
- Enable consistent entity type identification across the editor and game engine
- Map conceptual entity names to Build engine sprite indices

## Key Types / Data Structures
None.

## Global / File-Static State
None. (This is a preprocessor header containing only macro definitions.)

## Key Functions / Methods
None. (Header file with macro definitions only.)

## Preprocessor Definitions (Constants)
This file defines 40+ sprite/tile type constants. Notable groupings:

**Player & Enemies:** `PLAYER`, `SKELETON`, `BROWNMONSTER`, `AL`, `EVILAL`, `EVILALGRAVE`

**Interactive Objects:** `SWITCH1ON`, `SWITCH2ON/OFF`, `SWITCH3ON/OFF`, `COIN`, `COINSTACK`, `GIFTBOX`, `DIAMONDS`, `GIFTBOX`, `GRABBER`, `GRABCANNON`, `BOUNCYMAT`, `MIRROR`, `FLOORMIRROR`

**Weapons/Projectiles:** `BULLET`, `BOMB`, `MISSILE`, `CANNON`, `GUNONBOTTOM`, `BOMBEMITTER`, `LAUNCHER`, `EXPLOSION`, `SPLASH`

**Environmental:** `DAYSKY`, `NIGHTSKY`, `BACKGROUND`, `WATERFOUNTAIN`, `USEWATERFOUNTAIN`, `AIRPLANE`, `FOOTPRINT`, `STATUSBAR`, `STATUSBARFILL4/8`

**UI/Meta:** `ALPHABET`, `DEMOSIGN`, `NO`, `KENPICTURE`, `BUILDDISK`, `COMPASS`, `SPIRAL`, `MIRRORLABEL`

## Control Flow Notes
This is an include file parsed by the Build editor (Editart) and game code. Constants are used to identify entity types in level data structures throughout the engine. No runtime control flow.

## External Dependencies
- No includes or external symbols
- Comment indicates file is parsed by `Editart` and `Build` tools (editor/engine introspection)
