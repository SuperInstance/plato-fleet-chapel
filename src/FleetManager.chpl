// FleetManager.chpl — Cross-locale fleet coordination
// The fleet manager runs on a designated locale (typically locale 0, the RPi hub)
// and coordinates all room engines across the distributed Plato system.
//
// Chapel's PGAS model means this is NOT message-passing — it's direct remote
// memory access. When you write `engine.tick()` on locale 0, Chapel handles
// the remote execution on the engine's home locale transparently.

module FleetManager {
  use PlatoEngine;
  use Ternary;
  use Time;

  // Fleet-wide configuration
  record FleetConfig {
    var tickIntervalMs: int;     // ms between fleet ticks
    var alarmPropagation: bool;  // propagate alarms across all locales
    var syncThreshold: real;     // health threshold for fleet-wide sync
    var name: string;
  }

  // A fleet-wide alarm event
  record FleetAlarm {
    var sourceRoom: string;
    var sourceLocale: int;
    var alarmName: string;
    var timestamp: real;
    var severity: int;  // 0-3
  }

  // The fleet manager — coordinates room engines across locales
  class FleetCoordinator {
    var config: FleetConfig;
    var engines: [0..#16] shared RoomEngine?;
    var engineCount: int;
    var fleetAlarms: [0..#64] FleetAlarm;
    var fleetAlarmCount: int;
    var tickCount: int;
    var running: bool;

    proc init(cfg: FleetConfig) {
      config = cfg;
      engineCount = 0;
      fleetAlarmCount = 0;
      tickCount = 0;
      running = false;
    }

    // Register a room engine (typically runs on a specific locale)
    proc registerEngine(engine: shared RoomEngine) {
      if engineCount >= 16 then return;
      engines[engineCount] = engine;
      engineCount += 1;
    }

    // Run one fleet-wide tick: all engines tick in parallel
    proc fleetTick(now: real) {
      tickCount += 1;

      // coforall: each engine ticks on its own locale in parallel
      // In a real multi-locale deployment, Chapel handles the remote execution
      coforall i in 0..#engineCount {
        if engines[i] != nil {
          const eng = engines[i]!;
          // In production: on eng.id.localeId do eng.tick(now);
          eng.tick(now);
        }
      }

      // Collect alarms from all engines
      if config.alarmPropagation {
        for i in 0..#engineCount {
          if engines[i] != nil {
            const eng = engines[i]!;
            if eng.alarmActive.readFF() {
              for j in 0..#eng.alarmCount {
                if eng.alarms[j].triggered {
                  if fleetAlarmCount < 64 {
                    fleetAlarms[fleetAlarmCount] = new FleetAlarm(
                      eng.id.name, eng.id.localeId,
                      eng.alarms[j].name, now, 1);
                    fleetAlarmCount += 1;
                  }
                }
              }
            }
          }
        }
      }
    }

    // Fleet-wide health: average of all engine health scores
    proc fleetHealth(): real {
      if engineCount == 0 then return 1.0;
      var total = 0.0;
      for i in 0..#engineCount {
        if engines[i] != nil {
          total += engines[i]!.healthScore();
        }
      }
      return total / engineCount;
    }

    // Count rooms in alarm state
    proc alarmRoomCount(): int {
      var count = 0;
      for i in 0..#engineCount {
        if engines[i] != nil && engines[i]!.alarmActive.readFF() {
          count += 1;
        }
      }
      return count;
    }

    // Fleet ternary consensus: for each sensor slot, is the fleet mostly below/nominal/above?
    proc fleetConsensus(): [] Trit {
      var consensus: [0..#8] Trit;
      for slot in 0..#8 {
        var votes: [Trit.below..Trit.above] int;
        for i in 0..#engineCount {
          if engines[i] != nil && slot < engines[i]!.sensorCount {
            votes[engines[i]!.ternaryState[slot]] += 1;
          }
        }
        // Pick the trit with most votes; ties go to nominal
        if votes[Trit.below] > votes[Trit.nominal] && votes[Trit.below] > votes[Trit.above] {
          consensus[slot] = Trit.below;
        } else if votes[Trit.above] > votes[Trit.nominal] && votes[Trit.above] > votes[Trit.below] {
          consensus[slot] = Trit.above;
        } else {
          consensus[slot] = Trit.nominal;
        }
      }
      return consensus;
    }

    // Fleet summary report
    proc fleetSummary(): string {
      var lines: [1..0] string;
      lines.push_back("=== Fleet: %s (tick %i) ===".format(config.name, tickCount));
      lines.push_back("Health: %.1f%% | Rooms: %i | Alarms: %i".format(
        fleetHealth() * 100, engineCount, fleetAlarmCount));
      for i in 0..#engineCount {
        if engines[i] != nil {
          lines.push_back("  " + engines[i]!.summarize());
        }
      }
      return "\n".join(lines);
    }

    // Run simulation for N ticks
    proc simulate(ticks: int, sensorFeeder: proc(i: int, eng: shared RoomEngine, tick: int)) {
      running = true;
      var now = timeSinceEpoch().totalSeconds();
      for t in 1..ticks {
        // Feed sensor data to all engines
        for i in 0..#engineCount {
          if engines[i] != nil {
            sensorFeeder(i, engines[i]!!, t);
          }
        }
        // Tick the fleet
        now += 1.0;  // 1 second per tick for simulation
        fleetTick(now);
      }
      running = false;
    }
  }
}
