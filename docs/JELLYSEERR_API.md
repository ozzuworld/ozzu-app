# Jellyseerr API Documentation

This document describes the Jellyseerr API endpoints used in the OZZU app.

## Base URL
```
https://requests.ozzu.world
```

## Authentication Endpoints

**IMPORTANT:** All authentication endpoints require the `/api/v1` prefix.

### 1. Local Authentication
**Endpoint:** `POST /api/v1/auth/local`
**Description:** Authenticate using Jellyseerr local account credentials
**Request Body:**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```
**Response:** User object + session cookie
**Error Responses:**
- `403` - Access denied (endpoint may be disabled)

---

### 2. Jellyfin Authentication ⭐ (Used in this app)
**Endpoint:** `POST /api/v1/auth/jellyfin`
**Description:** Authenticate using Jellyfin credentials
**Request Body:**
```json
{
  "username": "hadmin",
  "password": "Pokemon123!",
  "hostname": "optional",
  "email": "optional"
}
```
**Response:** User object + session cookie (set-cookie header: `connect.sid=...`)
**Error Responses:**
- `401` - Invalid credentials (`{"message":"INVALID_CREDENTIALS"}`)
- `404` - Endpoint not found (wrong path or Jellyfin auth not enabled)

---

### 3. Plex Authentication
**Endpoint:** `POST /api/v1/auth/plex`
**Request Body:**
```json
{
  "authToken": "plex-token-here"
}
```
**Response:** User object + session cookie

---

### 4. Logout
**Endpoint:** `POST /api/v1/auth/logout`
**Response:**
```json
{
  "status": "ok"
}
```

---

### 5. Current User
**Endpoint:** `GET /api/v1/auth/me`
**Authentication:** Cookie (`connect.sid`) or X-Api-Key header required
**Response:** Currently authenticated User object
**Error Response:**
```json
{
  "message": "cookie 'connect.sid' required",
  "errors": [{"path": "/api/v1/auth/me", "message": "cookie 'connect.sid' required"}]
}
```

---

## Content Discovery Endpoints

### Trending Movies
**Endpoint:** `GET /api/v1/discover/movies/trending`
**Authentication:** Cookie or X-Api-Key header
**Response:**
```json
{
  "results": [
    {
      "title": "Movie Title",
      "posterPath": "/path/to/poster.jpg",
      "backdropPath": "/path/to/backdrop.jpg",
      "overview": "Movie description..."
    }
  ]
}
```

### Trending TV Shows
**Endpoint:** `GET /api/v1/discover/tv/trending`
**Authentication:** Cookie or X-Api-Key header

### Popular Movies
**Endpoint:** `GET /api/v1/discover/movies/popular`
**Authentication:** Cookie or X-Api-Key header

### Popular TV Shows
**Endpoint:** `GET /api/v1/discover/tv/popular`
**Authentication:** Cookie or X-Api-Key header

### Upcoming Movies
**Endpoint:** `GET /api/v1/discover/movies/upcoming`
**Authentication:** Cookie or X-Api-Key header

---

## Media Details Endpoints

### Movie Details
**Endpoint:** `GET /api/v1/movie/{movieId}`
**Authentication:** Cookie or X-Api-Key header

### TV Show Details
**Endpoint:** `GET /api/v1/tv/{tvId}`
**Authentication:** Cookie or X-Api-Key header

---

## Authentication Methods

Jellyseerr supports two authentication methods:

1. **Cookie Authentication** (used in this app)
   - Login via `/auth/jellyfin` generates a session cookie
   - Cookie is automatically included in subsequent requests
   - Cookie format: `connect.sid=xxxxx`

2. **API Key Authentication** (alternative)
   - Generate API key in Settings > General > API Key
   - Include in requests via `X-Api-Key` header

---

## Image URLs

Jellyseerr uses TMDb (The Movie Database) for images:
```
https://image.tmdb.org/t/p/{size}{path}
```

Common sizes:
- `w500` - Medium quality poster/backdrop
- `original` - Full resolution

---

## Notes

- **CORS Issues:** Jellyseerr may have CORS restrictions on web platforms. On web, skip Jellyseerr and use Jellyfin only.
- **Session Management:** Session cookies are stored securely using `flutter_secure_storage`
- **Error Handling:** 403 errors typically indicate wrong credentials or authentication method
