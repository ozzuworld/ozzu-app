import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../services/keycloak_service.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback? onLoggedIn;
  const LoginScreen({super.key, this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoggingIn = false;
  bool _showSuccessAnimation = false;

  Future<void> _ensureLogin(BuildContext context) async {
    setState(() {
      _isLoggingIn = true;
    });

    final auth = AuthService();
    
    // If already authenticated, show animation then callback
    if (auth.isAuthenticated) {
      setState(() {
        _showSuccessAnimation = true;
      });
      
      // Wait for animation to play, then callback
      await Future.delayed(const Duration(seconds: 2));
      widget.onLoggedIn?.call();
      return;
    }
    
    // Otherwise, trigger login and then show animation + callback
    try {
      await auth.login();
      
      setState(() {
        _showSuccessAnimation = true;
      });
      
      // Wait for animation to play
      await Future.delayed(const Duration(seconds: 2));
      
      if (widget.onLoggedIn != null) {
        widget.onLoggedIn!();
      }
    } catch (e) {
      setState(() {
        _isLoggingIn = false;
      });
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // "Welcome to Ozzu" text in Audiowide font with silver color
            const Text(
              'Welcome to Ozzu',
              style: TextStyle(
                fontFamily: 'Audiowide',
                fontSize: 32,
                color: Color(0xFFC0C0C0), // Silver color
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 60),
            
            // Show success animation after login, otherwise show button
            if (_showSuccessAnimation)
              SizedBox(
                width: 200,
                height: 200,
                child: Lottie.asset(
                  'assets/lottie/login-button.json',
                  repeat: false,
                ),
              )
            else
              ElevatedButton(
                onPressed: _isLoggingIn ? null : () => _ensureLogin(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoggingIn
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('Continue'),
              ),
          ],
        ),
      ),
    );
  }
}
