// main.chpl — Demo: 5-room fishing boat simulation
// Simulates the "Plato" — a fishing boat with 5 rooms, each on its own locale:
//   locale 0: Bridge (navigation, helm)
//   locale 1: Engine Room (propulsion, power)
//   locale 2: Fish Hold (catch storage, refrigeration)
//   locale 3: Galley (kitchen, crew comfort)
//   locale 4: Deck (winches, nets, weather)
//
// In production, each locale is a physical compute node (ESP32 or RPi).
// For this demo, we simulate on one locale but structure the code as if
// each room were on its own.

use Ternary;
use PlatoEngine;
use FleetManager;
use GrooveTracker;

proc main() {
  writeln("╔══════════════════════════════════════════════════════╗");
  writeln("║     Plato Fleet Coordinator — Chapel PGAS Demo      ║");
  writeln("║     5-Room Fishing Boat Simulation                  ║");
  writeln("╚══════════════════════════════════════════════════════╝");
  writeln();
  writeln("Locales available: %i".format(numLocales));
  writeln("Running simulation on locale 0: %s".format(here.name));
  writeln();

  // --- Setup fleet ---
  const config = new FleetConfig(
    tickIntervalMs = 1000,
    alarmPropagation = true,
    syncThreshold = 0.7,
    name = "F/V Plato"
  );
  var fleet = new FleetCoordinator(config);

  // --- Setup groove tracker ---
  var groove = new GrooveCoordinator(threshold = 0.65);

  // --- Room definitions ---
  const roomDefs = [
    ("Bridge",      0),
    ("Engine Room", 1),
    ("Fish Hold",   2),
    ("Galley",      3),
    ("Deck",        4)
  ];

  // Create engines and register with fleet + groove
  for (name, localeId) in roomDefs {
    const roomId = new RoomID(name, localeId, localeId);
    var engine = new shared RoomEngine(roomId);

    // Add sensors based on room type
    select name {
      when "Bridge" {
        engine.addSensor("temperature");
        engine.addSensor("pressure");
        engine.addSensor("battery");
      }
      when "Engine Room" {
        engine.addSensor("temperature");
        engine.addSensor("humidity");
        engine.addSensor("battery");
      }
      when "Fish Hold" {
        engine.addSensor("temperature");
        engine.addSensor("humidity");
      }
      when "Galley" {
        engine.addSensor("temperature");
        engine.addSensor("humidity");
        engine.addSensor("motion");
      }
      when "Deck" {
        engine.addSensor("temperature");
        engine.addSensor("humidity");
        engine.addSensor("motion");
        engine.addSensor("pressure");
      }
    }

    // Add alarms
    select name {
      when "Bridge" {
        engine.addAlarm("Low Battery", "battery", 15.0, false);
        engine.addAlarm("High Temp", "temperature", 28.0, true);
      }
      when "Engine Room" {
        engine.addAlarm("Overheating", "temperature", 50.0, true);
        engine.addAlarm("High Humidity", "humidity", 80.0, true);
      }
      when "Fish Hold" {
        engine.addAlarm("Cold Chain Break", "temperature", -10.0, false);
        engine.addAlarm("High Temp", "temperature", 2.0, true);
      }
      when "Galley" {
        engine.addAlarm("Fire Risk", "temperature", 40.0, true);
      }
      when "Deck" {
        engine.addAlarm("Storm Pressure", "pressure", 980.0, false);
        engine.addAlarm("Overheating", "temperature", 35.0, true);
      }
    }

    fleet.registerEngine(engine);
    groove.registerRoom(name, localeId);
  }

  writeln("Fleet configured: %i rooms registered".format(fleet.engineCount));
  writeln();

  // --- Sensor simulation ---
  // Simulates realistic fishing boat conditions over time
  proc simulateSensors(engineIdx: int, eng: shared RoomEngine, tick: int) {
    // Base values + sinusoidal variation + noise
    const t = tick:real;
    const noise = ((tick * 7 + engineIdx * 13) % 17):real / 17.0 - 0.5;

    select eng.id.name {
      when "Bridge" {
        eng.updateSensor(0, 22.0 + 3.0 * sin(t / 20.0) + noise, t); // temp
        eng.updateSensor(1, 1013.0 + 10.0 * sin(t / 50.0) + noise * 2, t); // pressure
        eng.updateSensor(2, 95.0 - tick * 0.1 + noise * 5, t); // battery drains
      }
      when "Engine Room" {
        eng.updateSensor(0, 45.0 + 10.0 * sin(t / 15.0) + noise * 3, t); // hot
        eng.updateSensor(1, 60.0 + 20.0 * sin(t / 25.0) + noise * 5, t); // humid
        eng.updateSensor(2, 88.0 - tick * 0.05 + noise * 2, t); // battery
      }
      when "Fish Hold" {
        eng.updateSensor(0, -5.0 + 3.0 * sin(t / 30.0) + noise, t); // cold!
        eng.updateSensor(1, 50.0 + 10.0 * sin(t / 20.0) + noise * 3, t);
      }
      when "Galley" {
        eng.updateSensor(0, 25.0 + 8.0 * sin(t / 12.0) + noise * 2, t); // cooking
        eng.updateSensor(1, 55.0 + 15.0 * sin(t / 18.0) + noise * 4, t);
        eng.updateSensor(2, max(0.0, 3.0 * sin(t / 8.0) + noise * 2), t); // motion
      }
      when "Deck" {
        eng.updateSensor(0, 15.0 + 10.0 * sin(t / 10.0) + noise * 3, t); // outside
        eng.updateSensor(1, 70.0 + 20.0 * sin(t / 15.0) + noise * 5, t);
        eng.updateSensor(2, max(0.0, 5.0 * sin(t / 6.0) + noise * 3), t); // motion
        eng.updateSensor(3, 1010.0 + 15.0 * sin(t / 40.0) + noise * 5, t); // pressure
      }
    }
  }

  // --- Run 50-tick simulation ---
  writeln(">>> Running 50-tick simulation...");
  writeln();

  // Custom simulation loop (instead of fleet.simulate) for detailed output
  var now = 0.0;
  for tick in 1..50 {
    // Feed sensors
    for i in 0..#fleet.engineCount {
      if fleet.engines[i] != nil {
        simulateSensors(i, fleet.engines[i]!!, tick);
      }
    }

    now += 1.0;
    fleet.fleetTick(now);

    // Update groove tracker with ternary state
    for i in 0..#fleet.engineCount {
      if fleet.engines[i] != nil {
        groove.updateGroove(i, fleet.engines[i]!.getTernaryState());
      }
    }

    // Print status every 10 ticks
    if tick % 10 == 0 {
      writeln("--- Tick %i ---".format(tick));
      writeln(fleet.fleetSummary());
      writeln(groove.summarize());
      writeln();

      // Print ternary state for each room
      for i in 0..#fleet.engineCount {
        if fleet.engines[i] != nil {
          const state = fleet.engines[i]!.getTernaryState();
          writeln("  %s: %s".format(fleet.engines[i]!.id.name, toString(state)));
        }
      }
      writeln();
    }
  }

  // --- Final Report ---
  writeln();
  writeln("╔══════════════════════════════════════════════════════╗");
  writeln("║              SIMULATION COMPLETE                    ║");
  writeln("╚══════════════════════════════════════════════════════╝");
  writeln();
  writeln("Fleet health: %.1f%%".format(fleet.fleetHealth() * 100));
  writeln("Total alarms: %i".format(fleet.fleetAlarmCount));
  writeln("Groove sync: %.1f%%".format(groove.fleetSyncScore() * 100));
  writeln();

  // Fleet consensus ternary state
  const consensus = fleet.fleetConsensus();
  writeln("Fleet ternary consensus: %s".format(toString(consensus)));

  // Desynced rooms
  const desynced = groove.desyncedRooms();
  if desynced.size > 0 {
    writeln("Rooms out of sync:");
    for idx in desynced {
      writeln("  ⚠️ %s".format(groove.signatures[idx].roomId));
    }
  } else {
    writeln("✅ All rooms in sync!");
  }
  writeln();
  writeln("Simulation finished successfully.");
}
