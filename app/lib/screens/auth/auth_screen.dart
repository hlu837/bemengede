// lib/screens/auth/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/user_profile.dart';
import '../../providers/auth_provider.dart';
import '../../utils/constants.dart';
import 'widgets/role_selector.dart';
import 'widgets/auth_text_field.dart';
import 'widgets/auth_success_card.dart';

enum AuthMode { login, signup, verify, forgot, reset }

class AuthScreen extends ConsumerStatefulWidget {
  final String? initialMode;
  const AuthScreen({super.key, this.initialMode});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  late AuthMode _mode;
  UserRole _selectedRole = UserRole.sender;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _showPassword = false;
  bool _agreedToTerms = false;
  bool _resetSent = false;
  bool _passwordUpdated = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _mode = switch (widget.initialMode) {
      'signup' => AuthMode.signup,
      'forgot' => AuthMode.forgot,
      'reset' => AuthMode.reset,
      _ => AuthMode.login,
    };
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _fullNameCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  // ── Titles ─────────────────────────────────────────────────────────────────

  String get _title => switch (_mode) {
        AuthMode.signup => 'Create Account',
        AuthMode.verify => 'Verify Your Email',
        AuthMode.forgot => 'Reset Password',
        AuthMode.reset => 'Set New Password',
        _ => 'Welcome Back',
      };

  String get _subtitle => switch (_mode) {
        AuthMode.signup => 'Join Bemengede today',
        AuthMode.verify => 'Enter the verification code sent to your email',
        AuthMode.forgot => "Enter your email and we'll send you a reset link",
        AuthMode.reset => 'Enter your new password',
        _ => 'Sign in to your account',
      };

  // ── Submit ─────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final auth = ref.read(authProvider.notifier);
    String? error;

    switch (_mode) {
      case AuthMode.login:
        error = await auth.signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          role: _selectedRole,
        );
        if (error == null && mounted) {
          await auth.refreshProfile();
          _navigateAfterLogin(selectedRole: _selectedRole);
        }
        break;

      case AuthMode.signup:
        error = await auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text,
          fullName: _fullNameCtrl.text.trim(),
          role: _selectedRole,
        );
        if (error == null) {
          setState(() => _mode = AuthMode.verify);
          _showSnack('Verification code sent! Check your email.');
        }
        break;

      case AuthMode.verify:
        error = await auth.verifyOtp(
          email: _emailCtrl.text.trim(),
          otp: _otpCtrl.text.trim(),
        );
        if (error == null) {
          setState(() => _mode = AuthMode.login);
          _showSnack('Email verified! You can now sign in.');
        }
        break;

      case AuthMode.forgot:
        error = await auth.forgotPassword(_emailCtrl.text.trim());
        if (error == null) setState(() => _resetSent = true);
        break;

      case AuthMode.reset:
        if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
          setState(() {
            _loading = false;
            _errorMessage = "Passwords don't match";
          });
          return;
        }
        error = await auth.updatePassword(_passwordCtrl.text);
        if (error == null) setState(() => _passwordUpdated = true);
        break;
    }

    if (mounted) {
      setState(() {
        _loading = false;
        _errorMessage = error;
      });
    }
  }

  void _navigateAfterLogin({required UserRole selectedRole}) {
    final state = ref.read(authProvider);
    if (state.isAdmin) {
      context.go(AppConstants.routeAdmin);
      return;
    }

    if (selectedRole == UserRole.traveler) {
      context.go(AppConstants.routeTraveler);
      return;
    }

    if (state.profile?.role == UserRole.traveler) {
      context.go(AppConstants.routeTraveler);
    } else {
      context.go(AppConstants.routeSender);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button
                  TextButton.icon(
                    onPressed: () => context.go(AppConstants.routeRoot),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back to Home'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const SizedBox(height: 28),
          _buildBody(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(AppColors.primary),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            (_mode == AuthMode.forgot || _mode == AuthMode.reset)
                ? Icons.key_rounded
                : Icons.inventory_2_rounded,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _title,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    // Success states
    if (_mode == AuthMode.reset && _passwordUpdated) {
      return AuthSuccessCard(
        icon: Icons.key_rounded,
        title: 'Password Updated!',
        message: 'Your password has been changed. You can now sign in.',
        buttonLabel: 'Sign In',
        onPressed: () => setState(() {
          _mode = AuthMode.login;
          _passwordUpdated = false;
        }),
      );
    }
    if (_mode == AuthMode.forgot && _resetSent) {
      return AuthSuccessCard(
        icon: Icons.mail_rounded,
        title: 'Check your email',
        message: 'We sent a password reset link to ${_emailCtrl.text}',
        buttonLabel: 'Back to Sign In',
        onPressed: () => setState(() {
          _mode = AuthMode.login;
          _resetSent = false;
        }),
        outlined: true,
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Role selector (login & signup)
          if (_mode == AuthMode.login || _mode == AuthMode.signup) ...[
            RoleSelector(
              selected: _selectedRole,
              label: _mode == AuthMode.login ? 'Sign in as:' : 'I want to:',
              onChanged: (r) => setState(() => _selectedRole = r),
            ),
            const SizedBox(height: 20),
          ],

          // Full name (signup only)
          if (_mode == AuthMode.signup) ...[
            AuthTextField(
              controller: _fullNameCtrl,
              label: 'Full Name',
              hint: 'Enter your full name',
              icon: Icons.person_outline_rounded,
              validator: (v) {
                if (v == null || v.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          // Email
          if (_mode != AuthMode.reset) ...[
            AuthTextField(
              controller: _emailCtrl,
              label: 'Email',
              hint: 'Enter your email',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              readOnly: _mode == AuthMode.verify,
              validator: (v) {
                if (v == null ||
                    !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                  return 'Invalid email address';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          // OTP field (verify only)
          if (_mode == AuthMode.verify) ...[
            AuthTextField(
              controller: _otpCtrl,
              label: 'Verification Code',
              hint: 'Enter the 6-digit code',
              icon: Icons.pin_outlined,
              keyboardType: TextInputType.number,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Code is required' : null,
            ),
            const SizedBox(height: 16),
          ],

          // Password
          if (_mode != AuthMode.forgot && _mode != AuthMode.verify) ...[
            AuthTextField(
              controller: _passwordCtrl,
              label: _mode == AuthMode.reset ? 'New Password' : 'Password',
              hint: _mode == AuthMode.reset
                  ? 'Enter new password'
                  : 'Enter your password',
              icon: Icons.lock_outline_rounded,
              obscureText: !_showPassword,
              suffixIcon: IconButton(
                icon: Icon(_showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              validator: (v) {
                if (v == null || v.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
          ],

          // Confirm password (reset only)
          if (_mode == AuthMode.reset) ...[
            const SizedBox(height: 8),
            AuthTextField(
              controller: _confirmPasswordCtrl,
              label: 'Confirm Password',
              hint: 'Confirm your new password',
              icon: Icons.lock_outline_rounded,
              obscureText: !_showPassword,
              suffixIcon: IconButton(
                icon: Icon(_showPassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
              validator: (v) {
                if (v != _passwordCtrl.text) return "Passwords don't match";
                return null;
              },
            ),
            const SizedBox(height: 8),
          ],

          // Forgot password link
          if (_mode == AuthMode.login) ...[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _mode = AuthMode.forgot),
                child: const Text('Forgot password?'),
              ),
            ),
          ],

          // Terms checkbox (signup)
          if (_mode == AuthMode.signup) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                  activeColor: const Color(AppColors.primary),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: GestureDetector(
                      onTap: () => context.go(AppConstants.routeTerms),
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(AppColors.textSecondary)),
                          children: [
                            TextSpan(text: 'I agree to the '),
                            TextSpan(
                              text: 'Terms and Conditions',
                              style: TextStyle(
                                color: Color(AppColors.primary),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Error message
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(
                    color: Color(AppColors.error), fontSize: 13),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Submit button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed:
                  (_loading || (_mode == AuthMode.signup && !_agreedToTerms))
                      ? null
                      : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(AppColors.primary),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor:
                    const Color(AppColors.primary).withOpacity(0.5),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      switch (_mode) {
                        AuthMode.login => 'Sign In',
                        AuthMode.signup => 'Create Account',
                        AuthMode.verify => 'Verify Email',
                        AuthMode.forgot => 'Send Reset Link',
                        AuthMode.reset => 'Update Password',
                      },
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
            ),
          ),

          const SizedBox(height: 20),

          // Toggle mode links
          _buildModeToggle(),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    if (_mode == AuthMode.forgot || _mode == AuthMode.reset) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Remember your password?',
              style: TextStyle(color: Color(AppColors.textSecondary))),
          TextButton(
            onPressed: () => setState(() => _mode = AuthMode.login),
            child: const Text('Sign In',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(AppColors.primary))),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _mode == AuthMode.login
              ? "Don't have an account?"
              : 'Already have an account?',
          style: const TextStyle(color: Color(AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => setState(() => _mode =
              _mode == AuthMode.login ? AuthMode.signup : AuthMode.login),
          child: Text(
            _mode == AuthMode.login ? 'Sign Up' : 'Sign In',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: Color(AppColors.primary)),
          ),
        ),
      ],
    );
  }
}
