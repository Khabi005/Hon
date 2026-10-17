import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/reading_progress.dart';
import '../sheets/pdf_contents_sheet.dart';
import '../sheets/pdf_appearance_sheet.dart';

class PdfReaderScreen extends StatefulWidget {
  final Book book;
  final int initialPage;

  const PdfReaderScreen({
    super.key,
    required this.book,
    this.initialPage = 1,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  PdfControllerPinch? _pinchController;
  PdfController? _flipController;

  int _currentPage = 1;
  int _pageCount = 0;
  bool _isLoading = true;
  bool _showControls = true;
  String? _errorMessage;
  bool _isUnsupportedPlatform = false;

  PdfColorFilterMode _colorFilterMode = PdfColorFilterMode.original;
  PdfPageViewMode _viewMode = PdfPageViewMode.continuousZoom;

  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    // 1. Platform Check: pdfx uses Android/iOS native pdf renderers; Linux desktop is not supported
    if (Platform.isLinux) {
      if (mounted) {
        setState(() {
          _isUnsupportedPlatform = true;
          _isLoading = false;
          _errorMessage =
              'PDF hardware rendering uses Android native platform services.\nLinux desktop preview is currently unsupported by the native PDF engine.';
        });
      }
      return;
    }

    // 2. Load persisted reader preferences
    final savedFilter = DatabaseService.instance.getPdfColorFilter();
    if (savedFilter == 'sepia') {
      _colorFilterMode = PdfColorFilterMode.sepia;
    } else if (savedFilter == 'inverted') {
      _colorFilterMode = PdfColorFilterMode.inverted;
    } else {
      _colorFilterMode = PdfColorFilterMode.original;
    }

    final savedViewMode = DatabaseService.instance.getPdfPageViewMode();
    if (savedViewMode == 'singlePage') {
      _viewMode = PdfPageViewMode.singlePage;
    } else {
      _viewMode = PdfPageViewMode.continuousZoom;
    }

    // 3. Validate file existence and integrity
    if (widget.book.filePath == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'No file path registered for this PDF.';
        });
      }
      return;
    }

    final file = File(widget.book.filePath!);
    if (!file.existsSync()) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'PDF file not found at:\n${file.path}';
        });
      }
      return;
    }

    if (file.lengthSync() == 0) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'The PDF file is empty (0 bytes) or corrupted.';
        });
      }
      return;
    }

    try {
      // 4. Pre-validate document opening to catch corrupt headers, encryption or format errors
      final testDoc = await PdfDocument.openFile(file.path);
      final docPages = testDoc.pagesCount;
      await testDoc.close();

      if (docPages <= 0) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'The PDF document contains 0 pages.';
          });
        }
        return;
      }

      final saved = DatabaseService.instance.getProgress(widget.book.id);
      final rawPage = widget.initialPage > 0
          ? widget.initialPage
          : (saved != null && saved.pageIndex > 0 ? saved.pageIndex : 1);
      final page = rawPage.clamp(1, docPages);

      if (_viewMode == PdfPageViewMode.continuousZoom) {
        final pinchCtrl = PdfControllerPinch(
          document: PdfDocument.openFile(file.path),
          initialPage: page,
        );
        if (mounted) {
          setState(() {
            _pinchController = pinchCtrl;
            _flipController = null;
            _currentPage = page;
            _pageCount = docPages;
            _isLoading = false;
          });
        }
      } else {
        final flipCtrl = PdfController(
          document: PdfDocument.openFile(file.path),
          initialPage: page,
        );
        if (mounted) {
          setState(() {
            _flipController = flipCtrl;
            _pinchController = null;
            _currentPage = page;
            _pageCount = docPages;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Unable to parse PDF document. The file may be corrupt or encrypted.\n$e';
        });
      }
    }
  }

  void _saveProgress(int page, int pageCount) {
    if (pageCount <= 0) return;
    final clampedPage = page.clamp(1, pageCount);
    if (mounted) {
      setState(() {
        _currentPage = clampedPage;
        _pageCount = pageCount;
      });
    }
    final prog = ReadingProgress(
      bookId: widget.book.id,
      pageIndex: clampedPage,
      totalPages: pageCount,
      completionPercentage: clampedPage / pageCount,
      lastReadAt: DateTime.now(),
    );
    DatabaseService.instance.saveProgress(prog);
  }

  void _goToPage(int page) {
    if (_pageCount <= 0) return;
    final target = page.clamp(1, _pageCount);
    if (_viewMode == PdfPageViewMode.continuousZoom) {
      _pinchController?.animateToPage(pageNumber: target);
    } else {
      _flipController?.animateToPage(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _pageCount) {
      _goToPage(_currentPage + 1);
    }
  }

  void _prevPage() {
    if (_currentPage > 1) {
      _goToPage(_currentPage - 1);
    }
  }

  void _toggleBookmark() async {
    HapticFeedback.lightImpact();
    final added = await DatabaseService.instance.toggleBookmark(
      widget.book.id,
      _currentPage,
      label: 'Page $_currentPage',
    );
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            added
                ? 'Bookmark added for Page $_currentPage'
                : 'Bookmark removed for Page $_currentPage',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _switchViewMode(PdfPageViewMode mode) async {
    if (_isUnsupportedPlatform || Platform.isLinux || _errorMessage != null) return;
    if (widget.book.filePath == null) return;
    final file = File(widget.book.filePath!);
    if (!file.existsSync()) return;

    final page = _currentPage.clamp(1, math.max(1, _pageCount)).toInt();

    setState(() {
      _viewMode = mode;
      _isLoading = true;
    });

    await DatabaseService.instance.setPdfPageViewMode(mode.name);

    _pinchController?.dispose();
    _flipController?.dispose();
    _pinchController = null;
    _flipController = null;

    try {
      if (mode == PdfPageViewMode.continuousZoom) {
        _pinchController = PdfControllerPinch(
          document: PdfDocument.openFile(file.path),
          initialPage: page,
        );
      } else {
        _flipController = PdfController(
          document: PdfDocument.openFile(file.path),
          initialPage: page,
        );
      }
    } catch (e) {
      _errorMessage = 'Failed to switch view mode: $e';
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showJumpToPageDialog() {
    if (_pageCount <= 1) return;
    final textController = TextEditingController(text: '$_currentPage');
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Go to Page'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(
            children: [
              Text('Enter page number (1 – $_pageCount):'),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: textController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Go'),
            onPressed: () {
              final page = int.tryParse(textController.text.trim());
              if (page != null && page >= 1 && page <= _pageCount) {
                Navigator.of(ctx).pop();
                _goToPage(page);
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pinchController?.dispose();
    _flipController?.dispose();
    super.dispose();
  }

  ColorFilter? _getColorFilter() {
    switch (_colorFilterMode) {
      case PdfColorFilterMode.original:
        return null;
      case PdfColorFilterMode.sepia:
        return const ColorFilter.mode(
          Color(0xFFFBF0D9),
          BlendMode.modulate,
        );
      case PdfColorFilterMode.inverted:
        return const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBookmarked =
        DatabaseService.instance.isBookmarked(widget.book.id, _currentPage);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            // PDF Body with gesture listener and optional color tone filter
            if (_isLoading)
              const Center(child: CupertinoActivityIndicator())
            else if (_isUnsupportedPlatform || _errorMessage != null)
              _buildErrorView(isDark)
            else
              Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (e) {
                  _pointerDownPos = e.position;
                  _pointerDownTime = DateTime.now();
                },
                onPointerUp: (e) {
                  if (_pointerDownPos != null && _pointerDownTime != null) {
                    final dist = (e.position - _pointerDownPos!).distance;
                    final dur = DateTime.now().difference(_pointerDownTime!);
                    if (dist < 12 && dur.inMilliseconds < 450) {
                      setState(() => _showControls = !_showControls);
                    }
                  }
                },
                child: _buildPdfViewer(),
              ),

            // Top Apple Books Header Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              top: _showControls ? 0 : -110,
              left: 0,
              right: 0,
              child: _buildTopBar(isDark, isBookmarked),
            ),

            // Bottom Floating Scrubber Pill
            if (!_isLoading &&
                !_isUnsupportedPlatform &&
                _errorMessage == null &&
                _pageCount > 0)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                bottom: _showControls ? 0 : -140,
                left: 0,
                right: 0,
                child: _buildBottomScrubber(isDark),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    Widget viewer;

    if (_viewMode == PdfPageViewMode.continuousZoom && _pinchController != null) {
      viewer = PdfViewPinch(
        controller: _pinchController!,
        onDocumentLoaded: (doc) {
          if (mounted) {
            setState(() {
              _pageCount = doc.pagesCount;
              if (_currentPage > _pageCount && _pageCount > 0) {
                _currentPage = _pageCount;
                _goToPage(_pageCount);
                _saveProgress(_pageCount, _pageCount);
              }
            });
          }
        },
        onDocumentError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'PDF rendering error: $error';
            });
          }
        },
        onPageChanged: (page) => _saveProgress(page, _pageCount),
        builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CupertinoActivityIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CupertinoActivityIndicator()),
          errorBuilder: (_, error) => Center(
            child: Text('Error rendering page: $error'),
          ),
        ),
      );
    } else if (_flipController != null) {
      viewer = PdfView(
        controller: _flipController!,
        onDocumentLoaded: (doc) {
          if (mounted) {
            setState(() {
              _pageCount = doc.pagesCount;
              if (_currentPage > _pageCount && _pageCount > 0) {
                _currentPage = _pageCount;
                _goToPage(_pageCount);
                _saveProgress(_pageCount, _pageCount);
              }
            });
          }
        },
        onDocumentError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _errorMessage = 'PDF rendering error: $error';
            });
          }
        },
        onPageChanged: (page) => _saveProgress(page, _pageCount),
        builders: PdfViewBuilders<DefaultBuilderOptions>(
          options: const DefaultBuilderOptions(),
          documentLoaderBuilder: (_) =>
              const Center(child: CupertinoActivityIndicator()),
          pageLoaderBuilder: (_) =>
              const Center(child: CupertinoActivityIndicator()),
          errorBuilder: (_, error) => Center(
            child: Text('Error rendering page: $error'),
          ),
        ),
      );
    } else {
      viewer = const Center(child: CupertinoActivityIndicator());
    }

    final filter = _getColorFilter();
    if (filter != null) {
      return ColorFiltered(colorFilter: filter, child: viewer);
    }
    return viewer;
  }

  Widget _buildTopBar(bool isDark, bool isBookmarked) {
    final hasControls =
        !_isLoading && !_isUnsupportedPlatform && _errorMessage == null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.of(context).padding.top + 8,
        12,
        8,
      ),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xEE1C1C1E) : const Color(0xEEFFFFFF)),
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(CupertinoIcons.chevron_left, size: 24),
            color: isDark ? Colors.white : Colors.black,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          if (hasControls) ...[
            // Bookmark toggle
            IconButton(
              icon: Icon(
                isBookmarked
                    ? CupertinoIcons.bookmark_fill
                    : CupertinoIcons.bookmark,
                size: 22,
              ),
              color: isBookmarked
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white70 : Colors.black54),
              onPressed: _toggleBookmark,
            ),
            // Contents Sheet (Bookmarks & Page Grid)
            IconButton(
              icon: const Icon(CupertinoIcons.list_bullet, size: 22),
              color: isDark ? Colors.white70 : Colors.black54,
              onPressed: () {
                PdfContentsSheet.show(
                  context,
                  bookId: widget.book.id,
                  bookTitle: widget.book.title,
                  currentPage: _currentPage,
                  totalPages: _pageCount,
                  onSelectPage: (p) => _goToPage(p),
                ).then((_) {
                  if (mounted) setState(() {});
                });
              },
            ),
            // Appearance options
            IconButton(
              icon: const Icon(CupertinoIcons.textformat_size, size: 22),
              color: isDark ? Colors.white70 : Colors.black54,
              onPressed: () {
                PdfAppearanceSheet.show(
                  context,
                  currentFilter: _colorFilterMode,
                  currentViewMode: _viewMode,
                  onSelectFilter: (mode) {
                    setState(() => _colorFilterMode = mode);
                    DatabaseService.instance.setPdfColorFilter(mode.name);
                  },
                  onSelectViewMode: (mode) {
                    if (_viewMode != mode) {
                      _switchViewMode(mode);
                    }
                  },
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomScrubber(bool isDark) {
    return Container(
      margin: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xEE1C1C1E) : const Color(0xEEFFFFFF)),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.black12,
          width: 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live Page Counter & Direct Jump Tap
          GestureDetector(
            onTap: _showJumpToPageDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Page $_currentPage of $_pageCount',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  if (_pageCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '(${((_currentPage / _pageCount) * 100).round()}%)',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 11,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Scrubber Row: Prev button, Slider, Next button
          Row(
            children: [
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_left, size: 20),
                color: _currentPage > 1
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? Colors.white24 : Colors.black26),
                onPressed: _currentPage > 1 ? _prevPage : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: const Color(0xFF007AFF),
                    inactiveTrackColor:
                        isDark ? Colors.white24 : Colors.black12,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    value: _currentPage
                        .toDouble()
                        .clamp(1.0, math.max(1.0, _pageCount.toDouble())),
                    min: 1.0,
                    max: math.max(1.0, _pageCount.toDouble()),
                    onChanged: (val) {
                      setState(() {
                        _currentPage = val.round();
                      });
                    },
                    onChangeEnd: (val) {
                      _goToPage(val.round());
                    },
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.chevron_right, size: 20),
                color: _currentPage < _pageCount
                    ? (isDark ? Colors.white : Colors.black)
                    : (isDark ? Colors.white24 : Colors.black26),
                onPressed: _currentPage < _pageCount ? _nextPage : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isUnsupportedPlatform
                  ? CupertinoIcons.device_laptop
                  : CupertinoIcons.exclamationmark_triangle,
              size: 54,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(height: 18),
            Text(
              _isUnsupportedPlatform ? 'Platform Notice' : 'Unable to Open PDF',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage ?? 'Unknown error occurred.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.45,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.white : Colors.black,
                    side: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Back'),
                ),
                if (!_isUnsupportedPlatform) ...[
                  const SizedBox(width: 14),
                  FilledButton.tonal(
                    onPressed: () async {
                      await DatabaseService.instance
                          .setLibraryMembership(widget.book.id, false);
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    style: FilledButton.styleFrom(
                      foregroundColor: CupertinoColors.destructiveRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('Remove from Library'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
