import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gps_filter.dart';
import 'settings.dart';
import 'theme.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

final db = FirebaseFirestore.instance;

double hav(double la1, double ln1, double la2, double ln2) {
  const r = 6371000.0;
  double rad(double d) => d * pi / 180;
  final a = pow(sin(rad(la2 - la1) / 2), 2) +
      cos(rad(la1)) * cos(rad(la2)) * pow(sin(rad(ln2 - ln1) / 2), 2);
  return 2 * r * asin(sqrt(a));
}

String todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());
String autoDirection() => DateTime.now().hour < 12 ? 'morning' : 'evening';

/// Bus number plate of the original (first) bus.
const kPlate = 'KL 04 AU3728';

/// The fleet. Each bus has its own live doc (buses/`<id>`_live), route doc (buses/`<id>`_route),
/// driver (app2_users/`<uid>`.bus) and student roster (app2_students/`<uid>`.bus).
class BusInfo {
  final String id, label, plate;
  final String asset; // bus photo (shown whole, at its own aspect ratio)
  final double aspect; // width / height of [asset]
  final String phone; // fleet contact (driver / coordinator), international format
  const BusInfo(this.id, this.label, this.plate, {this.asset = kHeroAsset, this.aspect = kHeroAspect, this.phone = ''});

  /// "+91 98479 81461"
  String get phoneText =>
      phone.startsWith('+91') && phone.length == 13 ? '+91 ${phone.substring(3, 8)} ${phone.substring(8)}' : phone;
}

const kBuses = [
  BusInfo('bus1', 'Bus 1', kPlate, phone: '+919847981461'),
  BusInfo('bus2', 'Bus 2', 'KL 04 AV 1315', asset: 'assets/images/bus2_wide.jpg', aspect: 1100 / 824, phone: '+917736731853'),
];

BusInfo busInfo(String id) => kBuses.firstWhere((b) => b.id == id, orElse: () => kBuses.first);
String otherBus(String id) => id == 'bus1' ? 'bus2' : 'bus1';

/// Bus a student/driver profile belongs to. Profiles created before multi-bus support have none -> Bus 1.
String busOf(Map<String, dynamic>? m) {
  final v = (m?['bus'] ?? 'bus1').toString();
  return kBuses.any((b) => b.id == v) ? v : 'bus1';
}

/// Stop zones use the EXACT GPS position of the bus (straight distance to the stop), not the saved road line.
/// A stop is reached when the bus is within [kStopRadius] metres. If the bus never gets that close (road
/// closure, detour, other lane) it is still passed once the bus came within [kStopOuter] metres and then moved
/// [kMoveAway] metres further away. Only the next [kLookahead] stops are checked, so a road that loops back
/// near an earlier stop cannot skip the stops in between.
const double kStopRadius = 50;
const double kStopOuter = 150;
const double kMoveAway = 40;
const int kLookahead = 6;

/// Road gateway used only to catch up when a trip starts or resumes in the middle of the route
/// (stops already behind the bus): 20 m long zone along the saved road line.
const double kGateHalfLen = 10;
const double kGateSide = 30;

/// Exact-GPS stop rule. Returns the index of the next upcoming stop after seeing the bus at [lat],[lng].
/// [minD] remembers the closest distance (m) the bus has been to each stop; keep the same list between fixes.
int gpsCandidate(List<Stop> stops, int next, double lat, double lng, List<double> minD) {
  while (minD.length < stops.length) {
    minD.add(double.infinity);
  }
  var cand = next;
  final end = min(stops.length, next + kLookahead);
  for (var j = next; j < end; j++) {
    final s = stops[j];
    if (s.lat == 0 && s.lng == 0) continue;
    final d = hav(lat, lng, s.lat, s.lng);
    if (d < minD[j]) minD[j] = d;
    final reached = d <= kStopRadius;
    final passedBy = minD[j] <= kStopOuter && d >= minD[j] + kMoveAway;
    if ((reached || passedBy) && j + 1 > cand) cand = j + 1;
  }
  return cand;
}

/// Estimated bus speed (m/s) used when OSRM gives no duration (about 30 km/h).
const kDefaultMps = 8.33;

class Stop {
  final String name, localName;
  final double lat, lng;
  final double distFromPrev; // metres along the road from the previous stop (0 = unknown / first)
  final double durFromPrev; // seconds of driving from the previous stop (0 = unknown / first)
  Stop(this.name, this.lat, this.lng, {this.localName = '', this.distFromPrev = 0, this.durFromPrev = 0});

  Stop copyWith({String? name, String? localName, double? lat, double? lng, double? distFromPrev, double? durFromPrev}) => Stop(
        name ?? this.name,
        lat ?? this.lat,
        lng ?? this.lng,
        localName: localName ?? this.localName,
        distFromPrev: distFromPrev ?? this.distFromPrev,
        durFromPrev: durFromPrev ?? this.durFromPrev,
      );

  Map<String, dynamic> toMap(int order) => {
        'name': name,
        if (localName.isNotEmpty) 'localName': localName,
        'lat': lat,
        'lng': lng,
        'order': order,
        'distFromPrev': distFromPrev,
        'durFromPrev': durFromPrev,
      };

  /// Tolerant parser: accepts different key names / GeoPoint / plain strings.
  factory Stop.fromAny(dynamic e) {
    if (e is! Map) return Stop(e.toString(), 0, 0);
    final m = e;
    double? num0(List<String> ks) {
      for (final k in ks) {
        final v = m[k];
        if (v is num) return v.toDouble();
        if (v is String) {
          final p = double.tryParse(v);
          if (p != null) return p;
        }
      }
      return null;
    }

    var lat = num0(['lat', 'latitude']);
    var lng = num0(['lng', 'lon', 'long', 'longitude']);
    for (final k in ['location', 'position', 'geo', 'coords']) {
      final v = m[k];
      if (v is GeoPoint) {
        lat = v.latitude;
        lng = v.longitude;
      }
    }
    final name = (m['name'] ?? m['stopName'] ?? m['title'] ?? m['stop'] ?? '').toString();
    return Stop(name, lat ?? 0, lng ?? 0,
        localName: (m['localName'] ?? '').toString(),
        distFromPrev: num0(['distFromPrev']) ?? 0,
        durFromPrev: num0(['durFromPrev']) ?? 0);
  }
}

List<double> reversePairs(List<double> g) {
  final out = <double>[];
  for (var i = g.length - 2; i >= 0; i -= 2) {
    out..add(g[i])..add(g[i + 1]);
  }
  return out;
}

/// Writes the stop-to-stop road distance (and driving time) onto every stop, in sequence order.
List<Stop> withLegs(List<Stop> s, List<double> legs, [List<double> durs = const []]) => [
      for (var i = 0; i < s.length; i++)
        s[i].copyWith(
          distFromPrev: i == 0 || i - 1 >= legs.length ? 0 : legs[i - 1],
          durFromPrev: i == 0 || i - 1 >= durs.length ? 0 : durs[i - 1],
        ),
    ];

List<double> straightLegs(List<Stop> s) =>
    [for (var i = 1; i < s.length; i++) hav(s[i - 1].lat, s[i - 1].lng, s[i].lat, s[i].lng) * 1.25];

List<double> estDurations(List<double> legs) => [for (final l in legs) l / kDefaultMps];

/// "12 min" / "1 hr 5 min" from seconds.
String durText(double secs) {
  final m = (secs / 60).round();
  return m < 1 ? '<1 min' : (m < 60 ? '$m min' : '${m ~/ 60} hr ${m % 60} min');
}

/// One direction of travel: stops in TRAVEL order + the road geometry in travel order.
/// Every distance / "passed" decision is made along this journey's own direction,
/// so forward and return trips never share history.
class Journey {
  final List<Stop> stops;
  final List<double> geo; // flat [lat,lng,...]
  Journey(this.stops, this.geo);

  bool get hasGeo => geo.length >= 4;
  int get _n => geo.length ~/ 2;

  late final List<double> cum = () {
    final c = <double>[0];
    for (var i = 1; i < _n; i++) {
      c.add(c.last + hav(geo[2 * i - 2], geo[2 * i - 1], geo[2 * i], geo[2 * i + 1]));
    }
    return c;
  }();

  /// Projects a point onto the road polyline (segment projection, not nearest vertex).
  /// Returns the distance along the route (m) and how far the point is from the road (m).
  /// With [hint] (last known progress) a candidate that is not behind the bus's previous position is
  /// preferred, so a route that doubles back near itself cannot make the bus jump backwards.
  ({double along, double off}) _project(double lat, double lng, {double? hint}) {
    final cl = cos(lat * pi / 180);
    const mDeg = 111320.0;
    var bestAlong = 0.0, bestOff = double.infinity;
    var hAlong = 0.0, hOff = double.infinity;
    for (var i = 0; i < _n - 1; i++) {
      final ax = (geo[2 * i + 1] - lng) * cl * mDeg, ay = (geo[2 * i] - lat) * mDeg;
      final bx = (geo[2 * i + 3] - lng) * cl * mDeg, by = (geo[2 * i + 2] - lat) * mDeg;
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
      t = t.clamp(0.0, 1.0).toDouble();
      final px = ax + t * dx, py = ay + t * dy;
      final d = sqrt(px * px + py * py);
      final along = cum[i] + t * (cum[i + 1] - cum[i]);
      if (d < bestOff) {
        bestOff = d;
        bestAlong = along;
      }
      if (hint != null && along >= hint - 250 && d < hOff) {
        hOff = d;
        hAlong = along;
      }
    }
    if (hint != null && hOff <= bestOff + 60) return (along: hAlong, off: hOff);
    return (along: bestAlong, off: bestOff);
  }

  late final List<double> stopProg = [for (final s in stops) hasGeo ? _project(s.lat, s.lng).along : 0.0];

  double _ck1 = 0, _ck2 = 0;
  double _off = 0; // sideways distance (m) of the last projected position from the road line
  double get lastOff => _off;
  double? _cv;
  double? _hint;
  bool _cs = false;

  /// Distance travelled along the route (m) for a GPS point, or null if off-route / no geometry.
  double? busProgress(double lat, double lng) {
    if (!hasGeo) return null;
    if (_cs && _ck1 == lat && _ck2 == lng) return _cv;
    final p = _project(lat, lng, hint: _hint);
    _cv = p.off > 500 ? null : p.along;
    _off = p.off;
    if (_cv != null) _hint = _cv;
    _ck1 = lat; _ck2 = lng; _cs = true;
    return _cv;
  }

  /// Forget the previous position (a new trip starts again from the beginning).
  void resetProgress() {
    _hint = null;
    _cs = false;
    _cv = null;
  }

  /// Estimated driving time of the whole journey (seconds).
  double get totalSeconds {
    final s = stops.fold(0.0, (a, e) => a + e.durFromPrev);
    return s > 0 ? s : totalMeters / kDefaultMps;
  }

  /// Road distance (m) between stop i-1 and stop i in this journey's direction.
  double leg(int i) {
    if (i <= 0 || i >= stops.length) return 0;
    if (hasGeo) return max(0.0, stopProg[i] - stopProg[i - 1]);
    final a = stops[i - 1], b = stops[i];
    return hav(a.lat, a.lng, b.lat, b.lng) * 1.25;
  }

  /// Total length of the journey in metres.
  double get totalMeters {
    final sum = stops.fold(0.0, (a, s) => a + s.distFromPrev);
    if (sum > 0) return sum;
    if (hasGeo) return cum.last;
    return straightLegs(stops).fold(0.0, (a, b) => a + b);
  }

  /// Index of the next upcoming stop for a position (all stops behind are "passed"), or null if unknown.
  /// Each stop is a gateway along the road (see [kGateHalfLen]): it is reached when the bus is inside the
  /// zone, and passed when the bus is beyond it, so the bus never has to touch the exact stop point.
  int? nextFor(double lat, double lng) {
    final b = busProgress(lat, lng);
    if (b == null) return null;
    final off = _off;
    var i = 0;
    while (i < stops.length) {
      final inside = b >= stopProg[i] - kGateHalfLen && b <= stopProg[i] + kGateHalfLen && off <= kGateSide;
      final beyond = b > stopProg[i] + kGateHalfLen;
      if (inside || beyond) {
        i++;
      } else {
        break;
      }
    }
    return i;
  }

  /// Road distance (m) from the bus to stop [i], where [n] is the next upcoming stop.
  double? remaining(double lat, double lng, int n, int i) {
    if (n >= stops.length || i < n || i >= stops.length) return null;
    final b = busProgress(lat, lng);
    if (b != null) return max(0.0, stopProg[i] - b);
    var d = hav(lat, lng, stops[n].lat, stops[n].lng) * 1.25;
    for (var k = n; k < i; k++) {
      d += hav(stops[k].lat, stops[k].lng, stops[k + 1].lat, stops[k + 1].lng) * 1.25;
    }
    return d;
  }
}

RouteData parseRoute(Map<String, dynamic>? m) {
  if (m == null) return RouteData.empty();
  List<Stop> st(dynamic v) => ((v as List?) ?? []).map(Stop.fromAny).toList();
  List<double> g(dynamic v) => ((v as List?) ?? []).whereType<num>().map((e) => e.toDouble()).toList();
  final ret = st(m['returnStops']);
  return RouteData(st(m['stops']), g(m['geometry']),
      retStops: ret,
      retGeo: g(m['returnGeometry']),
      retSame: m['returnSame'] != false || ret.isEmpty,
      plate: (m['plate'] ?? '').toString());
}

class RouteData {
  final List<Stop> stops; // forward (morning) journey
  final List<double> geo;
  final List<Stop> retStops; // return (evening) journey, when configured separately
  final List<double> retGeo;
  final bool retSame; // true = return is the forward route reversed
  final String plate; // optional number plate stored on the route doc (overrides the default)
  RouteData(this.stops, this.geo, {this.retStops = const [], this.retGeo = const [], this.retSame = true, this.plate = ''});

  /// Number plate to show for [busId].
  String plateFor(String busId) => plate.isNotEmpty ? plate : busInfo(busId).plate;
  static RouteData empty() => RouteData([], []);

  bool get hasReturn => !retSame && retStops.isNotEmpty;
  late final Journey fwd = Journey(stops, geo);
  late final Journey ret = hasReturn ? Journey(retStops, retGeo) : Journey(stops.reversed.toList(), reversePairs(geo));

  Journey plan(String dir) => dir == 'evening' ? ret : fwd;
  List<Stop> journey(String dir) => plan(dir).stops;
}

class Live {
  final Map<String, dynamic> m;
  final String busId; // which bus this state belongs to (the stop rules differ per bus, see [nextIn])
  Live(this.m, {this.busId = 'bus1'});
  factory Live.fromMap(Map<String, dynamic>? m, {String busId = 'bus1'}) => Live(m ?? {}, busId: busId);

  double _d(String k) => (m[k] as num?)?.toDouble() ?? 0;
  bool get tripActive => m['tripActive'] == true; // raw flag (driver side)
  bool get breakdown => m['breakdown'] == true;
  String get rawDirection => (m['direction'] ?? autoDirection()).toString();
  String get breakdownNote => (m['breakdownNote'] ?? '').toString();
  String get driverName => (m['driverName'] ?? '').toString();
  String get driverPhone => (m['driverPhone'] ?? '').toString();
  double get lat => _d('lat');
  double get lng => _d('lng');
  double get speed => _d('speed');
  double get accuracy => _d('accuracy');
  int get fixes => (m['fixes'] as num?)?.toInt() ?? 0; // GPS fixes used / rejected (driver diagnostics)
  int get fixesRejected => (m['fixesRejected'] as num?)?.toInt() ?? 0;
  double get covered => _d('coveredKm');
  double get top => _d('topSpeed');
  double get avg => _d('avgMoving');
  bool get isToday => m['tripDate'] == todayKey();

  /// A trip that is really running today (ignores stale flags from older days).
  bool get running => tripActive && isToday;

  /// Direction shown to students: stored one for today's trip, otherwise by time of day.
  String get direction => isToday ? rawDirection : autoDirection();

  int get next => isToday ? ((m['nextIndex'] as num?)?.toInt() ?? 0) : 0; // as stored by the driver
  DateTime? get updated => (m['updatedAt'] as Timestamp?)?.toDate();
  bool get hasFix => lat != 0 || lng != 0;

  /// Trip running but no GPS/heartbeat for 3+ minutes.
  bool get stale => running && updated != null && DateTime.now().difference(updated!).inMinutes >= 3;

  /// Speed used for time estimates.
  double get effSpeed => speed >= 10 ? (avg >= 10 ? 0.5 * speed + 0.5 * avg : speed) : (avg >= 10 ? avg : 30);

  /// The REAL next stop. Re-evaluated from the bus's current coordinates against THIS journey's own
  /// direction (forward stops in the morning, the return itinerary in the evening), so after a pause,
  /// restart or crash every stop physically behind the bus is "Passed" straight away.
  int realNextIn(RouteData r) {
    final plan = r.plan(direction);
    var n = next;
    if (running && hasFix) {
      // exact GPS: a stop the bus is standing at counts as reached straight away
      while (n < plan.stops.length &&
          (plan.stops[n].lat != 0 || plan.stops[n].lng != 0) &&
          hav(lat, lng, plan.stops[n].lat, plan.stops[n].lng) <= kStopRadius) {
        n++;
      }
    }
    return n.clamp(0, plan.stops.length).toInt();
  }

  /// Bus 1's MORNING run has a special start: until it has passed its second stop (e.g. Ochira -> Mukkada)
  /// the status shows the FIRST stop ("Heading to Ochira") and nothing is marked Passed yet. Once it passes
  /// the second stop, or any later one, that stop and every stop behind it is Passed.
  /// Bus 2 and every return journey use the standard rule only (no special start).
  bool get firstStopRule => busId == 'bus1' && direction == 'morning';

  /// Next stop as shown in the app (applies [firstStopRule]).
  int nextIn(RouteData r) {
    final n = realNextIn(r);
    if (firstStopRule && n == 1 && r.plan(direction).stops.length > 1) return 0;
    return n;
  }

  bool doneIn(RouteData r) {
    final c = r.plan(direction).stops.length;
    return isToday && c > 0 && nextIn(r) >= c;
  }

  double? remaining(RouteData r, int i) {
    if (!running || !hasFix) return null;
    return r.plan(direction).remaining(lat, lng, realNextIn(r), i);
  }

  /// The stop the Navigate button guides to: the real next stop while the trip runs, otherwise the first stop.
  Stop? navStop(RouteData r) {
    final stops = r.journey(direction);
    if (stops.isEmpty) return null;
    final n = running ? realNextIn(r) : (doneIn(r) ? stops.length : 0);
    return n < stops.length && (stops[n].lat != 0 || stops[n].lng != 0) ? stops[n] : null;
  }

  DateTime? eta(RouteData r, int i) {
    final d = remaining(r, i);
    if (d == null) return null;
    return DateTime.now().add(Duration(minutes: (d / 1000 / effSpeed * 60).round()));
  }

  /// "Heading to Ochira": always the next stop of the journey that is actually being run
  /// (forward stops in the morning, return stops in the evening).
  String? headingTo(RouteData r) {
    final stops = r.journey(direction);
    final n = nextIn(r);
    if (!running || n >= stops.length) return null;
    return 'Heading to ${stops[n].name}';
  }
}

class OsrmRoute {
  final List<double> geo;
  final List<double> legs; // metres between consecutive stops
  final List<double> durations; // seconds between consecutive stops
  final List<int> detours; // legs whose road is far longer than the gap between the two stops (side-lane / loop)
  OsrmRoute(this.geo, this.legs, [this.durations = const [], this.detours = const []]);
}

/// Road snapping, routing and place names (OSRM + Nominatim, both OpenStreetMap-based).
class Geo {
  static const _h = {'User-Agent': 'CarmelCollegeBus/1.0'};

  static const _osrm = 'https://router.project-osrm.org';

  /// How far (degrees) a road may point away from the direction of travel and still count as "the road we drive".
  static const _bearingRange = 60;

  /// Compass bearing (0..360, clockwise from north) from point 1 to point 2.
  static double bearing(double la1, double ln1, double la2, double ln2) {
    double rad(double d) => d * pi / 180;
    final y = sin(rad(ln2 - ln1)) * cos(rad(la2));
    final x = cos(rad(la1)) * sin(rad(la2)) - sin(rad(la1)) * cos(rad(la2)) * cos(rad(ln2 - ln1));
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// Direction of travel at stop [i]: towards the next stop (the last stop uses the way in). Null if unknown.
  static double? travelBearing(List<Stop> s, int i) {
    if (s.length < 2 || i < 0 || i >= s.length) return null;
    final a = i < s.length - 1 ? s[i] : s[i - 1];
    final b = i < s.length - 1 ? s[i + 1] : s[i];
    if ((a.lat == 0 && a.lng == 0) || (b.lat == 0 && b.lng == 0)) return null;
    if (hav(a.lat, a.lng, b.lat, b.lng) < 15) return null;
    return bearing(a.lat, a.lng, b.lat, b.lng);
  }

  /// Road route through the stops, in order.
  /// First it uses DIRECTIONAL snapping: every stop must sit on a road that runs in the direction of travel
  /// (within 80 m), so a stop at a junction snaps to the main road and not to the side lane, and the route
  /// cannot loop round a canal / service road to arrive from the other side. If that is impossible it falls
  /// back to plain snapping. Legs that are still far longer than the gap between their stops are reported in
  /// [OsrmRoute.detours].
  static Future<OsrmRoute> route(List<Stop> stops) async {
    if (stops.length < 2) return OsrmRoute([], []);
    try {
      return await _route(stops, directional: true);
    } catch (_) {
      return _route(stops, directional: false);
    }
  }

  static Future<OsrmRoute> _route(List<Stop> stops, {required bool directional}) async {
    final coords = stops.map((s) => '${s.lng},${s.lat}').join(';');
    final q = StringBuffer('overview=full&geometries=geojson&steps=false&alternatives=false');
    if (directional) {
      final b = [for (var i = 0; i < stops.length; i++) travelBearing(stops, i)];
      if (b.any((x) => x != null)) {
        final bs = b.map((x) => x == null ? '' : '${x.round()},$_bearingRange').join(';');
        final rs = List.filled(stops.length, '80').join(';');
        q.write('&bearings=$bs&radiuses=$rs');
      }
    }
    final res = await http.get(Uri.parse('$_osrm/route/v1/driving/$coords?$q')).timeout(const Duration(seconds: 20));
    final j = jsonDecode(res.body) as Map;
    if (j['code'] != 'Ok') throw 'Routing failed (${j['code']})';
    final r = (j['routes'] as List).first;
    final pts = r['geometry']['coordinates'] as List;
    final legs = [for (final l in r['legs'] as List) (l['distance'] as num).toDouble()];
    final durs = [for (final l in r['legs'] as List) (l['duration'] as num).toDouble()];
    final detours = <int>[];
    for (var i = 0; i < legs.length && i + 1 < stops.length; i++) {
      final straight = hav(stops[i].lat, stops[i].lng, stops[i + 1].lat, stops[i + 1].lng);
      if (legs[i] > max(900.0, straight * 2.5)) detours.add(i);
    }
    return OsrmRoute([for (final p in pts) ...[(p[1] as num).toDouble(), (p[0] as num).toDouble()]], legs, durs, detours);
  }

  /// Snaps every stop to the road centre line (OSRM nearest) on the road that runs in the direction of travel.
  /// Stops that cannot be snapped are kept as they are.
  static Future<List<Stop>> snapStops(List<Stop> stops) async {
    final snapped = await Future.wait([
      for (var i = 0; i < stops.length; i++)
        (stops[i].lat == 0 && stops[i].lng == 0)
            ? Future<List<double>?>.value(null)
            : snap(stops[i].lat, stops[i].lng, heading: travelBearing(stops, i)),
    ]);
    return [
      for (var i = 0; i < stops.length; i++)
        snapped[i] == null ? stops[i] : stops[i].copyWith(lat: snapped[i]![0], lng: snapped[i]![1]),
    ];
  }

  /// Snap + route + automatic detour repair. A stop that makes the bus take a long detour (it landed on a side
  /// lane) is moved to the nearby road position that gives the shortest way from the previous stop.
  static Future<(List<Stop>, OsrmRoute)> plan(List<Stop> stops) async {
    var s = await snapStops(stops);
    var r = await route(s);
    if (r.detours.isNotEmpty) {
      var changed = false;
      for (final leg in r.detours) {
        final k = leg + 1;
        final p = await _betterPlacement(s, k);
        if (p != null) {
          s = [for (var i = 0; i < s.length; i++) i == k ? s[i].copyWith(lat: p[0], lng: p[1]) : s[i]];
          changed = true;
        }
      }
      if (changed) r = await route(s);
    }
    return (s, r);
  }

  static Future<List<double>?> _betterPlacement(List<Stop> s, int k) async {
    if (k <= 0 || k >= s.length) return null;
    final prev = s[k - 1];
    final cur = await _legDistance(prev.lat, prev.lng, s[k].lat, s[k].lng);
    if (cur == null) return null;
    List<double>? best;
    var bestD = cur;
    for (final c in await _candidates(s[k].lat, s[k].lng)) {
      final d = await _legDistance(prev.lat, prev.lng, c[0], c[1]);
      if (d != null && d < bestD) {
        bestD = d;
        best = c;
      }
    }
    return (best != null && bestD < cur * 0.6) ? best : null;
  }

  /// Up to 5 road positions within 120 m of a point.
  static Future<List<List<double>>> _candidates(double lat, double lng) async {
    try {
      final res = await http.get(Uri.parse('$_osrm/nearest/v1/driving/$lng,$lat?number=5')).timeout(const Duration(seconds: 8));
      final ws = (jsonDecode(res.body) as Map)['waypoints'] as List;
      return [
        for (final w in ws)
          if ((w['distance'] as num).toDouble() <= 120) [((w['location'] as List)[1] as num).toDouble(), ((w['location'] as List)[0] as num).toDouble()],
      ];
    } catch (_) {
      return [];
    }
  }

  /// Road distance (m) between two points, or null.
  static Future<double?> _legDistance(double la1, double ln1, double la2, double ln2) async {
    try {
      final res = await http
          .get(Uri.parse('$_osrm/route/v1/driving/$ln1,$la1;$ln2,$la2?overview=false'))
          .timeout(const Duration(seconds: 10));
      final j = jsonDecode(res.body) as Map;
      if (j['code'] != 'Ok') return null;
      return ((j['routes'] as List).first['distance'] as num).toDouble();
    } catch (_) {
      return null;
    }
  }

  /// A short warning when [r] still contains a detour, otherwise null.
  static String? detourNote(List<Stop> stops, OsrmRoute r) {
    if (r.detours.isEmpty) return null;
    final i = r.detours.first;
    if (i + 1 >= stops.length || i >= r.legs.length) return null;
    final road = (r.legs[i] / 1000).toStringAsFixed(1);
    final gap = (hav(stops[i].lat, stops[i].lng, stops[i + 1].lat, stops[i + 1].lng) / 1000).toStringAsFixed(1);
    final more = r.detours.length > 1 ? ' (+${r.detours.length - 1} more)' : '';
    return 'Stop ${i + 1} → ${i + 2} makes a detour ($road km of road for a $gap km gap)$more. Drag stop ${i + 2} onto the main road.';
  }

  /// Nearest point on the road network as [lat, lng], or null if none within 300 m / offline.
  /// With [heading] (direction of travel) only roads running that way (+-60 degrees, within 80 m) are used first,
  /// so the point lands on the main road centre line and not on a crossing side lane.
  static Future<List<double>?> snap(double lat, double lng, {double? heading}) async {
    Future<List<double>?> go(bool directional) async {
      try {
        final extra = directional ? '&bearings=${heading!.round()},$_bearingRange&radiuses=80' : '';
        final res = await http.get(Uri.parse('$_osrm/nearest/v1/driving/$lng,$lat?number=1$extra')).timeout(const Duration(seconds: 8));
        final j = jsonDecode(res.body) as Map;
        if (j['code'] != 'Ok') return null;
        final w = (j['waypoints'] as List).first;
        if ((w['distance'] as num).toDouble() > 300) return null;
        final loc = w['location'] as List;
        return [(loc[1] as num).toDouble(), (loc[0] as num).toDouble()];
      } catch (_) {
        return null;
      }
    }

    if (heading != null) {
      final d = await go(true);
      if (d != null) return d;
    }
    return go(false);
  }

  /// Place name for a coordinate in the given language (e.g. 'en', 'ml').
  static Future<String?> placeName(double lat, double lng, String lang) async {
    try {
      final res = await http
          .get(
            Uri.https('nominatim.openstreetmap.org', '/reverse',
                {'format': 'jsonv2', 'lat': '$lat', 'lon': '$lng', 'zoom': '17', 'addressdetails': '1', 'accept-language': lang}),
            headers: _h,
          )
          .timeout(const Duration(seconds: 8));
      final j = jsonDecode(res.body) as Map;
      final n = j['name'];
      if (n is String && n.isNotEmpty) return n;
      final a = (j['address'] as Map?) ?? {};
      for (final k in ['suburb', 'neighbourhood', 'village', 'hamlet', 'town', 'city_district', 'locality', 'road']) {
        final v = a[k];
        if (v is String && v.isNotEmpty) return v;
      }
      final d = (j['display_name'] ?? '').toString();
      return d.isEmpty ? null : d.split(',').first.trim();
    } catch (_) {
      return null;
    }
  }
}

class Repo {
  static String get uid => FirebaseAuth.instance.currentUser!.uid;

  // ---- per-bus documents ----
  static String liveDoc(String busId) => 'buses/${busId}_live';
  static String routeDoc(String busId) => 'buses/${busId}_route';

  // The app used to track a single bus in these documents. Bus 1 falls back to them until its own
  // documents exist, so existing data keeps working without a migration.
  static const _legacyLive = 'bus/live';
  static const _legacyRoute = 'bus/bus2_route';

  static Stream<RouteData> routeStream(String busId) => db.doc(routeDoc(busId)).snapshots().asyncMap((s) async {
        var data = s.data();
        if (!s.exists && busId == 'bus1') {
          try {
            data = (await db.doc(_legacyRoute).get()).data();
          } catch (_) {}
        }
        return parseRoute(data);
      });

  static Future<RouteData> routeOnce(String busId) async {
    final s = await db.doc(routeDoc(busId)).get();
    var data = s.data();
    if (!s.exists && busId == 'bus1') data = (await db.doc(_legacyRoute).get()).data();
    return parseRoute(data);
  }

  /// Live state of a bus. The copy kept on the phone is shown at once (so after the app was closed, killed or
  /// restarted the stops behind the bus are Passed immediately), then the real-time data takes over.
  static Stream<Live> liveStream(String busId) async* {
    final cached = await LocalStore.loadLive(busId);
    if (cached != null) yield Live.fromMap(cached, busId: busId);
    var lastSave = DateTime(2000);
    await for (final s in db.doc(liveDoc(busId)).snapshots()) {
      var data = s.data();
      if (!s.exists && busId == 'bus1') {
        try {
          data = (await db.doc(_legacyLive).get()).data();
        } catch (_) {}
      }
      if (data != null && DateTime.now().difference(lastSave).inSeconds >= 2) {
        lastSave = DateTime.now();
        LocalStore.saveLive(busId, data);
      }
      yield Live.fromMap(data, busId: busId);
    }
  }

  /// Saves both directions with sequence order, inter-stop distances and driving times.
  static Future<void> saveRoute({
    required String busId,
    required List<Stop> fwd,
    required List<double> fwdGeo,
    required bool retSame,
    List<Stop> ret = const [],
    List<double> retGeo = const [],
  }) =>
      db.doc(routeDoc(busId)).set({
        'busId': busId,
        'stops': [for (var i = 0; i < fwd.length; i++) fwd[i].toMap(i + 1)],
        'geometry': fwdGeo,
        'returnSame': retSame,
        'returnStops': retSame ? [] : [for (var i = 0; i < ret.length; i++) ret[i].toMap(i + 1)],
        'returnGeometry': retSame ? [] : retGeo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // merge keeps optional fields such as 'plate'

  static Stream<QuerySnapshot<Map<String, dynamic>>> announcements() =>
      db.collection('app2_announcements').orderBy('createdAt', descending: true).limit(10).snapshots();

  static Future<void> postAnnouncement(String text) => db.collection('app2_announcements').add({
        'text': text,
        'by': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

  static DocumentReference<Map<String, dynamic>> attDoc(String studentUid) =>
      db.doc('app2_attendance/${studentUid}_${todayKey()}');

  /// status: 'present' (will ride) or 'skip' (will NOT be on the bus – the driver can see this).
  ///
  /// [rideBus] is the bus the student really rides this journey. When it differs from the bus the
  /// student is assigned to, the mark is a *contingency* (emergency bus switch): it shows up in the
  /// destination bus driver's Special Contingency Log for this journey, at [stop] on that bus's route.
  static Future<void> markAttendance(String journey, Map<String, dynamic> student,
      {String status = 'present', String? rideBus, String? stop}) {
    final assigned = busOf(student);
    final bus = rideBus ?? assigned;
    final boarding = stop ?? student['stop'];
    return attDoc(uid).set({
      'uid': uid,
      'name': student['name'],
      'stop': student['stop'],
      'bus': assigned,
      'date': todayKey(),
      '${journey}Status': status,
      '${journey}Time': FieldValue.serverTimestamp(),
      '${journey}Bus': bus,
      '${journey}Contingency': bus != assigned,
      '${journey}Stop': boarding,
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> todayRegister() =>
      db.collection('app2_attendance').where('date', isEqualTo: todayKey()).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> students() => db.collection('app2_students').snapshots();

  /// Roster key = the student's email in lower case (document id in `app2_roster`).
  static String rosterKey(String email) => email.trim().toLowerCase();

  /// Writes the student's profile to Firestore (app2_students/`<uid>`) if it does not exist yet.
  /// There is no open self-registration: the institution first adds the student to `app2_roster`
  /// (email, admission number, bus ...). A profile is only created from a matching roster entry, so anyone
  /// else gets [NotAuthorized]. Safe to call on every start: it never overwrites an existing profile.
  static Future<void> ensureStudentProfile({String? admissionNo}) async {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null) return;
    final ref = db.doc('app2_students/${u.uid}');
    if ((await ref.get()).exists) return;
    final email = u.email ?? '';
    final r = (await db.doc('app2_roster/${rosterKey(email)}').get()).data();
    if (r == null || (r['status'] ?? 'approved') != 'approved') throw const NotAuthorized('Your email is not registered by the institution.');
    final reg = (r['admissionNo'] ?? '').toString().trim();
    if (admissionNo != null && reg.isNotEmpty && reg.toLowerCase() != admissionNo.trim().toLowerCase()) {
      throw const NotAuthorized('The admission number does not match the institution records.');
    }
    await ref.set({
      'uid': u.uid,
      'name': (r['name'] ?? u.displayName ?? email.split('@').first).toString(),
      'email': email,
      'admissionNo': reg,
      'className': r['className'] ?? '',
      'phone': r['phone'] ?? '',
      'guardianName': r['guardianName'] ?? '',
      'guardianPhone': r['guardianPhone'] ?? '',
      'stop': r['stop'],
      'bus': busOf(r),
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> setStudentBus(String bus) =>
      db.doc('app2_students/$uid').set({'uid': uid, 'bus': bus}, SetOptions(merge: true));

  // ---- driver trip tracking ----
  static StreamSubscription<Position>? _sub;
  static Timer? _beat;
  static final GpsFilter _filter = GpsFilter();
  static String _busId = 'bus1';
  static String _direction = 'morning';
  static Journey? _plan;
  static int _next = 0;
  static double _cov = 0, _top = 0, _moveDist = 0, _moveSec = 0;
  static double? _lastLat, _lastLng;
  static DateTime? _lastT;
  static DateTime _lastWrite = DateTime(2000);
  static int _lastWrittenNext = -1;
  static List<double> _minD = []; // closest the bus has been to each stop (m)
  static int _fixN = 0; // accepted fixes since the trip started
  static int _pend = -1, _pendHits = 0; // a stop advance must be seen on 2 fixes in a row (GPS jitter guard)
  static final Set<int> _logged = {}; // stops already written to the trip history
  static bool get isTracking => _sub != null;

  static Future<String?> _permission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return 'Location permission is required to share the bus location.';
    }
    if (!await Geolocator.isLocationServiceEnabled()) return 'Please turn on GPS.';
    return null;
  }

  static void _resetStats() {
    _next = 0; _cov = 0; _top = 0; _moveDist = 0; _moveSec = 0;
    _pend = -1; _pendHits = 0; _logged.clear(); _minD = []; _fixN = 0;
    _lastLat = null; _lastLng = null; _lastT = null; _resetWrite();
    _filter.reset();
  }

  static void _resetWrite() {
    _lastWrite = DateTime(2000);
    _lastWrittenNext = -1;
  }

  static Future<String?> startTrip(String busId, String direction) async {
    final err = await _permission();
    if (err != null) return err;
    _resetStats();
    _busId = busId;
    String dName = '', dPhone = '';
    try {
      final u = (await db.doc('app2_users/$uid').get()).data();
      dName = (u?['name'] ?? '').toString();
      dPhone = (u?['phone'] ?? '').toString();
    } catch (_) {}
    await db.doc(liveDoc(busId)).set({
      'busId': busId,
      'driverName': dName,
      'driverPhone': dPhone,
      'tripActive': true,
      'tripDate': todayKey(),
      'direction': direction,
      'nextIndex': 0,
      'coveredKm': 0, 'topSpeed': 0, 'avgMoving': 0, 'speed': 0,
      'driverUid': uid,
      'breakdown': false,
      'startedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _begin(busId, direction);
    _persistTrip();
    return null;
  }

  /// Keeps the running trip on the phone, so a crash / restart can continue it even before the network answers.
  static void _persistTrip() => LocalStore.saveTrip(_busId, {
        'tripActive': true,
        'tripDate': todayKey(),
        'driverUid': uid,
        'direction': _direction,
        'nextIndex': _next,
        'coveredKm': _cov / 1000,
        'topSpeed': _top,
      });

  /// If the app was closed, killed or restarted during a trip, continue it when the driver reopens the app:
  /// same bus, same direction, same progress. The server copy wins when it answers (the trip may have been ended
  /// elsewhere); offline, the copy kept on the phone is used. A fresh GPS fix then marks every stop behind the
  /// bus as Passed at once.
  static Future<void> resumeIfNeeded(String busId) async {
    if (_sub != null) return;
    try {
      final local = await LocalStore.loadTrip(busId);
      Map<String, dynamic>? server;
      try {
        server = (await db.doc(liveDoc(busId)).get()).data();
      } catch (_) {}
      bool mine(Map<String, dynamic>? x) =>
          x != null && x['tripActive'] == true && x['driverUid'] == uid && x['tripDate'] == todayKey();
      final srv = mine(server), loc = mine(local);
      if (server != null ? !srv : !loc) {
        if (server != null && local != null) await LocalStore.clearTrip(busId); // trip was ended
        return;
      }
      final base = srv ? server! : local!;
      if (await _permission() != null) return;
      _resetStats();
      _busId = busId;
      int idx(Map<String, dynamic>? x) => (x?['nextIndex'] as num?)?.toInt() ?? 0;
      double dbl(Map<String, dynamic>? x, String k) => (x?[k] as num?)?.toDouble() ?? 0.0;
      _next = max(idx(base), loc ? idx(local) : 0);
      _logged.addAll([for (var i = 0; i < _next; i++) i]); // already in the trip history
      _cov = max(dbl(base, 'coveredKm'), loc ? dbl(local, 'coveredKm') : 0.0) * 1000;
      _top = max(dbl(base, 'topSpeed'), loc ? dbl(local, 'topSpeed') : 0.0);
      await _begin(busId, (base['direction'] ?? autoDirection()).toString(), restart: false);
      await refreshNow();
    } catch (_) {}
  }

  /// Called when the app returns to the foreground: take a fresh fix immediately and
  /// re-evaluate which stops are already behind the bus.
  static Future<void> refreshNow() async {
    if (_sub == null) return;
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation));
      _handle(p, force: true);
    } catch (_) {}
  }

  static Future<void> _begin(String busId, String direction, {bool restart = true}) async {
    _direction = direction;
    // This journey's own stops + road geometry (the return trip uses the return itinerary, never the forward one).
    _plan = (await routeOnce(busId)).plan(direction);
    if (restart) _plan!.resetProgress();
    _beat?.cancel();
    _beat = Timer.periodic(const Duration(seconds: 10), (t) async {
      if (t.tick % 3 == 0) {
        db.doc(liveDoc(_busId)).set({'updatedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
      // The GPS stream can go quiet (standing still with a distance filter, phone power saving). Ask for a
      // position ourselves when nothing arrived for 12 s, so location, speed and time keep updating.
      final last = _lastT;
      if (last == null || DateTime.now().difference(last).inSeconds > 12) {
        try {
          final p = await Geolocator.getCurrentPosition(
              locationSettings: LocationSettings(accuracy: _mode.acc, timeLimit: const Duration(seconds: 8)));
          _handle(p);
        } catch (_) {}
      }
    });
    await _listen(true);
  }

  /// GPS quality chosen in Settings: 0 battery saver, 1 balanced, 2 high accuracy.
  static ({LocationAccuracy acc, int filter, int secs, int write}) get _mode {
    switch (AppSettings.gpsMode) {
      case 0:
        return (acc: LocationAccuracy.medium, filter: 25, secs: 5, write: 10);
      case 1:
        return (acc: LocationAccuracy.high, filter: 8, secs: 2, write: 5);
      default:
        return (acc: LocationAccuracy.bestForNavigation, filter: 2, secs: 1, write: 3);
    }
  }

  static Future<void> _listen(bool foreground) async {
    await _sub?.cancel();
    final m = _mode;
    final LocationSettings settings = foreground && !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: m.acc,
            distanceFilter: m.filter,
            intervalDuration: Duration(seconds: m.secs),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'College Bus',
              notificationText: 'Sharing live bus location',
              enableWakeLock: true,
            ),
          )
        : LocationSettings(accuracy: m.acc, distanceFilter: m.filter);
    _sub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (p) => _handle(p),
      onError: (_) {
        // e.g. foreground-service permission missing: retry once without it
        if (foreground) _listen(false);
      },
    );
  }

  static void _handle(Position p, {bool force = false}) {
    final f = _filter.update(p);
    if (f == null) return;
    final now = DateTime.now();
    if (_lastLat != null && _lastT != null) {
      final d = hav(_lastLat!, _lastLng!, f.lat, f.lng);
      final dt = now.difference(_lastT!).inMilliseconds / 1000;
      if (d > 3 && d < 2000) {
        _cov += d;
        if (f.speedKmh > 3) { _moveDist += d; _moveSec += dt; }
      }
    }
    _lastLat = f.lat; _lastLng = f.lng; _lastT = now;
    _top = max(_top, f.speedKmh);

    // Which stops are behind us? Exact GPS distance to each stop (see kStopRadius). The saved road line is only
    // used to catch up when the trip starts or resumes in the middle of the route.
    _fixN++;
    final plan = _plan;
    if (plan != null) {
      var cand = _next;
      if (force || _fixN <= 3) {
        final c = plan.nextFor(f.lat, f.lng);
        if (c != null && c > cand) cand = c;
      }
      final g = gpsCandidate(plan.stops, _next, f.lat, f.lng, _minD);
      if (g > cand) cand = g;
      if (cand > _next) {
        // Only advance after two consecutive fixes agree (or on a forced re-check after a restart), so a single
        // noisy GPS point can never mark a stop as passed. Progress never goes backwards.
        if (_pend > _next && cand >= _pend) {
          _pendHits++;
        } else {
          _pend = cand;
          _pendHits = 1;
        }
        if (force || _pendHits >= 2) {
          _next = _pend;
          _pend = -1;
          _pendHits = 0;
        }
      } else {
        _pend = -1;
        _pendHits = 0;
      }
      _logPassed(plan);
    }

    if (!force && _next == _lastWrittenNext && now.difference(_lastWrite).inSeconds < _mode.write) return;
    _lastWrite = now;
    _lastWrittenNext = _next;
    _persistTrip();
    db.doc(liveDoc(_busId)).set({
      'lat': f.lat,
      'lng': f.lng,
      'speed': f.speedKmh,
      'accuracy': f.accuracy,
      'nextIndex': _next,
      'coveredKm': _cov / 1000,
      'topSpeed': _top,
      // diagnostics shown in the driver's GPS status card: is the route saved, and is the bus on it?
      'fixes': _filter.used,
      'fixesRejected': _filter.rejected,
      if (_moveSec > 20) 'avgMoving': _moveDist / _moveSec * 3.6,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Trip history `app2_trips/<bus>_<date>_<direction>`: one entry per passed stop, keyed by stop number, so a
  /// retry, an offline replay or a restart can never create a duplicate. Forward and return trips have separate
  /// documents.
  static void _logPassed(Journey plan) {
    final fresh = <int>[for (var i = 0; i < _next && i < plan.stops.length; i++) if (!_logged.contains(i)) i];
    if (fresh.isEmpty) return;
    _logged.addAll(fresh);
    db.doc('app2_trips/${_busId}_${todayKey()}_$_direction').set({
      'busId': _busId,
      'direction': _direction,
      'date': todayKey(),
      'driverUid': uid,
      'stops': {for (final i in fresh) '$i': {'name': plan.stops[i].name, 'at': Timestamp.now()}},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).catchError((Object _) {});
  }

  static Future<void> endTrip() async {
    await _sub?.cancel();
    _sub = null;
    _beat?.cancel();
    _beat = null;
    _plan = null;
    // keep nextIndex so students still see where the trip ended
    await LocalStore.clearTrip(_busId);
    await db.doc(liveDoc(_busId)).set({'tripActive': false, 'speed': 0}, SetOptions(merge: true));
  }

  static Future<void> reportBreakdown(String busId, bool on, String note) =>
      db.doc(liveDoc(busId)).set({'breakdown': on, 'breakdownNote': note}, SetOptions(merge: true));
}

/// Small copies of bus state kept ON THE PHONE (SharedPreferences): the last live state of each bus (students /
/// parents) and the driver's running trip. They let the app show / resume the exact state after being closed,
/// killed or restarted, even before Firestore answers.
class LocalStore {
  static Map<String, dynamic> _enc(Map<String, dynamic> m) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      if (v is Timestamp) {
        out['$k@ms'] = v.millisecondsSinceEpoch;
      } else if (v is num || v is String || v is bool) {
        out[k] = v;
      }
    });
    return out;
  }

  static Map<String, dynamic> _dec(Map<String, dynamic> j) {
    final out = <String, dynamic>{};
    j.forEach((k, v) {
      if (k.endsWith('@ms') && v is int) {
        out[k.substring(0, k.length - 3)] = Timestamp.fromMillisecondsSinceEpoch(v);
      } else {
        out[k] = v;
      }
    });
    return out;
  }

  static Future<void> _save(String key, Map<String, dynamic> m) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, jsonEncode(_enc(m)));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> _load(String key) async {
    try {
      final s = (await SharedPreferences.getInstance()).getString(key);
      if (s == null) return null;
      return _dec(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLive(String busId, Map<String, dynamic> m) => _save('live_$busId', m);
  static Future<Map<String, dynamic>?> loadLive(String busId) => _load('live_$busId');
  static Future<void> saveTrip(String busId, Map<String, dynamic> m) => _save('trip_$busId', m);
  static Future<Map<String, dynamic>?> loadTrip(String busId) => _load('trip_$busId');
  static Future<void> clearTrip(String busId) async {
    try {
      await (await SharedPreferences.getInstance()).remove('trip_$busId');
    } catch (_) {}
  }
}

/// Thrown when a signed-in user is not registered by the institution (no roster entry).
class NotAuthorized implements Exception {
  final String message;
  const NotAuthorized(this.message);
  @override
  String toString() => message;
}

/// What the app knows about a signed-in account.
class Account {
  final String role; // 'admin' | 'driver' | 'student'
  final String bus; // driver/student: their bus
  final String status; // 'active' | 'inactive' | 'pending'
  const Account(this.role, this.bus, {this.status = 'active'});
  bool get active => status == 'active';
}

/// Remembers who is logged in so the app opens straight into the right panel.
/// (The login itself is kept by Firebase Auth; it only ends when the user presses Logout.)
class Session {
  static Future<String?> lastEmail() async => (await SharedPreferences.getInstance()).getString('last_email');
  static Future<void> setLastEmail(String? e) async {
    final p = await SharedPreferences.getInstance();
    if (e == null) { await p.remove('last_email'); } else { await p.setString('last_email', e); }
  }

  static Future<String?> role(String uid) async => (await SharedPreferences.getInstance()).getString('role_$uid');
  static Future<void> setRole(String uid, String role) async =>
      (await SharedPreferences.getInstance()).setString('role_$uid', role);

  /// Bus chosen at sign-up, kept until the profile has really been written to Firestore.
  static Future<String?> pendingBus(String uid) async => (await SharedPreferences.getInstance()).getString('pending_bus_$uid');
  static Future<void> setPendingBus(String uid, String bus) async =>
      (await SharedPreferences.getInstance()).setString('pending_bus_$uid', bus);

  static Future<String?> bus(String uid) async => (await SharedPreferences.getInstance()).getString('bus_$uid');
  static Future<void> setBus(String uid, String bus) async =>
      (await SharedPreferences.getInstance()).setString('bus_$uid', bus);

  static Account _staff(Map<String, dynamic>? m) {
    final role = (m?['role'] ?? 'driver').toString().toLowerCase() == 'admin' ? 'admin' : 'driver';
    final status = m?['active'] == false ? 'inactive' : (m?['status'] ?? 'active').toString();
    return Account(role, busOf(m), status: status);
  }

  /// Reads the account from Firestore (cache first, then server with a timeout).
  /// Staff (admin / driver) have a document in app2_users; everyone else must be a registered student.
  static Future<Account> fetchAccount(String uid) async {
    final ref = db.doc('app2_users/$uid');
    try {
      final c = await ref.get(const GetOptions(source: Source.cache));
      if (c.exists) return _staff(c.data());
    } catch (_) {}
    final s = await ref.get().timeout(const Duration(seconds: 8));
    if (s.exists) return _staff(s.data());
    final sd = await db.doc('app2_students/$uid').get().timeout(const Duration(seconds: 8));
    if (!sd.exists) {
      try {
        await Repo.ensureStudentProfile();
      } on NotAuthorized {
        return const Account('none', 'bus1', status: 'unauthorized');
      }
      return Account('student', busOf((await db.doc('app2_students/$uid').get()).data()));
    }
    final m = sd.data();
    return Account('student', busOf(m), status: (m?['status'] ?? 'active').toString());
  }
}
