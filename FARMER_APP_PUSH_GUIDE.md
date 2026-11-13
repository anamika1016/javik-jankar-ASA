# Farmer App — Push Notifications (Android handover)

Give this file to the Android developer. The login and feed endpoints are in
**FARMER_APP_LOGIN_API.md**; this covers only push.

**What should happen:** an admin publishes news or a video on the web for a
state → every farmer of that state who is logged in on the app gets a
notification → tapping it opens that item.

---

## Before anything works — two things must be true

| | Who does it | How to check |
|---|---|---|
| 1. Firebase credentials on the server | Server admin | `rake farmer_push:status` prints `Firebase configured : yes` |
| 2. The app registers its FCM token after login | Android developer | Same command shows `Registered devices` above 0 |

If either is missing, publishing still works — the web list just shows why
nothing was sent. **Nothing is sent silently.**

---

## Part 1 — Server setup (one time)

In the Firebase console: **Project settings → Service accounts → Generate new
private key**. That downloads a `.json` file.

Copy that file onto the production server and point the app at it:

```bash
sudo mkdir -p /etc/asa
sudo cp kishan-6817f-firebase-adminsdk-*.json /etc/asa/fcm-service-account.json
sudo chmod 600 /etc/asa/fcm-service-account.json
sudo chown <the user the app runs as> /etc/asa/fcm-service-account.json
```

Then set, wherever the app's environment is defined:

```bash
FCM_SERVICE_ACCOUNT_FILE=/etc/asa/fcm-service-account.json
FCM_PROJECT_ID=kishan-6817f
```

Pasting the whole JSON into `FCM_SERVICE_ACCOUNT_JSON` works too, but the
file is easier to get right — the key contains newlines that are easy to
mangle in a shell variable.

Restart the app, then:

```bash
rake farmer_push:status
```

The background worker (`bin/jobs`) must also be running — notifications are
sent from a job so publishing never waits on Firebase. If the worker is
stopped, broadcasts stay at **Pending** on the web list.

---

## Part 2 — Android integration

### 2.0 Wire Firebase into the project

`google-services.json` comes from the same Firebase project the server
authenticates against. Both sides must be project **kishan-6817f** — a file
from any other project means the token is issued by a project the server
cannot send to, and nothing arrives with no error anywhere.

1. Put `google-services.json` in the **`app/`** module directory (not the
   project root).

2. Project-level `build.gradle` (or `settings.gradle.kts` plugins block):

   ```groovy
   plugins {
       id("com.google.gms.google-services") version "4.4.2" apply false
   }
   ```

3. App-level `app/build.gradle`:

   ```groovy
   plugins {
       id("com.google.gms.google-services")
   }

   dependencies {
       implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
       implementation("com.google.firebase:firebase-messaging")
   }
   ```

4. `AndroidManifest.xml` — the service that receives messages, and the
   runtime permission Android 13+ needs before a notification can be shown:

   ```xml
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

   <service
       android:name=".FarmerMessagingService"
       android:exported="false">
       <intent-filter>
           <action android:name="com.google.firebase.MESSAGING_EVENT" />
       </intent-filter>
   </service>
   ```

5. Ask for `POST_NOTIFICATIONS` at runtime on Android 13+. Without it the
   message is delivered and silently never displayed — the server will show
   "Sent", so this is an easy one to lose time on.

### 2.1 Register the token after every login

Call this **after** `/api/v1/farmer/login/otp/verify` succeeds.

```
POST https://jj.asaindia.org/api/v1/farmer/devices
Authorization: Bearer <token from verify>
Content-Type: application/json

{
  "fcm_token": "<FCM registration token>",
  "platform": "android",
  "app_version": "1.0.4"
}
```

```kotlin
// After login, and again from onNewToken().
FirebaseMessaging.getInstance().token.addOnSuccessListener { fcmToken ->
    api.registerDevice(
        authorization = "Bearer $sessionToken",
        body = DeviceBody(fcmToken = fcmToken, platform = "android", appVersion = BuildConfig.VERSION_NAME)
    )
}
```

Success:

```json
{
  "success": true,
  "message": "This device will now receive notifications for Madhya Pradesh.",
  "device_id": 12,
  "state": "Madhya Pradesh",
  "state_id": "1"
}
```

| Status | `error` | Meaning |
|---|---|---|
| `422` | `missing_fcm_token` | No token in the body |
| `401` | `missing_token` | No `Authorization` header |
| `401` | `invalid_token` | Session expired — log in again |

### 2.2 Re-register when Firebase rotates the token

```kotlin
class FarmerMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        // Only if a farmer is signed in; otherwise store it and send after login.
        sessionToken()?.let { registerDevice(it, token) }
    }
}
```

Firebase changes the token on reinstall, restore to a new phone, and
occasionally on its own. Miss this and that phone quietly stops receiving.

### 2.3 Unregister on sign-out

```
DELETE https://jj.asaindia.org/api/v1/farmer/devices
Authorization: Bearer <token>

{ "fcm_token": "<FCM registration token>" }
```

Skipping this leaves a shared handset receiving notifications for a farmer
who has logged out.

### 2.4 Handle the message

```json
{
  "notification": { "title": "MP seed subsidy", "body": "Apply by 30 November." },
  "data": {
    "type": "news",
    "id": "12",
    "state_id": "1",
    "deep_link": "farmer://news/12"
  }
}
```

```kotlin
override fun onMessageReceived(message: RemoteMessage) {
    val type = message.data["type"]          // "news" or "video"
    val id = message.data["id"]?.toIntOrNull()
    // Open the item itself, not just the list.
    openScreen(type, id)
}
```

**Every value in `data` is a string** — that is an FCM rule, so parse `id`
rather than expecting a number.

Sent with Android priority `high` and the default sound. Declare the
`POST_NOTIFICATIONS` runtime permission for Android 13+; without it the
notification is delivered but never shown.

---

## Part 3 — Testing it end to end

1. Log in on the app, then check the server:
   ```bash
   rake farmer_push:status
   ```
   `Registered devices` should include the farmer's state.

2. Send a test notification straight to that phone, with no news involved:
   ```bash
   rake 'farmer_push:test[<the fcm token>]'
   ```
   This proves Firebase, credentials and the handset, separately from the
   publishing flow.

3. Publish real news on the web for that farmer's state and watch the
   **Notification** column on **Farmer 360 → Farmer News**.

---

## When a notification does not arrive

Read the **Notification** column first — it names the cause.

| Shown on the web list | What it means | Fix |
|---|---|---|
| **Pending** (stays) | The job never ran | Start the `bin/jobs` worker |
| **Skipped** — "No farmer in this state has the app registered…" | Nobody from that state has registered a token | App is not calling `POST /farmer/devices`, or no farmer of that state has logged in |
| **Failed** — "Firebase is not configured…" | Server credentials missing | Part 1 above |
| **Failed** — "Firebase rejected the server credentials" | Wrong or revoked service account | Generate a new private key |
| **Sent to 0 of 3 devices** | Firebase took it, phones refused | Stale tokens; they are deleted automatically, ask the farmers to reopen the app |
| **Sent**, but nothing on the phone | Delivered but not displayed | `POST_NOTIFICATIONS` permission, battery optimisation, or notification channel |

A post published while **Inactive** is never pushed. Deactivating a post does
not recall a notification already sent — the app is told at send time only.

---

## Endpoint summary

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/api/v1/farmer/devices` | Bearer | Register this phone for notifications |
| `DELETE` | `/api/v1/farmer/devices` | Bearer | Stop notifications for this phone |

Both take the farmer token from `/api/v1/farmer/login/otp/verify`. A staff or
Jeevika Jankar token is rejected.
