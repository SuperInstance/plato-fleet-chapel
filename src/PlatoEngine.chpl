// PlatoEngine.chpl — Room engine running on a single locale
// Each Plato "room" is an autonomous control unit (e.g., a boat cabin).
// The engine reads sensors, evaluates ternary state, checks alarms,
// and responds to fleet-wide coordination signals.

module PlatoEngine {
  use Ternary;
  public use Time;

  // Room identity — which part of the boat this locale controls
  record RoomID {
    var name: string;
    var index: int;
    var localeId: int;
  }

  // A single sensor reading
  record SensorReading {
    var sensorType: string;  // "temperature", "humidity", "pressure", "motion", "battery"
    var value: real;
    var timestamp: real;
    var tritState: Trit;     // ternary interpretation
  }

  // Alarm definition
  record Alarm {
    var name: string;
    var sensorType: string;
    var threshold: real;
    var isAbove: bool;       // true = alarm when above threshold, false = below
    var triggered: bool;
    var cooldown: real;      // seconds between re-triggers
    var lastTriggered: real;
  }

  // The room engine — lives on a single locale
  class RoomEngine {
    var id: RoomID;
    var sensors: [0..#8] SensorReading;
    var sensorCount: int;
    var ternaryState: [0..#8] Trit;
    var alarms: [0..#16] Alarm;
    var alarmCount: int;
    var tickCount: int;
    var alarmActive: sync bool;  // sync var for cross-locale alarm coordination
    var status: string;

    proc init(roomId: RoomID) {
      id = roomId;
      sensorCount = 0;
      alarmCount = 0;
      tickCount = 0;
      alarmActive.writeEF(false);  // initially no alarm
      status = "idle";
    }

    // Add a sensor to monitor
    proc addSensor(sensorType: string): int {
      if sensorCount >= 8 then return -1;
      sensors[sensorCount] = new SensorReading(sensorType, 0.0, 0.0, Trit.nominal);
      sensorCount += 1;
      return sensorCount - 1;
    }

    // Add an alarm rule
    proc addAlarm(name: string, sensorType: string, threshold: real, isAbove: bool) {
      if alarmCount >= 16 then return;
      alarms[alarmCount] = new Alarm(name, sensorType, threshold, isAbove, false, 5.0, 0.0);
      alarmCount += 1;
    }

    // Update a sensor value (simulated or real)
    proc updateSensor(idx: int, value: real, timestamp: real) {
      if idx < 0 || idx >= sensorCount then return;
      sensors[idx].value = value;
      sensors[idx].timestamp = timestamp;
    }

    // Tick: evaluate all sensors, update ternary state, check alarms
    proc tick(now: real) {
      tickCount += 1;
      status = "running";

      // Evaluate ternary state for each sensor
      for i in 0..#sensorCount {
        // Default thresholds based on sensor type
        var (lo, hi) = getThresholds(sensors[i].sensorType);
        sensors[i].tritState = toTrit(sensors[i].value, lo, hi);
        ternaryState[i] = sensors[i].tritState;
      }

      // Check alarms
      var anyAlarm = false;
      for i in 0..#alarmCount {
        var triggered = false;
        for j in 0..#sensorCount {
          if sensors[j].sensorType == alarms[i].sensorType {
            if alarms[i].isAbove && sensors[j].value > alarms[i].threshold {
              triggered = true;
            } else if !alarms[i].isAbove && sensors[j].value < alarms[i].threshold {
              triggered = true;
            }
          }
        }
        if triggered && (now - alarms[i].lastTriggered > alarms[i].cooldown) {
          alarms[i].triggered = true;
          alarms[i].lastTriggered = now;
          anyAlarm = true;
        } else if !triggered {
          alarms[i].triggered = false;
        }
      }

      // Set sync alarm variable for cross-locale coordination
      alarmActive.writeEF(anyAlarm);
      if anyAlarm then status = "alarm";
      else status = "running";
    }

    // Get default thresholds for sensor types
    proc getThresholds(sensorType: string): (real, real) {
      select sensorType {
        when "temperature" do return (18.0, 26.0);
        when "humidity" do return (30.0, 70.0);
        when "pressure" do return (990.0, 1030.0);
        when "battery" do return (10.0, 95.0);
        when "motion" do return (-1.0, 5.0);
        otherwise do return (0.0, 100.0);
      }
    }

    // Get the current ternary state vector
    proc getTernaryState(): [] Trit {
      return ternaryState[0..#sensorCount];
    }

    // Health score: fraction of sensors in nominal state
    proc healthScore(): real {
      if sensorCount == 0 then return 1.0;
      var nominal = 0;
      for i in 0..#sensorCount {
        if sensors[i].tritState == Trit.nominal then nominal += 1;
      }
      return nominal:real / sensorCount:real;
    }

    // Summary for fleet reporting
    proc summarize(): string {
      var s = "%s (locale %i, tick %i): health %.1f%% - %s".format(
        id.name, id.localeId, tickCount, healthScore() * 100, status);
      if alarmActive.readFF() {
        s += " ⚠️ ALARM";
        for i in 0..#alarmCount {
          if alarms[i].triggered then
            s += " [%s]".format(alarms[i].name);
        }
      }
      return s;
    }
  }
}
