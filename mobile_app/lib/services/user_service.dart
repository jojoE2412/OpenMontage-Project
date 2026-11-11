class UserProfile {
  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
  });

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'email': email,
    'displayName': displayName,
    'photoUrl': photoUrl,
  };

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      displayName: map['displayName']?.toString() ?? 'Creator',
      photoUrl: map['photoUrl']?.toString(),
    );
  }
}

class UserService {
  const UserService();

  static const bool isConfigured = false;

  Future<UserProfile?> fetchCurrentUserProfile() async {
    return null;
  }

  Future<void> saveUserProfile(UserProfile profile) async {}

  Future<void> updateUserProfile(UserProfile profile) async {}
}
