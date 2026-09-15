import '../../core/utils/api_datetime.dart';
import 'package:equatable/equatable.dart';

class UserModel extends Equatable {
  final String id;
  final String email;
  /// Private, verified E.164 sign-in number (never present in public users).
  final String? mobileNumber;
  // Telegram-like: username (@id) is OPTIONAL and may be null.
  final String? username;
  final String displayName;
  final String? bio;
  final String? avatarUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final bool showLastSeen;
  final bool showProfilePhoto;
  final bool showBio;
  final bool allowGroupAdds;
  final bool allowForwarding;
  final int termsVersion;
  final bool isTwoFactorEnabled;
  final bool isAdmin;

  const UserModel({
    required this.id,
    required this.email,
    this.mobileNumber,
    this.username,
    required this.displayName,
    this.bio,
    this.avatarUrl,
    this.isOnline = false,
    this.lastSeen,
    this.showLastSeen = true,
    this.showProfilePhoto = true,
    this.showBio = true,
    this.allowGroupAdds = true,
    this.allowForwarding = true,
    this.termsVersion = 0,
    this.isTwoFactorEnabled = false,
    this.isAdmin = false,
  });

  /// Backwards-compatible non-null username for legacy UI (empty when unset).
  String get usernameOrEmpty => username ?? '';

  /// Display handle: @username when set, otherwise display name.
  String get handle => username != null && username!.isNotEmpty ? '@$username' : displayName;

  bool get hasUsername => username != null && username!.isNotEmpty;

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String? ?? '',
      mobileNumber: json['mobile_number'] as String?,
      username: json['username'] as String?,
      displayName: json['display_name'] as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isOnline: json['is_online'] as bool? ?? false,
      lastSeen: parseApiDateTime(json['last_seen'] as String?),
      showLastSeen: json['show_last_seen'] as bool? ?? true,
      showProfilePhoto: json['show_profile_photo'] as bool? ?? true,
      showBio: json['show_bio'] as bool? ?? true,
      allowGroupAdds: json['allow_group_adds'] as bool? ?? true,
      allowForwarding: json['allow_forwarding'] as bool? ?? true,
      termsVersion: json['terms_version'] as int? ?? 0,
      isTwoFactorEnabled: json['is_2fa_enabled'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'mobile_number': mobileNumber,
      'username': username,
      'display_name': displayName,
      'bio': bio,
      'avatar_url': avatarUrl,
      'is_online': isOnline,
      'last_seen': lastSeen?.toUtc().toIso8601String(),
      'show_last_seen': showLastSeen,
      'show_profile_photo': showProfilePhoto,
      'show_bio': showBio,
      'allow_group_adds': allowGroupAdds,
      'is_2fa_enabled': isTwoFactorEnabled,
    };
  }

  @override
  List<Object?> get props => [
    id,
    email,
    mobileNumber,
    username,
    displayName,
    bio,
    avatarUrl,
    isOnline,
    lastSeen,
    showLastSeen,
    showProfilePhoto,
    showBio,
    allowGroupAdds,
    allowForwarding,
    termsVersion,
    isTwoFactorEnabled,
    isAdmin,
  ];
}
