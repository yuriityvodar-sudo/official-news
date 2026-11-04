/// API base URL, passed at build time:
/// `flutter run --dart-define=API_URL=https://api.outernews.app`.
/// The default is the local Worker (`npx wrangler dev` in server/). On the
/// Android emulator use `--dart-define=API_URL=http://10.0.2.2:8787`.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8787',
);

/// The team's key for Sandbox purchases in the AI chat, which cost nothing
/// (#146): Roman's own builds have his (Roman, 28 Oct:
/// `--dart-define-from-file=.env` with his app/.env; git ignores it,
/// app/.env.example has the name), and `testflight` builds the TestFlight
/// key, which the TestFlight workflow builds in (Roman and Yurii, 29 Oct).
/// The server answers Sandbox purchases without a key too, App Review's from
/// a `store` build among them, but only up to a cap a day for all of them
/// together; the team's builds are not held to it.
const chatSandboxKey = String.fromEnvironment('CHAT_SANDBOX_KEY');

/// Which build this is: `testflight` for the team's phones, `store` for the
/// build submitted to the App Store, `dev` for a local one; the TestFlight
/// workflow sets it from its `build` choice (#137).
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');
