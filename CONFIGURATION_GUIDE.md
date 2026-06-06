# Configuration Guide — Plato Fleet Chapel

## Environment Requirements

| Requirement | Minimum | Recommended |
|------------|---------|-------------|
| Chapel | 1.30+ | 2.0+ |
| GCC | 9+ | 12+ |
| RAM | 2GB | 4GB+ |
| OS | Linux, macOS | Linux (x86_64) |

## Build Configuration

### Single-Locale (Development)

Default configuration. All rooms simulate on one locale:

```bash
make clean && make
./plato-fleet
```

### Multi-Locale (Production)

Each locale = one room = one physical node.

```bash
# Build Chapel with GASNet
export CHPL_COMM=gasnet
export CHPL_COMM_SUBSTRATE=udp

# Build Plato Fleet
make clean && make

# Run on 5 nodes
./plato-fleet -nl 5
```

### Environment Variables

```bash
# Chapel compiler location (if not in PATH)
export CHPL_HOME=/opt/chapel
export PATH=$CHPL_HOME/bin/linux64-x86_64:$PATH

# Communication backend
export CHPL_COMM=gasnet    # gasnet, mpi, or none (single-locale)
export CHPL_COMM_SUBSTRATE=udp  # udp, ibv, smp

# Optimization
export CHPL_TARGET_CPU=native    # optimize for current CPU
```

## Room Configuration

Rooms are configured in `main.chpl`. To add a room:

1. Define a `(name, localeId)` tuple in `roomDefs`
2. Add sensors with `addSensor()`
3. Add alarms with `addAlarm(name, sensorType, threshold, isAbove)`
4. Add sensor simulation in `simulateSensors()`

### Sensor Thresholds

Default thresholds per sensor type (in `PlatoEngine.chpl`):

| Sensor | Low | High | Unit |
|--------|-----|------|------|
| temperature | 18 | 26 | °C |
| humidity | 30 | 70 | %RH |
| pressure | 990 | 1030 | hPa |
| battery | 10 | 95 | % |
| motion | -1 | 5 | m/s² |

Override per-room in the engine's `getThresholds()` method.

## Fleet Configuration

In `FleetConfig`:

```chapel
var config = new FleetConfig(
  tickIntervalMs = 1000,      // tick frequency
  alarmPropagation = true,     // broadcast alarms fleet-wide
  syncThreshold = 0.7,         // health % for fleet sync
  name = "F/V Plato"          // fleet identifier
);
```

## Groove Configuration

In `GrooveCoordinator`:

```chapel
var groove = new GrooveCoordinator(
  threshold = 0.65  // sync score below this = desynced
);
```

## Deployment Architecture

```
                    ┌─────────────┐
                    │   Locale 0   │
                    │  Fleet Mgr   │
                    │  (RPi 4)     │
                    └──────┬──────┘
                           │ WiFi/Ethernet
              ┌────────────┼────────────┐
              │            │            │
      ┌───────┴──────┐ ┌──┴───────┐ ┌──┴───────┐
      │  Locale 1    │ │ Locale 2 │ │ Locale 3 │
      │  Engine Room │ │ Fish Hold│ │  Galley  │
      │  (RPi Zero)  │ │ (ESP32)  │ │ (ESP32)  │
      └──────────────┘ └──────────┘ └──────────┘
```

Note: ESP32 runs Rust/C, not Chapel. The locale abstraction on ESP32 is a "virtual locale" — a Chapel proxy that communicates via the ternary packing protocol.

## Troubleshooting

### "chpl: command not found"
```bash
source /path/to/chapel/util/setchplenv.bash
```

### "undefined reference to *_comm_*"
Build Chapel with a communication layer:
```bash
export CHPL_COMM=gasnet
cd $CHPL_HOME && make clean && make
```

### Compilation takes >5 minutes
First compilation includes Chapel runtime. Subsequent builds are faster. Use `--fast` flag.

### Tests fail with locale errors
Run tests single-locale:
```bash
./plato-test -nl 1
```
