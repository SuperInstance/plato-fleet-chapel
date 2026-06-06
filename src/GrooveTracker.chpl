// GrooveTracker.chpl — Music-cognitive sync across locales
// Plato rooms share a "groove" — a synchronized cognitive rhythm that keeps
// the fleet moving as one. On a fishing boat, this is the shared rhythm of
// deck work: hauling, sorting, navigating.
//
// The GrooveTracker measures how in-sync rooms are with each other,
// using ternary alignment scores and temporal coherence.

module GrooveTracker {
  use Ternary;
  use Time;

  // A room's groove signature — its ternary state history
  record GrooveSignature {
    var roomId: string;
    var localeId: int;
    var history: [0..#32] [0..#8] Trit;  // 32 ticks of ternary state
    var historyLen: int;
    var currentPhase: real;  // 0.0 to 1.0 — where in the groove cycle
    var tempo: real;          // beats per minute (metaphorical)
  }

  // Sync result between two rooms
  record SyncResult {
    var roomA: string;
    var roomB: string;
    var syncScore: real;     // 0.0 (desynchronized) to 1.0 (perfect sync)
    var ternaryAlignment: real;  // dot product normalized
    var phaseDiff: real;     // phase difference
    var tempoDiff: real;     // tempo difference
  }

  // The groove tracker — fleet-wide rhythm coordinator
  class GrooveCoordinator {
    var signatures: [0..#16] GrooveSignature;
    var sigCount: int;
    var globalTempo: real;
    var syncThreshold: real;

    proc init(threshold: real = 0.7) {
      sigCount = 0;
      globalTempo = 60.0;  // 1 Hz default
      syncThreshold = threshold;
    }

    // Register a room's groove signature
    proc registerRoom(roomId: string, localeId: int) {
      if sigCount >= 16 then return;
      signatures[sigCount] = new GrooveSignature(roomId, localeId,
        [0..#32] [0..#8] Trit.Trit.nominal, 0, 0.0, globalTempo);
      sigCount += 1;
    }

    // Update a room's groove with its current ternary state
    proc updateGroove(roomIdx: int, state: [] Trit) {
      if roomIdx < 0 || roomIdx >= sigCount then return;
      // Shift history: drop oldest, append newest
      for i in 0..#31 {
        signatures[roomIdx].history[i] = signatures[roomIdx].history[i+1];
      }
      const len = min(state.size, 8);
      for i in 0..#len {
        signatures[roomIdx].history[31][i] = state[i];
      }
      if signatures[roomIdx].historyLen < 32 {
        signatures[roomIdx].historyLen += 1;
      }
      // Advance phase
      signatures[roomIdx].currentPhase += 1.0 / 32.0;
      if signatures[roomIdx].currentPhase > 1.0 {
        signatures[roomIdx].currentPhase -= 1.0;
      }
    }

    // Compute sync score between two rooms
    proc computeSync(idxA: int, idxB: int): SyncResult {
      var result = new SyncResult();
      if idxA < 0 || idxA >= sigCount || idxB < 0 || idxB >= sigCount {
        return result;
      }

      result.roomA = signatures[idxA].roomId;
      result.roomB = signatures[idxB].roomId;

      // Ternary alignment: compare last N ternary vectors
      var alignmentSum = 0.0;
      var comparisons = 0;
      const histLen = min(signatures[idxA].historyLen, signatures[idxB].historyLen);
      for t in (32-histLen)..31 {
        const aSlice = signatures[idxA].history[t][0..#8];
        const bSlice = signatures[idxB].history[t][0..#8];
        const dp = dotProduct(aSlice, bSlice);
        alignmentSum += (dp + 8):real / 16.0:real;  // normalize from [-8,8] to [0,1]
        comparisons += 1;
      }
      result.ternaryAlignment = if comparisons > 0 then alignmentSum / comparisons else 0.5;

      // Phase coherence
      result.phaseDiff = abs(signatures[idxA].currentPhase - signatures[idxB].currentPhase);
      if result.phaseDiff > 0.5 then result.phaseDiff = 1.0 - result.phaseDiff;

      // Tempo coherence
      result.tempoDiff = abs(signatures[idxA].tempo - signatures[idxB].tempo);

      // Overall sync score: weighted combination
      result.syncScore = result.ternaryAlignment * 0.6
                       + (1.0 - result.phaseDiff * 2.0) * 0.3
                       + max(0.0, 1.0 - result.tempoDiff / 10.0) * 0.1;
      if result.syncScore < 0.0 then result.syncScore = 0.0;
      if result.syncScore > 1.0 then result.syncScore = 1.0;

      return result;
    }

    // Fleet-wide groove sync: average pairwise sync
    proc fleetSyncScore(): real {
      if sigCount < 2 then return 1.0;
      var total = 0.0;
      var pairs = 0;
      for i in 0..#sigCount {
        for j in (i+1)..#sigCount {
          total += computeSync(i, j).syncScore;
          pairs += 1;
        }
      }
      return if pairs > 0 then total / pairs else 1.0;
    }

    // Identify rooms that are out of sync
    proc desyncedRooms(): [] int {
      var result: [0..#16] int;
      var count = 0;
      for i in 0..#sigCount {
        // Compare with all others; if avg sync is low, this room is desynced
        var avgSync = 0.0;
        var comparisons = 0;
        for j in 0..#sigCount {
          if i != j {
            avgSync += computeSync(i, j).syncScore;
            comparisons += 1;
          }
        }
        if comparisons > 0 {
          avgSync /= comparisons;
          if avgSync < syncThreshold {
            result[count] = i;
            count += 1;
          }
        }
      }
      return result[0..#count];
    }

    // Groove summary
    proc summarize(): string {
      var lines: [1..0] string;
      lines.push_back("🎵 Groove Sync: %.1f%% (threshold: %.0f%%)".format(
        fleetSyncScore() * 100, syncThreshold * 100));
      for i in 0..#sigCount {
        lines.push_back("  %s (locale %i): phase %.2f, tempo %.1f".format(
          signatures[i].roomId, signatures[i].localeId,
          signatures[i].currentPhase, signatures[i].tempo));
      }
      return "\n".join(lines);
    }
  }
}
