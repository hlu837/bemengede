// lib/services/auth_service.dart
// Uses real Supabase auth + backend at https://packlink-sigma.vercel.app

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../utils/constants.dart';

class AuthResult {
  final String? error;
  const AuthResult({this.error});
  bool get isSuccess => error == null;
}

class AuthService {
  final _sb      = Supabase.instance.client;
  final _backend = AppConstants.backendUrl;  // https://packlink-sigma.vercel.app

  // ── Current Session ───────────────────────────────────────────────────────

  User?    get currentUser    => _sb.auth.currentUser;
  Session? get currentSession => _sb.auth.currentSession;
  Stream<AuthState> get authStateChanges => _sb.auth.onAuthStateChange;

  // ── Profile ───────────────────────────────────────────────────────────────

  Future<UserProfile?> fetchProfile(String userId) async {
    try {
      final data = await _sb.from('profiles').select().eq('id', userId).maybeSingle();
      return data == null ? null : UserProfile.fromMap(data);
    } catch (_) { return null; }
  }

  Future<bool> isUserBlocked(String userId) async {
    try {
      // system_settings is a single-row table with a blocked_users TEXT[]
      // column — not a key/value table — and regular users can't SELECT it
      // directly under RLS anyway. is_user_blocked() is the SECURITY DEFINER
      // function made for exactly this check (see supabase_system_settings.sql).
      final blocked = await _sb
          .rpc('is_user_blocked', params: {'check_user_id': userId});
      return blocked as bool? ?? false;
    } catch (_) { return false; }
  }

  // ── Sign Up ───────────────────────────────────────────────────────────────

  Future<AuthResult> signUp({
    required String email,
    required String password,
    required String fullName,
    required UserRole role,
  }) async {
    final nickname = fullName.split(' ').first;
    final response = await _sb.auth.signUp(
      email: email.trim(),
      password: password,
      data: {
        'full_name': fullName,
        'nickname':  nickname,
        'role':      role.value,
      },
    );

    if (response.user == null) return const AuthResult(error: 'Could not create account');
    if (response.session != null) await _sb.auth.signOut();

    // Send OTP via backend
    try {
      final res = await http.post(
        Uri.parse('$_backend/api/verify/send-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim(), 'purpose': 'verification'}),
      );
      if (res.statusCode != 200) {
        return const AuthResult(error: 'Account created but failed to send verification email');
      }
    } catch (_) {
      return const AuthResult(error: 'Account created but verification email failed');
    }
    return const AuthResult();
  }

  // ── Verify OTP ────────────────────────────────────────────────────────────

  Future<AuthResult> verifyOtp({required String email, required String otp}) async {
    try {
      final res = await http.post(
        Uri.parse('$_backend/api/verify/check-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim(), 'otp': otp.trim(), 'purpose': 'verification'}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        return AuthResult(error: data['error'] as String? ?? 'Invalid verification code');
      }
      return const AuthResult();
    } catch (_) { return const AuthResult(error: 'Failed to verify code'); }
  }

  // ── Sign In ───────────────────────────────────────────────────────────────

  Future<AuthResult> signIn({required String email, required String password, UserRole? role}) async {
    try {
      final response = await _sb.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      if (response.user == null) return const AuthResult(error: 'Invalid credentials');

      // Optionally update role
      if (role != null) {
        await _sb.from('profiles').update({'role': role.value}).eq('id', response.user!.id);
      }
      return const AuthResult();
    } on AuthException catch (e) {
      return AuthResult(error: e.message);
    } catch (e) {
      return AuthResult(error: e.toString());
    }
  }

  // ── Sign Out ──────────────────────────────────────────────────────────────

  Future<void> signOut() async => await _sb.auth.signOut();

  // ── Forgot Password ───────────────────────────────────────────────────────

  Future<AuthResult> forgotPassword(String email) async {
    try {
      final res = await http.post(
        Uri.parse('$_backend/api/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email.trim()}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['success'] != true) {
        return AuthResult(error: data['error'] as String? ?? 'Failed to send reset email');
      }
      return const AuthResult();
    } catch (_) { return const AuthResult(error: 'Reset email failed (server unavailable)'); }
  }

  // ── Reset Password ────────────────────────────────────────────────────────

  Future<AuthResult> resetPassword({required String token, required String newPassword}) async {
    try {
      final res = await http.post(
        Uri.parse('$_backend/api/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token, 'password': newPassword}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200 || data['success'] != true) {
        return AuthResult(error: data['error'] as String? ?? 'Failed to reset password');
      }
      return const AuthResult();
    } catch (_) { return const AuthResult(error: 'Password reset failed'); }
  }

  Future<AuthResult> updatePassword(String newPassword) async {
    try {
      await _sb.auth.updateUser(UserAttributes(password: newPassword));
      return const AuthResult();
    } on AuthException catch (e) { return AuthResult(error: e.message); }
  }

  // ── Switch Role ───────────────────────────────────────────────────────────

  Future<AuthResult> switchRole(String userId, UserRole newRole) async {
    try {
      await _sb.from('profiles').update({'role': newRole.value}).eq('id', userId);
      return const AuthResult();
    } catch (e) { return AuthResult(error: e.toString()); }
  }
}
