// lib/screens/admin/admin_screens.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/auth_provider.dart';
import '../../models/models.dart';
import '../../services/data_service.dart';
import '../../services/notification_service.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';

// ── Shared Admin Layout ───────────────────────────────────────────────────────

class AdminScaffold extends ConsumerWidget {
  final String title;
  final Widget body;
  final int currentIndex;

  static const _routes = [
    AppConstants.routeAdmin,
    AppConstants.routeAdminUsers,
    AppConstants.routeAdminKyc,
    AppConstants.routeAdminTrips,
    AppConstants.routeAdminPackages,
    AppConstants.routeAdminPayments,
    AppConstants.routeAdminDisputes,
    AppConstants.routeAdminSupport,
    AppConstants.routeAdminFees,
    AppConstants.routeAdminSettings,
  ];

  static const _navItems = [
    DrawerNavItem(
        icon: Icons.dashboard_rounded,
        label: 'Dashboard',
        route: AppConstants.routeAdmin),
    DrawerNavItem(
        icon: Icons.people_rounded,
        label: 'Users',
        route: AppConstants.routeAdminUsers),
    DrawerNavItem(
        icon: Icons.verified_user_rounded,
        label: 'KYC',
        route: AppConstants.routeAdminKyc),
    DrawerNavItem(
        icon: Icons.flight_takeoff_rounded,
        label: 'Trips',
        route: AppConstants.routeAdminTrips),
    DrawerNavItem(
        icon: Icons.inventory_2_rounded,
        label: 'Packages',
        route: AppConstants.routeAdminPackages),
    DrawerNavItem(
        icon: Icons.payments_rounded,
        label: 'Payments',
        route: AppConstants.routeAdminPayments),
    DrawerNavItem(
        icon: Icons.gavel_rounded,
        label: 'Disputes',
        route: AppConstants.routeAdminDisputes),
    DrawerNavItem(
        icon: Icons.support_agent_rounded,
        label: 'Support',
        route: AppConstants.routeAdminSupport),
    DrawerNavItem(
        icon: Icons.percent_rounded,
        label: 'Fees',
        route: AppConstants.routeAdminFees),
    DrawerNavItem(
        icon: Icons.settings_rounded,
        label: 'Settings',
        route: AppConstants.routeAdminSettings),
  ];

  const AdminScaffold(
      {super.key,
      required this.title,
      required this.body,
      required this.currentIndex});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(AppColors.error),
                borderRadius: BorderRadius.circular(6)),
            child: const Text('ADMIN',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
          ),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Color(AppColors.textPrimary))),
        ]),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(AppColors.textPrimary)),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                await ref.read(authProvider.notifier).signOut();
                if (context.mounted) context.go(AppConstants.routeAuth);
              },
              tooltip: 'Sign out'),
        ],
      ),
      drawer: AppDrawer(
        items: _navItems,
        currentIndex: currentIndex,
        onItemSelected: (i) {
          context.go(_routes[i]);
        },
        userName: 'Admin',
        userRole: 'Admin',
      ),
      body: body,
    );
  }
}

// ── Admin Dashboard ───────────────────────────────────────────────────────────

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _stats = [];
  List<Map<String, dynamic>> _recentDeliveries = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
    // Stopgap: this only fires when an admin happens to have the dashboard
    // open. It does NOT catch overdue deliveries in real time — see the
    // pg_cron + Edge Function note in supabase_migration.sql for the
    // durable fix that runs regardless of whether anyone's looking.
    NotificationService().checkAndReportExpiredDeliveries();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final results = await Future.wait([
        _svc.fetchAdminStats(),
        _svc.fetchAllDeliveries(),
      ]).timeout(const Duration(seconds: 15));

      final stats = results[0] as Map<String, int>;
      final deliveries = results[1] as List<Map<String, dynamic>>;

      if (mounted) {
        setState(() {
          _stats = stats.entries
              .map((e) => {'label': e.key, 'value': e.value})
              .toList();
          _recentDeliveries = deliveries.take(5).toList();
          _errorMessage = null;
          _loading = false;
        });
      }
    } on TimeoutException catch (e, st) {
      debugPrint('AdminDashboardScreen load timeout: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Loading the admin dashboard timed out. Please try again.';
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint('AdminDashboardScreen load error: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage =
              'Unable to load admin dashboard. Please refresh or check your connection.';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(authProvider).profile;
    return AdminScaffold(
      title: 'Dashboard',
      currentIndex: 0,
      body: _loading
          ? const LoadingSpinner()
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 64, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text(_errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _errorMessage = null;
                            });
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(16), children: [
                    Text(
                        'Welcome, ${profile?.fullName.split(' ').first ?? 'Admin'}',
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const Text('Platform overview',
                        style:
                            TextStyle(color: Color(AppColors.textSecondary))),
                    const SizedBox(height: 20),

                    // Stats grid
                    GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.5,
                      children: _stats
                          .map((s) => StatCard(
                              label: s['label'] as String,
                              value: '${s['value']}',
                              icon: _statIcon(s['label'] as String)))
                          .toList(),
                    ),
                    const SizedBox(height: 20),

                    // Quick links
                    AppCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Quick Actions',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          Wrap(spacing: 10, runSpacing: 10, children: [
                            _chip('Review KYC', Icons.verified_user_rounded,
                                () => context.go(AppConstants.routeAdminKyc)),
                            _chip(
                                'View Disputes',
                                Icons.gavel_rounded,
                                () => context
                                    .go(AppConstants.routeAdminDisputes)),
                            _chip('Manage Fees', Icons.percent_rounded,
                                () => context.go(AppConstants.routeAdminFees)),
                            _chip(
                                'Support Tickets',
                                Icons.support_agent_rounded,
                                () =>
                                    context.go(AppConstants.routeAdminSupport)),
                            _chip('All Trips', Icons.flight_rounded,
                                () => context.go(AppConstants.routeAdminTrips)),
                          ]),
                        ])),
                    const SizedBox(height: 20),

                    // Recent deliveries
                    SectionHeader(
                        title: 'Recent Deliveries',
                        actionLabel: 'View All',
                        onAction: () =>
                            context.go(AppConstants.routeAdminPackages)),
                    const SizedBox(height: 12),
                    ..._recentDeliveries.map((d) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                              child: Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(
                                      (d['packages'] as Map?)?['title']
                                              as String? ??
                                          'Delivery',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text('ETB ${d['amount']}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color:
                                              Color(AppColors.textSecondary))),
                                ])),
                            StatusBadge(d['status'] as String? ?? ''),
                          ])),
                        )),
                  ]),
                ),
    );
  }

  IconData _statIcon(String label) => switch (label) {
        'Total Users' => Icons.people_rounded,
        'Total Packages' => Icons.inventory_2_rounded,
        'Total Deliveries' => Icons.local_shipping_rounded,
        'Pending KYCs' => Icons.verified_user_rounded,
        _ => Icons.bar_chart_rounded,
      };

  Widget _chip(String label, IconData icon, VoidCallback onTap) => ActionChip(
        avatar: Icon(icon, size: 16, color: const Color(AppColors.primary)),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        onPressed: onTap,
        backgroundColor: const Color(AppColors.primaryLight),
      );
}

// ── Admin Users ───────────────────────────────────────────────────────────────

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  Set<String> _blockedIds = {};
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final users = await _svc.fetchAllUsers();
      final settings = await _svc.fetchSystemSettings();
      if (mounted) {
        setState(() {
          _users = users;
          _filtered = users;
          _blockedIds =
              Set<String>.from((settings['blocked_users'] as List?) ?? const []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load users: $e')));
      }
    }
  }

  void _filter() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() => _filtered = q.isEmpty
        ? _users
        : _users
            .where((u) =>
                (u['full_name'] as String? ?? '').toLowerCase().contains(q) ||
                (u['email'] as String? ?? '').toLowerCase().contains(q))
            .toList());
  }

  Future<void> _toggleBlock(Map<String, dynamic> user) async {
    final uid = user['id'] as String;
    final isBlocked = _blockedIds.contains(uid);
    final err =
        isBlocked ? await _svc.unblockUser(uid) : await _svc.blockUser(uid);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $err')));
      return;
    }
    setState(() {
      if (isBlocked) {
        _blockedIds.remove(uid);
      } else {
        _blockedIds.add(uid);
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isBlocked ? 'User unblocked' : 'User blocked')));
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Users',
      currentIndex: 1,
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                  hintText: 'Search by name or email...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(AppColors.border))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: Color(AppColors.border)))),
            )),
        Expanded(
            child: _loading
                ? const LoadingSpinner()
                : _filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.people_outline_rounded,
                        title: 'No users found')
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filtered.length,
                        itemBuilder: (_, i) {
                          final u = _filtered[i];
                          final uid = u['id'] as String;
                          final isBlocked = _blockedIds.contains(uid);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                                child: Row(children: [
                              CircleAvatar(
                                  radius: 22,
                                  backgroundColor:
                                      const Color(AppColors.primaryLight),
                                  child: Text(
                                      ((u['full_name'] as String? ?? 'U')
                                                  .isEmpty
                                              ? 'U'
                                              : (u['full_name'] as String)[0])
                                          .toUpperCase(),
                                      style: const TextStyle(
                                          color: Color(AppColors.primary),
                                          fontWeight: FontWeight.bold))),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(u['full_name'] as String? ?? 'Unknown',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(u['email'] as String? ?? '',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(
                                                AppColors.textSecondary))),
                                    Row(children: [
                                      StatusBadge(
                                          u['role'] as String? ?? 'sender'),
                                      if (isBlocked) ...[
                                        const SizedBox(width: 6),
                                        const StatusBadge('blocked'),
                                      ],
                                    ]),
                                  ])),
                              PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'block') _toggleBlock(u);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'block',
                                      child: Text(isBlocked
                                          ? 'Unblock User'
                                          : 'Block User'))
                                ],
                              ),
                            ])),
                          );
                        },
                      )),
      ]),
    );
  }
}

// ── Admin KYC ─────────────────────────────────────────────────────────────────

class AdminKycScreen extends ConsumerStatefulWidget {
  const AdminKycScreen({super.key});
  @override
  ConsumerState<AdminKycScreen> createState() => _AdminKycScreenState();
}

class _AdminKycScreenState extends ConsumerState<AdminKycScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  String _filter = 'pending';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final docs = await _svc.fetchAllKycDocuments(
          status: _filter == 'all' ? null : _filter);
      if (mounted) {
        setState(() {
          _docs = docs;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load KYC documents: $e')));
      }
    }
  }

  Future<void> _updateStatus(String id, String status, String userId) async {
    final err = await _svc.updateKycStatus(id, status, userId);
    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to update KYC: $err')));
      }
      return;
    }

    await NotificationService().sendNotification(
      userId: userId,
      title: status == 'approved' ? '✅ Verification Approved' : '❌ Verification Rejected',
      body: status == 'approved'
          ? 'Your identity documents have been verified. You now have full access to the platform.'
          : 'Your identity documents were rejected. Please review and re-submit them.',
      type: 'kyc_$status',
    );

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('KYC $status')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'KYC Review',
      currentIndex: 2,
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in ['pending', 'approved', 'rejected', 'all'])
                    Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(f.toUpperCase()),
                          selected: _filter == f,
                          onSelected: (_) {
                            setState(() {
                              _filter = f;
                              _loading = true;
                            });
                            _load();
                          },
                          selectedColor: const Color(AppColors.primaryLight),
                          labelStyle: TextStyle(
                              color: _filter == f
                                  ? const Color(AppColors.primary)
                                  : null,
                              fontWeight: FontWeight.w600),
                        )),
                ]))),
        Expanded(
            child: _loading
                ? const LoadingSpinner()
                : _docs.isEmpty
                    ? EmptyState(
                        icon: Icons.verified_user_rounded,
                        title:
                            'No ${_filter == 'all' ? '' : _filter} KYC documents')
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _docs.length,
                        itemBuilder: (_, i) {
                          final doc = _docs[i];
                          final profile = doc['profiles'] as Map?;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    const Icon(Icons.article_rounded,
                                        color: Color(AppColors.primary)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              profile?['full_name']
                                                      as String? ??
                                                  'Unknown',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          Text(
                                              profile?['email'] as String? ??
                                                  '',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Color(AppColors
                                                      .textSecondary))),
                                        ])),
                                    StatusBadge(doc['status'] as String? ?? ''),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(
                                      'Doc type: ${doc['document_type'] ?? 'N/A'}',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color:
                                              Color(AppColors.textSecondary))),
                                  if (doc['notes'] != null)
                                    Text('Notes: ${doc['notes']}',
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(
                                                AppColors.textSecondary))),
                                  if (doc['status'] == 'pending') ...[
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      Expanded(
                                          child: ElevatedButton(
                                        onPressed: () => _updateStatus(
                                            doc['id'] as String, 'approved',
                                            doc['user_id'] as String),
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(AppColors.success),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8))),
                                        child: const Text('Approve'),
                                      )),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: OutlinedButton(
                                        onPressed: () => _updateStatus(
                                            doc['id'] as String, 'rejected',
                                            doc['user_id'] as String),
                                        style: OutlinedButton.styleFrom(
                                            foregroundColor:
                                                const Color(AppColors.error),
                                            side: const BorderSide(
                                                color: Color(AppColors.error)),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8))),
                                        child: const Text('Reject'),
                                      )),
                                    ]),
                                  ],
                                ])),
                          );
                        },
                      )),
      ]),
    );
  }
}

// ── Admin Packages ────────────────────────────────────────────────────────────

class AdminPackagesScreen extends ConsumerStatefulWidget {
  const AdminPackagesScreen({super.key});
  @override
  ConsumerState<AdminPackagesScreen> createState() =>
      _AdminPackagesScreenState();
}

class _AdminPackagesScreenState extends ConsumerState<AdminPackagesScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _deliveries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _svc.fetchAllDeliveries();
      if (mounted) {
        setState(() {
          _deliveries = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load packages: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Deliveries',
      currentIndex: 4,
      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: _deliveries.isEmpty
                  ? const EmptyState(
                      icon: Icons.inventory_2_rounded,
                      title: 'No deliveries yet')
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _deliveries.length,
                      itemBuilder: (_, i) {
                        final d = _deliveries[i];
                        final pkg = d['packages'] as Map?;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                              child: Row(children: [
                            const Icon(Icons.local_shipping_rounded,
                                color: Color(AppColors.primary)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(pkg?['title'] as String? ?? 'Delivery',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                      '${d['from_location']} → ${d['to_location']}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              Color(AppColors.textSecondary))),
                                  Text('ETB ${d['amount']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: Color(AppColors.primary))),
                                ])),
                            StatusBadge(d['status'] as String? ?? ''),
                          ])),
                        );
                      },
                    ),
            ),
    );
  }
}

// ── Admin Payments ────────────────────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════════════════════
// CHANGED: Added "Reject & Block" functionality for commission proof rejection
// ═══════════════════════════════════════════════════════════════════════════════

class AdminPaymentsScreen extends ConsumerStatefulWidget {
  const AdminPaymentsScreen({super.key});
  @override
  ConsumerState<AdminPaymentsScreen> createState() =>
      _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends ConsumerState<AdminPaymentsScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _svc.fetchAllPayments();
      if (mounted) {
        setState(() {
          _payments = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load payments: $e')));
      }
    }
  }

  Future<void> _markCommissionPaid(String deliveryId) async {
    String selectedMethod = kPaymentMethods.first.value;
    final refCtrl = TextEditingController();
    bool acknowledged = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Record payment without proof?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8)),
                child: const Text(
                    'The traveler hasn\'t submitted a payment screenshot for this delivery. Only use this if you\'ve verified the payment through another channel (e.g. a bank statement or a receipt shared outside the app).',
                    style:
                        TextStyle(fontSize: 12, color: Color(AppColors.error))),
              ),
              const SizedBox(height: 16),
              Text('Delivery #${deliveryId.substring(0, 8)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              const Text('Payment Method',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: selectedMethod,
                items: kPaymentMethods
                    .map((m) =>
                        DropdownMenuItem(value: m.value, child: Text(m.label)))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => selectedMethod = v ?? selectedMethod),
                decoration: const InputDecoration(
                    isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              const Text('Payment Reference (e.g. Telebirr Transaction ID)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              TextField(
                controller: refCtrl,
                decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'e.g. TB123456789'),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setDialogState(() => acknowledged = !acknowledged),
                child: Row(children: [
                  Checkbox(
                      value: acknowledged,
                      onChanged: (v) =>
                          setDialogState(() => acknowledged = v ?? false)),
                  const Expanded(
                    child: Text(
                        'I\'ve personally verified this payment through another channel',
                        style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed:
                    acknowledged ? () => Navigator.pop(dialogCtx, true) : null,
                child: const Text('Confirm')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    await _svc.markCommissionPaid(deliveryId,
        paymentMethod: selectedMethod,
        paymentReference:
            refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commission marked as received')));
    _load();
  }

  Future<void> _approveProof(Map<String, dynamic> d) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve this payment proof?'),
        content: const Text(
            'This marks the commission as paid. Make sure the screenshot actually shows the right amount before approving.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve')),
        ],
      ),
    );
    if (confirmed != true) return;

    final err = await _svc.approveCommissionProof(d['id'] as String);
    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $err')));
      return;
    }
    final travelerId = d['traveler_id'] as String?;
    if (travelerId != null) {
      await NotificationService().sendNotification(
        userId: travelerId,
        title: 'Payment proof approved',
        body: 'Your commission payment was confirmed. Thanks!',
        type: 'commission_approved',
      );
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Proof approved')));
    _load();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NEW: Reject proof with option to also block the traveler
  // ═══════════════════════════════════════════════════════════════════════════
  Future<void> _rejectProof(Map<String, dynamic> d) async {
    final reasonCtrl = TextEditingController();
    bool shouldBlock = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          title: const Text('Reject this payment proof?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'The traveler will be asked to resubmit. Let them know why:'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'e.g. Amount doesn\'t match, screenshot unclear'),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              // NEW: Block traveler checkbox
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: InkWell(
                  onTap: () => setDialogState(() => shouldBlock = !shouldBlock),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: shouldBlock,
                        onChanged: (v) =>
                            setDialogState(() => shouldBlock = v ?? false),
                        activeColor: const Color(AppColors.error),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BLOCK this traveler',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(AppColors.error),
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'If checked, this traveler\'s account will be permanently blocked. They will only see a support contact screen when they log in. Use this for fraud or repeated fake submissions.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(AppColors.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(dialogCtx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor:
                        shouldBlock ? const Color(AppColors.error) : null),
                child: Text(shouldBlock ? 'Reject & Block' : 'Reject')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final reason = reasonCtrl.text.trim().isEmpty
        ? 'No reason given — please contact support'
        : reasonCtrl.text.trim();

    final String? err;
    final travelerId = d['traveler_id'] as String?;

    if (shouldBlock && travelerId != null) {
      // NEW: Use the combined reject + block method
      err = await _svc.rejectCommissionProofAndBlock(
        d['id'] as String,
        travelerId,
        reason,
      );
    } else {
      // Original reject only
      err = await _svc.rejectCommissionProof(d['id'] as String, reason);
      // Send notification for regular reject
      if (err == null && travelerId != null) {
        await NotificationService().sendNotification(
          userId: travelerId,
          title: 'Payment proof rejected',
          body: 'Reason: $reason. Please resubmit your payment proof.',
          type: 'commission_rejected',
        );
      }
    }

    if (!mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $err')));
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(shouldBlock
            ? 'Proof rejected and traveler blocked'
            : 'Proof rejected'),
        backgroundColor: shouldBlock ? const Color(AppColors.error) : null,
      ),
    );
    _load();
  }

  void _viewProof(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: InteractiveViewer(child: Image.network(url)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalVolume = _payments.fold<double>(
        0, (s, d) => s + ((d['amount'] as num?)?.toDouble() ?? 0));
    final commissionDue =
        _payments.where((d) => d['payment_status'] == 'commission_due').length;

    return AdminScaffold(
      title: 'Payments',
      currentIndex: 5,
      body: _loading
          ? const LoadingSpinner()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(
                      child: AppCard(
                          color: const Color(AppColors.primaryLight),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total Volume',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(AppColors.textSecondary))),
                                Text('ETB ${totalVolume.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(AppColors.primary))),
                              ]))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: AppCard(
                          color: const Color(0xFFFFFBEB),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Commission Due',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(AppColors.textSecondary))),
                                Text('$commissionDue',
                                    style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFD97706))),
                              ]))),
                ]),
                const SizedBox(height: 20),
                ..._payments.map((d) {
                  final pkg = d['packages'] as Map?;
                  final isDue = d['payment_status'] == 'commission_due';
                  final hasDispute = d['has_open_dispute'] == true;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: AppCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Expanded(
                                child: Text(
                                    pkg?['title'] as String? ?? 'Delivery',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                            StatusBadge(
                                d['payment_status'] as String? ?? 'pending'),
                          ]),
                          const SizedBox(height: 6),
                          Row(children: [
                            Text('ETB ${d['amount']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                    color: Color(AppColors.primary))),
                            const SizedBox(width: 10),
                            StatusBadge(d['status'] as String? ?? ''),
                          ]),
                          if (hasDispute) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Row(children: [
                                Icon(Icons.pause_circle_outline_rounded,
                                    size: 16, color: Color(0xFF92400E)),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      'Open dispute on this delivery — resolve it first before touching payment.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF92400E),
                                          fontWeight: FontWeight.w600)),
                                ),
                              ]),
                            ),
                          ] else if (isDue) ...[
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(8)),
                              child: const Text(
                                  'Awaiting payment proof from the traveler — nothing to review yet.',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(AppColors.textSecondary))),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () =>
                                    _markCommissionPaid(d['id'] as String),
                                child: const Text(
                                    'Record manually (no proof) ⚠',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Color(AppColors.textSecondary),
                                        decoration: TextDecoration.underline)),
                              ),
                            ),
                          ],
                          if (!hasDispute &&
                              d['payment_status'] ==
                                  'commission_proof_submitted') ...[
                            const SizedBox(height: 10),
                            if (d['commission_proof_url'] != null)
                              GestureDetector(
                                onTap: () => _viewProof(
                                    d['commission_proof_url'] as String),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                      d['commission_proof_url'] as String,
                                      height: 140,
                                      width: double.infinity,
                                      fit: BoxFit.cover),
                                ),
                              ),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(
                                  child: ElevatedButton(
                                      onPressed: () => _approveProof(d),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(AppColors.success),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8))),
                                      child: const Text('Approve'))),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: OutlinedButton(
                                      onPressed: () => _rejectProof(d),
                                      style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              const Color(AppColors.error),
                                          side: const BorderSide(
                                              color: Color(AppColors.error)),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8))),
                                      child: const Text('Reject'))),
                            ]),
                          ],
                        ])),
                  );
                }),
              ]),
            ),
    );
  }
}

// ── Admin Fees ────────────────────────────────────────────────────────────────

class AdminFeesScreen extends ConsumerStatefulWidget {
  const AdminFeesScreen({super.key});
  @override
  ConsumerState<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

class _AdminFeesScreenState extends ConsumerState<AdminFeesScreen> {
  final _svc = DataService();
  final Map<String, TextEditingController> _controllers = {};
  List<Map<String, dynamic>> _settings = [];
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _svc.fetchPlatformSettings();
      if (mounted) {
        final feeSettings = settings
            .where((s) =>
                (s['setting_key'] as String).contains('fee') ||
                (s['setting_key'] as String).contains('rate') ||
                (s['setting_key'] as String).contains('commission'))
            .toList();
        for (final s in feeSettings) {
          _controllers[s['setting_key'] as String] =
              TextEditingController(text: s['setting_value'] as String? ?? '');
        }
        setState(() {
          _settings = feeSettings;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load fee settings: $e')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    for (final entry in _controllers.entries) {
      await _svc.upsertSetting(entry.key, entry.value.text.trim());
    }
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Fee settings saved!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Fee Management',
      currentIndex: 8,
      body: _loading
          ? const LoadingSpinner()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_settings.isEmpty)
                  const AppCard(
                      child: Column(children: [
                    Text('No fee settings found in platform_settings table.',
                        style:
                            TextStyle(color: Color(AppColors.textSecondary))),
                    SizedBox(height: 12),
                    Text(
                        'Add entries with keys like "platform_fee_rate", "commission_rate" to configure fees.',
                        style: TextStyle(
                            fontSize: 13,
                            color: Color(AppColors.textSecondary))),
                  ]))
                else ...[
                  const Text('Platform Fee Configuration',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  ..._settings.map((s) {
                    final key = s['setting_key'] as String;
                    return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: _controllers[key],
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText: key.replaceAll('_', ' ').toUpperCase(),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 14)),
                        ));
                  }),
                  const SizedBox(height: 8),
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
                        label: const Text('Save Fee Settings',
                            style: TextStyle(fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(AppColors.primary),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                      )),
                ],
              ],
            ),
    );
  }
}

// ── Admin Disputes ────────────────────────────────────────────────────────────

class AdminDisputesScreen extends ConsumerStatefulWidget {
  const AdminDisputesScreen({super.key});
  @override
  ConsumerState<AdminDisputesScreen> createState() =>
      _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends ConsumerState<AdminDisputesScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _disputes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _svc.fetchAllDisputes();
      if (mounted) {
        setState(() {
          _disputes = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(String disputeId, String resolution,
      Map<String, dynamic>? delivery) async {
    final err = await _svc.resolveDispute(disputeId, resolution);
    if (err != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to resolve dispute: $err')));
      }
      return;
    }

    final senderId = delivery?['sender_id'] as String?;
    final travelerId = delivery?['traveler_id'] as String?;

    if (resolution == 'refund_sender' && travelerId != null) {
      // Flag the traveler's record with a platform penalty — admin ruled
      // against them on this dispute.
      await _svc.flagTravelerPenalty(travelerId,
          reason: 'Dispute resolved: refund issued to sender');
    }

    // Notify both parties about the outcome, regardless of which way it
    // went, so no one is left wondering.
    final resolutionLabel = resolution == 'refund_sender'
        ? 'refunded to the sender'
        : 'released to the traveler';
    if (senderId != null) {
      await NotificationService().sendNotification(
        userId: senderId,
        title: '⚖️ Dispute Resolved',
        body:
            'Your dispute has been reviewed. Outcome: payment $resolutionLabel.',
        type: 'dispute_resolved',
      );
    }
    if (travelerId != null) {
      await NotificationService().sendNotification(
        userId: travelerId,
        title: '⚖️ Dispute Resolved',
        body: resolution == 'refund_sender'
            ? 'A dispute on one of your deliveries was resolved in the sender\'s favor. A platform penalty has been noted on your account.'
            : 'A dispute on one of your deliveries was resolved in your favor — payment has been released.',
        type: 'dispute_resolved',
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Dispute resolved')));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Disputes',
      currentIndex: 6,
      body: _loading
          ? const LoadingSpinner()
          : _disputes.isEmpty
              ? const EmptyState(
                  icon: Icons.gavel_rounded,
                  title: 'No disputes',
                  subtitle: 'When users raise disputes they appear here')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _disputes.length,
                  itemBuilder: (_, i) {
                    final d = _disputes[i];
                    final delivery = d['deliveries'] as Map<String, dynamic>?;
                    final isOpen = d['status'] == 'open';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AppCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              const Icon(Icons.warning_amber_rounded,
                                  color: Color(0xFFD97706)),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      d['reason'] as String? ?? 'Dispute',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold))),
                              StatusBadge(d['status'] as String? ?? 'open'),
                            ]),
                            const SizedBox(height: 8),
                            if (delivery != null)
                              Text(
                                  'Delivery: ${delivery['from_location']} → ${delivery['to_location']}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(AppColors.textSecondary))),
                            Text('Amount: ETB ${delivery?['amount'] ?? 'N/A'}',
                                style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(AppColors.textSecondary))),
                            if (d['description'] != null) ...[
                              const SizedBox(height: 6),
                              Text(d['description'] as String,
                                  style: const TextStyle(fontSize: 13)),
                            ],
                            if (isOpen) ...[
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(
                                    child: ElevatedButton(
                                  onPressed: () => _resolve(d['id'] as String,
                                      'refund_sender', delivery),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(AppColors.primary),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                  child: const Text('Refund Sender'),
                                )),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: OutlinedButton(
                                  onPressed: () => _resolve(d['id'] as String,
                                      'release_to_traveler', delivery),
                                  style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                  child: const Text('Release to Traveler'),
                                )),
                              ]),
                            ],
                          ])),
                    );
                  },
                ),
    );
  }
}

// ── Admin Support ─────────────────────────────────────────────────────────────

class AdminSupportScreen extends ConsumerStatefulWidget {
  const AdminSupportScreen({super.key});
  @override
  ConsumerState<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends ConsumerState<AdminSupportScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _tickets = [];
  bool _loading = true;
  Map<String, dynamic>? _selected;
  final _responseCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _responseCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final tickets = await _svc.fetchAllSupportTickets();
      if (mounted) {
        setState(() {
          _tickets = tickets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load support tickets: $e')));
      }
    }
  }

  Future<void> _respond(String ticketId, String newStatus) async {
    if (_responseCtrl.text.trim().isEmpty) return;
    try {
      final err = await _svc.respondToSupportTicket(
          ticketId, newStatus, _responseCtrl.text.trim());
      if (mounted) {
        if (err == null) {
          setState(() => _selected = null);
          _responseCtrl.clear();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Response sent!')));
          _load();
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $err')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Support Tickets',
      currentIndex: 7,
      body: _loading
          ? const LoadingSpinner()
          : _tickets.isEmpty
              ? const EmptyState(
                  icon: Icons.support_agent_rounded,
                  title: 'No support tickets')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tickets.length,
                  itemBuilder: (_, i) {
                    final t = _tickets[i];
                    final profile = t['profiles'] as Map?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                          onTap: () => setState(() => _selected = t),
                          child: Row(children: [
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(t['subject'] as String? ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  Text(
                                      profile?['full_name'] as String? ??
                                          profile?['email'] as String? ??
                                          'Unknown user',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              Color(AppColors.textSecondary))),
                                  Text(t['description'] as String? ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color:
                                              Color(AppColors.textSecondary))),
                                ])),
                            const SizedBox(width: 8),
                            Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  StatusBadge(t['status'] as String? ?? 'open'),
                                  const SizedBox(height: 4),
                                  StatusBadge(
                                      t['priority'] as String? ?? 'medium'),
                                ]),
                          ])),
                    );
                  },
                ),
    );
  }
}

class _ResponseSheet extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;

  const _ResponseSheet(
      {required this.ticket,
      required this.controller,
      required this.onSend,
      required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black12)]),
      padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
              child: Text(ticket['subject'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
        ]),
        Text(ticket['description'] as String? ?? '',
            style: const TextStyle(
                color: Color(AppColors.textSecondary), fontSize: 13),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
        const Divider(height: 20),
        Expanded(
            child: TextField(
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                    hintText: 'Write your response...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: const Color(AppColors.surface)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: ElevatedButton(
                  onPressed: () => onSend('in_progress'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(AppColors.primary),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  child: const Text('Reply'))),
          const SizedBox(width: 10),
          Expanded(
              child: OutlinedButton(
                  onPressed: () => onSend('resolved'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(AppColors.success),
                      side: const BorderSide(color: Color(AppColors.success)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  child: const Text('Resolve'))),
        ]),
      ]),
    );
  }
}

// ── Admin Trips ───────────────────────────────────────────────────────────────

class AdminTripsScreen extends ConsumerStatefulWidget {
  const AdminTripsScreen({super.key});
  @override
  ConsumerState<AdminTripsScreen> createState() => _AdminTripsScreenState();
}

class _AdminTripsScreenState extends ConsumerState<AdminTripsScreen> {
  final _svc = DataService();
  List<Map<String, dynamic>> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await _svc.fetchAllAdminTrips();
      if (mounted) {
        setState(() {
          _trips = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load trips: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'All Trips',
      currentIndex: 3,
      body: _loading
          ? const LoadingSpinner()
          : _trips.isEmpty
              ? const EmptyState(
                  icon: Icons.flight_rounded, title: 'No trips yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trips.length,
                  itemBuilder: (_, i) {
                    final t = _trips[i];
                    final p = t['profiles'] as Map?;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: AppCard(
                          child: Row(children: [
                        const Icon(Icons.flight_rounded,
                            color: Color(AppColors.primary)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('${t['from_area']} → ${t['to_area']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              Text(
                                  p?['nickname'] ??
                                      p?['full_name'] ??
                                      'Unknown traveler',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(AppColors.textSecondary))),
                              if (t['travel_date'] != null)
                                Text('Date: ${t['travel_date']}',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(AppColors.textSecondary))),
                            ])),
                        StatusBadge(t['status'] as String? ?? 'active'),
                      ])),
                    );
                  },
                ),
    );
  }
}

// ── Admin Settings ────────────────────────────────────────────────────────────

class AdminSettingsScreen extends ConsumerStatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  ConsumerState<AdminSettingsScreen> createState() =>
      _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends ConsumerState<AdminSettingsScreen> {
  final _svc = DataService();

  final _telebirrCtrl = TextEditingController();
  final _cbeCtrl = TextEditingController();
  final _awashCtrl = TextEditingController();
  final _commissionCtrl = TextEditingController();
  final _newBlockedUserCtrl = TextEditingController();

  List<String> _blockedUsers = [];
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _telebirrCtrl.dispose();
    _cbeCtrl.dispose();
    _awashCtrl.dispose();
    _commissionCtrl.dispose();
    _newBlockedUserCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _svc.fetchSystemSettings();
      if (mounted) {
        _telebirrCtrl.text = s['escrow_telebirr'] as String? ?? '';
        _cbeCtrl.text = s['escrow_cbe'] as String? ?? '';
        _awashCtrl.text = s['escrow_awash'] as String? ?? '';
        final rate = s['commission_rate'];
        _commissionCtrl.text = rate == null ? '' : rate.toString();
        setState(() {
          _blockedUsers =
              List<String>.from((s['blocked_users'] as List?) ?? const []);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to load settings: $e')));
      }
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final err = await _svc.saveSystemSettings(
      escrowTelebirr: _telebirrCtrl.text.trim(),
      escrowCbe: _cbeCtrl.text.trim(),
      escrowAwash: _awashCtrl.text.trim(),
      commissionRate: double.tryParse(_commissionCtrl.text.trim()) ?? 0,
      blockedUsers: _blockedUsers,
    );
    if (mounted) {
      setState(() => _saving = false);
      if (err != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to save: $err')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Settings updated successfully!'),
          backgroundColor: Color(0xFF2E7D32),
        ));
      }
    }
  }

  void _addBlockedUser() {
    final id = _newBlockedUserCtrl.text.trim();
    if (id.isEmpty) return;
    if (_blockedUsers.contains(id)) {
      _newBlockedUserCtrl.clear();
      return;
    }
    setState(() {
      _blockedUsers.add(id);
      _newBlockedUserCtrl.clear();
    });
  }

  void _removeBlockedUser(String id) {
    setState(() => _blockedUsers.remove(id));
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboard, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminScaffold(
      title: 'Platform Settings',
      currentIndex: 9,
      body: _loading
          ? const LoadingSpinner()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Escrow Accounts',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _field(_telebirrCtrl, 'Telebirr Escrow Account'),
                _field(_cbeCtrl, 'CBE Escrow Account'),
                _field(_awashCtrl, 'Awash Escrow Account'),
                const SizedBox(height: 8),
                const Text('Commission',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _field(_commissionCtrl, 'Commission Rate (%)',
                    keyboard:
                        const TextInputType.numberWithOptions(decimal: true),
                    hint: 'e.g. 10'),
                const SizedBox(height: 8),
                const Text('Blocked Users',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text(
                  'Users blocked from the platform. Changes take effect once you press Save Settings below.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                if (_blockedUsers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No users are currently blocked.',
                        style: TextStyle(fontSize: 13, color: Colors.black45)),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _blockedUsers.map((id) {
                      return Chip(
                        avatar: const Icon(Icons.block_rounded,
                            size: 16, color: Color(0xFFB71C1C)),
                        label: Text(id, style: const TextStyle(fontSize: 12)),
                        backgroundColor: const Color(0xFFFDECEA),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () => _removeBlockedUser(id),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _newBlockedUserCtrl,
                        decoration: InputDecoration(
                          labelText: 'Add User ID to block',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        onFieldSubmitted: (_) => _addBlockedUser(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _addBlockedUser,
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(
                          backgroundColor: const Color(AppColors.primary),
                          foregroundColor: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
                      label: const Text('Save Settings',
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
}