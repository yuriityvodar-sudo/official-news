import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/article.dart';
import '../../core/news_widgets.dart';
import '../../core/theme.dart';

/// Kickoff placeholder in the agreed look: publisher, decision type, serif
/// headline and summary. Item 4 replaces it with the real article screen
/// (image, share, "Read the official decision").
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: CupertinoNavigationBar(
        backgroundColor: scheme.surface,
        border: null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          PublisherLine(article),
          const SizedBox(height: 16),
          KindLabel(article),
          Text(article.headline, style: text.articleHeadline),
          const SizedBox(height: 10),
          Text(fullDate(article.publishedAt), style: text.meta),
          const SizedBox(height: 20),
          Text(
            article.originalLanguage == 'en'
                ? 'Summary by AI'
                : 'Summary by AI · original in ${article.originalLanguage.toUpperCase()}',
            style: text.meta,
          ),
          const SizedBox(height: 8),
          Text(
            article.summary ?? article.shortSummary ?? 'No summary yet.',
            style: text.body,
          ),
          const SizedBox(height: 24),
          SelectableText(article.originalUrl, style: text.meta),
        ],
      ),
    );
  }
}
