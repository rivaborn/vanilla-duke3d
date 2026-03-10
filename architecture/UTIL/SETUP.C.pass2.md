# UTIL/SETUP.C — Enhanced Analysis

## Architectural Role

SETUP.C is a **standalone configuration utility** in the engine's toolchain, not part of the runtime engine. It generates a persistent configuration file (`setup.dat`) that defines hardware capabilities and keybindings—likely consumed by BUILD.C or the game itself before startup. Unlike the hierarchical, camera-driven BUILD.C editor, SETUP.C is purely a TUI configuration wizard targeting DOS hardware discovery: graphics modes (Chain4, VESA, chipset-optimized variants), audio devices, serial networking, and input mappings.

## Key Cross-References

### Incoming (who depends on this file)
- **No incoming callers** in the provided codebase. SETUP.C is a standalone utility (`main()` entry point) with no subsystem integration. The generated `setup.dat` file is the sole artifact; the engine presumably reads it at startup.

### Outgoing (what this file depends on)
- **DOS BIOS**:
  - INT 0x10 (video mode setting, cursor positioning)
  - INT 0x09 (keyboard interrupt for `keyhandler`)
  - INT 0x20/0x21 (DOS system calls: exit, print)
- **Hardware I/O**: 
  - VGA text buffer (0xB8000) for direct screen rendering
  - VGA CRTC registers (0x3D4/0x3D5) for cursor control
  - Keyboard controller (0x60, 0x61) for scancode reading
  - Interrupt controller (0x20) for EOI signaling
- **Standard C library** (`<dos.h>`, `<conio.h>`, `<io.h>`):
  - File I/O: `open()`, `read()`, `write()`, `close()` (POSIX-style)
  - Console: `getch()` (blocking key read), `outp()` (port I/O)
  - Utilities: `printf()`, `strlen()`, `exit()`

## Design Patterns & Rationale

1. **Interrupt-Driven Keyboard Handler** (`keyhandler`)
   - **Why**: DOS `getch()` is slow and blocking; the custom handler captures scancodes in real-time via INT 0x9, updating `keystatus[]` array for non-blocking polling.
   - **Pattern**: Classic ISR (interrupt service routine) with volatile state shared with main loop.
   - **Tradeoff**: Complexity vs. responsiveness; SETUP.C doesn't need high throughput, but the pattern is consistent with SRC/KDMENG.C's audio ISR and K.ASM's timer handler.

2. **Hierarchical State Machine** (menu nesting)
   - **Structure**: `main()` loops through top-level menu selections (graphics, sound, input, etc.), each triggering cascading submenus (e.g., GRAPHMENU → CHAINXDIMMENU, CHAINYDIMMENU).
   - **Rationale**: Encodes dependency trees: graphics mode selection determines which dimension menus appear; sound device selection gates playback rate options.
   - **Data**: Menu offsets/lengths hardcoded in `menuoffs[]`, `menuleng[]` arrays; strings indexed from `strtable[135]`.

3. **Screen Save/Restore** (assembly routines)
   - **Why**: DOS text mode redraws entire 80×25 grid per menu. Saving/restoring 4000-byte VGA buffer (25 rows × 80 cols × 2 bytes/cell) avoids flicker and allows logical "popping" of menu stack.
   - **Pattern**: Common in Turbo Vision–era TUI frameworks. SETUP.C inlines it; BUILD.C likely uses similar.
   - **Assembly**: `savescreen()` and `restorescreen()` use `REP MOVSW` for bulk copy; 386 version uses 32-bit (`REP MOVSD` on 1000 dwords) vs. 16-bit mode.

4. **Packed Bitfield Configuration** (`option[]` array)
   - **Encoding**: 8-byte array stores 8 logical options, with sub-fields packed as nybbles (e.g., `option[6]` encodes both X and Y dimensions: `option[6]&0x0F` is X, `(option[6]>>4)&0x0F` is Y).
   - **Rationale**: Minimizes disk footprint; `setup.dat` is ~27 bytes (8 option bytes + 19 key bytes).
   - **Tradeoff**: Readability vs. compactness; no schema/version field (fragile to format changes).

5. **Localized String Tables**
   - **Data**: `strtable[135]` centralizes all UI text; `keytable[]` maps 256 scancodes to names ("ESC", "KP 5", etc.).
   - **Pattern**: Enables translation and UI consistency without code changes; menu system is data-driven.

## Data Flow Through This File

```
[Startup]
  ↓
loadsetup() → open("setup.dat") → read option[], keys[] → setup default(key==0)
  ↓
drawscreen() → render frame + title
savescreen() → backup VGA state
  ↓
[Main Loop]
  restorescreen() → pop menu stack
  menu() → poll keystatus[], render items, highlight selection
    ← capture user choice or ESC
  ↓
  [Branch on selection]
    Graphics → GRAPHMENU → option[0] = user choice
              → if VESA or Chain, open submenu for dimensions
    Sound    → DIGIMENU → option[1] = choice
              → if not "none", open submenus for format, Hz
    Input    → INPUTMENU → option[3] = choice
              → if keyboard, call definekeys() → getscancode() loop
    Comms    → COMMENU → option[4] = choice
              → if COM port, open submenus for speed, IRQ
    ESC or "Save" → savesetup() → write option[], keys[] → exit
  ↓
savesetup() → open("setup.dat", O_CREAT|O_TRUNC|O_WRONLY)
           → write(option[0..7], 8 bytes) + write(keys[0..18], 19 bytes)
           → close()
```

**State Residency**: `option[]` and `keys[]` are modified in-place during menu traversal; each selection immediately updates the array. No transactional semantics (no "cancel" button to revert multiple selections).

## Learning Notes

### Idiomatic to 1990s DOS Game Engines
- **Hardware proximity**: Direct VGA memory access, scancode capture, port I/O with no abstraction layer. Modern engines use OS-mediated APIs (DirectX, X11, Win32 window managers).
- **Real-mode segmentation**: Assembly code explicitly manages `es`, `ds` segments for memory access (16-bit mode); 386 version uses flat 32-bit addressing via pragmas.
- **ISR pattern**: Keyboard handler is a low-level callback; modern systems use event queues or OS message pumps.
- **Configuration as bytecode**: Packed bitfields and implicit enum mappings (e.g., menu index = array offset) are compact but fragile. Modern engines use structured config files (JSON, TOML) with versioning.

### Cross-Engine Patterns
- **Hierarchical menus**: Matches BUILD.C's nested UI (property dialogs, tile browser), but BUILD.C is in-world (3D editor), whereas SETUP.C is out-of-band (pre-game TUI).
- **Interrupt handlers**: Parallels KDMENG.C's `sbhandler` (sound card ISR) and K.ASM's `pctimerhandler_` (timer ISR). All three follow the same discipline: disable interrupts, save/restore CPU state, service hardware, send EOI.
- **Screen state save**: BUILD.C likely uses `savescreen()` / `restorescreen()` similarly for dialog overlays.

### Engine Architecture Insights
- **Two-phase boot**: Game likely loads `setup.dat` at startup, caches hardware info (graphics mode, sound device, keybindings), then initializes ENGINE.C's rendering, KDMENG.C's audio, and MULTI.C's networking using those cached values.
- **No runtime reconfig**: SETUP.C is a standalone utility; no in-game settings menu. Configuration is "compile-time" (before game launch).
- **Keyboard mapping**: The `keys[]` array (19 scancodes) maps to actions in `strtable[]` rows 115–132 (e.g., "Move FORWARD" → keys[0] scancode → 0xC8 = up arrow). Game engine likely reads `keys[]` at startup and builds reverse lookup (action → scancode).

## Potential Issues

1. **No format versioning**: `setup.dat` is raw binary with no version field. If engine changes `option[]` layout (e.g., adds 9th option), old setup.dat silently corrupts (misaligned reads).
   - Mitigation: First byte could encode format version; currently `keys[0]==0` is used to detect "uninitialized" state.

2. **Keyboard handler race condition**: `keyhandler()` reads `keystatus[]` shared with `menu()` main loop without mutual exclusion. If a key is pressed/released mid-iteration of the menu poll loop, inconsistent state is possible (though unlikely to manifest with DOS single-core architecture and interrupt priority).

3. **Hard-coded limits**: `NUMOPTIONS=8`, `NUMKEYS=19`, `strtable[135]` are all compile-time constants. Adding a 9th option or 20th keybinding requires recompilation and binary rebuild.

4. **No bounds checking on menu indices**: `menu()` wraps selection at boundaries but doesn't validate that `menunum` is within `[0, NUMENUS)`. Passing invalid `menunum` reads garbage from `menuoffs[]`, `menuleng[]`.

5. **Fragile string indexing**: Menu strings are offset-calculated manually; `menuoffs[VESA2MENU]=?` is brittle to reordering or insertion of items in `strtable[]`.
   - Mitigation: Compiler could compute offsets programmatically, but first-pass code is hand-indexed.

---

**Learning Opportunity**: SETUP.C exemplifies a era when configuration was **static, pre-game, decoupled from the runtime engine**. Modern games offer in-game settings menus that serialize to JSON. This utility is the DOS-era equivalent: a standalone wizard that generates a binary blob for game consumption.
