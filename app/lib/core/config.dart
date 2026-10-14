/// API base URL, passed at build time:
/// `flutter run --dart-define=API_URL=https://api.officialnews.workers.dev`.
/// The default is the local Worker (`npx wrangler dev` in server/). On the
/// Android emulator use `--dart-define=API_URL=http://10.0.2.2:8787`.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8787',
);
