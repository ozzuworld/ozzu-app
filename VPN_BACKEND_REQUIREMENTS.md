# VPN Integration - Backend Requirements

## Overview

The mobile app now implements native VPN functionality using WireGuard protocol and Headscale for network coordination. This document outlines the backend API endpoint that must be implemented for the VPN feature to work.

## Required Backend Endpoint

### Device Registration Endpoint

**Endpoint:** `POST /api/v1/device/register`
**Base URL:** `https://headscale.ozzu.world`

**Purpose:** Register a mobile device with Headscale and return WireGuard configuration for VPN connection.

### Request

**Headers:**
```
Authorization: Bearer <keycloak_access_token>
Content-Type: application/json
```

**Body:**
```json
{
  "device_name": "android-1234567890" | "ios-1234567890",
  "platform": "android" | "ios"
}
```

**Authentication:**
- The request uses the Keycloak access token obtained during user login
- The backend must validate this token with the Keycloak server
- Extract user information from the token (user ID, email, etc.)

### Response

**Success (200 or 201):**
```json
{
  "privateKey": "<wireguard_private_key>",
  "publicKey": "<wireguard_public_key>",
  "address": "100.64.0.X/32",
  "serverPublicKey": "<headscale_server_public_key>",
  "serverEndpoint": "headscale.ozzu.world:51820",
  "allowedIPs": "100.64.0.0/10",
  "dns": "100.100.100.100",
  "persistentKeepalive": 25
}
```

**Alternative field names (both supported):**
```json
{
  "private_key": "...",
  "public_key": "...",
  "ipv4": "100.64.0.X/32",
  "server_public_key": "...",
  "server_endpoint": "...",
  "allowed_ips": "...",
  "persistent_keepalive": 25
}
```

**Error (4xx/5xx):**
```json
{
  "error": "Error message describing what went wrong"
}
```

## Backend Implementation Steps

### 1. Validate Keycloak Token

```python
# Pseudo-code example
def validate_keycloak_token(token):
    # Verify token with Keycloak
    response = requests.get(
        f"{KEYCLOAK_URL}/realms/{REALM}/protocol/openid-connect/userinfo",
        headers={"Authorization": f"Bearer {token}"}
    )

    if response.status_code != 200:
        raise AuthenticationError("Invalid token")

    return response.json()  # Contains user info
```

### 2. Register Device with Headscale

The backend needs to:

1. Generate WireGuard keypair for the device (or have device generate and send public key)
2. Register the device with Headscale using one of these methods:

   **Option A: Pre-Auth Key (Recommended)**
   ```python
   # Create a pre-auth key for this user
   preauth_key = headscale_api.create_preauth_key(
       user=keycloak_user_id,
       reusable=False,
       ephemeral=False
   )

   # Register device with the pre-auth key
   device = headscale_api.register_node(
       key=preauth_key,
       name=device_name,
       user=keycloak_user_id
   )
   ```

   **Option B: Direct API Registration**
   ```python
   # Directly register via Headscale API
   device = headscale_api.register_device(
       user_id=keycloak_user_id,
       device_name=device_name,
       public_key=device_public_key
   )
   ```

### 3. Get WireGuard Configuration

```python
# Retrieve the assigned IP and network configuration
config = headscale_api.get_device_config(device_id)

return {
    "privateKey": device_private_key,
    "publicKey": device_public_key,
    "address": config['ipv4'],
    "serverPublicKey": headscale_server_public_key,
    "serverEndpoint": "headscale.ozzu.world:51820",
    "allowedIPs": "100.64.0.0/10",  # Tailscale IP range
    "dns": "100.100.100.100",  # MagicDNS
    "persistentKeepalive": 25
}
```

## Headscale API Integration

The backend will need to interact with Headscale's API. Key endpoints:

### Create Pre-Auth Key
```http
POST https://headscale.ozzu.world/api/v1/preauthkey
Authorization: Bearer <headscale_api_key>
Content-Type: application/json

{
  "user": "<user_id>",
  "reusable": false,
  "ephemeral": false,
  "expiration": "2025-12-31T23:59:59Z"
}
```

### Register Node
```http
POST https://headscale.ozzu.world/api/v1/machine/register
Content-Type: application/json

{
  "key": "<preauth_key>",
  "name": "<device_name>"
}
```

### Get Node Info
```http
GET https://headscale.ozzu.world/api/v1/node/<node_id>
Authorization: Bearer <headscale_api_key>
```

## Security Considerations

1. **Token Validation:** Always validate the Keycloak access token on every request
2. **User Isolation:** Ensure devices are registered under the correct user namespace
3. **Rate Limiting:** Implement rate limiting to prevent abuse
4. **Key Security:** Private keys should be generated server-side and transmitted over HTTPS only once
5. **Device Limits:** Consider limiting the number of devices per user
6. **Audit Logging:** Log all device registrations for security auditing

## Mobile App Flow

1. User logs into the app with Keycloak (already implemented)
2. User taps "Connect VPN" in the app
3. App calls `/api/v1/device/register` with Keycloak token
4. Backend validates token, registers device with Headscale, returns WireGuard config
5. App configures WireGuard with the received configuration
6. VPN connection is established

## Testing the Integration

### Test Device Registration

```bash
# Get Keycloak access token (from mobile app or test script)
TOKEN="<access_token>"

# Test device registration
curl -X POST https://headscale.ozzu.world/api/v1/device/register \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "device_name": "test-device-12345",
    "platform": "android"
  }'
```

### Expected Response

```json
{
  "privateKey": "YAnz3...",
  "publicKey": "xTIBA...",
  "address": "100.64.0.5/32",
  "serverPublicKey": "gN3wk...",
  "serverEndpoint": "headscale.ozzu.world:51820",
  "allowedIPs": "100.64.0.0/10",
  "dns": "100.100.100.100",
  "persistentKeepalive": 25
}
```

## Alternative: OIDC Registration Flow

If you prefer to use Headscale's built-in OIDC registration instead of the API approach:

1. Device generates WireGuard keypair locally
2. Device initiates registration with Headscale's OIDC endpoint
3. User is redirected to Keycloak (seamlessly authenticated if session exists)
4. Headscale completes registration and returns config

This approach requires more complex implementation in the mobile app and may not provide as seamless an experience.

## Contact

For questions about this implementation, please contact the mobile development team.
