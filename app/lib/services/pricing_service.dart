// lib/services/pricing_service.dart
// Automated distance-based pricing engine.
//
// Price = base fare + (distance in km * per-km rate) + (weight over 1kg *
//         per-kg rate) + delivery-type surcharge (Office Drop-off costs more
//         than Hand-to-Hand, per spec).
//
// Rates are read from the `platform_settings` table (same table the admin
// "Fee Management" screen already edits — see admin_screens.dart
// AdminFeesScreen) under these keys, so admins can tune pricing without a
// redeploy:
//   pricing_base_fare_etb                 (flat starting fare, ETB)
//   pricing_per_km_rate_etb               (ETB per km of route distance)
//   pricing_per_kg_rate_etb               (ETB per kg above the first 1kg)
//   pricing_office_dropoff_surcharge_etb  (flat add-on for Office Drop-off)
//   pricing_min_price_etb                 (floor — price never quoted below this)
//
// If a row is missing (e.g. fresh install before an admin has touched Fee
// Management), sane defaults below are used so the app still works.

import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:gebeta_gl/gebeta_gl.dart' show LatLng;
import 'gebeta_service.dart';

class PriceBreakdown {
  final double distanceKm;
  final double baseFare;
  final double distanceCost;
  final double weightCost;
  final double typeSurcharge;
  final double total;
  final bool
      distanceEstimated; // true if Gebeta directions failed and we fell back to straight-line

  const PriceBreakdown({
    required this.distanceKm,
    required this.baseFare,
    required this.distanceCost,
    required this.weightCost,
    required this.typeSurcharge,
    required this.total,
    required this.distanceEstimated,
  });
}

class PricingRates {
  final double baseFare;
  final double perKmRate;
  final double perKgRate;
  final double officeDropoffSurcharge;
  final double minPrice;

  const PricingRates({
    required this.baseFare,
    required this.perKmRate,
    required this.perKgRate,
    required this.officeDropoffSurcharge,
    required this.minPrice,
  });

  static const defaults = PricingRates(
    baseFare: 50, // ETB flat starting fare
    perKmRate: 12, // ETB per km
    perKgRate: 30, // ETB per kg above the first 1kg
    officeDropoffSurcharge: 25, // Office Drop-off costs more (per spec)
    minPrice: 60, // never quote below this
  );
}

class PricingService {
  final _sb = Supabase.instance.client;
  final _gebeta = GebetaService();

  static const _keyBaseFare = 'pricing_base_fare_etb';
  static const _keyPerKm = 'pricing_per_km_rate_etb';
  static const _keyPerKg = 'pricing_per_kg_rate_etb';
  static const _keyOfficeFee = 'pricing_office_dropoff_surcharge_etb';
  static const _keyMinPrice = 'pricing_min_price_etb';

  /// Seeds platform_settings with default pricing rows if missing, so they
  /// show up immediately in AdminFeesScreen ("keys containing
  /// fee/rate/commission") for admins to tune. Safe to call repeatedly —
  /// only inserts keys that don't already exist, never overwrites an
  /// admin's saved value.
  Future<void> ensureDefaultRatesExist() async {
    try {
      final keys = [
        _keyBaseFare,
        _keyPerKm,
        _keyPerKg,
        _keyOfficeFee,
        _keyMinPrice
      ];
      final existing = await _sb
          .from('platform_settings')
          .select('setting_key')
          .inFilter('setting_key', keys);
      final have = (existing as List)
          .map((e) => (e as Map)['setting_key'] as String)
          .toSet();

      final defaultsMap = <String, double>{
        _keyBaseFare: PricingRates.defaults.baseFare,
        _keyPerKm: PricingRates.defaults.perKmRate,
        _keyPerKg: PricingRates.defaults.perKgRate,
        _keyOfficeFee: PricingRates.defaults.officeDropoffSurcharge,
        _keyMinPrice: PricingRates.defaults.minPrice,
      };

      for (final entry in defaultsMap.entries) {
        if (!have.contains(entry.key)) {
          await _sb.from('platform_settings').upsert({
            'setting_key': entry.key,
            'setting_value': entry.value.toString(),
          });
        }
      }
    } catch (e) {
      // Non-fatal — calculatePrice() falls back to PricingRates.defaults anyway.
      print('PricingService.ensureDefaultRatesExist error: $e');
    }
  }

  Future<PricingRates> fetchRates() async {
    try {
      final keys = [
        _keyBaseFare,
        _keyPerKm,
        _keyPerKg,
        _keyOfficeFee,
        _keyMinPrice
      ];
      final rows = await _sb
          .from('platform_settings')
          .select('setting_key, setting_value')
          .inFilter('setting_key', keys);
      final map = {
        for (final r in (rows as List))
          (r as Map)['setting_key'] as String: (r)['setting_value']
      };

      double read(String key, double fallback) {
        final v = map[key];
        if (v == null) return fallback;
        return double.tryParse(v.toString()) ?? fallback;
      }

      return PricingRates(
        baseFare: read(_keyBaseFare, PricingRates.defaults.baseFare),
        perKmRate: read(_keyPerKm, PricingRates.defaults.perKmRate),
        perKgRate: read(_keyPerKg, PricingRates.defaults.perKgRate),
        officeDropoffSurcharge:
            read(_keyOfficeFee, PricingRates.defaults.officeDropoffSurcharge),
        minPrice: read(_keyMinPrice, PricingRates.defaults.minPrice),
      );
    } catch (e) {
      print('PricingService.fetchRates error: $e');
      return PricingRates.defaults;
    }
  }

  /// Road distance in km between two points. Tries Gebeta Directions first
  /// (actual route distance); if that's unavailable (missing API key,
  /// endpoint shape mismatch, no network) falls back to straight-line
  /// (haversine) distance scaled by 1.3x as a rough road-distance estimate
  /// for Addis Ababa's street grid.
  Future<({double km, bool estimated})> getDistanceKm(
      LatLng from, LatLng to) async {
    final route = await _gebeta.getDirections(from, to);
    if (route != null && route.distanceMeters > 0) {
      return (km: route.distanceMeters / 1000, estimated: false);
    }
    final straightLineKm = _haversineKm(from, to);
    return (km: straightLineKm * 1.3, estimated: true);
  }

  double _haversineKm(LatLng a, LatLng b) {
    const r = 6371.0; // Earth radius km
    final dLat = _deg2rad(b.latitude - a.latitude);
    final dLng = _deg2rad(b.longitude - a.longitude);
    final lat1 = _deg2rad(a.latitude);
    final lat2 = _deg2rad(b.latitude);
    final h = (1 - math.cos(dLat)) / 2 +
        math.cos(lat1) * math.cos(lat2) * (1 - math.cos(dLng)) / 2;
    return 2 * r * math.asin(math.sqrt(h));
  }

  double _deg2rad(double d) => d * (math.pi / 180);

  /// Computes the full price breakdown for a delivery request.
  PriceBreakdown calculatePrice({
    required double distanceKm,
    required double weightKg,
    required String deliveryType, // 'hand' | 'office'
    required PricingRates rates,
    required bool distanceEstimated,
  }) {
    final distanceCost = distanceKm * rates.perKmRate;
    final billableWeight = weightKg > 1 ? weightKg - 1 : 0;
    final weightCost = billableWeight * rates.perKgRate;
    final typeSurcharge =
        deliveryType == 'office' ? rates.officeDropoffSurcharge : 0.0;

    var total = rates.baseFare + distanceCost + weightCost + typeSurcharge;
    if (total < rates.minPrice) total = rates.minPrice;

    return PriceBreakdown(
      distanceKm: distanceKm,
      baseFare: rates.baseFare,
      distanceCost: distanceCost,
      weightCost: weightCost,
      typeSurcharge: typeSurcharge,
      total: total,
      distanceEstimated: distanceEstimated,
    );
  }
}
