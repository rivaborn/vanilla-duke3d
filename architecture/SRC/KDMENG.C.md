# SRC/KDMENG.C

## File Purpose
Sound engine for the Build engine, supporting multi-channel digital audio playback, music sequencing, spatial effects, and multiple legacy sound cards (Sound Blaster, Pro Audio Spectrum, PC speaker). Handles real-time audio mixing, effects processing, and DMA-based hardware interaction.

## Core Responsibilities
- Sound card detection, initialization, and hardware configuration (SB, PAS, PC speaker)
- Wave sample loading (.KWV files) and memory management
- Music file loading (.KDM files) and note sequencing
- Real-time audio mixing and rendering (~120 Hz update rate)
- 16-channel sound effect mixing with effects (vibrato, tremolo, panning)
- Spatial audio effects (distance-based attenuation, listener-relative panning)
- DMA buffer management and interrupt handling
- Frequency/volume/panning effect envelopes
- Interrupt handler installation and restoration

## Key Types / Data Structures
None.

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `digistat` | char | static | Sound device type (0=disabled, 1=Sound Blaster, 2=Pro Audio Spectrum, 13=PC speaker) |
| `musistat` | char | static | Music playback enabled flag |
| `snd` | char* | global | Pointer to wave sample buffer (loaded from .KWV files) |
| `sndseg` | unsigned short | global | DOS conventional memory segment for DMA audio buffer |
| `samplerate` | long | global | Audio sample rate in Hz (validated 6000–48000) |
| `numspeakers` | long | global | Speaker configuration (1=mono, 2=stereo) |
| `bytespersample` | long | global | Sample depth (1=8-bit, 2=16-bit) |
| `splc[16]` | long[] | global | Sample position (fixed-point <<12) for each playback channel |
| `svol1[16]`, `svol2[16]` | long[] | global | Left/mono and right channel volumes per channel |
| `frqtable[256]` | long[] | static | MIDI note-to-frequency lookup table (semitone steps) |
| `eff[16][256]` | long[][] | global | Effect lookup tables: vibrato, tremolo, ramps, panning curves, etc. |
| `musicstatus` | long | global | Playback state (0=stopped, 1=playing) |
| `globposx`, `globposy` | long | static | Listener X/Y position (for spatial audio) |
| `globxvect`, `globyvect` | long | static | Listener forward vector (for relative panning) |
| `sbport`, `sbirq` | long | global | Sound Blaster I/O port and IRQ vector |
| `sbdma`, `sbdma8`, `sbdma16` | long | global | DMA channel configuration for Sound Blaster |

## Key Functions / Methods

### initsb
- **Signature:** `initsb(char dadigistat, char damusistat, long dasamplerate, char danumspeakers, char dabytespersample, char daintspersec, char daquality)`
- **Purpose:** Initialize sound system, configure hardware, load samples, build effect tables, set up interrupt handlers.
- **Inputs:**
  - `dadigistat`: Sound device type (0=none, 1=Sound Blaster, 2=PAS, 13=PC speaker, 255=off)
  - `damusistat`: Music enabled (1 to enable)
  - `dasamplerate`: Sample rate (clamped to 6000–48000 Hz)
  - `danumspeakers`: 1=mono, 2=stereo
  - `dabytespersample`: 1=8-bit, 2=16-bit
  - `daintspersec`: Interrupt frequency (1–120 Hz)
  - `daquality`: 0=low quality, 1=high quality resampling
- **Outputs/Return:** None
- **Side effects:**
  - Allocates and configures DMA buffer in conventional memory
  - Installs interrupt handlers for sound card IRQ
  - Configures DMA controller and PC timer (if applicable)
  - Builds 12-note-per-octave frequency lookup table using 1137589835 scaling factor
  - Generates 16 effect lookup tables (vibrato, tremolo, panning, ramps)
  - Loads wave samples from `WAVES.KWV`
- **Calls:** getsbset, resetsb, sbin, sbout, convallocate, loadwaves, _dos_getvect, _dos_setvect, setuppctimerhandler, installbikdmhandlers, preparesndbuf
- **Notes:**
  - Validates and clamps all parameters to safe ranges
  - Different hardware paths for SB (versions <0x0200, <0x0300, <0x0400)
  - PC speaker mode uses real-time timer interpolation
  - Early hardware versions forced to lower sample rates and 8-bit/mono

### uninitsb
- **Signature:** `uninitsb()`
- **Purpose:** Shut down sound system, disable interrupts, deallocate hardware resources.
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:**
  - Disables DMA transfers and interrupt handlers
  - Restores original interrupt vectors
  - Deallocates DOS conventional memory (`sndseg`)
  - Frees sound sample buffer
  - Resets sound hardware to idle state
- **Calls:** koutp, kinp, convdeallocate, resetsb, sbout, uninstallbikdmhandlers, free
- **Notes:** Safe to call even if initsb was not called (checks `digistat` and `musistat`)

### preparesndbuf
- **Signature:** `preparesndbuf()`
- **Purpose:** Main audio mixing and rendering loop (~120 times per second); handles spatial audio, effects, music sequencing, and DMA buffer updates.
- **Inputs:** None (operates on global state)
- **Outputs/Return:** None
- **Side effects:**
  - Increments DMA buffer write position (`sndoffsplc`)
  - Updates channel playback positions and sample indices
  - Applies frequency, volume, and panning effects with 256-sample envelopes
  - Processes note-on/off events from loaded KDM music
  - Computes distance-based attenuation for spatial sounds
  - Renders audio using `monolocomb`, `monohicomb`, `stereolocomb`, `stereohicomb` (inline assembly mixers)
  - Writes samples to DMA buffer via `bound2char`, `bound2short`, or `pcbound2char`
- **Calls:** kinp, dmulscale28, klabs, msqrtasm, mulscale16, mulscale24, monolocomb, monohicomb, stereolocomb, stereohicomb, calcvolookupmono, calcvolookupstereo, copybuf, clearbuf, startwave
- **Notes:**
  - Performance-critical; extensively uses inline assembly and fixed-point math
  - Double-buffered DMA handling (toggles `sndoffsplc` XOR `sndoffsxor`)
  - Implements Doppler shift approximation via `sincoffs` smoothing
  - Envelopes from `ramplookup` applied during note-off ramp
  - Supports both low-quality (linear interpolation) and high-quality (quadratic) resampling

### loadsong
- **Signature:** `loadsong(char *filename)`
- **Purpose:** Load KDM music file and prepare note sequence for playback.
- **Inputs:** `filename` – path to .KDM file (extension added if missing)
- **Outputs/Return:** 0 on success, −1 on file not found, −2 on version mismatch
- **Side effects:**
  - Stops current playback (`musicoff`)
  - Reads version, note count, track count, track properties, note timing/frequency/volume/effects
  - Populates global music state arrays: `numnotes`, `numtracks`, `trinst`, `nttime`, `ntfreq`, `ntvol1`, etc.
- **Calls:** musicoff, strupr, strstr, strcat, kopen4load, kread, kclose, printf, uninitsb
- **Notes:** Version checking (expects 0); prints error and calls `uninitsb` on failure

### wsay
- **Signature:** `wsay(char *dafilename, long dafreq, long volume1, long volume2)`
- **Purpose:** Play a named sound effect by frequency and volume.
- **Inputs:**
  - `dafilename` – wave name (case-insensitive, matched against `instname[]`)
  - `dafreq` – playback frequency in Hz
  - `volume1` – left/mono volume
  - `volume2` – right channel volume
- **Outputs/Return:** None
- **Side effects:** Allocates least-recently-used channel and calls `startwave`
- **Calls:** startwave
- **Notes:** Silent if `digistat == 0` (sound disabled)

### wsayfollow
- **Signature:** `wsayfollow(char *dafilename, long dafreq, long davol, long *daxplc, long *dayplc, char followstat)`
- **Purpose:** Play a sound that tracks a moving entity position.
- **Inputs:**
  - `dafilename` – wave name
  - `dafreq` – frequency
  - `davol` – volume
  - `daxplc`, `dayplc` – pointers to position (if `followstat=1`) or direct coordinates (if `followstat=0`)
  - `followstat` – 0=static position, 1=follow pointer
- **Outputs/Return:** None
- **Side effects:** Allocates channel with position tracking; subsequent `preparesndbuf` calls update spatial attenuation based on listener position
- **Notes:** Sets `chanstat[i] = followstat+1` to distinguish tracked vs. static channels

### startwave
- **Signature:** `startwave(long wavnum, long dafreq, long davolume1, long davolume2, long dafrqeff, long davoleff, long dapaneff)`
- **Purpose:** Start playback of a wave on a specific channel with effects.
- **Inputs:**
  - `wavnum` – index into wave sample table
  - `dafreq` – frequency (Hz)
  - `davolume1`, `davolume2` – volume levels
  - `dafrqeff`, `davoleff`, `dapaneff` – effect numbers (0=none, 1–15 = effect index)
- **Outputs/Return:** None
- **Side effects:**
  - Chooses least-recently-used channel (max `splc`)
  - Disables channel briefly for clean switch
  - Pre-calculates volume lookup table for the channel
  - Initializes sample position, frequency, volume, and effect state
- **Calls:** calcvolookupmono, calcvolookupstereo
- **Notes:** Silent if both volumes are 0

### setears
- **Signature:** `setears(long daposx, long daposy, long daxvect, long dayvect)`
- **Purpose:** Set listener position and forward vector for spatial audio computation.
- **Inputs:** `daposx`, `daposy` – listener X/Y position; `daxvect`, `dayvect` – forward vector components
- **Outputs/Return:** None
- **Side effects:** Updates `globposx`, `globposy`, `globxvect`, `globyvect`
- **Notes:** Called by game engine before `preparesndbuf` each frame

### musicon / musicoff
- **Signature:** `musicon()` / `musicoff()`
- **Purpose:** Start and stop music playback.
- **Inputs:** None
- **Outputs/Return:** None
- **Side effects:**
  - `musicon`: Sets `musicstatus=1`, resets `notecnt=0`, `timecount=nttime[0]`, `musicrepeat=1`
  - `musicoff`: Sets `musicstatus=0`, zeros all `splc[]`, resets playback pointers
- **Notes:** Both are idempotent; `musicon` requires `musistat==1` to take effect

### getsndbufinfo
- **Signature:** `getsndbufinfo(long *dasndoffsplc, long *dasndbufsiz)`
- **Purpose:** Query current DMA buffer offset and size (game uses for debug overlay).
- **Inputs:** Pointers to output variables
- **Outputs/Return:** None (outputs via pointers)
- **Side effects:** None

### loadwaves
- **Signature:** `loadwaves(char *wavename)`
- **Purpose:** Load wave sample data from .KWV file.
- **Inputs:** `wavename` – filename (extension ".KWV" added if missing)
- **Outputs/Return:** None
- **Side effects:**
  - Reads wave metadata (names, lengths, loop points, fine-tuning) from file
  - Allocates or reuses sound buffer in heap memory
  - Reads sample data; pads end with silence (128 bytes of 0x80)
  - Updates `wavoffs[]` to point into the buffer; tracks `totsndbytes`
- **Calls:** kopen4load, kread, kclose, malloc, printf, exit
- **Notes:** Falls back to `WAVES.KWV` if named file not found; skips reload if same file already loaded

### sbhandler (interrupt handler)
- **Signature:** `void __interrupt __far sbhandler()`
- **Purpose:** Service Sound Blaster interrupt.
- **Inputs:** None (CPU interrupt context)
- **Outputs/Return:** None
- **Side effects:**
  - Acknowledges SB DMA interrupt (8-bit and/or 16-bit depending on version)
  - Re-enables interrupts and calls `preparesndbuf`
  - Sends EOI to interrupt controller
- **Calls:** sbmixin, kinp, koutp, preparesndbuf

## Control Flow Notes

**Initialization Phase:**
- Game calls `initsb(1, 1, 22050, 2, 1, 40, 0)` (or similar) once at startup
- Loads wave samples and sets up DMA/interrupt handlers

**Main Frame Loop (~40 times per second in-game):**
- Game calls `setears()` to update listener position
- Game calls `preparesndbuf()` ~3 times per frame (120 Hz internal rate)
  - Processes note-on/off from music file
  - Updates spatial effects based on sound/listener positions
  - Renders audio into DMA buffer
- Sound card interrupt fires at regular intervals, triggers `sbhandler`, which calls `preparesndbuf`

**Sound Effects:**
- Game calls `wsay("EXPLOSION", freq, vol, vol)` to play an effect
- `startwave` allocates a channel and starts playback
- `preparesndbuf` continues mixing that channel until sample finishes

**Music:**
- Game calls `loadsong("SONG.KDM")`
- Game calls `musicon()`
- `preparesndbuf` checks `musicstatus` and processes note events based on `timecount`

**Shutdown:**
- Game calls `uninitsb()` to restore hardware and free memory

## External Dependencies

**Notable includes:**
- `<malloc.h>` – memory allocation
- `<dos.h>` – DOS interrupts and hardware access
- `<io.h>`, `<fcntl.h>` – file I/O flags
- `<string.h>`, `<stdio.h>` – string and console functions

**External symbols (defined elsewhere):**
- `kopen4load()`, `kread()`, `kclose()` – Build engine file I/O
- `_dos_getvect()`, `_dos_setvect()`, `_disable()`, `_enable()` – DOS/compiler intrinsics
- `int386()`, `int386x()` – DPMI/DOS interrupt calls
- `monolocomb()`, `monohicomb()`, `stereolocomb()`, `stereohicomb()` – Watcom inline-asm mixing routines (also declared with `#pragma aux` calling conventions)
- `setuppctimerhandler()`, `pctimerhandler()` – PC timer real-mode handler setup
- `pcbound2char()`, `bound2char()`, `bound2short()` – Inline-asm sample conversion to DMA buffer
- `strupr()`, `strstr()`, `strcat()`, `strcpy()`, `strcmp()`, `memcpy()` – Standard C library

**Inline assembly helpers** (marked with `#pragma aux`):
- `fsin`, `klabs`, `mulscale16/24/30`, `dmulscale28`, `msqrtasm` – Fixed-point math
- `clearbuf`, `copybuf` – Fast buffer operations
- `kontp`, `kinp`, `koutpw` – Port I/O
- `resetsb`, `sbin`, `sbout`, `sbmixin`, `sbmixout` – Sound Blaster commands
- `findpas`, `convallocate`, `convdeallocate` – Hardware detection and DOS memory
