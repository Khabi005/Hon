import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/parser.dart' as html_parser;
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/reading_progress.dart';
import '../../../core/utils/epub_parser.dart';
import '../../../shared/widgets/ornate_divider.dart';
import '../sheets/themes_settings_sheet.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;

  const ReaderScreen({
    super.key,
    required this.book,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  bool _showControls = true;
  bool _isLoading = true;
  String? _errorMessage;

  List<EpubChapterItem> _chapters = [];
  int _currentChapterIndex = 0;
  int _currentPageIndex = 0;
  int _totalPages = 691; // Default estimate or calculated

  late PageController _pageController;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _scrollController = ScrollController();
    _loadBookContent();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadBookContent() async {
    try {
      final savedProgress = DatabaseService.instance.getProgress(widget.book.id);
      if (savedProgress != null) {
        _currentPageIndex = savedProgress.pageIndex;
        _totalPages = savedProgress.totalPages > 0 ? savedProgress.totalPages : 691;
      }

      // Check if file is EPUB
      if (widget.book.format == BookFormat.epub) {
        File? file;
        if (widget.book.filePath != null) {
          if (widget.book.filePath!.startsWith('assets/')) {
            // For fixture assets, write to temp staging to parse
            final bytes = await rootBundle.load(widget.book.filePath!);
            final tempFile = File('${Directory.systemTemp.path}/${widget.book.id}.epub');
            await tempFile.writeAsBytes(bytes.buffer.asUint8List());
            file = tempFile;
          } else {
            file = File(widget.book.filePath!);
          }
        }

        if (file != null && file.existsSync()) {
          final metadata = await EpubParser.parse(file);
          if (mounted) {
            setState(() {
              _chapters = metadata.chapters;
              _isLoading = false;
            });
            return;
          }
        }
      }

      // Fallback: seed chapters for Pride and Prejudice sample
      _chapters = [
        const EpubChapterItem(
          id: 'ch33',
          title: 'Chapter 33',
          contentHref: 'ch33.xhtml',
          htmlContent: '''
<p>More than once did Elizabeth, in her ramble within the park, unexpectedly meet Mr. Darcy. She felt all the perverseness of the mischance that should bring him where no one else was brought, and, to prevent its ever happening again, took care to inform him at first that it was a favourite haunt of hers. How it could occur a second time, therefore, was very odd! Yet it did, and even a third, did it happen.</p>
<p>It was on the third of these occasions that she was walking near the park palings, when the sound of horses drew her notice, and looking through the fence she saw him riding toward her. He immediately dismounted and leading his horse walked by her side along the path.</p>
<p>Elizabeth was surprised, but answered his civil inquiries with calmness; and they walked on for some minutes in silence, each feeling the awkwardness of the encounter. At last Darcy broke it by asking if she had heard lately from Netherfield.</p>
<p>"I have not heard from Jane for several days," she replied; "she was then quite well."</p>
<p>"My cousin Colonel Fitzwilliam tells me that he had the pleasure of meeting you yesterday."</p>
<p>"He did; we had a very pleasant walk together."</p>
''',
        ),
        const EpubChapterItem(
          id: 'ch40',
          title: 'Chapter 40',
          contentHref: 'ch40.xhtml',
          htmlContent: '''
<p>Elizabeth's impatience to acquaint Jane with what had happened could no longer be overcome; and at length, resolving to suppress every particular in which her sister was concerned, and preparing her to be surprised, she related to her the next morning the chief of the scene between Mr. Darcy and herself.</p>
<p>Miss Bennet's astonishment was soon lessened by the strong sisterly partiality which made any admiration of Elizabeth appear perfectly natural; and all surprise was shortly lost in other feelings. She was sorry that Mr. Darcy should have delivered his sentiments in a manner so little suited to recommend them; but still more was she grieved for the unhappiness which her sister's refusal must have given him.</p>
<p>"His being so sure of succeeding was wrong," said she, "and certainly ought not to have appeared; but consider how much it must have increased his disappointment!"</p>
<p>"Indeed," replied Elizabeth, "I am heartily sorry for him; but he has other feelings which will probably soon drive away his regard for me. You do not blame me, however, for refusing him?"</p>
<p>"Blame you! Oh, no!"</p>
<p>"And you do consider me justified in doing it?"</p>
<p>"Most definitely, upon such grounds."</p>
''',
        ),
      ];

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _saveProgress() {
    final progress = ReadingProgress(
      bookId: widget.book.id,
      chapterIndex: _currentChapterIndex.toDouble(),
      pageIndex: _currentPageIndex,
      totalPages: _totalPages,
      completionPercentage: _currentPageIndex / _totalPages,
      lastReadAt: DateTime.now(),
    );
    DatabaseService.instance.saveProgress(progress);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  List<String> _extractParagraphs(String html) {
    try {
      final doc = html_parser.parse(html);
      final pElements = doc.querySelectorAll('p');
      if (pElements.isNotEmpty) {
        return pElements.map((e) => e.text.trim()).where((t) => t.isNotEmpty).toList();
      }
      return doc.body?.text.split('\n\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList() ?? [];
    } catch (_) {
      return [html];
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPreferencesProvider);
    final themeConfig = prefs.themeConfig;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: themeConfig.systemBrightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: themeConfig.backgroundColor,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              // Main Reading Content Area
              GestureDetector(
                onTap: _toggleControls,
                behavior: HitTestBehavior.opaque,
                child: _buildReaderBody(prefs, themeConfig),
              ),

              // Ambient Top Header Overlay (Fade in/out)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildTopHeader(themeConfig),
              ),

              // Ambient Bottom Bar Overlay (Fade in/out)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildBottomBar(themeConfig),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderBody(ReaderPreferencesState prefs, ReaderThemeConfig themeConfig) {
    if (_isLoading) {
      return Center(
        child: CupertinoActivityIndicator(color: themeConfig.textColor),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Unable to load book: $_errorMessage',
            style: TextStyle(color: themeConfig.textColor),
          ),
        ),
      );
    }

    final chapter = _chapters.isNotEmpty
        ? _chapters[_currentChapterIndex]
        : const EpubChapterItem(
            id: 'demo',
            title: 'Chapter 40',
            contentHref: '',
            htmlContent: '',
          );

    final paragraphs = _extractParagraphs(chapter.htmlContent);

    // Padding calculations matching Apple Books reference
    final topPadding = MediaQuery.of(context).padding.top + 50.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 50.0;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        prefs.horizontalMargin,
        topPadding,
        prefs.horizontalMargin,
        bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          // Chapter Title Header
          Text(
            chapter.title,
            textAlign: TextAlign.center,
            style: HonTypography.chapterTitle(color: themeConfig.textColor),
          ),
          const SizedBox(height: 10),

          // Ornate Apple Books flourish divider
          OrnateDivider(
            color: themeConfig.ornamentColor,
            width: 140,
            height: 22,
          ),
          const SizedBox(height: 28),

          // Paragraphs
          ...paragraphs.map((pText) {
            return Padding(
              padding: EdgeInsets.only(bottom: prefs.paragraphSpacing),
              child: Text(
                pText,
                textAlign: prefs.isJustified ? TextAlign.justify : TextAlign.left,
                style: HonTypography.readerBody(
                  color: themeConfig.textColor,
                  fontSize: prefs.fontSize,
                  lineHeight: prefs.lineHeight,
                  fontFamily: prefs.fontFamily.displayName,
                ),
              ),
            );
          }),
          const SizedBox(height: 48),

          // Chapter Navigation Buttons
          if (_chapters.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentChapterIndex > 0)
                  TextButton.icon(
                    icon: Icon(CupertinoIcons.chevron_left, color: themeConfig.textColor),
                    label: Text(
                      'Previous Chapter',
                      style: TextStyle(color: themeConfig.textColor),
                    ),
                    onPressed: () {
                      setState(() {
                        _currentChapterIndex--;
                        _scrollController.jumpTo(0);
                      });
                      _saveProgress();
                    },
                  )
                else
                  const SizedBox.shrink(),
                if (_currentChapterIndex < _chapters.length - 1)
                  TextButton.icon(
                    label: Text(
                      'Next Chapter',
                      style: TextStyle(color: themeConfig.textColor),
                    ),
                    icon: Icon(CupertinoIcons.chevron_right, color: themeConfig.textColor),
                    onPressed: () {
                      setState(() {
                        _currentChapterIndex++;
                        _scrollController.jumpTo(0);
                      });
                      _saveProgress();
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildTopHeader(ReaderThemeConfig themeConfig) {
    final topSafe = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.fromLTRB(16, topSafe + 8, 16, 8),
      color: themeConfig.backgroundColor.withOpacity(0.92),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Location jump back (Reference Image 3: "372")
          InkWell(
            onTap: () {
              // Return to previous reading bookmark
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.arrow_counterclockwise,
                    size: 14,
                    color: themeConfig.secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentPageIndex > 0 ? _currentPageIndex : 372}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: themeConfig.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Center: "9 pages left in chapter"
          Text(
            '9 pages left in chapter',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: themeConfig.secondaryTextColor,
            ),
          ),

          // Right: Circular close button ( X )
          IconButton(
            onPressed: () {
              _saveProgress();
              Navigator.of(context).pop();
            },
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: themeConfig.textColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.xmark,
                size: 15,
                color: themeConfig.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ReaderThemeConfig themeConfig) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomSafe + 8),
      color: themeConfig.backgroundColor.withOpacity(0.92),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 40), // Balancer

          // Center: Page indicator (e.g. "395 of 691")
          Text(
            '${_currentPageIndex + 1} of $_totalPages',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: themeConfig.secondaryTextColor,
            ),
          ),

          // Right: Menu icon button to open Themes & Settings sheet
          IconButton(
            onPressed: () => ThemesSettingsSheet.show(context),
            icon: Icon(
              CupertinoIcons.textformat_size,
              color: themeConfig.textColor,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}
