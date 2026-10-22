import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../data.dart';
import '../theme.dart';

class MapEditResult {
  final List<Stop> stops;
  final List<double> geo;
  MapEditResult(this.stops, this.geo);
}

class _Place {
  final String name;
  final LatLng pos;
  _Place(this.name, this.pos);
}

/// Edit one journey on an OpenStreetMap map.
/// - Move the map so the red pin is on a stop, then "Add stop" (snapped to the nearest road, named automatically).
/// - Tap a numbered pin to select it: drag it to move it (it snaps to the road when dropped), rename or delete it.
/// - The road route and the distance between stops are recalculated after every change.
class MapEditorScreen extends StatefulWidget {
  final String title;
  final List<Stop> stops;
  final List<double> geometry;
  final List<double> refGeometry; // the other direction, shown in grey for reference
  const MapEditorScreen({super.key, required this.title, required this.stops, required this.geometry, this.refGeometry = const []});
  @override
  State<MapEditorScreen> createState() => _MapEditorScreenState();
}

class _MapEditorScreenState extends State<MapEditorScreen> {
  final _map = MapController();
  final _mapKey = GlobalKey();
  final _name = TextEditingController();
  final _query = TextEditingController();
  late List<Stop> _stops;
  late List<double> _geo;
  late final List<LatLng> _ref;
  late final ValueNotifier<LatLng> _center;
  List<_Place> _results = [];
  int? _sel;
  bool _dragging = false, _searching = false, _locating = false, _busy = false, _routing = false;
  int _token = 0;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _stops = [...widget.stops];
    _geo = widget.geometry;
    final r = widget.refGeometry;
    _ref = [for (var i = 0; i + 1 < r.length; i += 2) LatLng(r[i], r[i + 1])];
    final placed = _stops.where((s) => s.lat != 0 || s.lng != 0).toList();
    _center = ValueNotifier(placed.isNotEmpty ? LatLng(placed.last.lat, placed.last.lng) : const LatLng(9.42, 76.33));
  }

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    _center.dispose();
    _map.dispose();
    super.dispose();
  }

  void _done() => Navigator.pop(context, MapEditResult(_stops, _geo));

  List<LatLng> get _line => [for (var i = 0; i + 1 < _geo.length; i += 2) LatLng(_geo[i], _geo[i + 1])];

  double get _totalM => _stops.fold(0.0, (a, s) => a + s.distFromPrev);
  double get _totalS => _stops.fold(0.0, (a, s) => a + s.durFromPrev);

  // ---------- road route + distances ----------
  Future<void> _recalc() async {
    if (_stops.length < 2) {
      setState(() { _geo = []; _stops = withLegs(_stops, const [], const []); });
      return;
    }
    final t = ++_token;
    setState(() => _routing = true);
    try {
      final r = await Geo.route(_stops);
      if (!mounted || t != _token) return;
      setState(() {
        _geo = r.geo;
        _stops = withLegs(_stops, r.legs, r.durations);
        final warn = Geo.detourNote(_stops, r); // a leg that loops round side lanes / a canal
        if (warn != null) _msg = warn;
      });
    } catch (_) {
      if (mounted && t == _token) setState(() => _msg = 'Could not calculate the road route (offline?). Stops are kept.');
    }
    if (mounted && t == _token) setState(() => _routing = false);
  }

  // ---------- add / select / drag ----------
  Future<void> _addHere() async {
    setState(() { _busy = true; _msg = null; });
    final c = _center.value;
    var lat = c.latitude, lng = c.longitude;
    // snap to the main road centre line: the road that runs in the direction of travel (previous stop -> here)
    double? heading;
    if (_stops.isNotEmpty) {
      final l = _stops.last;
      if ((l.lat != 0 || l.lng != 0) && hav(l.lat, l.lng, lat, lng) > 15) heading = Geo.bearing(l.lat, l.lng, lat, lng);
    }
    final sn = await Geo.snap(lat, lng, heading: heading);
    if (sn != null) { lat = sn[0]; lng = sn[1]; }
    var name = _name.text.trim();
    if (name.isEmpty) name = await Geo.placeName(lat, lng, 'en') ?? 'Stop ${_stops.length + 1}';
    var local = await Geo.placeName(lat, lng, 'ml') ?? '';
    if (local == name) local = '';
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _stops.add(Stop(name, lat, lng, localName: local));
      _name.clear();
      _busy = false;
      _msg = 'Added "$name" as stop ${_stops.length}${sn == null ? ' (no road found nearby, kept exact spot)' : ''}.';
    });
    _map.move(LatLng(lat, lng), _map.camera.zoom);
    _recalc();
  }

  void _select(int? i) {
    setState(() {
      _sel = i;
      _name.text = i == null ? '' : _stops[i].name;
    });
  }

  LatLng? _toLatLng(Offset global) {
    final box = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    final local = box.globalToLocal(global);
    return _map.camera.offsetToCrs(local);
  }

  void _dragUpdate(int i, Offset global) {
    final ll = _toLatLng(global);
    if (ll == null) return;
    setState(() => _stops[i] = _stops[i].copyWith(lat: ll.latitude, lng: ll.longitude));
  }

  Future<void> _dropped(int i) async {
    setState(() => _dragging = false);
    final s = _stops[i];
    // snap onto the main road that runs in the direction of travel (towards the next stop)
    final sn = await Geo.snap(s.lat, s.lng, heading: Geo.travelBearing(_stops, i));
    if (!mounted) return;
    if (sn != null) setState(() => _stops[i] = _stops[i].copyWith(lat: sn[0], lng: sn[1]));
    HapticFeedback.selectionClick();
    _recalc();
  }

  void _delete() {
    final i = _sel;
    if (i == null) return;
    setState(() {
      _stops.removeAt(i);
      _sel = null;
      _name.clear();
    });
    _recalc();
  }

  // ---------- search / my location ----------
  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() { _searching = true; _msg = null; });
    try {
      final res = await http
          .get(
            Uri.https('nominatim.openstreetmap.org', '/search', {'format': 'jsonv2', 'q': q, 'limit': '6', 'countrycodes': 'in'}),
            headers: {'User-Agent': 'CarmelCollegeBus/1.0'},
          )
          .timeout(const Duration(seconds: 10));
      final list = jsonDecode(res.body) as List;
      _results = [
        for (final e in list) _Place((e['display_name'] ?? '').toString(), LatLng(double.parse(e['lat'].toString()), double.parse(e['lon'].toString()))),
      ];
      if (_results.isEmpty) _msg = 'No places found. Try another name, or move the map by hand.';
    } catch (_) {
      _msg = 'Search failed (check internet). You can still move the map by hand.';
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _myLocation() async {
    setState(() { _locating = true; _msg = null; });
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) throw 'Location permission denied';
      final p = await Geolocator.getCurrentPosition();
      _map.move(LatLng(p.latitude, p.longitude), 16);
    } catch (e) {
      _msg = 'Could not get your location: $e';
    }
    if (mounted) setState(() => _locating = false);
  }

  // ---------- UI ----------
  Widget _pin(int i) {
    final sel = _sel == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _select(sel ? null : i),
      onPanDown: (_) => setState(() => _dragging = true),
      onPanStart: (_) {
        if (_sel != i) _select(i);
      },
      onPanUpdate: (d) => _dragUpdate(i, d.globalPosition),
      onPanEnd: (_) => _dropped(i),
      onPanCancel: () => setState(() => _dragging = false),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: sel ? kAmber : kYellow,
          border: Border.all(color: kBg, width: sel ? 2 : 1.4),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 3)],
        ),
        child: Text('${i + 1}', style: TextStyle(color: kOnGold, fontSize: sel ? 12 : 10.5, fontWeight: FontWeight.w800)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sel = _sel;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: BackButton(onPressed: _done),
          actions: [TextButton(onPressed: _done, child: const Text('Done', style: TextStyle(color: kYellow, fontWeight: FontWeight.w800)))],
        ),
        body: Column(children: [
          Expanded(
            child: Stack(children: [
              FlutterMap(
                key: _mapKey,
                mapController: _map,
                options: MapOptions(
                  initialCenter: _center.value,
                  initialZoom: 13,
                  interactionOptions: InteractionOptions(flags: _dragging ? InteractiveFlag.none : InteractiveFlag.all),
                  onPositionChanged: (camera, _) {
                    final c = camera.center;
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _center.value != c) _center.value = c;
                    });
                  },
                  onTap: (_, __) {
                    if (_sel != null) _select(null);
                  },
                ),
                children: [
                  TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.carmel.college_bus'),
                  if (_ref.length > 1) PolylineLayer(polylines: [Polyline(points: _ref, strokeWidth: 3, color: Colors.grey)]),
                  if (_geo.length >= 4) PolylineLayer(polylines: [Polyline(points: _line, strokeWidth: 5, color: kBlue)]),
                  MarkerLayer(markers: [
                    for (var i = 0; i < _stops.length; i++)
                      if (_stops[i].lat != 0 || _stops[i].lng != 0)
                        Marker(point: LatLng(_stops[i].lat, _stops[i].lng), width: _sel == i ? 32 : 26, height: _sel == i ? 32 : 26, child: _pin(i)),
                  ]),
                  const RichAttributionWidget(attributions: [TextSourceAttribution('OpenStreetMap contributors')]),
                ],
              ),
              if (sel == null)
                const IgnorePointer(
                  child: Center(child: Padding(padding: EdgeInsets.only(bottom: 34), child: Icon(Icons.location_pin, size: 48, color: kRed))),
                ),
              Positioned(
                top: 8, left: 8, right: 8,
                child: Column(children: [
                  Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(14),
                    color: kBg2,
                    child: TextField(
                      controller: _query,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _search(),
                      decoration: InputDecoration(
                        hintText: 'Search a place (e.g. Kayamkulam)',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searching
                            ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _search),
                      ),
                    ),
                  ),
                  if (_results.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(color: kBg2, borderRadius: BorderRadius.circular(14)),
                      child: ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          for (final r in _results)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined, color: kYellow),
                              title: Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              onTap: () {
                                _map.move(r.pos, 16);
                                setState(() => _results = []);
                              },
                            ),
                        ],
                      ),
                    ),
                ]),
              ),
              Positioned(
                left: 10, bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kBg2.o(.95), borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_routing) const Padding(padding: EdgeInsets.only(right: 8), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))),
                    Text('${_stops.length} stops • ${(_totalM / 1000).toStringAsFixed(1)} km${_totalS > 0 ? ' • ~${durText(_totalS)}' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
              Positioned(
                right: 12, bottom: 12,
                child: FloatingActionButton.small(
                  heroTag: null,
                  onPressed: _locating ? null : _myLocation,
                  child: _locating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
                ),
              ),
            ]),
          ),
          Container(
            decoration: const BoxDecoration(color: kBg2),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: SafeArea(
              top: false,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (sel == null)
                  ValueListenableBuilder<LatLng>(
                    valueListenable: _center,
                    builder: (_, c, __) => Text('Pin at ${c.latitude.toStringAsFixed(5)}, ${c.longitude.toStringAsFixed(5)} • tap a numbered pin to edit it',
                        style: const TextStyle(color: kMuted, fontSize: 12)),
                  )
                else
                  Text(
                    'Stop ${sel + 1}${_stops[sel].distFromPrev > 0 ? ' • ${(_stops[sel].distFromPrev / 1000).toStringAsFixed(1)} km • ${durText(_stops[sel].durFromPrev)} from previous' : ''} • drag the pin, it snaps to the road',
                    style: const TextStyle(color: kAmber, fontSize: 12),
                  ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (v) {
                        final i = _sel;
                        if (i != null && v.trim().isNotEmpty) _stops[i] = _stops[i].copyWith(name: v.trim());
                      },
                      onSubmitted: (_) => sel == null ? _addHere() : _select(null),
                      decoration: InputDecoration(
                        hintText: sel == null ? 'Stop name (empty = auto-name)' : 'Rename stop',
                        isDense: true,
                        fillColor: kCard,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (sel == null)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(110, 50)),
                      onPressed: _busy ? null : _addHere,
                      child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add stop'),
                    )
                  else ...[
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: kRed.o(.2), foregroundColor: kRed),
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: kYellow, foregroundColor: kOnGold),
                      onPressed: () => _select(null),
                      icon: const Icon(Icons.check),
                    ),
                  ],
                ]),
                if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, style: const TextStyle(color: kAmber, fontSize: 12))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
