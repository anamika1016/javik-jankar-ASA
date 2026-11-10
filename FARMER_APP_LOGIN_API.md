# Farmer App — Login API (Android)

Base URL (production): `https://jj.asaindia.org`

A farmer signs in with **either** a mobile number **or** an Aadhaar number.
Either way the OTP is sent **only to the mobile number held in the ASA farmer
register** — never to a number typed into the app. If the register has no
mobile number for that farmer, login is not possible and the API says so.

All requests and responses are JSON. Send `Content-Type: application/json`.

Optional headers, recorded against the login for the web list:

| Header | Example |
|---|---|
| `X-Device-Name` | `Redmi Note 12` |
| `X-App-Version` | `1.0.3` |

---

## 1. Send OTP

```
POST /api/v1/farmer/login/otp/send
```

Request — send **one** of these:

```json
{ "mobile_no": "7898071513" }
```
```json
{ "aadhaar_no": "123412341234" }
```

Success — `200`:

```json
{
  "success": true,
  "message": "OTP sent to the registered mobile number.",
  "otp_token": "eyJfcmFpbHMiOnsiZGF0YSI6...",
  "mobile_masked": "******1513",
  "expires_in_seconds": 600
}
```

Show `mobile_masked` on the OTP screen so the farmer knows which number to
check. Keep `otp_token` in memory — step 2 needs it.

Failures:

| Status | Body `message` | Meaning |
|---|---|---|
| `422` | `Mobile number or Aadhaar number is required.` | Neither field sent |
| `404` | `Farmer Not Found` | No such farmer in the register |
| `422` | `This farmer has no registered mobile number. Please contact your FCO.` | Register has no mobile for them |
| `429` | `An OTP was just sent. Please wait a minute before trying again.` | Resend throttle, 60 s per mobile |
| `422` | `OTP could not be sent. …` | SMS gateway refused |

Disable the **Resend OTP** button for 60 seconds, otherwise it returns `429`.

---

## 2. Verify OTP

```
POST /api/v1/farmer/login/otp/verify
```

```json
{
  "otp_token": "<from step 1>",
  "otp": "483921"
}
```

Success — `200`:

```json
{
  "success": true,
  "message": "Logged in successfully.",
  "token": "eyJfcmFpbHMiOnsiZGF0YSI6...",
  "farmer": {
    "id": 5,
    "full_name": "Pooja",
    "father_husband_name": "Jay",
    "mobile_masked": "******1513",
    "aadhaar_masked": "XXXX-XXXX-3333",
    "gender": "Female",
    "age": 28,
    "occupation": "Farming",
    "village_name": "Kya K Pass",
    "district_name": null,
    "state_name": null,
    "ics_team_name": "Ma Machna Crop Producer Company Ltd",
    "tracenet_id": "MP2001415600",
    "is_lead_farmer": false,
    "login_count": 3,
    "last_logged_in_at": "2026-11-10T14:15:02.000+05:30"
  }
}
```

Store `token` securely (EncryptedSharedPreferences / Keystore). It is valid
for **30 days**.

Failures — all `401` unless noted:

| `message` | Meaning |
|---|---|
| `Invalid or expired OTP.` | Wrong OTP, or the token is not ours |
| `OTP has expired. Please request a new one.` | Older than 10 minutes |
| `This OTP has already been used. Please request a new one.` | Already exchanged for a token |
| `Too many wrong attempts. Please request a new OTP.` | 5 wrong tries on one OTP |
| `OTP and otp_token are required.` (`422`) | A field is missing |

On any of these, send the farmer back to step 1 for a fresh OTP.

---

## 3. Farmer profile

```
GET /api/v1/farmer/me
Authorization: Bearer <token>
```

Returns the same `farmer` block as step 2, plus `detail` — the full register
record (land details, crop production, ICS, ID cards, document URLs). Read
`detail` defensively: the register adds fields over time.

`401 Unauthorized. Please login again.` means the token expired — go to step 1.

---

## 4. Logout

```
DELETE /api/v1/farmer/logout
Authorization: Bearer <token>
```

Returns `{ "success": true, "message": "Logged out." }`. The token is
stateless, so the app must also delete its stored copy.

---

## Notes for the app

**Token scope.** Farmer tokens work **only** on `/api/v1/farmer/*`. They are
rejected by every Jeevika Jankar and staff endpoint, and those tokens are
rejected here. Do not share one token store between the two apps.

**Aadhaar handling.** Send the Aadhaar only on step 1 and do not persist it on
the device. The server stores only the last four digits plus a one-way hash —
it never keeps the full number.

**Timing.** Step 1 waits on the SMS gateway, so allow up to ~15 s. Step 2 is
served from cache and returns in milliseconds; a 10 s client timeout is ample.

**Retry.** Safe to retry step 1 after the 60 s throttle. Never auto-retry
step 2 — a repeat of the same OTP returns "already been used".

---

## cURL examples

```bash
curl -X POST https://jj.asaindia.org/api/v1/farmer/login/otp/send \
  -H 'Content-Type: application/json' \
  -d '{"mobile_no":"7898071513"}'

curl -X POST https://jj.asaindia.org/api/v1/farmer/login/otp/verify \
  -H 'Content-Type: application/json' \
  -d '{"otp_token":"<token>","otp":"483921"}'

curl https://jj.asaindia.org/api/v1/farmer/me \
  -H 'Authorization: Bearer <token>'
```

---

## Web side

Every successful login appears at **Sidebar → Farmer 360 → Farmer App Logins**
(`/farmer-app-logins`) with name, masked mobile, village, ICS, Tracenet, how
the farmer logged in, login count, and first/last login time.
