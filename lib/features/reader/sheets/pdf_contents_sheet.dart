import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/bookmark.dart';

class PdfContentsSheet extends StatefulWidget {
  final String bookId;
  final String bookTitle;
  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onSelectPage;

  const PdfContentsSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    required this.currentPage,
    required this.totalPages,
    required this.onSelectPage,
  });

  static Future<void> show(
    BuildContext context, {
    required String bookId,
    required String bookTitle,
    required int currentPage,
    required int totalPages,
    required ValueChanged<int> onSelectPage,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PdfContentsSheet(
        bookId: bookId,
        bookTitle: bookTitle,
        currentPage: currentPage,
        totalPages: totalPages,
        onSelectPage: onSelectPage,
      ),
    );
  }

  @override
  State<PdfContentsSheet> createState() => _PdfContentsSheetState();
}

class _PdfContentsSheetState extends State<PdfContentsSheet> {
  int _selectedTabIndex = 0; // 0: Bookmarks, 1: Page Grid
  late List<Bookmark> _bookmarks;

  @override
  void initState() {
    super.initState();
    _loadBookmarks();
  }

  void _loadBookmarks() {
    setState(() {
      _bookmarks = DatabaseService.instance.getBookmarks(widget.bookId);
    });
  }

  Future<void> _deleteBookmark(Bookmark bm) async {
    await DatabaseService.instance.removeBookmark(bm.bookId, bm.pageIndex);
    _loadBookmarks();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 36),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.bookTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Page ${widget.currentPage} of ${widget.totalPages}',
                        style: TextStyle(
                          fontSize: 12,
                          color: subtextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.check_mark_circled_solid, size: 28),
                  color: isDark ? Colors.white70 : Colors.black87,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),

          // iOS 18 Segmented Pill Tabs
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            height: 34,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              children: [
                _buildSegmentItem('Bookmarks', 0, isDark),
                _buildSegmentItem('Page Grid', 1, isDark),
              ],
            ),
          ),

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.black12,
          ),

          // Body
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildBookmarksList(textColor, subtextColor, isDark)
                : _buildPageGrid(textColor, subtextColor, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String title, int index, bool isDark) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarksList(Color textColor, Color subtextColor, bool isDark) {
    if (_bookmarks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.bookmark,
                size: 48,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
              const SizedBox(height: 14),
              Text(
                'No Bookmarks Saved',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap the bookmark button in the top bar to save pages for quick reference.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: subtextColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      itemCount: _bookmarks.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
      ),
      itemBuilder: (context, index) {
        final bm = _bookmarks[index];
        final isCurrent = bm.pageIndex == widget.currentPage;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFF007AFF).withOpacity(0.15)
                  : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.bookmark_fill,
              size: 18,
              color: isCurrent ? const Color(0xFF007AFF) : subtextColor,
            ),
          ),
          title: Text(
            bm.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent ? const Color(0xFF007AFF) : textColor,
            ),
          ),
          subtitle: Text(
            'Page ${bm.pageIndex} of ${widget.totalPages}',
            style: TextStyle(
              fontSize: 12,
              color: subtextColor,
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            onPressed: () => _deleteBookmark(bm),
          ),
          onTap: () {
            widget.onSelectPage(bm.pageIndex);
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Widget _buildPageGrid(Color textColor, Color subtextColor, bool isDark) {
    if (widget.totalPages <= 0) {
      return Center(
        child: Text(
          'No pages available.',
          style: TextStyle(color: subtextColor),
        ),
      );
    }

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: widget.totalPages,
      itemBuilder: (context, index) {
        final pageNum = index + 1;
        final isCurrent = pageNum == widget.currentPage;
        final isBookmarked = _bookmarks.any((b) => b.pageIndex == pageNum);

        return GestureDetector(
          onTap: () {
            widget.onSelectPage(pageNum);
            Navigator.of(context).pop();
          },
          child: Container(
            decoration: BoxDecoration(
              color: isCurrent
                  ? const Color(0xFF007AFF).withOpacity(0.12)
                  : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isCurrent
                    ? const Color(0xFF007AFF)
                    : (isDark ? Colors.white12 : Colors.black12),
                width: isCurrent ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.doc_text,
                        size: 26,
                        color: isCurrent
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white54 : Colors.black45),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$pageNum',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w600,
                          color: isCurrent
                              ? const Color(0xFF007AFF)
                              : textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isBookmarked)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(
                      CupertinoIcons.bookmark_fill,
                      size: 14,
                      color: Color(0xFF007AFF),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
