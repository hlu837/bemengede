// lib/screens/sender/sender_packages_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gebeta_gl/gebeta_gl.dart' show LatLng;
import '../../providers/auth_provider.dart';
import '../../services/data_service.dart';
import '../../services/gebeta_service.dart' as gebeta;
import '../../services/notification_service.dart';
import '../../services/pricing_service.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';
import '../shared/map_screen.dart';
import 'package_detail_screen.dart';

// ── My Packages: single authoritative master list ──────────────────────────
// Replaces the old 3-way split across "My Packages" / "Active Orders" /
// "Track Delivery". Everything lives here now behind a TabBar:
//   Pending          → packages still looking for a traveler
//   In Transit       → deliveries with a traveler assigned, tap through to
//                       PackageDetailScreen (step tracker + live map)
//   Drafts & Canceled → expired/cancelled packages and cancelled deliveries
//
// NOTE: this app has no real "draft" concept in the schema today — a
// package is either posted or it isn't, there's no save-without-posting
// step. This tab currently shows expired/cancelled items only. If you want
// true drafts, that needs an `is_draft` column on `packages` plus a save
// action in the post-package sheet below.
class SenderPackagesScreen extends ConsumerStatefulWidget {
  const SenderPackagesScreen({super.key});
  @override
  ConsumerState<SenderPackagesScreen> createState() =>
      _SenderPackagesScreenState();
}

class _SenderPackagesScreenState extends ConsumerState<SenderPackagesScreen>
    with SingleTickerProviderStateMixin {
  final _svc = DataService();
  late final TabController _tabController;

  List<PackageModel> _packages = [];
  List<DeliveryModel> _inTransit = [];
  List<DeliveryModel> _cancelledDeliveries = [];
  KycStatus _kycStatus = KycStatus.notSubmitted;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _loading = true);
    final results = await Future.wait([
      _svc.fetchSenderPackages(user.id),
      // ═══════════════════════════════════════════════════════════════════
      // FIXED: The traveler's "Mark as Delivered" action actually sets the
      // delivery status to 'completed' (see traveler_screens.dart
      // _updateStatus(d.id, 'completed')) — 'delivered' is never actually
      // written anywhere. Fetching only 'delivered' meant a finished
      // delivery silently vanished from this tab the moment the traveler
      // completed it, instead of showing the payment-confirmation button.
      // ═══════════════════════════════════════════════════════════════════
      _svc.fetchSenderDeliveries(user.id,
          statuses: ['accepted', 'in_transit', 'completed']),
      _svc.fetchSenderDeliveries(user.id, statuses: ['cancelled']),
      _svc.fetchKycStatus(user.id),
    ]);
    if (mounted) {
      setState(() {
        _packages = results[0] as List<PackageModel>;
        _inTransit = results[1] as List<DeliveryModel>;
        _cancelledDeliveries = results[2] as List<DeliveryModel>;
        _kycStatus = results[3] as KycStatus;
        _loading = false;
      });
    }
  }

  Future<void> _delete(String id) async {
    final err = await _svc.deletePackage(id);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $err')));
    } else {
      _load();
    }
  }

  // Sender cancel — only reachable from the UI while status is 'accepted'
  // (traveler hasn't picked up yet), matching the DB-level RLS guard.
  Future<void> _cancelDelivery(DeliveryModel delivery) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this delivery?'),
        content: Text(
            'This will cancel "${delivery.packageTitle ?? 'this package'}" with '
            '${delivery.travelerName ?? 'the traveler'}. They\'ll be notified. '
            'This can\'t be undone.'),
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

    final err = await _svc.cancelDeliveryAsSender(delivery.id);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $err')));
      return;
    }
    await NotificationService().notifyTravelerDeliveryCancelledBySender(
      travelerId: delivery.travelerId,
      packageTitle: delivery.packageTitle ?? 'a package',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Delivery cancelled')));
    _load();
  }

  void _showPostSheet() {
    if (_kycStatus != KycStatus.approved) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Complete KYC verification to post packages')));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => PostPackageSheet(
          userId: ref.read(authProvider).user!.id, onSuccess: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Only truly-unmatched packages belong here. A 'matched' package
    // already has a row in _inTransit (fetched separately from
    // `deliveries`) — leaving it in this list too made it look like the
    // package was "still pending" even after a traveler had accepted it.
    final pending = _packages.where((p) => p.status == 'pending').toList();
    final draftsAndCancelled = _packages
        .where((p) => p.status == 'expired' || p.status == 'cancelled')
        .toList();

    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('My Packages',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
          bottom: TabBar(
            controller: _tabController,
            labelColor: const Color(AppColors.primary),
            unselectedLabelColor: const Color(AppColors.textSecondary),
            indicatorColor: const Color(AppColors.primary),
            tabs: [
              Tab(text: 'Pending (${pending.length})'),
              // ═══════════════════════════════════════════════════════════════
              // CHANGED: Tab label now includes delivered items too
              // ═══════════════════════════════════════════════════════════════
              Tab(text: 'Active (${_inTransit.length})'),
              Tab(
                  text:
                      'Drafts & Canceled (${draftsAndCancelled.length + _cancelledDeliveries.length})'),
            ],
          )),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPostSheet,
        backgroundColor: const Color(AppColors.primary),
        icon: const Icon(Icons.add, color: Colors.white),
        label:
            const Text('Post Package', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(children: [
                if (_kycStatus != KycStatus.approved)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: KycWarningBanner(
                        isPending: _kycStatus == KycStatus.pending),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // ── Pending ──────────────────────────────────────
                      pending.isEmpty
                          ? const EmptyState(
                              icon: Icons.inventory_2_rounded,
                              title: 'No pending packages',
                              subtitle:
                                  'Post a package and it\'ll show up here while it waits for a traveler')
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: pending.length,
                              itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _PackageCard(
                                      package: pending[i],
                                      onDelete: () => _delete(pending[i].id))),
                            ),

                      // ── In Transit / Active ───────────────────────────
                      _inTransit.isEmpty
                          ? const EmptyState(
                              icon: Icons.local_shipping_rounded,
                              title: 'Nothing active',
                              subtitle:
                                  'Once a traveler accepts a package, it\'ll show up here with live status')
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _inTransit.length,
                              itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _InTransitCard(
                                    delivery: _inTransit[i],
                                    onTap: () async {
                                      final changed =
                                          await Navigator.push<bool>(
                                              context,
                                              MaterialPageRoute(
                                                  builder: (_) =>
                                                      PackageDetailScreen(
                                                          delivery:
                                                              _inTransit[i])));
                                      if (changed == true) _load();
                                    },
                                    onCancel: _inTransit[i].status == 'accepted'
                                        ? () => _cancelDelivery(_inTransit[i])
                                        : null,
                                    // ═══════════════════════════════════════
                                    // NEW: Pass the refresh callback
                                    // ═══════════════════════════════════════
                                    onRefresh: _load,
                                  )),
                            ),

                      // ── Drafts & Canceled ────────────────────────────
                      (draftsAndCancelled.isEmpty &&
                              _cancelledDeliveries.isEmpty)
                          ? const EmptyState(
                              icon: Icons.drafts_rounded,
                              title: 'Nothing here',
                              subtitle:
                                  'Expired or canceled packages will show up here')
                          : ListView(
                              padding: const EdgeInsets.all(16),
                              children: [
                                ...draftsAndCancelled.map((p) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _PackageCard(
                                        package: p,
                                        onDelete: () => _delete(p.id)))),
                                ..._cancelledDeliveries.map((d) => Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _InTransitCard(
                                        delivery: d,
                                        onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    PackageDetailScreen(
                                                        delivery: d))),
                                        onRefresh: _load))),
                              ],
                            ),
                    ],
                  ),
                ),
              ]),
            ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  final PackageModel package;
  final VoidCallback onDelete;
  const _PackageCard({required this.package, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: const Color(AppColors.primaryLight),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.inventory_2_rounded,
                  color: Color(AppColors.primary))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(package.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                Text('${package.fromLocation} → ${package.toLocation}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(AppColors.textSecondary))),
              ])),
          StatusBadge(package.status),
          if (package.status == 'pending')
            IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    color: Color(AppColors.error)),
                tooltip: 'Delete'),
        ]),
        const Divider(height: 20),
        Row(children: [
          _info(Icons.scale_rounded, '${package.weight} kg'),
          const SizedBox(width: 16),
          _info(Icons.attach_money_rounded,
              'ETB ${package.offeredPrice.toStringAsFixed(0)}'),
        ]),
      ]),
    );
  }

  Widget _info(IconData icon, String label) => Row(children: [
        Icon(icon, size: 14, color: const Color(AppColors.textSecondary)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: Color(AppColors.textSecondary))),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════
// CHANGED: _InTransitCard is now StatefulWidget to handle payment confirmation
// ═══════════════════════════════════════════════════════════════════════════
class _InTransitCard extends StatefulWidget {
  final DeliveryModel delivery;
  final VoidCallback onTap;
  final VoidCallback? onCancel;
  final VoidCallback? onRefresh;
  const _InTransitCard(
      {required this.delivery,
      required this.onTap,
      this.onCancel,
      this.onRefresh});

  @override
  State<_InTransitCard> createState() => _InTransitCardState();
}

class _InTransitCardState extends State<_InTransitCard> {
  bool _confirming = false;

  // Check if sender needs to confirm they paid the traveler
  // FIXED: the app only ever writes status = 'completed' when a traveler
  // marks a delivery delivered (never 'delivered') — this used to check
  // the wrong string, so the button could never appear.
  bool get _needsPaymentConfirmation {
    return widget.delivery.status == 'completed' &&
        (widget.delivery.paymentStatus == 'pending' ||
            widget.delivery.paymentStatus == null);
  }

  bool get _paymentConfirmed {
    return widget.delivery.paymentStatus == 'sender_confirmed' ||
        widget.delivery.paymentStatus == 'commission_proof_submitted' ||
        widget.delivery.paymentStatus == 'commission_paid';
  }

  bool get _isDelivered {
    return widget.delivery.status == 'completed';
  }

  Future<void> _confirmTravelerPaid() async {
    final svc = DataService();
    setState(() => _confirming = true);

    final err = await svc.confirmTravelerPaid(widget.delivery.id);

    if (mounted) {
      setState(() => _confirming = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $err'),
              backgroundColor: const Color(AppColors.error)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Payment confirmed! Traveler has been notified to pay commission.'),
            backgroundColor: Color(AppColors.success),
          ),
        );
        widget.onRefresh?.call();
      }
    }
  }

  void _showConfirmDialog() {
    showDialog(
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
                'Have you paid the traveler ETB ${widget.delivery.amount.toStringAsFixed(0)} for "${widget.delivery.packageTitle ?? 'this delivery'}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF7EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF2A9E2D)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'After confirming, the traveler will be notified to pay the platform commission.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF2A9E2D)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmTravelerPaid();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppColors.primary),
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, I Paid'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDelivered = _isDelivered;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: widget.onTap,
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                    // ═══════════════════════════════════════════════════════════
                    // NEW: Different color for delivered vs in-transit
                    // ═══════════════════════════════════════════════════════════
                    color: isDelivered
                        ? const Color(0xFFEBF7EB)
                        : const Color(AppColors.primaryLight),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    isDelivered
                        ? Icons.check_circle_rounded
                        : Icons.local_shipping_rounded,
                    color: isDelivered
                        ? const Color(0xFF2A9E2D)
                        : const Color(AppColors.primary))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(widget.delivery.packageTitle ?? 'Package',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                      '${widget.delivery.fromLocation ?? '—'} → ${widget.delivery.toLocation ?? '—'}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(AppColors.textSecondary)),
                      overflow: TextOverflow.ellipsis),
                  if (widget.delivery.travelerName != null)
                    Text('Carried by ${widget.delivery.travelerName}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Color(AppColors.textSecondary))),
                ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('ETB ${widget.delivery.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              StatusBadge(widget.delivery.status),
              // ═══════════════════════════════════════════════════════════════
              // NEW: Show payment status for delivered items
              // ═══════════════════════════════════════════════════════════════
              if (isDelivered) ...[
                const SizedBox(height: 4),
                _PaymentStatusBadge(
                    paymentStatus: widget.delivery.paymentStatus ?? 'pending'),
              ],
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded,
                color: Color(AppColors.textSecondary)),
          ]),
          // ═══════════════════════════════════════════════════════════════════
          // NEW: Show "Traveler Paid" button for delivered-but-not-paid items
          // ═══════════════════════════════════════════════════════════════════
          if (_needsPaymentConfirmation) ...[
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _confirming ? null : _showConfirmDialog,
                icon: _confirming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.payments_rounded, size: 18),
                label: Text(_confirming
                    ? 'Confirming...'
                    : 'Traveler Paid — ETB ${widget.delivery.amount.toStringAsFixed(0)}'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(AppColors.primary),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap after you pay the traveler. The traveler will then pay the platform commission.',
              style: TextStyle(
                  fontSize: 11, color: Color(AppColors.textSecondary)),
            ),
          ] else if (isDelivered && _paymentConfirmed) ...[
            const Divider(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF7EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(
                  widget.delivery.paymentStatus == 'commission_paid'
                      ? Icons.check_circle_rounded
                      : Icons.hourglass_top_rounded,
                  size: 18,
                  color: widget.delivery.paymentStatus == 'commission_paid'
                      ? const Color(AppColors.success)
                      : const Color(0xFFD97706),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.delivery.paymentStatus == 'commission_paid'
                        ? 'Commission paid — all settled'
                        : 'Waiting for traveler to pay commission...',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.delivery.paymentStatus == 'commission_paid'
                          ? const Color(AppColors.success)
                          : const Color(0xFFD97706),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ]),
            ),
          ] else if (widget.onCancel != null) ...[
            const Divider(height: 20),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: widget.onCancel,
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(AppColors.error),
                    side: const BorderSide(color: Color(AppColors.error)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                child: const Text('Cancel delivery'),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW: Payment status badge widget
// ═══════════════════════════════════════════════════════════════════════════
class _PaymentStatusBadge extends StatelessWidget {
  final String paymentStatus;
  const _PaymentStatusBadge({required this.paymentStatus});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (paymentStatus) {
      'pending' => ('Payment Pending', const Color(0xFFD97706)),
      'sender_confirmed' => (
          'Awaiting Commission',
          const Color(AppColors.primary)
        ),
      'commission_due' => ('Commission Due', const Color(0xFFD97706)),
      'commission_proof_submitted' => (
          'Proof Submitted',
          const Color(AppColors.primary)
        ),
      'commission_paid' => ('All Paid', const Color(AppColors.success)),
      _ => ('Payment Pending', const Color(0xFFD97706)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Post Package Bottom Sheet ──────────────────────────────────────────────────

// Made public (and moved-in-place, not duplicated) so the Sender Dashboard
// can trigger the same "Post New Package" sheet directly from its welcome
// CTA without hopping through the My Packages screen first.
class PostPackageSheet extends ConsumerStatefulWidget {
  final String userId;
  final VoidCallback onSuccess;
  const PostPackageSheet(
      {super.key, required this.userId, required this.onSuccess});

  @override
  ConsumerState<PostPackageSheet> createState() => _PostPackageSheetState();
}

class _PostPackageSheetState extends ConsumerState<PostPackageSheet> {
  final _formKey = GlobalKey<FormState>();
  final _svc = DataService();
  final _pricingSvc = PricingService();
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String _deliveryType = 'hand';
  bool _confirmedLegal = false;
  bool _submitting = false;
  // Coordinates captured from location picker
  double? _fromLat, _fromLng, _toLat, _toLng;
  bool _computingPrice = false;
  PriceBreakdown? _priceBreakdown;
  String? _priceComputeError;

  // Title/nickname/description/weight fields were removed from this form to
  // keep posting fast — a sender just needs pickup, dropoff, and delivery
  // type. Weight is still part of the pricing formula (and travelers still
  // see it on the package card), so we assume the "standard" 1kg tier here
  // rather than asking for it. If you later want accurate per-package
  // weights for travelers to plan around, bring the Weight field back and
  // wire it into _computePrice() below instead of _standardWeightKg.
  static const _standardWeightKg = 1.0;

  @override
  void initState() {
    super.initState();
    // Seed defaults into platform_settings on first load (safe to call repeatedly)
    _pricingSvc
        .ensureDefaultRatesExist()
        .catchError((e) => print('Failed to seed pricing defaults: $e'));
  }

  @override
  void dispose() {
    for (final c in [_fromCtrl, _toCtrl, _priceCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickLocation(String label, bool isFrom) async {
    final result = await Navigator.of(context).push<LocationResult>(
      MaterialPageRoute(
          builder: (_) => LocationPickerScreen(title: 'Pick $label Location')),
    );
    if (result != null) {
      if (isFrom) {
        _fromLat = result.latLng.latitude;
        _fromLng = result.latLng.longitude;
        _fromCtrl.text = result.address;
      } else {
        _toLat = result.latLng.latitude;
        _toLng = result.latLng.longitude;
        _toCtrl.text = result.address;
      }
      setState(() {});
      // Auto-compute price once both locations are set
      if (_fromLat != null && _toLat != null) {
        _computePrice();
      }
    }
  }

  Future<void> _computePrice() async {
    if (_fromLat == null ||
        _fromLng == null ||
        _toLat == null ||
        _toLng == null) {
      return;
    }

    setState(() {
      _computingPrice = true;
      _priceBreakdown = null;
      _priceComputeError = null;
    });

    try {
      final dist = await _pricingSvc.getDistanceKm(
        LatLng(_fromLat!, _fromLng!),
        LatLng(_toLat!, _toLng!),
      );

      final rates = await _pricingSvc.fetchRates();
      final breakdown = _pricingSvc.calculatePrice(
        distanceKm: dist.km,
        weightKg: _standardWeightKg,
        deliveryType: _deliveryType,
        rates: rates,
        distanceEstimated: dist.estimated,
      );

      setState(() {
        _priceBreakdown = breakdown;
        _priceCtrl.text = breakdown.total.toStringAsFixed(0);
        _computingPrice = false;
      });
    } catch (e) {
      print('Price computation error: $e');
      setState(() {
        _computingPrice = false;
        _priceComputeError = 'Failed to compute price: $e';
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_confirmedLegal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Please confirm the package contains only legal items')));
      return;
    }
    if (_fromLat == null || _toLat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Please pick both pickup and dropoff locations on the map')));
      return;
    }

    setState(() => _submitting = true);
    final err = await _svc.insertPackage({
      'sender_id': widget.userId,
      'title': _autoTitle(),
      'from_location': _fromCtrl.text.trim(),
      'to_location': _toCtrl.text.trim(),
      'from_lat': _fromLat,
      'from_lng': _fromLng,
      'to_lat': _toLat,
      'to_lng': _toLng,
      'weight': _standardWeightKg,
      'offered_price': double.tryParse(_priceCtrl.text) ?? 0,
      'delivery_type': _deliveryType,
      'distance_km': _priceBreakdown?.distanceKm,
      'status': 'pending',
      'legal_items_confirmed': true,
    });

    if (mounted) {
      setState(() => _submitting = false);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $err')));
      } else {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Package posted successfully!')));
      }
    }
  }

  // With the Package Title field gone, derive a short, readable title from
  // the dropoff address instead (e.g. "Package to Bole") so it still shows
  // up sensibly in lists, notifications, and package details elsewhere in
  // the app.
  String _autoTitle() {
    final dropoff = _toCtrl.text.trim();
    if (dropoff.isEmpty) return 'Package';
    final firstPart = dropoff.split(',').first.trim();
    return 'Package to ${firstPart.isEmpty ? dropoff : firstPart}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      expand: false,
      builder: (_, ctrl) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Post New Package',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context)),
                  ])),
          const Divider(),
          Expanded(
              child: ListView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(20),
                  children: [
                Form(
                    key: _formKey,
                    child: Column(children: [
                      // Package rules info
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: const Color(AppColors.primaryLight),
                              borderRadius: BorderRadius.circular(10)),
                          child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Package Rules',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(AppColors.primary))),
                                SizedBox(height: 6),
                                Text(
                                    '✓ Only legal items allowed\n✓ Standard limit: under 5 kg\n✓ Larger packages may have extra charges',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Color(AppColors.textSecondary))),
                              ])),
                      const SizedBox(height: 16),
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Pickup & Dropoff Locations',
                              style: TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickLocation('Pickup', true),
                            icon: const Icon(Icons.location_on_rounded),
                            label: Text(_fromCtrl.text.isEmpty
                                ? 'Pick Pickup'
                                : 'Pickup ✓'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _fromLat != null
                                  ? const Color(AppColors.successLight)
                                  : const Color(AppColors.surface),
                              foregroundColor: _fromLat != null
                                  ? const Color(AppColors.success)
                                  : const Color(AppColors.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _pickLocation('Dropoff', false),
                            icon: const Icon(Icons.location_on_rounded),
                            label: Text(_toCtrl.text.isEmpty
                                ? 'Pick Dropoff'
                                : 'Dropoff ✓'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _toLat != null
                                  ? const Color(AppColors.successLight)
                                  : const Color(AppColors.surface),
                              foregroundColor: _toLat != null
                                  ? const Color(AppColors.success)
                                  : const Color(AppColors.textPrimary),
                            ),
                          ),
                        ),
                      ]),
                      if (_fromCtrl.text.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Pickup: ${_fromCtrl.text}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(AppColors.textSecondary)))),
                      if (_toCtrl.text.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Dropoff: ${_toCtrl.text}',
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(AppColors.textSecondary)))),
                      const SizedBox(height: 16),
                      _field(
                        _priceCtrl,
                        'Price (ETB)',
                        'Auto-calculated',
                        keyboard: TextInputType.number,
                        validator: (v) => (double.tryParse(v ?? '') == null)
                            ? 'Invalid price'
                            : null,
                      ),
                      if (_computingPrice)
                        const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: SizedBox(
                                width: 12,
                                height: 12,
                                child:
                                    CircularProgressIndicator(strokeWidth: 1))),
                      if (_priceBreakdown != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: const Color(AppColors.primaryLight),
                                borderRadius: BorderRadius.circular(10)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Price Breakdown',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: Color(AppColors.primary))),
                                  const SizedBox(height: 8),
                                  _priceBreakdownRow(
                                      'Base Fare', _priceBreakdown!.baseFare),
                                  _priceBreakdownRow(
                                      'Distance (${_priceBreakdown!.distanceKm.toStringAsFixed(1)} km)',
                                      _priceBreakdown!.distanceCost),
                                  if (_priceBreakdown!.weightCost > 0)
                                    _priceBreakdownRow('Weight Surcharge',
                                        _priceBreakdown!.weightCost),
                                  if (_priceBreakdown!.typeSurcharge > 0)
                                    _priceBreakdownRow('Office Drop-off Fee',
                                        _priceBreakdown!.typeSurcharge),
                                  Divider(
                                      height: 12,
                                      color: const Color(AppColors.primary)
                                          .withOpacity(0.3)),
                                  Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('Total',
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    Color(AppColors.primary))),
                                        Text(
                                            'ETB ${_priceBreakdown!.total.toStringAsFixed(0)}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    Color(AppColors.primary))),
                                      ]),
                                  if (_priceBreakdown!.distanceEstimated)
                                    const Padding(
                                        padding: EdgeInsets.only(top: 6),
                                        child: Text(
                                            '* Distance estimated (map service unavailable)',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Color(
                                                    AppColors.textSecondary)))),
                                ]),
                          ),
                        ),
                      if (_priceComputeError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(_priceComputeError!,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(AppColors.error))),
                          ),
                        ),
                      const SizedBox(height: 16),
                      const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Delivery Type',
                              style: TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(height: 8),
                      Row(children: [
                        _typeBtn(
                            'hand', 'Hand-to-Hand', Icons.handshake_rounded,
                            () {
                          setState(() => _deliveryType = 'hand');
                          if (_fromLat != null && _toLat != null) {
                            _computePrice();
                          }
                        }),
                        const SizedBox(width: 10),
                        _typeBtn(
                            'office', 'Office Drop-off', Icons.business_rounded,
                            () {
                          setState(() => _deliveryType = 'office');
                          if (_fromLat != null && _toLat != null) {
                            _computePrice();
                          }
                        }),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Checkbox(
                            value: _confirmedLegal,
                            onChanged: (v) =>
                                setState(() => _confirmedLegal = v ?? false),
                            activeColor: const Color(AppColors.primary)),
                        const Expanded(
                            child: Text(
                                'I confirm this package contains only legal items',
                                style: TextStyle(fontSize: 13))),
                      ]),
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(AppColors.primary),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12))),
                            child: _submitting
                                ? const CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)
                                : const Text('Post Package',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                          )),
                    ])),
              ])),
        ]),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint,
      {TextInputType? keyboard,
      int maxLines = 1,
      String? Function(String?)? validator,
      void Function(String)? onChanged}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboard,
      validator: validator,
      onChanged: onChanged,
      decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(AppColors.textSecondary)),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
    );
  }

  Widget _typeBtn(
          String val, String label, IconData icon, VoidCallback onTap) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: _deliveryType == val
                  ? const Color(AppColors.primaryLight)
                  : const Color(AppColors.surface),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: _deliveryType == val
                      ? const Color(AppColors.primary)
                      : const Color(AppColors.border)),
            ),
            child: Column(children: [
              Icon(icon,
                  color: _deliveryType == val
                      ? const Color(AppColors.primary)
                      : const Color(AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _deliveryType == val
                          ? const Color(AppColors.primary)
                          : const Color(AppColors.textPrimary))),
            ]),
          ),
        ),
      );

  Widget _priceBreakdownRow(String label, double amount) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
          Text('ETB ${amount.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
        ]),
      );
}
