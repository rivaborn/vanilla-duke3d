# SRC/MMULTI.C — Enhanced Analysis

## Architectural Role

MMULTI.C implements the **modem transport layer** for the Build engine's multiplayer protocol, providing a parallel implementation to MULTI.C (which handles serial COM and IPX). This file bridges the game engine and a low-level network driver, implementing reliable datagram delivery with CRC-16 validation, timeout-based packet retransmission, and deduplication. It enforces strict ordering guarantees for up to 16 players by managing per-player send/receive queues and ACK state machines embedded in packet headers.

## Key Cross-References

### Incoming (who depends on this file)
- **Game engine** (BUILD.C or game main loop): calls `initmultiplayers()`, `sendpacket()`, `getpacket()`, `sendlogoff()`, `setpackettimeout()` 
- **Timing subsystem** (ENGINE.C or game loop): provides `totalclock` global used for timeout detection and resend triggers
- **Editor/setup** (BSTUB.C, SETUP.C, etc.): may initialize multiplayer mode via command-line parsing

### Outgoing (what this file depends on)
- **Network driver** (DOS interrupt/far-call interface): `callcommit()` invokes driver via `gcom` structure with INT or 32-bit far call
- **Game timing**: reads `totalclock` to compute elapsed time since last send
- **Standard C library**: `memcpy()`, `strtok()`, `stricmp()`, `atol()`
- **PRAGMAS.H utilities**: `copybuf()` for bulk memory copy
- **Command-line parsing**: reads `_argc`, `_argv` to extract network driver address ("net" keyword)

## Design Patterns & Rationale

**Reliable datagram protocol with circular packet buffer:**
- `bakpacketbuf[BAKSIZ]` is a **16 KB circular ring buffer** holding all unack'd packets per player
- `bakpacketptr[][]` and `bakpacketlen[][]` index into this buffer, keyed by player and packet sequence (modulo 256)
- Rationale: Modem links (2400–56k baud) have high latency and packet loss; buffering unack'd data enables retransmission without game-engine involvement

**Timeout-based retransmission (not ACK-driven):**
- `getpacket()` scans all players for `totalclock > lastsendtime[i] + timeoutcount`
- On timeout, increments `errorgotnum[i]` and re-queues the packet (by decrementing `outcntplc[i]`)
- Rationale: Simpler than maintaining ACK timers; suits modem latency (hundreds of ms typical)

**Double-packet batching optimization:**
- If two packets are queued (`outcntplc + 1 < outcntend`), both are serialized into one transmission
- First packet includes length; receiver splits them back apart
- Rationale: Reduces modem overhead for bursty game state (position updates, weapon fire, etc.)

**Error ACK counters in header:**
- `errorgotnum[]`, `errorfixnum[]`, `errorresendnum[]` track error events per player
- Header byte 1 encodes these; allows receiver to infer which error packets were lost
- Rationale: Avoids needing separate ACK packets; piggybacks on game data

**CRC-16 lookup table:**
- `initcrc()` pre-computes 256-entry lookup table using polynomial 0x1021 (ITU standard)
- Fast O(N) CRC computation without bit-by-bit shifts
- Rationale: Modem-era error detection; matches Hayes AT command set and XMODEM protocols

## Data Flow Through This File

```
Outgoing:
  Game → sendpacket(player, buf, len)
    → Copy to bakpacketbuf[] (dedup check against last packet)
    → Increment outcntend[]
    → dosendpackets()
      → Build header (seq, ACKs, payload)
      → Compute CRC-16
      → Driver (gcom + callcommit)
      → Network

Incoming:
  Network → Driver → getpacket()
    → Check timeouts, retransmit stale packets
    → If inlastpacket set, return buffered 2nd half
    → Else, fetch from driver (gcom)
    → Validate CRC, sequence counter, ACKs
    → Handle single or double packet
    → Update incnt[], outcntplc[] (ACK processing)
    → Return message to game
```

**State machines:**
- Per-player: `incnt[]` (sequence received), `outcntplc/outcntend` (send queue bounds), `errorgot/errorfixnum/errorresendnum` (ACK state)
- Global: `inlastpacket`, `lastpacketfrom`, `lastpacketleng` (split double-packet reassembly)

## Learning Notes

**What this file teaches about 1990s game networking:**
- **Modem-era constraints**: 2400–56k baud, high latency (500+ ms possible), packet loss ~1–5%. Solution: in-game retransmission, not transport-layer.
- **No framing protocol**: Game data is raw; driver is responsible for byte-level framing (likely serial/CRC-based).
- **Strict ordering assumption**: Packets must arrive in order (checked via `incnt[*other]` counter); double-packet assembly breaks if out-of-order.
- **Deduplication heuristic**: Only checks the immediately-previous packet. Assumes modern retransmit is rare—does not cache full history.
- **Precomputed lookup tables**: Both CRC and (likely) sound synthesis use 256-entry tables—memory was scarce; CPU speed made iteration attractive.

**Contrasts with modern engines:**
- Modern engines use UDP/TCP stacks, not custom protocols.
- Modern engines separate **transport** (TCP, QUIC) from **game protocol** (serialization, compression).
- This file conflates both: CRC, sequence numbers, retransmit are transport; message format is ad-hoc.
- No concept of **congestion control** or **bandwidth adaptation**—sends on demand.

**Idiomatic patterns:**
- **Macro-heavy inline assembly** (pragmas.h utilities, `updatecrc16` macro)
- **Global state dominates** (no encapsulation; `gcom` is a shared structure pointer)
- **DOS interrupt model**: `callcommit()` delegates to driver via INT or far call; typical for 1990s device drivers.
- **Bit-packing in headers**: ACK counters encoded in 3-bit fields (byte 1: `(errorgot&7) | ((errorresend&7)<<3)`)

## Potential Issues

1. **Circular buffer overflow:** If `bakpacketplc` wraps but unack'd packets are still buffered, newer packets will overwrite old ones. No explicit overflow check.

2. **Double-packet reassembly deadlock:** If `inlastpacket` is set but the second packet is never received (player timeout or crash), the game can stall waiting for it. No timeout mechanism clears this flag.

3. **Sequence counter wrap:** `incnt[]`, `outcntplc/outcntend` wrap at 256. If packets are buffered >256 deep, modular arithmetic can cause collisions. Code assumes 256 is large enough for typical modem RTT.

4. **Timeout wrap-around:** If `totalclock` wraps (32-bit signed long, ~24 days at 120 Hz), `getpacket()` comparison `totalclock > lastsendtime[i] + timeoutcount` may misfire. Partially mitigated by resetting `lastsendtime[]` on timeout.

5. **Deduplication is weak:** `sendpacket()` only compares against the immediately-previous packet in the queue (lines 189–193). If the game queues identical packets with other packets in between, deduplication fails—leading to duplicate sends and ACK confusion.

6. **No keep-alive:** If the game doesn't call `getpacket()` regularly, timeouts won't trigger and packets won't be resent. Silent stall risk.

7. **Disconnect handling unclear:** `syncstate` flag is declared but never set or checked in this file. Connection drop detection likely happens in game layer, not here.

---

**Sources referenced:**
- SRC/MULTI.C (parallel serial/IPX implementation)
- SRC/ENGINE.C (totalclock source)
- PRAGMAS.H (copybuf, math macros)
- Architecture context sections on Multiplayer & Networking, Core Rendering Engine
