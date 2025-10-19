import 'package:flutter/material.dart';
import '../services/keycloak_service.dart';
import 'voice_call_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _isInitializing = true;
  String _statusMessage = 'Initializing authentication...';
  
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;
  late AnimationController _logoController;
  late Animation<double> _logoAnimation;

  @override
  void initState() {
    super.initState();
    
    _glowController = AnimationController(
      duration: Duration(seconds: 3),
      vsync: this,
    )..repeat();
    
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _glowController,
      curve: Curves.easeInOut,
    ));
    
    _logoController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _logoAnimation = CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    );
    
    _logoController.forward();
    _initializeAuth();
  }

  @override
  void dispose() {
    _glowController.dispose();
    _logoController.dispose();
    super.dispose();
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
        _statusMessage = 'Ready to connect';
      });
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _statusMessage = 'Setup failed: $e';
      });
    }
  }

  Future<void> _login() async {
    // Don't allow login if not initialized
    if (!_authService.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please wait, initializing...'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Wiring up...';
    });

    try {
      final success = await _authService.login();
      
      if (success) {
        _navigateToVoiceCall();
      } else {
        setState(() {
          _statusMessage = 'Connection failed';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Animated OZZU Logo with glow effect
                AnimatedBuilder(
                  animation: _logoAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _logoAnimation.value,
                      child: AnimatedBuilder(
                        animation: _glowAnimation,
                        builder: (context, child) {
                          return Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.4 * _glowAnimation.value),
                                  blurRadius: 50,
                                  spreadRadius: 20,
                                ),
                                BoxShadow(
                                  color: Colors.cyan.withOpacity(0.2 * _glowAnimation.value),
                                  blurRadius: 80,
                                  spreadRadius: 30,
                                ),
                              ],
                            ),
                            child: Text(
                              'OZZU',
                              style: TextStyle(
                                fontSize: 88,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: 12,
                                shadows: [
                                  Shadow(
                                    color: Colors.blue.withOpacity(0.8),
                                    blurRadius: 20,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                
                SizedBox(height: 60),
                
                // Status message
                Text(
                  _statusMessage,
                  style: TextStyle(
                    fontSize: 18,
                    color: _isInitializing ? Colors.orange : Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                SizedBox(height: 80),
                
                // Wire Up! Button
                if (!_isInitializing && !_authService.isAuthenticated)
                  Container(
                    width: double.infinity,
                    height: 70,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        side: BorderSide(
                          color: Colors.blue,
                          width: 2,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(35),
                        ),
                      ).copyWith(
                        overlayColor: WidgetStateProperty.all(
                          Colors.blue.withOpacity(0.1),
                        ),
                      ),
                      child: AnimatedBuilder(
                        animation: _glowAnimation,
                        builder: (context, child) {
                          return Container(
                            decoration: _isLoading ? null : BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blue.withOpacity(0.3 * _glowAnimation.value),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: _isLoading 
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      SizedBox(width: 16),
                                      Text(
                                        'Wiring up...',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 2,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    'Wire Up!',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 3,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                
                // Loading indicator for initialization
                if (_isInitializing) 
                  Container(
                    width: double.infinity,
                    height: 70,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.orange.withOpacity(0.5),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(35),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.orange,
                            ),
                          ),
                          SizedBox(width: 16),
                          Text(
                            'Preparing...',
                            style: TextStyle(
                              fontSize: 20,
                              color: Colors.orange,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                SizedBox(height: 60),
                
                // Minimal connection info at bottom
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _authService.isInitialized ? Colors.green : Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            _authService.isInitialized ? 'Ready' : 'Initializing',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
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