// lib/screens/shared/map_screen.dart
// Real Gebeta Maps integration — replaces the previous placeholder stubs.

import 'dart:async';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:gebeta_gl/gebeta_gl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/gebeta_service.dart';
import '../../services/data_service.dart';
import '../../models/models.dart';
import 'web_iframe_map.dart';

// gebeta_gl (MapLibre-based) only actually supports Android and iOS.
// Gebeta's own docs (docs.gebeta.app/docs/tiles/flutter) say so explicitly
// ("Supports ios and android") — pub.dev's platform badge claiming web
// support too is misleading/inaccurate. Use this everywhere we decide
// whether to build a real GebetaMap vs. a lightweight tap-to-pick fallback.
// Deliberately does NOT touch dart:io's Platform class, since that import
// breaks web compilation — defaultTargetPlatform + kIsWeb cover every
// platform safely from one shared foundation import.
bool get _gebetaMapSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

// ── Shared result type returned by LocationPickerScreen ───────────────────────

class LocationResult {
  final LatLng latLng;
  final String address;
  const LocationResult({required this.latLng, required this.address});
}

// ── Constants ─────────────────────────────────────────────────────────────────

const _kAddisAbaba = LatLng(9.0192, 38.7525);
const _kDefaultZoom = 12.0;
const _kTrackingZoom = 13.5;
const _kGreen = Color(0xFF1E7E34);
const _kStyleUrl = GebetaService.styleUrl;
const _kApiKey = GebetaService.apiKey;

// ─────────────────────────────────────────────────────────────────────────────
// UNSUPPORTED-PLATFORM MAP FALLBACK
// Shown on any platform gebeta_gl doesn't actually support (web, Windows,
// Linux, macOS — only Android/iOS have a real implementation per Gebeta's
// own docs). Keeps "tap to drop a pin" working via an approximate lat/lng
// window so flows like LocationPickerScreen stay usable everywhere.
// ─────────────────────────────────────────────────────────────────────────────

class _UnsupportedPlatformMapFallback extends StatelessWidget {
  final LatLng centerTarget;
  final LatLng? picked;
  final void Function(LatLng)? onTap;
  final String? statusText;

  const _UnsupportedPlatformMapFallback({
    required this.centerTarget,
    this.picked,
    this.onTap,
    this.statusText,
  });

  static const double _degSpan = 0.06;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        void handleTap(TapUpDetails details) {
          if (onTap == null) return;
          final dx = (details.localPosition.dx / w) - 0.5;
          final dy = (details.localPosition.dy / h) - 0.5;
          final lat = centerTarget.latitude - dy * _degSpan;
          final lng = centerTarget.longitude + dx * _degSpan;
          onTap!(LatLng(lat, lng));
        }

        return GestureDetector(
          onTapUp: onTap == null ? null : handleTap,
          child: Container(
            color: const Color(0xFFE3EFE6),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _GridPainter()),
                Center(
                  child: Icon(
                    Icons.location_on_rounded,
                    size: 40,
                    color: picked != null ? _kGreen : Colors.black26,
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Material(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(
                        statusText ??
                            'Interactive map preview isn\'t available on this '
                                'this platform. '
                                '${onTap != null ? "Tap anywhere to drop an approximate pin." : ""}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, height: 1.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.06)
      ..strokeWidth = 1;
    const step = 32.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCATION PICKER SCREEN
// Full-screen interactive Gebeta map. User taps to drop a pin; the address is
// reverse-geocoded and shown in a bottom card. Confirming returns LocationResult.
// ─────────────────────────────────────────────────────────────────────────────

class LocationPickerScreen extends StatefulWidget {
  final String title;
  final LatLng? initialLocation;

  const LocationPickerScreen({
    super.key,
    required this.title,
    this.initialLocation,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPickerScreen> {
  GebetaMapController? _controller;
  Symbol? _marker;

  LatLng? _picked;
  String _address = '';
  bool _resolving = false;

  final _gebeta = GebetaService();
  final _searchCtrl = TextEditingController();
  bool _searching = false;
  String? _searchError;

  // gebeta_gl's `myLocationEnabled` turns on MapLibre's native "my location"
  // layer, but the plugin does NOT request the Android runtime location
  // permission itself (confirmed in Gebeta's own docs). If we pass
  // myLocationEnabled: true before permission is granted, the native map
  // view fails to render at all on Android 6.0+ — no crash, no dialog, just
  // a blank screen. So: request permission first, and only ask the map to
  // show the location layer once we know it's actually granted.
  bool _myLocationEnabled = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
  }

  Future<void> _ensureLocationPermission() async {
    if (kIsWeb) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      final granted = permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always;
      if (mounted) setState(() => _myLocationEnabled = granted);
    } catch (_) {
      // Leave _myLocationEnabled false — the pin-drop flow still works
      // without the blue "my location" dot.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Called once the map has fully initialised.
  // Only invoked on non-web platforms — see build() below.
  void _onMapCreated(GebetaMapController controller) {
    _controller = controller;
    final initial = widget.initialLocation ?? _kAddisAbaba;
    if (widget.initialLocation != null) {
      _dropPin(initial);
    }
  }

  // Drop / move pin, then reverse-geocode the coordinate asynchronously.
  Future<void> _dropPin(LatLng coord) async {
    setState(() {
      _picked = coord;
      _address =
          '${coord.latitude.toStringAsFixed(5)}, ${coord.longitude.toStringAsFixed(5)}';
      _resolving = true;
    });

    // Remove the old marker symbol if present.
    if (_marker != null) {
      await _controller?.removeSymbol(_marker!);
      _marker = null;
    }

    // Place new marker.
    _marker = await _controller?.addSymbol(SymbolOptions(
      geometry: coord,
      iconImage: 'marker',
      iconSize: 1.8,
      iconAnchor: 'bottom',
    ));

    // Animate camera to pin.
    await _controller
        ?.animateCamera(CameraUpdate.newLatLngZoom(coord, _kTrackingZoom));

    // Reverse-geocode in the background.
    final resolved = await _gebeta.reverseGeocode(coord);
    if (mounted) {
      setState(() {
        if (resolved != null && resolved.isNotEmpty) _address = resolved;
        _resolving = false;
      });
    }
  }

  void _confirm() {
    if (_picked == null) return;
    Navigator.pop(
      context,
      LocationResult(latLng: _picked!, address: _address),
    );
  }

  // Forward-geocode the search box text, then drop/move the pin there.
  // Reuses _dropPin so this works identically on native (GebetaMapController)
  // and web (WebIframeMap picks up the new `markerAt`/camera move via
  // didUpdateWidget) without any platform-specific branching here.
  Future<void> _search() async {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
    });

    final found = await _gebeta.geocode(query);

    if (!mounted) return;

    if (found == null) {
      setState(() {
        _searching = false;
        _searchError = 'No results found for "$query"';
      });
      return;
    }

    setState(() => _searching = false);
    await _dropPin(found);
  }

  @override
  Widget build(BuildContext context) {
    // NOTE on layout: on web the map is a real <iframe> (see WebIframeMap).
    // Flutter widgets stacked ON TOP of an iframe via Positioned+Stack don't
    // reliably receive pointer events — even wrapped in PointerInterceptor —
    // due to a long-standing Flutter engine limitation specific to iframe
    // platform views (flutter/flutter#81081, #104970, #118452). The old
    // layout floated the search bar and Confirm button directly over the
    // iframe, which is exactly the pattern that triggers it: taps landed on
    // the map underneath instead of the widgets above it.
    //
    // Fix: never let an interactive widget's screen rect overlap the map's.
    // Search bar now lives in the AppBar's `bottom`, and the confirm card
    // sits in a separate Column row below the map — neither ever shares
    // coordinates with the iframe, so there's nothing for it to swallow.
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_searchError != null ? 104 : 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchCtrl,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.white,
                      hintText: _picked == null
                          ? 'Search a location, or tap on the map'
                          : 'Search a different location',
                      hintStyle: const TextStyle(fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: _kGreen),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _kGreen),
                              ),
                            )
                          : (_searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchError = null);
                                  },
                                )
                              : null),
                    ),
                  ),
                ),
                if (_searchError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Material(
                      color: const Color(0xFFB71C1C),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Text(_searchError!,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Map (fills remaining space above the confirm card) ─────────
          Expanded(
            child: Stack(
              children: [
                // gebeta_gl supports Android, iOS, and Web — build the real
                // map there. It has no implementation at all on
                // Windows/Linux/macOS desktop, so fall back to a
                // tap-friendly placeholder only there.
                _gebetaMapSupported
                    ? GebetaMap(
                        apiKey: _kApiKey,
                        styleString: _kStyleUrl,
                        initialCameraPosition: CameraPosition(
                          target: widget.initialLocation ?? _kAddisAbaba,
                          zoom: _kDefaultZoom,
                        ),
                        onMapCreated: _onMapCreated,
                        myLocationEnabled: _myLocationEnabled,
                        onMapClick: (point, coordinates) =>
                            _dropPin(coordinates),
                      )
                    : kIsWeb
                        ? WebIframeMap(
                            initial: widget.initialLocation ?? _kAddisAbaba,
                            zoom: _kDefaultZoom,
                            interactive: true,
                            markerAt: _picked,
                            onTap: _dropPin,
                          )
                        : _UnsupportedPlatformMapFallback(
                            centerTarget:
                                widget.initialLocation ?? _kAddisAbaba,
                            picked: _picked,
                            onTap: _dropPin,
                          ),

                // ── Tap-hint banner ────────────────────────────────────
                // Purely informational (no buttons/taps needed on it), so
                // it's harmless for it to visually sit over the iframe —
                // nothing here depends on receiving a click.
                if (_picked == null)
                  Positioned(
                    top: 16,
                    left: 24,
                    right: 24,
                    child: IgnorePointer(
                      child: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app_rounded,
                                  color: _kGreen, size: 20),
                              SizedBox(width: 8),
                              Text('Tap on the map to choose a location',
                                  style: TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Address card + confirm button (its own row, below the map —
          // never overlaps the iframe, so no pointer events get swallowed)
          if (_picked != null)
            Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black26,
                      blurRadius: 12,
                      offset: Offset(0, -3))
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Selected Location',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black54)),
                    const SizedBox(height: 6),
                    if (_resolving)
                      const Row(
                        children: [
                          SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _kGreen)),
                          SizedBox(width: 10),
                          Text('Resolving address…',
                              style: TextStyle(fontSize: 14)),
                        ],
                      )
                    else
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: _kGreen, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(_address,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        // Confirming shouldn't be blocked on the reverse-
                        // geocode call finishing — _confirm() already falls
                        // back to the raw "lat, lng" address text set
                        // synchronously in _dropPin, so there's nothing to
                        // wait on here.
                        onPressed: _confirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kGreen,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey[400],
                          disabledForegroundColor: Colors.white70,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Confirm Location',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SENDER TRACKING MAP SCREEN
// Shows the route between pickup → dropoff and the traveler's live position
// (refreshed via Supabase Realtime). Falls back gracefully if coordinates are
// unavailable.
// ─────────────────────────────────────────────────────────────────────────────

class SenderTrackingMapScreen extends StatefulWidget {
  final String deliveryId;
  final String travelerId;
  final String packageTitle;

  const SenderTrackingMapScreen({
    super.key,
    required this.deliveryId,
    required this.travelerId,
    required this.packageTitle,
  });

  @override
  State<SenderTrackingMapScreen> createState() =>
      _SenderTrackingMapScreenState();
}

class _SenderTrackingMapScreenState extends State<SenderTrackingMapScreen> {
  GebetaMapController? _controller;

  // Map annotations
  Symbol? _travelerMarker;
  Symbol? _pickupMarker;
  Symbol? _dropoffMarker;
  Line? _routeLine;

  // Data
  DeliveryModel? _delivery;
  LatLng? _travelerPos;
  DateTime? _lastPositionAt;
  Timer? _stallTimer;
  // If we haven't heard a location update in this long, warn the sender
  // that tracking may not actually be working (e.g. traveler's GPS
  // permission is off) instead of leaving them staring at "Waiting…"
  // indefinitely with no explanation.
  static const _kStallThreshold = Duration(seconds: 90);
  bool _trackingStalled = false;

  // Supabase realtime subscription
  RealtimeChannel? _channel;
  bool _loading = true;
  String? _error;

  final _gebeta = GebetaService();
  final _data = DataService();

  @override
  void initState() {
    super.initState();
    _loadDelivery();
    _subscribeToTraveler();
    // Check every 15s whether we've gone stale-long without a location
    // update. Starts the clock from screen-open, so a traveler who never
    // sends a single update (permission off from the start) still gets
    // flagged, not just ones who stop updating mid-trip.
    _lastPositionAt = DateTime.now();
    _stallTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_lastPositionAt!);
      final stalled = elapsed > _kStallThreshold;
      if (stalled != _trackingStalled) {
        setState(() => _trackingStalled = stalled);
      }
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _controller?.dispose();
    _stallTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDelivery() async {
    try {
      final d = await _data.fetchDeliveryById(widget.deliveryId);
      if (mounted)
        setState(() {
          _delivery = d;
          _loading = false;
        });
      if (_controller != null) _drawOnMap();
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  // Subscribe to this delivery's row for real-time location updates —
  // location now lives on `deliveries` directly (see
  // LocationTrackingService), not on a `trips` row, since trips were
  // removed in favor of instant matching.
  void _subscribeToTraveler() {
    final sb = Supabase.instance.client;
    _channel = sb
        .channel('delivery-location-${widget.deliveryId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'deliveries',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.deliveryId,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final lat = (row['current_lat'] as num?)?.toDouble();
            final lng = (row['current_lng'] as num?)?.toDouble();
            if (lat != null && lng != null && mounted) {
              setState(() {
                _travelerPos = LatLng(lat, lng);
                _lastPositionAt = DateTime.now();
                _trackingStalled = false;
              });
              _moveTravelerMarker(LatLng(lat, lng));
            }
          },
        )
        .subscribe();
  }

  // Called once the GebetaMap widget is ready.
  void _onMapCreated(GebetaMapController controller) {
    _controller = controller;
    if (_delivery != null) _drawOnMap();
  }

  // Draw pickup/dropoff markers and route line.
  Future<void> _drawOnMap() async {
    final d = _delivery;
    if (d == null || _controller == null) return;

    final fromLat = d.fromLat;
    final fromLng = d.fromLng;
    final toLat = d.toLat;
    final toLng = d.toLng;

    if (fromLat == null || fromLng == null) return;

    final from = LatLng(fromLat, fromLng);

    // Pickup marker
    _pickupMarker = await _controller!.addSymbol(SymbolOptions(
      geometry: from,
      iconImage: 'marker',
      iconSize: 1.6,
      iconAnchor: 'bottom',
      iconColor: '#1E7E34',
      textField: 'Pickup',
      textOffset: const Offset(0, 1.2),
      textSize: 12,
    ));

    if (toLat != null && toLng != null) {
      final to = LatLng(toLat, toLng);

      // Dropoff marker
      _dropoffMarker = await _controller!.addSymbol(SymbolOptions(
        geometry: to,
        iconImage: 'marker',
        iconSize: 1.6,
        iconAnchor: 'bottom',
        iconColor: '#E53935',
        textField: 'Dropoff',
        textOffset: const Offset(0, 1.2),
        textSize: 12,
      ));

      // Draw route
      final route = await _gebeta.getDirections(from, to);
      final routePoints = (route != null && route.points.isNotEmpty)
          ? route.points
          : [from, to]; // straight line fallback

      _routeLine = await _controller!.addLine(LineOptions(
        geometry: routePoints,
        lineColor: '#1E7E34',
        lineWidth: 4,
        lineOpacity: 0.85,
      ));

      // Fit camera to show both ends
      await _controller!.animateCamera(
        CameraUpdate.newLatLngBounds(
          LatLngBounds(
            southwest: LatLng(
              fromLat < toLat ? fromLat : toLat,
              fromLng < toLng ? fromLng : toLng,
            ),
            northeast: LatLng(
              fromLat > toLat ? fromLat : toLat,
              fromLng > toLng ? fromLng : toLng,
            ),
          ),
          left: 60,
          top: 80,
          right: 60,
          bottom: 200,
        ),
      );
    } else {
      // Only pickup coord available — just centre on it.
      await _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(from, _kTrackingZoom),
      );
    }
  }

  // Move (or create) the traveler marker smoothly.
  Future<void> _moveTravelerMarker(LatLng pos) async {
    if (_controller == null) return;
    if (_travelerMarker != null) {
      await _controller!.updateSymbol(
        _travelerMarker!,
        SymbolOptions(geometry: pos),
      );
    } else {
      _travelerMarker = await _controller!.addSymbol(SymbolOptions(
        geometry: pos,
        iconImage: 'marker',
        iconSize: 1.8,
        iconColor: '#1565C0',
        iconAnchor: 'bottom',
        textField: 'Traveler',
        textOffset: const Offset(0, 1.2),
        textSize: 12,
      ));
    }
    // Pan camera to traveler position without changing zoom.
    await _controller!.animateCamera(CameraUpdate.newLatLng(pos));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.packageTitle,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kGreen,
        foregroundColor: Colors.white,
        actions: [
          if (_travelerPos != null)
            IconButton(
              icon: const Icon(Icons.my_location_rounded),
              tooltip: 'Centre on traveler',
              onPressed: () => _controller?.animateCamera(
                CameraUpdate.newLatLngZoom(_travelerPos!, _kTrackingZoom),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // ── Map ──────────────────────────────────────────────────────────
          // gebeta_gl supports Android, iOS, and Web — build the real map
          // there; fall back only on unsupported desktop platforms.
          _gebetaMapSupported
              ? GebetaMap(
                  apiKey: _kApiKey,
                  styleString: _kStyleUrl,
                  initialCameraPosition: CameraPosition(
                    target: _kAddisAbaba,
                    zoom: _kDefaultZoom,
                  ),
                  onMapCreated: _onMapCreated,
                  myLocationEnabled: false,
                )
              : kIsWeb
                  ? WebIframeMap(
                      initial: _travelerPos ?? _kAddisAbaba,
                      zoom: _kDefaultZoom,
                      interactive: false,
                      markerAt: _travelerPos,
                    )
                  : _UnsupportedPlatformMapFallback(
                      centerTarget: _travelerPos ?? _kAddisAbaba,
                      statusText: _travelerPos != null
                          ? 'Live map preview isn\'t available on this '
                              'platform. Traveler is currently being tracked — '
                              'see status below.'
                          : _trackingStalled
                              ? 'Live map preview isn\'t available on this '
                                  'platform. Live tracking isn\'t updating — '
                                  'the traveler\'s GPS may be off.'
                              : 'Live map preview isn\'t available on this '
                                  'platform. Waiting for traveler location '
                                  'updates…',
                    ),

          // ── Loading overlay ───────────────────────────────────────────
          if (_loading)
            const ColoredBox(
              color: Colors.white54,
              child: Center(child: CircularProgressIndicator(color: _kGreen)),
            ),

          // ── Error banner ──────────────────────────────────────────────
          if (_error != null)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Material(
                color: const Color(0xFFB71C1C),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text(_error!,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),

          // ── Status chip ───────────────────────────────────────────────
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _travelerPos != null
                            ? const Color(0xFF43A047)
                            : _trackingStalled
                                ? const Color(0xFFE65100)
                                : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _travelerPos != null
                            ? 'Live location active — tracking traveler'
                            : _trackingStalled
                                ? 'Live tracking isn\'t updating — the traveler\'s GPS may be off'
                                : 'Waiting for traveler location updates…',
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
