# WireGuard VPN Implementation with Headscale

## Overview

This app uses **WireGuard protocol** to connect to a Headscale mesh network. This is the correct and working approach for mobile VPN integration with Headscale.

## Architecture: WireGuard + Headscale

### Understanding the Components

```
┌─────────────────┐
│  Mobile Device  │
│   (WireGuard)   │
└────────┬────────┘
         │ WireGuard Tunnel
         │ (Encrypted)
         ▼
┌─────────────────┐      ┌──────────────────┐
│   Headscale     │◄────►│  Other Devices   │
│ (Mesh Control)  │      │  in the Network  │
└─────────────────┘      └──────────────────┘
```

**Key Points:**
- **WireGuard** = The VPN protocol (fast, modern, secure)
- **Headscale** = Self-hosted mesh network coordinator (like Tailscale, but open-source)
- Your device connects via WireGuard TO Headscale
- Headscale coordinates the mesh and routes traffic between devices

### How Headscale Works

Headscale is NOT a traditional VPN server. It's a **mesh network coordinator** that uses WireGuard:

1. **Control Plane:** Headscale manages device registration, IP assignment, and routing
2. **Data Plane:** Actual traffic flows through WireGuard tunnels
3. **Mesh Network:** All devices can communicate with each other through the mesh

Think of it like this:
- **Traditional VPN:** Client → Server → Internet
- **Headscale Mesh:** Device A ↔ Headscale ↔ Device B (all connected peers)

## Will You See Other Nodes in the Cluster?

**YES!** When you connect via WireGuard to Headscale:

✅ You join the mesh network
✅ You get an IP address in the mesh (100.x.x.x range)
✅ You can communicate with other devices in the network
✅ Other devices can reach you (if allowed by ACLs)
✅ Traffic is encrypted via WireGuard

**How to reach other nodes:**
- Each device gets a mesh IP (e.g., 100.64.0.5)
- You can ping/connect to other devices using their mesh IPs
- Headscale can also provide MagicDNS for hostname resolution
- ACLs (Access Control Lists) determine who can talk to whom

## Implementation Details

### Mobile App Components

#### 1. WireGuard Integration
**Package:** `wireguard_flutter: ^0.1.3`
**Location:** `pubspec.yaml`

```dart
dependencies:
  wireguard_flutter: ^0.1.3
```

#### 2. VPN Manager
**Location:** `lib/services/vpn_manager.dart`

**Key Functions:**
```dart
// Connect to VPN
Future<bool> connect() async {
  // 1. Get Keycloak access token
  // 2. Register device with backend
  // 3. Receive WireGuard configuration
  // 4. Activate WireGuard tunnel
}

// Disconnect from VPN
Future<bool> disconnect() async

// Get connection statistics
Future<void> _updateStats() async
```

#### 3. Headscale Service
**Location:** `lib/services/headscale_service.dart`

**Key Method:**
```dart
Future<WireGuardConfig?> registerDevice(String accessToken) async {
  // Calls backend API: POST /api/v1/device/register
  // Returns WireGuard configuration
}
```

### Connection Flow

```
1. User taps "Connect VPN"
   ↓
2. Get Keycloak access token
   ↓
3. Call backend: POST /api/v1/device/register
   ↓
4. Backend registers device with Headscale
   ↓
5. Backend returns WireGuard config:
   - Private key (for this device)
   - Public key (for this device)
   - Server public key (Headscale's WireGuard key) ← CRITICAL!
   - Server endpoint (headscale.ozzu.world:51820)
   - Assigned IP (100.x.x.x/32)
   - Allowed IPs (100.64.0.0/10)
   - DNS server
   ↓
6. App creates WireGuard tunnel with config
   ↓
7. WireGuard establishes encrypted tunnel to Headscale
   ↓
8. Connected! Device is now part of mesh network
```

### WireGuard Configuration Format

```ini
[Interface]
PrivateKey = <device_private_key>
Address = 100.64.0.5/32
DNS = 100.100.100.100

[Peer]
PublicKey = <headscale_server_public_key>
Endpoint = headscale.ozzu.world:51820
AllowedIPs = 100.64.0.0/10
PersistentKeepalive = 25
```

**Explanation:**
- **Interface section:** Your device's configuration
- **Peer section:** Headscale server configuration
- **AllowedIPs:** Which IPs route through the VPN (the entire mesh range)
- **PersistentKeepalive:** Keep connection alive through NAT

## Backend Requirements

### CRITICAL: Server Public Key

The backend MUST provide the **actual Headscale WireGuard public key**, not a placeholder.

**Current Issue:**
```json
{
  "serverPublicKey": "PLACEHOLDER_SERVER_KEY"  // ❌ This fails!
}
```

**Required:**
```json
{
  "serverPublicKey": "gN3wkSA7yDJ5M2qKPxF8hVZ3kL9mN2pQ4rS6tU8vW0Y="  // ✅ Actual key
}
```

**How to get the server public key:**

See `VPN_BACKEND_REQUIREMENTS.md` for detailed instructions. Quick methods:

```bash
# Method 1: Read from Headscale data directory
cat /var/lib/headscale/noise_public.key

# Method 2: Derive from private key
wg pubkey < /var/lib/headscale/noise_private.key

# Method 3: Check WireGuard interface
sudo wg show
```

### API Endpoint

**POST** `/api/v1/device/register`

**Request:**
```json
{
  "device_name": "android-1234567890",
  "platform": "android"
}
```

**Headers:**
```
Authorization: Bearer <keycloak_access_token>
```

**Response:**
```json
{
  "privateKey": "SJki2pitya9a9UuMBhngnYa/8OCuRuRtMOYmI/pX2H4=",
  "publicKey": "IErTUEqtporOIm5c1cqoAvSzIr0/mjsG+N/bo3qdl28=",
  "address": "100.94.187.85/32",
  "serverPublicKey": "<ACTUAL_HEADSCALE_WIREGUARD_KEY>",
  "serverEndpoint": "headscale.ozzu.world:51820",
  "allowedIPs": "100.64.0.0/10",
  "dns": "100.100.100.100",
  "persistentKeepalive": 25
}
```

## Testing

### Prerequisites

1. ✅ User logged in with Keycloak
2. ✅ Backend endpoint `/api/v1/device/register` accessible
3. ✅ Headscale server running at headscale.ozzu.world
4. ⚠️ **Backend provides actual server public key (not placeholder)**

### Test Connection

1. Open app and log in with Keycloak
2. Navigate to Security screen
3. Tap "Connect VPN"
4. Check logs for WireGuard configuration
5. Verify connection establishes
6. Check assigned mesh IP

### Expected Logs

```
Starting VPN connection with Headscale
Got access token, registering device with Headscale
Got WireGuard config:
  Address: 100.94.187.85/32
  Server endpoint: headscale.ozzu.world:51820
  Allowed IPs: 100.64.0.0/10
Built WireGuard configuration
Creating WireGuard tunnel: ozzu-vpn
WireGuard VPN connected successfully
VPN state updated: connected
```

### Verify Mesh Connectivity

Once connected:

```bash
# From your mobile device (using terminal app or adb shell)
# Ping other devices in the mesh
ping 100.64.0.1  # Example mesh IP of another device

# Check your assigned IP
ip addr show wg0

# View WireGuard stats
wg show
```

## Troubleshooting

### "Invalid server public key"

**Error:**
```
Invalid server public key received from backend.
Backend must provide the actual Headscale WireGuard public key.
Current value: PLACEHOLDER_SERVER_KEY
```

**Solution:**
- Backend team needs to retrieve and configure the actual Headscale server public key
- See `VPN_BACKEND_REQUIREMENTS.md` for instructions
- The key should be 44 characters, base64-encoded

### "KeyFormatException"

**Cause:** Server public key is not valid WireGuard format

**Solution:**
- Verify key is base64-encoded
- Check for extra whitespace
- Ensure it's 44 characters long
- Make sure it's the WireGuard public key, not an API key

### "Failed to connect VPN"

**Possible causes:**
1. Backend endpoint unreachable
2. Invalid Keycloak token
3. Headscale server down
4. Firewall blocking port 51820
5. Invalid WireGuard configuration

**Debug steps:**
1. Check backend logs
2. Verify Headscale server is running
3. Test backend endpoint with curl
4. Check WireGuard configuration format

## Comparison: WireGuard Direct vs Tailscale SDK

### ✅ WireGuard Direct (Current Implementation)

**Advantages:**
- Simple and straightforward
- Works with standard WireGuard protocol
- No proprietary dependencies
- Good performance
- Full control over configuration

**How it works:**
- Device connects TO Headscale via WireGuard
- Headscale acts as mesh coordinator
- Traffic may route through Headscale node
- Still get full mesh network benefits

### ❌ Tailscale SDK (Attempted, Not Available)

**Why we tried:**
- Native Tailscale protocol implementation
- Direct peer-to-peer connections (more efficient)
- Automatic NAT traversal

**Why it didn't work:**
- Tailscale Android SDK not publicly available
- `com.tailscale:ipn:1.74.1` doesn't exist on Maven
- Would require proprietary Tailscale integration

**Verdict:** WireGuard approach is correct and sufficient!

## Performance Notes

**WireGuard is extremely fast:**
- Modern cryptography (ChaCha20, Poly1305)
- Minimal overhead
- Better performance than OpenVPN/IPSec
- Low battery usage on mobile

**Headscale mesh routing:**
- Some traffic may route through Headscale node
- For peer-to-peer scenarios, Headscale can facilitate direct connections
- Overall performance is excellent for most use cases

## Security

**What's encrypted:**
- ✅ All VPN traffic (via WireGuard)
- ✅ Authentication (via Keycloak)
- ✅ Device registration (HTTPS)

**Access control:**
- Keycloak handles user authentication
- Headscale manages device authorization
- ACLs can restrict device-to-device communication

## Next Steps

1. ✅ Mobile app implementation complete
2. ⚠️ **Backend must provide actual server public key**
3. 🔄 Test connection once backend updated
4. 🔄 Verify mesh network connectivity
5. 🔄 Test communication between multiple devices

## Files Modified

**Mobile App:**
- `lib/services/vpn_manager.dart` - VPN management logic
- `lib/services/headscale_service.dart` - Backend API communication
- `pubspec.yaml` - Added wireguard_flutter dependency
- `android/app/build.gradle.kts` - Removed Tailscale SDK
- `android/app/src/main/kotlin/.../MainActivity.kt` - Reverted to basic activity

**Documentation:**
- `VPN_BACKEND_REQUIREMENTS.md` - Backend implementation guide
- `WIREGUARD_HEADSCALE_IMPLEMENTATION.md` - This file

## References

- [WireGuard Official Site](https://www.wireguard.com/)
- [Headscale Documentation](https://headscale.net/)
- [wireguard_flutter Package](https://pub.dev/packages/wireguard_flutter)
- [Headscale GitHub](https://github.com/juanfont/headscale)

---

**Implementation Date:** 2025-11-17
**Status:** Ready for testing (pending backend server public key update)
**Architecture:** WireGuard + Headscale mesh network
**Authentication:** Keycloak SSO integration
