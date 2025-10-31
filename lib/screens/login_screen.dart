import 'package:flutter/material.dart';
import '../services/keycloak_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Minimal placeholder to satisfy const usage; keep your real UI if exists
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text('Login', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}
