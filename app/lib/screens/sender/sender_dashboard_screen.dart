// lib/screens/sender/sender_dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mode_provider.dart';
import '../../models/user_profile.dart';
import '../../services/data_service.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';
import 'sender_packages_screen.dart' show PostPackageSheet;

class SenderDashboardScreen extends ConsumerStatefulWidget {
  const SenderDashboardScreen({super.key});
  @override
  ConsumerState<SenderDashboardScreen> createState() => _SenderDashboardScreenState();
}

class _SenderDashboardScreenState extends ConsumerState<SenderDashboardScreen> {
  final _svc = DataService();
  Map<String, int> _stats = {};
  List<DeliveryModel> _recent = [];
  KycStatus _kycStatus = KycStatus.notSubmitted;
  bool _loading = true;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
    // Landing on the Sender dashboard means we're viewing sender mode —
    // sync the shared in-memory mode so the sidebar badge/toggle agrees.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(currentModeProvider.notifier).state = UserRole.sender;
      }
    });
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final results = await Future.wait([
      _svc.fetchSenderStats(user.id),
      _svc.fetchSenderDeliveries(user.id),
      _svc.fetchKycStatus(user.id),
    ]);
    if (mounted) {
      setState(() {
        _stats = results[0] as Map<String, int>;
        _recent = (results[1] as List<DeliveryModel>).take(5).toList();
        _kycStatus = results[2] as KycStatus;
        _loading = false;
      });
    }
  }

  // Opens the same "Post New Package" sheet used on the My Packages screen,
  // straight from the dashboard — no extra navigation hop required.
  void _openPostSheet() {
    if (_kycStatus != KycStatus.approved) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Complete KYC verification to post packages'),
        action: SnackBarAction(
          label: 'Verify',
          onPressed: () => context.go(AppConstants.routeSenderKyc),
        ),
      ));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => PostPackageSheet(
        userId: ref.read(authProvider).user!.id,
        onSuccess: _load,
      ),
    );
  }

  static const _navItems = [
    DrawerNavItem(icon: Icons.dashboard_rounded,       label: 'Dashboard',         route: AppConstants.routeSender),
    // Single authoritative tab for everything delivery-related — Pending,
    // In Transit, and Drafts/Canceled are now tabs inside this screen
    // (see SenderPackagesScreen), with drill-down to a Package Detail
    // screen for live tracking. "Active Orders" and "Track Delivery" have
    // been folded in here to remove the 3-screen hop this used to require.
    DrawerNavItem(icon: Icons.inventory_2_rounded,     label: 'My Packages',       route: AppConstants.routeSenderPackages),
    DrawerNavItem(icon: Icons.shield_rounded,          label: 'KYC Verification',  route: AppConstants.routeSenderKyc),
    DrawerNavItem(icon: Icons.support_agent_rounded,   label: 'Support',           route: AppConstants.routeSenderSupport),
    DrawerNavItem(icon: Icons.history_rounded,         label: 'Delivery History',  route: AppConstants.routeSenderHistory),
    DrawerNavItem(icon: Icons.settings_rounded,        label: 'Settings',          route: AppConstants.routeSenderSettings),
  ];

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider).profile;
    final firstName = profile?.fullName.split(' ').first ?? 'there';

    return DashboardScaffold(
      title: 'Sender Dashboard',
      navItems: _navItems,
      currentIndex: _tabIndex,
      onTabChanged: (i) { setState(() => _tabIndex = i); context.go(_navItems[i].route); },
      userName: profile?.fullName ?? '',
      userRole: 'Sender',
      // Tapping the role badge flips the shared mode state and routes
      // straight to the Traveler dashboard — no sign-out, no reload.
      allowModeToggle: true,
      onModeToggle: () {
        ref.read(currentModeProvider.notifier).state = UserRole.traveler;
        context.go(AppConstants.routeTraveler);
      },
      body: _loading ? const LoadingSpinner() : RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Welcome
            Text('Welcome back, $firstName! 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            const Text('Track and manage your packages below.', style: TextStyle(color: Color(AppColors.textSecondary))),
            const SizedBox(height: 16),

            // Primary CTA — this is the main trigger to post a package,
            // right where a sender lands after signing in. Tapping it opens
            // the Post New Package sheet directly, no extra screen hop.
            InkWell(
              onTap: _openPostSheet,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(AppColors.primary),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_box_rounded, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Have something to send?',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Post a package and find a traveler in minutes',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
                ]),
              ),
            ),
            const SizedBox(height: 20),

            // Stats
            GridView.count(
              crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12,
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              children: [
                StatCard(label: 'Active Packages', value: '${_stats['activePackages'] ?? 0}', icon: Icons.inventory_2_rounded),
                StatCard(label: 'In Transit', value: '${_stats['inTransit'] ?? 0}', icon: Icons.local_shipping_rounded, iconColor: const Color(AppColors.primary)),
                StatCard(label: 'Delivered', value: '${_stats['delivered'] ?? 0}', icon: Icons.check_circle_rounded, iconColor: const Color(AppColors.success)),
                StatCard(label: 'Pending', value: '${_stats['pending'] ?? 0}', icon: Icons.schedule_rounded, iconColor: const Color(0xFFD97706)),
              ],
            ),
            const SizedBox(height: 20),

            // Quick Actions
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [Icon(Icons.inventory_2_rounded, color: Color(AppColors.primary), size: 20), SizedBox(width: 8), Text('Quick Actions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]),
                const SizedBox(height: 12),
                _quickAction(Icons.add_circle_outline, 'Post New Package', _openPostSheet),
                const SizedBox(height: 8),
                _quickAction(Icons.gps_fixed_rounded, 'Track Deliveries', () => context.go(AppConstants.routeSenderPackages)),
              ]),
            ),
            const SizedBox(height: 16),

            // Recent Activity
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SectionHeader(title: 'Recent Activity', actionLabel: 'View All', onAction: () => context.go(AppConstants.routeSenderHistory)),
                const SizedBox(height: 12),
                if (_recent.isEmpty)
                  const EmptyState(icon: Icons.history_rounded, title: 'No recent activity', subtitle: 'Post a package to get started')
                else
                  ..._recent.map((d) => _deliveryRow(d)),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(AppColors.surface), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, color: const Color(AppColors.primary), size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          const Icon(Icons.chevron_right_rounded, color: Color(AppColors.textSecondary), size: 20),
        ]),
      ),
    );
  }

  Widget _deliveryRow(DeliveryModel d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: _statusColor(d.status), shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(child: Text('${d.packageTitle ?? 'Package'} — ${d.status.replaceAll('_', ' ')}', maxLines: 1, overflow: TextOverflow.ellipsis)),
        Text(_formatDate(d.createdAt), style: const TextStyle(fontSize: 12, color: Color(AppColors.textSecondary))),
      ]),
    );
  }

  Color _statusColor(String s) => switch (s) {
    'in_transit' => const Color(AppColors.primary),
    'completed' || 'delivered' => const Color(AppColors.success),
    _ => const Color(0xFFD97706),
  };

  String _formatDate(String iso) {
    try { return DateTime.parse(iso).toLocal().toString().substring(0, 10); } catch (_) { return ''; }
  }
}
