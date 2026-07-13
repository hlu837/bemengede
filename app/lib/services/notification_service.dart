// lib/services/notification_service.dart
// Handles creating notifications in Supabase notifications table

import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _sb = Supabase.instance.client;

  static const adminEmail = 'picklink237@gmail.com';

  // ── Send notification to a user ───────────────────────────────────────────

  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    String? type,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      await _sb.from('notifications').insert({
        'user_id': userId,
        'title':   title,
        'body':    body,
        if (type != null) 'type': type,
        'read':    false,
      });
    } catch (e) {
      // Notification failure should never crash the app
      print('Notification error: $e');
    }
  }

  // ── Get admin user id ─────────────────────────────────────────────────────

  Future<String?> _getAdminId() async {
    final data = await _sb.from('profiles')
        .select('id')
        .eq('email', adminEmail)
        .maybeSingle();
    return data?['id'] as String?;
  }

  // ── Payment notification (Feature 1) ─────────────────────────────────────
  // Called when a delivery is marked completed — notifies admin only.
  // NOTE: the traveler-facing "🌟 Delivery Complete! Payout Earned." message
  // is now sent by the set_delivery_expiry() Supabase trigger (fires on the
  // deliveries UPDATE that sets status = 'completed'), so it goes out even
  // if the traveler's app isn't open. Don't add a duplicate traveler
  // notification here — it'll double up with the trigger's.

  Future<void> notifyAdminDeliveryCompleted({
    required String travelerName,
    required double amount,
    required String packageTitle,
  }) async {
    final adminId = await _getAdminId();
    if (adminId != null) {
      await sendNotification(
        userId: adminId,
        title:  '📦 Delivery Completed — Payment Pending',
        body:   '$travelerName completed delivery of "$packageTitle" for ETB ${amount.toStringAsFixed(0)}. '
                'Commission collection pending.',
        type: 'admin_payment_pending',
      );
    }
  }

  // ── Sender-initiated cancellation ─────────────────────────────────────────
  // Called when a sender cancels a delivery before pickup (see
  // DataService.cancelDeliveryAsSender). Lets the traveler know immediately
  // instead of them finding out only when the card disappears from their list.

  Future<void> notifyTravelerDeliveryCancelledBySender({
    required String travelerId,
    required String packageTitle,
  }) async {
    await sendNotification(
      userId: travelerId,
      title:  'Delivery cancelled',
      body:   'The sender cancelled "$packageTitle" before pickup. No action needed.',
      type: 'delivery_cancelled_by_sender',
    );
  }

  // ── Max 2 packages check (Feature 2) ─────────────────────────────────────

  Future<bool> travelerHasMaxPackages(String travelerId) async {
    // Count active deliveries (accepted or in_transit) for this traveler.
    // 'accepted'/'in_transit' are deliveries-table statuses reached via
    // DataService.instantMatchDelivery() (formerly via
    // respondToDeliveryApproval() before the request/approval flow was
    // replaced with instant matching).
    final data = await _sb.from('deliveries')
        .select('id')
        .eq('traveler_id', travelerId)
        .inFilter('status', ['accepted', 'in_transit'])
        .count(CountOption.exact);
    return data.count >= 2;
  }

  // ── Expiry report (Feature 3) ─────────────────────────────────────────────
  // Called by a periodic check — reports deliveries stuck > 4h

  Future<void> checkAndReportExpiredDeliveries() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 4)).toIso8601String();

    // 'accepted'/'in_transit' with an approved_at column only ever existed
    // on delivery_approvals — but that table's status column only ever
    // holds pending/approved/rejected, so this never matched anything.
    // Overdue tracking belongs on `deliveries` (pickup_at is the real
    // "started" timestamp there, set when the traveler marks in_transit).
    final data = await _sb.from('deliveries')
        .select('id, traveler_id, sender_id, pickup_at, packages(title)')
        .inFilter('status', ['accepted', 'in_transit'])
        .lt('pickup_at', cutoff);

    final overdue = data as List;
    if (overdue.isEmpty) return;

    final adminId = await _getAdminId();

    for (final d in overdue) {
      final pkg = (d['packages'] as Map?)?['title'] as String? ?? 'Package';
      final travelerId = d['traveler_id'] as String;
      final senderId   = d['sender_id']   as String;
      final deliveryId = d['id']           as String;

      // Notify traveler
      await sendNotification(
        userId: travelerId,
        title:  '⚠️ Delivery Overdue',
        body:   'Your delivery of "$pkg" has exceeded the 4-5 hour limit. '
                'Please complete or report the delivery immediately.',
        type: 'delivery_overdue',
      );

      // Notify sender
      await sendNotification(
        userId: senderId,
        title:  '⚠️ Delivery Delayed',
        body:   'Your package "$pkg" has not been delivered within the expected time. '
                'We are investigating. Contact support if needed.',
        type: 'delivery_overdue',
      );

      // Notify admin
      if (adminId != null) {
        await sendNotification(
          userId: adminId,
          title:  '🚨 Overdue Delivery Report',
          body:   'Delivery of "$pkg" (id: ${deliveryId.substring(0, 8)}) has exceeded 4 hours. '
                  'Traveler and sender have been notified.',
          type: 'admin_overdue_report',
        );
      }
    }
  }
}
