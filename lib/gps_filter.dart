import 'dart:math';
import 'package:geolocator/geolocator.dart';

double _hv(double la1, double ln1, double la2, double ln2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(la2 - la1) / 2), 2) + cos(rad(la1)) * cos(rad(la2)) * pow(sin(rad(ln2 - ln1) / 2), 2);
  return 2 * r * asin(sqrt(a));
}

class FilteredFix {
  final double lat, lng, speedKmh, accuracy;
  const FilteredFix(this.lat, this.lng, this.speedKmh, this.accuracy);
}

/// Low-lag GPS smoothing.
/// - Adaptive Kalman filter on position: process noise grows with the bus speed, so it follows
///   the bus closely at speed while still removing jitter when standing still.
/// - Rejects very poor fixes and impossible jumps.
/// - Speed uses the GPS Doppler speed with a fast-attack / slower-release smoother.
class GpsFilter {
  double _lat = 0, _lng = 0, _var = -1, _speed = 0; // _speed in m/s
  int _ts = 0;
  int _bad = 0;
  int _lastRawTs = 0; // timestamp (ms) of the last GPS fix seen
  int used = 0, rejected = 0; // diagnostics shown to the driver

  void reset() {
    _var = -1;
    _speed = 0;
    _bad = 0;
    _lastRawTs = 0;
    used = 0;
    rejected = 0;
  }

  FilteredFix? update(Position p) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tsFix = p.timestamp.millisecondsSinceEpoch;
    final age = (now - tsFix) / 1000.0;
    if (_var < 0) {
      // First fix of a trip: it may be an old cached location. A live GPS stream gives a NEW timestamp on the
      // next fix, so the second distinct fix is accepted even when the phone clock is a little off.
      final live = _lastRawTs != 0 && tsFix > _lastRawTs;
      _lastRawTs = tsFix;
      if (age > 20 && !live) {
        rejected++;
        return null;
      }
    } else {
      if (tsFix < _lastRawTs) {
        rejected++;
        return null; // out-of-order / old fix
      }
      _lastRawTs = tsFix;
    }
    final acc = max(p.accuracy, 3.0);
    var raw = (p.speed.isNaN || p.speed < 0) ? 0.0 : p.speed;
    if (_var < 0) {
      if (p.accuracy > 100 && ++_bad < 3) {
        rejected++;
        return null; // wait for a usable first fix
      }
      _lat = p.latitude;
      _lng = p.longitude;
      _var = acc * acc;
      _speed = raw;
      _ts = now;
    } else {
      if (p.accuracy > 80) {
        rejected++;
        return null; // unusable fix
      }
      final dt = max(0.0, (now - _ts) / 1000.0);
      final jump = _hv(_lat, _lng, p.latitude, p.longitude);
      if (dt > 0 && jump / dt > 70 && p.accuracy > 25) {
        rejected++;
        return null; // impossible jump
      }
      // some phones report speed 0 (no Doppler): derive it from the distance moved
      if (raw < 0.5 && dt >= 1 && jump > max(acc, 12.0)) raw = min(jump / dt, 40.0);
      // standing still: ignore GPS wobble so the position does not drift between stops
      if (raw < 0.8 && _speed < 1.2 && jump < max(acc, 8.0)) {
        _ts = now;
        _speed = 0;
        used++;
        return FilteredFix(_lat, _lng, 0, sqrt(_var));
      }
      final q = max(3.0, _speed * 1.2 + 3.0);
      _var += dt * q * q;
      final k = _var / (_var + acc * acc);
      _lat += k * (p.latitude - _lat);
      _lng += k * (p.longitude - _lng);
      _var = (1 - k) * _var;
      _ts = now;
      _speed += (raw > _speed ? 0.75 : 0.55) * (raw - _speed);
    }
    final shown = _speed < 0.7 ? 0.0 : _speed;
    used++;
    return FilteredFix(_lat, _lng, shown * 3.6, sqrt(_var));
  }
}
