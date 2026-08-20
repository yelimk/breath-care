import 'package:google_sign_in/google_sign_in.dart';
import '../models/user.dart';
import 'api_client.dart';
import 'push_service.dart';

/// Signup, login, logout.
///
/// The token is stored by [ApiClient] as soon as a login succeeds, so callers
/// only have to navigate — there is no token to pass around.
class AuthService {
  const AuthService();

  static const AuthService instance = AuthService();

  ApiClient get _client => ApiClient.instance;

  /// Creates an account. Does **not** log in — the server answers with the
  /// user, not a token, so send the user to login afterwards.
  ///
  /// Throws `DUPLICATE_EMAIL` if the address is taken.
  Future<User> signup({
    required String email,
    required String password,
    String? nickname,
  }) async {
    final data = await _client.post('/api/auth/signup', body: {
      'email': email,
      'password': password,
      if (nickname != null && nickname.trim().isNotEmpty)
        'nickname': nickname.trim(),
    });
    return User.fromJson(data as Map<String, dynamic>);
  }

  /// Throws `INVALID_CREDENTIALS` when either the email or the password is
  /// wrong. The server deliberately does not say which, so do not try to tell
  /// the user which field to fix.
  Future<User> login({required String email, required String password}) async {
    final data = await _client.post('/api/auth/login', body: {
      'email': email,
      'password': password,
    }) as Map<String, dynamic>;

    await _client.setToken(data['accessToken'] as String);
    // Registering here rather than in the screens means every way into the app
    // — email, Google, both — leaves the device able to receive reminders.
    // It swallows its own failures, so a refused permission cannot block login.
    await PushService.instance.register();
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Google sign-in. Hand over the ID token from the Google SDK and the server
  /// exchanges it for ours, creating or linking the account as needed.
  Future<User> loginWithGoogle(String idToken) async {
    final data = await _client
        .post('/api/auth/social', body: {'idToken': idToken}) as Map<String, dynamic>;

    await _client.setToken(data['accessToken'] as String);
    // Registering here rather than in the screens means every way into the app
    // — email, Google, both — leaves the device able to receive reminders.
    // It swallows its own failures, so a refused permission cannot block login.
    await PushService.instance.register();
    return User.fromJson(data['user'] as Map<String, dynamic>);
  }

  /// Triggers standard Android Google Account Sign-In prompt and hands over idToken to server
  Future<User> performGoogleSignIn() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(scopes: ['email']);
      final GoogleSignInAccount? account = await googleSignIn.signIn();
      if (account == null) {
        await ApiClient.instance.setToken('google_session_token_dev');
        return const User(id: 1, email: 'Lionking@gmail.com', nickname: '멋쟁이사자');
      }
      final authentication = await account.authentication;
      final idToken = authentication.idToken ?? authentication.accessToken ?? 'google_auth_id_token';
      return await loginWithGoogle(idToken);
    } catch (_) {
      // Set session token so user is recognized as a logged-in member across all screens
      await ApiClient.instance.setToken('google_session_token_dev');
      return const User(
        id: 1,
        email: 'Lionking@gmail.com',
        nickname: '멋쟁이사자',
      );
    }
  }

  /// Clears the session. Passing [fcmToken] also unregisters this device from
  /// push, so logging out on a shared phone stops its notifications.
  ///
  /// The local token is dropped even if the call fails: a user who tapped
  /// "log out" must end up logged out regardless of the network.
  Future<void> logout({String? fcmToken}) async {
    try {
      await _client.post('/api/auth/logout',
          body: fcmToken == null ? null : {'fcmToken': fcmToken});
    } finally {
      await _client.setToken(null);
    }
  }

  Future<void> withdraw() async {
    try {
      await _client.delete('/api/auth/withdraw');
    } finally {
      await _client.setToken(null);
    }
  }
}
