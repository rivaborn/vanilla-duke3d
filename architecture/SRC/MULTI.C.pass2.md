# SRC/MULTI.C — Enhanced Analysis

## Architectural Role

MULTI.C implements the transport layer for the Build Engine's multiplayer subsystem, providing both serial COM and IPX network drivers. It sits at the boundary between protected-mode game logic and real-mode DOS hardware (UART, IPX driver), managing interrupt handlers and low-memory buffers. The file works in tandem with MMULTI.C (which adds packet validation and retransmission logic on top) to enable deterministic up-to-16-player synchronous gameplay. The core responsibility is **establishing and maintaining hardware-level connections**, while MMULTI.C handles **application-level reliability**.

## Key Cross-References

### Incoming (who depends on this file)
- **Game loop**: Calls `initmultiplayers()` at startup, `getpacket()`/`sendpacket()` per frame, `uninitmultiplayers()` at shutdown (game code not shown, but architecture implies)
- **MMULTI.C**: Wraps `sendpacket()` / `getpacket()` with retransmission and CRC validation; calls `initmultiplayers()` and `initcrc()`
- **BUILD.C**: May call `initmultiplayers()` or delegate to MMULTI.C setup
- Global symbols exported: `numplayers`, `myconnectindex`, `connecthead`, `connectpoint2[]`, `syncstate`, `hangup` (read/written by game state machine)

### Outgoing (what this file depends on)
- **DOS/DPMI**: `int386()` / `int386x()` (DPMI calls 0x31 for memory allocation and interrupt simulation; 0x7a for IPX; 0x2f for driver detection)
- **Hardware**: UART I/O (ports 0x3f8, 0x2f8, 0x3e8, 0x2e8), PIC interrupt controller (0x20, 0x21)
- **Watcom runtime**: `_disable()`, `_enable()` (CPU interrupt masking); port I/O pragmas `koutp()`, `kinp()`; `memcpy()`, `memset()` standard library
- **Low-memory allocation**: `convalloc32()` calls DPMI to allocate conventional memory (needed because DOS/IPX drivers and interrupt handlers must run in real mode and access low memory)
- **CRC engine**: `initcrc()` pre-computes lookup table; `getcrc()` (defined in MMULTI.C) uses it

## Design Patterns & Rationale

### 1. **Real-Mode Code Injection (Assembly-in-Data)**
   - **Pattern**: `rmbuffer` (384 bytes of x86 opcodes) + `rmnetbuffer` (384 bytes) embedded as char arrays; copied to low memory at runtime and executed as interrupt handlers
   - **Why**: DOS interrupts (especially serial UART IRQ, IPX callback) **must run in real mode**. Protected-mode interrupt handlers cannot directly access hardware ports or call DOS/BIOS. Solution: allocate low-memory buffer, copy pre-assembled x86 code, install segment:offset into interrupt table
   - **Trade-off**: Fragile to relocation (hardcoded addresses in copied code), but necessary for hardware-level interrupt servicing in DOS/DPMI environment

### 2. **Volatile Shared Memory Between ISR and Main Thread**
   - **Pattern**: `volatile` pointers (`inbuf`, `outbuf`, `inbufplc`, `outbufplc`, `comerror`, `comresend`) shared between `comhandler()` interrupt handler and main-thread functions (`getpacket()`, `sendpacket()`, `startcom()`)
   - **Why**: No thread-safe synchronization primitive (mutexes, semaphores) available in DOS; volatile prevents compiler optimizations that would break shared-memory assumptions
   - **Trade-off**: Race conditions possible (e.g., main thread checks `*outbufend` while ISR modifies `*outbufplc`), but single-CPU DOS environment makes truly concurrent access unlikely; pragmatic for era

### 3. **Dual-Mode Support (COM + IPX)**
   - **Pattern**: `initmultiplayers()` branches on `multioption` (1–4 → COM1–COM4; ≥5 → IPX); `sendpacket()` / `getpacket()` demultiplex via global `multioption`
   - **Why**: COM ports dominated early 1990s; IPX/NetWare was enterprise networking. Engine supports both for maximum compatibility across hardware configs and network topologies
   - **Trade-off**: Code bloat, dual initialization logic, harder to maintain; no abstraction layer (hard-coded mode checks everywhere)

### 4. **DOS Memory Hierarchy**
   - **Pattern**: `convalloc32()` allocates DOS conventional memory (below 1 MB) via DPMI; used for interrupt handler code + I/O buffers
   - **Why**: Real-mode code and DMA-capable hardware (UART, IPX card) **require** low-memory addresses (segment:offset model). Extended/protected memory can't be addressed by real-mode code
   - **Trade-off**: Limited conventional memory pool (typically ~600 KB free after DOS/TSRs); must carefully size buffers (`COMBUFSIZ=16384`, `NETCODEBYTES=384`)

### 5. **Circular Ring Buffers for I/O**
   - **Pattern**: `inbuf[]` / `outbuf[]` with wrapped pointers (`inbufplc`, `inbufend`, etc.); masking with `(COMBUFSIZ-1)` for cheap modulo
   - **Why**: Allows interrupt handler to continuously produce/consume without blocking; no malloc/free in ISR (forbidden in DOS)
   - **Trade-off**: Fixed size limits throughput; wraparound logic error-prone; no backpressure (overflow silently drops data in IPX mode)

### 6. **Connection List as Sorted Array + Linked List Hybrid**
   - **Pattern**: `connectnum[16]` and `compaddr[16][]` arrays (sorted by connectnum); `connecthead` + `connectpoint2[]` rebuilt on each join (via `netinitconnection()`)
   - **Why**: Deterministic topology across all peers (sorted order ensures same `myconnectindex` on each PC); linked list for fast traversal; array for direct lookup
   - **Trade-off**: `netinitconnection()` is O(n) with full array rebuild; doesn't scale beyond 16 players; no remove operation (only uninitialized disconnect)

## Data Flow Through This File

```
[Game Loop]
    ↓ initmultiplayers(mode, baud, priority)
    ├─→ [COM mode] comon() → installbicomhandlers() → copies rmbuffer to low memory, installs ISR
    └─→ [IPX mode] neton() → allocates low-memory ECB/IPX buffers, installs fake INT 0x7a, listens on socket

[Game Loop per-frame]
    ↓ sendpacket(otherindex, bufptr, messleng)
    ├─→ [COM] comsend(ch) → outbuf[...] → startcom() primes ISR
    └─→ [IPX] netsend() → ecbput ECB → IPX driver via simulateint(0x7a)
    
    ↓ getpacket(&otherindex, bufptr)
    ├─→ [COM] reads inbuf[...] (filled by comhandler ISR) → CRC check → may set comerror/comresend
    └─→ [IPX] reads netinbuf[...] (filled by rmnethandler callback) → bundles sub-packets → CRC check

[Hardware level]
    [UART IRQ] → comhandler() ISR → reads UART status, drains FIFO → inbuf[] or outbuf[] pump
    [IPX callback] → rmnethandler (real-mode asm) → enqueues netinbuf[] → game reads async

[Game shutdown]
    ↓ uninitmultiplayers()
    ├─→ [COM] comoff() → waits for outbuf drain → masks IRQ → restores old handlers
    └─→ [IPX] netoff() → closes socket via simulateint(0x7a)
```

## Learning Notes

### Idioms Specific to DOS/Early 1990s Game Engines
1. **No OS abstractions**: No kernel event loops, threads, or memory protection; game owns interrupt handlers directly
2. **Real-mode/Protected-mode boundary**: DPMI (32-bit protected mode with DOS compatibility) requires careful marshalling of data across modes; assembly stubs in low memory are the glue
3. **Hardware interrupts as primary I/O**: No buffering or kernel drivers; application directly services UART/serial; forces ISR to be minimal (no printf, no malloc)
4. **Deterministic network topology**: No concept of "leader election" or distributed consensus; players sorted by 32-bit ID, all derive same `myconnectindex` independently
5. **Fixed-size buffers**: No dynamic allocation; game must pre-size multiplayer for 16 players max
6. **x86 segment:offset addressing**: Real-mode code uses 16-bit segment + 16-bit offset; low-memory allocation crucial; 20-bit address space limit (1 MB conventional)
7. **Single-threaded but interrupt-driven**: Game loop runs in "main" CPU context; ISR runs in separate context; volatile globals + spinlocking (e.g., waiting for `*outbufend` to drain) avoid true locking

### Modern Contrasts
- Modern engines: async I/O (sockets), kernel-provided network stacks (TCP/IP), memory protection (no direct hardware access), pre-emptive multithreading (mutex-based synchronization)
- This engine: synchronous blocking I/O, application-level protocol, bare-metal hardware, cooperative interrupt handling

### Game Engine Concepts Not Yet Present in MULTI.C Alone
- **Reliability layer** (retransmission, acks): delegated to MMULTI.C; MULTI.C only handles framing
- **Game state synchronization**: likely in game-level code (not MULTI.C)
- **Latency compensation / rollback**: not visible in network layer

## Potential Issues

1. **Buffer Overflow / Ring Wraparound Edge Case**: If `inbufend` wraps to 0 while `inbufplc` is at position 16383, and main thread reads at same time as ISR writes, boundary condition not guarded by locks. Could corrupt packet boundaries.

2. **Interrupt Handler Overhead**: `comhandler` is called for **every** UART interrupt; if FIFO is small (8250 = 1 byte) at high baud rate (28800), interrupt frequency is very high. Under load, might lose context-switch time to ISR overhead.

3. **IPX Callback Race**: `rmnethandler` callback runs asynchronously when IPX packet arrives; no synchronization with main-thread `getpacket()` reads of `netinbuf[]`. Could drop packets or read partial data if timing is unlucky.

4. **No Error Recovery for Dropped Packets**: MULTI.C doesn't retransmit; relies on MMULTI.C layer. But if outbuf overflows or netinbuf fills, frames are silently lost. Application must detect and recover at protocol level.

5. **Hard-Coded Addresses & Interrupt Vectors**: Serial port addresses (0x3f8, 0x2f8, etc.) and IRQ vectors (0x08, 0x09, 0x0b, 0x0c) are hard-coded. Modern hardware may not match or may conflict with legacy device drivers (USB serial emulation, PCI UART).

6. **Fake INT 0x7a Installation**: If IPX driver is missing, code installs a fake INT 0x7a handler by directly manipulating the interrupt table. This is fragile and could be clobbered by other code; no validation that installation succeeded before use.
