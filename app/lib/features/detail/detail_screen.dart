import 'package:flutter/material.dart';

import '../../core/article.dart';

/// Kickoff placeholder: shows the fields of one article. Item 4 replaces it
/// with the real article detail screen.
class DetailScreen extends StatelessWidget {
  const DetailScreen({super.key, required this.article});

  final Article article;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(article.source.name, style: text.labelLarge),
          const SizedBox(height: 8),
          Text(article.headline, style: text.headlineSmall),
          const SizedBox(height: 16),
          Text(article.summary ?? article.shortSummary ?? 'No summary yet.', style: text.bodyLarge),
          const SizedBox(height: 16),
          SelectableText(article.originalUrl, style: text.bodySmall),
        ],
      ),
    );
  }
}
