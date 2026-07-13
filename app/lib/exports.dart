// lib/exports.dart
// Single import to access all screens, models, services, and widgets.

// Models
export 'models/user_profile.dart';
export 'models/models.dart';

// Services
export 'services/auth_service.dart';
export 'services/data_service.dart';

// Providers
export 'providers/auth_provider.dart';

// Shared widgets
export 'widgets/common/shared_widgets.dart';

// Auth
export 'screens/auth/auth_screen.dart';
export 'screens/auth/widgets/role_selector.dart';
export 'screens/auth/widgets/auth_text_field.dart';
export 'screens/auth/widgets/auth_success_card.dart';

// Sender
export 'screens/sender/sender_dashboard_screen.dart';
export 'screens/sender/sender_packages_screen.dart';
export 'screens/sender/browse_travelers_screen.dart';
export 'screens/sender/package_detail_screen.dart';
export 'screens/sender/sender_misc_screens.dart';

// Traveler
export 'screens/traveler/traveler_screens.dart';

// Shared
export 'screens/shared/blocked_account_screen.dart';

// Admin
export 'screens/admin/admin_screens.dart';

// Router + Utils
export 'router.dart';
export 'utils/constants.dart';
