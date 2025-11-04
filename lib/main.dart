import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'services/keycloak_service.dart';
import 'screens/welcome_screen.dart';
import 'screens/voice_call_screen.dart';

// Global logger for iOS debugging (visible via device logs)
final Logger debugLogger = Logger(
  printer: PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    printTime: true,
  ),
);

void main() {
  debugLogger.i('🚀 OZZU App Starting - iOS Debug Mode Active');
  runApp(const OzzuApp());
}

class OzzuApp extends StatelessWidget {
  const OzzuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OZZU',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    debugLogger.d('📱 AuthWrapper: Starting initialization...');
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      debugLogger.i('🔑 AuthService: Initializing Keycloak...');
      await _authService.initialize();
      debugLogger.i('✅ AuthService: Initialization complete');
      
      setState(() => _initialized = true);

      // Debug authentication state
      debugLogger.i('🔍 AuthService: Checking authentication status...');
      debugLogger.i('🔍 AuthService: isAuthenticated = ${_authService.isAuthenticated}');
      
      // If already authenticated, go directly to voice chat.
      if (_authService.isAuthenticated && mounted) {
        debugLogger.i('✅ AuthService: User already authenticated - navigating to VoiceCall');
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VoiceCallScreen(startUnmuted: true)),
        );
      } else {
        debugLogger.w('⚠️  AuthService: User not authenticated - showing WelcomeScreen');
      }
    } catch (e, stackTrace) {
      debugLogger.e('❌ AuthService: Initialization failed', error: e, stackTrace: stackTrace);
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      debugLogger.d('⏳ AuthWrapper: Showing loading screen...');
      return Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFFF9A9E), // Light coral pink
                Color(0xFFFAD0C4), // Peachy pink
              ],
            ),
          ),
          child: const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ),
      );
    }
    
    debugLogger.d('🎉 AuthWrapper: Showing WelcomeScreen');
    // Show welcome screen first; after successful login, navigate to voice chat
    return WelcomeScreen(onLoggedIn: () {
      debugLogger.i('🎉 WelcomeScreen: User logged in successfully - navigating to VoiceCall');
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VoiceCallScreen(startUnmuted: true)),
      );
    });
  }
}