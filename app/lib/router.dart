// lib/router.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/auth_provider.dart' as ap;
import 'screens/landing/index.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/sender/sender_dashboard_screen.dart';
import 'screens/sender/sender_packages_screen.dart';
import 'screens/sender/sender_misc_screens.dart';
import 'screens/traveler/traveler_screens.dart';
import 'screens/traveler/traveler_kyc_screen.dart';
import 'screens/admin/admin_screens.dart';
import 'screens/shared/blocked_account_screen.dart';
import 'utils/constants.dart';

// ── Terms Screen ──────────────────────────────────────────────────────────────

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Terms & Conditions',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionTitle('1. Acceptance of Terms'),
            _SectionText(
              'By accessing and using Bemengede, you accept and agree to be bound by the terms and provision of this agreement.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('2. Use License'),
            _SectionText(
              'Permission is granted to temporarily download one copy of the materials (information or software) on Bemengede for personal, non-commercial transitory viewing only.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('3. Disclaimer'),
            _SectionText(
              'The materials on Bemengede are provided on an \'as is\' basis. Bemengede makes no warranties, expressed or implied, and hereby disclaims and negates all other warranties including, without limitation, implied warranties or conditions of merchantability, fitness for a particular purpose, or non-infringement of intellectual property or other violation of rights.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('4. Limitations'),
            _SectionText(
              'In no event shall Bemengede or its suppliers be liable for any damages (including, without limitation, damages for loss of data or profit, or due to business interruption) arising out of the use or inability to use the materials on Bemengede.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('5. Accuracy of Materials'),
            _SectionText(
              'The materials appearing on Bemengede could include technical, typographical, or photographic errors. Bemengede does not warrant that any of the materials on its website are accurate, complete, or current. Bemengede may make changes to the materials contained on its website at any time without notice.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('6. Links'),
            _SectionText(
              'Bemengede has not reviewed all of the sites linked to its website and is not responsible for the contents of any such linked site. The inclusion of any link does not imply endorsement by Bemengede of the site. Use of any such linked website is at the user\'s own risk.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('7. Modifications'),
            _SectionText(
              'Bemengede may revise these terms of service for its website at any time without notice. By using this website, you are agreeing to be bound by the then current version of these terms of service.',
            ),
            const SizedBox(height: 24),
            _SectionTitle('8. Governing Law'),
            _SectionText(
              'These terms and conditions are governed by and construed in accordance with the laws of Ethiopia, and you irrevocably submit to the exclusive jurisdiction of the courts in that location.',
            ),
            const SizedBox(height: 32),
            Center(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => context.go(AppConstants.routeAuth),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A9E2D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Sign In',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }
}

class _SectionText extends StatelessWidget {
  final String text;
  const _SectionText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        color: Colors.black54,
        height: 1.6,
      ),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(ap.authProvider);

  return GoRouter(
    // Start at landing page for all users; redirect will handle authentication flow
    initialLocation: AppConstants.routeLanding,
    redirect: (context, state) {
      if (authState.loading) return null;
      final authenticated = authState.isAuthenticated;
      final loc = state.matchedLocation;
      final publicRoutes = [
        AppConstants.routeRoot,
        AppConstants.routeLanding,
        AppConstants.routeAuth,
        AppConstants.routeTerms
      ];
      if (!authenticated && !publicRoutes.contains(loc)) {
        return AppConstants.routeAuth;
      }
      // Blocked accounts (e.g. commission-proof rejected by admin) get
      // locked to the support-only screen, no matter where they try to go.
      if (authenticated && authState.blocked) {
        return loc == AppConstants.routeBlocked
            ? null
            : AppConstants.routeBlocked;
      }
      if (authenticated && loc == AppConstants.routeBlocked) {
        // No longer blocked (or never was) — don't strand them here.
        if (authState.isAdmin) return AppConstants.routeAdmin;
        return authState.profile?.role.name == 'traveler'
            ? AppConstants.routeTraveler
            : AppConstants.routeSender;
      }
      if (authenticated &&
          (loc == AppConstants.routeAuth ||
              loc == AppConstants.routeRoot ||
              loc == AppConstants.routeLanding)) {
        if (authState.isAdmin) return AppConstants.routeAdmin;
        return authState.profile?.role.name == 'traveler'
            ? AppConstants.routeTraveler
            : AppConstants.routeSender;
      }
      return null;
    },
    routes: [
      // ── Public ──────────────────────────────────────────────────────────
      GoRoute(
          path: AppConstants.routeRoot,
          redirect: (_, __) => AppConstants.routeLanding),
      GoRoute(
          path: AppConstants.routeLanding,
          builder: (_, __) => const LandingPage()),
      GoRoute(
          path: AppConstants.routeAuth,
          builder: (_, state) =>
              AuthScreen(initialMode: state.uri.queryParameters['mode'])),
      GoRoute(
          path: AppConstants.routeTerms,
          builder: (_, __) => const TermsScreen()),
      GoRoute(
          path: AppConstants.routeBlocked,
          builder: (_, __) => const BlockedAccountScreen()),

      // ── Sender ───────────────────────────────────────────────────────────
      GoRoute(
          path: AppConstants.routeSender,
          builder: (_, __) => const SenderDashboardScreen()),
      GoRoute(
          path: AppConstants.routeSenderPackages,
          builder: (_, __) => const SenderPackagesScreen()),
      GoRoute(
          path: AppConstants.routeSenderHistory,
          builder: (_, __) => const SenderHistoryScreen()),
      GoRoute(
          path: AppConstants.routeSenderSettings,
          builder: (_, __) => const SenderSettingsScreen()),
      GoRoute(
          path: AppConstants.routeSenderKyc,
          builder: (_, __) => const SenderKycScreen()),
      GoRoute(
          path: AppConstants.routeSenderSupport,
          builder: (_, __) => const SenderSupportScreen()),
      GoRoute(
          path: AppConstants.routeSenderCreate,
          builder: (_, __) => const SenderPackagesScreen()),

      // ── Traveler ─────────────────────────────────────────────────────────
      GoRoute(
          path: AppConstants.routeTraveler,
          builder: (_, __) => const TravelerDashboardScreen()),
      GoRoute(
          path: AppConstants.routeTravelerPackages,
          builder: (_, __) => const TravelerPackagesScreen()),
      GoRoute(
          path: AppConstants.routeTravelerOffers,
          builder: (_, __) => const TravelerOffersScreen()),
      GoRoute(
          path: AppConstants.routeTravelerCommission,
          builder: (_, __) => const TravelerCommissionScreen()),
      GoRoute(
          path: AppConstants.routeTravelerHistory,
          builder: (_, __) => const TravelerHistoryScreen()),
      GoRoute(
          path: AppConstants.routeTravelerSettings,
          builder: (_, __) => const TravelerSettingsScreen()),
      GoRoute(
          path: AppConstants.routeTravelerKyc,
          builder: (_, __) => const TravelerKycScreen()),

      // ── Admin ────────────────────────────────────────────────────────────
      GoRoute(
          path: AppConstants.routeAdmin,
          builder: (_, __) => const AdminDashboardScreen()),
      GoRoute(
          path: AppConstants.routeAdminUsers,
          builder: (_, __) => const AdminUsersScreen()),
      GoRoute(
          path: AppConstants.routeAdminKyc,
          builder: (_, __) => const AdminKycScreen()),
      GoRoute(
          path: AppConstants.routeAdminPackages,
          builder: (_, __) => const AdminPackagesScreen()),
      GoRoute(
          path: AppConstants.routeAdminPayments,
          builder: (_, __) => const AdminPaymentsScreen()),
      GoRoute(
          path: AppConstants.routeAdminFees,
          builder: (_, __) => const AdminFeesScreen()),
      GoRoute(
          path: AppConstants.routeAdminDisputes,
          builder: (_, __) => const AdminDisputesScreen()),
      GoRoute(
          path: AppConstants.routeAdminSupport,
          builder: (_, __) => const AdminSupportScreen()),
      GoRoute(
          path: AppConstants.routeAdminTrips,
          builder: (_, __) => const AdminTripsScreen()),
      GoRoute(
          path: AppConstants.routeAdminSettings,
          builder: (_, __) => const AdminSettingsScreen()),
    ],
    errorBuilder: (_, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});
