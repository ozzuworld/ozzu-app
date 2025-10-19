import 'package:flutter/material.dart';
import 'services/keycloak_service.dart';
import 'screens/login_screen.dart';
import 'screens/voice_call_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveKit Voice App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
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
      print('🚀 Initializing LiveKit Voice App...');
      
      // Initialize authentication service
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
      return Scaffold(
        backgroundColor: Colors.blue[50],
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blue[600],
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.voice_chat,
                  size: 80,
                  color: Colors.white,
                ),
              ),
              
              SizedBox(height: 32),
              
              Text(
                'LiveKit Voice App',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              
              SizedBox(height: 16),
              
              Text(
                'Initializing...',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
              
              SizedBox(height: 24),
              
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
              ),
              
              // Fixed syntax: use ...[ instead of ..[
              if (_errorMessage.isNotEmpty) ...[
                SizedBox(height: 32),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 32),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.error, color: Colors.red[600]),
                      SizedBox(height: 8),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.red[700]),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isInitializing = true;
                            _errorMessage = '';
                          });
                          _initializeApp();
                        },
                        child: Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Show appropriate screen based on authentication status
    if (_authService.isAuthenticated) {
      return VoiceCallScreen();
    } else {
      return LoginScreen();
    }
  }
}