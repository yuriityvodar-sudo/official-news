/// API base URL, passed at build time:
/// `flutter run --dart-define=API_URL=https://api.officialnews.workers.dev`.
/// The default is the local Worker (`npx wrangler dev` in server/). On the
/// Android emulator use `--dart-define=API_URL=http://10.0.2.2:8787`.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8787',
);

/// Opens the AI chat to Sandbox purchases, which cost nothing, on Roman's own
/// builds only (#146, Roman, 28 Oct): `--dart-define-from-file=.env` with his
/// app/.env (git ignores it; app/.env.example has the name). The server
/// answers no Sandbox purchase without it, and builds without it, such as
/// TestFlight's, keep the chat closed (`ChatScreen.opened`).
const chatSandboxKey = String.fromEnvironment('CHAT_SANDBOX_KEY');
