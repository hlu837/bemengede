// lib/screens/shared/blocked_account_screen.dart
//
// Shown instead of the normal dashboard when AuthState.blocked is true
// (currently: a traveler whose commission-payment proof an admin rejected
// with "block account" checked). Deliberately has no drawer, no bottom
// nav, no way to reach any other in-app screen — just the reason, a way
// to contact support, and sign out. Wired in router.dart's redirect.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../services/data_service.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';

class BlockedAccountScreen extends ConsumerStatefulWidget {
  const BlockedAccountScreen({super.key});

  @override
  ConsumerState<BlockedAccountScreen> createState() =>
      _BlockedAccountScreenState();
}

class _BlockedAccountScreenState extends ConsumerState<BlockedAccountScreen> {
  final _svc = DataService();
  final _subjectCtrl =
      TextEditingController(text: 'My account was blocked');
  final _descCtrl = TextEditingController();
  String? _reason;
  bool _loadingReason = true;
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    _loadReason();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadReason() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final reason = await _svc.fetchBlockedReason(user.id);
    if (mounted) setState(() {
      _reason = reason;
      _loadingReason = false;
    });
  }

  Future<void> _sendTicket() async {
    final user = ref.read(authProvider).user;
    if (user == null || _descCtrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final err = await _svc.createSupportTicket(
      userId: user.id,
      subject: _subjectCtrl.text.trim().isEmpty
          ? 'My account was blocked'
          : _subjectCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      priority: 'high',
    );
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $err')));
      return;
    }
    setState(() => _sent = true);
    _descCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 24),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.block_rounded,
                    color: Color(AppColors.error), size: 36),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your account has been blocked',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'You no longer have access to Bemengede. If you think this is '
              'a mistake, contact support below.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(AppColors.textSecondary)),
            ),
            const SizedBox(height: 20),
            if (_loadingReason)
              const Center(child: LoadingSpinner())
            else if (_reason != null && _reason!.trim().isNotEmpty)
              AppCard(
                color: const Color(0xFFFEF2F2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Reason',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(AppColors.error))),
                    const SizedBox(height: 6),
                    Text(_reason!,
                        style: const TextStyle(
                            color: Color(AppColors.textPrimary))),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const AppCard(
              color: Color(0xFFEBF7EB),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ContactItem(
                      icon: Icons.email_rounded,
                      label: 'Email',
                      value: 'support@bemengede.com'),
                  _ContactItem(
                      icon: Icons.access_time_rounded,
                      label: 'Response',
                      value: '< 24h'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contact support',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  if (_sent)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(AppColors.successLight),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Row(children: [
                        Icon(Icons.check_circle_rounded,
                            color: Color(AppColors.success), size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                              'Message sent. Our team will get back to you.',
                              style: TextStyle(
                                  color: Color(AppColors.success),
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    )
                  else ...[
                    TextFormField(
                      controller: _subjectCtrl,
                      decoration: InputDecoration(
                        labelText: 'Subject',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Explain your situation',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        onPressed: _sending ? null : _sendTicket,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(AppColors.primary),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Send to support'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: () => ref.read(authProvider.notifier).signOut(),
                style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(AppColors.textSecondary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ContactItem(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF2A9E2D), size: 20),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Color(AppColors.textSecondary))),
        Text(value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
