import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/article.dart';
import '../../core/news_widgets.dart';
import '../../core/router.dart';
import '../../core/theme.dart';

/// Kickoff placeholder in the agreed look: masthead, "Latest" and a text-only
/// row per article from the API. Item 3 replaces it with the real feed
/// (images, Top stories, day groups).
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
    await page.catchError(
      (_) => const ArticlesPage(items: [], nextCursor: null, top: []),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<ArticlesPage>(
          future: _page,
          builder: (context, snapshot) => CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Pull to refresh works in every state, including error and empty.
              CupertinoSliverRefreshControl(onRefresh: _refresh),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Official News', style: text.masthead),
                      const SizedBox(height: 4),
                      Text(longDay(DateTime.now()), style: text.dateLine),
                      const SizedBox(height: 20),
                      Text('Latest', style: text.section),
                    ],
                  ),
                ),
              ),
              _content(context, snapshot),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AsyncSnapshot<ArticlesPage> snapshot) {
    if (snapshot.connectionState != ConnectionState.done) {
      return const SliverFillRemaining(
        child: Center(child: CupertinoActivityIndicator()),
      );
    }
    if (snapshot.hasError || snapshot.data!.items.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            snapshot.hasError
                ? "Couldn't load the news. Pull down to retry.\n\n${snapshot.error}"
                : 'No news yet.',
            style: NewsText.from(context).meta,
          ),
        ),
      );
    }
    final items = snapshot.data!.items;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) => _ArticleRow(items[index]),
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  const _ArticleRow(this.article);

  final Article article;

  @override
  Widget build(BuildContext context) {
    final text = NewsText.from(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.of(context).pushNamed(Routes.detail, arguments: article),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            KindLabel(article),
            PublisherLine(article),
            const SizedBox(height: 4),
            Text(article.headline, style: text.headline),
            const SizedBox(height: 6),
            Text(timeAgo(article.publishedAt), style: text.meta),
          ],
        ),
      ),
    );
  }
}
