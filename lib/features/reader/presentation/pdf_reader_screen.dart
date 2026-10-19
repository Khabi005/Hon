import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/reader_theme.dart';
import '../widgets/reader_chrome.dart';
import '../sheets/reader_menu_popup.dart';
import '../sheets/themes_settings_sheet.dart';
import 'package:pdfx/pdfx.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/reading_progress.dart';
import '../sheets/pdf_contents_sheet.dart';
import '../sheets/pdf_appearance_sheet.dart';

class PdfReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  final int initialPage;

  const PdfReaderScreen({super.key, required this.book, this.initialPage = 1});

  @override
  ConsumerState<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends ConsumerState<PdfReaderScreen>
    with WidgetsBindingObserver {
  PdfControllerPinch? _pinchController;
  PdfController? _flipController;

  int _currentPage = 1;
  int _pageCount = 0;
  bool _isLoading = true;
  bool _showControls = true;
  String? _errorMessage;
  bool _isUnsupportedPlatform = false;

  bool _isOrientationLocked = false;
  double? _appliedBrightness;
  PdfPageViewMode _viewMode = PdfPageViewMode.continuousZoom;

  Offset? _pointerDownPos;
  DateTime? _pointerDownTime;
  DateTime? _sessionStartTime;
  bool _isForegrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Do NOT start timer during loading/validation! Timer starts once PDF document is open, readable, AND foregrounded.
    _sessionStartTime = null;
    _initPdf();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isForegrounded = false;
      _pauseReadingSession();
    } else if (state == AppLifecycleState.resumed) {
      _isForegrounded = true;
      _resumeReadingSession();
    }
  }

  void _pauseReadingSession() {
    if (_sessionStartTime != null) {
      final elapsed = DateTime.now().difference(_sessionStartTime!).inSeconds;
      if (elapsed > 0) {
        DatabaseService.instance.addReadingTime(elapsed);
      }
      _sessionStartTime =
          null; // Crucial: STOP timer so background time is never counted!
    }
  }

  void _resumeReadingSession() {
    // Only restart timer if PDF has valid, readable document in foreground
    if (!_isLoading &&
        _errorMessage == null &&
        !_isUnsupportedPlatform &&
        _isForegrounded &&
        _sessionStartTime == null) {
      _sessionStartTime = DateTime.now();
    }
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
      if (!mounted) {
        await testDoc.close();
        return;
      }

      if (docPages <= 0) {
        await testDoc.close();
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
          document: Future.value(testDoc),
          initialPage: page,
        );
        if (mounted) {
          setState(() {
            _pinchController = pinchCtrl;
            _flipController = null;
            _currentPage = page;
            _pageCount = docPages;
            _isLoading = false;
            _sessionStartTime = null;
          });
        }
      } else {
        final flipCtrl = PdfController(
          document: Future.value(testDoc),
          initialPage: page,
        );
        if (mounted) {
          setState(() {
            _flipController = flipCtrl;
            _pinchController = null;
            _currentPage = page;
            _pageCount = docPages;
            _isLoading = false;
            _sessionStartTime = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _sessionStartTime = null;
          _errorMessage =
              'Unable to parse PDF document. The file may be corrupt or encrypted.\n$e';
        });
      }
    }
  }

  void _saveProgress(int page, int pageCount) {
    if (pageCount <= 0) return;
    final clampedPage = page.clamp(1, pageCount);
    if (mounted && (_currentPage != clampedPage || _pageCount != pageCount)) {
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _switchViewMode(PdfPageViewMode mode) async {
    if (!mounted || _isLoading || mode == _viewMode) return;
    if (_isUnsupportedPlatform || Platform.isLinux || _errorMessage != null) {
      return;
    }
    if (widget.book.filePath == null) return;
    final file = File(widget.book.filePath!);
    if (!file.existsSync()) return;

    final page = _currentPage.clamp(1, math.max(1, _pageCount)).toInt();

    setState(() {
      _viewMode = mode;
      _isLoading = true;
    });

    _pauseReadingSession();
    await DatabaseService.instance.setPdfPageViewMode(mode.name);
    if (!mounted) return;

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

  Future<void> _showJumpToPageDialog() async {
    if (_pageCount <= 1) return;
    final page = await showDialog<int>(
      context: context,
      builder: (_) => _PageJumpDialog(current: _currentPage, total: _pageCount),
    );
    if (mounted && page != null) _goToPage(page);
  }

  Future<void> _toggleOrientationLock() async {
    final orientation = MediaQuery.orientationOf(context);
    await SystemChrome.setPreferredOrientations(
      _isOrientationLocked
          ? []
          : [
              orientation == Orientation.portrait
                  ? DeviceOrientation.portraitUp
                  : DeviceOrientation.landscapeLeft,
            ],
    );
    if (mounted) setState(() => _isOrientationLocked = !_isOrientationLocked);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseReadingSession();
    if (_isOrientationLocked) SystemChrome.setPreferredOrientations([]);
    if (Platform.isAndroid && _appliedBrightness != null) {
      const MethodChannel(
        'com.hon.reader/readium_reader',
      ).invokeMethod<void>('setBrightness', {'brightness': -1.0});
    }
    _pinchController?.dispose();
    _flipController?.dispose();
    super.dispose();
  }

  ColorFilter? _getColorFilter() {
    final theme = ref.read(readerPreferencesProvider).themeConfig;
    if (theme.preset == ReaderThemePreset.original) return null;
    // Map white paper and black ink to the same six reader theme colors.
    final bg = theme.backgroundColor;
    final ink = theme.textColor;
    final b = [bg.r * 255, bg.g * 255, bg.b * 255];
    final t = [ink.r * 255, ink.g * 255, ink.b * 255];
    return ColorFilter.matrix([
      (b[0] - t[0]) / 255,
      0,
      0,
      0,
      t[0],
      0,
      (b[1] - t[1]) / 255,
      0,
      0,
      t[1],
      0,
      0,
      (b[2] - t[2]) / 255,
      0,
      t[2],
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final preferences = ref.watch(readerPreferencesProvider);
    final theme = preferences.themeConfig;
    if (Platform.isAndroid && _appliedBrightness != preferences.brightness) {
      _appliedBrightness = preferences.brightness;
      const MethodChannel('com.hon.reader/readium_reader').invokeMethod<void>(
        'setBrightness',
        {'brightness': preferences.brightness},
      );
    }
    final isDark = theme.systemBrightness == Brightness.dark;
    final isBookmarked = DatabaseService.instance.isBookmarked(
      widget.book.id,
      _currentPage,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: theme.backgroundColor,
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
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + 68,
                      bottom: MediaQuery.paddingOf(context).bottom + 60,
                    ),
                    child: _buildPdfViewer(),
                  ),
                ),

              // Top Apple Books Header Bar
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: AnimatedSlide(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  offset: _showControls ? Offset.zero : const Offset(0, -1),
                  child: ReaderControlsVisibility(
                    visible: _showControls,
                    child: ReaderHeader(
                      theme: theme,
                      location: '$_currentPage',
                      status: _pageCount > 0
                          ? '${_pageCount - _currentPage} pages left'
                          : widget.book.title,
                      onPrevious: _currentPage > 1 ? _prevPage : null,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),

              // Bottom Floating Scrubber Pill
              if (!_isLoading &&
                  !_isUnsupportedPlatform &&
                  _errorMessage == null &&
                  _pageCount > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    offset: _showControls ? Offset.zero : const Offset(0, 1),
                    child: ReaderControlsVisibility(
                      visible: _showControls,
                      child: ReaderFooter(
                        theme: theme,
                        progress: 'Page $_currentPage of $_pageCount',
                        onProgress: _showJumpToPageDialog,
                        onMenu: () => _showReaderMenu(theme, isBookmarked),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    Widget viewer;

    if (_viewMode == PdfPageViewMode.continuousZoom &&
        _pinchController != null) {
      viewer = PdfViewPinch(
        controller: _pinchController!,
        onDocumentLoaded: (doc) {
          _resumeReadingSession();
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
          _pauseReadingSession();
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
          errorBuilder: (_, error) =>
              Center(child: Text('Error rendering page: $error')),
        ),
      );
    } else if (_flipController != null) {
      viewer = PdfView(
        controller: _flipController!,
        onDocumentLoaded: (doc) {
          _resumeReadingSession();
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
          _pauseReadingSession();
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
          errorBuilder: (_, error) =>
              Center(child: Text('Error rendering page: $error')),
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

  void _showReaderMenu(ReaderThemeConfig theme, bool isBookmarked) {
    ReaderMenuPopup.show(
      context,
      theme: theme,
      searchLabel: 'Go to Page',
      onOpenContents: () =>
          PdfContentsSheet.show(
            context,
            theme: theme,
            bookId: widget.book.id,
            bookTitle: widget.book.title,
            currentPage: _currentPage,
            totalPages: _pageCount,
            onSelectPage: _goToPage,
          ).then((_) {
            if (mounted) setState(() {});
          }),
      onOpenSearch: _showJumpToPageDialog,
      onOpenThemes: () => ThemesSettingsSheet.show(
        context,
        supportsTypography: false,
        bookId: widget.book.id,
        layoutControl: StatefulBuilder(
          builder: (context, update) => SegmentedButton<PdfPageViewMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: PdfPageViewMode.singlePage,
                label: Text('Paged'),
              ),
              ButtonSegment(
                value: PdfPageViewMode.continuousZoom,
                label: Text('Scroll & Zoom'),
              ),
            ],
            selected: {_viewMode},
            onSelectionChanged: (selection) async {
              await _switchViewMode(selection.first);
              if (context.mounted) update(() {});
            },
          ),
        ),
      ),
      onToggleReadingMode: () => _switchViewMode(
        _viewMode == PdfPageViewMode.singlePage
            ? PdfPageViewMode.continuousZoom
            : PdfPageViewMode.singlePage,
      ),
      onToggleBookmark: _toggleBookmark,
      onToggleOrientationLock: _toggleOrientationLock,
      isOrientationLocked: _isOrientationLocked,
      isBookmarked: isBookmarked,
      isContinuousScroll: _viewMode == PdfPageViewMode.continuousZoom,
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
                      await DatabaseService.instance.setLibraryMembership(
                        widget.book.id,
                        false,
                      );
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

class _PageJumpDialog extends StatefulWidget {
  final int current;
  final int total;
  const _PageJumpDialog({required this.current, required this.total});
  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final controller = TextEditingController(text: '${widget.current}');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final page = int.tryParse(controller.text);
    if (page != null && page >= 1 && page <= widget.total) {
      Navigator.of(context).pop(page);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Go to Page'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: InputDecoration(labelText: 'Page 1–${widget.total}'),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Go')),
    ],
  );
}
