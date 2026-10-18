# BreakTimer

An iOS app for tracking breaks against a daily break budget (default 30 minutes, adjustable from 10 to 120 minutes in 5-minute steps). Users start and end breaks, see how much budget is left, and keep it visible on the Home Screen, the Lock Screen, and in a Live Activity / Dynamic Island. Data is stored on the device first and synced to Supabase. Every user sees only their own data.

- SwiftUI, Swift 6, `@Observable`, async/await. Minimum iOS 17; Liquid Glass on iOS 26+.
- SwiftData in a shared App Group (app and widget extension use the same store).
- WidgetKit (Home Screen and Lock Screen widgets), App Intents (interactive buttons), ActivityKit (Live Activity, no push).
- Supabase (supabase-swift) for email + password auth and offline-first sync.
- German is the development language; English is the second localization.
- Works with a free Apple ID (Xcode "Personal Team").

## Requirements

- Xcode 26 or newer (built and tested with Xcode 27.1). The iOS 26 SDK is needed for Liquid Glass.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- A Supabase project (free tier is fine), plus the [Supabase CLI](https://supabase.com/docs/guides/cli) if you want to deploy from the terminal.

## Project layout

```
project.yml                 XcodeGen spec (never edit the .xcodeproj, it is generated and gitignored)
Configuration/              Base.xcconfig + example files for Config.xcconfig / Signing.xcconfig
Shared/                     Compiled into the app and the widget extension
  Budget/                   BudgetEngine: all budget math, pure Swift, unit-tested
  Logging/                  Log facade, per-process log files, masking, retention
  Model/                    SwiftData model, App Group access
  Breaks/                   BreakController + effects (widgets, notifications, Live Activity)
  Intents/                  Start/End break App Intents (LiveActivityIntent)
  Settings/, UI/            Shared settings, theme, ring
BreakTimer/                 App target (Today, History, Settings, Auth, Support, Services)
BreakTimerWidget/           Widget extension (Home/Lock Screen widgets, Live Activity UI)
BreakTimerTests/            Unit tests (budget engine, email masking, log retention)
supabase/migrations/        SQL migration (tables, trigger, RLS)
supabase/functions/         delete-account Edge Function
scripts/                    String Catalog helper
```

## 1. Configure the project

Create both local config files from the examples. They are gitignored.

```bash
cp Configuration/Config.example.xcconfig Configuration/Config.xcconfig
cp Configuration/Signing.example.xcconfig Configuration/Signing.xcconfig
```

### Config.xcconfig

```
SUPABASE_URL = https:/$()/your-project-ref.supabase.co
SUPABASE_ANON_KEY = your-anon-key
SUPPORT_EMAIL = support@yourcompany.com
```

- Find the URL and the anon (public) key in the Supabase dashboard under **Project Settings → API**. Never put the service-role key into the app.
- xcconfig treats `//` as the start of a comment. That's why the URL is written as `https:/$()/…`. Keep that form.
- The values reach the code through Info.plist keys (`SupabaseURL`, `SupabaseAnonKey`, `SupportEmail`). Without a valid URL and key, the sign-in screen shows a "not configured" notice.

### Signing.xcconfig

```
DEVELOPMENT_TEAM = ABCDE12345
BUNDLE_ID_PREFIX = com.yourname.breaktimer
```

- `DEVELOPMENT_TEAM`: your Personal Team ID. In Xcode open **Settings → Accounts**, select your Apple ID and the "(Personal Team)" entry. Alternatively, pick the team once in a target's **Signing & Capabilities** tab and copy the `DEVELOPMENT_TEAM` value from the build settings.
- `BUNDLE_ID_PREFIX`: a reverse-DNS prefix that's unique to you. Every identifier is derived from it:
  - App: `BUNDLE_ID_PREFIX`
  - Widget extension: `BUNDLE_ID_PREFIX.widget`
  - App Group: `group.BUNDLE_ID_PREFIX` (exposed to code through the `AppGroupIdentifier` Info.plist key)

  **Don't change it after the first install.** A new prefix means a new app with an empty data store.

Both targets use automatic signing and have entitlements files that contain the App Group.

### Generate and open

```bash
xcodegen generate
open BreakTimer.xcodeproj
```

Run `xcodegen generate` again whenever you add or remove files, or change `project.yml`.

## 2. Set up Supabase

1. **Create a project** at [supabase.com](https://supabase.com).
2. **Enable email auth with confirmation**: **Authentication → Sign In / Providers → Email**. Enable the provider, keep **Confirm email** on, and set the minimum password length to 8 (the app requires 8 characters too).
3. **Add the redirect URLs**: under **Authentication → URL Configuration → Redirect URLs**, add
   - `breaktimer://auth-callback` (email confirmation after sign-up)
   - `breaktimer://reset-password` (password reset)

   (or simply `breaktimer://**`). The links in Supabase's emails open the app through this custom URL scheme. Open them on the iPhone that requested them: the app uses the PKCE flow, so a link opened on another device can't finish the sign-in. The email still counts as confirmed, though, and you can sign in normally.
4. **Run the migration** `supabase/migrations/20261018000000_breaktimer_init.sql`, either way:
   - Dashboard: open **SQL Editor**, paste the file and run it, or
   - CLI:
     ```bash
     supabase link --project-ref your-project-ref
     supabase db push
     ```
   This creates `break_sessions` and `user_settings` with row level security, so each user can only select, insert and update their own rows. It also adds a trigger that maintains `updated_at` and enforces "latest `updated_at` wins".
5. **Deploy the delete-account function**:
   ```bash
   supabase functions deploy delete-account --project-ref your-project-ref
   ```
   It verifies the caller's JWT and deletes that user with the service role. Their rows are removed through `ON DELETE CASCADE`. `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are provided to Edge Functions automatically.
6. **Email sending**: Supabase's built-in email service is heavily rate-limited and meant for testing. For real use, configure your own SMTP server under **Authentication → Emails → SMTP Settings**. The default email templates work as they are.

## 3. Run in the Simulator

Select the **BreakTimer** scheme and an iPhone Simulator, then press Run. You can also build from the terminal:

```bash
xcodebuild -project BreakTimer.xcodeproj -scheme BreakTimer -destination 'generic/platform=iOS Simulator' build
```

Run the unit tests (adjust the Simulator name):

```bash
xcodebuild -project BreakTimer.xcodeproj -scheme BreakTimer -destination 'platform=iOS Simulator,name=iPhone 16' test
```

**Trying the app without Supabase**: Debug builds accept the launch argument `-skipAuth` (**Product → Scheme → Edit Scheme → Run → Arguments**). It signs in a local demo account without sync. When you later sign in with a real account, the demo data is cleared.

### Widgets in the Simulator

- **Home Screen**: long-press the Home Screen, tap **Edit → Add Widget**, search for "BreakTimer", and add the small or medium widget. The **Starten** / **Beenden** buttons start and end breaks without opening the app. iOS runs the intents in the app's process.
- **Lock Screen**: lock the Simulator (⌘L), wake it, long-press the Lock Screen, choose **Customize → Lock Screen**, and add the BreakTimer widgets below the clock (or the inline one above it).
- Countdowns and rings animate by themselves (timer-based `Text` and `ProgressView`). The timeline contains entries for "5 minutes left" and "budget used up", so the colors switch to orange and red on time. Widgets reload whenever a break starts or ends, the budget changes, or the appearance changes.
- Widgets show "Melde dich in BreakTimer an." while nobody is signed in.

### Live Activity and Dynamic Island in the Simulator

- Start a break from the app or a widget. The Live Activity starts automatically. The first time, iOS asks whether to allow Live Activities.
- Lock the Simulator (⌘L) to see the Lock Screen banner with countdown, progress bar and **Beenden** button.
- Use a Simulator with a Dynamic Island (iPhone 14 Pro or later). Go to the Home Screen to see the compact presentation, and long-press the island for the expanded one. The minimal presentation appears when another app also shows a Live Activity.
- When the budget runs out, the activity becomes stale and switches to overtime styling ("+m:ss über").
- iOS ends Live Activities after at most 8 hours. That limit is iOS's, not the app's.

### Notifications

Notification permission is requested on the first break started in the app, not at launch. While a break runs, one notification is scheduled at 5 minutes left and one when the budget is used up. Both are rescheduled when the budget or a session changes, and cancelled when the break ends. Both can be turned off in Settings.

### Sending the log to support

**Einstellungen → Support → Protokoll an Support senden** merges `app.log` and `widget.log` by timestamp into `BreakTimer-Log-YYYY-MM-DD-HHmm.txt`, with a diagnostic header.

- **The Mail composer only works on a real iPhone with a Mail account.** In the Simulator, `MFMailComposeViewController.canSendMail()` returns false, so only the fallback can be tested there. The fallback is a share sheet with the file, plus the support address and a copy button.
- The temporary export file is deleted once the sheet closes. Only the fact that a report was sent is logged, never its contents.

## 4. Run on my iPhone (free Apple ID)

1. In Xcode, open **Settings → Accounts**, click **+** and sign in with your Apple ID. A "Personal Team" appears.
2. Put the Personal Team ID into `Configuration/Signing.xcconfig` as `DEVELOPMENT_TEAM`, and set a unique `BUNDLE_ID_PREFIX` (e.g. `com.yourname.breaktimer`). Then run `xcodegen generate`.
3. Connect the iPhone with a cable and unlock it. Tap **Trust** if it asks.
4. On the iPhone, enable **Developer Mode** under **Settings → Privacy & Security → Developer Mode**, and restart when asked.
5. In Xcode, select the BreakTimer scheme and your cabled iPhone as the run destination, then press **Run**. Xcode registers the two App IDs and the App Group for your Personal Team automatically.
6. The first launch fails with an "untrusted developer" message. On the iPhone, open **Settings → General → VPN & Device Management**, select your Apple ID under "Developer App", and tap **Trust**. Then press Run again.

**The 7-day limit**: apps signed with a free account stop launching after 7 days. Connect the iPhone and press **Run** in Xcode again. **Don't delete the app first**: reinstalling over it keeps its data, but deleting it removes the local store.

Only capabilities that a Personal Team supports are used: App Groups, WidgetKit, interactive widgets (App Intents), Live Activities, local notifications and the `breaktimer://` URL scheme. There are exactly two App IDs (app and widget). A free account allows up to 10.

## How it works

### Budget math

`Shared/Budget/BudgetEngine.swift` is pure Swift with no SwiftUI or SwiftData imports, and is unit-tested.

- Time is never counted with a ticking counter. Only start and end timestamps are stored, and everything is derived from `Date()`. That way the app, widgets and Live Activity always agree, even after the app has been killed.
- Daily usage = today's finished sessions + elapsed time of the running one. Remaining = budget − usage, which can go negative (overtime).
- A break that crosses midnight counts toward the day it started.
- A budget change applies immediately to today, including a running break: today's sessions take the new budget. Future days use the new setting. Past days keep the budget stored on their sessions, so the history stays accurate.
- If a break runs for more than 2 hours, the app asks "Pause vergessen zu beenden?" and lets the user set the real end time.

### Sync

SwiftData on the device is the source of truth. A session needs syncing while `syncedAt < updatedAt`. Deletes are soft (`deleted_at`) until they've reached the server.

- **When**: on app foreground, after a break ends or a session is edited or deleted, after a budget change, after sign-in, and with **Jetzt synchronisieren** in Settings.
- **Push**: unsynced sessions are upserted; the budget setting is upserted if it changed.
- **Pull**: the budget setting and the last 30 days of sessions are fetched, so a new phone shows everything after sign-in.
- **Conflicts**: the latest `updated_at` wins. This is enforced by the database trigger on push and by the merge on the device.
- Timestamps are stored in UTC; `day` is the local calendar date of the start time on the device that recorded it.

### Authentication

- Supabase email + password, with sign-up confirmation (check-inbox screen with resend), password reset via a `breaktimer://reset-password` link, password change, sign-out and account deletion.
- The session is stored in the Keychain (supabase-swift's default storage).
- **Sign-out** clears all local break data and settings. The logs stay, because they help with login problems. **Account deletion** calls the Edge Function, then removes all local data including the logs.

### Logging

- Every entry goes to `os.Logger` and to a per-process file in the App Group container: `app.log` for the app, including App Intents (which iOS runs in the app's process), and `widget.log` for the widget extension.
- Line format: `ISO-8601 timestamp with offset | LEVEL | process | category | message`.
- The default level is INFO; **Ausführliche Protokollierung** in Settings enables DEBUG.
- Email addresses are masked (`a***@gmail.com`). Passwords, tokens and keys are never logged, and messages are additionally scrubbed for email addresses and JWTs.
- Retention: on app launch, entries older than 14 days are dropped, and the oldest entries are trimmed so all logs together stay under 2 MB.

### Localization

German (`de`) is the development language: all source strings are German, and English (`en`) is the second localization, both in String Catalogs (`Localizable.xcstrings` in the app and the widget). The Xcode IDE adds new strings to the catalogs automatically when you build. `xcodebuild` doesn't, so after a command-line build run:

```bash
python3 scripts/update_string_catalogs.py
```

This adds missing keys with their English translations (from the table in the script). Users pick the app language in **Einstellungen → Sprache**, which opens BreakTimer's page in iOS Settings.

## Notes

- **UIKit use**: the only UIKit view is the `MFMailComposeViewController` wrapper. Two small UIKit APIs are used besides that, because SwiftUI has no equivalent: `UIPasteboard`, for the copy button in the share fallback, and `UIColor` system colors, through `Color(uiColor:)`.
- **Liquid Glass** (`glassEffect`, glass button styles) is used on iOS 26 and later. Older versions fall back to system materials and colors.
- **Third-party code**: the only dependency is the official `supabase-swift` package. The packages it depends on come with it.
