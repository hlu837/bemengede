// lib/services/location_tracking_service.dart
//
// Streams the traveler's device GPS to Supabase. Two independent things can
// each want that stream running, so both are tracked here and share one
// underlying Geolocator subscription:
//
//   1. DELIVERY TRACKING — while a specific delivery is in_transit, position
//      goes to `deliveries.current_lat/current_lng` so the sender's
//      SenderTrackingMapScreen (which subscribes to Supabase Realtime on
//      that delivery row) sees live movement. Started/stopped automatically
//      by the Active Deliveries screen — see startTracking()/stopTracking().
//
//   2. LIVE / PRESENCE TRACKING — the traveler dashboard's Live/Off toggle.
//      While "Live", position goes to `profiles.current_lat/current_lng`
//      and `profiles.is_online = true`, so senders can see which travelers
//      are around *before* any delivery has been matched. Started/stopped
//      via goOnline()/goOffline().
//
// Either one alone keeps the GPS stream alive; the stream only stops once
// both are off, so a traveler mid-delivery who flips Live off (or vice
// versa) doesn't lose the tracking that's actually still needed.
//
// NOTE: previously delivery tracking wrote to a `trips` row (keyed by
// traveler_id + status='active'), back when travelers had to post a trip
// before they could carry a delivery. Trips were removed in favor of
// instant matching (sender posts → traveler searches → instant delivery),
// so there's no longer a trip row to write to — delivery tracking keys
// directly on the delivery itself, which is more precise anyway (a
// traveler could in theory have more than one active delivery).
//
// GebetaService.updateTripLocation() is intentionally left as a disabled
// no-op — Gebeta has no live-tracking endpoint. Position updates go
// straight to Supabase, which is what the sender's map already listens to.

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationTrackingService {
  static final LocationTrackingService _instance =
      LocationTrackingService._internal();
  factory LocationTrackingService() => _instance;
  LocationTrackingService._internal();

  final _sb = Supabase.instance.client;
  StreamSubscription<Position>? _positionSub;

  String? _activeDeliveryId;
  bool _isOnline = false;
  String? _travelerId;

  bool get isTracking => _positionSub != null;
  bool get isOnline => _isOnline;

  // ── Live / presence tracking (traveler dashboard toggle) ─────────────────

  /// Call when the traveler flips the "Live" toggle ON.
  /// Marks them online and starts streaming position into their profile
  /// row, independent of any active delivery.
  Future<bool> goOnline(String travelerId) async {
    final permission = await _ensurePermission();
    if (!permission) return false;

    _travelerId = travelerId;
    _isOnline = true;

    try {
      await _sb
          .from('profiles')
          .update({'is_online': true}).eq('id', travelerId);
    } catch (_) {
      // Best-effort — the position updates below will retry the flag too.
    }

    await _ensureStreamRunning();
    return true;
  }

  /// Call when the traveler flips the "Live" toggle OFF.
  Future<void> goOffline() async {
    _isOnline = false;
    final travelerId = _travelerId;
    _travelerId = null;

    if (travelerId != null) {
      try {
        await _sb
            .from('profiles')
            .update({'is_online': false}).eq('id', travelerId);
      } catch (_) {
        // Best-effort — nothing useful to surface for a background flag.
      }
    }

    await _maybeStopStream();
  }

  // ── Delivery tracking (unchanged behavior) ────────────────────────────────

  /// Call when a traveler marks a delivery `in_transit`.
  /// Safe to call repeatedly — it no-ops if already tracking this delivery.
  Future<bool> startTracking(String deliveryId) async {
    if (_activeDeliveryId == deliveryId && isTracking) return true;

    final permission = await _ensurePermission();
    if (!permission) return false;

    _activeDeliveryId = deliveryId;
    await _ensureStreamRunning();
    return true;
  }

  /// Call when a delivery is marked `completed` or `cancelled`.
  Future<void> stopTracking() async {
    _activeDeliveryId = null;
    await _maybeStopStream();
  }

  // ── Shared GPS stream ──────────────────────────────────────────────────────

  Future<void> _ensureStreamRunning() async {
    if (_positionSub != null) return; // already streaming

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 25, // meters — only emit once the traveler has moved
    );

    _positionSub =
        Geolocator.getPositionStream(locationSettings: settings).listen(
      _pushPosition,
      onError: (_) {
        // Swallow stream errors (e.g. GPS momentarily unavailable) —
        // don't crash the app over a dropped location fix.
      },
      cancelOnError: false,
    );
  }

  /// Stops the underlying GPS stream once nothing needs it anymore.
  Future<void> _maybeStopStream() async {
    if (_isOnline || _activeDeliveryId != null) return; // still needed
    await _positionSub?.cancel();
    _positionSub = null;
  }

  Future<void> _pushPosition(Position position) async {
    final now = DateTime.now().toIso8601String();

    final deliveryId = _activeDeliveryId;
    if (deliveryId != null) {
      try {
        await _sb
            .from('deliveries')
            .update({
              'current_lat': position.latitude,
              'current_lng': position.longitude,
              'last_location_at': now,
            })
            .eq('id', deliveryId);
      } catch (_) {
        // Best-effort — a single missed GPS tick shouldn't surface an error
        // to the traveler mid-delivery.
      }
    }

    if (_isOnline && _travelerId != null) {
      try {
        await _sb
            .from('profiles')
            .update({
              'current_lat': position.latitude,
              'current_lng': position.longitude,
              'last_location_at': now,
            })
            .eq('id', _travelerId!);
      } catch (_) {
        // Best-effort — same reasoning as above.
      }
    }
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }
}