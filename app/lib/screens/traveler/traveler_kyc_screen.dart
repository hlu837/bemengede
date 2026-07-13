// lib/screens/traveler/traveler_kyc_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../services/data_service.dart';
import '../../models/models.dart';
import '../../utils/constants.dart';
import '../../widgets/common/shared_widgets.dart';

class TravelerKycScreen extends ConsumerStatefulWidget {
  const TravelerKycScreen({super.key});
  @override
  ConsumerState<TravelerKycScreen> createState() => _TravelerKycScreenState();
}

class _TravelerKycScreenState extends ConsumerState<TravelerKycScreen> {
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
  final _refNameCtrl       = TextEditingController();
  final _refPhoneCtrl      = TextEditingController();
  final _refRelationCtrl   = TextEditingController();
  final _refOccupationCtrl = TextEditingController();
  final _refEmployerCtrl   = TextEditingController();
  final _refIdCtrl         = TextEditingController();

  // Step 3 — Supporting Document from Employer/Gov
  String _supportDocType = 'employer_letter';
  Uint8List? _supportDocFile;

  @override
  void initState() { super.initState(); _loadStatus(); }

  @override
  void dispose() {
    for (final c in [_notesCtrl, _refNameCtrl, _refPhoneCtrl, _refRelationCtrl,
        _refOccupationCtrl, _refEmployerCtrl, _refIdCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final status = await _svc.fetchKycStatus(user.id);
    if (mounted) setState(() { _status = status; _loading = false; });
  }

  Future<void> _pickFile(bool isSelfie, {bool isSupportDoc = false}) async {
    final source = isSelfie ? ImageSource.camera : ImageSource.gallery;
    final picked = isSelfie || isSupportDoc
        ? await _picker.pickImage(source: source, imageQuality: 85)
        : await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    // Read as bytes instead of wrapping in dart:io's File — File has no web
    // implementation, so reading bytes via XFile keeps this working on
    // mobile, desktop, and web alike.
    final bytes = await picked.readAsBytes();
    setState(() {
      if (isSupportDoc) { _supportDocFile = bytes; }
      else if (isSelfie) { _selfieFile = bytes; }
      else { _docFile = bytes; }
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
      final selfieUrl = await _svc.uploadKycFile(user.id, _selfieFile!, 'selfie');
      // Upload support doc
      String? supportUrl;
      if (_supportDocFile != null) {
        supportUrl = await _svc.uploadKycFile(user.id, _supportDocFile!, 'support_doc');
      }

      // Insert into kyc_documents with all new fields
      await _svc.submitKycFull(
        userId:               user.id,
        documentType:         _docType,
        documentUrl:          docUrl,
        selfieUrl:            selfieUrl,
        notes:                _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        referenceFullName:    _refNameCtrl.text.trim(),
        referencePhone:       _refPhoneCtrl.text.trim(),
        referenceRelationship: _refRelationCtrl.text.trim(),
        referenceOccupation:  _refOccupationCtrl.text.trim().isEmpty ? null : _refOccupationCtrl.text.trim(),
        referenceEmployer:    _refEmployerCtrl.text.trim(),
        referenceIdNumber:    _refIdCtrl.text.trim().isEmpty ? null : _refIdCtrl.text.trim(),
        supportDocUrl:        supportUrl,
        supportDocType:       _supportDocType,
      );

      if (mounted) setState(() { _status = KycStatus.pending; _submitting = false; });
      if (mounted) _showSnack('KYC submitted! Under review in 24–48 hours.');
    } catch (e) {
      if (mounted) setState(() => _submitting = false);
      if (mounted) _showSnack('Submission failed: ${e.toString()}', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(AppColors.error) : const Color(AppColors.success),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(AppColors.surface),
      appBar: AppBar(
        title: const Text('KYC Verification', style: TextStyle(fontWeight: FontWeight.bold)),
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

  Widget _approvedState() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80, decoration: const BoxDecoration(color: Color(AppColors.successLight), shape: BoxShape.circle),
          child: const Icon(Icons.verified_user_rounded, size: 44, color: Color(AppColors.success))),
      const SizedBox(height: 20),
      const Text('You are Verified!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(AppColors.textPrimary))),
      const SizedBox(height: 8),
      const Text('Senders can see your verified badge and trust you more.', textAlign: TextAlign.center, style: TextStyle(color: Color(AppColors.textSecondary))),
    ]),
  ));

  Widget _pendingState() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(width: 80, height: 80, decoration: const BoxDecoration(color: Color(0xFFFFFBEB), shape: BoxShape.circle),
          child: const Icon(Icons.hourglass_empty_rounded, size: 44, color: Color(0xFFD97706))),
      const SizedBox(height: 20),
      const Text('Under Review', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(AppColors.textPrimary))),
      const SizedBox(height: 8),
      const Text('Your documents are being reviewed.\nThis usually takes 24–48 hours.', textAlign: TextAlign.center, style: TextStyle(color: Color(AppColors.textSecondary))),
    ]),
  ));

  // ── Multi-Step Form ────────────────────────────────────────────────────────

  Widget _form() {
    return Column(children: [
      // Step indicator
      _StepIndicator(current: _step, steps: const ['ID Documents', 'Reference Person', 'Support Letter']),
      Expanded(child: SingleChildScrollView(
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
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(AppColors.border)))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!_submitting && _blockingReason != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFFB91C1C)),
                const SizedBox(width: 6),
                Expanded(child: Text(_blockingReason!, style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)))),
              ]),
            ),
          ],
          Row(children: [
            if (_step > 0) ...[
              Expanded(child: OutlinedButton(
                onPressed: () => setState(() => _step--),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: const Color(AppColors.primary).withOpacity(0.4),
                ),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_step == 2 ? 'Submit KYC' : 'Continue', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }

  bool _canProceed() {
    if (_submitting) return false;
    return switch (_step) { 0 => _step1Valid, 1 => _step2Valid, _ => _step3Valid };
  }

  void _onNext() {
    if (_step < 2) { setState(() => _step++); }
    else { _submit(); }
  }

  // ── Step 1: ID Documents ──────────────────────────────────────────────────

  Widget _step1() => Column(key: const ValueKey(0), crossAxisAlignment: CrossAxisAlignment.start, children: [
    const _SectionTitle(icon: Icons.badge_rounded, title: 'Government-Issued ID', subtitle: 'Upload a clear photo of your ID document'),
    const SizedBox(height: 14),

    // Doc type chips
    const Text('Document Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(AppColors.textPrimary))),
    const SizedBox(height: 8),
    Wrap(spacing: 8, children: [
      for (final t in [('passport', 'Passport'), ('national_id', 'National ID'), ('drivers_license', "Driver's License")])
        ChoiceChip(
          label: Text(t.$2),
          selected: _docType == t.$1,
          onSelected: (_) => setState(() => _docType = t.$1),
          selectedColor: const Color(AppColors.primaryLight),
          labelStyle: TextStyle(color: _docType == t.$1 ? const Color(AppColors.primary) : null, fontWeight: FontWeight.w500),
        ),
    ]),
    const SizedBox(height: 16),

    // Upload ID doc
    _UploadBox(label: 'Upload ID Document', sublabel: 'JPG, PNG or PDF · Max 5MB', done: _docFile != null, icon: Icons.file_present_rounded, onTap: () => _pickFile(false)),
    const SizedBox(height: 12),

    // Upload selfie
    _UploadBox(label: 'Upload Selfie Holding ID', sublabel: 'Take a photo of yourself holding the document', done: _selfieFile != null, icon: Icons.camera_alt_rounded, onTap: () => _pickFile(true)),
    const SizedBox(height: 12),

    // Notes
    TextFormField(
      controller: _notesCtrl,
      maxLines: 3,
      decoration: _dec('Additional Notes (optional)', 'Any information that might help reviewers'),
    ),
  ]);

  // ── Step 2: Reference Person ──────────────────────────────────────────────

  Widget _step2() => Column(key: const ValueKey(1), crossAxisAlignment: CrossAxisAlignment.start, children: [
    const _SectionTitle(icon: Icons.people_rounded, title: 'Reference / Emergency Person', subtitle: 'Provide a contact who can verify your identity. Must be a government worker or company employee.'),
    const SizedBox(height: 14),

    const AppCard(color: Color(0xFFFFFBEB), padding: EdgeInsets.all(12), child: Row(children: [
      Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 18),
      SizedBox(width: 8),
      Expanded(child: Text('This person will be contacted only in case of fraud investigation or disputes.', style: TextStyle(fontSize: 12, color: Color(0xFF92400E)))),
    ])),
    const SizedBox(height: 14),

    _field(_refNameCtrl, 'Full Name *', 'e.g. Dr. Abebe Girma'),
    const SizedBox(height: 12),
    _field(_refPhoneCtrl, 'Phone Number *', '+251 9XX XXX XXXX', keyboard: TextInputType.phone),
    const SizedBox(height: 12),
    _field(_refRelationCtrl, 'Relationship to You *', 'e.g. Employer, Supervisor, Colleague'),
    const SizedBox(height: 12),
    _field(_refOccupationCtrl, 'Their Occupation', 'e.g. Government Officer, Manager'),
    const SizedBox(height: 12),
    _field(_refEmployerCtrl, 'Their Employer / Organization *', 'e.g. Ministry of Transport, Ethio Telecom'),
    const SizedBox(height: 12),
    _field(_refIdCtrl, 'Their Government ID Number (optional)', 'e.g. National ID or Employee ID'),

    const SizedBox(height: 12),
    const AppCard(color: Color(AppColors.primaryLight), padding: EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Why is this required?', style: TextStyle(fontWeight: FontWeight.bold, color: Color(AppColors.primary), fontSize: 13)),
      SizedBox(height: 6),
      Text('Bemengede uses a reference system for traveler accountability. Your reference person vouches for your identity and is used for fraud prevention only.', style: TextStyle(fontSize: 12, color: Color(AppColors.textSecondary))),
    ])),
  ]);

  // ── Step 3: Supporting Document ───────────────────────────────────────────

  Widget _step3() => Column(key: const ValueKey(2), crossAxisAlignment: CrossAxisAlignment.start, children: [
    const _SectionTitle(icon: Icons.description_rounded, title: 'Supporting Document', subtitle: 'Upload a letter from your employer or a government institution confirming your identity.'),
    const SizedBox(height: 14),

    const Text('Document Type', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(AppColors.textPrimary))),
    const SizedBox(height: 8),
    Wrap(spacing: 8, children: [
      for (final t in [('employer_letter', 'Employer Letter'), ('government_letter', 'Government Letter'), ('company_id', 'Company ID Card')])
        ChoiceChip(
          label: Text(t.$2),
          selected: _supportDocType == t.$1,
          onSelected: (_) => setState(() => _supportDocType = t.$1),
          selectedColor: const Color(AppColors.primaryLight),
          labelStyle: TextStyle(color: _supportDocType == t.$1 ? const Color(AppColors.primary) : null, fontWeight: FontWeight.w500),
        ),
    ]),
    const SizedBox(height: 16),

    // What should the document contain
    AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Document must include:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(AppColors.textPrimary))),
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
            const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(AppColors.success)),
            const SizedBox(width: 8),
            Text(item, style: const TextStyle(fontSize: 13, color: Color(AppColors.textPrimary))),
          ]),
        ),
    ])),
    const SizedBox(height: 14),

    _UploadBox(
      label: 'Upload Supporting Document',
      sublabel: 'PDF, JPG or PNG · Max 5MB',
      done: _supportDocFile != null,
      icon: Icons.upload_file_rounded,
      onTap: () => _pickFile(false, isSupportDoc: true),
    ),

    const SizedBox(height: 14),
    const AppCard(color: Color(AppColors.successLight), padding: EdgeInsets.all(12), child: Row(children: [
      Icon(Icons.security_rounded, color: Color(AppColors.success), size: 20),
      SizedBox(width: 10),
      Expanded(child: Text('All documents are encrypted and only accessible by Bemengede reviewers.', style: TextStyle(fontSize: 12, color: Color(AppColors.success)))),
    ])),
  ]);

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _field(TextEditingController ctrl, String label, String hint, {TextInputType? keyboard}) =>
    TextFormField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: _dec(label, hint),
      onChanged: (_) => setState(() {}),
    );

  InputDecoration _dec(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintStyle: const TextStyle(color: Color(AppColors.textSecondary), fontSize: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(AppColors.border))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(AppColors.primary), width: 2)),
    filled: true, fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          Expanded(child: Column(children: [
            Row(children: [
              if (i > 0) Expanded(child: Container(height: 2, color: i <= current ? const Color(AppColors.primary) : const Color(AppColors.border))),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: i < current ? const Color(AppColors.primary) : i == current ? const Color(AppColors.primary) : const Color(AppColors.border),
                  shape: BoxShape.circle,
                ),
                child: Center(child: i < current
                    ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                    : Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: i == current ? Colors.white : const Color(AppColors.textSecondary)))),
              ),
              if (i < steps.length - 1) Expanded(child: Container(height: 2, color: i < current ? const Color(AppColors.primary) : const Color(AppColors.border))),
            ]),
            const SizedBox(height: 4),
            Text(steps[i], style: TextStyle(fontSize: 10, fontWeight: i == current ? FontWeight.w600 : FontWeight.normal, color: i == current ? const Color(AppColors.primary) : const Color(AppColors.textSecondary)), textAlign: TextAlign.center),
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
  const _SectionTitle({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 44, height: 44, decoration: BoxDecoration(color: const Color(AppColors.primaryLight), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: const Color(AppColors.primary), size: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(AppColors.textPrimary))),
        const SizedBox(height: 3),
        Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(AppColors.textSecondary))),
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

  const _UploadBox({required this.label, required this.sublabel, required this.done, required this.icon, required this.onTap});

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
          border: Border.all(color: done ? const Color(AppColors.success) : const Color(AppColors.border), width: done ? 2 : 1, style: done ? BorderStyle.solid : BorderStyle.solid),
        ),
        child: Column(children: [
          Icon(done ? Icons.check_circle_rounded : icon, size: 40, color: done ? const Color(AppColors.success) : const Color(AppColors.textSecondary)),
          const SizedBox(height: 10),
          Text(done ? 'File selected ✓' : label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: done ? const Color(AppColors.success) : const Color(AppColors.textPrimary))),
          const SizedBox(height: 4),
          Text(done ? 'Tap to change' : sublabel, style: const TextStyle(fontSize: 12, color: Color(AppColors.textSecondary))),
        ]),
      ),
    );
  }
}