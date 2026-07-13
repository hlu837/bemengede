// lib/screens/sender/package_detail_screen.dart
//
// Dedicated detail screen for a single delivery, reached by tapping a card
// in the "In Transit" tab of SenderPackagesScreen (My Packages). Replaces
// the old standalone "Track Delivery" screen — this is now the one place
// a sender drills into for a specific delivery's status + live map.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/models.dart';
import '../../services/data_service.dart';
import '../../services/notification_service.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';
import '../shared/map_screen.dart';

class PackageDetailScreen extends StatefulWidget {
  final DeliveryModel delivery;
  const PackageDetailScreen({super.key, required this.delivery});

  @override
  State<PackageDetailScreen> createState() => _PackageDetailScreenState();
}

class _PackageDetailScreenState extends State<PackageDetailScreen> {
  final _svc = DataService();
  final _sb = Supabase.instance.client;
  bool _cancelling = false;
  bool _confirmingPayment = false;

  // Local, mutable copy of the delivery so this screen can reflect status
  // changes the traveler makes (e.g. "Mark as Delivered") while the sender
  // is already sitting on this screen. Previously this screen only ever
  // rendered widget.delivery — a snapshot taken at navigation time — so it
  // would silently go stale and keep showing "In Transit" forever.
  late DeliveryModel _delivery;
  RealtimeChannel? _channel;
  bool _notifiedCompletion = false;

  DeliveryModel get delivery => _delivery;

  // NOTE: the app only ever writes status = 'completed' when a traveler
  // marks a delivery delivered — 'delivered' is never actually set anywhere,
  // it only exists as a legacy/alternate value some read-paths tolerate.
  bool get _needsPaymentConfirmation {
    return delivery.status == 'completed' &&
        (delivery.paymentStatus == 'pending' || delivery.paymentStatus == null);
  }

  bool get _paymentConfirmed {
    return delivery.paymentStatus == 'sender_confirmed' ||
        delivery.paymentStatus == 'commission_proof_submitted' ||
        delivery.paymentStatus == 'commission_paid';
  }

  @override
  void initState() {
    super.initState();
    _delivery = widget.delivery;
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // Realtime is the primary path, but we also refresh once right away in
  // case the status already changed between when the list screen fetched
  // it and when this screen mounted.
  void _subscribeRealtime() {
    _refreshDelivery();
    _channel = _sb
        .channel('package-detail-${widget.delivery.id}')
        .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'deliveries',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'id',
                value: widget.delivery.id),
            callback: (_) => _refreshDelivery())
        .subscribe();
  }

  Future<void> _refreshDelivery() async {
    final fresh = await _svc.fetchDeliveryById(widget.delivery.id);
    if (fresh == null || !mounted) return;
    final wasDone = ['completed', 'delivered'].contains(_delivery.status);
    setState(() => _delivery = fresh);

    final isDone = ['completed', 'delivered'].contains(fresh.status);
    if (isDone && !wasDone && !_notifiedCompletion && mounted) {
      _notifiedCompletion = true;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This package has been marked as delivered!'),
          backgroundColor: Color(AppColors.success)));
    }
  }

  // Sender cancel from the detail screen. Allowed pre-pickup ('accepted')
  // and mid-transit ('in_transit') — the wording changes depending on which,
  // since cancelling after pickup means the package is physically with the
  // traveler and needs to be handed back, not just "un-requested".
  Future<void> _cancel() async {
    final midTransit = delivery.status == 'in_transit';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this delivery?'),
        content: Text(midTransit
            ? 'This package is already with the traveler. Cancelling now means '
                'you\'ll need to coordinate getting it back directly with them. '
                'This can\'t be undone.'
            : 'This will cancel the delivery before pickup. The traveler will '
                'be notified. This can\'t be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel delivery',
                  style: TextStyle(color: Color(AppColors.error)))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling = true);
    final err = await _svc.cancelDeliveryAsSender(delivery.id);
    if (!mounted) return;
    if (err != null) {
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $err')));
      return;
    }
    await NotificationService().notifyTravelerDeliveryCancelledBySender(
      travelerId: delivery.travelerId,
      packageTitle: delivery.packageTitle ?? 'a package',
    );
    if (!mounted) return;
    Navigator.pop(context, true); // tell My Packages to refresh
  }

  // Sender confirms they've paid the traveler (outside the app) once the
  // package is marked delivered. This is the trigger that notifies the
  // traveler to pay the platform commission.
  Future<void> _confirmTravelerPaid() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.payments_rounded, color: Color(AppColors.primary)),
          SizedBox(width: 8),
          Text('Confirm Payment'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Have you paid the traveler ETB ${delivery.amount.toStringAsFixed(0)} for '
                '"${delivery.packageTitle ?? 'this delivery'}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF7EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF2A9E2D)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'After confirming, the traveler will be notified to pay the platform commission.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF2A9E2D)),
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not Yet')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(AppColors.primary),
                  foregroundColor: Colors.white),
              child: const Text('Yes, I Paid')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _confirmingPayment = true);
    final err = await _svc.confirmTravelerPaid(delivery.id);
    if (!mounted) return;
    setState(() => _confirmingPayment = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $err'),
          backgroundColor: const Color(AppColors.error)));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Payment confirmed! Traveler has been notified to pay commission.'),
        backgroundColor: Color(AppColors.success)));
    _refreshDelivery();
  }

  @override
  Widget build(BuildContext context) {
    final canCancel = ['accepted', 'in_transit'].contains(delivery.status);
    final steps = [
      ('Package Created', true, Icons.receipt_long_rounded),
      ('Picked Up',
          ['accepted', 'in_transit', 'completed', 'delivered']
              .contains(delivery.status),
          Icons.inventory_2_rounded),
      ('In Transit',
          ['in_transit', 'completed', 'delivered'].contains(delivery.status),
          Icons.local_shipping_rounded),
      ('Delivered',
          ['completed', 'delivered'].contains(delivery.status),
          Icons.check_circle_rounded),
    ];

    // Map only makes sense once a traveler is actually assigned and moving
    // — before "accepted" there's no traveler position to show yet.
    final canViewMap =
        ['accepted', 'in_transit'].contains(delivery.status);

    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: Text(delivery.packageTitle ?? 'Package Details',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Expanded(
                    child: Text(delivery.packageTitle ?? 'Package',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  StatusBadge(delivery.status),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.location_on_rounded,
                      size: 14, color: Color(AppColors.textSecondary)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                        '${delivery.fromLocation ?? '—'} → ${delivery.toLocation ?? '—'}',
                        style: const TextStyle(
                            color: Color(AppColors.textSecondary))),
                  ),
                ]),
              ])),
          if (delivery.status == 'in_transit' && delivery.isOverdue) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.timer_off_rounded,
                    size: 18, color: Color(AppColors.error)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                      'This delivery is overdue — it\'s past the expected 5-hour window. We\'ve notified the traveler and our team.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Color(AppColors.error),
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 16),

          // Step-by-step progress tracker
          AppCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Delivery Progress',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),
                ...steps.map((s) =>
                    _Step(label: s.$1, done: s.$2, icon: s.$3)),
              ])),
          const SizedBox(height: 16),

          AppCard(
              child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Fixed Price',
                  style: TextStyle(color: Color(AppColors.textSecondary))),
              Text('ETB ${delivery.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            if (delivery.travelerName != null) ...[
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Traveler',
                    style: TextStyle(color: Color(AppColors.textSecondary))),
                Text(delivery.travelerName!,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ],
          ])),
          const SizedBox(height: 16),

          // ── Sender confirms payment to traveler ──────────────────────────
          if (_needsPaymentConfirmation) ...[
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Row(children: [
                    Icon(Icons.payments_rounded, color: Color(AppColors.primary)),
                    SizedBox(width: 8),
                    Text('Payment to traveler',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'This package has been delivered. Once you\'ve paid the '
                      'traveler outside the app, confirm it here.',
                      style: TextStyle(fontSize: 12, color: Color(AppColors.textSecondary))),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _confirmingPayment ? null : _confirmTravelerPaid,
                      icon: _confirmingPayment
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.payments_rounded, size: 18),
                      label: Text(_confirmingPayment
                          ? 'Confirming...'
                          : 'Traveler Paid — ETB ${delivery.amount.toStringAsFixed(0)}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(AppColors.primary),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ])),
            const SizedBox(height: 16),
          ] else if (_paymentConfirmed) ...[
            AppCard(
                child: Row(children: [
              Icon(
                delivery.paymentStatus == 'commission_paid'
                    ? Icons.check_circle_rounded
                    : Icons.hourglass_top_rounded,
                color: delivery.paymentStatus == 'commission_paid'
                    ? const Color(AppColors.success)
                    : const Color(0xFFD97706),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  delivery.paymentStatus == 'commission_paid'
                      ? 'Commission paid — all settled'
                      : 'You\'ve paid the traveler. Waiting for them to pay the platform commission.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: delivery.paymentStatus == 'commission_paid'
                        ? const Color(AppColors.success)
                        : const Color(0xFFD97706),
                  ),
                ),
              ),
            ])),
            const SizedBox(height: 16),
          ],
          const SizedBox(height: 4),

          // ── Prominent live-map CTA ──────────────────────────────────────
          if (canViewMap)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SenderTrackingMapScreen(
                      deliveryId: delivery.id,
                      travelerId: delivery.travelerId,
                      packageTitle: delivery.packageTitle ?? 'Package',
                    ),
                  ),
                ),
                icon: const Text('📍', style: TextStyle(fontSize: 18)),
                label: const Text('View Live on Map',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(AppColors.primary),
                  foregroundColor: Colors.white,
                  elevation: 3,
                  shadowColor: const Color(AppColors.primary).withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(AppColors.surface),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(AppColors.border))),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: Color(AppColors.textSecondary)),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text(
                        'Live map opens once a traveler accepts this package.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Color(AppColors.textSecondary)))),
              ]),
            ),

          if (canCancel) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _cancelling ? null : _cancel,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(AppColors.error),
                    side: const BorderSide(color: Color(AppColors.error)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: _cancelling
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(AppColors.error)))
                    : const Text('Cancel delivery',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final bool done;
  final IconData icon;
  const _Step({required this.label, required this.done, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: done
                    ? const Color(AppColors.success)
                    : const Color(AppColors.border),
                shape: BoxShape.circle),
            child: Icon(icon,
                size: 18,
                color: done ? Colors.white : const Color(AppColors.textSecondary))),
        const SizedBox(width: 12),
        Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: done
                    ? const Color(AppColors.textPrimary)
                    : const Color(AppColors.textSecondary))),
        const Spacer(),
        if (done)
          const Icon(Icons.check_rounded,
              color: Color(AppColors.success), size: 18),
      ]),
    );
  }
}
