# Bemengede Flutter App — Auth Module

## What's included

This is the **Auth Flow** conversion from your React/Supabase web app to Flutter.

### Files generated

```
lib/
├── main.dart                        # App entry point
├── router.dart                      # GoRouter with all 30+ routes + auth guard
├── utils/
│   └── constants.dart               # Colors, routes, Supabase config
├── models/
│   └── user_profile.dart            # UserProfile model (mirrors React interface)
├── services/
│   └── auth_service.dart            # All auth API calls (Supabase + backend)
├── providers/
│   └── auth_provider.dart           # Riverpod state (mirrors AuthContext.tsx)
└── screens/
    └── auth/
        ├── auth_screen.dart         # Full auth UI (login/signup/OTP/forgot/reset)
        └── widgets/
            ├── role_selector.dart   # Traveler vs Sender role cards
            ├── auth_text_field.dart # Reusable input field with validation
            └── auth_success_card.dart # Success states (email sent, password updated)
```

---

## Setup

### 0. Map API key (required before the map works)

The app uses [Gebeta Maps](https://gebeta.app) (vector tiles via the
`gebeta_gl` package, plus geocoding/directions REST APIs). Copy the example
defines file and fill in your real Gebeta key:

```bash
cp dart_defines.example.json dart_defines.json
# then edit dart_defines.json and set the real GEBETA_API_KEY
```

Run/build with it:

```bash
flutter run --dart-define-from-file=dart_defines.json
```

`dart_defines.json` is git-ignored — never commit it. In CI, set
`GEBETA_API_KEY` as a secret and pass `--dart-define=GEBETA_API_KEY=$KEY`
instead of the file.

### 1. Fill in your credentials

Open `lib/utils/constants.dart` and replace:

```dart
static const supabaseUrl    = 'YOUR_SUPABASE_URL';       // from Supabase dashboard
static const supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY'; // from Supabase dashboard
static const backendUrl     = 'YOUR_BACKEND_URL';         // e.g. https://api.yourapp.com
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Android — deep link setup (for password reset emails)

Add to `android/app/src/main/AndroidManifest.xml` inside `<activity>`:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="io.supabase.bemengede" android:host="login-callback" />
</intent-filter>
```

### 4. iOS — deep link setup

Add to `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>io.supabase.bemengede</string>
    </array>
  </dict>
</array>
```

### 5. Supabase Redirect URL

In your Supabase dashboard → Auth → URL Configuration, add:
```
io.supabase.bemengede://login-callback
```

### 6. Run

```bash
flutter run
```

---

### 7. Apply the database migration (required for auto-expiry to actually work)

`supabase_migration.sql` in the repo root creates two scheduled server-side
jobs via `pg_cron` — one that auto-expires package requests nobody accepted,
one that reports overdue deliveries. Until this is run, expiration only
happens on the client when someone has the app open, which is not reliable.

Run it once:

1. Supabase Dashboard → SQL Editor → New query.
2. Paste the full contents of `supabase_migration.sql`.
3. Run it.

Confirm the jobs are actually scheduled:

```sql
SELECT jobname, schedule, active FROM cron.job;
```

You should see `expire-pending-packages` and `report-overdue-deliveries`,
both `active = true`. Re-running the migration later (e.g. after pulling
updates) is safe — `cron.schedule()` upserts by job name.

---

## Auth flow mapping (React → Flutter)

| React                        | Flutter                              |
|------------------------------|--------------------------------------|
| `AuthContext.tsx`            | `auth_provider.dart` (Riverpod)      |
| `AuthService` (inline)       | `auth_service.dart`                  |
| `Auth.tsx` (all 5 modes)     | `auth_screen.dart`                   |
| `useAuth()` hook             | `ref.watch(authProvider)`            |
| `react-router-dom`           | `go_router`                          |
| `@supabase/supabase-js`      | `supabase_flutter`                   |
| Zod validation               | `TextFormField` validators           |
| `toast()`                    | `ScaffoldMessenger.showSnackBar()`   |

---

## Next steps

The router has placeholder screens for all 30+ routes. Tell me which section
to convert next:
- **Traveler** screens (dashboard, trips, packages, offers)
- **Sender** screens (dashboard, create delivery, tracking)
- **Admin** screens (dashboard, users, KYC, disputes)
- **Shared components** (bottom nav, notifications, chat)
