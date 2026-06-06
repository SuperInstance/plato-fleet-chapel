# Plato Fleet Coordinator — Chapel PGAS Implementation

> *"Write once, run distributed."* — The PGAS promise that Plato's architecture was waiting for.

## The Insight: Why Chapel?

Plato is a distributed room-control system. Each "room" is an autonomous unit — an ESP32 monitoring temperature, humidity, pressure, and motion — coordinated by a fleet manager (typically a Raspberry Pi). The challenge has always been the same: **you think in one program, but you deploy across many nodes.**

Chapel's **PGAS (Partitioned Global Address Space)** model eliminates this mismatch:

| Concept | Plato | Chapel |
|---------|-------|--------|
| Physical device (ESP32, RPi) | Room / Fleet Manager | **Locale** |
| Room sensor state | Ternary (-1, 0, +1) | **Domain maps** over enums |
| Parallel room execution | Concurrent room ticks | **`coforall` over locales** |
| Cross-room alarm signaling | MQTT / HTTP callbacks | **`sync` variables** |
| Fleet-wide coordination | Centralized server | **Single program, multiple locales** |

You write **one program**. Chapel distributes it. Each locale IS a room.

```
// Your code:
coforall loc in Locales {
  on loc {
    engine.tick();  // runs ON that locale, transparently
  }
}
```

No message passing. No serialization. No REST APIs between rooms. Just code that runs where it should.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                  Chapel PGAS Memory                   │
│                                                       │
│  locale 0          locale 1         locale 2          │
│  ┌──────────┐     ┌──────────┐    ┌──────────┐      │
│  │ Bridge   │     │ Engine   │    │ Fish Hold│      │
│  │          │     │ Room     │    │          │      │
│  │ temp     │     │ temp     │    │ temp     │      │
│  │ pressure │     │ humidity │    │ humidity │      │
│  │ battery  │     │ battery  │    │          │      │
│  └────┬─────┘     └────┬─────┘    └────┬─────┘      │
│       │                │               │             │
│  ┌────┴─────┐     ┌────┴─────┐    ┌────┴─────┐      │
│  │ locale 3  │     │ locale 4  │    │           │     │
│  │ Galley   │     │ Deck     │    │           │     │
│  │          │     │          │    │           │     │
│  │ temp     │     │ temp     │    │           │     │
│  │ humidity │     │ humidity │    │           │     │
│  │ motion   │     │ motion   │    │           │     │
│  └──────────┘     │ pressure │    │           │     │
│                    └──────────┘    │           │     │
│                                    │           │     │
│  FleetCoordinator (locale 0)      │           │     │
│  GrooveCoordinator (locale 0)     │           │     │
└──────────────────────────────────────────────────────┘
```

## Locale = Room: The Natural Mapping

In Plato, a "room" is a physical space with sensors. In Chapel, a "locale" is a physical compute unit with memory and processors. This isn't a metaphor — it's the same abstraction.

```chapel
// Each room engine is bound to a locale
var bridgeEngine = new RoomEngine(new RoomID("Bridge", 0, 0));
on Locales[0] do bridgeEngine.tick();  // runs on locale 0

var engineRoom = new RoomEngine(new RoomID("Engine Room", 1, 1));
on Locales[1] do engineRoom.tick();    // runs on locale 1
```

When you run with `-nl 5`, you get 5 locales. Each locale runs one room. The fleet manager coordinates them through PGAS — no middleware, no message brokers.

## Domain Maps = Ternary State

Plato uses ternary state: each sensor reading maps to **below target (-1)**, **nominal (0)**, or **above target (+1)**. This is naturally expressed as a Chapel domain over an enum:

```chapel
enum Trit { below = -1, nominal = 0, above = 1 }
var roomState: [0..#sensorCount] Trit;
```

Domain maps give us:
- **Compact serialization**: Pack 4 trits into 1 byte (2 bits each)
- **Parallel operations**: `coforall` over domain indices
- **Fleet consensus**: Reduce across all locales' domain maps
- **Zero-copy remote access**: PGAS means reading another locale's domain is a hardware operation

## Sync Variables = Alarm Coordination

When the engine room overheats, every other room needs to know. In MQTT/REST architectures, this means publish/subscribe, message queues, and eventual consistency. In Chapel:

```chapel
// In RoomEngine
var alarmActive: sync bool;  // blocks until written

// Engine room sets alarm
on Locales[1] do engineRoom.alarmActive.writeEF(true);

// Fleet coordinator reads (blocks if needed)
if engineRoom.alarmActive.readFF() {
  // Propagate to all locales
}
```

`sync` variables are Chapel's built-in coordination primitive. They're like atomic variables with built-in empty/full semantics. Perfect for alarm propagation — no race conditions, no missed signals.

## Comparison: Chapel vs Others for Plato

| Feature | Chapel (PGAS) | Rust | C | Elixir |
|---------|--------------|------|---|--------|
| **Distributed memory** | Built-in (PGAS) | External (MPI/gRPC) | External (MPI) | Built-in (BEAM) |
| **Write once, run distributed** | ✅ Native | ❌ Manual serialization | ❌ Manual MPI | ⚠️ OTP supervision |
| **Locale = physical node** | ✅ 1:1 mapping | ❌ Manual mapping | ❌ Manual mapping | ⚠️ Node module |
| **Ternary as type** | ✅ Enum with domain | Bitfield | Bitfield | Atom tuple |
| **Parallel room ticks** | `coforall` | rayon/tokio | OpenMP/pthreads | Task.Supervisor |
| **Alarm sync** | `sync` var | Mutex + condvar | pthread_cond | GenServer cast |
| **Single binary deployment** | ✅ | ✅ | ✅ | ❌ (BEAM required) |
| **Learning curve** | Medium | High | High | Medium |
| **Embedded (ESP32)** | ❌ | ⚠️ (no_std) | ✅ | ❌ |
| **Binary size** | ~5MB | ~500KB | ~50KB | ~30MB (BEAM) |
| **Fleet-wide reduce** | Built-in | Manual | Manual | Manual |

**The tradeoff**: Chapel wins on developer experience for distributed coordination. Rust/C win on bare-metal embedded. The ideal Plato deployment uses **Rust/C on ESP32 rooms** and **Chapel on the fleet manager** (RPi or server).

## Fishing Boat Example: F/V Plato

The demo simulates a fishing boat with 5 rooms, each on its own locale:

| Locale | Room | Sensors | Alarms |
|--------|------|---------|--------|
| 0 | Bridge | temperature, pressure, battery | Low Battery, High Temp |
| 1 | Engine Room | temperature, humidity, battery | Overheating, High Humidity |
| 2 | Fish Hold | temperature, humidity | Cold Chain Break, High Temp |
| 3 | Galley | temperature, humidity, motion | Fire Risk |
| 4 | Deck | temperature, humidity, motion, pressure | Storm Pressure, Overheating |

Run the simulation:

```bash
make run
```

Sample output:
```
╔══════════════════════════════════════════════════════╗
║     Plato Fleet Coordinator — Chapel PGAS Demo      ║
║     5-Room Fishing Boat Simulation                  ║
╚══════════════════════════════════════════════════════╝

Locales available: 5
Running simulation on locale 0: locale#0

Fleet configured: 5 rooms registered

>>> Running 50-tick simulation...

--- Tick 10 ---
=== Fleet: F/V Plato (tick 10) ===
Health: 80.0% | Rooms: 5 | Alarms: 0
  Bridge (locale 0, tick 10): health 66.7% - running
  Engine Room (locale 1, tick 10): health 66.7% - running
  Fish Hold (locale 2, tick 10): health 100.0% - running
  Galley (locale 3, tick 10): health 100.0% - running
  Deck (locale 4, tick 10): health 75.0% - running

🎵 Groove Sync: 72.3% (threshold: 65%)
  Bridge (locale 0): phase 0.31, tempo 60.0
  Engine Room (locale 1): phase 0.31, tempo 60.0
  ...
```

### Multi-Locale Execution

With Chapel built for multi-locale (MPI or GASNet):

```bash
# Run on 5 physical nodes
./plato-fleet -nl 5

# Or via MPI
mpirun -np 5 ./plato-fleet -nl 5
```

Each room automatically runs on its designated locale. No configuration changes.

## Project Structure

```
plato-fleet-chapel/
├── Makefile                    — Build targets
├── src/
│   ├── Ternary.chpl            — Ternary (-1/0/+1) pack/unpack, dot product
│   ├── PlatoEngine.chpl        — Room engine (sensors, alarms, ternary state)
│   ├── FleetManager.chpl       — Cross-locale fleet coordination
│   ├── GrooveTracker.chpl      — Music-cognitive sync across locales
│   └── main.chpl               — 5-room fishing boat simulation demo
├── test/
│   └── tests.chpl              — 25 unit + integration tests
├── README.md                   — This file
└── CONFIGURATION_GUIDE.md      — Build and deployment guide
```

## Module Reference

### Ternary.chpl
- `pack(ternary)` / `unpack(packed, count)` — Serialize/deserialize ternary state
- `dotProduct(a, b)` — Ternary vector alignment score
- `toTrit(value, low, high)` — Real → Trit conversion
- `countTrits(ternary)` — Count by type
- `toString(ternary)` — Human-readable (↓·↑)

### PlatoEngine.chpl
- `RoomEngine` — Single-room controller
  - `addSensor(type)` / `updateSensor(idx, value, time)`
  - `addAlarm(name, sensor, threshold, isAbove)`
  - `tick(now)` — Evaluate sensors, update ternary, check alarms
  - `healthScore()` / `getTernaryState()` / `summarize()`

### FleetManager.chpl
- `FleetCoordinator` — Multi-locale orchestrator
  - `registerEngine(engine)` — Add a room to the fleet
  - `fleetTick(now)` — Parallel tick via `coforall`
  - `fleetHealth()` / `alarmRoomCount()` / `fleetConsensus()`
  - `simulate(ticks, feeder)` — Run N-tick simulation

### GrooveTracker.chpl
- `GrooveCoordinator` — Rhythm synchronization
  - `registerRoom(id, locale)` / `updateGroove(idx, state)`
  - `computeSync(a, b)` — Pairwise sync score
  - `fleetSyncScore()` — Fleet-wide rhythm coherence
  - `desyncedRooms()` — Find out-of-sync rooms

## Tests (25 total)

| # | Category | Test |
|---|----------|------|
| 1-3 | Ternary | Trit enum value correctness |
| 4-5 | Ternary | Pack/unpack roundtrip |
| 6 | Ternary | Pack size calculation |
| 7-8 | Ternary | Dot product (identical, opposite, orthogonal) |
| 9-11 | Ternary | toTrit conversion |
| 12 | Ternary | countTrits |
| 13-14 | Engine | Creation and sensor registration |
| 15-16 | Engine | Tick with nominal values |
| 17-19 | Engine | Tick with alarm values, ternary state |
| 20 | Engine | Alarm cooldown |
| 21-22 | Fleet | Engine registration, tick coordination |
| 23-24 | Fleet | Alarm collection, consensus ternary |
| 25-27 | Groove | Creation, update, history |
| 28-29 | Groove | Sync score (identical, opposite) |
| 30 | Groove | Fleet-wide sync |
| 31 | Groove | Desynced room detection |
| 32-35 | Integration | 50-tick simulation, alarm cascade |

```bash
make test
```

## Building & Installation

### Option 1: Pre-built Binary (Recommended)

```bash
# Download from https://github.com/chapel-lang/chapel/releases
wget https://github.com/chapel-lang/chapel/releases/download/2.3.0/chapel-2.3.0.tar.gz
tar xzf chapel-2.3.0.tar.gz
cd chapel-2.3.0
source util/setchplenv.bash  # or .fish for fish shell
make
make check
```

### Option 2: From Source

```bash
git clone https://github.com/chapel-lang/chapel.git
cd chapel
source util/setchplenv.bash
make -j$(nproc)
make check
```

### Option 3: Package Manager

```bash
# macOS
brew install chapel

# Some Linux distros may have it in package repos
# Otherwise, use Option 1 or 2
```

### Multi-Locale (for actual distributed execution)

For running across multiple physical nodes, build Chapel with a communication layer:

```bash
# GASNet (recommended for Ethernet clusters)
export CHPL_COMM=gasnet
export CHPL_COMM_SUBSTRATE=udp  # or ibv for InfiniBand, smp for single node

# MPI (alternative)
export CHPL_COMM=mpi

# Then build Chapel and this project normally
make clean && make
```

### Building Plato Fleet

```bash
cd plato-fleet-chapel
make          # build simulation
make test     # run tests
make run      # run 5-room demo
```

## The PGAS Mental Model

If you're coming from message-passing (MPI, gRPC, MQTT), PGAS requires a mindset shift:

**Message Passing (what you're used to):**
```
Room A: serialize state → send over network → Room B receives → deserialize
```

**PGAS (what Chapel gives you):**
```
Room A: write to shared variable
Room B: read from shared variable
(Chapel handles the network transfer transparently)
```

The variable `bridgeEngine.sensors[0].value` lives on locale 0's memory. When locale 1 reads it, Chapel issues a remote GET. When locale 0 writes it, Chapel may invalidate caches on other locales. You never think about this.

This is why Plato + Chapel is powerful: the fleet coordinator reads all room states as if they're local arrays. The underlying runtime handles the fact that they're spread across ESP32s, RPis, or cloud VMs.

## Limitations & Practical Notes

1. **ESP32 can't run Chapel** — Use Rust/C on microcontrollers, Chapel on the fleet manager
2. **Single-node demo** — Without multi-locale Chapel, everything runs on one node (but code is structured for distribution)
3. **Startup time** — Chapel programs have a few-second startup for locale initialization
4. **Garbage collection** — Chapel is GC'd; not suitable for hard real-time (<1ms) loops
5. **Community size** — Chapel has a smaller ecosystem than Rust/Go

The sweet spot: **Chapel on the coordinator (RPi 4+), Rust/C on the edge (ESP32)**. Chapel handles fleet logic; Rust handles sensor I/O. They communicate over serial/WiFi with the compact ternary packing format defined in `Ternary.chpl`.

## License

MIT

## Related

- [Plato Room Engine (Rust)](https://github.com/SuperInstance/plato-room) — ESP32 room controller
- [Plato Fleet (Elixir)](https://github.com/SuperInstance/plato-fleet) — Original fleet coordinator
- [Chapel Language](https://chapel-lang.org/) — PGAS programming language
- [PGAS Model](https://en.wikipedia.org/wiki/Partitioned_global_address_space) — Background on the memory model
