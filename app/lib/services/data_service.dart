// lib/services/data_service.dart
// All queries mapped to real Supabase tables & columns

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/models.dart';
import '../models/user_profile.dart';

class DataService {
  final _sb = Supabase.instance.client;

  // ── Profiles ──────────────────────────────────────────────────────────────

  Future<UserProfile?> fetchProfile(String userId) async {
    final data =
        await _sb.from('profiles').select().eq('id', userId).maybeSingle();
    return data == null ? null : UserProfile.fromMap(data);
  }

  Future<String?> updateProfile(
      String userId, Map<String, dynamic> updates) async {
    try {
      await _sb.from('profiles').update(updates).eq('id', userId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Live / presence status ───────────────────────────────────────────────
  // Backs the traveler dashboard's Live/Off toggle. Reading a user's own
  // `is_online` flag is allowed by the existing self-only SELECT policy on
  // `profiles` — actually flipping it and streaming position updates is
  // handled by LocationTrackingService (goOnline/goOffline), not here.

  /// Whether the given traveler is currently marked Live. Own-row read only.
  Future<bool> fetchTravelerLiveStatus(String travelerId) async {
    final data = await _sb
        .from('profiles')
        .select('is_online')
        .eq('id', travelerId)
        .maybeSingle();
    return (data?['is_online'] as bool?) ?? false;
  }

  /// Travelers currently Live, with just enough info to plot them on a map.
  /// Routed through a SECURITY DEFINER RPC (see
  /// supabase_add_traveler_live_status.sql) since `profiles` isn't broadly
  /// readable — only the fields exposed by fetch_online_travelers() are.
  Future<List<Map<String, dynamic>>> fetchOnlineTravelers() async {
    final data = await _sb.rpc('fetch_online_travelers');
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<Map<String, dynamic>?> fetchProfileSettings(String userId) async {
    return await _sb
        .from('profiles')
        .select(
            'id, full_name, nickname, email, phone, preferred_payment, payment_account, avatar_url, kyc_status, role')
        .eq('id', userId)
        .maybeSingle();
  }

  // ── NEW: Check if user is blocked (for login/auth wrapper) ───────────────
  Future<bool> isUserBlocked(String userId) async {
    try {
      // system_settings is a single-row table with a blocked_users TEXT[]
      // column, not a key/value table — use the SECURITY DEFINER function
      // from supabase_system_settings.sql instead, which any signed-in user
      // can call safely.
      final blocked = await _sb
          .rpc('is_user_blocked', params: {'check_user_id': userId});
      return blocked as bool? ?? false;
    } catch (e) {
      return false;
    }
  }

  // ── NEW: Fetch blocked user reason (stored in profile or separate tracking) ─
  // If you want to store a reason why someone was blocked, you'd need a new table.
  // For now, we'll use a simple flag. You can extend this later.
  Future<String?> fetchBlockedReason(String userId) async {
    try {
      final data = await _sb
          .from('profiles')
          .select('blocked_reason')
          .eq('id', userId)
          .maybeSingle();
      return data?['blocked_reason'] as String?;
    } catch (e) {
      return null;
    }
  }

  // ── NEW: Set blocked reason on profile (call this when rejecting commission proof)
  Future<String?> setBlockedReason(String userId, String reason) async {
    try {
      await _sb.from('profiles').update({
        'blocked_reason': reason,
      }).eq('id', userId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Packages ──────────────────────────────────────────────────────────────

  Future<List<PackageModel>> fetchSenderPackages(String userId) async {
    final data = await _sb
        .from('packages')
        .select()
        .eq('sender_id', userId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => PackageModel.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<PackageModel>> fetchAvailablePackages(
      String excludeUserId) async {
    // Travelers see packages with status 'pending' that aren't theirs (per
    // RLS). NOTE: this used to filter on 'matched', but nothing in the app
    // ever transitions a package to that status after creation -- packages
    // are created as 'pending' (see sender_packages_screen.dart) and stay
    // that way until someone's request on it is actually approved, so
    // 'matched' packages simply never existed and this feed was always
    // empty.
    final data = await _sb
        .from('packages')
        .select()
        .eq('status', 'pending')
        .neq('sender_id', excludeUserId)
        .order('created_at', ascending: false);

    var packages =
        (data as List).map((m) => m as Map<String, dynamic>).toList();
    if (packages.isEmpty) return [];

    // Multiple travelers can request the same package (the sender picks
    // one), but this traveler shouldn't see — or be able to re-request —
    // a package they already have a pending request on.
    final myPending = await _sb
        .from('delivery_approvals')
        .select('package_id')
        .eq('traveler_id', excludeUserId)
        .eq('status', 'pending');
    final alreadyRequested = (myPending as List)
        .map((m) => (m as Map)['package_id'] as String?)
        .whereType<String>()
        .toSet();
    if (alreadyRequested.isNotEmpty) {
      packages =
          packages.where((p) => !alreadyRequested.contains(p['id'])).toList();
    }
    if (packages.isEmpty) return [];

    // Fetch sender profiles from profiles_public (readable by all authenticated users per RLS)
    final senderIds =
        packages.map((p) => p['sender_id'] as String).toSet().toList();
    final profiles = await _sb
        .from('profiles_public')
        .select('id, nickname, full_name')
        .inFilter('id', senderIds);
    final profileMap = {
      for (final p in (profiles as List)) (p as Map)['id']: p
    };

    return packages
        .map((m) => PackageModel.fromMap(m,
            profile: profileMap[m['sender_id']] as Map<String, dynamic>?))
        .toList();
  }

  Future<String?> insertPackage(Map<String, dynamic> data) async {
    try {
      await _sb.from('packages').insert(data);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deletePackage(String packageId) async {
    try {
      await _sb.from('packages').delete().eq('id', packageId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Instant Match (Sender posts → Traveler searches → instant delivery) ──
  // Replaces the old delivery_approvals request/approve flow entirely: the
  // moment a traveler taps "Request Delivery" on an available package, this
  // creates the real delivery straight away — no sender approval step, no
  // pending-request inbox. Mirrors the careful rollback style of the old
  // approval-accept path so a partial failure doesn't leave things half
  // applied (package marked matched but no delivery, etc).
  Future<String?> instantMatchDelivery({
    required String packageId,
    required String senderId,
    required String travelerId,
  }) async {
    try {
      final activeCount = await _sb
          .from('deliveries')
          .select('id')
          .eq('traveler_id', travelerId)
          .inFilter(
              'status', ['accepted', 'in_transit']).count(CountOption.exact);
      if (activeCount.count >= 2) {
        return 'You already have 2 active deliveries. Complete one before requesting another.';
      }

      final pkg = await _sb
          .from('packages')
          .select('offered_price, from_location, to_location, status')
          .eq('id', packageId)
          .maybeSingle();
      if (pkg == null) return 'This package no longer exists.';
      if (pkg['status'] != 'pending') {
        return 'Someone else already matched with this package.';
      }

      final packageUpdate = await _sb
          .from('packages')
          .update({'status': 'matched'})
          .eq('id', packageId)
          .eq('status', 'pending') // guards against a race with another traveler
          .select('id');
      if (packageUpdate.isEmpty) {
        return 'Someone else already matched with this package.';
      }

      final amount = (pkg['offered_price'] as num?)?.toDouble() ?? 0.0;
      try {
        await _sb.from('deliveries').insert({
          'sender_id': senderId,
          'traveler_id': travelerId,
          'package_id': packageId,
          'status': 'accepted',
          'amount': amount,
          'payment_status': 'pending',
          'pickup_location': pkg['from_location'] as String? ?? '',
          'dropoff_location': pkg['to_location'] as String? ?? '',
        });
      } catch (e) {
        // Roll the package back to pending so this isn't left half-applied.
        await _sb
            .from('packages')
            .update({'status': 'pending'}).eq('id', packageId);
        rethrow;
      }

      return null;
    } catch (e) {
      return e.toString();
    }
  }


  // ── Traveler Offers ───────────────────────────────────────────────────────

  Future<List<TravelerOffer>> fetchTravelerOffers(String travelerId) async {
    final data = await _sb
        .from('traveler_offers')
        .select('*, packages(title, from_location, to_location, weight)')
        .eq('traveler_id', travelerId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => TravelerOffer.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<TravelerOffer>> fetchSenderOffers(String senderId) async {
    // Senders see offers on their packages
    final packages =
        await _sb.from('packages').select('id').eq('sender_id', senderId);
    final pkgIds =
        (packages as List).map((p) => (p as Map)['id'] as String).toList();
    if (pkgIds.isEmpty) return [];

    final data = await _sb
        .from('traveler_offers')
        .select(
            '*, packages(title, from_location, to_location, weight, offered_price)')
        .inFilter('package_id', pkgIds)
        .eq('status', 'active')
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => TravelerOffer.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<String?> insertTravelerOffer({
    required String travelerId,
    required String packageId,
    String? tripId,
    double? price,
  }) async {
    try {
      await _sb.from('traveler_offers').insert({
        'traveler_id': travelerId,
        'package_id': packageId,
        if (tripId != null) 'trip_id': tripId,
        if (price != null) 'price': price,
        'status': 'active',
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updateOfferStatus(String offerId, String status) async {
    try {
      await _sb
          .from('traveler_offers')
          .update({'status': status}).eq('id', offerId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Trips ─────────────────────────────────────────────────────────────────

  Future<List<TripModel>> fetchActiveTrips() async {
    final tripsData = await _sb
        .from('trips')
        .select()
        .eq('status', 'active')
        .order('created_at', ascending: false);
    final trips =
        (tripsData as List).map((m) => m as Map<String, dynamic>).toList();
    if (trips.isEmpty) return [];

    final travelerIds =
        trips.map((t) => t['traveler_id'] as String).toSet().toList();

    // profiles_public is readable by all authenticated users (per RLS policy)
    final profiles = await _sb
        .from('profiles_public')
        .select('id, nickname, full_name, avatar_url')
        .inFilter('id', travelerIds);
    final profileMap = {
      for (final p in (profiles as List)) (p as Map)['id']: p
    };

    // KYC status from profiles
    final kycProfiles = await _sb
        .from('profiles')
        .select('id, kyc_status')
        .inFilter('id', travelerIds);
    final kycMap = {
      for (final k in (kycProfiles as List)) k['id']: k['kyc_status']
    };

    // Completed deliveries count
    final approvals = await _sb
        .from('delivery_approvals')
        .select('traveler_id')
        .inFilter('traveler_id', travelerIds)
        .eq('status', 'approved');
    final deliveryCount = <String, int>{};
    for (final d in (approvals as List)) {
      final id = (d as Map)['traveler_id'] as String;
      deliveryCount[id] = (deliveryCount[id] ?? 0) + 1;
    }

    return trips.map((t) {
      final tid = t['traveler_id'] as String;
      return TripModel.fromMap(
        t,
        profile: profileMap[tid] as Map<String, dynamic>?,
        isVerified: kycMap[tid] == 'approved',
        completedDeliveries: deliveryCount[tid] ?? 0,
      );
    }).toList();
  }

  // ── KYC ───────────────────────────────────────────────────────────────────

  Future<KycStatus> fetchKycStatus(String userId) async {
    final data = await _sb
        .from('profiles')
        .select('kyc_status')
        .eq('id', userId)
        .maybeSingle();
    return KycStatusExt.fromString(data?['kyc_status'] as String?);
  }

  Future<Map<String, dynamic>?> fetchKycDocument(String userId) async {
    return await _sb
        .from('kyc_documents')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<String?> submitKyc({
    required String userId,
    required String documentType,
    required String documentUrl,
    String? selfieUrl,
    String? notes,
  }) async {
    try {
      await _sb.from('kyc_documents').insert({
        'user_id': userId,
        'document_type': documentType,
        'document_url': documentUrl,
        'selfie_url': selfieUrl,
        'notes': notes,
        'status': 'pending',
      });
      await _sb
          .from('profiles')
          .update({'kyc_status': 'pending'}).eq('id', userId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Full KYC submission including reference person + supporting document
  Future<void> submitKycFull({
    required String userId,
    required String documentType,
    required String documentUrl,
    required String selfieUrl,
    String? notes,
    required String referenceFullName,
    required String referencePhone,
    required String referenceRelationship,
    String? referenceOccupation,
    required String referenceEmployer,
    String? referenceIdNumber,
    String? supportDocUrl,
    required String supportDocType,
  }) async {
    await _sb.from('kyc_documents').insert({
      'user_id': userId,
      'document_type': documentType,
      'document_url': documentUrl,
      'selfie_url': selfieUrl,
      'notes': notes,
      'status': 'pending',
      'reference_full_name': referenceFullName,
      'reference_phone': referencePhone,
      'reference_relationship': referenceRelationship,
      'reference_occupation': referenceOccupation,
      'reference_employer': referenceEmployer,
      'reference_id_number': referenceIdNumber,
      'support_doc_url': supportDocUrl,
      'support_doc_type': supportDocType,
    });
    await _sb
        .from('profiles')
        .update({'kyc_status': 'pending'}).eq('id', userId);
  }

  Future<String> uploadKycFile(
      String userId, Uint8List bytes, String suffix) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$suffix';
    // uploadBinary (Uint8List) works on every platform, including web —
    // dart:io's File does not exist on web and will break compilation there.
    await _sb.storage.from('kyc-documents').uploadBinary(path, bytes);
    return _sb.storage.from('kyc-documents').getPublicUrl(path);
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<List<AppNotification>> fetchNotifications(String userId) async {
    final data = await _sb
        .from('notifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    return (data as List)
        .map((m) => AppNotification.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> markNotificationRead(String id) async {
    await _sb.from('notifications').update({'read': true}).eq('id', id);
  }

  // ── NEW: Send notification to a user ─────────────────────────────────────
  Future<String?> sendNotification({
    required String userId,
    required String title,
    required String body,
    String? type, // e.g., 'commission_due', 'payment_confirmed', etc.
    String? relatedId, // delivery_id, package_id, etc.
  }) async {
    try {
      await _sb.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        if (type != null) 'type': type,
        if (relatedId != null) 'related_id': relatedId,
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Platform Settings ─────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchPlatformSettings() async {
    final data =
        await _sb.from('platform_settings').select().order('setting_key');
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<String?> upsertSetting(String key, String value) async {
    try {
      await _sb
          .from('platform_settings')
          .upsert({'setting_key': key, 'setting_value': value});
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── System Settings ──────────────────────────────────────────────────────
  // system_settings is a single row (id = 1) with named columns —
  // escrow_telebirr, escrow_cbe, escrow_awash, commission_rate,
  // blocked_users (TEXT[]) — per supabase_system_settings.sql. This used to
  // query a key/value shape that doesn't exist in the real table (no `key`
  // or `value` columns), which silently broke: Platform Settings (escrow
  // accounts + blocked-user management), the traveler's "Commission
  // Payment Required" notification (missing escrow account numbers), and
  // the traveler's commission payment screen.

  Future<Map<String, dynamic>> fetchSystemSettings() async {
    final row = await _sb
        .from('system_settings')
        .select(
            'escrow_telebirr, escrow_cbe, escrow_awash, commission_rate, blocked_users')
        .eq('id', 1)
        .maybeSingle();
    return {
      'escrow_telebirr': row?['escrow_telebirr'] as String? ?? '',
      'escrow_cbe': row?['escrow_cbe'] as String? ?? '',
      'escrow_awash': row?['escrow_awash'] as String? ?? '',
      'commission_rate': row?['commission_rate'],
      'blocked_users': row?['blocked_users'] ?? [],
    };
  }

  Future<String?> saveSystemSettings({
    required String escrowTelebirr,
    required String escrowCbe,
    required String escrowAwash,
    required double commissionRate,
    required List<String> blockedUsers,
  }) async {
    try {
      await _sb.from('system_settings').update({
        'escrow_telebirr': escrowTelebirr,
        'escrow_cbe': escrowCbe,
        'escrow_awash': escrowAwash,
        'commission_rate': commissionRate,
        'blocked_users': blockedUsers,
      }).eq('id', 1);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Stats ─────────────────────────────────────────────────────────────────

  Future<Map<String, int>> fetchSenderStats(String userId) async {
    final packages =
        await _sb.from('packages').select('status').eq('sender_id', userId);
    final statuses =
        (packages as List).map((p) => (p as Map)['status'] as String).toList();
    return {
      'activePackages':
          statuses.where((s) => ['pending', 'matched'].contains(s)).length,
      'inTransit': statuses.where((s) => s == 'in_transit').length,
      'delivered': statuses.where((s) => s == 'delivered').length,
      'pending': statuses.where((s) => s == 'pending').length,
    };
  }

  Future<Map<String, dynamic>> fetchTravelerStats(String userId) async {
    final trips =
        await _sb.from('trips').select('status').eq('traveler_id', userId);
    final approvals = await _sb
        .from('delivery_approvals')
        .select('status')
        .eq('traveler_id', userId);
    final tripStatuses =
        (trips as List).map((t) => (t as Map)['status'] as String).toList();
    final approvalStatuses =
        (approvals as List).map((a) => (a as Map)['status'] as String).toList();
    return {
      'activeTrips': tripStatuses.where((s) => s == 'active').length,
      'deliveriesCompleted':
          approvalStatuses.where((s) => s == 'approved').length,
      'pendingRequests': approvalStatuses.where((s) => s == 'pending').length,
    };
  }

  // ── Admin ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAllUsers() async {
    final data = await _sb
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAllKycDocuments(
      {String? status}) async {
    var query = _sb
        .from('kyc_documents')
        .select('*, profiles!kyc_documents_user_id_fkey(full_name, email)');
    if (status != null) query = query.eq('status', status);
    final data = await query.order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<String?> updateKycStatus(
      String kycId, String status, String userId) async {
    try {
      // NOTE: this used to do two direct table updates from the client,
      // but the second one (profiles.kyc_status) was silently blocked by
      // RLS (self-only UPDATE policy) since it's the admin's session, not
      // the target user's. Routed through a SECURITY DEFINER RPC instead —
      // see supabase_fix_kyc_status_rpc.sql — same pattern already used by
      // flagTravelerPenalty()/increment_traveler_penalty().
      await _sb.rpc('update_kyc_status', params: {
        'p_kyc_id': kycId,
        'p_status': status,
        'p_user_id': userId,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllDeliveryApprovals(
      {String? status}) async {
    var query = _sb.from('delivery_approvals').select('''
      *,
      packages(title, from_location, to_location),
      sender:profiles!delivery_approvals_sender_id_fkey(full_name, nickname),
      traveler:profiles!delivery_approvals_traveler_id_fkey(full_name, nickname)
    ''');
    if (status != null) query = query.eq('status', status);
    final data = await query.order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAllPackages({String? status}) async {
    var query = _sb
        .from('packages')
        .select('*, profiles!packages_sender_id_fkey(full_name, nickname)');
    if (status != null) query = query.eq('status', status);
    final data = await query.order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<List<Map<String, dynamic>>> fetchAllTrips() async {
    final data = await _sb
        .from('trips')
        .select('*, profiles!trips_traveler_id_fkey(full_name, nickname)')
        .order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<Map<String, int>> fetchAdminStats() async {
    final users =
        await _sb.from('profiles').select('id').count(CountOption.exact);
    final packages =
        await _sb.from('packages').select('id').count(CountOption.exact);
    final approvals = await _sb
        .from('delivery_approvals')
        .select('id')
        .count(CountOption.exact);
    final kycs = await _sb
        .from('kyc_documents')
        .select('id')
        .eq('status', 'pending')
        .count(CountOption.exact);
    return {
      'totalUsers': users.count,
      'totalPackages': packages.count,
      'totalDeliveries': approvals.count,
      'pendingKycs': kycs.count,
    };
  }

  // Blocked users live in the `blocked_users` TEXT[] column on the single
  // system_settings row (id = 1) — see supabase_system_settings.sql.
  Future<String?> blockUser(String userId) async {
    try {
      final row = await _sb
          .from('system_settings')
          .select('blocked_users')
          .eq('id', 1)
          .maybeSingle();
      final current =
          List<String>.from((row?['blocked_users'] as List?) ?? const []);
      if (!current.contains(userId)) current.add(userId);
      await _sb
          .from('system_settings')
          .update({'blocked_users': current}).eq('id', 1);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> unblockUser(String userId) async {
    try {
      final row = await _sb
          .from('system_settings')
          .select('blocked_users')
          .eq('id', 1)
          .maybeSingle();
      final current =
          List<String>.from((row?['blocked_users'] as List?) ?? const []);
      current.remove(userId);
      await _sb
          .from('system_settings')
          .update({'blocked_users': current}).eq('id', 1);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updatePackageStatus(String packageId, String status) async {
    try {
      await _sb.from('packages').update({'status': status}).eq('id', packageId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Deliveries ────────────────────────────────────────────────────────────

  Future<List<DeliveryModel>> fetchTravelerDeliveries(String userId,
      {List<String>? statuses}) async {
    var query = _sb
        .from('deliveries')
        .select(
            '*, packages(id, title, from_location, to_location, weight, offered_price, from_lat, from_lng, to_lat, to_lng)')
        .eq('traveler_id', userId);
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((m) => DeliveryModel.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<DeliveryModel>> fetchSenderDeliveries(String userId,
      {List<String>? statuses}) async {
    var query = _sb
        .from('deliveries')
        .select(
            '*, packages(id, title, from_location, to_location, weight, offered_price, from_lat, from_lng, to_lat, to_lng)')
        .eq('sender_id', userId);
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List)
        .map((m) => DeliveryModel.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<DeliveryModel?> fetchDeliveryById(String deliveryId) async {
    try {
      final data = await _sb
          .from('deliveries')
          .select(
              '*, packages(id, title, from_location, to_location, weight, offered_price, from_lat, from_lng, to_lat, to_lng)')
          .eq('id', deliveryId)
          .maybeSingle();
      return data == null ? null : DeliveryModel.fromMap(data);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllDeliveries() async {
    final data = await _sb
        .from('deliveries')
        .select('*, packages(title, from_location, to_location)')
        .order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  // Fields the client is allowed to touch via updateDelivery. This is a
  // whitelist, not a denylist — anything not in this set (amount,
  // payment_status, sender_id, traveler_id, commission fields, etc.) is
  // silently dropped before the request goes out, so a bug or a rogue
  // caller can never smuggle a sensitive field through this generic path.
  // Sensitive fields have their own dedicated methods with their own RLS
  // policies (markCommissionPaid, submitCommissionProof,
  // approveCommissionProof, rejectCommissionProof, cancelDeliveryAsSender).
  static const Set<String> _updateDeliveryAllowedFields = {
    'status',
    'pickup_at',
    'expires_at',
    'completed_at',
  };

  Future<String?> updateDelivery(
      String deliveryId, Map<String, dynamic> updates) async {
    final filtered = <String, dynamic>{
      for (final entry in updates.entries)
        if (_updateDeliveryAllowedFields.contains(entry.key))
          entry.key: entry.value
    };

    final dropped = updates.keys.toSet().difference(filtered.keys.toSet());
    if (dropped.isNotEmpty) {
      // Surface this loudly in debug builds so a caller trying to pass a
      // disallowed field finds out immediately instead of silently no-oping
      // in production.
      assert(() {
        debugPrint(
            'updateDelivery: dropped disallowed field(s) $dropped — add a '
            'dedicated method instead of widening this whitelist.');
        return true;
      }());
    }

    if (filtered.isEmpty) return null;

    try {
      await _sb.from('deliveries').update(filtered).eq('id', deliveryId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // Sender-initiated cancellation. Only allowed while the delivery hasn't
  // been picked up yet ('accepted') — enforced both here (UI gating) and at
  // the DB layer via an RLS policy (see supabase_fix_sender_cancel.sql) so a
  // sender can't cancel mid-transit just by calling this directly. Distinct from
  // the traveler's own 'cancelled' path (declining a 'pending' request) so
  // we can tell the two apart later via cancelled_by.
  Future<String?> cancelDeliveryAsSender(String deliveryId) async {
    try {
      await _sb.from('deliveries').update({
        'status': 'cancelled',
        'cancelled_by': 'sender',
        'cancelled_at': DateTime.now().toIso8601String(),
      }).eq('id', deliveryId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── NEW: Sender confirms they paid the traveler ──────────────────────────
  // Called when sender clicks "Traveler Paid" button after delivery is marked delivered.
  // This transitions the delivery payment_status to 'sender_confirmed' and
  // sends a notification to the traveler to pay the platform commission.
  Future<String?> confirmTravelerPaid(String deliveryId) async {
    try {
      // 1. Update delivery status to indicate sender has confirmed payment
      await _sb.from('deliveries').update({
        'payment_status': 'sender_confirmed',
        'sender_confirmed_at': DateTime.now().toIso8601String(),
      }).eq('id', deliveryId);

      // 2. Fetch delivery details to get traveler_id and amount
      final delivery = await _sb
          .from('deliveries')
          .select('traveler_id, amount, packages(title)')
          .eq('id', deliveryId)
          .single();

      final travelerId = delivery['traveler_id'] as String;
      final amount = (delivery['amount'] as num?)?.toDouble() ?? 0.0;
      final packageTitle = (delivery['packages']
              as Map<String, dynamic>?)?['title'] as String? ??
          'your delivery';

      // 3. Fetch admin commission account details
      final settings = await fetchSystemSettings();
      final commissionRate =
          (settings['commission_rate'] as num?)?.toDouble() ?? 0.0;
      final commissionAmount = amount * (commissionRate / 100);

      // 4. Build commission payment instructions
      final telebirr = settings['escrow_telebirr'] as String? ?? '';
      final cbe = settings['escrow_cbe'] as String? ?? '';
      final awash = settings['escrow_awash'] as String? ?? '';

      final String paymentInstructions = '''
You have received payment from the sender for "$packageTitle".

Please pay the platform commission (${commissionRate.toStringAsFixed(1)}% = ${commissionAmount.toStringAsFixed(2)} ETB) to one of the following accounts:

Telebirr: $telebirr
CBE: $cbe
Awash: $awash

After payment, go to "Commission Payment" in your dashboard and upload your payment screenshot.
''';

      // 5. Send notification to traveler
      await sendNotification(
        userId: travelerId,
        title: 'Commission Payment Required',
        body: paymentInstructions,
        type: 'commission_due',
        relatedId: deliveryId,
      );

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── NEW: Fetch commission payment details for traveler ───────────────────
  // Returns the delivery with commission info so the traveler knows what to pay
  Future<Map<String, dynamic>?> fetchCommissionDetails(
      String deliveryId) async {
    try {
      final delivery = await _sb.from('deliveries').select('''
            id, amount, payment_status, commission_proof_url, 
            commission_rejection_reason, commission_proof_submitted_at,
            packages(title, from_location, to_location),
            sender:profiles!deliveries_sender_id_fkey(full_name, nickname)
          ''').eq('id', deliveryId).maybeSingle();

      if (delivery == null) return null;

      final settings = await fetchSystemSettings();
      final amount = (delivery['amount'] as num?)?.toDouble() ?? 0.0;
      final commissionRate =
          (settings['commission_rate'] as num?)?.toDouble() ?? 0.0;

      return {
        ...delivery,
        'commission_rate': commissionRate,
        'commission_amount': amount * (commissionRate / 100),
        'escrow_telebirr': settings['escrow_telebirr'],
        'escrow_cbe': settings['escrow_cbe'],
        'escrow_awash': settings['escrow_awash'],
      };
    } catch (e) {
      return null;
    }
  }

  // ── NEW: Admin rejects commission proof and blocks traveler ──────────────
  // This combines rejectCommissionProof + blockUser + setBlockedReason + notification
  Future<String?> rejectCommissionProofAndBlock(
      String deliveryId, String travelerId, String reason) async {
    try {
      // 1. Reject the commission proof
      final rejectError = await rejectCommissionProof(deliveryId, reason);
      if (rejectError != null) return rejectError;

      // 2. Block the user
      final blockError = await blockUser(travelerId);
      if (blockError != null) return blockError;

      // 3. Set blocked reason on profile
      final reasonError = await setBlockedReason(travelerId, reason);
      if (reasonError != null) return reasonError;

      // 4. Send notification to traveler that they've been blocked
      await sendNotification(
        userId: travelerId,
        title: 'Account Blocked',
        body:
            'Your commission proof was rejected. Reason: $reason. Your account has been blocked. Please contact support for assistance.',
        type: 'account_blocked',
        relatedId: deliveryId,
      );

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<List<TripModel>> fetchActiveTravelerTrips() async {
    return await fetchActiveTrips();
  }

  Future<List<SupportTicket>> fetchSupportTickets(String userId) async {
    final data = await _sb
        .from('support_tickets')
        .select('*, profiles(id, full_name, nickname)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (data as List)
        .map((m) => SupportTicket.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<String?> createSupportTicket({
    required String userId,
    required String subject,
    required String description,
    required String priority,
  }) async {
    try {
      await _sb.from('support_tickets').insert({
        'user_id': userId,
        'subject': subject,
        'description': description,
        'priority': priority,
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<List<Map<String, dynamic>>> fetchAllSupportTickets() async {
    final data = await _sb
        .from('support_tickets')
        .select('*, profiles(id, full_name, nickname)')
        .order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<String?> respondToSupportTicket(
      String ticketId, String newStatus, String response) async {
    try {
      await _sb.from('support_tickets').update({
        'status': newStatus,
        'response': response,
        'responded_at': DateTime.now().toIso8601String(),
      }).eq('id', ticketId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updateProfileSettings(
      String userId, Map<String, dynamic> updates) async {
    return updateProfile(userId, updates);
  }

  // ── Ratings ───────────────────────────────────────────────────────────────

  Future<List<int>> fetchUserRatings(String userId) async {
    final data =
        await _sb.from('ratings').select('stars').eq('ratee_id', userId);
    return (data as List).map((r) => (r as Map)['stars'] as int).toList();
  }

  Future<String?> submitRating({
    required String deliveryId,
    required String raterId,
    required String rateeId,
    required int stars, // 1–5
    String? comment,
  }) async {
    try {
      // Insert rating
      await _sb.from('ratings').insert({
        'delivery_id': deliveryId,
        'rater_id': raterId,
        'ratee_id': rateeId,
        'stars': stars,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
      });
      // Recompute average on the profile
      final allRatings =
          await _sb.from('ratings').select('stars').eq('ratee_id', rateeId);
      final list =
          (allRatings as List).map((r) => (r as Map)['stars'] as int).toList();
      if (list.isNotEmpty) {
        final avg = list.reduce((a, b) => a + b) / list.length;
        await _sb.from('profiles').update({
          'avg_rating': avg,
          'review_count': list.length,
        }).eq('id', rateeId);
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Disputes ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAllDisputes({String? status}) async {
    var query = _sb.from('disputes').select(
        '*, deliveries(sender_id, traveler_id, from_location, to_location, amount), profiles(full_name)');
    if (status != null) query = query.eq('status', status);
    final data = await query.order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<String?> createDispute({
    required String deliveryId,
    required String raisedBy,
    required String reason,
    String? description,
  }) async {
    try {
      await _sb.from('disputes').insert({
        'delivery_id': deliveryId,
        'raised_by': raisedBy,
        'reason': reason,
        'description': description,
        'status': 'open',
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // Flags the traveler's account with a platform penalty when a dispute is
  // resolved in the sender's favor (refund_sender). Kept intentionally
  // simple — a running penalty counter on the profile row — rather than an
  // automatic ban, so admin can still use judgement on repeat offenders.
  Future<String?> flagTravelerPenalty(String travelerId,
      {required String reason}) async {
    try {
      await _sb.rpc('increment_traveler_penalty', params: {
        'p_traveler_id': travelerId,
        'p_reason': reason,
      });
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> resolveDispute(String disputeId, String resolution) async {
    try {
      await _sb.from('disputes').update({
        'status': 'resolved',
        'resolution': resolution,
        'resolved_at': DateTime.now().toIso8601String(),
      }).eq('id', disputeId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Payments ──────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAllPayments() async {
    final data = await _sb
        .from('deliveries')
        .select(
            '*, packages(title), profiles!deliveries_sender_id_fkey(full_name)')
        .order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  Future<String?> markCommissionPaid(String deliveryId,
      {String? paymentMethod, String? paymentReference}) async {
    try {
      final rows = await _sb
          .from('deliveries')
          .update({
            'payment_status': 'commission_paid',
            if (paymentMethod != null)
              'commission_payment_method': paymentMethod,
            if (paymentReference != null)
              'commission_payment_reference': paymentReference,
          })
          .eq('id', deliveryId)
          .select('id');
      if ((rows as List).isEmpty) {
        return 'Nothing was updated — this delivery may no longer be in '
            'commission_due status, or you may not have admin permissions '
            'on this row. Please refresh and try again.';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Commission proof of payment ───────────────────────────────────────────
  // Traveler pays the commission outside the app, then screenshots the
  // receipt and submits it here for admin review. Mirrors the KYC upload
  // pattern (uploadKycFile) but uses its own bucket since these are payment
  // receipts, not identity documents — keeping them separate makes future
  // access-control/retention policies easier to set differently for each.
  Future<String> uploadCommissionProofFile(
      String deliveryId, Uint8List bytes) async {
    final path = '$deliveryId/${DateTime.now().millisecondsSinceEpoch}_proof';
    await _sb.storage.from('commission-proofs').uploadBinary(path, bytes);
    return _sb.storage.from('commission-proofs').getPublicUrl(path);
  }

  Future<String?> submitCommissionProof(
      String deliveryId, Uint8List bytes) async {
    try {
      final url = await uploadCommissionProofFile(deliveryId, bytes);
      final rows = await _sb
          .from('deliveries')
          .update({
            'payment_status': 'commission_proof_submitted',
            'commission_proof_url': url,
            'commission_proof_submitted_at': DateTime.now().toIso8601String(),
            'commission_rejection_reason': null,
          })
          .eq('id', deliveryId)
          .select('id');
      if ((rows as List).isEmpty) {
        // The update matched zero rows — Postgres/PostgREST treats this as
        // success and throws nothing, but nothing was actually saved. This
        // happens when the row's current state doesn't satisfy the RLS
        // policy's USING clause (e.g. payment_status wasn't 'commission_due',
        // or there's an open dispute). Surface it as a real error instead of
        // silently telling the traveler it worked.
        return 'The update was blocked (no matching row) — this delivery may '
            'not be in a state that allows submitting proof right now '
            '(e.g. an open dispute, or it isn\'t marked commission due). '
            'Please refresh and try again, or contact support.';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> approveCommissionProof(String deliveryId) async {
    try {
      final rows = await _sb
          .from('deliveries')
          .update({
            'payment_status': 'commission_paid',
          })
          .eq('id', deliveryId)
          .select('id');
      if ((rows as List).isEmpty) {
        return 'Nothing was updated — this delivery may no longer be in '
            'commission_proof_submitted status, or you may not have admin '
            'permissions on this row. Please refresh and try again.';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> rejectCommissionProof(
      String deliveryId, String reason) async {
    try {
      final rows = await _sb
          .from('deliveries')
          .update({
            'payment_status': 'commission_due',
            'commission_rejection_reason': reason,
          })
          .eq('id', deliveryId)
          .select('id');
      if ((rows as List).isEmpty) {
        return 'Nothing was updated — this delivery may no longer be in '
            'commission_proof_submitted status, or you may not have admin '
            'permissions on this row. Please refresh and try again.';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ── Admin Trips ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchAllAdminTrips() async {
    final data = await _sb
        .from('trips')
        .select('*, profiles!trips_traveler_id_fkey(full_name, avatar_url)')
        .order('created_at', ascending: false);
    return (data as List).map((m) => m as Map<String, dynamic>).toList();
  }

  // ── Request expiration ────────────────────────────────────────────────────
  // NOT the source of truth. The real fix lives in supabase_migration.sql
  // section 6 — a pg_cron job runs server-side every 30 minutes and expires
  // stale pending packages regardless of whether anyone has the app open.
  // This client-side call is kept only as an instant, redundant fallback so
  // a user sitting in the app doesn't have to wait up to 30 minutes to see
  // their own expired request update — it's a nice-to-have, not a
  // requirement. If the migration hasn't been applied to your Supabase
  // project yet, THIS is silently the only thing expiring requests, which
  // is exactly the unreliable behavior it's meant to back up, not replace.

  Future<void> expireOldRequests() async {
    try {
      // Packages pending > 2 hours with no traveler acceptance expire automatically
      final cutoff =
          DateTime.now().subtract(const Duration(hours: 2)).toIso8601String();
      await _sb
          .from('packages')
          .update({'status': 'expired'})
          .eq('status', 'pending')
          .lt('created_at', cutoff);
    } catch (_) {}
  }
}