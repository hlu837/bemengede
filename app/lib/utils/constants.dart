// lib/utils/constants.dart

class AppConstants {
  // ── Supabase ──────────────────────────────────────────────────────────────
  static const supabaseUrl = 'https://hpuddzhekgtdxjwuuuph.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhwdWRkemhla2d0ZHhqd3V1dXBoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0NDE5NjgsImV4cCI6MjA4MDAxNzk2OH0.T1FY3FV_wvHUNGhtGBjLVe9rDDkU3igm6EAQgDEnc1Q';
  static const backendUrl = 'https://packlink-sigma.vercel.app';

  // ── Admin ─────────────────────────────────────────────────────────────────
  static const designatedAdminEmail = 'picklink237@gmail.com';

  // ── Routes ────────────────────────────────────────────────────────────────
  static const routeRoot = '/';
  static const routeLanding = '/landing';
  static const routeAuth = '/auth';
  static const routeTerms = '/terms';
  static const routeBlocked = '/blocked';

  static const routeSender = '/sender';
  static const routeSenderPackages = '/sender/packages';
  // routeSenderTravelers, routeSenderRequests, routeSenderOffers, and
  // routeSenderTracking all retired — Find Commuters/Requests removed in
  // favor of instant matching (sender posts → traveler searches → instant
  // delivery), folded into routeSenderPackages (My Packages tabs + Package
  // Detail screen).
  static const routeSenderKyc = '/sender/kyc';
  static const routeSenderHistory = '/sender/history';

  static const routeSenderSettings = '/sender/settings';
  static const routeSenderSupport = '/sender/support';
  static const routeSenderCreate = '/sender/create';

  static const routeTraveler = '/traveler';
  // routeTravelerTrips and routeTravelerRequests retired along with
  // Find Commuters — see note above.
  static const routeTravelerPackages = '/traveler/packages';
  static const routeTravelerOffers = '/traveler/offers';
  static const routeTravelerCommission = '/traveler/commission';
  static const routeTravelerKyc = '/traveler/kyc';
  static const routeTravelerHistory = '/traveler/history';
  static const routeTravelerSettings = '/traveler/settings';

  static const routeAdmin = '/admin';
  static const routeAdminUsers = '/admin/users';
  static const routeAdminKyc = '/admin/kyc';
  static const routeAdminTrips = '/admin/trips';
  static const routeAdminPackages = '/admin/packages';
  static const routeAdminPayments = '/admin/payments';
  static const routeAdminFees = '/admin/fees';
  static const routeAdminSettings = '/admin/settings';
  static const routeAdminDisputes = '/admin/disputes';
  static const routeAdminSupport = '/admin/support';
}

class AppColors {
  static const primary = 0xFF3CBE3F;
  static const primaryLight = 0xFFEBF7EB;
  static const background = 0xFFFFFFFF;
  static const surface = 0xFFF8FAFC;
  static const border = 0xFFE2E8F0;
  static const textPrimary = 0xFF0F172A;
  static const textSecondary = 0xFF64748B;
  static const error = 0xFFEF4444;
  static const success = 0xFF22C55E;
  static const successLight = 0xFFF0FDF4;
}
