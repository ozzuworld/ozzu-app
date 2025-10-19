import 'package:flutter/material.dart';
import '../services/keycloak_service.dart';
import 'voice_call_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isInitializing = true;
  String _statusMessage = 'Initializing authentication...';

  @override
  void initState() {
    super.initState();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    setState(() {
      _isInitializing = true;
      _statusMessage = 'Setting up authentication...';
    });

    try {
      // Ensure AuthService is initialized
      await _authService.initialize();
      
      // Check if already authenticated
      if (_authService.isAuthenticated) {
        _navigateToVoiceCall();
        return;
      }
      
      setState(() {
        _isInitializing = false;
        _statusMessage = 'Ready to login';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _statusMessage = 'Authentication setup failed: $e';
      });
    }
  }

  Future<void> _login() async {
    // Don't allow login if not initialized
    if (!_authService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please wait, initializing...')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Logging in...';
    });

    try {
      final success = await _authService.login();
      
      if (success) {
        _navigateToVoiceCall();
      } else {
        setState(() {
          _statusMessage = 'Login failed';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Login error: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _navigateToVoiceCall() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => VoiceCallScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo/Title Section
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
                
                // App Title
                Text(
                  'LiveKit Voice App',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                
                SizedBox(height: 8),
                
                Text(
                  'Real-time voice communication',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                
                SizedBox(height: 48),
                
                // Status Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(20),
                    child: Column(
                      children: [
                        if (_isInitializing)
                          CircularProgressIndicator()
                        else if (_authService.isAuthenticated)
                          Icon(Icons.check_circle, size: 48, color: Colors.green)
                        else
                          Icon(Icons.login, size: 48, color: Colors.blue),
                        
                        SizedBox(height: 12),
                        
                        Text(
                          _statusMessage,
                          style: TextStyle(
                            fontSize: 16,
                            color: _isInitializing ? Colors.orange : 
                                   _authService.isAuthenticated ? Colors.green : Colors.blue,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                
                SizedBox(height: 32),
                
                // Login Button
                if (!_isInitializing && !_authService.isAuthenticated)
                  Container(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _login,
                      icon: _isLoading 
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(Icons.login, color: Colors.white),
                      label: Text(
                        _isLoading ? 'Signing in...' : 'Sign in with Keycloak',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        padding: EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                
                SizedBox(height: 32),
                
                // Server Info
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Authentication Server:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Realm: ${AuthService.realm}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                      Text(
                        'Client: ${AuthService.clientId}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}