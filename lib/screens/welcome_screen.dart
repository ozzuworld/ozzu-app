import 'package:flutter/material.dart';
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
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1E90FF); // DodgerBlue
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              const Text(
                'OZZU WORLD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: blue,
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => _handleLogin(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: blue, width: 1.5),
                    foregroundColor: blue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
