// lib/screens/traveler/traveler_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mode_provider.dart';
import '../../models/user_profile.dart';
import '../../services/data_service.dart';
import '../../services/notification_service.dart';
import '../../services/location_tracking_service.dart';
import '../../widgets/common/dispute_dialog.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';

// ── Traveler Dashboard ────────────────────────────────────────────────────────

class TravelerDashboardScreen extends ConsumerStatefulWidget {
  const TravelerDashboardScreen({super.key});
  @override
  ConsumerState<TravelerDashboardScreen> createState() =>
      _TravelerDashboardScreenState();
}

class _TravelerDashboardScreenState
    extends ConsumerState<TravelerDashboardScreen> {
  final _svc = DataService();
  Map<String, dynamic> _stats = {};
  KycStatus _kycStatus = KycStatus.notSubmitted;
  bool _loading = true;
  int _tabIndex = 0;
  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Track pending commission count for notification badge
  // ═══════════════════════════════════════════════════════════════════════════
  int _pendingCommissions = 0;
  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Live/Off toggle — whether this traveler is currently broadcasting
  // availability + position so senders can see them before a delivery is
  // even matched. Backed by LocationTrackingService.goOnline()/goOffline().
  // ═══════════════════════════════════════════════════════════════════════════
  bool _isLive = false;
  bool _togglingLive = false;
  // Whether we've already done the "force Offline on entry" reset for this
  // dashboard mount — only the very first load after sign-in should do this;
  // later pull-to-refreshes must keep reflecting the traveler's real status.
  bool _initialLiveSynced = false;

  static const _navItems = [
    DrawerNavItem(
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
        route: AppConstants.routeTraveler),
    // This is the screen fed by DataService.fetchAvailablePackages() —
    // renamed from "Carry Packages" per the bidding-system purge.
    DrawerNavItem(
        icon: Icons.inventory_2_rounded,
        label: 'Available Packages',
        route: AppConstants.routeTravelerPackages),
    // NOTE: this is the active-delivery lifecycle screen (Accept/Decline →
    // In Transit → Delivered) — NOT a duplicate of Available Packages.
    // Renamed from "My Offers" to something accurate now that there's no
    // bidding/negotiation happening here, just status progression.
    DrawerNavItem(
        icon: Icons.local_shipping_rounded,
        label: 'Active Deliveries',
        route: AppConstants.routeTravelerOffers),
    // ═══════════════════════════════════════════════════════════════════════
    // NEW: Commission Payment menu item
    // ═══════════════════════════════════════════════════════════════════════
    DrawerNavItem(
        icon: Icons.payment_rounded,
        label: 'Commission Payment',
        route: AppConstants.routeTravelerCommission),
    DrawerNavItem(
        icon: Icons.shield_rounded,
        label: 'KYC Verification',
        route: AppConstants.routeTravelerKyc),
    DrawerNavItem(
        icon: Icons.history_rounded,
        label: 'History & Earnings',
        route: AppConstants.routeTravelerHistory),
    DrawerNavItem(
        icon: Icons.settings_rounded,
        label: 'Settings',
        route: AppConstants.routeTravelerSettings),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    // Landing on the Traveler dashboard means we're viewing traveler mode —
    // sync the shared in-memory mode so the sidebar badge/toggle agrees.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(currentModeProvider.notifier).state = UserRole.traveler;
      }
    });
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final stats = await _svc.fetchTravelerStats(user.id);
    final kyc = await _svc.fetchKycStatus(user.id);
    // ═══════════════════════════════════════════════════════════════════════
    // NEW: Count pending commissions
    // ═══════════════════════════════════════════════════════════════════════
    final deliveries =
        await _svc.fetchTravelerDeliveries(user.id, statuses: ['completed']);
    final pendingCount = deliveries
        .where((d) =>
            d.paymentStatus == 'commission_due' ||
            d.paymentStatus == 'sender_confirmed')
        .length;
    // Live status: every fresh sign-in/dashboard mount should start Off —
    // the traveler must explicitly flip the toggle each session, it should
    // never come back on by itself just because a stale `is_online` row was
    // left set to true (e.g. the app got killed without a clean sign-out).
    // Pull-to-refresh on an already-open dashboard, however, should keep
    // reflecting the traveler's real current status.
    bool isLive;
    if (!_initialLiveSynced) {
      await LocationTrackingService().goOffline();
      isLive = false;
      _initialLiveSynced = true;
    } else {
      isLive = await _svc.fetchTravelerLiveStatus(user.id);
    }

    if (mounted) {
      setState(() {
        _stats = stats;
        _kycStatus = kyc;
        _pendingCommissions = pendingCount;
        _isLive = isLive;
        _loading = false;
      });
    }
  }

  Future<void> _toggleLive(bool goLive) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() => _togglingLive = true);
    if (goLive) {
      final started = await LocationTrackingService().goOnline(user.id);
      if (!started && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Location permission is off — turn it on so senders can see you\'re live.')));
      }
      if (mounted) {
        setState(() {
          _isLive = started;
          _togglingLive = false;
        });
      }
    } else {
      await LocationTrackingService().goOffline();
      if (mounted) {
        setState(() {
          _isLive = false;
          _togglingLive = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider).profile;
    final firstName = profile?.fullName.split(' ').first ?? 'there';

    return DashboardScaffold(
      title: 'Traveler Dashboard',
      navItems: _navItems,
      currentIndex: _tabIndex,
      onTabChanged: (i) {
        setState(() => _tabIndex = i);
        context.go(_navItems[i].route);
      },
      userName: profile?.fullName ?? '',
      userRole: 'Traveler',
      // Tapping the role badge flips back to Sender mode and routes there
      // directly — same signed-in session, no reload.
      allowModeToggle: true,
      onModeToggle: () {
        // Leaving Traveler mode — stop broadcasting Live status/position
        // right away instead of waiting for a future dashboard reload.
        if (LocationTrackingService().isOnline) {
          LocationTrackingService().goOffline();
        }
        if (_isLive) setState(() => _isLive = false);
        ref.read(currentModeProvider.notifier).state = UserRole.sender;
        context.go(AppConstants.routeSender);
      },
      // ═══════════════════════════════════════════════════════════════════════
      // NEW: Pass notification badges to drawer
      // ═══════════════════════════════════════════════════════════════════════

      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Welcome
                  Text('Welcome back, $firstName! ✈️',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  const Text('Ready to make deliveries today?',
                      style: TextStyle(color: Color(AppColors.textSecondary))),
                  const SizedBox(height: 16),

                  // ═══════════════════════════════════════════════════════════════
                  // NEW: Live/Off toggle — go live to broadcast availability +
                  // position so senders can see nearby travelers.
                  // ═══════════════════════════════════════════════════════════════
                  AppCard(
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: (_isLive
                                    ? const Color(AppColors.success)
                                    : const Color(AppColors.textSecondary))
                                .withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isLive
                                ? Icons.wifi_tethering_rounded
                                : Icons.wifi_tethering_off_rounded,
                            color: _isLive
                                ? const Color(AppColors.success)
                                : const Color(AppColors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isLive ? "You're Live" : "You're Offline",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isLive
                                    ? 'Senders can see your location and match you with nearby packages.'
                                    : 'Go live so senders can find and track you nearby.',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(AppColors.textSecondary)),
                              ),
                            ],
                          ),
                        ),
                        _togglingLive
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2.5),
                              )
                            : Switch(
                                value: _isLive,
                                activeColor: const Color(AppColors.success),
                                onChanged: _toggleLive,
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ═══════════════════════════════════════════════════════════════
                  // NEW: Commission payment alert banner
                  // ═══════════════════════════════════════════════════════════════
                  if (_pendingCommissions > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: GestureDetector(
                        onTap: () =>
                            context.go(AppConstants.routeTravelerCommission),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFD97706)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFFD97706).withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.payment_rounded,
                                  color: Color(0xFFD97706),
                                  size: 26,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$_pendingCommissions Commission Payment${_pendingCommissions > 1 ? 's' : ''} Pending',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Color(0xFFD97706),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    const Text(
                                      'You have deliveries waiting for commission payment. Tap to pay and submit proof.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Color(AppColors.textSecondary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFFD97706),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Stats
                  GridView.count(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 1.5,
                    children: [
                      StatCard(
                          label: 'Total Earnings',
                          value:
                              'ETB ${(_stats['totalEarnings'] as double? ?? 0).toStringAsFixed(0)}',
                          icon: Icons.attach_money_rounded,
                          iconColor: const Color(AppColors.success)),
                      StatCard(
                          label: 'Active Trips',
                          value: '${_stats['activeTrips'] ?? 0}',
                          icon: Icons.flight_takeoff_rounded),
                      StatCard(
                          label: 'Completed',
                          value: '${_stats['deliveriesCompleted'] ?? 0}',
                          icon: Icons.check_circle_rounded,
                          iconColor: const Color(AppColors.success)),
                      StatCard(
                          label: 'Pending Requests',
                          value: '${_stats['pendingRequests'] ?? 0}',
                          icon: Icons.schedule_rounded,
                          iconColor: const Color(0xFFD97706)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // KYC banner
                  if (_kycStatus != KycStatus.approved)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: KycWarningBanner(
                          isPending: _kycStatus == KycStatus.pending,
                          onVerifyNow: () =>
                              context.go(AppConstants.routeTravelerKyc)),
                    ),

                  // Quick Actions
                  AppCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Row(children: [
                          Icon(Icons.flight_takeoff_rounded,
                              color: Color(AppColors.primary), size: 20),
                          SizedBox(width: 8),
                          Text('Quick Actions',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold))
                        ]),
                        const SizedBox(height: 12),
                        _action(
                            Icons.inventory_2_outlined,
                            'Browse Package Requests',
                            () =>
                                context.go(AppConstants.routeTravelerPackages)),
                        const SizedBox(height: 8),
                        _action(
                            Icons.shield_outlined,
                            _kycStatus == KycStatus.approved
                                ? 'View KYC Status'
                                : 'Complete KYC',
                            () => context.go(AppConstants.routeTravelerKyc)),
                        // ═══════════════════════════════════════════════════
                        // NEW: Quick action for commission payment
                        // ═══════════════════════════════════════════════════
                        if (_pendingCommissions > 0) ...[
                          const SizedBox(height: 8),
                          _action(
                            Icons.payment_rounded,
                            'Pay Commission ($_pendingCommissions pending)',
                            () => context
                                .go(AppConstants.routeTravelerCommission),
                            color: const Color(0xFFD97706),
                          ),
                        ],
                      ])),
                ],
              ),
            ),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color? color}) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: const Color(AppColors.surface),
                borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(icon,
                  color: color ?? const Color(AppColors.primary), size: 20),
              const SizedBox(width: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              const Spacer(),
              const Icon(Icons.chevron_right_rounded,
                  color: Color(AppColors.textSecondary), size: 20)
            ])),
      );
}

// ── Traveler Packages ─────────────────────────────────────────────────────────

class TravelerPackagesScreen extends ConsumerStatefulWidget {
  const TravelerPackagesScreen({super.key});
  @override
  ConsumerState<TravelerPackagesScreen> createState() =>
      _TravelerPackagesScreenState();
}

class _TravelerPackagesScreenState
    extends ConsumerState<TravelerPackagesScreen> {
  final _svc = DataService();
  final _notifSvc = NotificationService();
  List<PackageModel> _packages = [];
  bool _loading = true;
  String? _acceptingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final pkgs = await _svc.fetchAvailablePackages(user.id);
    if (mounted) {
      setState(() {
        _packages = pkgs;
        _loading = false;
      });
    }
  }

  Future<void> _accept(PackageModel pkg) async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    setState(() => _acceptingId = pkg.id);
    final err = await _svc.instantMatchDelivery(
      packageId: pkg.id,
      senderId: pkg.senderId,
      travelerId: user.id,
    );

    if (err == null) {
      await _notifSvc.sendNotification(
        userId: pkg.senderId,
        title: 'Your package is matched!',
        body:
            'A traveler is now carrying "${pkg.title}". Check My Packages for tracking.',
        type: 'delivery_matched',
      );
      if (mounted) setState(() => _packages.removeWhere((p) => p.id == pkg.id));
    }

    if (mounted) {
      setState(() => _acceptingId = null);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $err'), backgroundColor: Colors.red));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Matched! This is now an active delivery.')));
        context.go(AppConstants.routeTravelerOffers);
      }
    }
  }

  String _timeAgo(String iso) {
    try {
      final diff = DateTime.now().difference(DateTime.parse(iso));
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      return 'just now';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('Available Packages',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: _packages.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_rounded,
                      title: 'No packages available',
                      subtitle:
                          'Check back later for new package requests from senders')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _packages.length,
                      itemBuilder: (_, i) {
                        final p = _packages[i];
                        final accepting = _acceptingId == p.id;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                              child: Row(children: [
                            Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                    color: const Color(AppColors.primaryLight),
                                    borderRadius: BorderRadius.circular(12)),
                                child: const Icon(Icons.inventory_2_rounded,
                                    color: Color(AppColors.primary))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(p.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  Text('From ${p.displaySenderName}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              Color(AppColors.textSecondary))),
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    _info(Icons.location_on_rounded,
                                        '${p.fromLocation} → ${p.toLocation}'),
                                  ]),
                                  Row(children: [
                                    _info(
                                        Icons.scale_rounded, '${p.weight} kg'),
                                    const SizedBox(width: 10),
                                    _info(Icons.attach_money_rounded,
                                        'Fixed payout: ETB ${p.offeredPrice.toStringAsFixed(0)}'),
                                  ]),
                                ])),
                            const SizedBox(width: 8),
                            Column(children: [
                              Text(_timeAgo(p.createdAt),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(AppColors.textSecondary))),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: accepting ? null : () => _accept(p),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        const Color(AppColors.primary),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8)),
                                child: accepting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Text('Deliver This',
                                        style: TextStyle(fontSize: 13)),
                              ),
                            ]),
                          ])),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _info(IconData icon, String t) => Row(children: [
        Icon(icon, size: 12, color: const Color(AppColors.textSecondary)),
        const SizedBox(width: 3),
        Text(t,
            style: const TextStyle(
                fontSize: 12, color: Color(AppColors.textSecondary)))
      ]);
}

// ── Traveler Offers (active deliveries) ───────────────────────────────────────

class TravelerOffersScreen extends ConsumerStatefulWidget {
  const TravelerOffersScreen({super.key});
  @override
  ConsumerState<TravelerOffersScreen> createState() =>
      _TravelerOffersScreenState();
}

class _TravelerOffersScreenState extends ConsumerState<TravelerOffersScreen> {
  final _svc = DataService();
  final _sb = Supabase.instance.client;
  List<DeliveryModel> _active = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final list = await _svc.fetchTravelerDeliveries(user.id,
        statuses: ['pending', 'accepted', 'in_transit']);
    if (mounted) {
      setState(() {
        _active = list;
        _loading = false;
      });
    }
    // Safety net: if the sender cancels a delivery from their side while
    // this traveler is mid-transit, this realtime reload is how we find out.
    // Nothing left in_transit? Make sure GPS streaming isn't still running.
    if (!list.any((d) => d.status == 'in_transit')) {
      await LocationTrackingService().stopTracking();
    }
  }

  void _subscribeRealtime() {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    _channel = _sb
        .channel('traveler-offers-${user.id}')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'deliveries',
            filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'traveler_id',
                value: user.id),
            callback: (_) => _load())
        .subscribe();
  }

  Future<void> _updateStatus(String deliveryId, String newStatus) async {
    final now = DateTime.now();
    final updates = <String, dynamic>{'status': newStatus};
    final travelerId = ref.read(authProvider).user?.id;

    // Stamp pickup time and set 5-hour expiry window when traveler picks up
    if (newStatus == 'in_transit') {
      updates['pickup_at'] = now.toIso8601String();
      updates['expires_at'] =
          now.add(const Duration(hours: 5)).toIso8601String();
    }

    // Manual commission model: sender pays the traveler directly, so on
    // completion the traveler owes Bemengede its cut — not the other way
    // around. NOTE: payment_status is no longer set here — the
    // set_delivery_expiry() DB trigger (Supabase) now sets
    // payment_status = 'commission_due' and sends the traveler their
    // "Payout Earned" notification itself, so it fires reliably even if
    // no one has the app open. Only stamp completed_at as a client hint;
    // the trigger sets it too but this keeps the local model in sync
    // without waiting on a realtime round-trip.
    if (newStatus == 'completed') {
      updates['completed_at'] = now.toIso8601String();
    }

    final error = await _svc.updateDelivery(deliveryId, updates);
    if (error != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Could not update delivery: $error'),
            backgroundColor: const Color(AppColors.error)));
      }
      return;
    }

    // ── Live GPS tracking ────────────────────────────────────────────────
    // Start streaming device location into trips.current_lat/current_lng
    // the moment the traveler goes in_transit, so the sender's live map
    // (SenderTrackingMapScreen) has something to subscribe to. Stop it as
    // soon as the delivery wraps up or is cancelled — no reason to keep
    // draining battery/GPS after the trip ends.
    if (travelerId != null) {
      if (newStatus == 'in_transit') {
        final started =
            await LocationTrackingService().startTracking(deliveryId);
        if (!started && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Location permission is off — the sender won\'t see your live position on the map.')));
        }
      } else if (newStatus == 'completed' || newStatus == 'cancelled') {
        await LocationTrackingService().stopTracking();
      }
    }

    // Admin heads-up isn't sent by the DB trigger, so keep sending it from
    // here; then prompt the rating screen.
    if (newStatus == 'completed' && mounted) {
      final delivery = _active.firstWhere((d) => d.id == deliveryId,
          orElse: () => _active.first);
      final travelerName =
          ref.read(authProvider).profile?.fullName ?? 'A traveler';
      await NotificationService().notifyAdminDeliveryCompleted(
        travelerName: travelerName,
        amount: delivery.amount,
        packageTitle: delivery.packageTitle ?? 'Package',
      );
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            _RatingSheet(deliveryId: deliveryId, rateeId: delivery.senderId),
      );
    }

    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
        title: const Text('Active Offers',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(AppColors.successLight),
                  borderRadius: BorderRadius.circular(20)),
              child: const Row(children: [
                Icon(Icons.circle, size: 8, color: Color(AppColors.success)),
                SizedBox(width: 6),
                Text('Live',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(AppColors.success),
                        fontWeight: FontWeight.w600))
              ]))
        ],
      ),
      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: _active.isEmpty
                  ? const EmptyState(
                      icon: Icons.local_offer_rounded,
                      title: 'No active offers',
                      subtitle:
                          'Browse package requests or wait for senders to find your trip')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _active.length,
                      itemBuilder: (_, i) {
                        final d = _active[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AppCard(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(d.packageTitle ?? 'Delivery',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15)),
                                        Text(
                                            '${d.fromLocation} → ${d.toLocation}',
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(
                                                    AppColors.textSecondary))),
                                      ])),
                                  StatusBadge(d.status),
                                ]),
                                const Divider(height: 20),
                                Row(children: [
                                  _stat('Amount',
                                      'ETB ${d.amount.toStringAsFixed(0)}'),
                                  const SizedBox(width: 16),
                                  _stat('Weight', '${d.weight} kg'),
                                ]),
                                const SizedBox(height: 14),
                                if (d.status == 'in_transit' && d.isOverdue)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                        color: const Color(0xFFFEF2F2),
                                        borderRadius: BorderRadius.circular(8)),
                                    child: Row(children: [
                                      const Icon(Icons.timer_off_rounded,
                                          size: 16,
                                          color: Color(AppColors.error)),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        child: Text(
                                            'Overdue — this delivery is past its 5-hour window. Please complete it or report a problem.',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Color(AppColors.error),
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ]),
                                  ),
                                // Action buttons depending on status
                                if (d.status == 'pending')
                                  Row(children: [
                                    Expanded(
                                        child: ElevatedButton(
                                            onPressed: () =>
                                                _updateStatus(d.id, 'accepted'),
                                            style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(
                                                    AppColors.success),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8))),
                                            child: const Text('Accept'))),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: OutlinedButton(
                                            onPressed: () => _updateStatus(
                                                d.id, 'cancelled'),
                                            style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(
                                                    AppColors.error),
                                                side: const BorderSide(
                                                    color:
                                                        Color(AppColors.error)),
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8))),
                                            child: const Text('Decline'))),
                                  ]),
                                if (d.status == 'accepted')
                                  SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _updateStatus(d.id, 'in_transit'),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(AppColors.primary),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8))),
                                        child: const Text('Mark as In Transit'),
                                      )),
                                if (d.status == 'in_transit')
                                  SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _updateStatus(d.id, 'completed'),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(AppColors.success),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8))),
                                        child: const Text('Mark as Delivered'),
                                      )),
                              ])),
                        );
                      },
                    ),
            ),
    );
  }

  Widget _stat(String label, String val) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Color(AppColors.textSecondary))),
        Text(val,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ]);
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW: Commission Payment Screen — dedicated page for travelers to pay commission
// ═══════════════════════════════════════════════════════════════════════════

class TravelerCommissionScreen extends ConsumerStatefulWidget {
  const TravelerCommissionScreen({super.key});
  @override
  ConsumerState<TravelerCommissionScreen> createState() =>
      _TravelerCommissionScreenState();
}

class _TravelerCommissionScreenState
    extends ConsumerState<TravelerCommissionScreen> {
  final _svc = DataService();
  List<DeliveryModel> _pendingCommissions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      // Fetch completed deliveries that need commission payment
      final deliveries = await _svc.fetchTravelerDeliveries(user.id,
          statuses: ['completed', 'delivered']);
      // Filter to only those needing commission payment
      final pending = deliveries
          .where((d) =>
              d.paymentStatus == 'commission_due' ||
              d.paymentStatus == 'sender_confirmed' ||
              d.paymentStatus == 'commission_proof_submitted')
          .toList();

      if (mounted) {
        setState(() {
          _pendingCommissions = pending;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading commissions: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
        title: const Text('Commission Payment',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: _pendingCommissions.isEmpty
                  ? const EmptyState(
                      icon: Icons.check_circle_rounded,
                      title: 'All caught up!',
                      subtitle:
                          'You have no pending commission payments. Great job!')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _pendingCommissions.length,
                      itemBuilder: (_, i) {
                        final d = _pendingCommissions[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CommissionPaymentCard(
                            delivery: d,
                            onChanged: _load,
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _CommissionPaymentCard extends StatefulWidget {
  final DeliveryModel delivery;
  final VoidCallback onChanged;
  const _CommissionPaymentCard({
    required this.delivery,
    required this.onChanged,
  });

  @override
  State<_CommissionPaymentCard> createState() => _CommissionPaymentCardState();
}

class _CommissionPaymentCardState extends State<_CommissionPaymentCard> {
  final _svc = DataService();
  final _picker = ImagePicker();
  bool _uploading = false;
  bool _loadingDetails = false;
  Map<String, dynamic>? _commissionDetails;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() => _loadingDetails = true);
    final details = await _svc.fetchCommissionDetails(widget.delivery.id);
    if (mounted) {
      setState(() {
        _commissionDetails = details;
        _loadingDetails = false;
      });
    }
  }

  Future<void> _submitProof() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploading = true);
    final bytes = await picked.readAsBytes();
    final err = await _svc.submitCommissionProof(widget.delivery.id, bytes);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $err')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Proof submitted — waiting for admin review')));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;
    final commissionRate =
        _commissionDetails?['commission_rate'] as double? ?? 0;
    final commissionAmount =
        _commissionDetails?['commission_amount'] as double? ?? 0;
    final escrowTelebirr =
        _commissionDetails?['escrow_telebirr'] as String? ?? '';
    final escrowCbe = _commissionDetails?['escrow_cbe'] as String? ?? '';
    final escrowAwash = _commissionDetails?['escrow_awash'] as String? ?? '';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(AppColors.primaryLight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.payment_rounded,
                color: Color(AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.packageTitle ?? 'Delivery',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${d.fromLocation} → ${d.toLocation}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'ETB ${d.amount.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _PaymentStatusBadge(
                    paymentStatus: d.paymentStatus ?? 'pending'),
              ],
            ),
          ]),
          const Divider(height: 20),

          // Commission details
          if (_loadingDetails) ...[
            const Center(
                child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(AppColors.primaryLight),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Commission Details',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Color(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Delivery Amount'),
                      Text('ETB ${d.amount.toStringAsFixed(0)}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Commission Rate ($commissionRate%)'),
                      Text('ETB ${commissionAmount.toStringAsFixed(2)}'),
                    ],
                  ),
                  const Divider(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'You Pay',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'ETB ${commissionAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(AppColors.primary),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Payment instructions
            const Text(
              'Pay to one of these accounts:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (escrowTelebirr.isNotEmpty)
              _accountRow(
                  Icons.phone_android_rounded, 'Telebirr', escrowTelebirr),
            if (escrowCbe.isNotEmpty)
              _accountRow(Icons.account_balance_rounded, 'CBE', escrowCbe),
            if (escrowAwash.isNotEmpty)
              _accountRow(Icons.account_balance_rounded, 'Awash', escrowAwash),
            const SizedBox(height: 16),

            // Action based on status
            if (d.paymentStatus == 'commission_paid') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF7EB),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Color(AppColors.success)),
                    SizedBox(width: 8),
                    Text(
                      'Commission paid — all settled',
                      style: TextStyle(
                        color: Color(AppColors.success),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (d.paymentStatus == 'commission_proof_submitted') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: Color(0xFFD97706)),
                    SizedBox(width: 8),
                    Text(
                      'Proof submitted — awaiting admin review',
                      style: TextStyle(
                        color: Color(0xFFD97706),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (d.commissionProofUrl != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    d.commissionProofUrl!,
                    height: 120,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ] else ...[
              // commission_due or sender_confirmed
              if (d.commissionRejectionReason != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Previous proof rejected: ${d.commissionRejectionReason}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(AppColors.error),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _uploading ? null : _submitProof,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.upload_rounded, size: 18),
                  label: Text(
                    _uploading ? 'Uploading...' : 'Submit Payment Proof',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(AppColors.primary),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'After paying the commission, upload a screenshot of your payment receipt.',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(AppColors.textSecondary),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _accountRow(IconData icon, String method, String account) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(AppColors.primary)),
            const SizedBox(width: 8),
            Text(
              '$method: ',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
            Expanded(
              child: Text(
                account,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(AppColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      );
}

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

// ── Traveler History ──────────────────────────────────────────────────────────

class TravelerHistoryScreen extends ConsumerStatefulWidget {
  const TravelerHistoryScreen({super.key});
  @override
  ConsumerState<TravelerHistoryScreen> createState() =>
      _TravelerHistoryScreenState();
}

class _TravelerHistoryScreenState extends ConsumerState<TravelerHistoryScreen> {
  final _svc = DataService();
  List<DeliveryModel> _deliveries = [];
  bool _loading = true;
  double _avgRating = 0;
  int _reviewCount = 0;
  bool _isVerified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final deliveries = await _svc.fetchTravelerDeliveries(user.id,
          statuses: ['completed', 'cancelled']);
      final kyc = await _svc.fetchKycStatus(user.id);
      // Fetch ratings
      final ratings = await _svc.fetchUserRatings(user.id);
      if (mounted) {
        setState(() {
          _deliveries = deliveries;
          _isVerified = kyc == KycStatus.approved;
          _avgRating = ratings.isEmpty
              ? 0
              : ratings.reduce((a, b) => a + b) / ratings.length;
          _reviewCount = ratings.length;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalEarned = _deliveries
        .where((d) => d.paymentStatus == 'released')
        .fold(0.0, (s, d) => s + (d.agreedPrice ?? 0));
    final pendingPayout = _deliveries
        .where((d) => d.isCompleted && d.paymentStatus == 'received')
        .fold(0.0, (s, d) => s + (d.agreedPrice ?? 0));
    final completed = _deliveries.where((d) => d.isCompleted).length;

    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('History & Earnings',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: _loading
          ? const LoadingSpinner()
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 48, color: Color(AppColors.error)),
                      const SizedBox(height: 12),
                      const Text('Couldn\'t load history',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(AppColors.textSecondary))),
                      const SizedBox(height: 16),
                      ElevatedButton(
                          onPressed: _load, child: const Text('Retry')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Rating summary
                      AppCard(
                          child: Row(children: [
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                if (_reviewCount > 0) ...[
                                  const Icon(Icons.star_rounded,
                                      color: Color(0xFFF59E0B), size: 20),
                                  const SizedBox(width: 4),
                                  Text(_avgRating.toStringAsFixed(1),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  const SizedBox(width: 4),
                                  Text('($_reviewCount reviews)',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color:
                                              Color(AppColors.textSecondary))),
                                ] else
                                  const Text('No reviews yet',
                                      style: TextStyle(
                                          color:
                                              Color(AppColors.textSecondary))),
                                if (_isVerified) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                          color: const Color(
                                              AppColors.successLight),
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      child: const Text('Verified',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Color(AppColors.success),
                                              fontWeight: FontWeight.bold))),
                                ],
                              ]),
                              const SizedBox(height: 4),
                              Text('$completed deliveries completed',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(AppColors.textSecondary))),
                            ])),
                      ])),
                      const SizedBox(height: 12),

                      // Earnings cards
                      Row(children: [
                        Expanded(
                            child: AppCard(
                                color: const Color(AppColors.successLight),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Total Earned',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(
                                                  AppColors.textSecondary))),
                                      Text(
                                          'ETB ${totalEarned.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Color(AppColors.success))),
                                    ]))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: AppCard(
                                color: const Color(AppColors.primaryLight),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Pending Payout',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(
                                                  AppColors.textSecondary))),
                                      Text(
                                          'ETB ${pendingPayout.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Color(AppColors.primary))),
                                    ]))),
                      ]),
                      const SizedBox(height: 20),

                      const Text('Delivery History',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),

                      if (_deliveries.isEmpty)
                        const EmptyState(
                            icon: Icons.history_rounded,
                            title: 'No history yet',
                            subtitle: 'Completed deliveries will appear here')
                      else
                        ..._deliveries.map((d) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _TravelerHistoryCard(
                                  delivery: d, onChanged: _load),
                            )),
                    ],
                  ),
                ),
    );
  }
}

class _TravelerHistoryCard extends ConsumerWidget {
  final DeliveryModel delivery;
  final VoidCallback onChanged;
  const _TravelerHistoryCard({required this.delivery, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = delivery;
    return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: d.isCancelled
                    ? const Color(0xFFFEF2F2)
                    : const Color(AppColors.successLight),
                shape: BoxShape.circle),
            child: Icon(
                d.isCancelled
                    ? Icons.cancel_rounded
                    : Icons.check_circle_rounded,
                color: d.isCancelled
                    ? const Color(AppColors.error)
                    : const Color(AppColors.success))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(d.packageTitle ?? 'Package',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${d.fromLocation} → ${d.toLocation}',
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
          if (d.senderName != null)
            Text('From: ${d.senderName}',
                style: const TextStyle(
                    fontSize: 12, color: Color(AppColors.textSecondary))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('ETB ${(d.agreedPrice ?? d.amount).toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          StatusBadge(d.status),
          const SizedBox(height: 4),
          if (d.paymentStatus == 'released')
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(AppColors.successLight),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Released',
                    style: TextStyle(
                        fontSize: 10,
                        color: Color(AppColors.success),
                        fontWeight: FontWeight.bold)))
          else if (d.isCompleted)
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                    color: const Color(AppColors.primaryLight),
                    borderRadius: BorderRadius.circular(10)),
                child: const Text('Pending Payout',
                    style: TextStyle(
                        fontSize: 10,
                        color: Color(AppColors.primary),
                        fontWeight: FontWeight.bold))),
        ]),
      ]),
      const Divider(height: 20),
      if (d.isCompleted &&
          [
            'commission_due',
            'commission_proof_submitted',
            'commission_paid',
            'sender_confirmed'
          ].contains(d.paymentStatus)) ...[
        _CommissionProofSection(delivery: d, onChanged: onChanged),
        const Divider(height: 20),
      ],
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () {
            final userId = ref.read(authProvider).user?.id;
            if (userId == null) return;
            showReportProblemDialog(context,
                deliveryId: d.id, raisedByUserId: userId);
          },
          icon: const Icon(Icons.warning_amber_rounded,
              size: 16, color: Color(AppColors.error)),
          label: const Text('Report a Problem',
              style: TextStyle(color: Color(AppColors.error), fontSize: 12)),
        ),
      ),
    ]));
  }
}

// ── Commission proof of payment ───────────────────────────────────────────
// Traveler pays Bemengede its commission outside the app, then submits a
// screenshot of that payment here for an admin to review. Three states:
//   commission_due               → show upload button (+ rejection reason
//                                   if this is a resubmit after a reject)
//   commission_proof_submitted   → "under review", show what was submitted
//   commission_paid              → confirmed, nothing left to do
class _CommissionProofSection extends StatefulWidget {
  final DeliveryModel delivery;
  final VoidCallback onChanged;
  const _CommissionProofSection(
      {required this.delivery, required this.onChanged});

  @override
  State<_CommissionProofSection> createState() =>
      _CommissionProofSectionState();
}

class _CommissionProofSectionState extends State<_CommissionProofSection> {
  final _svc = DataService();
  final _picker = ImagePicker();
  bool _uploading = false;

  Future<void> _submitProof() async {
    final picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _uploading = true);
    final bytes = await picked.readAsBytes();
    final err = await _svc.submitCommissionProof(widget.delivery.id, bytes);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Upload failed: $err')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Proof submitted — waiting for admin review')));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.delivery;

    if (d.paymentStatus == 'commission_paid') {
      return Row(children: [
        const Icon(Icons.check_circle_rounded,
            size: 16, color: Color(AppColors.success)),
        const SizedBox(width: 6),
        const Text('Commission paid',
            style: TextStyle(
                fontSize: 12,
                color: Color(AppColors.success),
                fontWeight: FontWeight.w600)),
      ]);
    }

    if (d.paymentStatus == 'commission_proof_submitted') {
      return Row(children: [
        if (d.commissionProofUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(d.commissionProofUrl!,
                width: 40, height: 40, fit: BoxFit.cover),
          ),
        const SizedBox(width: 10),
        const Expanded(
          child: Text('Payment proof submitted — awaiting admin review',
              style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.w600)),
        ),
      ]);
    }

    // commission_due or sender_confirmed
    if (d.hasOpenDispute) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Icon(Icons.pause_circle_outline_rounded,
              size: 16, color: Color(0xFF92400E)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
                'Payment paused — there\'s an open dispute on this delivery. It\'ll unlock once our team resolves it.',
                style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF92400E),
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (d.commissionRejectionReason != null) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8)),
          child: Text(
              'Proof rejected: ${d.commissionRejectionReason}. Please resubmit.',
              style:
                  const TextStyle(fontSize: 12, color: Color(AppColors.error))),
        ),
        const SizedBox(height: 8),
      ],
      const Text('Commission owed to Bemengede — pay, then submit proof',
          style:
              TextStyle(fontSize: 12, color: Color(AppColors.textSecondary))),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _uploading ? null : _submitProof,
          icon: _uploading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.upload_rounded, size: 16),
          label: Text(_uploading ? 'Uploading...' : 'Submit payment proof'),
          style: OutlinedButton.styleFrom(
              foregroundColor: const Color(AppColors.primary),
              side: const BorderSide(color: Color(AppColors.primary)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8))),
        ),
      ),
    ]);
  }
}

// ── Traveler Settings ─────────────────────────────────────────────────────────

class TravelerSettingsScreen extends ConsumerStatefulWidget {
  const TravelerSettingsScreen({super.key});
  @override
  ConsumerState<TravelerSettingsScreen> createState() =>
      _TravelerSettingsScreenState();
}

class _TravelerSettingsScreenState
    extends ConsumerState<TravelerSettingsScreen> {
  final _svc = DataService();
  final _fullNameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  String _email = '';
  String _preferredPayment = '';
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_fullNameCtrl, _nicknameCtrl, _phoneCtrl, _accountCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final data = await _svc.fetchProfileSettings(user.id);
    if (data != null && mounted) {
      _fullNameCtrl.text = data['full_name'] ?? '';
      _nicknameCtrl.text = data['nickname'] ?? '';
      _phoneCtrl.text = data['phone'] ?? '';
      _accountCtrl.text = data['payment_account'] ?? '';
      setState(() {
        _email = data['email'] ?? '';
        _preferredPayment = data['preferred_payment'] ?? '';
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_nicknameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nickname is required')));
      return;
    }
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _saving = true);
    final err = await _svc.updateProfileSettings(user.id, {
      'full_name': _fullNameCtrl.text.trim(),
      'nickname': _nicknameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'preferred_payment': _preferredPayment.isEmpty ? null : _preferredPayment,
      'payment_account':
          _accountCtrl.text.trim().isEmpty ? null : _accountCtrl.text.trim(),
    });
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err ?? 'Settings saved!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('Settings',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: _loading
          ? const LoadingSpinner()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Row(children: [
                        Icon(Icons.person_outline_rounded,
                            color: Color(AppColors.primary)),
                        SizedBox(width: 8),
                        Text('Profile Info',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))
                      ]),
                      const SizedBox(height: 16),
                      _field(_fullNameCtrl, 'Full Name'),
                      const SizedBox(height: 12),
                      _field(_nicknameCtrl, 'Nickname * (visible to senders)'),
                      const SizedBox(height: 12),
                      TextFormField(
                          initialValue: _email,
                          enabled: false,
                          decoration: _dec('Email')),
                      const SizedBox(height: 12),
                      _field(_phoneCtrl, 'Phone'),
                    ])),
                const SizedBox(height: 16),
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Row(children: [
                        Icon(Icons.credit_card_rounded,
                            color: Color(AppColors.primary)),
                        SizedBox(width: 8),
                        Text('Payout Preference',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))
                      ]),
                      const SizedBox(height: 4),
                      const Text('Where you want to receive your earnings',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(AppColors.textSecondary))),
                      const SizedBox(height: 16),
                      ...kPaymentMethods.map((m) => RadioListTile<String>(
                            value: m.value,
                            groupValue: _preferredPayment,
                            onChanged: (v) =>
                                setState(() => _preferredPayment = v ?? ''),
                            title: Text(m.label,
                                style: const TextStyle(fontSize: 14)),
                            activeColor: const Color(AppColors.primary),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          )),
                      if (_preferredPayment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _field(_accountCtrl,
                            '${kPaymentMethods.firstWhere((m) => m.value == _preferredPayment, orElse: () => const PaymentMethod(value: '', label: '', placeholder: '')).label} Account'),
                      ],
                    ])),
                const SizedBox(height: 20),
                SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_rounded),
                      label: const Text('Save Changes',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(AppColors.primary),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12))),
                    )),
              ],
            ),
    );
  }

  Widget _field(TextEditingController ctrl, String label) =>
      TextFormField(controller: ctrl, decoration: _dec(label));
  InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      filled: true,
      fillColor: Colors.white);
}
// Traveler KYC: moved to dedicated file `traveler_kyc_screen.dart` to avoid
// duplicate class definitions. Use that file for the full KYC implementation.

// ── Rating Sheet ──────────────────────────────────────────────────────────────
// Shown to traveler after marking delivery completed

class _RatingSheet extends ConsumerStatefulWidget {
  final String deliveryId;
  final String rateeId;
  const _RatingSheet({required this.deliveryId, required this.rateeId});
  @override
  ConsumerState<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends ConsumerState<_RatingSheet> {
  final _svc = DataService();
  final _commentCtrl = TextEditingController();
  int _stars = 5;
  bool _submitting = false;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _submitting = true);
    final err = await _svc.submitRating(
      deliveryId: widget.deliveryId,
      raterId: user.id,
      rateeId: widget.rateeId,
      stars: _stars,
      comment: _commentCtrl.text.trim(),
    );
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err == null
                ? 'Rating submitted. Thank you!'
                : 'Rating error: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Rate the Sender',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('How was your experience with this delivery?',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            // Star selector
            Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  return GestureDetector(
                    onTap: () => setState(() => _stars = i + 1),
                    child: Icon(
                        i < _stars
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: 40,
                        color: i < _stars ? Colors.amber : Colors.grey),
                  );
                })),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Leave a comment (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Rating',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                )),
          ]),
    );
  }
}
