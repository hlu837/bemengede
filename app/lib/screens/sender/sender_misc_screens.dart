// lib/screens/sender/sender_history_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/data_service.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';
import '../../widgets/common/dispute_dialog.dart';

class SenderHistoryScreen extends ConsumerStatefulWidget {
  const SenderHistoryScreen({super.key});
  @override
  ConsumerState<SenderHistoryScreen> createState() =>
      _SenderHistoryScreenState();
}

class _SenderHistoryScreenState extends ConsumerState<SenderHistoryScreen> {
  final _svc = DataService();
  List<DeliveryModel> _deliveries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // ═══════════════════════════════════════════════════════════════════
      // CHANGED: Also include 'delivered' status so sender can confirm payment
      // ═══════════════════════════════════════════════════════════════════
      final list = await _svc.fetchSenderDeliveries(user.id,
          statuses: ['completed', 'cancelled', 'delivered']);
      if (mounted)
        setState(() {
          _deliveries = list;
          _loading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _loading = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('History',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: _loading
          ? const LoadingSpinner()
          : _error != null
              ? _HistoryError(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _deliveries.isEmpty
                      ? const EmptyState(
                          icon: Icons.history_rounded,
                          title: 'No history yet',
                          subtitle:
                              'Your completed deliveries will appear here')
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _deliveries.length,
                          itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _HistoryCard(
                                  delivery: _deliveries[i], onRefresh: _load)),
                        ),
                ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _HistoryError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: Color(AppColors.error)),
          const SizedBox(height: 12),
          const Text('Couldn\'t load history',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _HistoryCard extends StatefulWidget {
  final DeliveryModel delivery;
  final VoidCallback onRefresh;
  const _HistoryCard({required this.delivery, required this.onRefresh});

  @override
  State<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends State<_HistoryCard> {
  bool _confirming = false;

  // ═══════════════════════════════════════════════════════════════════════
  // FIXED: the app only ever writes status = 'completed' when a delivery is
  // marked delivered (never 'delivered') — this checked the wrong string.
  // ═══════════════════════════════════════════════════════════════════════
  bool get _needsPaymentConfirmation {
    return widget.delivery.status == 'completed' &&
        (widget.delivery.paymentStatus == 'pending' ||
            widget.delivery.paymentStatus == null);
  }

  bool get _paymentConfirmed {
    return widget.delivery.paymentStatus == 'sender_confirmed' ||
        widget.delivery.paymentStatus == 'commission_proof_submitted' ||
        widget.delivery.paymentStatus == 'commission_paid';
  }

  Future<void> _confirmTravelerPaid() async {
    final svc = DataService();
    setState(() => _confirming = true);

    final err = await svc.confirmTravelerPaid(widget.delivery.id);

    if (mounted) {
      setState(() => _confirming = false);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $err'),
              backgroundColor: const Color(AppColors.error)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Payment confirmed! Traveler has been notified to pay commission.'),
            backgroundColor: Color(AppColors.success),
          ),
        );
        widget.onRefresh();
      }
    }
  }

  void _showConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.payments_rounded, color: Color(AppColors.primary)),
          SizedBox(width: 8),
          Text('Confirm Payment'),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Have you paid the traveler ETB ${widget.delivery.amount.toStringAsFixed(0)} for "${widget.delivery.packageTitle ?? 'this delivery'}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEBF7EB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xFF2A9E2D)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'After confirming, the traveler will be notified to pay the platform commission.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF2A9E2D)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not Yet'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmTravelerPaid();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppColors.primary),
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, I Paid'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cancelled = widget.delivery.isCancelled;
    final delivered = widget.delivery.status == 'completed';

    return AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
                color: cancelled
                    ? const Color(0xFFFEF2F2)
                    : delivered
                        ? const Color(0xFFEBF7EB)
                        : const Color(AppColors.successLight),
                shape: BoxShape.circle),
            child: Icon(
                cancelled
                    ? Icons.cancel_rounded
                    : delivered
                        ? Icons.local_shipping_rounded
                        : Icons.check_circle_rounded,
                color: cancelled
                    ? const Color(AppColors.error)
                    : delivered
                        ? const Color(0xFF2A9E2D)
                        : const Color(AppColors.success))),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.delivery.packageTitle ?? 'Package',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
              '${widget.delivery.fromLocation} → ${widget.delivery.toLocation}',
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
          if (widget.delivery.travelerName != null)
            Text('Traveler: ${widget.delivery.travelerName}',
                style: const TextStyle(
                    fontSize: 12, color: Color(AppColors.textSecondary))),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('ETB ${widget.delivery.amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          StatusBadge(widget.delivery.status),
          const SizedBox(height: 4),
          // ═══════════════════════════════════════════════════════════════
          // NEW: Show payment status badge for delivered items
          // ═══════════════════════════════════════════════════════════════
          if (delivered) ...[
            _PaymentStatusBadge(
                paymentStatus: widget.delivery.paymentStatus ?? 'pending'),
          ],
          Text(_fmtDate(widget.delivery.createdAt),
              style: const TextStyle(
                  fontSize: 11, color: Color(AppColors.textSecondary))),
        ]),
      ]),
      const Divider(height: 20),

      // ═══════════════════════════════════════════════════════════════════
      // NEW: Show "Traveler Paid" button or payment status message
      // ═══════════════════════════════════════════════════════════════════
      if (_needsPaymentConfirmation) ...[
        SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _confirming ? null : _showConfirmDialog,
            icon: _confirming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.payments_rounded, size: 18),
            label: Text(_confirming
                ? 'Confirming...'
                : 'Traveler Paid — ETB ${widget.delivery.amount.toStringAsFixed(0)}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(AppColors.primary),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap after you pay the traveler. The traveler will then pay the platform commission.',
          style: TextStyle(fontSize: 11, color: Color(AppColors.textSecondary)),
        ),
      ] else if (delivered && _paymentConfirmed) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEBF7EB),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(
              widget.delivery.paymentStatus == 'commission_paid'
                  ? Icons.check_circle_rounded
                  : Icons.hourglass_top_rounded,
              size: 18,
              color: widget.delivery.paymentStatus == 'commission_paid'
                  ? const Color(AppColors.success)
                  : const Color(0xFFD97706),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.delivery.paymentStatus == 'commission_paid'
                    ? 'Commission paid — all settled'
                    : 'Waiting for traveler to pay commission...',
                style: TextStyle(
                  fontSize: 12,
                  color: widget.delivery.paymentStatus == 'commission_paid'
                      ? const Color(AppColors.success)
                      : const Color(0xFFD97706),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ]),
        ),
      ] else ...[
        // Original report button for non-delivered items
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => showReportProblemDialog(context,
                deliveryId: widget.delivery.id,
                raisedByUserId: widget.delivery.senderId),
            icon: const Icon(Icons.warning_amber_rounded,
                size: 16, color: Color(AppColors.error)),
            label: const Text('Report a Problem',
                style: TextStyle(color: Color(AppColors.error), fontSize: 12)),
          ),
        ),
      ],
    ]));
  }

  String _fmtDate(String iso) {
    try {
      return DateTime.parse(iso).toLocal().toString().substring(0, 10);
    } catch (_) {
      return '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// NEW: Payment status badge widget
// ═══════════════════════════════════════════════════════════════════════════
class _PaymentStatusBadge extends StatelessWidget {
  final String paymentStatus;
  const _PaymentStatusBadge({required this.paymentStatus});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (paymentStatus) {
      'pending' => ('Payment Pending', const Color(0xFFD97706)),
      'sender_confirmed' => (
          'Awaiting Commission',
          const Color(AppColors.primary)
        ),
      'commission_due' => ('Commission Due', const Color(0xFFD97706)),
      'commission_proof_submitted' => (
          'Proof Submitted',
          const Color(AppColors.primary)
        ),
      'commission_paid' => ('All Paid', const Color(AppColors.success)),
      _ => ('Payment Pending', const Color(0xFFD97706)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// lib/screens/sender/sender_settings_screen.dart

class SenderSettingsScreen extends ConsumerStatefulWidget {
  const SenderSettingsScreen({super.key});
  @override
  ConsumerState<SenderSettingsScreen> createState() =>
      _SenderSettingsScreenState();
}

class _SenderSettingsScreenState extends ConsumerState<SenderSettingsScreen> {
  final _svc = DataService();
  final _fullNameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  String _email = '';
  String _preferredPayment = '';
  bool _loading = true, _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_fullNameCtrl, _nicknameCtrl, _phoneCtrl, _accountCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final data = await _svc.fetchProfileSettings(user.id);
    if (data != null && mounted) {
      _fullNameCtrl.text = data['full_name'] ?? '';
      _nicknameCtrl.text = data['nickname'] ?? '';
      _phoneCtrl.text = data['phone'] ?? '';
      _accountCtrl.text = data['payment_account'] ?? '';
      setState(() {
        _email = data['email'] ?? '';
        _preferredPayment = data['preferred_payment'] ?? '';
        _loading = false;
      });
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _saving = true);
    final err = await _svc.updateProfileSettings(user.id, {
      'full_name': _fullNameCtrl.text.trim(),
      'nickname':
          _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'preferred_payment': _preferredPayment.isEmpty ? null : _preferredPayment,
      'payment_account':
          _accountCtrl.text.trim().isEmpty ? null : _accountCtrl.text.trim(),
    });
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err ?? 'Settings saved!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('Settings',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: _loading
          ? const LoadingSpinner()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Row(children: [
                        Icon(Icons.person_outline_rounded,
                            color: Color(AppColors.primary)),
                        SizedBox(width: 8),
                        Text('Profile Info',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))
                      ]),
                      const SizedBox(height: 16),
                      _field(_fullNameCtrl, 'Full Name'),
                      const SizedBox(height: 12),
                      _field(_nicknameCtrl, 'Nickname (visible to travelers)'),
                      const SizedBox(height: 12),
                      TextFormField(
                          initialValue: _email,
                          enabled: false,
                          decoration: _dec('Email')),
                      const SizedBox(height: 12),
                      _field(_phoneCtrl, 'Phone'),
                    ])),
                const SizedBox(height: 16),
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Row(children: [
                        Icon(Icons.credit_card_rounded,
                            color: Color(AppColors.primary)),
                        SizedBox(width: 8),
                        Text('Payment Preference',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold))
                      ]),
                      const SizedBox(height: 4),
                      const Text('How you prefer to pay travelers',
                          style: TextStyle(
                              fontSize: 13,
                              color: Color(AppColors.textSecondary))),
                      const SizedBox(height: 16),
                      ...kPaymentMethods.map((m) => RadioListTile<String>(
                            value: m.value,
                            groupValue: _preferredPayment,
                            onChanged: (v) =>
                                setState(() => _preferredPayment = v ?? ''),
                            title: Text(m.label,
                                style: const TextStyle(fontSize: 14)),
                            activeColor: const Color(AppColors.primary),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                          )),
                      if (_preferredPayment.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _field(_accountCtrl,
                            '${kPaymentMethods.firstWhere((m) => m.value == _preferredPayment, orElse: () => const PaymentMethod(value: '', label: '', placeholder: '')).label} Account Number'),
                      ],
                    ])),
                const SizedBox(height: 20),
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
                      label: const Text('Save Changes',
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

  Widget _field(TextEditingController ctrl, String label) =>
      TextFormField(controller: ctrl, decoration: _dec(label));
  InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      filled: true,
      fillColor: Colors.white);
}

// ─────────────────────────────────────────────────────────────────────────────
// lib/screens/sender/sender_kyc_screen.dart

class SenderKycScreen extends ConsumerStatefulWidget {
  const SenderKycScreen({super.key});
  @override
  ConsumerState<SenderKycScreen> createState() => _SenderKycScreenState();
}

class _SenderKycScreenState extends ConsumerState<SenderKycScreen> {
  final _svc = DataService();
  final _picker = ImagePicker();

  // ── State ─────────────────────────────────────────────────────────────────
  KycStatus _status = KycStatus.notSubmitted;
  bool _loading = true;
  bool _submitting = false;
  int _step = 0; // 0=ID docs, 1=reference person, 2=support doc

  // Step 1 — ID Documents
  String _docType = 'passport';
  Uint8List? _docFile;
  Uint8List? _selfieFile;
  final _notesCtrl = TextEditingController();

  // Step 2 — Reference / Emergency Person
  final _refNameCtrl = TextEditingController();
  final _refPhoneCtrl = TextEditingController();
  final _refRelationCtrl = TextEditingController();
  final _refOccupationCtrl = TextEditingController();
  final _refEmployerCtrl = TextEditingController();
  final _refIdCtrl = TextEditingController();

  // Step 3 — Supporting Document from Employer/Gov
  String _supportDocType = 'employer_letter';
  Uint8List? _supportDocFile;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    for (final c in [
      _notesCtrl,
      _refNameCtrl,
      _refPhoneCtrl,
      _refRelationCtrl,
      _refOccupationCtrl,
      _refEmployerCtrl,
      _refIdCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final status = await _svc.fetchKycStatus(user.id);
    if (mounted)
      setState(() {
        _status = status;
        _loading = false;
      });
  }

  Future<void> _pickFile(bool isSelfie, {bool isSupportDoc = false}) async {
    final source = isSelfie ? ImageSource.camera : ImageSource.gallery;
    final picked = isSelfie || isSupportDoc
        ? await _picker.pickImage(source: source, imageQuality: 85)
        : await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    // Read as bytes instead of wrapping in dart:io's File — File has no web
    // implementation, so reading bytes via XFile keeps this working on
    // mobile, desktop, and web alike.
    final bytes = await picked.readAsBytes();
    setState(() {
      if (isSupportDoc) {
        _supportDocFile = bytes;
      } else if (isSelfie) {
        _selfieFile = bytes;
      } else {
        _docFile = bytes;
      }
    });
  }

  bool get _step1Valid => _docFile != null && _selfieFile != null;
  bool get _step2Valid =>
      _refNameCtrl.text.trim().length >= 2 &&
      _refPhoneCtrl.text.trim().length >= 9 &&
      _refRelationCtrl.text.trim().isNotEmpty &&
      _refEmployerCtrl.text.trim().isNotEmpty;
  bool get _step3Valid => _supportDocFile != null;

  // Human-readable reason the current step can't proceed yet, or null if
  // it's fine. Shown next to the Continue/Submit button so a disabled
  // button never looks like it's just silently broken.
  String? get _blockingReason {
    switch (_step) {
      case 0:
        if (_docFile == null && _selfieFile == null) {
          return 'Upload your ID document and a selfie to continue.';
        }
        if (_docFile == null) return 'Upload your ID document to continue.';
        if (_selfieFile == null) return 'Take a selfie to continue.';
        return null;
      case 1:
        if (_refNameCtrl.text.trim().length < 2) {
          return 'Enter the reference person\'s full name.';
        }
        if (_refPhoneCtrl.text.trim().length < 9) {
          return 'Enter a valid phone number (at least 9 digits).';
        }
        if (_refRelationCtrl.text.trim().isEmpty) {
          return 'Enter your relationship to this person.';
        }
        if (_refEmployerCtrl.text.trim().isEmpty) {
          return 'Enter their employer or organization.';
        }
        return null;
      default:
        if (_supportDocFile == null) {
          return 'Upload a supporting document to submit.';
        }
        return null;
    }
  }

  Future<void> _submit() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    setState(() => _submitting = true);

    try {
      // Upload ID document
      final docUrl = await _svc.uploadKycFile(user.id, _docFile!, 'id_doc');
      // Upload selfie
      final selfieUrl =
          await _svc.uploadKycFile(user.id, _selfieFile!, 'selfie');
      // Upload support doc
      String? supportUrl;
      if (_supportDocFile != null) {
        supportUrl =
            await _svc.uploadKycFile(user.id, _supportDocFile!, 'support_doc');
      }

      // Insert into kyc_documents with all new fields
      await _svc.submitKycFull(
        userId: user.id,
        documentType: _docType,
        documentUrl: docUrl,
        selfieUrl: selfieUrl,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        referenceFullName: _refNameCtrl.text.trim(),
        referencePhone: _refPhoneCtrl.text.trim(),
        referenceRelationship: _refRelationCtrl.text.trim(),
        referenceOccupation: _refOccupationCtrl.text.trim().isEmpty
            ? null
            : _refOccupationCtrl.text.trim(),
        referenceEmployer: _refEmployerCtrl.text.trim(),
        referenceIdNumber:
            _refIdCtrl.text.trim().isEmpty ? null : _refIdCtrl.text.trim(),
        supportDocUrl: supportUrl,
        supportDocType: _supportDocType,
      );

      if (mounted)
        setState(() {
          _status = KycStatus.pending;
          _submitting = false;
        });
      if (mounted) _showSnack('KYC submitted! Under review in 24–48 hours.');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (mounted)
        _showSnack('Submission failed: ${e.toString()}', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError
          ? const Color(AppColors.error)
          : const Color(AppColors.success),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
        title: const Text('Verification',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(AppColors.textPrimary)),
      ),
      body: _loading
          ? const LoadingSpinner()
          : _status == KycStatus.approved
              ? _approvedState()
              : _status == KycStatus.pending
                  ? _pendingState()
                  : _form(),
    );
  }

  // ── Status States ──────────────────────────────────────────────────────────

  Widget _approvedState() => Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                  color: Color(AppColors.successLight), shape: BoxShape.circle),
              child: const Icon(Icons.verified_user_rounded,
                  size: 44, color: Color(AppColors.success))),
          const SizedBox(height: 20),
          const Text('You are Verified!',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(AppColors.textPrimary))),
          const SizedBox(height: 8),
          const Text('You can now post packages and request deliveries.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(AppColors.textSecondary))),
        ]),
      ));

  Widget _pendingState() => Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                  color: Color(0xFFFFFBEB), shape: BoxShape.circle),
              child: const Icon(Icons.hourglass_empty_rounded,
                  size: 44, color: Color(0xFFD97706))),
          const SizedBox(height: 20),
          const Text('Under Review',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(AppColors.textPrimary))),
          const SizedBox(height: 8),
          const Text(
              'Your documents are being reviewed.\nThis usually takes 24–48 hours.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(AppColors.textSecondary))),
        ]),
      ));

  // ── Multi-Step Form ────────────────────────────────────────────────────────

  Widget _form() {
    return Column(children: [
      // Step indicator
      _StepIndicator(
          current: _step,
          steps: const ['ID Documents', 'Reference Person', 'Support Letter']),
      Expanded(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: switch (_step) {
            0 => _step1(),
            1 => _step2(),
            _ => _step3(),
          },
        ),
      )),
      // Bottom navigation
      Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(AppColors.border)))),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_submitting && _blockingReason != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 16, color: Color(0xFFB91C1C)),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(_blockingReason!,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFB91C1C)))),
                  ]),
                ),
              ],
              Row(children: [
                if (_step > 0) ...[
                  Expanded(
                      child: OutlinedButton(
                    onPressed: () => setState(() => _step--),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12))),
                    child: const Text('Back'),
                  )),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _canProceed() ? _onNext : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(AppColors.primary),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor:
                          const Color(AppColors.primary).withOpacity(0.4),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(_step == 2 ? 'Submit KYC' : 'Continue',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ]),
            ]),
      ),
    ]);
  }

  bool _canProceed() {
    if (_submitting) return false;
    return switch (_step) {
      0 => _step1Valid,
      1 => _step2Valid,
      _ => _step3Valid
    };
  }

  void _onNext() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  // ── Step 1: ID Documents ──────────────────────────────────────────────────

  Widget _step1() => Column(
          key: const ValueKey(0),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
                icon: Icons.badge_rounded,
                title: 'Government-Issued ID',
                subtitle: 'Upload a clear photo of your ID document'),
            const SizedBox(height: 14),

            // Doc type chips
            const Text('Document Type',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(AppColors.textPrimary))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final t in [
                ('passport', 'Passport'),
                ('national_id', 'National ID'),
                ('drivers_license', "Driver's License")
              ])
                ChoiceChip(
                  label: Text(t.$2),
                  selected: _docType == t.$1,
                  onSelected: (_) => setState(() => _docType = t.$1),
                  selectedColor: const Color(AppColors.primaryLight),
                  labelStyle: TextStyle(
                      color: _docType == t.$1
                          ? const Color(AppColors.primary)
                          : null,
                      fontWeight: FontWeight.w500),
                ),
            ]),
            const SizedBox(height: 16),

            // Upload ID doc
            _UploadBox(
                label: 'Upload ID Document',
                sublabel: 'JPG, PNG · Max 5MB',
                done: _docFile != null,
                icon: Icons.file_present_rounded,
                onTap: () => _pickFile(false)),
            const SizedBox(height: 12),

            // Upload selfie
            _UploadBox(
                label: 'Upload Selfie Holding ID',
                sublabel: 'Take a photo of yourself holding the document',
                done: _selfieFile != null,
                icon: Icons.camera_alt_rounded,
                onTap: () => _pickFile(true)),
            const SizedBox(height: 12),

            // Notes
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: _dec('Additional Notes (optional)',
                  'Any information that might help reviewers'),
            ),
          ]);

  // ── Step 2: Reference Person ──────────────────────────────────────────────

  Widget _step2() => Column(
          key: const ValueKey(1),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
                icon: Icons.people_rounded,
                title: 'Reference / Emergency Person',
                subtitle:
                    'Provide a contact who can verify your identity. Must be a government worker or company employee.'),
            const SizedBox(height: 14),
            const AppCard(
                color: Color(0xFFFFFBEB),
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded,
                      color: Color(0xFFD97706), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'This person will be contacted only in case of fraud investigation or disputes.',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF92400E)))),
                ])),
            const SizedBox(height: 14),
            _field(_refNameCtrl, 'Full Name *', 'e.g. Dr. Abebe Girma'),
            const SizedBox(height: 12),
            _field(_refPhoneCtrl, 'Phone Number *', '+251 9XX XXX XXXX',
                keyboard: TextInputType.phone),
            const SizedBox(height: 12),
            _field(_refRelationCtrl, 'Relationship to You *',
                'e.g. Employer, Supervisor, Colleague'),
            const SizedBox(height: 12),
            _field(_refOccupationCtrl, 'Their Occupation',
                'e.g. Government Officer, Manager'),
            const SizedBox(height: 12),
            _field(_refEmployerCtrl, 'Their Employer / Organization *',
                'e.g. Ministry of Transport, Ethio Telecom'),
            const SizedBox(height: 12),
            _field(_refIdCtrl, 'Their Government ID Number (optional)',
                'e.g. National ID or Employee ID'),
            const SizedBox(height: 12),
            const AppCard(
                color: Color(AppColors.primaryLight),
                padding: EdgeInsets.all(12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Why is this required?',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(AppColors.primary),
                              fontSize: 13)),
                      SizedBox(height: 6),
                      Text(
                          'Bemengede uses a reference system for accountability. Your reference person vouches for your identity and is used for fraud prevention only.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(AppColors.textSecondary))),
                    ])),
          ]);

  // ── Step 3: Supporting Document ───────────────────────────────────────────

  Widget _step3() => Column(
          key: const ValueKey(2),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle(
                icon: Icons.description_rounded,
                title: 'Supporting Document',
                subtitle:
                    'Upload a letter from your employer or a government institution confirming your identity.'),
            const SizedBox(height: 14),

            const Text('Document Type',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(AppColors.textPrimary))),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final t in [
                ('employer_letter', 'Employer Letter'),
                ('government_letter', 'Government Letter'),
                ('company_id', 'Company ID Card')
              ])
                ChoiceChip(
                  label: Text(t.$2),
                  selected: _supportDocType == t.$1,
                  onSelected: (_) => setState(() => _supportDocType = t.$1),
                  selectedColor: const Color(AppColors.primaryLight),
                  labelStyle: TextStyle(
                      color: _supportDocType == t.$1
                          ? const Color(AppColors.primary)
                          : null,
                      fontWeight: FontWeight.w500),
                ),
            ]),
            const SizedBox(height: 16),

            // What should the document contain
            AppCard(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Document must include:',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: Color(AppColors.textPrimary))),
                  const SizedBox(height: 10),
                  for (final item in [
                    'Your full name',
                    'Name and stamp of the organization',
                    'Date of issue (must be within 6 months)',
                    'Signature of the issuing authority',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        const Icon(Icons.check_circle_outline_rounded,
                            size: 16, color: Color(AppColors.success)),
                        const SizedBox(width: 8),
                        Text(item,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(AppColors.textPrimary))),
                      ]),
                    ),
                ])),
            const SizedBox(height: 14),

            _UploadBox(
              label: 'Upload Supporting Document',
              sublabel: 'JPG or PNG · Max 5MB',
              done: _supportDocFile != null,
              icon: Icons.upload_file_rounded,
              onTap: () => _pickFile(false, isSupportDoc: true),
            ),

            const SizedBox(height: 14),
            const AppCard(
                color: Color(AppColors.successLight),
                padding: EdgeInsets.all(12),
                child: Row(children: [
                  Icon(Icons.security_rounded,
                      color: Color(AppColors.success), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          'All documents are encrypted and only accessible by Bemengede reviewers.',
                          style: TextStyle(
                              fontSize: 12, color: Color(AppColors.success)))),
                ])),
          ]);

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _field(TextEditingController ctrl, String label, String hint,
          {TextInputType? keyboard}) =>
      TextFormField(
        controller: ctrl,
        keyboardType: keyboard,
        decoration: _dec(label, hint),
        onChanged: (_) => setState(() {}),
      );

  InputDecoration _dec(String label, String hint) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(
            color: Color(AppColors.textSecondary), fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(AppColors.border))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(AppColors.primary), width: 2)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );
}

// ── Step Indicator ────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int current;
  final List<String> steps;
  const _StepIndicator({required this.current, required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        for (int i = 0; i < steps.length; i++) ...[
          Expanded(
              child: Column(children: [
            Row(children: [
              if (i > 0)
                Expanded(
                    child: Container(
                        height: 2,
                        color: i <= current
                            ? const Color(AppColors.primary)
                            : const Color(AppColors.border))),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: i < current
                      ? const Color(AppColors.primary)
                      : i == current
                          ? const Color(AppColors.primary)
                          : const Color(AppColors.border),
                  shape: BoxShape.circle,
                ),
                child: Center(
                    child: i < current
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white)
                        : Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: i == current
                                    ? Colors.white
                                    : const Color(AppColors.textSecondary)))),
              ),
              if (i < steps.length - 1)
                Expanded(
                    child: Container(
                        height: 2,
                        color: i < current
                            ? const Color(AppColors.primary)
                            : const Color(AppColors.border))),
            ]),
            const SizedBox(height: 4),
            Text(steps[i],
                style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        i == current ? FontWeight.w600 : FontWeight.normal,
                    color: i == current
                        ? const Color(AppColors.primary)
                        : const Color(AppColors.textSecondary)),
                textAlign: TextAlign.center),
          ])),
        ],
      ]),
    );
  }
}

// ── Section Title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionTitle(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: const Color(AppColors.primaryLight),
              borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: const Color(AppColors.primary), size: 22)),
      const SizedBox(width: 12),
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(AppColors.textPrimary))),
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(
                fontSize: 12, color: Color(AppColors.textSecondary))),
      ])),
    ]);
  }
}

// ── Upload Box ────────────────────────────────────────────────────────────────

class _UploadBox extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool done;
  final IconData icon;
  final VoidCallback onTap;

  const _UploadBox(
      {required this.label,
      required this.sublabel,
      required this.done,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: done ? const Color(AppColors.successLight) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: done
                  ? const Color(AppColors.success)
                  : const Color(AppColors.border),
              width: done ? 2 : 1,
              style: BorderStyle.solid),
        ),
        child: Column(children: [
          Icon(done ? Icons.check_circle_rounded : icon,
              size: 40,
              color: done
                  ? const Color(AppColors.success)
                  : const Color(AppColors.textSecondary)),
          const SizedBox(height: 10),
          Text(done ? 'File selected ✓' : label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: done
                      ? const Color(AppColors.success)
                      : const Color(AppColors.textPrimary))),
          const SizedBox(height: 4),
          Text(done ? 'Tap to change' : sublabel,
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// lib/screens/sender/sender_support_screen.dart

class SenderSupportScreen extends ConsumerStatefulWidget {
  const SenderSupportScreen({super.key});
  @override
  ConsumerState<SenderSupportScreen> createState() =>
      _SenderSupportScreenState();
}

class _SenderSupportScreenState extends ConsumerState<SenderSupportScreen> {
  final _svc = DataService();
  List<SupportTicket> _tickets = [];
  bool _loading = true, _creating = false, _submitting = false;
  SupportTicket? _selected;
  final _subjectCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'medium';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final tickets = await _svc.fetchSupportTickets(user.id);
    if (mounted)
      setState(() {
        _tickets = tickets;
        _loading = false;
      });
  }

  Future<void> _submit() async {
    final user = ref.read(authProvider).user;
    if (user == null ||
        _subjectCtrl.text.trim().isEmpty ||
        _descCtrl.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    final err = await _svc.createSupportTicket(
        userId: user.id,
        subject: _subjectCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        priority: _priority);
    if (mounted) {
      setState(() {
        _submitting = false;
        if (err == null) {
          _creating = false;
          _subjectCtrl.clear();
          _descCtrl.clear();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Support ticket created!')));
      if (err == null) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
          title: const Text('Support Center',
              style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0),
      body: _loading
          ? const LoadingSpinner()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Quick contact
                const AppCard(
                    color: Color(0xFFEBF7EB),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _ContactInfo(
                              icon: Icons.email_rounded,
                              label: 'Email',
                              value: 'support@bemengede.com'),
                          _ContactInfo(
                              icon: Icons.chat_bubble_rounded,
                              label: 'Chat',
                              value: '9AM – 6PM'),
                          _ContactInfo(
                              icon: Icons.access_time_rounded,
                              label: 'Response',
                              value: '< 24h'),
                        ])),
                const SizedBox(height: 16),

                // Create ticket
                if (!_creating)
                  SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => setState(() => _creating = true),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Create Support Ticket'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(AppColors.primary),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12))),
                      ))
                else
                  AppCard(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('New Ticket',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold)),
                              IconButton(
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () =>
                                      setState(() => _creating = false)),
                            ]),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: _subjectCtrl,
                            decoration: _dec('Subject')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _priority,
                          decoration: _dec('Priority'),
                          items: const [
                            DropdownMenuItem(
                                value: 'low',
                                child: Text('Low — General inquiry')),
                            DropdownMenuItem(
                                value: 'medium',
                                child: Text('Medium — Issue with delivery')),
                            DropdownMenuItem(
                                value: 'high',
                                child: Text('High — Urgent / Account issue')),
                          ],
                          onChanged: (v) =>
                              setState(() => _priority = v ?? 'medium'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: _descCtrl,
                            maxLines: 4,
                            decoration: _dec('Description')),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                              child: ElevatedButton(
                            onPressed: _submitting ? null : _submit,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(AppColors.primary),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10))),
                            child: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Submit'),
                          )),
                          const SizedBox(width: 10),
                          OutlinedButton(
                              onPressed: () =>
                                  setState(() => _creating = false),
                              style: OutlinedButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10))),
                              child: const Text('Cancel')),
                        ]),
                      ])),
                const SizedBox(height: 20),

                const Text('Your Tickets',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                if (_tickets.isEmpty)
                  const EmptyState(
                      icon: Icons.support_agent_rounded,
                      title: 'No tickets yet',
                      subtitle:
                          'Submit a ticket and our team will respond within 24h')
                else
                  ..._tickets.map((t) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TicketCard(
                          ticket: t,
                          onTap: () => setState(() => _selected = t)))),
              ],
            ),
      bottomSheet: _selected == null
          ? null
          : _TicketDetail(
              ticket: _selected!,
              onClose: () => setState(() => _selected = null)),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      filled: true,
      fillColor: Colors.white);
}

class _ContactInfo extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ContactInfo(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(children: [
        Icon(icon, color: const Color(0xFF2A9E2D), size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A5C1C))),
        Text(value,
            style: const TextStyle(fontSize: 11, color: Color(0xFF2A9E2D))),
      ]);
}

class _TicketCard extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onTap;
  const _TicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) => AppCard(
      onTap: onTap,
      child: Row(children: [
        Icon(_statusIcon(ticket.status),
            color: _statusColor(ticket.status), size: 22),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ticket.subject,
              style: const TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text(ticket.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: Color(AppColors.textSecondary))),
        ])),
        const SizedBox(width: 8),
        StatusBadge(ticket.status),
      ]));

  IconData _statusIcon(String s) => switch (s) {
        'resolved' => Icons.check_circle_rounded,
        'in_progress' => Icons.hourglass_top_rounded,
        'closed' => Icons.block_rounded,
        _ => Icons.chat_bubble_outline_rounded
      };
  Color _statusColor(String s) => switch (s) {
        'resolved' => const Color(AppColors.success),
        'in_progress' => const Color(AppColors.primary),
        'closed' => const Color(AppColors.textSecondary),
        _ => const Color(0xFFD97706)
      };
}

class _TicketDetail extends StatelessWidget {
  final SupportTicket ticket;
  final VoidCallback onClose;
  const _TicketDetail({required this.ticket, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black12)]),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
              child: Text(ticket.subject,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClose),
        ]),
        Text('Ticket #${ticket.id.substring(0, 8)}',
            style: const TextStyle(
                fontSize: 12, color: Color(AppColors.textSecondary))),
        const Divider(height: 20),
        Row(children: [
          StatusBadge(ticket.status),
          const SizedBox(width: 10),
          StatusBadge(ticket.priority)
        ]),
        const SizedBox(height: 12),
        const Text('Your Message',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Expanded(
            child: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              Text(ticket.description,
                  style:
                      const TextStyle(color: Color(AppColors.textSecondary))),
              if (ticket.adminResponse != null) ...[
                const SizedBox(height: 16),
                Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEBF7EB),
                        borderRadius: BorderRadius.circular(10)),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Support Team Response',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E6B20))),
                          const SizedBox(height: 6),
                          Text(ticket.adminResponse!,
                              style: const TextStyle(color: Color(0xFF1E6B20))),
                        ])),
              ],
            ]))),
      ]),
    );
  }
}
