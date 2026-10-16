import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/reading_progress.dart';

class PdfReaderScreen extends StatefulWidget {
  final Book book;

  const PdfReaderScreen({
    super.key,
    required this.book,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  PdfDocument? _document;
  PdfController? _pdfController;
  int _currentPage = 1;
  int _pageCount = 1;
  bool _isLoading = true;
  bool _showControls = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final saved = DatabaseService.instance.getProgress(widget.book.id);
      final initialPage = saved != null && saved.pageIndex > 0 ? saved.pageIndex : 1;

      if (widget.book.filePath != null) {
        final file = File(widget.book.filePath!);
        if (file.existsSync()) {
          final doc = await PdfDocument.openFile(file.path);
          _pdfController = PdfController(
            document: PdfDocument.openFile(file.path),
            initialPage: initialPage,
          );
          if (mounted) {
            setState(() {
              _document = doc;
              _pageCount = doc.pagesCount;
              _currentPage = initialPage;
              _isLoading = false;
            });
            return;
          }
        }
      }

      // If no valid file yet
      if (mounted) {
        setState(() {
          _errorMessage = 'PDF file not found at ${widget.book.filePath}';
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

  void _saveProgress(int page) {
    _currentPage = page;
    final prog = ReadingProgress(
      bookId: widget.book.id,
      pageIndex: page,
      totalPages: _pageCount,
      completionPercentage: page / (_pageCount > 0 ? _pageCount : 1),
      lastReadAt: DateTime.now(),
    );
    DatabaseService.instance.saveProgress(prog);
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _document?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF2F2F7),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            // PDF View
            if (_isLoading)
              const Center(child: CupertinoActivityIndicator())
            else if (_errorMessage != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  ),
                ),
              )
            else if (_pdfController != null)
              GestureDetector(
                onTap: () {
                  setState(() => _showControls = !_showControls);
                },
                child: PdfView(
                  controller: _pdfController!,
                  onPageChanged: (page) => _saveProgress(page),
                  builders: PdfViewBuilders<DefaultBuilderOptions>(
                    options: const DefaultBuilderOptions(),
                    documentLoaderBuilder: (_) =>
                        const Center(child: CupertinoActivityIndicator()),
                    pageLoaderBuilder: (_) =>
                        const Center(child: CupertinoActivityIndicator()),
                  ),
                ),
              ),

            // Top Header Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(context).padding.top + 8,
                  16,
                  8,
                ),
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.book.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark_circle_fill),
                      color: isDark ? Colors.white70 : Colors.black54,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Progress Bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              bottom: _showControls ? 0 : -100,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(
                  24,
                  10,
                  24,
                  MediaQuery.of(context).padding.bottom + 10,
                ),
                color: (isDark ? Colors.black : Colors.white).withOpacity(0.9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Page $_currentPage of $_pageCount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
