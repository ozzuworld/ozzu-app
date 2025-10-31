import 'package:flutter/material.dart';
import 'services/keycloak_service.dart';
import 'screens/login_screen.dart';
import 'screens/voice_call_screen.dart';

void main() {
  runApp(OzzuApp());
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
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isInitializing = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      print('🚀 Initializing OZZU App...');
      await _authService.initialize();
      setState(() {
        _isInitializing = false;
      });
      print('✅ App initialization completed');
    } catch (e) {
      print('❌ App initialization failed: $e');
      setState(() {
        _isInitializing = false;
        _errorMessage = 'Failed to initialize app: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_authService.isAuthenticated) {
      return const VoiceCallScreen(startUnmuted: true);
    } else {
      return const LoginScreen();
    }
  }
}
