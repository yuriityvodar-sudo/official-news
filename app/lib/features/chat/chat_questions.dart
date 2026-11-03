import '../../core/article.dart';
import '../../l10n/app_localizations.dart';

/// The questions the chat suggests about [article] before the first is
/// asked: about a decision, what it means for the reader; about a tick, an
/// event known from its outlets' headlines (#230, the mockup of 3 Nov).
List<String> suggestedQuestions(Article article, AppLocalizations l10n) =>
    article.isTick
    ? [
        l10n.chatSuggestWhatIsKnown,
        l10n.chatSuggestWhyItMatters,
        l10n.chatSuggestWhatNext,
      ]
    : [
        l10n.chatSuggestConcernsMe,
        l10n.chatSuggestWhatChanges,
        l10n.chatSuggestWhatToDo,
      ];

/// The paywall's sample question about [article], asked at once once just
/// bought: the first of [suggestedQuestions].
String firstQuestionOf(Article article, AppLocalizations l10n) =>
    suggestedQuestions(article, l10n).first;
