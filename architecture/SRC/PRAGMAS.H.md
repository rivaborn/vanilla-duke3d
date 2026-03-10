# SRC/PRAGMAS.H

## File Purpose
Header file defining inline x86 assembly pragmas for the Watcom C compiler. Provides optimized implementations of fixed-point math, VGA graphics operations, hardware I/O, memory manipulation, and timer functions critical to the Build Engine's real-time 3D rendering pipeline.

## Core Responsibilities
- Fixed-point arithmetic with variable-bit right shifts (multiply-scale, divide-scale)
- Double and triple multiply-accumulate operations for vector calculations
- VGA mode 13h and mode X (planar) pixel and line drawing
- Video memory operations (copy, fill, clear with alignment optimization)
- Memory buffer swapping and reversing
- Mouse and keyboard hardware interface
- 8253 PIT timer initialization and reading at 1MHz resolution
- Signed/unsigned min/max and utility math operations
- I/O port read/write wrappers

## Key Types / Data Structures
None.

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `dmval` | `long` | static | Holds remainder/quotient result for divmod/moddiv operations |
| `timeroffs1mhz` | `long` | static | Calibration offset for 1MHz timer measurements |

## Key Functions / Methods

### sqr
- Signature: `#pragma aux sqr = "imul eax, eax" parm nomemory [eax] value [eax]`
- Purpose: Square a 32-bit signed integer
- Inputs: `eax` (operand)
- Outputs: `eax` (result)

### mulscale / mulscaleN (N=1–32)
- Signature: `#pragma aux mulscaleN = "imul edx" "shrd eax, edx, N" parm [eax][edx][...] value [eax]`
- Purpose: Fixed-point multiply-scale: `(eax × edx) >> N`
- Inputs: `eax`, `edx` (multiplicands); `ecx` or immediate N (shift bits, except mulscale32)
- Outputs: `eax` (result); `mulscale32` returns in `edx`
- Notes: Core operation for 3D transforms, lighting, and interpolation

### dmulscaleN (N=1–32)
- Signature: `#pragma aux dmulscaleN = [3 imul, add, adc, shrd] parm [eax][edx][esi][edi][...] value [eax]`
- Purpose: Dual multiply-accumulate: `(eax × edx + esi × edi) >> N`
- Inputs: Four multiplicands in eax, edx, esi, edi; shift count in ecx
- Outputs: `eax` (result)
- Notes: Used for weighted sums and bilinear interpolation

### tmulscaleN (N=1–32)
- Signature: `#pragma aux tmulscaleN = [6 registers, 3 imul, cumulative add/adc, shrd] parm [eax][edx][ebx][ecx][esi][edi] value [eax]`
- Purpose: Triple multiply-accumulate: `(eax × edx + ebx × ecx + esi × edi) >> N`
- Inputs: Six multiplicands across register pairs
- Outputs: `eax` (result)

### divscaleN (N=1–32)
- Signature: `#pragma aux divscaleN = [shl eax N, sar edx (32-N), idiv ebx]`
- Purpose: Scaled division: `(eax << N) / ebx`
- Inputs: `eax` (dividend), `ebx` (divisor), `ecx` or immediate N
- Outputs: `eax` (quotient), `edx` (remainder)

### boundmulscale
- Signature: `#pragma aux boundmulscale = [multiply, shrd, overflow detection, clamp]`
- Purpose: Multiply with saturation to int32 range
- Inputs: `eax`, `ebx` (operands); `ecx` (shift bits)
- Outputs: `eax` (clamped result)
- Notes: Prevents overflow in graphics calculations

### drawpixel / drawpixels / drawpixelses
- Signature: `#pragma aux draw... = "mov [byte/word/dword ptr edi], [eax/ax/al]"`
- Purpose: Write to linear or planar video memory
- Inputs: `edi` (address), `eax` (value)

### clearbuf / clearbufbyte, copybuf / copybufbyte
- Purpose: Fill/copy memory with alignment optimization (dword then byte ops)
- Inputs: `edi` (dest/target), `esi` (src), `ecx` (count), `eax` (fill value)
- Notes: Multi-path logic for unaligned buffers

### qinterpolatedown16 / qinterpolatedown16short
- Purpose: Fixed-point linear interpolation for graphics scanlines
- Inputs: `eax` (output ptr), `ecx` (count), `edx` (initial value), `esi` (step)

### limitrate
- Purpose: Synchronize to VGA vertical retrace for frame-rate capping
- Side effects: Blocks until retrace detected via port 0x3da

### inittimer1mhz / gettime1mhz / deltatime1mhz
- Purpose: Initialize, read, and compute deltas on 8253 PIT timer at 1MHz
- Notes: Calibrates timer offset; handles wraparound in 28-bit counter

## Control Flow Notes
Pragmas are called from other translation units; no internal flow. Together they form the low-level substrate for graphics rendering, 3D math, and real-time I/O in the Build Engine.

## External Dependencies
- **Compiler:** Watcom C `#pragma aux` directive
- **Hardware:** x86-32 (80386+), VGA (I/O ports 0x3ce, 0x3da; memory 0xa0000), 8253 PIT, PS/2 mouse (INT 33h), BIOS (INT 10h/5)
- **Symbols defined elsewhere:** None; all inline assembly
