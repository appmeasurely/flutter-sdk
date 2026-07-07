# AppMeasurely Flutter SDK

Mobile attribution and analytics tracking for Flutter apps. Works on iOS and Android.

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  appmeasurely:
    git:
      url: https://github.com/appmeasurely/flutter-sdk.git
      ref: v1.0.0
```

Then run:
```bash
flutter pub get
```

---

## Quick Start

### Step 1 — Initialize in main.dart

```dart
import 'package:appmeasurely/appmeasurely.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppMeasurely.init('YOUR_APP_KEY');
  runApp(MyApp());
}
```

### Step 2 — Track Custom Events

```dart
// Simple event
await AppMeasurely.trackEvent('level_complete');

// Event with properties
await AppMeasurely.trackEvent('purchase_initiated', properties: {
  'product_id': 'gold_pack',
  'price': 4.99,
  'currency': 'USD',
});
```

### Step 3 — Track Revenue

```dart
await AppMeasurely.trackRevenue(9.99, currency: 'USD');
await AppMeasurely.trackRevenue(4.99,
  currency: 'USD',
  eventName: 'subscription_monthly',
);
```

---

## What's Tracked Automatically

| Event | Description |
|-------|-------------|
| `install` | Fired once on first app launch |
| `app_open` | Fired on every subsequent launch |
| `session_start` | When app resumes |
| `session_end` | When app pauses (includes duration) |

---

## Advanced Options

```dart
await AppMeasurely.init(
  'YOUR_APP_KEY',
  debug: true, // Enable console logging
);
```

## Set User Properties

```dart
AppMeasurely.setUserProperty('user_type', 'premium');
AppMeasurely.setUserProperty('account_age_days', 30);
```

---

## Get Your App Key

1. Log in to your [AppMeasurely dashboard](https://app.appmeasurely.com)
2. Go to **SDK Docs** in the left sidebar
3. Select your app from the dropdown
4. Copy your App Key

---

## Support

- Documentation: [appmeasurely.com/docs](https://appmeasurely.com/docs)
- Email: support@appmeasurely.com
