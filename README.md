# Asthma Guard

Asthma Guard is a Flutter prototype for viewing air-quality information in an asthma-support context. The current version demonstrates a dashboard, location permission flow, and local caching. It is not connected to a live air-quality service.

## Current prototype

- **Home dashboard:** displays an AQI-style value, a simple risk label, its timestamp, and a location scope.
- **Mock readings:** values are generated locally to demonstrate updates; they are not measurements from an environmental monitoring service.
- **Location:** the dashboard can request device location and display approximate coordinates. It also supports a default/manual location scope when location is unavailable or denied.
- **Local cache:** the latest reading, timestamp, and location scope are stored on the device using shared preferences.
- **Other sections:** Diary, Insights, and Profile are currently placeholder screens.

This prototype is for demonstration and development only. Its sample readings are not real-time or medically validated and should not be used to make health or treatment decisions.

## Requirements

- Flutter SDK installed and available on your `PATH`.
- A device, emulator, or browser supported by Flutter.

The Dart SDK constraint is specified in [`pubspec.yaml`](pubspec.yaml).

## Run locally

From the project directory:

```sh
flutter pub get
flutter run
```

To run the widget tests:

```sh
flutter test
```

## Project structure

- `lib/` — Flutter application source.
- `test/` — widget tests.
- `web/` — web app entry point, manifest, and icons.

## Notes

- Device location access depends on the platform's location services and permission settings.
- The app currently uses a mock environmental data source. A real service, production data handling, and platform-specific permission configuration would be needed before treating readings as live.
