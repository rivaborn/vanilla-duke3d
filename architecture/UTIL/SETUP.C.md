# UTIL/SETUP.C

## File Purpose
DOS-era interactive configuration utility for the Build Engine. Manages hardware settings (graphics, sound, input devices, communications) via a menu-driven TUI, with keyboard interrupt handling and persistent storage to `setup.dat`. Exclusively targets DOS/real-mode x86 architecture with direct hardware access.

## Core Responsibilities
- Present hierarchical menu system for hardware configuration selection
- Manage graphics modes (Chain, VESA, specialized chipsets)
- Configure digitized sound devices and playback parameters
- Set music, input devices (keyboard/mouse/joystick), and serial communications
- Custom keybinding capture via keyboard interrupt handler
- Save/restore VGA screen state during menu transitions
- Load and persist configuration to binary file
- Direct VGA text-mode rendering with box-drawing characters

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| `strtable[135]` | array of char pointers | Localized menu item strings and descriptions |
| `keytable[]` | array of char pointers | Scancode-to-human-readable key name mappings (e.g., "Q", "ESC", "KP 5") |
| `menuoffs[NUMENUS]` | static array | Offset indices into `strtable` for each menu's first string |
| `menuleng[NUMENUS]` | static array | Length of each menu in items |
| `option[NUMOPTIONS]` | static array | Current 8 hardware configuration options (packed bitfields) |
| `keys[NUMKEYS]` | static array | Current 19 keybindings (scancodes) |
| `keystatus[256]` | volatile array | Real-time key state (0=up, 1=down) for all 256 scancodes |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `screeninfo[4000]` | unsigned char array | static | VGA text-mode buffer backup (80×25 × 2 bytes per cell) |
| `readch`, `oldreadch`, `extended` | volatile unsigned char | static | Keyboard interrupt state: current scancode, previous, extended key flag |
| `keystatus[256]` | volatile unsigned char | static | Per-scancode key down/up tracker for interrupt handler |
| `defaultkey[NUMKEYS]` | unsigned char array | static | Hardcoded default keybindings (arrow keys, ctrl, alt, etc.) |
| `oldkeyhandler` | function pointer | static | Saved original DOS keyboard interrupt (INT 0x9) handler |
| `menuoffs[NUMENUS]` | int array | static | Precomputed offsets into `strtable` for menu start positions |

## Key Functions / Methods

### `main()`
- **Purpose:** Primary event loop orchestrating configuration workflow
- **Inputs:** Command-line args (unused)
- **Outputs/Return:** None (exits via INT 0x10 mode set)
- **Side effects:** 
  - Loads `setup.dat` into `option[]` and `keys[]`
  - Draws initial UI, saves VGA state
  - Modifies global `option[]`, `keys[]` based on user selections
  - Saves config to disk on exit
  - Restores video mode (INT 0x10, AX=3)
- **Calls:** `loadsetup()`, `drawscreen()`, `savescreen()`, `menu()`, `definekeys()`, `restorescreen()`, `savesetup()`
- **Notes:** Nested menu branching for graphics/sound/comms submenus; option packing/unpacking via bitfield manipulation (e.g., `option[6]&0xf0`)

### `loadsetup()`
- **Purpose:** Initialize configuration from persistent storage or defaults
- **Inputs:** None
- **Outputs/Return:** None (modifies globals `option[]`, `keys[]`)
- **Side effects:** Opens, reads, closes `setup.dat` (3 reads: option array, key array, type check); sets defaults if file missing or corrupted
- **Calls:** `open()`, `read()`, `close()` (POSIX I/O)
- **Notes:** No explicit error handling for read failures; if `keys[0] == 0`, treats as uninitialized and copies `defaultkey[]`

### `savesetup()`
- **Purpose:** Persist current configuration to disk
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:** Creates/truncates `setup.dat`, writes `option[]` and `keys[]`; exits if file open fails
- **Calls:** `open()`, `write()`, `close()`, `printf()`, `exit()`
- **Notes:** Uses O_CREAT, O_TRUNC flags; calls `exit(0)` on I/O error

### `drawscreen()`
- **Purpose:** Render initial TUI frame (border, title, hints)
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:** Sets VGA text mode 3, draws box-drawing characters (218, 196, 191, 179, 192, 217), positions title and help text
- **Calls:** `outp()` (direct VGA controller I/O), `printchr()`, `printstr()`
- **Notes:** Hardcoded 80×25 mode; uses VGA color attributes (78=bright white on black, 71=bright cyan, etc.)

### `menu(unsigned char *title, int menunum, int selection)`
- **Purpose:** Render interactive scrollable menu and capture user selection
- **Inputs:** 
  - `title`: Menu heading string
  - `menunum`: Index into `menuoffs[]`/`menuleng[]` arrays
  - `selection`: Default highlighted item index
- **Outputs/Return:** Selected item index (≥0), or negative codes for cancel/special keys (−1, −256 for F1, −257 for spacebar)
- **Side effects:** Renders menu with box frame, highlights current selection, polls `getch()` in loop, skips separator lines (char 196)
- **Calls:** `strlen()`, `printstr()`
- **Notes:** Wraps selection at menu boundaries; ESC returns `−1−selection` (cancellation); ENTER/SPACE confirm; arrows navigate

### `definekeys()`
- **Purpose:** Provide UI for remapping keyboard controls
- **Inputs:** None
- **Outputs/Return:** None (modifies global `keys[]`)
- **Side effects:** 
  - Clears screen lines 1–23
  - Displays keybinding instructions
  - Loops `menu(KEYMENU)` with real-time key name updates
  - Calls `getscancode()` on selection
  - F1 resets to `defaultkey[]`
- **Calls:** `printchr()`, `printstr()`, `menu()`, `getscancode()`
- **Notes:** Updates `strtable` entries in-place with current key names before each menu call

### `getscancode(unsigned char scancode)`
- **Purpose:** Capture next keyboard press via interrupt handler
- **Inputs:** `scancode`: Current keybinding (shown as fallback if abort)
- **Outputs/Return:** New scancode (scanned via keyboard interrupt), or original if <2
- **Side effects:** 
  - Blanks all screen cells (sets attribute to 19)
  - Installs custom `keyhandler` to INT 0x9
  - Polls `keystatus[]` until non-0xAA key detected
  - Restores old INT 0x9 handler
  - Disables/enables CPU interrupts around handler swap
- **Calls:** `_dos_getvect()`, `_dos_setvect()`, `_disable()`, `_enable()` (Watcom intrinsics)
- **Notes:** Ignores 0xAA (pause key); double-loop over all screen cells to clear highlight; only accepts scancode > 1

### `keyhandler()` (interrupt handler)
- **Purpose:** Capture keyboard scancode and update global `keystatus[]` on every key event
- **Inputs:** None (called by CPU on INT 0x9)
- **Outputs/Return:** None
- **Side effects:** 
  - Reads scancode from port 0x60
  - Acknowledges interrupt on port 0x61
  - Updates `readch`, `extended`, `keystatus[code+extended]`
  - Sends EOI (0x20) to PIC (port 0x20)
- **Calls:** None
- **Notes:** Handles extended keys (0xE1 prefix sets `extended=128`); debounces by comparing `oldreadch` to `readch`; bit 7 of scancode indicates key release

### `printstr(int x, int y, unsigned char string[81], unsigned char attribute)`
- **Purpose:** Write null-terminated string to VGA text memory
- **Inputs:** 
  - `x`, `y`: Column, row (0–79, 0–24)
  - `string`: Null-terminated message
  - `attribute`: VGA color byte (foreground/background)
- **Outputs/Return:** None
- **Side effects:** Calls `printchrasm()` once per character
- **Calls:** `printchrasm()`, `strlen()` (via loop)
- **Notes:** Assumes string length ≤81; iterates char-by-char

### `printchr(int x, int y, unsigned char character, unsigned char attribute, int len)`
- **Purpose:** Repeat character `len` times at position (x,y)
- **Inputs:** 
  - `x`, `y`: Column, row
  - `character`, `attribute`: Single char and color
  - `len`: Repeat count
- **Outputs/Return:** None
- **Side effects:** Calls `printchrasm()` with calculated video offset
- **Calls:** `printchrasm()`
- **Notes:** Video offset = `(y*80+x)<<1`; shifts because VGA text cells are 2 bytes each (char + attr)

### Assembly helpers: `printchrasm()`, `savescreen()`, `restorescreen()`
- **Purpose:** Optimized video memory operations using REP STOSW/MOVSW
- **Notes:** Conditional compilation for 386 vs. 16-bit real mode; 386 version uses pragmas, 16-bit uses inline asm with segment overrides

## Control Flow Notes
- **Init phase (main):** Load setup.dat → draw frame → save VGA state → initialize menu offset table
- **Main menu loop:** Display menu → branch on selection (case 0–4 for config categories) → handle nested submenus → return to main loop
- **Configuration updates:** Graphics/sound/comms selections trigger dependent submenus (e.g., VESA mode → select mode dimensions); keyboard submenu calls `definekeys()`
- **Shutdown:** On case 6 (save) or ESC from main menu, call `savesetup()` and exit
- **Frame rendering:** Restore VGA state before each menu to erase previous menu; redraw borders/text per menu
- **Keyboard:** Hardware interrupt-driven; keyhandler updates `keystatus[]` in real-time; `getscancode()` polls until a valid key is pressed

## External Dependencies
- **DOS/BIOS:** `<dos.h>` — `_interrupt`, `_far`, `_disable()`, `_enable()`, `_dos_setvect()`, `_dos_getvect()`, `_asm` intrinsics
- **Console I/O:** `<conio.h>` — `getch()`, `outp()` (VGA direct I/O)
- **File I/O:** `<io.h>`, `<fcntl.h>`, `<sys/types.h>`, `<sys/stat.h>` — `open()`, `read()`, `write()`, `close()`
- **Stdio:** `<stdio.h>` — `printf()`, `strlen()`
- **Compiler-specific:** Watcom C pragmas (`#pragma aux`) for 386-optimized assembly; conditional `#if defined(__386__)` for architecture branching
- **Hardware:** Direct reads/writes to VGA text buffer (0xB8000/0xB8000000), keyboard controller (port 0x60), interrupt controller (port 0x20/0x21), and VGA CRTC (ports 0x3D4/0x3D5)
