import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../services/keycloak_service.dart';
import '../main.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback? onLoggedIn;
  const WelcomeScreen({super.key, this.onLoggedIn});

  Future<void> _handleLogin(BuildContext context) async {
    final auth = AuthService();
    try {
      if (!auth.isAuthenticated) {
        debugLogger.i('🔑 WelcomeScreen: Starting login');
        await auth.login();
      }
      onLoggedIn?.call();
    } catch (e) {
      debugLogger.e('❌ WelcomeScreen: Login failed', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: GestureDetector(
          onTap: () => _handleLogin(context),
          child: Lottie.asset(
            'assets/lottie/login-button.json',
            width: 200,
            height: 200,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
