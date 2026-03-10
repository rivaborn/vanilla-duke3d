# SRC/MULTI.C

## File Purpose
Multiplayer communication subsystem for the Build Engine, supporting both serial COM port connections and IPX network transport. Manages player connections, packet synchronization, and connection state across up to 16 players.

## Core Responsibilities
- Initialize/deinitialize COM and IPX network modes via `initmultiplayers()` / `uninitmultiplayers()`
- Manage player connection list and linked-list topology via `netinitconnection()` / `netuninitconnection()`
- Send outbound packets with framing, CRC, and retransmission via `sendpacket()` / `netsend()` / `comsend()`
- Receive and validate inbound packets, detecting errors and resending via `getpacket()` / COM interrupt handler
- Install/restore interrupt handlers for serial port via `installbicomhandlers()` / `uninstallbicomhandlers()`
- Simulate DOS/DPMI real-mode interrupts (0x7a IPX, 0x2f driver checks, 0x31 DPMI) via `simulateint()`
- Calculate and validate CRC-16 checksums via `initcrc()` / `getcrc()` for error detection

## Key Types / Data Structures
| Name | Kind | Purpose |
|------|------|---------|
| `rminfo` | struct | Real-mode register state for DPMI interrupt simulation (EAX–SS, flags) |
| `rmbuffer` | char[] (384 bytes) | Real-mode COM port interrupt handler code (x86 assembly in data) |
| `rmnetbuffer` | char[] (384 bytes) | Real-mode IPX handler callback stub (x86 assembly in data) |

## Global / File-Static State
| Name | Type | Scope | Purpose |
|------|------|-------|---------|
| `syncstate` | char | global | Sync error counter incremented when packet parsing fails |
| `hangup` | char | global | Controls modem control line handling on COM shutdown |
| `multioption` | char | static | 1–4 for COM1–COM4, ≥5 for IPX; 0 = disabled |
| `comrateoption` | char | static | Baud rate selection (low nibble) and interrupt vector (high nibble) |
| `numplayers` | short | global | Current player count (includes self) |
| `myconnectindex` | short | global | Local player's index in connection list [0..15] |
| `connecthead` | short | global | Head of linked-list of connected players |
| `connectpoint2[16]` | short[] | global | Next-player pointers; -1 = end of list |
| `myconnectnum` | long | global | Local player's 32-bit ID (from priority + random + network address) |
| `otherconnectnum` | long | global | Remote player's connect number (COM mode only) |
| `mypriority` | long | global | Tiebreaker priority for master selection in protocol |
| `crctable[256]` | long[] | global | Precomputed CRC-16 lookup table (CCITT poly 0x1021) |
| `comnum` | long | global | Serial port number (1–4) when COM mode active |
| `comvect` | long | global | Interrupt vector (DOS IRQ offset for COM) |
| `comspeed` | long | global | Baud rate in bits/sec (2400–115200) |
| `inbuf, outbuf` | volatile char* | static | Low-memory circular buffers for COM I/O (COMBUFSIZ=16384 bytes) |
| `incnt, outbufplc, outbufend` | volatile short/char* | static | Ring buffer pointers and counters |
| `comerror, comresend` | volatile char* | static | Error/resend state flags for COM protocol |
| `socket` | short | global | IPX socket number (0x4949 default) |
| `compaddr[16][12]` | char[][] | global | 10-byte network address + 2-byte socket for each player |
| `mycompaddr[12]` | char[] | global | Local network address |
| `netincnt[16], netoutcnt[16]` | char[] | global | Per-player input/output packet sequence numbers (IPX mode) |
| `omessout[16][4][546]` | char[][][] | global | Outbound message FIFO (4 packets/player, max 546 bytes IPX) |
| `omessleng[16][4], omessconnectindex[16][4]` | short[][] | global | Metadata for queued packets |
| `rmoffset32, rmsegment16` | long | global | Allocated low-memory DOS buffer address and paragraph segment |
| `my7a` | long | static | Allocated memory for fake INT 0x7a handler (if IPX not present) |

## Key Functions / Methods

### initmultiplayers
- **Signature:** `initmultiplayers(char damultioption, char dacomrateoption, char dapriority)`
- **Purpose:** Initialize multiplayer subsystem; select COM or IPX mode and set parameters
- **Inputs:** `damultioption` (1–4 = COM1–COM4, ≥5 = IPX); `dacomrateoption` (baud rate + IRQ); `dapriority` (connection tie-breaker)
- **Outputs/Return:** None (void)
- **Side effects:** Calls `initcrc()`, then either `comon()` or `neton()` based on mode; sets global connection state
- **Calls:** `initcrc()`, `comon()`, `neton()`
- **Notes:** Sets `numplayers=1` at end; does not send logon packet

### neton
- **Signature:** `neton(void)`
- **Purpose:** Initialize IPX/NetWare network driver and allocate low-memory real-mode handlers
- **Inputs:** None
- **Outputs/Return:** 0 on success; -1 if IPX driver not found; -2 if socket open failed
- **Side effects:** Allocates ~2KB low-memory via `convalloc32()`; installs fake INT 0x7a if needed; sets up IPX ECB (event control blocks) and DMA buffers; calls `simulateint(0x7a)` to query driver and open socket
- **Calls:** `simulateint()`, `convalloc32()`, `netinitconnection()`, `memcpy()`
- **Notes:** Derives `myconnectnum` from network address + priority; initializes receive ECB for listening; calls `netinitconnection()` for self

### comon
- **Signature:** `comon(void)`
- **Purpose:** Initialize serial COM port with interrupt handler, UART settings, and circular buffers
- **Inputs:** None (uses global `comnum`, `comspeed`, `comvect`)
- **Outputs/Return:** -1 on invalid com port or speed; 0 on success
- **Side effects:** Allocates UART interrupt handler via `installbicomhandlers()`; sets baud rate, parity, stop bits; flushes UART FIFO; unmasks interrupt; initializes ring buffers
- **Calls:** `installbicomhandlers()`, `koutp()` (out), `kinp()` (in), `_disable()`, `_enable()`
- **Notes:** Detects 16550A FIFO (sets `*comtype=16` if present); falls back to 8250 (1-byte FIFO)

### sendpacket
- **Signature:** `sendpacket(short otherconnectindex, char *bufptr, short messleng)`
- **Purpose:** Queue an outbound packet for transmission via COM or IPX
- **Inputs:** `otherconnectindex` (destination player index or -1 for broadcast); `bufptr` (message data); `messleng` (message length in bytes)
- **Outputs/Return:** None (void)
- **Side effects:** 
  - COM mode: Writes to `outbuf` ring buffer, increments `outcnt`, calls `startcom()` to kick transmission; adds header byte + CRC (if enabled)
  - IPX mode: Queues packet in `omessout` FIFO with retransmission logic; bundles last 4 sent packets per receiver; calls `netsend()`
- **Calls:** `comsend()`, `startcom()`, `netsend()`, `getcrc()`
- **Notes:** Special handling for reserved messages (0xc0–0xff); IPX mode allows retransmission via ACK-based sequence numbers

### getpacket
- **Signature:** `short getpacket(short *otherconnectindex, char *bufptr)`
- **Purpose:** Dequeue and validate an inbound packet, detecting errors and requesting retransmission
- **Inputs:** `otherconnectindex` (output: sender's player index); `bufptr` (output: message data)
- **Outputs/Return:** Message length (0–546 bytes) on success; 0 if no packet available or reserved message consumed
- **Side effects:**
  - COM mode: Reads from `inbuf` ring buffer; increments `*incnt` on valid packet; sets error flags (`*comerror`, `*comresend`) if CRC or sequence error detected
  - IPX mode: Reads from `netinbufplc`; processes up to 4 sub-packets per IPX packet; updates `netincnt` per sender
- **Calls:** `getcrc()`, `updatecrc16()` (macro), `processreservedmessage()`
- **Notes:** Escape-byte handling for COM (0x83/0x8f); reserved messages (≥200) trigger `processreservedmessage()` and not returned to caller unless ≤ 2 bytes

### comhandler
- **Signature:** `void interrupt far comhandler(void)`
- **Purpose:** x86 interrupt handler for COM UART (IRQ 3 or 4); service transmit/receive FIFO
- **Inputs:** None (reads from UART status/data ports)
- **Outputs/Return:** None (interrupt-driven)
- **Side effects:** 
  - Reads UART interrupt ID register (`*comport+2`)
  - If transmit (ID=2): Drain up to `*comtype` bytes from `outbuf` ring; service resend/error flags
  - If receive (ID=4): Drain up to `*comtype` bytes from UART into `inbuf` ring
  - EOI (end-of-interrupt) to PIC (0x20)
- **Calls:** `koutp()`, `kinp()`
- **Notes:** Volatile globals (`inbufend`, `outbufplc`, etc.) shared with main thread; may loop if more interrupts pending

### installbicomhandlers
- **Signature:** `installbicomhandlers(void)`
- **Purpose:** Replace protected-mode and real-mode interrupt vectors with custom COM handler
- **Inputs:** None (uses global `comvect`)
- **Outputs/Return:** None (void)
- **Side effects:** 
  - Allocates low-memory DOS buffer for real-mode handler code + buffers via `convalloc32()`
  - Saves old interrupt vectors (`orig_pm_sel`, `orig_pm_off`, `orig_rm_seg`, `orig_rm_off`)
  - Copies `rmbuffer` (x86 asm) into low memory at offset COMCODEOFFS
  - Installs `comhandler()` as protected-mode vector and real-mode trampoline
- **Calls:** `convalloc32()`, `int386x()`, `memcpy()`
- **Notes:** Uses DPMI calls 0x35xx (get vector), 0x25xx (set vector), 0x0200/0x0201 (real-mode vector)

### netinitconnection
- **Signature:** `long netinitconnection(long newconnectnum, char *newcompaddr)`
- **Purpose:** Add a new remote player to the connection list, maintaining sorted order
- **Inputs:** `newconnectnum` (32-bit player ID); `newcompaddr` (10-byte network address)
- **Outputs/Return:** -1 if duplicate or no space; 1 if added
- **Side effects:** 
  - Increments `numplayers`
  - Sorts `connectnum[]` and `compaddr[]` by connect number
  - Rebuilds `connecthead` and `connectpoint2[]` linked list
  - Sets `myconnectindex` if `newconnectnum == myconnectnum`
- **Calls:** None
- **Notes:** Maintains deterministic order across all peers for connection list topology

### processreservedmessage
- **Signature:** `processreservedmessage(short tempbufleng, char *datempbuf)`
- **Purpose:** Handle login/logoff and connection synchronization messages (253–255)
- **Inputs:** `tempbufleng` (message length); `datempbuf` (message data, first byte is type)
- **Outputs/Return:** None (void)
- **Side effects:**
  - Type 253 (login): Extracts remote `myconnectnum`; responds with type 254; calls `netinitconnection()` to add remote; broadcasts peer list if this player is master
  - Type 254 (login response): Adds all listed peers via `netinitconnection()`
  - Type 255 (logoff): Calls `netuninitconnection()` to remove peer
- **Calls:** `netinitconnection()`, `netuninitconnection()`, `sendpacket()`
- **Notes:** IPX mode: encodes `connectnum` + 10-byte address per peer in type 254

### initcrc
- **Signature:** `initcrc(void)`
- **Purpose:** Pre-compute CRC-16-CCITT lookup table for fast packet validation
- **Inputs:** None
- **Outputs/Return:** None (void)
- **Side effects:** Fills global `crctable[256]` using polynomial 0x1021
- **Calls:** None
- **Notes:** Called once at startup; used by `getcrc()` and `updatecrc16()` macro

### convalloc32
- **Signature:** `long convalloc32(long size)`
- **Purpose:** Allocate conventional (low) DOS memory via DPMI call 0x0100
- **Inputs:** `size` (bytes to allocate)
- **Outputs/Return:** 32-bit linear address (paragraph << 4) on success; 0 on failure
- **Side effects:** Calls DPMI int 0x31
- **Calls:** `int386()`
- **Notes:** Needed for real-mode interrupt handlers and IPX/DMA buffers

### simulateint
- **Signature:** `long simulateint(char intnum, long daeax, ..., long daedi)`
- **Purpose:** Execute a real-mode DOS interrupt from protected mode (DPMI 0x0300)
- **Inputs:** DOS interrupt number; x86 register values (EAX, EBX, ECX, EDX, ESI, EDI)
- **Outputs/Return:** Return value in EAX
- **Side effects:** Calls DPMI int 0x31 to switch to real mode, execute interrupt, switch back
- **Calls:** `int386x()`, `fixregistersaftersimulate()` (inline pragma)
- **Notes:** Adjusts ESI/EDI to account for `rmoffset32` DOS base; used for IPX (0x7a), int 0x2f checks

## Control Flow Notes
**Initialization Phase:**
1. Engine calls `initmultiplayers(mode, baud/irq, priority)`
2. If COM mode (1–4): `comon()` → `installbicomhandlers()` installs interrupt handler
3. If NET mode (≥5): `neton()` → allocates low-memory buffers → sends logon via `sendlogon()`
4. Peers respond with type 254 and exchange topology via `processreservedmessage()` → `netinitconnection()`

**Game Loop (frame-level):**
- Game engine calls `getpacket()` repeatedly to drain incoming messages
- Game engine calls `sendpacket()` to queue outbound messages
- COM mode: `getpacket()` reads `inbuf` (filled by interrupt handler); `sendpacket()` writes `outbuf` (drained by `comhandler`)
- IPX mode: `getpacket()` reads `netinbuf` (filled by `rmnethandler` callback); `sendpacket()` queues `omessout` (sent via `netsend()` → IPX driver)

**Shutdown Phase:**
1. Engine calls `sendlogoff()` to broadcast type 255 messages
2. Engine calls `uninitmultiplayers()` → `comoff()` or `netoff()`
3. `comoff()`: waits for `outbuf` to drain; masks interrupt; restores old handlers
4. `netoff()`: closes socket via `simulateint(0x7a, 0x1, ...)`

## External Dependencies
- **Includes:** `<stdio.h>`, `<stdlib.h>`, `<string.h>`, `<dos.h>`, `<i86.h>` (Watcom C DOS/x86 headers)
- **DPMI/DOS calls:** INT 0x31 (DPMI), INT 0x21 (DOS generic), INT 0x2f (driver check), INT 0x7a (IPX/NetWare)
- **Real-mode code:** `rmbuffer` (COM handler asm), `rmnetbuffer` (IPX callback asm) embedded in data
- **External symbols (assumed defined elsewhere):**
  - `int386()`, `int386x()` — Watcom DPMI interrupt simulation
  - `_disable()`, `_enable()` — CPU interrupt enable/disable
  - `koutp()`, `kinp()` — Port I/O pragmas (inline x86 OUT/IN)
  - `processreservedmessage()` — Defined in this file; may call game-level handlers
  - `memcpy()` — Standard library
- **Hardware accessed:** Serial UART (3F8, 2F8, 3E8, 2E8), PIC interrupt controller (0x20, 0x21), BIOS data area (0x400)
