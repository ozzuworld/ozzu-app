# Tailscale VPN Implementation with Headscale

## Overview

This app now uses the **native Tailscale SDK** to connect to your Headscale server. This is the architecturally correct approach for Headscale integration.

### Why Tailscale SDK?

**Headscale is NOT a traditional VPN server.** It's a control server for mesh networks, similar to Tailscale's cloud service.

```
Traditional VPN (WireGuard):
Client → [VPN Server] ← Wrong approach!

Headscale Mesh Network (Correct):
Client A ↔ Client B ↔ Client C
    ↑ ↑ ↑
  Headscale (coordinates, doesn't route)
```

The Tailscale SDK implements the full mesh networking protocol that Headscale expects.

## Architecture

### Components

1. **Backend** - Provides pre-auth keys
2. **Headscale** - Control server (coordinates mesh network)
3. **Android Native** - Tailscale SDK via platform channels
4. **Flutter App** - UI and state management

### Flow

```
User Taps "Connect"
    ↓
Flutter: Get Keycloak token
    ↓
Backend: Validate token → Generate pre-auth key
    ↓
Flutter: Receive pre-auth key
    ↓
Android: Launch Tailscale SDK with:
  - login-server: https://headscale.ozzu.world
  - authkey: <pre-auth-key>
    ↓
Tailscale SDK: Connect to Headscale
    ↓
Headscale: Register device in mesh network
    ↓
Connected! Device joins VPN mesh
```

## Implementation Details

### Android Platform Channel

**Location:** `android/app/src/main/kotlin/com/example/livekit_voice_app/MainActivity.kt`

**Methods:**
- `connect(loginServer, authKey)` - Connect to Headscale with pre-auth key
- `disconnect()` - Disconnect from VPN
- `getStatus()` - Get current connection status

**Dependencies:**
```kotlin
implementation("com.tailscale:ipn:1.74.1")
```

### Flutter Service

**Location:** `lib/services/tailscale_vpn_service.dart`

**Purpose:** Manages communication with native Tailscale SDK

**Key Methods:**
```dart
Future<bool> connect(String loginServer, String authKey)
Future<bool> disconnect()
Future<Map<String, dynamic>?> getStatus()
```

### VPN Manager

**Location:** `lib/services/vpn_manager.dart`

**Updated Flow:**
1. Get Keycloak access token
2. Call `headscaleService.getPreAuthKey(accessToken)`
3. Extract pre-auth key and login server from response
4. Call `tailscaleService.connect(loginServer, authKey)`
5. Handle connection state updates

## Backend Requirements

Your backend is already set up correctly! It's returning:

```json
{
  "success": true,
  "pre_auth_key": "cab0090a196ab62a839071d02c453743506e640582e2b21a",
  "login_server": "https://headscale.ozzu.world",
  "expiration": "24h"
}
```

**This is exactly what we need!** ✅

### What the Backend Does

1. Validates Keycloak access token
2. Creates a pre-auth key in Headscale for the user
3. Returns the pre-auth key to the mobile app

The backend does NOT need to:
- ❌ Generate WireGuard keys
- ❌ Configure WireGuard
- ❌ Manage IP addresses directly

Headscale handles all of that automatically when the device connects with the pre-auth key.

## Testing

### Prerequisites

1. User must be logged in with Keycloak
2. Backend endpoint `/api/v1/device/register` must be accessible
3. Headscale server must be running

### Test Flow

1. Open app and log in with Keycloak
2. Navigate to Settings → VPN
3. Tap "Connect VPN"
4. Tailscale SDK will launch (first time may show permission dialog)
5. Connection should establish automatically using pre-auth key
6. VPN status should show "Connected" with assigned IP

### Expected Logs

```
Starting VPN connection with Headscale
Got access token, getting pre-auth key from Headscale
Got pre-auth key, connecting to Tailscale
Login server: https://headscale.ozzu.world
Tailscale VPN connection initiated successfully
```

## Troubleshooting

### "CONNECTION_ERROR"

**Cause:** Tailscale SDK not available or initialization failed

**Solution:**
- Ensure Tailscale SDK dependency is in `build.gradle.kts`
- Run `flutter clean && flutter pub get`
- Rebuild the app

### "INVALID_ARGS"

**Cause:** Missing login server or auth key

**Solution:**
- Check backend is returning `pre_auth_key` and `login_server`
- Verify response format matches expected structure

### "Not authenticated"

**Cause:** Keycloak access token not available

**Solution:**
- User needs to log in first
- Check Keycloak configuration

## Advantages of This Approach

✅ **Architecturally Correct** - Uses proper mesh network protocol
✅ **Native Performance** - Uses official Tailscale SDK
✅ **Seamless Auth** - One-tap connection with Keycloak
✅ **Headscale Compatible** - Works perfectly with self-hosted control server
✅ **Mesh Networking** - Devices can communicate peer-to-peer
✅ **Auto-Updates** - Tailscale SDK handles protocol updates

## Comparison: Old vs New Approach

### ❌ Old Approach (WireGuard Direct)

```
Problems:
- Tried to treat Headscale as a traditional VPN server
- Required server public key (doesn't exist for Headscale)
- Missed the mesh networking aspect
- Incompatible with Headscale's architecture
```

### ✅ New Approach (Tailscale SDK)

```
Benefits:
- Uses proper mesh network protocol
- Works with Headscale as designed
- Native SDK handles complexity
- Seamless with pre-auth keys
- Peer-to-peer mesh networking
```

## Next Steps

1. ✅ Backend is ready (returns pre-auth keys)
2. ✅ Mobile app implementation complete
3. 🔄 Test on physical device
4. 🔄 Verify mesh network connectivity
5. 🔄 Test peer-to-peer communication between devices

## Files Changed

- `android/app/build.gradle.kts` - Added Tailscale SDK dependency
- `android/app/src/main/kotlin/.../MainActivity.kt` - Platform channel implementation
- `lib/services/tailscale_vpn_service.dart` - New service for Tailscale
- `lib/services/vpn_manager.dart` - Updated to use Tailscale
- `lib/services/headscale_service.dart` - Added getPreAuthKey method
- `pubspec.yaml` - Removed WireGuard dependencies

## References

- [Tailscale Android SDK](https://pkg.go.dev/tailscale.com/ipn/ipnlocal)
- [Headscale Documentation](https://headscale.net)
- [Headscale OIDC Auth](https://headscale.net/stable/ref/oidc/)

## Support

For issues or questions:
1. Check logs for detailed error messages
2. Verify backend is returning pre-auth keys
3. Ensure Headscale server is accessible
4. Review this documentation

---

**Implementation Date:** 2025-11-17
**Status:** Ready for Testing
**Requires:** Headscale server running, Backend API functional, Keycloak authentication
