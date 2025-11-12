import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../services/keycloak_service.dart';
import '../main.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback? onLoggedIn;
  const WelcomeScreen({super.key, this.onLoggedIn});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isAnimating = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    // Initially display the static frame
    _controller.value = 0.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_isAnimating || _isLoggedIn) return; // Prevent double tap & replay
    final auth = AuthService();
    try {
      if (!auth.isAuthenticated) {
        debugLogger.i('🔑 WelcomeScreen: Starting login');
        await auth.login();
      }
      setState(() => _isLoggedIn = true);
      // Play animation once
      setState(() => _isAnimating = true);
      await _controller.animateTo(1.0, duration: const Duration(seconds: 3));
      // After animation completes
      widget.onLoggedIn?.call();
    } catch (e) {
      debugLogger.e('❌ WelcomeScreen: Login failed', error: e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e'), backgroundColor: Colors.red.shade900),
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
          onTap: _handleLogin,
          child: Lottie.asset(
            'assets/lottie/login-button.json',
            controller: _controller,
            onLoaded: (composition) {
              _controller.duration = composition.duration;
              if (!_isAnimating) {
                // Show first frame for static state
                _controller.value = 0.0;
              }
            },
            repeat: false,
            width: 200,
            height: 200,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
