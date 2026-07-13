// lib/widgets/common/shared_widgets.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';
import '../../providers/auth_provider.dart';
import '../../services/data_service.dart';
import '../../models/models.dart';

// ── Status Badge ──────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final String status;
  const StatusBadge(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status.toLowerCase()) {
      'approved' ||
      'delivered' ||
      'completed' ||
      'resolved' ||
      'released' ||
      'commission_paid' =>
        (const Color(AppColors.success), const Color(AppColors.successLight)),
      'pending' || 'open' || 'commission_due' => (
          const Color(0xFFD97706),
          const Color(0xFFFFFBEB)
        ),
      'in_transit' || 'in_progress' || 'accepted' || 'active' => (
          const Color(AppColors.primary),
          const Color(AppColors.primaryLight)
        ),
      'paused' => (
          const Color(AppColors.textSecondary),
          const Color(AppColors.surface)
        ),
      'cancelled' || 'rejected' || 'closed' || 'blocked' => (
          const Color(AppColors.error),
          const Color(0xFFFEF2F2)
        ),
      'matched' => (const Color(0xFF7C3AED), const Color(0xFFF5F3FF)),
      _ => (
          const Color(AppColors.textSecondary),
          const Color(AppColors.surface)
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

// ── Stat Card ─────────────────────────────────────────────────────────────────

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? iconColor;

  const StatCard(
      {super.key,
      required this.label,
      required this.value,
      required this.icon,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (iconColor ?? const Color(AppColors.primary))
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color: iconColor ?? const Color(AppColors.primary), size: 20),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(AppColors.textPrimary))),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.buttonLabel,
      this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 56,
                color: const Color(AppColors.textSecondary).withOpacity(0.4)),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(AppColors.textPrimary)),
                textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 14, color: Color(AppColors.textSecondary)),
                  textAlign: TextAlign.center),
            ],
            if (buttonLabel != null && onPressed != null) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(AppColors.primary),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: Text(buttonLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SectionHeader(
      {super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(AppColors.textPrimary))),
        if (actionLabel != null && onAction != null)
          TextButton(
              onPressed: onAction,
              child: Text(actionLabel!,
                  style: const TextStyle(color: Color(AppColors.primary)))),
      ],
    );
  }
}

// ── Info Banner ───────────────────────────────────────────────────────────────

class InfoBanner extends StatelessWidget {
  final String message;
  final Color? color;
  final IconData icon;
  final Widget? trailing;

  const InfoBanner(
      {super.key,
      required this.message,
      this.color,
      this.icon = Icons.info_outline,
      this.trailing});

  @override
  Widget build(BuildContext context) {
    final c = color ?? const Color(0xFFD97706);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: c.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.3))),
      child: Row(children: [
        Icon(icon, color: c, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(message,
                style: TextStyle(
                    color: c, fontSize: 13, fontWeight: FontWeight.w500))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

// ── Drawer Nav Item ───────────────────────────────────────────────────────────

class DrawerNavItem {
  final IconData icon;
  final String label;
  final String route;
  const DrawerNavItem(
      {required this.icon, required this.label, required this.route});
}

// ── App Drawer ────────────────────────────────────────────────────────────────
// Slides in from the left when hamburger is tapped — works on mobile

class AppDrawer extends ConsumerWidget {
  final List<DrawerNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onItemSelected;
  final String userName;
  final String userRole;
  // ── Sender/Traveler mode toggle ───────────────────────────────────────
  // When true, the role badge becomes tappable and calls onModeToggle
  // instead of just sitting there as a static label. Admin drawer never
  // sets this, so admin's badge stays exactly as before.
  final bool allowModeToggle;
  final VoidCallback? onModeToggle;

  const AppDrawer({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onItemSelected,
    required this.userName,
    required this.userRole,
    this.allowModeToggle = false,
    this.onModeToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
            topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User info header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(AppColors.primaryLight),
                border: Border(
                    bottom: BorderSide(
                        color:
                            const Color(AppColors.primary).withOpacity(0.15))),
              ),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(AppColors.primary),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(userName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(AppColors.textPrimary))),
                      const SizedBox(height: 3),
                      if (allowModeToggle && onModeToggle != null)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: onModeToggle,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: const Color(AppColors.primary),
                                  borderRadius: BorderRadius.circular(20)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(userRole.toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.swap_horiz_rounded,
                                      size: 13, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: const Color(AppColors.primary),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(userRole.toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ])),
              ]),
            ),

            // Nav items
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                itemCount: items.length,
                itemBuilder: (_, i) => _DrawerItem(
                  icon: items[i].icon,
                  label: items[i].label,
                  selected: i == currentIndex,
                  onTap: () {
                    Navigator.of(context).pop(); // close drawer
                    onItemSelected(i);
                  },
                ),
              ),
            ),

            // Logout button
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color:
                        const Color(AppColors.textSecondary).withOpacity(0.1),
                  ),
                ),
              ),
              child: _DrawerItem(
                icon: Icons.logout_rounded,
                label: 'Logout',
                selected: false,
                onTap: () async {
                  Navigator.of(context).pop(); // close drawer
                  await ref.read(authProvider.notifier).signOut();
                  if (context.mounted) {
                    context.go(AppConstants.routeAuth);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerItem(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color:
                selected ? const Color(AppColors.primary) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            Icon(icon,
                size: 21,
                color: selected
                    ? Colors.white
                    : const Color(AppColors.textSecondary)),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected
                    ? Colors.white
                    : const Color(AppColors.textSecondary),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Dashboard Scaffold (drawer nav for mobile) ────────────────────────────────

class DashboardScaffold extends ConsumerWidget {
  final String title;
  final Widget body;
  final List<DrawerNavItem> navItems;
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  final Widget? floatingActionButton;
  final String userName;
  final String userRole;
  final bool allowModeToggle;
  final VoidCallback? onModeToggle;

  const DashboardScaffold({
    super.key,
    required this.title,
    required this.body,
    required this.navItems,
    required this.currentIndex,
    required this.onTabChanged,
    this.floatingActionButton,
    this.userName = '',
    this.userRole = '',
    this.allowModeToggle = false,
    this.onModeToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Color(AppColors.textPrimary))),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: const IconThemeData(color: Color(AppColors.textPrimary)),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      drawer: AppDrawer(
        items: navItems,
        currentIndex: currentIndex,
        onItemSelected: onTabChanged,
        userName: userName,
        userRole: userRole,
        allowModeToggle: allowModeToggle,
        onModeToggle: onModeToggle,
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

// Keep BottomNavItem as alias so existing code doesn't break
typedef BottomNavItem = DrawerNavItem;

// ── Notification Bell ────────────────────────────────────────────────────────
// Shows an unread-count badge and, on tap, a dropdown list of the user's
// recent notifications (KYC approval/rejection, disputes, payouts, etc.).
// Backed by DataService.fetchNotifications / markNotificationRead, which
// already existed but had no UI reading from them until now.

class NotificationBell extends ConsumerStatefulWidget {
  const NotificationBell({super.key});
  @override
  ConsumerState<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends ConsumerState<NotificationBell> {
  final _svc = DataService();
  List<AppNotification> _items = [];
  bool _loading = false;
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _overlay?.remove();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _loading = true);
    try {
      final items = await _svc.fetchNotifications(user.id);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _unreadCount => _items.where((n) => !n.read).length;

  Future<void> _markRead(AppNotification n) async {
    if (n.read) return;
    await _svc.markNotificationRead(n.id);
    if (mounted) {
      setState(() {
        final i = _items.indexWhere((x) => x.id == n.id);
        if (i != -1) {
          _items[i] = AppNotification(
            id: n.id, userId: n.userId, title: n.title, body: n.body,
            read: true, createdAt: n.createdAt);
        }
      });
    }
  }

  void _toggleOverlay() {
    if (_overlay != null) {
      _closeOverlay();
      return;
    }
    _load();
    final overlay = Overlay.of(context);
    _overlay = OverlayEntry(builder: (_) => Stack(children: [
      // Tap-away scrim to close the panel
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _closeOverlay,
      )),
      CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 8),
        child: _panel(),
      ),
    ]));
    overlay.insert(_overlay!);
  }

  void _closeOverlay() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() {});
  }

  Widget _panel() {
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 320,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(AppColors.border)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(children: [
              const Text('Notifications',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              if (_loading)
                const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: _items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('No notifications yet',
                        style: TextStyle(
                            color: const Color(AppColors.textSecondary),
                            fontSize: 13)))
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      return InkWell(
                        onTap: () => _markRead(n),
                        child: Container(
                          color: n.read ? Colors.white : const Color(AppColors.primaryLight).withOpacity(0.35),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (!n.read)
                              Container(
                                margin: const EdgeInsets.only(top: 5, right: 8),
                                width: 8, height: 8,
                                decoration: const BoxDecoration(
                                    color: Color(AppColors.primary), shape: BoxShape.circle),
                              ),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(n.title ?? '',
                                    style: TextStyle(
                                        fontWeight: n.read ? FontWeight.w500 : FontWeight.bold,
                                        fontSize: 13)),
                                const SizedBox(height: 3),
                                Text(n.body ?? '',
                                    style: const TextStyle(
                                        fontSize: 12, color: Color(AppColors.textSecondary))),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: _toggleOverlay,
        icon: Stack(clipBehavior: Clip.none, children: [
          const Icon(Icons.notifications_rounded),
          if (_unreadCount > 0)
            Positioned(
              right: -2, top: -2,
              child: Container(
                padding: const EdgeInsets.all(3),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(
                    color: Color(AppColors.error), shape: BoxShape.circle),
                child: Text(_unreadCount > 9 ? '9+' : '$_unreadCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Loading Spinner ───────────────────────────────────────────────────────────

class LoadingSpinner extends StatelessWidget {
  const LoadingSpinner({super.key});
  @override
  Widget build(BuildContext context) => const Center(
      child: Padding(
          padding: EdgeInsets.all(48), child: CircularProgressIndicator()));
}

// ── App Card ──────────────────────────────────────────────────────────────────

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final Color? color;
  final VoidCallback? onTap;

  const AppCard(
      {super.key, required this.child, this.padding, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: child,
    );
    if (onTap != null) return GestureDetector(onTap: onTap, child: card);
    return card;
  }
}

// ── KYC Warning Banner ────────────────────────────────────────────────────────

class KycWarningBanner extends StatelessWidget {
  final bool isPending;
  final VoidCallback? onVerifyNow;

  const KycWarningBanner({super.key, this.isPending = false, this.onVerifyNow});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded,
            color: Color(0xFFD97706), size: 26),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isPending ? 'Verification In Progress' : 'Verification Required',
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF92400E))),
          Text(
              isPending
                  ? 'Your documents are under review.'
                  : 'Complete KYC to access full features.',
              style: const TextStyle(fontSize: 12, color: Color(0xFF92400E))),
        ])),
        if (!isPending && onVerifyNow != null)
          TextButton(
              onPressed: onVerifyNow,
              child: const Text('Verify',
                  style: TextStyle(color: Color(AppColors.primary)))),
      ]),
    );
  }
}