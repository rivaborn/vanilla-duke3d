# SRC/MMULTI.C

## File Purpose
Network multiplayer communication module for the Build engine. Handles packet buffering, transmission, reception, and validation between up to 16 players with CRC error detection and timeout-based packet resending.

## Core Responsibilities
- Initialize multiplayer mode and establish player connectivity graph
- Buffer outgoing packets per player with deduplication
- Batch and transmit packets through a driver interface (via `gcom`)
- Receive, validate, and reassemble incoming packets with CRC16 checks
- Implement reliable delivery via timeout detection and automatic resends
- Manage packet sequencing and error acknowledgment protocol

## Key Types / Data Structures

| Name | Kind | Purpose |
|------|------|---------|
| `gcomtype` | struct | Driver communication buffer; holds packet data, metadata, and command codes for IPC with network driver |

## Global / File-Static State

| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `incnt[MAXPLAYERS]` | long[] | static | Incoming packet sequence counter per player |
| `outcntplc[MAXPLAYERS]` | long[] | static | Outgoing packet placement index (next to send) |
| `outcntend[MAXPLAYERS]` | long[] | static | Outgoing packet end index (next to queue) |
| `errorgotnum[MAXPLAYERS]` | char[] | static | Error ACK counter received from each player |
| `errorfixnum[MAXPLAYERS]` | char[] | static | Error ACK counter we've processed |
| `errorresendnum[MAXPLAYERS]` | char[] | static | Resend request counter per player |
| `crctable[256]` | long[] | global | Pre-computed CRC16 lookup table |
| `bakpacketbuf[BAKSIZ]` | char[] | static | Circular buffer for backup (sent but unACK'd) packets |
| `bakpacketptr[MAXPLAYERS][256]` | short[][] | static | Pointer into `bakpacketbuf` for each queued packet |
| `bakpacketlen[MAXPLAYERS][256]` | short[][] | static | Length of each queued packet |
| `bakpacketplc` | long | static | Current write position in circular backup buffer |
| `lastpacket[576]` | char[] | static | Buffer for second half of split double-packet |
| `inlastpacket` | char | static | Flag: second half of double-packet pending |
| `lastpacketfrom`, `lastpacketleng` | short | static | Source and length of buffered second half |
| `myconnectindex`, `numplayers` | short | global | Local player index and total player count |
| `connecthead`, `connectpoint2[MAXPLAYERS]` | short | global | Linked-list of active player indices |
| `syncstate` | char | global | (Unused flag, purpose not inferable) |
| `timeoutcount`, `resendagaincount` | long | static | Millisecond thresholds for timeout and resend delays |
| `lastsendtime[MAXPLAYERS]` | long[] | static | Last send/retry time per player |
| `gcom` | gcomtype* | static | Pointer to shared driver communication block |

## Key Functions / Methods

### initmultiplayers
- **Signature:** `initmultiplayers(char damultioption, char dacomrateoption, char dapriority)`
- **Purpose:** Initialize multiplayer mode; parse command-line network parameters and set up connectivity.
- **Inputs:** Multi-option code, com-rate option, priority level (parameters stored but not used here).
- **Outputs/Return:** None (void).
- **Side effects:** Initializes `crctable`, resets `incnt`/`outcntplc`/`outcntend`, searches `_argv` for "net" keyword, populates `gcom`, `numplayers`, `myconnectindex`, and `connectpoint2` linked list. If no "net" mode, defaults to single-player.
- **Calls:** `initcrc()`, `strtok()`, `stricmp()`, `atol()`.
- **Notes:** Expects network driver to pass address as `_argv[i+1]`. Initializes per-player state and `lastsendtime[i] = totalclock` for all players.

### initcrc
- **Signature:** `initcrc()`
- **Purpose:** Build CRC16 lookup table using polynomial 0x1021 (ITU standard).
- **Inputs:** None.
- **Outputs/Return:** None (void).
- **Side effects:** Populates global `crctable[256]`.
- **Calls:** None.
- **Notes:** Deterministic; called once at init. Used by `getcrc()` for fast CRC computation.

### setpackettimeout
- **Signature:** `setpackettimeout(long datimeoutcount, long daresendagaincount)`
- **Purpose:** Configure timeout and resend thresholds.
- **Inputs:** New timeout interval (ms), new resend interval (ms).
- **Outputs/Return:** None (void).
- **Side effects:** Updates `timeoutcount`, `resendagaincount`; resets all `lastsendtime[i] = totalclock`.
- **Calls:** None.
- **Notes:** Resynchronizes timers when called.

### getcrc
- **Signature:** `getcrc(char *buffer, short bufleng)`
- **Purpose:** Compute CRC16 checksum of buffer in reverse byte order.
- **Inputs:** Buffer pointer, length.
- **Outputs/Return:** 16-bit CRC value (masked 0xffff).
- **Side effects:** None.
- **Calls:** None (uses macro `updatecrc16` with `crctable`).
- **Notes:** Processes bytes in descending index order.

### callcommit
- **Signature:** `callcommit()`
- **Purpose:** Invoke network driver via interrupt or far call.
- **Inputs:** None (reads `gcom->intnum` and `gcom->longcalladdress`).
- **Outputs/Return:** None (void).
- **Side effects:** Calls driver; driver modifies `gcom` fields.
- **Calls:** `int386()` or `longcall()` (inline asm pragma).
- **Notes:** If `gcom->intnum & 0xff00`, uses 32-bit far call; else standard interrupt.

### sendpacket
- **Signature:** `sendpacket(long other, char *bufptr, long messleng)`
- **Purpose:** Queue an outgoing packet for a destination player.
- **Inputs:** Destination player index, message buffer, message length.
- **Outputs/Return:** None (void).
- **Side effects:** Stores packet in circular `bakpacketbuf`; updates `bakpacketptr[other][]` and `bakpacketlen[other][]`; increments `outcntend[other]`; updates `lastsendtime[other]`; calls `dosendpackets(other)`.
- **Calls:** `dosendpackets()`.
- **Notes:** Deduplicates identical consecutive packets (reuses backup buffer pointer). Returns early if `numplayers < 2`.

### dosendpackets
- **Signature:** `dosendpackets(long other)`
- **Purpose:** Batch and transmit one or two queued packets to a player via driver.
- **Inputs:** Destination player index.
- **Outputs/Return:** None (void).
- **Side effects:** Constructs packet in `gcom->buffer` with header (sequence, ACKs), payload(s), and CRC tail; sets `gcom->other`, `gcom->numbytes`, `gcom->command = 1`; calls `callcommit()`.
- **Calls:** `getcrc()`, `callcommit()`.
- **Notes:** Sends 1 sub-packet if `outcntplc[other]+1 == outcntend[other]`, else 2. Encodes error ACK counters in byte 1. If double-packet, first packet includes length field. Increments `outcntplc[other]` per sub-packet.

### getpacket
- **Signature:** `short getpacket(short *other, char *bufptr)`
- **Purpose:** Retrieve and validate a received packet; handle resend timeouts.
- **Inputs:** Pointer to receive source player index, pointer to output buffer.
- **Outputs/Return:** Message length (0 if no valid packet, or buffered second-half length).
- **Side effects:** Checks all players for timeout; on timeout, increments `errorgotnum[i]` and retriggers `dosendpackets(i)`. If `inlastpacket`, returns buffered second half and clears flag. Otherwise, calls driver (`gcom->command = 2`). Validates CRC, sequence counter (CNT), and error ACK fields; updates `errorfixnum[*other]` and `outcntplc[*other]` based on ACKs. Handles single and double packets; for double, buffers second half in `lastpacket` and returns first half.
- **Calls:** `callcommit()`, `memcpy()`, `getcrc()`, `dosendpackets()`.
- **Notes:** Increments `incnt[*other]` on successful single packet; increments by 2 on double packet. Returns early if `numplayers < 2` or if `inlastpacket`. CNT mismatch tolerance: < 32 packets old = skip silently; >= 32 = error.

### sendlogoff
- **Signature:** `sendlogoff()`
- **Purpose:** Broadcast disconnect notification to all other players.
- **Inputs:** None.
- **Outputs/Return:** None (void).
- **Side effects:** Constructs 2-byte packet (255, myconnectindex) and sends to all players via `sendpacket()`.
- **Calls:** `sendpacket()`.
- **Notes:** Iterates `connectpoint2[]` linked list.

### uninitmultiplayers, sendlogon, getoutputcirclesize, setsocket, flushpackets, genericmultifunction
- **Notes:** Stubs (empty or minimal). `flushpackets()` has commented-out reset logic. `genericmultifunction()` unused by this module.

## Control Flow Notes
**Init sequence:** `initmultiplayers()` → `initcrc()`, set up `gcom` pointer and player list.

**Frame/update loop (implicit in game):**
1. Game calls `sendpacket()` to queue outgoing messages.
2. Game calls `getpacket()` in a loop until no more packets.
3. `getpacket()` internally invokes `dosendpackets()` on timeouts.

**Packet resend:** Handled implicitly in `getpacket()` via `lastsendtime` and timeout counters; game does not explicitly resend.

## External Dependencies
- **Includes:** `<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<dos.h>`, `<process.h>`, `<stdarg.h>`, `"pragmas.h"`
- **External symbols (defined elsewhere):** 
  - `totalclock` (global from game engine) — used for timeout calculation
  - `_argc`, `_argv` (standard C runtime) — command-line parsing
  - `int386()` (DOS interrupt wrapper, likely from runtime)
  - `strtok()`, `stricmp()`, `atol()` (standard C library)
  - `memcpy()` (standard C library)
  - `copybuf()` (defined in pragmas.h, likely asm utility)
  - `min()` (likely macro, standard)
