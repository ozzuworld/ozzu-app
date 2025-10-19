import 'package:flutter/material.dart';
import 'services/keycloak_service.dart';
import 'screens/login_screen.dart';
import 'screens/voice_call_screen.dart';

void main() {
  runApp(OzzuApp());
}

class OzzuApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OZZU',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
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

class _AuthWrapperState extends State<AuthWrapper>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isInitializing = true;
  String _errorMessage = '';
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _pulseAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      print('🚀 Initializing OZZU App...');
      
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
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // OZZU Logo with glow
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.5 * _pulseAnimation.value),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Text(
                      'OZZU',
                      style: TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 8,
                      ),
                    ),
                  );
                },
              ),
              
              SizedBox(height: 40),
              
              Text(
                'Initializing...',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white70,
                ),
              ),
              
              SizedBox(height: 30),
              
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              
              if (_errorMessage.isNotEmpty) ..[
                SizedBox(height: 40),
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 32),
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 32),
                      SizedBox(height: 12),
                      Text(
                        _errorMessage,
                        style: TextStyle(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isInitializing = true;
                            _errorMessage = '';
                          });
                          _initializeApp();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
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