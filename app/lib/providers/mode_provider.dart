// lib/providers/mode_provider.dart
//
// In-memory "which dashboard am I looking at" toggle. This is purely a
// frontend view switch — it does NOT change profiles.role in Supabase.
//
// IMPORTANT BACKEND CAVEAT: profiles.role in the DB is still a single value
// (sender | traveler | admin). This toggle lets a signed-in user *view* the
// other side's dashboard/nav without signing out, and every data call here
// is scoped by user.id (not by role), so read/browse screens work fine.
// But if your Supabase Row-Level-Security policies gate writes by
// profiles.role (e.g. "only travelers can insert into delivery_approvals"),
// a sender who toggles into Traveler mode will hit an RLS error on actions
// like accepting a package. If you want full dual-role support, either:
//   (a) relax the relevant RLS policies to check auth.uid() ownership
//       instead of role, or
//   (b) keep this toggle read-only/informational until you decide to
//       support one account holding both roles server-side.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_profile.dart';

/// Current dashboard mode being viewed. Defaults to the account's actual
/// `profiles.role` on login (set from AuthProvider when the profile loads).
final currentModeProvider = StateProvider<UserRole>((ref) => UserRole.sender);

extension UserRoleLabel on UserRole {
  String get displayLabel => switch (this) {
        UserRole.sender => 'SENDER',
        UserRole.traveler => 'TRAVELER',
        UserRole.admin => 'ADMIN',
      };
}
