/// English names for the languages of the sources (docs/sources.csv).
const _names = {
  'ar': 'Arabic',
  'de': 'German',
  'en': 'English',
  'es': 'Spanish',
  'fr': 'French',
  'hi': 'Hindi',
  'id': 'Indonesian',
  'it': 'Italian',
  'ja': 'Japanese',
  'ko': 'Korean',
  'pl': 'Polish',
  'pt': 'Portuguese',
  'ru': 'Russian',
  'tr': 'Turkish',
  'uk': 'Ukrainian',
  'zh': 'Chinese',
};

/// "German" for "de"; an unknown code is shown in capitals, as it is.
String languageName(String code) => _names[code] ?? code.toUpperCase();
