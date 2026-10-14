import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/router.dart';

/// Kickoff placeholder: a plain list of headlines from the API, to prove the
/// app and the backend talk to each other. Item 3 replaces it with the real feed.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.api});

  final ApiClient? api;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final ApiClient _api = widget.api ?? ApiClient();
  late Future<ArticlesPage> _page = _api.fetchArticles();

  Future<void> _refresh() async {
    final page = _api.fetchArticles();
    setState(() => _page = page);
    await page;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Official News')),
      body: FutureBuilder<ArticlesPage>(
        future: _page,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text("Couldn't load the news. Pull down to retry.\n\n${snapshot.error}"),
              ),
            );
          }
          final items = snapshot.data!.items;
          if (items.isEmpty) {
            return const Center(child: Text('No news yet.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final article = items[index];
                return ListTile(
                  title: Text(article.headline),
                  subtitle: Text('${article.country} · ${article.source.name}'),
                  onTap: () => Navigator.of(context).pushNamed(Routes.detail, arguments: article),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
