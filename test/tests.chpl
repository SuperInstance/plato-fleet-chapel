// tests.chpl — All unit tests for Plato fleet coordinator
// Run with: chpl -o plato-test test/tests.chpl src/Ternary.chpl src/PlatoEngine.chpl src/FleetManager.chpl src/GrooveTracker.chpl && ./plato-test

use Ternary;
use PlatoEngine;
use FleetManager;
use GrooveTracker;

var passed = 0;
var failed = 0;

proc test(name: string, result: bool) {
  if result {
    passed += 1;
    writeln("  ✅ %s".format(name));
  } else {
    failed += 1;
    writeln("  ❌ %s".format(name));
  }
}

proc assertEq(actual: int, expected: int): bool do return actual == expected;
proc assertEq(actual: real, expected: real, tol: real = 1e-6): bool do return abs(actual - expected) < tol;
proc assertEq(actual: bool, expected: bool): bool do return actual == expected;
proc assertEq(actual: string, expected: string): bool do return actual == expected;

proc main() {
  writeln("═══ Plato Fleet Chapel — Unit Tests ═══");
  writeln();

  // ========================================
  // Ternary Tests
  // ========================================
  writeln("[Ternary Module]");

  // Test 1: Trit enum values
  test("Trit.below == -1", Trit.below:int == -1);
  test("Trit.nominal == 0", Trit.nominal:int == 0);
  test("Trit.above == 1", Trit.above:int == 1);

  // Test 2: Pack/unpack roundtrip
  {
    var original: [0..#7] Trit = [Trit.below, Trit.nominal, Trit.above,
                                   Trit.nominal, Trit.below, Trit.above, Trit.nominal];
    var packed = pack(original);
    var restored = unpack(packed, 7);
    var match = true;
    for i in 0..#7 do if restored[i] != original[i] then match = false;
    test("Pack/unpack roundtrip (7 trits)", match);
  }

  // Test 3: Pack/unpack roundtrip — powers of 4
  {
    var original: [0..#8] Trit;
    for i in 0..#8 do original[i] = if i % 3 == 0 then Trit.below
                       else if i % 3 == 1 then Trit.nominal
                       else Trit.above;
    var packed = pack(original);
    test("Packed size for 8 trits = 2 bytes", packed.size == 2);
    var restored = unpack(packed, 8);
    var match = true;
    for i in 0..#8 do if restored[i] != original[i] then match = false;
    test("Pack/unpack roundtrip (8 trits)", match);
  }

  // Test 4: Ternary dot product — identical vectors
  {
    var a: [0..#4] Trit = [Trit.above, Trit.above, Trit.above, Trit.above];
    test("Dot product (identical above)", dotProduct(a, a) == 4);
  }

  // Test 5: Ternary dot product — opposite vectors
  {
    var a: [0..#4] Trit = [Trit.above, Trit.above, Trit.above, Trit.above];
    var b: [0..#4] Trit = [Trit.below, Trit.below, Trit.below, Trit.below];
    test("Dot product (opposite)", dotProduct(a, b) == -4);
  }

  // Test 6: Ternary dot product — orthogonal
  {
    var a: [0..#4] Trit = [Trit.above, Trit.below, Trit.nominal, Trit.above];
    var b: [0..#4] Trit = [Trit.below, Trit.above, Trit.above, Trit.below];
    test("Dot product (orthogonal)", dotProduct(a, b) == -3);
  }

  // Test 7: toTrit conversion
  test("toTrit below threshold", toTrit(10.0, 15.0, 25.0) == Trit.below);
  test("toTrit nominal", toTrit(20.0, 15.0, 25.0) == Trit.nominal);
  test("toTrit above threshold", toTrit(30.0, 15.0, 25.0) == Trit.above);

  // Test 8: countTrits
  {
    var v: [0..#6] Trit = [Trit.below, Trit.nominal, Trit.above, Trit.below, Trit.nominal, Trit.nominal];
    var (b, n, a) = countTrits(v);
    test("countTrits (2 below, 3 nominal, 1 above)", b == 2 && n == 3 && a == 1);
  }

  writeln();

  // ========================================
  // PlatoEngine Tests
  // ========================================
  writeln("[PlatoEngine Module]");

  // Test 9: Engine creation and sensor registration
  {
    var id = new RoomID("TestRoom", 0, 0);
    var engine = new shared RoomEngine(id);
    engine.addSensor("temperature");
    engine.addSensor("humidity");
    test("Engine sensor count = 2", engine.sensorCount == 2);
    test("Engine status = idle", engine.status == "idle");
  }

  // Test 10: Engine tick with nominal values
  {
    var id = new RoomID("NominalRoom", 0, 0);
    var engine = new shared RoomEngine(id);
    engine.addSensor("temperature");
    engine.addSensor("humidity");
    engine.updateSensor(0, 22.0, 1.0);  // within temp thresholds (18, 26)
    engine.updateSensor(1, 50.0, 1.0);  // within humidity thresholds (30, 70)
    engine.tick(1.0);
    test("Health score with nominal sensors", assertEq(engine.healthScore(), 1.0));
    test("No alarm active", !engine.alarmActive.readFF());
  }

  // Test 11: Engine tick with out-of-range values
  {
    var id = new RoomID("AlarmRoom", 0, 0);
    var engine = new shared RoomEngine(id);
    engine.addSensor("temperature");
    engine.addAlarm("Overheat", "temperature", 28.0, true);
    engine.updateSensor(0, 35.0, 1.0);  // above threshold
    engine.tick(1.0);
    test("Alarm triggered for overheating", engine.alarmActive.readFF());
    test("Engine status = alarm", engine.status == "alarm");
  }

  // Test 12: Engine ternary state after tick
  {
    var id = new RoomID("StateRoom", 0, 0);
    var engine = new shared RoomEngine(id);
    engine.addSensor("temperature");  // thresholds (18, 26)
    engine.addSensor("battery");      // thresholds (10, 95)
    engine.updateSensor(0, 15.0, 1.0);  // below -> Trit.below
    engine.updateSensor(1, 98.0, 1.0);  // above -> Trit.above
    engine.tick(1.0);
    const state = engine.getTernaryState();
    test("Ternary state[0] = below", state[0] == Trit.below);
    test("Ternary state[1] = above", state[1] == Trit.above);
  }

  // Test 13: Alarm cooldown
  {
    var id = new RoomID("CoolRoom", 0, 0);
    var engine = new shared RoomEngine(id);
    engine.addSensor("temperature");
    engine.addAlarm("Overheat", "temperature", 28.0, true);
    engine.updateSensor(0, 35.0, 1.0);
    engine.tick(1.0);
    test("First alarm triggers", engine.alarmActive.readFF());
    // Now tick again immediately — should be in cooldown
    engine.updateSensor(0, 35.0, 2.0);
    engine.tick(2.0);
    // Cooldown check: alarm was triggered at 1.0, now 2.0, cooldown is 5.0
    // So alarm should still be triggered (it was already triggered last time)
    // But new alarm won't fire due to cooldown. The alarmActive reflects current state.
    test("Alarm persists during sustained condition", engine.alarmActive.readFF());
  }

  writeln();

  // ========================================
  // FleetManager Tests
  // ========================================
  writeln("[FleetManager Module]");

  // Test 14: Fleet creation and engine registration
  {
    var config = new FleetConfig(1000, true, 0.7, "TestFleet");
    var fleet = new FleetCoordinator(config);
    var id1 = new RoomID("Room1", 0, 0);
    var id2 = new RoomID("Room2", 1, 1);
    fleet.registerEngine(new shared RoomEngine(id1));
    fleet.registerEngine(new shared RoomEngine(id2));
    test("Fleet engine count = 2", fleet.engineCount == 2);
  }

  // Test 15: Fleet tick coordination
  {
    var config = new FleetConfig(1000, true, 0.7, "TickFleet");
    var fleet = new FleetCoordinator(config);
    var id1 = new RoomID("Room1", 0, 0);
    var id2 = new RoomID("Room2", 1, 1);
    var eng1 = new shared RoomEngine(id1);
    var eng2 = new shared RoomEngine(id2);
    eng1.addSensor("temperature");
    eng2.addSensor("temperature");
    eng1.updateSensor(0, 22.0, 0.0);
    eng2.updateSensor(0, 24.0, 0.0);
    fleet.registerEngine(eng1);
    fleet.registerEngine(eng2);
    fleet.fleetTick(1.0);
    test("Fleet tick count = 1", fleet.tickCount == 1);
    test("Fleet health = 1.0", assertEq(fleet.fleetHealth(), 1.0));
  }

  // Test 16: Fleet alarm collection
  {
    var config = new FleetConfig(1000, true, 0.7, "AlarmFleet");
    var fleet = new FleetCoordinator(config);
    var id1 = new RoomID("GoodRoom", 0, 0);
    var id2 = new RoomID("BadRoom", 1, 1);
    var eng1 = new shared RoomEngine(id1);
    var eng2 = new shared RoomEngine(id2);
    eng1.addSensor("temperature");
    eng2.addSensor("temperature");
    eng2.addAlarm("Overheat", "temperature", 28.0, true);
    eng1.updateSensor(0, 22.0, 0.0);
    eng2.updateSensor(0, 35.0, 0.0);
    fleet.registerEngine(eng1);
    fleet.registerEngine(eng2);
    fleet.fleetTick(1.0);
    test("Fleet collected alarms", fleet.fleetAlarmCount >= 1);
    test("Fleet alarm room count = 1", fleet.alarmRoomCount() == 1);
  }

  // Test 17: Fleet consensus ternary
  {
    var config = new FleetConfig(1000, false, 0.7, "ConsensusFleet");
    var fleet = new FleetCoordinator(config);
    var id1 = new RoomID("Room1", 0, 0);
    var id2 = new RoomID("Room2", 1, 1);
    var id3 = new RoomID("Room3", 2, 2);
    var eng1 = new shared RoomEngine(id1);
    var eng2 = new shared RoomEngine(id2);
    var eng3 = new shared RoomEngine(id3);
    eng1.addSensor("temperature"); eng1.updateSensor(0, 22.0, 0.0);  // nominal
    eng2.addSensor("temperature"); eng2.updateSensor(0, 22.0, 0.0);  // nominal
    eng3.addSensor("temperature"); eng3.updateSensor(0, 35.0, 0.0);  // above
    fleet.registerEngine(eng1);
    fleet.registerEngine(eng2);
    fleet.registerEngine(eng3);
    fleet.fleetTick(1.0);
    const consensus = fleet.fleetConsensus();
    test("Fleet consensus sensor[0] = nominal (2 of 3)", consensus[0] == Trit.nominal);
  }

  writeln();

  // ========================================
  // GrooveTracker Tests
  // ========================================
  writeln("[GrooveTracker Module]");

  // Test 18: Groove coordinator creation
  {
    var groove = new GrooveCoordinator(threshold = 0.65);
    groove.registerRoom("Room1", 0);
    groove.registerRoom("Room2", 1);
    test("Groove room count = 2", groove.sigCount == 2);
  }

  // Test 19: Groove update and history
  {
    var groove = new GrooveCoordinator(threshold = 0.65);
    groove.registerRoom("Room1", 0);
    var state: [0..#4] Trit = [Trit.nominal, Trit.above, Trit.below, Trit.nominal];
    for i in 1..10 {
      groove.updateGroove(0, state);
    }
    test("Groove history length = 10", groove.signatures[0].historyLen == 10);
    test("Groove phase advanced", groove.signatures[0].currentPhase > 0.0);
  }

  // Test 20: Sync score — identical rooms
  {
    var groove = new GrooveCoordinator(threshold = 0.5);
    groove.registerRoom("Room1", 0);
    groove.registerRoom("Room2", 1);
    var state: [0..#4] Trit = [Trit.nominal, Trit.above, Trit.below, Trit.nominal];
    for i in 1..15 {
      groove.updateGroove(0, state);
      groove.updateGroove(1, state);
    }
    const sync = groove.computeSync(0, 1);
    test("Identical rooms sync score > 0.8", sync.syncScore > 0.8);
  }

  // Test 21: Sync score — different rooms
  {
    var groove = new GrooveCoordinator(threshold = 0.5);
    groove.registerRoom("Room1", 0);
    groove.registerRoom("Room2", 1);
    var stateA: [0..#4] Trit = [Trit.above, Trit.above, Trit.above, Trit.above];
    var stateB: [0..#4] Trit = [Trit.below, Trit.below, Trit.below, Trit.below];
    for i in 1..15 {
      groove.updateGroove(0, stateA);
      groove.updateGroove(1, stateB);
    }
    const sync = groove.computeSync(0, 1);
    test("Opposite rooms sync score < 0.5", sync.syncScore < 0.5);
  }

  // Test 22: Fleet-wide groove score
  {
    var groove = new GrooveCoordinator(threshold = 0.5);
    groove.registerRoom("Room1", 0);
    groove.registerRoom("Room2", 1);
    groove.registerRoom("Room3", 2);
    var state: [0..#4] Trit = [Trit.nominal, Trit.nominal, Trit.nominal, Trit.nominal];
    for i in 1..20 {
      groove.updateGroove(0, state);
      groove.updateGroove(1, state);
      groove.updateGroove(2, state);
    }
    const fleetSync = groove.fleetSyncScore();
    test("Fleet-wide groove sync > 0.8", fleetSync > 0.8);
  }

  // Test 23: Desynced room detection
  {
    var groove = new GrooveCoordinator(threshold = 0.9);
    groove.registerRoom("Room1", 0);
    groove.registerRoom("Room2", 1);
    groove.registerRoom("Room3", 2);
    var goodState: [0..#4] Trit = [Trit.nominal, Trit.nominal, Trit.nominal, Trit.nominal];
    var badState: [0..#4] Trit = [Trit.below, Trit.above, Trit.below, Trit.above];
    for i in 1..20 {
      groove.updateGroove(0, goodState);
      groove.updateGroove(1, goodState);
      groove.updateGroove(2, badState);  // this one is different
    }
    const desynced = groove.desyncedRooms();
    test("Detected 1 desynced room", desynced.size == 1);
  }

  writeln();

  // ========================================
  // Integration Tests
  // ========================================
  writeln("[Integration]");

  // Test 24: Full 50-tick fishing boat simulation
  {
    var config = new FleetConfig(1000, true, 0.7, "IntegrationTest");
    var fleet = new FleetCoordinator(config);
    var groove = new GrooveCoordinator(threshold = 0.65);

    const rooms = [("Bridge", 0), ("Engine Room", 1), ("Fish Hold", 2),
                   ("Galley", 3), ("Deck", 4)];

    for (name, locId) in rooms {
      var id = new RoomID(name, locId, locId);
      var eng = new shared RoomEngine(id);
      eng.addSensor("temperature");
      fleet.registerEngine(eng);
      groove.registerRoom(name, locId);
    }

    // Run 50 ticks
    for tick in 1..50 {
      for i in 0..#fleet.engineCount {
        if fleet.engines[i] != nil {
          const t = tick:real;
          const val = 20.0 + 5.0 * sin(t / 10.0);
          fleet.engines[i]!.updateSensor(0, val, t);
        }
      }
      fleet.fleetTick(tick:real);
      for i in 0..#fleet.engineCount {
        if fleet.engines[i] != nil {
          groove.updateGroove(i, fleet.engines[i]!.getTernaryState());
        }
      }
    }

    test("50-tick simulation: fleet tick count = 50", fleet.tickCount == 50);
    test("50-tick simulation: fleet health > 0", fleet.fleetHealth() > 0.0);
    test("50-tick simulation: groove sync > 0", groove.fleetSyncScore() > 0.0);
    test("50-tick simulation: all rooms registered", fleet.engineCount == 5);
  }

  // Test 25: Multi-locale simulation with alarm cascade
  {
    var config = new FleetConfig(1000, true, 0.7, "CascadeTest");
    var fleet = new FleetCoordinator(config);

    var id1 = new RoomID("Engine Room", 1, 1);
    var eng1 = new shared RoomEngine(id1);
    eng1.addSensor("temperature");
    eng1.addAlarm("Fire", "temperature", 50.0, true);
    fleet.registerEngine(eng1);

    // Simulate escalating temperature
    for tick in 1..30 {
      const temp = 30.0 + tick:real * 1.0; // rises from 31 to 60
      eng1.updateSensor(0, temp, tick:real);
      fleet.fleetTick(tick:real);
    }

    test("Alarm cascade: fleet has alarms", fleet.fleetAlarmCount > 0);
    test("Alarm cascade: engine in alarm at tick 30", eng1.alarmActive.readFF());
  }

  writeln();
  writeln("══════════════════════════════════════");
  writeln("Results: %i passed, %i failed".format(passed, failed));
  if failed > 0 {
    writeln("SOME TESTS FAILED ❌");
  } else {
    writeln("ALL TESTS PASSED ✅");
  }
}
