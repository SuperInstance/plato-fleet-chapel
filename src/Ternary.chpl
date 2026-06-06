// Ternary.chpl — Ternary (-1, 0, +1) pack/unpack using Chapel ranges
// Plato fleet uses ternary state to represent below-target / nominal / above-target
// for room sensors. Packed as 2 bits per trit for compact network transfer.

module Ternary {
  // Trit values: -1 (below), 0 (nominal), +1 (above)
  enum Trit { below = -1, nominal = 0, above = 1 }

  // Pack an array of Trits into a compact uint(8) array (2 bits per trit, 4 trits per byte)
  proc pack(ternary: [] Trit): [] uint(8) {
    const n = ternary.size;
    const packedSize = (n + 3) / 4;  // ceil(n/4)
    var packed: [0..#packedSize] uint(8) = 0;

    for i in 0..#n {
      const byteIdx = i / 4;
      const bitPos = (i % 4) * 2;
      // Map: below(-1)->0, nominal(0)->1, above(1)->2, invalid->3
      const code: uint(8) = if ternary[i] == Trit.below then 0
                            else if ternary[i] == Trit.nominal then 1
                            else 2;
      packed[byteIdx] |= code << bitPos;
    }
    return packed;
  }

  // Unpack a compact uint(8) array back to Trit values
  proc unpack(packed: [] uint(8), count: int): [] Trit {
    var ternary: [0..#count] Trit = Trit.nominal;

    for i in 0..#count {
      const byteIdx = i / 4;
      const bitPos = (i % 4) * 2;
      const code = (packed[byteIdx] >> bitPos) & 0x3:uint(8);
      select code {
        when 0 do ternary[i] = Trit.below;
        when 1 do ternary[i] = Trit.nominal;
        when 2 do ternary[i] = Trit.above;
        otherwise ternary[i] = Trit.nominal; // invalid treated as nominal
      }
    }
    return ternary;
  }

  // Ternary dot product: sum of element-wise multiplication
  // In Plato, this measures alignment between two room state vectors
  proc dotProduct(a: [] Trit, b: [] Trit): int {
    var sum = 0;
    for i in a.domain do
      sum += a[i]:int * b[i]:int;
    return sum;
  }

  // Convert a real value to Trit based on thresholds
  proc toTrit(value: real, low: real, high: real): Trit {
    if value < low then return Trit.below;
    else if value > high then return Trit.above;
    else return Trit.nominal;
  }

  // Count trits by type
  proc countTrits(ternary: [] Trit): (int, int, int) {
    var below = 0, nominal = 0, above = 0;
    for t in ternary {
      select t {
        when Trit.below do below += 1;
        when Trit.nominal do nominal += 1;
        when Trit.above do above += 1;
      }
    }
    return (below, nominal, above);
  }

  // Ternary to human-readable string
  proc toString(ternary: [] Trit): string {
    var s = "[";
    for i in ternary.domain {
      if i > 0 then s += " ";
      select ternary[i] {
        when Trit.below do s += "↓";
        when Trit.nominal do s += "·";
        when Trit.above do s += "↑";
      }
    }
    s += "]";
    return s;
  }
}
