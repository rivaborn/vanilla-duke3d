# SRC/KDMENG.C — Enhanced Analysis

## Architectural Role

KDMENG.C is the **primary audio subsystem bridge** between the game engine and legacy DOS sound hardware. It manages both real-time sound effects (16 simultaneous channels with spatial effects) and MIDI-like music sequencing via proprietary .KDM music files and .KWV sample archives. The engine operates in interrupt-driven mode (Sound Blaster IRQ or PC timer INT 0x08), ensuring deterministic audio output at ~120 Hz independent of game frame rate—a critical separation of concerns in early 90s game development where audio latency could cause synchronization issues.

## Key Cross-References

### Incoming (who depends on this file)

From the cross-reference context, KDMENG.C is called by **game initialization code** (not visible in call graph, suggesting top-level startup):
- **`initsb()`** — called once at engine startup to configure hardware and load assets
- **`loadsong()`** — called by game to load .KDM music files (called before `musicon()`)
- **`wsay()` / `wsayfollow()`** — game calls these to trigger sound effects by name
- **`setears()`** — game calls per-frame to update listener position for spatial audio
- **`preparesndbuf()`** — called ~40 times per second by main loop AND via `sbhandler` interrupt (dual-path invocation pattern)
- **`getsndbufinfo()`** — called by debug overlay to display audio buffer state
- **`musicon()` / `musicoff()`** — called by game to control music playback

Notably, the cross-ref call graph does **not** prominently list KDMENG callers—suggesting the audio system is largely autonomous after initialization, with minimal per-frame coupling.

### Outgoing (what this file depends on)

**Audio synthesis (K.ASM):**
- `monolocomb()`, `monohicomb()`, `stereolocomb()`, `stereohicomb()` — four variants of comb-filter mixing routines for low/high quality audio at 1–2 speaker configs
- `setuppctimerhandler()`, `pctimerhandler()` — PC speaker real-mode interrupt handler installation
- `bound2char()`, `bound2short()`, `pcbound2char()` — sample format conversion with bounds-clamping

**Hardware control (inline asm pragmas):**
- `resetsb()`, `sbin()`, `sbout()`, `sbmixin()`, `sbmixout()` — Sound Blaster command I/O
- `findpas()` — Detect Pro Audio Spectrum hardware
- `kontp()`, `kinp()`, `koutpw()` — Direct port I/O for DMA and timer control

**Memory and file I/O:**
- `convallocate()`, `convdeallocate()` — DOS conventional memory management (required for DMA buffers)
- `kopen4load()`, `kread()`, `kclose()` — Asset loading via CACHE1D subsystem
- `malloc()`, `free()` — Heap allocation for sample buffers

**Fixed-point math (PRAGMAS.H):**
- `mulscale16/24/30()`, `dmulscale28()`, `msqrtasm()`, `klabs()` — arithmetic-heavy mixing pipeline (no x87 FPU use; Watcom inline asm only)

**Utility:**
- `_dos_getvect()`, `_dos_setvect()`, `_disable()`, `_enable()` — Interrupt vector management
- `int386()`, `int386x()` — DPMI/DOS interrupt calls for hardware initialization

## Design Patterns & Rationale

**Interrupt-driven, double-buffered audio pipeline:**
The DMA buffer is split into two halves. The `sbhandler` ISR fires when one half completes, triggering `preparesndbuf()` to fill the other half. This allows continuous audio without busy-waiting and decouples audio timing from game logic. The `sndoffsplc XOR sndoffsxor` double-buffering check prevents tearing.

**Frequency-table synthesis instead of floating-point:**
The `frqtable[256]` is pre-computed using fixed-point (1137589835 = 2^30 * 12th-root-of-2). Each note is a semitone step. This avoids expensive FPU operations in the mixing ISR—critical for 1995-era CPUs where an x87 exception could halt the entire system.

**Hardware abstraction via compile-time switches:**
Rather than runtime polymorphism, different sound cards (SB, PAS, PC speaker) are selected at `initsb()` time via `digistat` enum. Each path initializes distinct interrupt handlers and port I/O sequences. This was typical of DOS-era monolithic audio drivers—there's no listener object or callback interface.

**Mixing quality trade-off:**
Four comb filter variants (mono/stereo × low/high quality) allow runtime selection via `kdmqual` flag. Low-quality uses linear interpolation; high-quality (implied) uses finer sample stepping. Game can trade CPU for audio fidelity per deployment.

**Spatial effects via listener-relative math:**
`globposx`, `globposy`, `globxvect`, `globyvect` define listener state. Each sound channel computes distance (`msqrtasm`) and relative angle (`dmulscale28`) to apply panning and attenuation. This is classic 3D audio: no per-sample ray tracing, just pre-computed lookup tables for gain and pan curves.

## Data Flow Through This File

```
Game Init
  ↓
initsb() ──────────────────────┐
  ├─→ getsbset(), resetsb()    │ Hardware config
  ├─→ loadwaves("WAVES.KWV")   │ Asset load
  ├─→ build eff[16][256]       │ Effect LUTs
  └─→ _dos_setvect(sbport IRQ) │ Install ISR
     ↓
[Sound Blaster IRQ fires]
     ↓
sbhandler() ──→ preparesndbuf()
                  ├─→ Game called setears() last frame
                  ├─→ Update channel freqs/vols/pan per music notes
                  ├─→ For each of 16 channels:
                  │    ├─→ Apply effects (vibrato, tremolo)
                  │    ├─→ Spatial math (distance, angle)
                  │    └─→ Call comb filter (mono/stereolocomb)
                  ├─→ bound2char/short() for DMA write
                  └─→ Toggle sndoffsplc for next buffer half
```

**Asynchronous call paths:**
- **Interrupt-driven:** ISR → `sbhandler()` → `preparesndbuf()`
- **Polled (fallback for PC speaker):** Game loop calls `preparesndbuf()` directly

**Music integration:**
`loadsong()` populates `nttime[]`, `ntfreq[]`, `ntvol1/2[]`, etc. Each call to `preparesndbuf()` checks if `timecount >= nttime[notecnt]` to trigger note-on events via `startwave()`.

## Learning Notes

**What makes this engine era-specific:**

1. **No state objects:** All state is global arrays. Modern engines use voice/channel objects with vtable polymorphism; this uses flat index-based lookup.
2. **Fixed-point arithmetic everywhere:** No float/double; all samples, frequencies, and gain are 16.16 or similar. This was necessary on 486/Pentium before widespread FPU adoption.
3. **Polyphonic mixing at CPU bottleneck:** 16 channels is modest by modern standards but required careful asm optimization in 1995. The comb filter is a time-tested synthesis kernel, not a general-purpose DSP.
4. **Interrupt-driven audio without OS abstraction:** Directly installs ISRs, manages DMA, and modifies video memory. A modern game would use OS audio APIs (ALSA, CoreAudio, WASAPI).
5. **Proprietary .KDM/.KWV formats:** The game's own music and sample formats—no standard MIDI/WAV support visible. Suggests tight coupling to toolchain.

**Architectural lessons:**
- Separating audio timing (ISR at hardware rate) from game logic (variable framerate) prevents stuttering.
- Pre-computed lookup tables (frqtable, eff[], qualookup) trade memory for CPU in tight loops.
- Spatial audio math (distance + angle → gain + pan) is simpler than impulse response but still effective.

## Potential Issues

**Not clearly inferable from code + context:**
- How does `preparesndbuf()` remain isochronous (never exceeds budget) given 16 channels × effects? The code uses inline asm extensively, but ISR overrun risk is implicit.
- The PC speaker path (`digistat==13`) uses real-mode timer (`setuppctimerhandler`), but cross-refs don't show how this integrates with the main `sbhandler` architecture.
- Memory fragmentation: `loadwaves()` calls `malloc()` without a persistent memory manager. Repeated load/unload could fragment heap on longer play sessions.
