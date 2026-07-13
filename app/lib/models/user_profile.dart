// lib/models/user_profile.dart
// Table: profiles
// Columns: id, email, full_name, nickname, phone, role, avatar_url,
//          kyc_status, preferred_payment, payment_account, created_at, updated_at

enum UserRole { sender, traveler, admin }

extension UserRoleExt on UserRole {
  String get value => name;
  static UserRole fromString(String? s) => switch (s) {
    'traveler' => UserRole.traveler,
    'admin'    => UserRole.admin,
    _          => UserRole.sender,
  };
}

class UserProfile {
  final String id;
  final String email;
  final String fullName;
  final String? nickname;
  final String? phone;
  final UserRole role;
  final String? avatarUrl;
  final String? kycStatus;       // approved | pending | rejected | null
  final String? preferredPayment;
  final String? paymentAccount;
  final String createdAt;
  final String updatedAt;

  const UserProfile({
    required this.id,
    required this.email,
    required this.fullName,
    this.nickname,
    this.phone,
    required this.role,
    this.avatarUrl,
    this.kycStatus,
    this.preferredPayment,
    this.paymentAccount,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isKycApproved => kycStatus == 'approved';
  bool get isKycPending  => kycStatus == 'pending';

  factory UserProfile.fromMap(Map<String, dynamic> m) => UserProfile(
    id:               m['id'] as String,
    email:            m['email'] as String? ?? '',
    fullName:         m['full_name'] as String? ?? '',
    nickname:         m['nickname'] as String?,
    phone:            m['phone'] as String?,
    role:             UserRoleExt.fromString(m['role'] as String?),
    avatarUrl:        m['avatar_url'] as String?,
    kycStatus:        m['kyc_status'] as String?,
    preferredPayment: m['preferred_payment'] as String?,
    paymentAccount:   m['payment_account'] as String?,
    createdAt:        m['created_at'] as String? ?? '',
    updatedAt:        m['updated_at'] as String? ?? '',
  );

  UserProfile copyWith({
    String? fullName, String? nickname, String? phone,
    UserRole? role, String? avatarUrl, String? kycStatus,
    String? preferredPayment, String? paymentAccount,
  }) => UserProfile(
    id: id, email: email,
    fullName:         fullName         ?? this.fullName,
    nickname:         nickname         ?? this.nickname,
    phone:            phone            ?? this.phone,
    role:             role             ?? this.role,
    avatarUrl:        avatarUrl        ?? this.avatarUrl,
    kycStatus:        kycStatus        ?? this.kycStatus,
    preferredPayment: preferredPayment ?? this.preferredPayment,
    paymentAccount:   paymentAccount   ?? this.paymentAccount,
    createdAt: createdAt, updatedAt: updatedAt,
  );
}
