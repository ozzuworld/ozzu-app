# LiveKit Voice App

A Flutter application for voice chat using LiveKit real-time communication.

## Features

- 🎤 **Voice Chat**: Real-time voice communication using LiveKit
- 🔇 **Mute/Unmute**: Toggle microphone on/off during calls
- 📱 **Cross Platform**: Works on Android, iOS, Web, and Desktop
- 🔐 **Secure Authentication**: Token-based authentication with your LiveKit server
- 🎛️ **Room Management**: Connect/disconnect from voice rooms

## Server Configuration

This app is configured to connect to your LiveKit server:

- **WebSocket URL**: `wss://livekit.ozzu.world`
- **Token Endpoint**: `https://api.ozzu.world/livekit/token`

## Getting Started

### Prerequisites

- Flutter SDK (>=3.9.2)
- Android Studio / Xcode for mobile development
- A running LiveKit server instance

### Installation

1. Clone the repository:
```bash
git clone https://github.com/ozzuworld/livekit_voice_app.git
cd livekit_voice_app
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

### Platform Setup

#### Android
The app is pre-configured with the following permissions in `android/app/src/main/AndroidManifest.xml`:
- `CAMERA`
- `RECORD_AUDIO`
- `INTERNET`
- `ACCESS_NETWORK_STATE`
- `CHANGE_NETWORK_STATE`
- `MODIFY_AUDIO_SETTINGS`
- `BLUETOOTH` (for Bluetooth audio devices)

#### iOS
The app includes the following permissions in `ios/Runner/Info.plist`:
- `NSCameraUsageDescription`
- `NSMicrophoneUsageDescription`
- `UIBackgroundModes` (audio)

## Usage

1. **Launch the App**: Open the app on your device
2. **Connect**: Tap the "Connect" button to join a voice room
3. **Communicate**: Use the mute/unmute button to control your microphone
4. **Disconnect**: Tap "Disconnect" when you're done

## Technical Details

### Dependencies

- `livekit_client: ^2.5.2` - LiveKit Flutter SDK
- `http: ^1.2.2` - HTTP client for token authentication

### Authentication Flow

1. App requests a token from `https://api.ozzu.world/livekit/token`
2. Token is used to authenticate with the LiveKit server
3. Once authenticated, the app joins the voice room

### Token Format

Your server should return tokens in one of these formats:

```json
// Option 1: Direct token string
"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."

// Option 2: Object with token field
{
  "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
}

// Option 3: Object with accessToken field
{
  "accessToken": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9..."
}
```

## Development

### Building

```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release

# iOS build (requires macOS)
flutter build ios --release
```

### Testing

```bash
# Run tests
flutter test

# Check for issues
flutter doctor
```

## Troubleshooting

### Common Issues

1. **Connection Failed**: Check if your LiveKit server is running and accessible
2. **Token Error**: Verify your token endpoint returns valid JWT tokens
3. **Permissions**: Ensure microphone permissions are granted on the device
4. **Network**: Check internet connectivity and firewall settings

### Debug Information

The app displays:
- Connection status
- Number of remote participants
- Server configuration details
- Error messages in snackbars

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is private and proprietary.

## Support

For issues and questions, please create an issue in this repository.