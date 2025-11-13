import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/keycloak_service.dart';
import '../main.dart';

class WelcomeScreen extends StatefulWidget {
  final VoidCallback? onLoggedIn;
  const WelcomeScreen({super.key, this.onLoggedIn});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoggingIn = false;
  bool _showSuccessAnimation = false;

  Future<void> _handleLogin() async {
    if (_isLoggingIn || _showSuccessAnimation) return;
    
    setState(() {
      _isLoggingIn = true;
    });

    final auth = AuthService();
    
    try {
      // If already authenticated, show animation then callback
      if (auth.isAuthenticated) {
        debugLogger.i('✅ WelcomeScreen: Already authenticated');
        setState(() {
          _showSuccessAnimation = true;
        });
        
        await Future.delayed(const Duration(seconds: 2));
        widget.onLoggedIn?.call();
        return;
      }
      
      // Otherwise, trigger login and then show animation + callback
      debugLogger.i('🔑 WelcomeScreen: Starting login');
      await auth.login();
      
      debugLogger.i('✅ WelcomeScreen: Login successful');
      setState(() {
        _showSuccessAnimation = true;
      });
      
      // Wait for animation to play
      await Future.delayed(const Duration(seconds: 2));
      
      widget.onLoggedIn?.call();
      
    } catch (e) {
      debugLogger.e('❌ WelcomeScreen: Login failed', error: e);
      setState(() {
        _isLoggingIn = false;
      });
      
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // "Welcome to Ozzu" text in Audiowide font with silver color
            Text(
              'Welcome to Ozzu',
              style: GoogleFonts.audiowide(
                fontSize: 32,
                color: const Color(0xFFC0C0C0), // Silver color
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 60),
            
            // Show success animation after login, otherwise show lock button
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
              GestureDetector(
                onTap: _isLoggingIn ? null : _handleLogin,
                child: SizedBox(
                  width: 150,
                  height: 150,
                  child: Lottie.asset(
                    'assets/lottie/lock-button.json',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
