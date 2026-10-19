class BrowseRequest {
  final int page;
  final String? filter;
  final String? sort;

  const BrowseRequest({this.page = 1, this.filter, this.sort});
}

class SearchRequest {
  final String query;
  final int page;
  final List<String> genres;

  const SearchRequest({
    required this.query,
    this.page = 1,
    this.genres = const [],
  });
}

class SourceNovelSummary {
  final String id;
  final String title;
  final String? coverUrl;
  final String? author;
  final String? description;
  final List<String> genres;
  final double? rating;

  const SourceNovelSummary({
    required this.id,
    required this.title,
    this.coverUrl,
    this.author,
    this.description,
    this.genres = const [],
    this.rating,
  });
}

class SourcePage {
  final List<SourceNovelSummary> novels;
  final bool hasNextPage;
  final int page;

  const SourcePage({
    required this.novels,
    this.hasNextPage = false,
    this.page = 1,
  });
}

class NovelDetails {
  final String id;
  final String title;
  final String author;
  final String description;
  final String? coverUrl;
  final String status;
  final List<String> genres;
  final List<SourceChapter> chapters;

  const NovelDetails({
    required this.id,
    required this.title,
    this.author = 'Unknown Author',
    this.description = '',
    this.coverUrl,
    this.status = 'Ongoing',
    this.genres = const [],
    this.chapters = const [],
  });
}

class SourceChapter {
  final String id;
  final String title;
  final double index;
  final DateTime? releaseDate;
  final String? url;

  const SourceChapter({
    required this.id,
    required this.title,
    required this.index,
    this.releaseDate,
    this.url,
  });
}

class ChapterContent {
  final String chapterId;
  final String title;
  final String htmlBody;
  final List<String> imageUrls;

  const ChapterContent({
    required this.chapterId,
    required this.title,
    required this.htmlBody,
    this.imageUrls = const [],
  });
}

abstract interface class NovelSource {
  String get id;
  String get name;
  String get baseUrl;
  String get iconUrl;
  bool get isEnabled;

  Future<SourcePage> browse(BrowseRequest request);
  Future<SourcePage> search(SearchRequest request);
  Future<NovelDetails> getNovel(String novelId);
  Future<List<SourceChapter>> getChapters(String novelId);
  Future<ChapterContent> getChapter(String chapterId);
}

class SourceListing {
  final int index;
  final String name;
  final bool incrementing;
  const SourceListing({
    required this.index,
    required this.name,
    required this.incrementing,
  });
}

class SourceControl {
  final int id;
  final String label, group, kind;
  final Object? value;
  final List<String> options;
  const SourceControl({
    required this.id,
    required this.label,
    required this.group,
    required this.kind,
    this.value,
    this.options = const [],
  });
  factory SourceControl.fromMap(Map<dynamic, dynamic> data) => SourceControl(
    id: (data['id'] as num).toInt(),
    label: data['label'] as String? ?? '',
    group: data['group'] as String? ?? '',
    kind: data['kind'] as String? ?? 'TextFilter',
    value: data['value'],
    options: (data['options'] as List? ?? [])
        .map((value) => value.toString())
        .toList(),
  );
}

class SourceCatalogInfo {
  final String baseUrl;
  final List<SourceControl> settings, filters;
  final bool hasSearch;
  final bool searchIncrementing;
  final List<SourceListing> listings;
  const SourceCatalogInfo({
    this.baseUrl = '',
    this.settings = const [],
    this.filters = const [],
    this.hasSearch = true,
    this.searchIncrementing = true,
    this.listings = const [],
  });
}
