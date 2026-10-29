/// API base URL, passed at build time:
/// `flutter run --dart-define=API_URL=https://api.officialnews.workers.dev`.
/// The default is the local Worker (`npx wrangler dev` in server/). On the
/// Android emulator use `--dart-define=API_URL=http://10.0.2.2:8787`.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8787',
);

/// Opens the AI chat to Sandbox purchases, which cost nothing, on the team's
/// builds only (#146): Roman's own with his key (Roman, 28 Oct:
/// `--dart-define-from-file=.env` with his app/.env; git ignores it,
/// app/.env.example has the name), and `testflight` builds with the
/// TestFlight key, which the TestFlight workflow builds in (Roman and Yurii,
/// 29 Oct). The server answers no Sandbox purchase without a key, and builds
/// without one, such as `store` ones, keep the chat closed
/// (`ChatScreen.opened`).
const chatSandboxKey = String.fromEnvironment('CHAT_SANDBOX_KEY');

/// Which build this is: `testflight` for the team's phones, `store` for the
/// build submitted to the App Store, `dev` for a local one; the TestFlight
/// workflow sets it from its `build` choice (#137).
const appBuild = String.fromEnvironment('APP_BUILD', defaultValue: 'dev');
