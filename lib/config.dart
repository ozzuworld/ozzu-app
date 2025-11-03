// Application Configuration
class AppConfig {
  // LiveKit Server Configuration
  static const String livekitWebsocketUrl = 'wss://livekit.ozzu.world';
  static const String livekitTokenUrl = 'https://api.ozzu.world/token';
  
  // Keycloak Authentication Configuration
  static const String keycloakUrl = 'https://idp.ozzu.world'; // External URL for mobile
  static const String keycloakRealm = 'allsafe';
  static const String keycloakClientId = 'june-mobile-app'; // Different client for mobile
  
  // OAuth Configuration
  static const String oauthRedirectScheme = 'livekit';
  static const String oauthRedirectHost = 'auth';
  static const String oauthRedirectUri = '$oauthRedirectScheme://$oauthRedirectHost';
  
  // Room Configuration
  static const String defaultRoomName = 'ozzu-main';
  
  // Connection Configuration
  static const int connectionTimeout = 30;
  static const int tokenTimeout = 10;
  static const int tokenRefreshThreshold = 30; // seconds before expiry
  
  // Audio Settings
  static const bool startMuted = true;
  static const bool adaptiveStream = true;
  static const bool dynacast = true;
  
  // Development/Debug Settings
  static const bool enableDebugLogs = true;
  static const bool enableKeycloakLogs = true;
}