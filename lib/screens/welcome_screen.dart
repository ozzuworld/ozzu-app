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
    const background = Color(0xFF121212); // Modern dark
    const blue = Color(0xFF248CE0);      // Modern blue
    return Scaffold(
      backgroundColor: background,
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
                  fontFamily: 'Montserrat', // If font included, otherwise remove
                  shadows: [
                    Shadow(
                      offset: Offset(0, 2),
                      blurRadius: 8,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleLogin(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 3,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Montserrat', // If available
                    ),
                  ),
                  child: const Text(
                    'Login',
                    style: TextStyle(
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
