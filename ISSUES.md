# YourPost Known Issues

This file tracks known issues and bugs in the YourPost mail server.

## API Issues

### 1. JWT Authentication — Implemented ✅
- **Status**: Completed
- **Location**: `src/api/server.zig`, `src/config.zig`
- **Implementation**:
  - HS256 JWT: `signJwt` / `verifyJwt` in `server.zig` using `std.crypto.auth.hmac.sha2.HmacSha256`
  - `handleAuth` issues real JWTs with `email`, `role`, `exp` (24h) claims
  - All `/api/v1/*` endpoints (except `/api/v1/auth`) require `Authorization: Bearer <token>`
  - Secret configured via `YP_JWT_SECRET` env var (default: `change-me-in-production`)

### 2. RBAC — Implemented ✅
- **Status**: Completed
- **Location**: `src/api/server.zig`, `src/db/global.zig`
- **Implementation**:
  - `role` column in `users` table (default `'user'`), migration on open
  - Admin-only: `GET /api/v1/users`, `POST /api/v1/users`, `PUT /api/v1/users/{email}`, `DELETE /api/v1/users/{email}`
  - User-scoped: `/api/v1/mailboxes/{user}/*` — only the token owner (or admin) may access
  - Returns `403 Forbidden` on role mismatch

### 3. User Management API — Completed ✅
- **Status**: Completed
- **Endpoints**:
  - `GET /api/v1/users` — list users (returns `email`, `role`, `active`, `quota_bytes`)
  - `POST /api/v1/users` — create user with `role` parameter
  - `PUT /api/v1/users/{email}` — update `role`, `quota_bytes`, `active`
  - `DELETE /api/v1/users/{email}` — deactivate user

### 4. API Path Extraction Bug — Fixed ✅
- **Status**: Fixed in commit 6ec5bcf

### 5. Cross-compilation Library Paths — Fixed ✅
- **Status**: Fixed in commit d512eb9

## Open Items

### 6. Token Expiry / Refresh
- **Status**: Open
- **Description**: Tokens expire after 24h with no refresh mechanism. Clients must re-login.
- **Fix Needed**: Add `POST /api/v1/auth/refresh` endpoint that accepts a valid (non-expired) token.

### 7. API Documentation
- **Status**: Open
- **Description**: `yourpost-docs/content/docs/api.md` needs updating for: JWT auth header requirements, RBAC rules, new `PUT /api/v1/users/{email}` endpoint, `role` field in responses.

---

**Last Updated**: 2026-05-04
