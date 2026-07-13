// lib/services/gebeta_service.dart
// Gebeta Maps API integration for Bemengede (replaces AmbaLay).
//
// Verified against https://docs.gebeta.app (July 2026):
//   ✅ Forward geocoding — GET https://mapapi.gebeta.app/v2/search/geocode
//                          ?query={text}&apiKey={key}
//                          Response: { data: { query, results: [{ id, name,
//                          display_name, category, location:{lat,lng},
//                          address:{city,country,country_code} }] } }
//                          https://docs.gebeta.app/docs/geocoding/geocoding-forward
//   ✅ Reverse geocoding  — GET https://mapapi.gebeta.app/api/v1/route/revgeocoding
//                          ?lat={lat}&lon={lon}&apiKey={key}
//                          Exact success-response field names aren't published
//                          in the docs (only params/status codes are), so
//                          _parseReverseGeocodeAddress() below tries several
//                          plausible shapes defensively. Log/inspect a real
//                          response and tighten this once you've seen one.
//                          https://docs.gebeta.app/docs/geocoding/geocoding-reverse
//   ⚠️ Directions         — GET https://mapapi.gebeta.app/api/route/direction/
//                          ?origin={lat,lng}&destination={lat,lng}&apiKey={key}
//                          Docs confirm the request shape but not the success
//                          response body. getDirections() below parses several
//                          plausible shapes (GeoJSON-ish `path`/`route`/
//                          `coordinates`, or a Google-style
//                          `routes[0].overview_polyline`) — inspect a real
//                          response and simplify once confirmed.
//                          https://docs.gebeta.app/docs/direction
//   ✅ Vector tiles        — rendered via the official `gebeta_gl` Flutter
//                          package (MapLibre-based), not a raw XYZ URL. See
//                          map_screen.dart. Style URL: https://tiles.gebeta.app/styles/standard/style.json
//                          https://docs.gebeta.app/docs/tiles/flutter
//
// Get an API key at https://gebeta.app — this app reads it from
// --dart-define=GEBETA_API_KEY=... (see dart_defines.example.json), never
// hardcoded in source.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gebeta_gl/gebeta_gl.dart' show LatLng;

class GebetaService {
  // ── API Configuration ────────────────────────────────────────────────────
  // Run / build with:
  //   flutter run    --dart-define=GEBETA_API_KEY=your_real_key
  //   flutter build apk --dart-define=GEBETA_API_KEY=your_real_key
  // Or copy dart_defines.example.json -> dart_defines.json, fill in the real
  // key, and pass --dart-define-from-file=dart_defines.json (keep that file
  // out of git — it's already in .gitignore).
  //
  // NOTE: this only keeps the key out of the *source repo* — it's still a
  // client-side app, so a determined user can extract the key from the
  // compiled binary. If usage grows, consider proxying requests through your
  // own backend so the key never ships to the device.
  static const String apiKey = String.fromEnvironment('GEBETA_API_KEY');

  static const String _mapApiBase = 'https://mapapi.gebeta.app';

  /// True if the app was built/run without providing GEBETA_API_KEY.
  /// Check this at startup (see main.dart) so a missing key fails loudly.
  static bool get isApiKeyMissing => apiKey.isEmpty;

  // Vector map style used by the GebetaMap widget in map_screen.dart.
  static const String styleUrl =
      'https://tiles.gebeta.app/styles/standard/style.json';

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        // Docs note apiKey can also be sent as a Bearer token instead of a
        // query param — sending both is harmless belt-and-suspenders.
        'Authorization': 'Bearer $apiKey',
      };

  // ── Forward Geocoding — text → coordinates ──────────────────────────────
  // Confirmed shape: { data: { results: [{ location: { lat, lng }, ... }] } }

  Future<LatLng?> geocode(String query) async {
    try {
      final uri = Uri.parse('$_mapApiBase/v2/search/geocode').replace(
        queryParameters: {'query': query, 'apiKey': apiKey},
      );
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body);
      final results = body?['data']?['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final loc = (results[0] as Map)['location'] as Map?;
      if (loc == null) return null;
      final lat = (loc['lat'] as num?)?.toDouble();
      final lng = (loc['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;

      return LatLng(lat, lng);
    } catch (e) {
      print('Gebeta geocode error: $e');
      return null;
    }
  }

  // ── Reverse Geocoding — coordinates → address ───────────────────────────
  // Request shape confirmed; success response shape is not published, so we
  // try a few plausible field paths before falling back to raw coordinates.

  Future<String?> reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.parse('$_mapApiBase/api/v1/route/revgeocoding').replace(
        queryParameters: {
          'lat': point.latitude.toString(),
          'lon': point.longitude.toString(),
          'apiKey': apiKey,
        },
      );
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        print('Gebeta reverseGeocode HTTP ${res.statusCode}: ${res.body}');
        return null;
      }

      final body = jsonDecode(res.body);
      final address = _parseReverseGeocodeAddress(body);

      // Self-diagnosing: if none of our known/guessed shapes matched, print
      // the raw body so it shows up in `flutter run`/logcat. Paste that JSON
      // back to whoever's maintaining this to get the parser tightened to
      // the real shape instead of guesses.
      if (address == null) {
        print('Gebeta reverseGeocode: no address field found in response. '
            'Raw body: ${res.body}');
      }

      return address;
    } catch (e) {
      print('Gebeta reverseGeocode error: $e');
      return null;
    }
  }

  // Field names a reverse-geocode "address" is plausibly stored under,
  // ordered roughly by likelihood. Checked at every level while walking the
  // response, so this works regardless of nesting depth (root, data.*,
  // data.results[0].*, results[0].address.*, etc.) without needing to know
  // the exact shape ahead of time.
  static const _addressFieldNames = [
    'display_name',
    'formatted_address',
    'name',
    'address',
    'label',
    'description',
  ];

  String? _parseReverseGeocodeAddress(dynamic body) {
    // Unwrap a single-element results/data list, if present, before
    // searching — otherwise a field like `results[0].name` won't be found
    // by the flat key checks below.
    dynamic node = body;
    for (var depth = 0; depth < 4 && node != null; depth++) {
      if (node is Map) {
        for (final key in _addressFieldNames) {
          final value = node[key];
          if (value is String && value.trim().isNotEmpty) return value;
        }
        // `address` sometimes turns out to be a structured object
        // ({city, subcity, country, ...}) rather than one flat string —
        // join whatever string parts it has into something readable.
        final addressObj = node['address'];
        if (addressObj is Map) {
          final parts = addressObj.values
              .whereType<String>()
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (parts.isNotEmpty) return parts.join(', ');
        }
        // Descend into the most likely nesting container.
        final next = node['data'] ?? node['result'] ?? node['results'];
        if (next == null) break;
        node = next is List && next.isNotEmpty ? next[0] : next;
      } else if (node is List && node.isNotEmpty) {
        node = node[0];
      } else {
        break;
      }
    }
    return null;
  }

  // ── Directions — route between two points ───────────────────────────────
  // Request shape confirmed; success response shape is not published in the
  // docs, so this parses several plausible shapes defensively. If none
  // match, distance/duration come back as 0 and points as an empty list
  // (straight line still gets drawn by map_screen.dart from the two
  // endpoints) rather than throwing.

  Future<GebetaRoute?> getDirections(LatLng from, LatLng to) async {
    try {
      final uri = Uri.parse('$_mapApiBase/api/route/direction/').replace(
        queryParameters: {
          'origin': '{${from.latitude},${from.longitude}}',
          'destination': '{${to.latitude},${to.longitude}}',
          'apiKey': apiKey,
        },
      );
      final res = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;

      final body = jsonDecode(res.body);
      return _parseDirectionsResponse(body);
    } catch (e) {
      print('Gebeta directions error: $e');
      return null;
    }
  }

  GebetaRoute? _parseDirectionsResponse(dynamic body) {
    if (body is! Map) return null;

    double distanceM = 0;
    double durationSec = 0;
    List<LatLng> points = [];

    // Shape guess #1 (matches the `gebetamap` Dart client's ResponseData:
    // message/status/totalDistance/path — the closest thing to an official
    // reference for this endpoint's shape).
    if (body.containsKey('path') || body.containsKey('totalDistance')) {
      distanceM = _asDouble(body['totalDistance']);
      durationSec = _asDouble(body['totalTime'] ?? body['duration']);
      points = _parsePointList(body['path']);
    }
    // Shape guess #2: Google-Directions-style routes[].legs[].
    else if (body['routes'] is List) {
      final routes = body['routes'] as List;
      if (routes.isNotEmpty) {
        final route = routes[0] as Map;
        final legs = (route['legs'] as List?) ?? [];
        for (final leg in legs) {
          distanceM +=
              _asDouble((leg as Map)['distance']?['value'] ?? leg['distance']);
          durationSec +=
              _asDouble(leg['duration']?['value'] ?? leg['duration']);
        }
        points = _parsePointList(
            route['path'] ?? route['coordinates'] ?? route['geometry']);
      }
    }
    // Shape guess #3: a flat top-level route object.
    else if (body['route'] != null || body['coordinates'] != null) {
      final route = (body['route'] as Map?) ?? body;
      distanceM = _asDouble(route['distance'] ?? route['totalDistance']);
      durationSec = _asDouble(route['duration'] ?? route['totalTime']);
      points = _parsePointList(route['coordinates'] ?? route['path']);
    }

    if (points.isEmpty && distanceM == 0 && durationSec == 0) return null;

    return GebetaRoute(
      distanceMeters: distanceM,
      durationSeconds: durationSec,
      points: points,
    );
  }

  double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  /// Accepts a list of points in either `[lat, lng]`, `{lat, lng}`/`{lat,
  /// lon}`, or `{latitude, longitude}` shape and normalizes to LatLng.
  List<LatLng> _parsePointList(dynamic raw) {
    if (raw is! List) return [];
    final out = <LatLng>[];
    for (final p in raw) {
      if (p is List && p.length >= 2) {
        // Coordinates are frequently [lng, lat] in GeoJSON-style payloads —
        // Gebeta's own docs use lat-first everywhere else, so we assume the
        // same here. Flip this if a real response comes back reversed.
        out.add(LatLng(_asDouble(p[0]), _asDouble(p[1])));
      } else if (p is Map) {
        final lat = p['lat'] ?? p['latitude'];
        final lng = p['lng'] ?? p['lon'] ?? p['longitude'];
        if (lat != null && lng != null) {
          out.add(LatLng(_asDouble(lat), _asDouble(lng)));
        }
      }
    }
    return out;
  }

  // ── Trip tracking ────────────────────────────────────────────────────────
  // No documented Gebeta live-tracking endpoint used here. Live traveler
  // position is handled via Supabase Realtime instead (see map_screen.dart).
  // Kept as a disabled no-op so nothing crashes if still referenced.
  Future<bool> updateTripLocation({
    required String tripId,
    required LatLng location,
  }) async {
    return false;
  }
}

// ── Data classes ────────────────────────────────────────────────────────────

class GebetaRoute {
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;

  const GebetaRoute({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
  });

  String get distanceText {
    if (distanceMeters >= 1000) {
      return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
    }
    return '${distanceMeters.toInt()} m';
  }

  String get durationText {
    final mins = (durationSeconds / 60).round();
    if (mins >= 60) return '${mins ~/ 60}h ${mins % 60}m';
    return '${mins}min';
  }
}
