# Farmer App — Login API (Android)

Base URL (production): `https://jj.asaindia.org`

A farmer signs in with **either** a mobile number **or** an Aadhaar number.
Either way the OTP is sent **only to the mobile number held in the ASA farmer
register** — never to a number typed into the app. If the register has no
mobile number for that farmer, login is not possible and the API says so.

All requests and responses are JSON. Send `Content-Type: application/json`.

Optional headers, recorded against the login and shown on the web list:

| Header | Example |
|---|---|
| `X-Device-Name` | `Redmi Note 12` |
| `X-App-Version` | `1.0.3` |
| `X-Latitude` | `23.2250491` |
| `X-Longitude` | `74.8512613` |
| `X-Location` | `Bhawanipatna, Odisha` |

Send these on **verify** when the farmer has granted location permission.

**The same values are accepted in the JSON body of the verify request**, which
is usually easier from Android — use whichever suits:

```json
{
  "otp_token": "...",
  "otp": "483921",
  "latitude": 23.2250491,
  "longitude": 74.8512613,
  "location": "Bhawanipatna, Odisha",
  "device_name": "Redmi Note 12",
  "app_version": "1.0.3"
}
```

`lat` / `lng` are accepted as short names. All of it is optional; a value that
is not a number is ignored, and `0,0` is treated as "no fix" rather than as a
place. **If nothing is sent, the web list shows "GPS not shared by app"** —
so if locations are missing there, the app is not sending them.

### Rules the app must build around

- An OTP is valid for **2 minutes**.
- **Resend** is allowed once every **60 seconds**.
- More than **3 wrong OTPs** locks that mobile number for **1 hour**. The
  count is per mobile number, so requesting a new OTP does not reset it.
  A successful login clears it.

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
  "expires_in_seconds": 120,
  "resend_available_in_seconds": 60
}
```

Show `mobile_masked` on the OTP screen so the farmer knows which number to
check. Keep `otp_token` in memory — step 2 needs it.

Failures:

| Status | Body `message` | Meaning |
|---|---|---|
| `422` | `Mobile number or Aadhaar number is required.` | Neither field sent |
| `422` | `Enter a valid 10-digit mobile number starting with 6, 7, 8 or 9.` | Mobile failed validation; the register was not called |
| `404` | `Farmer Not Found` | No such farmer in the register |
| `422` | `This farmer has no valid registered mobile number. Please contact your FCO.` | Register has no usable mobile for them |
| `429` | `An OTP was just sent. Please wait a minute before trying again.` | Resend throttle, 60 s per mobile |
| `423` | `Too many wrong OTP attempts. This mobile number is locked for N more minutes.` | Locked after more than 3 wrong OTPs |
| `422` | `OTP could not be sent. …` | SMS gateway refused |

Disable the **Resend OTP** button for 60 seconds, otherwise it returns `429`.

---

## 2. Resend OTP

```
POST /api/v1/farmer/login/otp/resend
```

```json
{ "otp_token": "<from step 1>" }
```

Same response as step 1, with a **new** `otp_token`. The previous code stops
working immediately, so always verify against the newest token.

The farmer does not have to retype their Aadhaar. If the app has lost the
token, `{ "mobile_no": ... }` or `{ "aadhaar_no": ... }` works too.

Errors are the same as step 1 — in particular `429` before 60 seconds have
passed, and `423` when the number is locked.

Keep the **Resend OTP** button disabled for `resend_available_in_seconds`.

---

## 3. Verify OTP

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
| `OTP has expired. Please request a new one.` | Older than 2 minutes, or superseded by a resend |
| `This OTP has already been used. Please request a new one.` | Already exchanged for a token |
| `Invalid OTP. N attempts left.` | Wrong code; shows how many tries remain before the lock |
| `Too many wrong OTP attempts. This mobile number is locked for N more minutes.` (`423`) | More than 3 wrong codes |
| `OTP and otp_token are required.` (`422`) | A field is missing |

On any of these, send the farmer back to step 1 for a fresh OTP.

---

## 4. Farmer profile

```
GET /api/v1/farmer/me
Authorization: Bearer <token>
```

Returns the same `farmer` block as step 2, plus `detail` — the full register
record (land details, crop production, ICS, ID cards, document URLs). Read
`detail` defensively: the register adds fields over time.

`401 Unauthorized. Please login again.` means the token expired — go to step 1.

---

## 5. Farmer News

```
GET /api/v1/farmer/news
Authorization: Bearer <token>
```

Returns news published for **the farmer's own state plus All States**, newest
first. Nothing from another state is ever included — the server decides this
from the state on the farmer's register record, so the app sends no filter.

```json
{
  "success": true,
  "state": "Madhya Pradesh",
  "news": [
    {
      "id": 12,
      "title": "MP seed subsidy",
      "body": "Apply by 30 November.",
      "link_url": "https://…",
      "image_url": "https://jj.asaindia.org/uploads/farmer_feed/1762…-notice.jpg",
      "state": "Madhya Pradesh",
      "for_all_states": false,
      "published_at": "2026-11-11T10:15:00.000+05:30"
    }
  ]
}
```

`body`, `link_url` and `image_url` may be null. Up to 100 items are returned.

---

## 6. Farmer Videos

```
GET /api/v1/farmer/videos
Authorization: Bearer <token>
```

Same state rule as news.

```json
{
  "success": true,
  "state": "Madhya Pradesh",
  "videos": [
    {
      "id": 4,
      "title": "Soil health",
      "description": "How to read a soil card.",
      "video_url": "https://youtu.be/abc123",
      "thumbnail_url": "https://jj.asaindia.org/uploads/farmer_feed/1762…-thumb.jpg",
      "duration": "4:30",
      "uploaded": false,
      "state": "All States",
      "for_all_states": true,
      "published_at": "2026-11-11T10:15:00.000+05:30"
    }
  ]
}
```

`uploaded: true` means the file is hosted here and `video_url` points at it;
`false` means it is an external link (YouTube and the like). Either way
`video_url` is a full URL the player can open directly.

Both feeds answer `401` with the usual message when the token is missing or
expired — send the farmer back to login.

---

## 7. Logout

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

**Timing.** Step 1 waits on the SMS gateway, so allow up to ~15 s. Verify is
served from cache and returns in milliseconds; a 10 s client timeout is ample.

**Countdown.** Show a 2-minute countdown on the OTP screen and a separate
60-second countdown on the Resend button.

**Retry.** Safe to retry step 1 after the 60 s throttle. Never auto-retry
verify — a repeat of the same OTP returns "already been used", and a wrong
one costs an attempt against the 3-strike lock.

---

## cURL examples

```bash
curl -X POST https://jj.asaindia.org/api/v1/farmer/login/otp/send \
  -H 'Content-Type: application/json' \
  -d '{"mobile_no":"7898071513"}'

curl -X POST https://jj.asaindia.org/api/v1/farmer/login/otp/resend \
  -H 'Content-Type: application/json' \
  -d '{"otp_token":"<token>"}'

curl -X POST https://jj.asaindia.org/api/v1/farmer/login/otp/verify \
  -H 'Content-Type: application/json' \
  -H 'X-Latitude: 23.2250491' -H 'X-Longitude: 74.8512613' \
  -d '{"otp_token":"<token>","otp":"483921"}'

curl https://jj.asaindia.org/api/v1/farmer/me \
  -H 'Authorization: Bearer <token>'
```

---

## Web side

The page opens on **today** and has a calendar to pick any other date, plus
Today / Yesterday / All Dates shortcuts. Every sign-in is kept, so a farmer
shows up under each date they logged in, with that date's own count, time,
method and device. Export Excel follows whatever date and search is applied.

Every successful login appears at **Sidebar → Farmer 360 → Farmer App Logins**
(`/farmer-app-logins`) with name, masked mobile and Aadhaar, whether they
signed in by mobile or Aadhaar, village and district, ICS and Tracenet,
login count, first and last login time, the outcome of the last OTP, and the
device, IP and coordinates the login came from.

The OTP code itself is never stored and never shown — only whether it was
verified, is still awaiting entry, or expired, and how many wrong tries it
took. Storing it would let anyone with access to that page sign in as the
farmer.
