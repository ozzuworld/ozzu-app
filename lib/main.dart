import 'package:flutter/material.dart';
import 'services/keycloak_service.dart';
import 'screens/login_screen.dart';
import 'screens/voice_call_screen.dart';

void main() {
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
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _authService.initialize();
    setState(() => _initialized = true);

    // If already authenticated, go directly to voice chat.
    if (_authService.isAuthenticated && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VoiceCallScreen(startUnmuted: true)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Show login first; after successful login, navigate to voice chat
    return LoginScreen(onLoggedIn: () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const VoiceCallScreen(startUnmuted: true)),
      );
    });
  }
}
