class FirebaseAuthService {
  const FirebaseAuthService();

  static const bool isConfigured = false;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    throw UnimplementedError(
      'Firebase Authentication will be configured in the next integration phase.',
    );
  }

  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    throw UnimplementedError(
      'Firebase Authentication will be configured in the next integration phase.',
    );
  }

  Future<void> signOut() async {
    throw UnimplementedError(
      'Firebase Authentication will be configured in the next integration phase.',
    );
  }
}
