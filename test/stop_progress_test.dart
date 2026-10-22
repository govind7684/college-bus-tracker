import 'package:college_bus/data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A straight north-south road with three stops about 1.1 km apart.
  final stops = [Stop('A', 9.00, 76.5), Stop('B', 9.01, 76.5), Stop('C', 9.02, 76.5)];
  Journey fwd() => Journey(stops, [9.00, 76.5, 9.01, 76.5, 9.02, 76.5]);

  test('stops behind the bus are passed, the rest are upcoming', () {
    final j = fwd();
    expect(j.nextFor(9.0, 76.5), 1); // at A -> A passed, next is B
    expect(j.nextFor(9.005, 76.5), 1); // between A and B
    expect(j.nextFor(9.012, 76.5), 2); // beyond B
    expect(j.nextFor(9.02, 76.5), 3); // at the last stop -> everything passed
  });

  test('a route that is far from the bus gives no progress (no false stop changes)', () {
    expect(fwd().nextFor(9.005, 76.6), isNull);
  });

  test('return journey has its own sequence: stops behind along the return direction are passed', () {
    final rs = stops.reversed.toList();
    final back = Journey(rs, [9.02, 76.5, 9.01, 76.5, 9.00, 76.5]);
    expect(back.nextFor(9.02, 76.5), 1); // C passed
    expect(back.nextFor(9.012, 76.5), 1); // between C and B
    expect(back.nextFor(9.0, 76.5), 3);
  });

  // Gateway rule: each stop is a zone 20 m long along the road (10 m each side of the stop point).
  group('stop gateway', () {
    test('17 m before stop B: not reached yet', () {
      expect(fwd().nextFor(9.01 - 0.00015, 76.5), 1);
    });

    test('7 m before stop B: inside the gateway, so B is reached', () {
      expect(fwd().nextFor(9.01 - 0.00006, 76.5), 2);
    });

    test('bus on the far side of the road (about 22 m sideways) still reaches B', () {
      expect(fwd().nextFor(9.01, 76.5002), 2);
    });

    test('about 44 m sideways at B is outside the gateway: not reached', () {
      expect(fwd().nextFor(9.01, 76.5004), 1);
    });

    test('bus detours around B (about 44 m sideways) but ends up beyond it: B is passed', () {
      expect(fwd().nextFor(9.0102, 76.5004), 2);
    });
  });

  // Exact-GPS rule: straight distance to the stop, the saved road line is not used.
  group('exact GPS stop rule', () {
    // 10 stops along a line, about 1.1 km apart
    final line = [for (var k = 0; k < 10; k++) Stop('S$k', 9.0 + k * 0.01, 76.5)];

    test('within 50 m of the next stop: reached', () {
      expect(gpsCandidate(line, 0, 9.0 + 0.00027, 76.5, []), 1); // about 30 m
    });

    test('80 m away and approaching: not reached yet', () {
      expect(gpsCandidate(line, 0, 9.0 + 0.00072, 76.5, []), 0);
    });

    test('never touches the stop (about 100 m beside it), then moves away: passed', () {
      final minD = <double>[];
      expect(gpsCandidate(line, 0, 9.0, 76.5009, minD), 0); // closest approach about 100 m
      expect(gpsCandidate(line, 0, 9.0 + 0.0013, 76.5009, minD), 1); // now more than 40 m further away
    });

    test('a stop far away is not passed', () {
      expect(gpsCandidate(line, 0, 9.0 + 0.004, 76.5, []), 0);
    });

    test('only the next few stops are checked (a loop cannot skip many stops)', () {
      expect(gpsCandidate(line, 0, 9.08, 76.5, []), 0); // standing at stop 8 while the next stop is 0
    });

    test('a missed stop is passed when the next one is reached', () {
      expect(gpsCandidate(line, 0, 9.01, 76.5, []), 2); // at stop 1, stop 0 was skipped
    });
  });
}
