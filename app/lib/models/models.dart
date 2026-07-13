// lib/models/models.dart
// Models mapped exactly to real Supabase schema

// ── Package ───────────────────────────────────────────────────────────────────
// Table: packages
// Columns: id, sender_id, title, description, from_location, to_location,
//          weight, offered_price, status, created_at

class PackageModel {
  final String id;
  final String senderId;
  final String title;
  final String? description;
  final String fromLocation;
  final String toLocation;
  final double weight;
  final double offeredPrice;
  final String status;
  final String createdAt;
  final String? senderNickname;
  final String? senderFullName;
  // Delivery type + route coordinates (used by automated pricing engine)
  final String deliveryType; // 'hand' | 'office'
  final double? fromLat;
  final double? fromLng;
  final double? toLat;
  final double? toLng;
  final double? distanceKm; // cached distance if computed

  const PackageModel({
    required this.id,
    required this.senderId,
    required this.title,
    this.description,
    required this.fromLocation,
    required this.toLocation,
    required this.weight,
    required this.offeredPrice,
    required this.status,
    required this.createdAt,
    this.senderNickname,
    this.senderFullName,
    this.deliveryType = 'hand',
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.distanceKm,
  });

  factory PackageModel.fromMap(Map<String, dynamic> m,
      {Map<String, dynamic>? profile}) {
    return PackageModel(
      id: m['id'] as String,
      senderId: m['sender_id'] as String? ?? '',
      title: m['title'] as String? ?? '',
      description: m['description'] as String?,
      fromLocation: m['from_location'] as String? ?? '',
      toLocation: m['to_location'] as String? ?? '',
      weight: (m['weight'] as num?)?.toDouble() ?? 0,
      offeredPrice: (m['offered_price'] as num?)?.toDouble() ?? 0,
      status: m['status'] as String? ?? 'pending',
      createdAt: m['created_at'] as String? ?? '',
      senderNickname: profile?['nickname'] as String?,
      senderFullName: profile?['full_name'] as String?,
      deliveryType: m['delivery_type'] as String? ?? 'hand',
      fromLat: (m['from_lat'] as num?)?.toDouble(),
      fromLng: (m['from_lng'] as num?)?.toDouble(),
      toLat: (m['to_lat'] as num?)?.toDouble(),
      toLng: (m['to_lng'] as num?)?.toDouble(),
      distanceKm: (m['distance_km'] as num?)?.toDouble(),
    );
  }

  String get displaySenderName =>
      senderNickname ?? senderFullName ?? 'Anonymous';
}

// ── Trip ──────────────────────────────────────────────────────────────────────
// Table: trips  (Addis Ababa in-city routes only — no cross-city/country travel)
// Columns: id, traveler_id, from_area, to_area, from_lat, from_lng, to_lat, to_lng,
//          travel_date, available_weight, price, notes, status, created_at,
//          current_lat, current_lng, last_location_at

class TripModel {
  final String id;
  final String travelerId;
  final String
      fromArea; // e.g. "Bole", "Piassa", "Kazanchis" — sub-city/neighborhood
  final String toArea;
  final double? fromLat;
  final double? fromLng;
  final double? toLat;
  final double? toLng;
  final String? travelDate;
  final double? availableWeight;
  final double? price; // flat price per delivery on this route, not per-kg
  final String? notes;
  final String status;
  final String createdAt;
  // Live location, updated while traveler is online (for map tracking)
  final double? currentLat;
  final double? currentLng;
  final String? lastLocationAt;
  // Traveler profile (joined from profiles_public)
  final String? travelerNickname;
  final String? travelerFullName;
  final String? travelerAvatar;
  final bool isVerified;
  final double avgRating;
  final int reviewCount;
  final int completedDeliveries;

  const TripModel({
    required this.id,
    required this.travelerId,
    required this.fromArea,
    required this.toArea,
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.travelDate,
    this.availableWeight,
    this.price,
    this.notes,
    required this.status,
    required this.createdAt,
    this.currentLat,
    this.currentLng,
    this.lastLocationAt,
    this.travelerNickname,
    this.travelerFullName,
    this.travelerAvatar,
    this.isVerified = false,
    this.avgRating = 0,
    this.reviewCount = 0,
    this.completedDeliveries = 0,
  });

  factory TripModel.fromMap(
    Map<String, dynamic> m, {
    Map<String, dynamic>? profile,
    bool isVerified = false,
    double avgRating = 0,
    int reviewCount = 0,
    int completedDeliveries = 0,
  }) {
    return TripModel(
      id: m['id'] as String,
      travelerId: m['traveler_id'] as String? ?? '',
      fromArea: m['from_area'] as String? ?? '',
      toArea: m['to_area'] as String? ?? '',
      fromLat: (m['from_lat'] as num?)?.toDouble(),
      fromLng: (m['from_lng'] as num?)?.toDouble(),
      toLat: (m['to_lat'] as num?)?.toDouble(),
      toLng: (m['to_lng'] as num?)?.toDouble(),
      travelDate: m['travel_date'] as String?,
      availableWeight: (m['available_weight'] as num?)?.toDouble(),
      price: (m['price'] as num?)?.toDouble(),
      notes: m['notes'] as String?,
      status: m['status'] as String? ?? 'active',
      createdAt: m['created_at'] as String? ?? '',
      currentLat: (m['current_lat'] as num?)?.toDouble(),
      currentLng: (m['current_lng'] as num?)?.toDouble(),
      lastLocationAt: m['last_location_at'] as String?,
      travelerNickname: profile?['nickname'] as String?,
      travelerFullName: profile?['full_name'] as String?,
      travelerAvatar: profile?['avatar_url'] as String?,
      isVerified: isVerified,
      avgRating: avgRating,
      reviewCount: reviewCount,
      completedDeliveries: completedDeliveries,
    );
  }

  String get displayName => travelerNickname ?? travelerFullName ?? 'Commuter';
  String get route => '$fromArea → $toArea';
}

// ── Traveler Offer ────────────────────────────────────────────────────────────
// Table: traveler_offers
// Columns: id, traveler_id, trip_id, package_id, status, price, created_at

class TravelerOffer {
  final String id;
  final String travelerId;
  final String? tripId;
  final String? packageId;
  final String status;
  final double? price;
  final String createdAt;
  final String? packageTitle;
  final String? fromLocation;
  final String? toLocation;
  final double? weight;
  final String? travelerName;
  final String? senderName;

  const TravelerOffer({
    required this.id,
    required this.travelerId,
    this.tripId,
    this.packageId,
    required this.status,
    this.price,
    required this.createdAt,
    this.packageTitle,
    this.fromLocation,
    this.toLocation,
    this.weight,
    this.travelerName,
    this.senderName,
  });

  factory TravelerOffer.fromMap(Map<String, dynamic> m) {
    final pkg = m['packages'] as Map<String, dynamic>?;
    final traveler = m['profiles'] as Map<String, dynamic>?;
    return TravelerOffer(
      id: m['id'] as String,
      travelerId: m['traveler_id'] as String? ?? '',
      tripId: m['trip_id'] as String?,
      packageId: m['package_id'] as String?,
      status: m['status'] as String? ?? 'active',
      price: (m['price'] as num?)?.toDouble(),
      createdAt: m['created_at'] as String? ?? '',
      packageTitle: pkg?['title'] as String?,
      fromLocation: pkg?['from_location'] as String?,
      toLocation: pkg?['to_location'] as String?,
      weight: (pkg?['weight'] as num?)?.toDouble(),
      travelerName:
          (traveler?['nickname'] ?? traveler?['full_name']) as String?,
    );
  }
}

// ── KYC ───────────────────────────────────────────────────────────────────────
// Table: kyc_documents
// Columns: id, user_id, document_type, document_url, selfie_url,
//          status, notes, reviewed_at, reviewed_by, created_at

enum KycStatus { notSubmitted, pending, approved, rejected }

extension KycStatusExt on KycStatus {
  static KycStatus fromString(String? s) => switch (s) {
        'pending' => KycStatus.pending,
        'approved' => KycStatus.approved,
        'rejected' => KycStatus.rejected,
        _ => KycStatus.notSubmitted,
      };

  String get label => switch (this) {
        KycStatus.pending => 'Under Review',
        KycStatus.approved => 'Approved',
        KycStatus.rejected => 'Rejected',
        KycStatus.notSubmitted => 'Not Submitted',
      };
}

// ── Notification ──────────────────────────────────────────────────────────────
// Table: notifications
// Columns: id, user_id, (+ more columns not in schema export)

class AppNotification {
  final String id;
  final String userId;
  final String? title;
  final String? body;
  final bool read;
  final String createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.title,
    this.body,
    this.read = false,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        title: m['title'] as String?,
        body: m['body'] as String?,
        read: m['read'] as bool? ?? false,
        createdAt: m['created_at'] as String? ?? '',
      );
}

// ── Chat Message ──────────────────────────────────────────────────────────────

// ── Payment Methods (Ethiopia) ────────────────────────────────────────────────

class PaymentMethod {
  final String value;
  final String label;
  final String placeholder;
  const PaymentMethod(
      {required this.value, required this.label, required this.placeholder});
}

const kPaymentMethods = [
  PaymentMethod(
      value: 'telebirr', label: 'Telebirr', placeholder: '+251 9XX XXX XXXX'),
  PaymentMethod(
      value: 'cbe',
      label: 'CBE (Commercial Bank of Ethiopia)',
      placeholder: 'Enter CBE account number'),
  PaymentMethod(
      value: 'awash',
      label: 'Awash Bank',
      placeholder: 'Enter Awash account number'),
  PaymentMethod(
      value: 'dashen',
      label: 'Dashen Bank',
      placeholder: 'Enter Dashen account number'),
  PaymentMethod(
      value: 'abyssinia',
      label: 'Bank of Abyssinia',
      placeholder: 'Enter Abyssinia account number'),
  PaymentMethod(
      value: 'cbe_birr',
      label: 'CBE Birr (Mobile)',
      placeholder: '+251 9XX XXX XXXX'),
  PaymentMethod(
      value: 'cash',
      label: 'Cash on Delivery',
      placeholder: 'No account needed'),
];

// ── Delivery ──────────────────────────────────────────────────────────────────
// Table: deliveries
// Columns: id, sender_id, traveler_id, package_id, status, pickup_at,
//          expires_at, completed_at, amount, payment_status, created_at

class DeliveryModel {
  final String id;
  final String senderId;
  final String travelerId;
  final String packageId;
  final String status;
  final String? pickupAt;
  final String? expiresAt;
  final String? completedAt;
  final double amount;
  final String paymentStatus;
  final String createdAt;
  // Joined package info
  final String? packageTitle;
  final String? fromLocation;
  final String? toLocation;
  final double? weight;
  final String? travelerName;
  final String? senderName;
  final bool isCancelled;
  final bool isCompleted;
  final double? agreedPrice;
  final double? fromLat;
  final double? fromLng;
  final double? toLat;
  final double? toLng;
  final String? commissionProofUrl;
  final String? commissionRejectionReason;
  final bool hasOpenDispute;

  const DeliveryModel({
    required this.id,
    required this.senderId,
    required this.travelerId,
    required this.packageId,
    required this.status,
    this.pickupAt,
    this.expiresAt,
    this.completedAt,
    this.amount = 0,
    this.paymentStatus = 'pending',
    required this.createdAt,
    this.packageTitle,
    this.fromLocation,
    this.toLocation,
    this.weight,
    this.travelerName,
    this.senderName,
    this.isCancelled = false,
    this.isCompleted = false,
    this.agreedPrice,
    this.fromLat,
    this.fromLng,
    this.toLat,
    this.toLng,
    this.commissionProofUrl,
    this.commissionRejectionReason,
    this.hasOpenDispute = false,
  });

  factory DeliveryModel.fromMap(Map<String, dynamic> m) {
    final pkg = m['packages'] as Map<String, dynamic>?;
    final traveler = m['traveler'] as Map<String, dynamic>?;
    final sender = m['sender'] as Map<String, dynamic>?;
    final status = (m['status'] as String?)?.toLowerCase() ?? 'pending';
    return DeliveryModel(
      id: m['id'] as String,
      senderId: m['sender_id'] as String? ?? '',
      travelerId: m['traveler_id'] as String? ?? '',
      packageId: m['package_id'] as String? ?? '',
      status: status,
      pickupAt: m['pickup_at'] as String?,
      expiresAt: m['expires_at'] as String?,
      completedAt: m['completed_at'] as String?,
      amount: (m['amount'] as num?)?.toDouble() ?? 0,
      paymentStatus: m['payment_status'] as String? ?? 'pending',
      createdAt: m['created_at'] as String? ?? '',
      packageTitle: pkg?['title'] as String?,
      fromLocation: pkg?['from_location'] as String?,
      toLocation: pkg?['to_location'] as String?,
      weight: (pkg?['weight'] as num?)?.toDouble(),
      travelerName:
          (traveler?['nickname'] ?? traveler?['full_name']) as String?,
      senderName: (sender?['nickname'] ?? sender?['full_name']) as String?,
      agreedPrice: (m['agreed_price'] as num?)?.toDouble(),
      isCancelled: status == 'cancelled',
      isCompleted: ['completed', 'delivered'].contains(status),
      fromLat: (pkg?['from_lat'] as num?)?.toDouble(),
      fromLng: (pkg?['from_lng'] as num?)?.toDouble(),
      toLat: (pkg?['to_lat'] as num?)?.toDouble(),
      toLng: (pkg?['to_lng'] as num?)?.toDouble(),
      commissionProofUrl: m['commission_proof_url'] as String?,
      commissionRejectionReason: m['commission_rejection_reason'] as String?,
      hasOpenDispute: m['has_open_dispute'] as bool? ?? false,
    );
  }

  bool get isOverdue {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(DateTime.parse(expiresAt!));
  }

  Duration? get timeRemaining {
    if (expiresAt == null) return null;
    final remaining = DateTime.parse(expiresAt!).difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class SupportTicket {
  final String id;
  final String userId;
  final String subject;
  final String description;
  final String priority;
  final String status;
  final String createdAt;
  final String? adminResponse;
  final String? customerName;

  const SupportTicket({
    required this.id,
    required this.userId,
    required this.subject,
    required this.description,
    required this.priority,
    required this.status,
    required this.createdAt,
    this.adminResponse,
    this.customerName,
  });

  factory SupportTicket.fromMap(Map<String, dynamic> m) {
    final profile = m['profiles'] as Map<String, dynamic>?;
    return SupportTicket(
      id: m['id'] as String,
      userId: m['user_id'] as String? ?? '',
      subject: m['subject'] as String? ?? '',
      description: m['description'] as String? ?? '',
      priority: m['priority'] as String? ?? 'medium',
      status: m['status'] as String? ?? 'open',
      createdAt: m['created_at'] as String? ?? '',
      adminResponse: m['response'] as String?,
      customerName: (profile?['nickname'] ?? profile?['full_name']) as String?,
    );
  }
}

// ── Rating ────────────────────────────────────────────────────────────────────
// Table: ratings
// Columns: id, delivery_id, rater_id, ratee_id, stars, comment, created_at

class RatingModel {
  final String id;
  final String deliveryId;
  final String raterId;
  final String rateeId;
  final int stars;
  final String? comment;
  final String createdAt;

  const RatingModel({
    required this.id,
    required this.deliveryId,
    required this.raterId,
    required this.rateeId,
    required this.stars,
    this.comment,
    required this.createdAt,
  });

  factory RatingModel.fromMap(Map<String, dynamic> m) => RatingModel(
        id: m['id'] as String,
        deliveryId: m['delivery_id'] as String,
        raterId: m['rater_id'] as String,
        rateeId: m['ratee_id'] as String,
        stars: m['stars'] as int,
        comment: m['comment'] as String?,
        createdAt: m['created_at'] as String? ?? '',
      );
}
