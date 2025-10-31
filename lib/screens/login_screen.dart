import 'package:flutter/material.dart';
import '../services/keycloak_service.dart';

class LoginScreen extends StatelessWidget {
  final VoidCallback? onLoggedIn;
  const LoginScreen({super.key, this.onLoggedIn});

  Future<void> _ensureLogin(BuildContext context) async {
    final auth = AuthService();
    // If already authenticated, fire callback
    if (auth.isAuthenticated) {
      onLoggedIn?.call();
      return;
    }
    // Otherwise, trigger login and then callback
    try {
      await auth.login();
      if (onLoggedIn != null) onLoggedIn!();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: ElevatedButton(
          onPressed: () => _ensureLogin(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('Continue'),
        ),
      ),
    );
  }
}
