# SRC/K.ASM

## File Purpose
x86-32 assembly code implementing the audio synthesis and PCM sample conversion engine for Duke3D. Contains four combinatorial synthesis functions (mono/stereo × low/high quality), PC timer interrupt handling for audio playback, and sample bounding/format conversion utilities (8-bit, 16-bit).

## Core Responsibilities
- **Comb filter synthesis** (four variants: monolocomb, monohicomb, stereolocomb, stereohicomb) for real-time audio generation
- **PC timer interrupt handling** (pctimerhandler_) for PCM playback scheduling and buffer management
- **Audio sample bounding and conversion** to char (8-bit) and short (16-bit) formats with saturation
- **Self-modifying code** to inject setup parameters into inner loops for performance optimization
- **Double-buffering management** via `_bufferside` flag and buffer pointer arithmetic
- **Interrupt chaining** to delegate to the original timer interrupt handler after processing

## Key Types / Data Structures
None.

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `_kdmasm1`, `_kdmasm2`, `_kdmasm3`, `_kdmasm4` | dword | global | Parameter passing for synthesis setup (external) |
| `_pcsndptr` | dword | global | Current PCM sample buffer write pointer (external) |
| `_pcsndbufsiz` | dword | global | PCM buffer size in samples (external) |
| `_chainbackcnt` | dword | global | Samples remaining before timer interrupt triggers (external) |
| `_chainbackstart` | dword | global | Initial value for chainbackcnt reload (external) |
| `_bufferside` | byte | global | Ping-pong flag (0/1) for double-buffering (external) |
| `mach1lm`, `mach2ls`, `mach5lm`, etc. | — | static | Self-modifying code patches in comb filter loops |
| `pcmach1`, `pcmach2`, `pcmach3` | — | static | Self-modifying code patches in PC timer handler |
| `machchar`, `pcmachchar` | — | static | Self-modifying code patches in sample conversion loops |

## Key Functions / Methods

### monolocomb_
- **Signature:** `void monolocomb_(void)`
- **Purpose:** Low-quality mono comb filter synthesis loop. Processes stereo input sample-by-sample with 12-bit fixed-point fractional addressing.
- **Inputs (via registers):** `eax`=temp, `ebx`=volume offset, `ecx`=sample count, `edx`=fractional delta, `esi`=sample pointer (integer part), `edi`=output buffer, `ebp`=fractional position
- **Outputs:** Modified output buffer at `[edi]`, returns combined position in `eax`
- **Side effects:** Self-modifies mach1lm, mach3lm, mach4lm, mach5lm patches; reads/writes external `_kdmasm1-4`
- **Calls:** None within this file
- **Notes:** Uses carry flag from `adc` for fractional overflow. Loop invariant: `ebp` holds 32-bit fractional, `esi` holds integer part. Jump table handles early-exit conditions (_kdmasm1 trigger).

### monohicomb_
- **Signature:** `void monohicomb_(void)`
- **Purpose:** High-quality mono comb filter synthesis. Adds interpolation via `_qualookup` table lookup based on fractional part.
- **Inputs (via registers):** Same as monolocomb_
- **Outputs:** Modified output buffer at `[edi]`, returns combined position in `eax`
- **Side effects:** Self-modifies mach1hm–mach5hm patches; reads _kdmasm1-4, _qualookup
- **Calls:** External `_qualookup` (near)
- **Notes:** Computes interpolation index from high byte of fractional position; uses `adc` for carry propagation.

### stereolocomb_
- **Signature:** `void stereolocomb_(void)`
- **Purpose:** Low-quality stereo (2-channel) comb filter synthesis. Processes two channels simultaneously with separate volume offsets.
- **Inputs (via registers):** Same as monolocomb_; `ebx` and `ebx+4` point to separate volume tables
- **Outputs:** Modified stereo output buffer (8 bytes per iteration), returns combined position
- **Side effects:** Self-modifies mach1ls–mach5ls patches; double-buffer stride (add/sub 8)
- **Calls:** None
- **Notes:** Two parallel sample processing chains per loop iteration.

### stereohicomb_
- **Signature:** `void stereohicomb_(void)`
- **Purpose:** High-quality stereo comb filter synthesis with interpolation.
- **Inputs (via registers):** Same as stereolocomb_
- **Outputs:** Modified stereo output buffer, returns combined position
- **Side effects:** Self-modifies mach1hs–mach5hs patches
- **Calls:** External `_qualookup`
- **Notes:** Combines stereo processing with quality interpolation; uses `ebp` as sample counter (not offset).

### setuppctimerhandler_
- **Signature:** `void setuppctimerhandler_(dword eax, dword ebx)`
- **Purpose:** Pre-configures the PC timer interrupt handler by injecting end-of-buffer address and optionally patching sample divider.
- **Inputs:** `eax` = end-of-buffer address, `ebx` = sample divider
- **Outputs:** None (self-modifies pcmach3, conditionally pcmach1/pcmach2)
- **Side effects:** Writes to pcmach3+2 always; if `ebx >= 65000`, injects divider arithmetic into pcmach1/pcmach2
- **Calls:** None
- **Notes:** Used during initialization; enables dynamic sample rate control.

### pctimerhandler_
- **Signature:** `void pctimerhandler_(void)` — interrupt handler (far call)
- **Purpose:** PC timer interrupt (INT 8) handler for real-time PCM playback. Manages sample output, buffer refill, and chaining to the original handler.
- **Inputs:** None (triggered by hardware interrupt)
- **Outputs:** None (modifies PCM output port and buffer state)
- **Side effects:** 
  - Reads/writes `_pcsndptr`, `_chainbackcnt`, `_chainbackstart`, `_bufferside`, `_pcsndbufsiz`
  - Outputs samples to I/O port 0x42h (PC speaker)
  - Calls `preparesndbuf_` when buffer boundary crossed
  - Modifies `ds` segment to DGROUP
  - Chains to `_oldpctimerhandler` for original behavior
- **Calls:** `preparesndbuf_` (near), `__GETDS` (near), `_chain_intr_` (near)
- **Notes:** Double-buffered (flips `_bufferside`). Three exit paths: normal iretd, buffer-refill iretd, and chained interrupt. Uses `cmp`/`jge` to detect end-of-buffer; uses `jnz` conditionally to wrap to start.

### pcbound2char_
- **Signature:** `void pcbound2char_(dword* esi, dword edi, dword ecx)`
- **Purpose:** Convert two-sample 32-bit stereo dword pairs to 16-bit clamped char pairs via PC sound lookup table.
- **Inputs:** `esi` = source buffer (dword pairs), `edi` = destination offset (within lookup table), `ecx` = byte pair count
- **Outputs:** Audio data written via `_pcsndlookup` lookup and stored in buffer
- **Side effects:** Modifies `esi`, reads `_pcsndlookup` twice per iteration, self-modifies pcmachchar
- **Calls:** External `_pcsndlookup` (near)
- **Notes:** Uses `sbb` instruction for sign-bit extraction (overflow handling). Processes high byte of each sample.

### bound2char_
- **Signature:** `void bound2char_(dword* esi, dword edi, dword ecx)` — PC-independent version
- **Purpose:** Same as pcbound2char_ but writes directly without lookup table; simple byte saturation.
- **Inputs:** `esi` = source dword pairs, `edi` = destination offset, `ecx` = byte pair count
- **Outputs:** Clamped byte pairs stored in destination
- **Side effects:** Self-modifies machchar
- **Calls:** None
- **Notes:** No external lookup; uses `sbb` for min(0) logic, stores high byte of each sample.

### bound2short_
- **Signature:** `void bound2short_(dword* esi, dword edi, dword ecx)` — 16-bit conversion
- **Purpose:** Convert stereo dword pairs to 16-bit short samples with saturation and XOR-bit offset (8000h).
- **Inputs:** `esi` = source dword pairs, `edi` = destination offset, `ecx` = sample pair count
- **Outputs:** 16-bit shorts stored in destination (4 bytes per iteration)
- **Side effects:** Self-modifies machshort; `sbb` for sign saturation
- **Calls:** None
- **Notes:** Uses `xor eax, 80008000h` to flip sign bits (unsigned representation). Byte count scaled by 4 internally.

## Control Flow Notes
- **Initialization path:** `setuppctimerhandler_()` configures parameters, then interrupt timer is armed
- **Per-frame audio:** INT 8 (PC timer) fires periodically, calling `pctimerhandler_()`. This reads one sample, outputs to port 0x42h, checks if buffer exhausted, and if so, calls `preparesndbuf_()` to refill and toggles `_bufferside`
- **Synthesis path:** Higher-level code calls one of the four comb functions (monolocomb_, monohicomb_, stereolocomb_, stereohicomb_) to generate samples into a working buffer
- **Sample conversion:** After synthesis, bound2char_, pcbound2char_, or bound2short_ converts the 32-bit working buffer to output format (8-bit or 16-bit with saturation)
- **Shutdown:** Not inferable from this file; original handler is chained at end of pctimerhandler_

## External Dependencies
- **External variables (global):** `_kdmasm1`, `_kdmasm2`, `_kdmasm3`, `_kdmasm4`, `_chainbackcnt`, `_chainbackstart`, `_pcsndptr`, `_samplecount`, `_pcsndbufsiz`, `_oldpctimerhandler` (far), `_bufferside`
- **External functions (near calls):** `_qualookup`, `_pcsndlookup`, `_chain_intr_`, `__GETDS`, `preparesndbuf_`
- **I/O ports:** 0x20h (PIC interrupt control), 0x42h (PC speaker sample output)
- **Data segment:** DGROUP (established via `mov ax, DGROUP; mov ds, ax`)
