// lib/providers/auth_provider.dart

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/location_tracking_service.dart';
import '../utils/constants.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

// ── Auth State ────────────────────────────────────────────────────────────────

class AuthState {
  final User? user;
  final UserProfile? profile;
  final bool loading;
  final bool blocked;
  // True only until the very first session/profile check (app boot) has
  // finished. Deliberately separate from `loading`, which also flips true
  // during ordinary sign-in/sign-up/etc button presses — main.dart uses
  // this one to show a one-time splash instead of the Landing Page while
  // GoRouter doesn't yet know where to send you, without hijacking the
  // whole screen on every later login attempt too.
  final bool initializing;

  const AuthState(
      {this.user,
      this.profile,
      this.loading = true,
      this.blocked = false,
      this.initializing = true});

  bool get isAuthenticated => user != null && profile != null;
  bool get isAdmin =>
      user?.email?.toLowerCase() ==
      AppConstants.designatedAdminEmail.toLowerCase();

  AuthState copyWith({
    User? user,
    UserProfile? profile,
    bool? loading,
    bool? blocked,
    bool? initializing,
    bool clearUser = false,
    bool clearProfile = false,
  }) =>
      AuthState(
        user: clearUser ? null : (user ?? this.user),
        profile: clearProfile ? null : (profile ?? this.profile),
        loading: loading ?? this.loading,
        blocked: blocked ?? this.blocked,
        initializing: initializing ?? this.initializing,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _svc;
  Timer? _blockCheckTimer;

  AuthNotifier(this._svc) : super(const AuthState()) {
    _init();
  }

  @override
  void dispose() {
    _blockCheckTimer?.cancel();
    super.dispose();
  }

  // Re-checks blocked status periodically while a user is signed in, so an
  // admin blocking someone takes effect during their active session instead
  // of only at their next login/app-launch/auth-state-change.
  void _startBlockPolling(String userId) {
    _blockCheckTimer?.cancel();
    _blockCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (!mounted) return;
      final blocked = await _svc.isUserBlocked(userId);
      if (mounted && blocked != state.blocked) {
        state = state.copyWith(blocked: blocked);
      }
    });
  }

  Future<void> _init() async {
    // Listen to Supabase session changes
    _svc.authStateChanges.listen((event) async {
      final user = event.session?.user;
      if (user != null) {
        final profile = await _svc.fetchProfile(user.id);
        final blocked = await _svc.isUserBlocked(user.id);
        if (mounted) {
          state = AuthState(
              user: user,
              profile: profile,
              loading: false,
              blocked: blocked,
              initializing: false);
          _startBlockPolling(user.id);
        }
      } else {
        _blockCheckTimer?.cancel();
        if (mounted) {
          state = const AuthState(loading: false, initializing: false);
        }
      }
    });

    // Check existing session on app launch
    final user = _svc.currentSession?.user;
    if (user != null) {
      final profile = await _svc.fetchProfile(user.id);
      final blocked = await _svc.isUserBlocked(user.id);
      state = AuthState(
          user: user,
          profile: profile,
          loading: false,
          blocked: blocked,
          initializing: false);
      _startBlockPolling(user.id);
    } else {
      state = const AuthState(loading: false, initializing: false);
    }
  }

  Future<String?> signIn(
      {required String email, required String password, UserRole? role}) async {
    state = state.copyWith(loading: true);
    final result =
        await _svc.signIn(email: email, password: password, role: role);
    if (result.isSuccess) {
      final user = _svc.currentSession?.user;
      if (user != null) {
        final profile = await _svc.fetchProfile(user.id);
        final blocked = await _svc.isUserBlocked(user.id);
        if (mounted) {
          state = AuthState(
              user: user,
              profile: profile,
              loading: false,
              blocked: blocked,
              initializing: false);
        }
      } else {
        state = state.copyWith(loading: false);
      }
    } else {
      state = state.copyWith(loading: false);
    }
    return result.error;
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
  }) async {
    state = state.copyWith(loading: true);
    final result = await _svc.signUp(
        email: email, password: password, fullName: fullName, role: role);
    state = state.copyWith(loading: false);
    return result.error;
  }

  Future<String?> verifyOtp(
      {required String email, required String otp}) async {
    state = state.copyWith(loading: true);
    final result = await _svc.verifyOtp(email: email, otp: otp);
    state = state.copyWith(loading: false);
    return result.error;
  }

  Future<String?> forgotPassword(String email) async =>
      (await _svc.forgotPassword(email)).error;
  Future<String?> updatePassword(String newPassword) async =>
      (await _svc.updatePassword(newPassword)).error;

  Future<void> signOut() async {
    // A traveler who signs out mid-"Live" shouldn't keep broadcasting
    // position/availability to senders indefinitely.
    if (LocationTrackingService().isOnline) {
      await LocationTrackingService().goOffline();
    }
    state = const AuthState(loading: false, initializing: false);
    try {
      await _svc.signOut();
    } catch (_) {
      // We still clear local auth state even if the backend sign-out fails.
    }
  }

  Future<String?> switchRole(UserRole newRole) async {
    if (state.user == null) return 'Not logged in';
    final result = await _svc.switchRole(state.user!.id, newRole);
    if (result.isSuccess && state.profile != null) {
      state = state.copyWith(profile: state.profile!.copyWith(role: newRole));
    }
    return result.error;
  }

  // Refresh profile after settings update
  Future<void> refreshProfile() async {
    if (state.user == null) return;
    final profile = await _svc.fetchProfile(state.user!.id);
    if (mounted && profile != null) state = state.copyWith(profile: profile);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(ref.read(authServiceProvider));
});
