import 'package:flutter/material.dart';
import '../../core/database/database_service.dart';
import '../../core/models/book.dart';
import '../../app/theme/hon_colors.dart';
import '../../shared/widgets/book_cover_widget.dart';

enum AddToLibraryChoice {
  addToLibrary,
  notNow,
}

class AddToLibraryPrompt {
  static Future<AddToLibraryChoice> show(
    BuildContext context, {
    required Book novel,
  }) async {
    final db = DatabaseService.instance;

    // Rule: Recheck membership immediately before showing
    if (db.isBookInLibrary(novel.id)) {
      return AddToLibraryChoice.addToLibrary;
    }

    // Rule: If suppressed for current session, automatically proceed as Not Now
    if (db.isPromptSuppressedForSession(novel.id)) {
      return AddToLibraryChoice.notNow;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showModalBottomSheet<AddToLibraryChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Small Cover Thumbnail
              BookCoverWidget(
                title: novel.title,
                author: novel.author,
                coverPath: novel.coverPath,
                width: 65,
                height: 98,
                borderRadius: 6,
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                'Add to Library?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : Colors.black,
                  fontFamily: 'serif',
                ),
              ),
              const SizedBox(height: 8),

              // Description
              Text(
                'Add "${novel.title}" to your library to find it easily and check for new chapters.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Action Buttons
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Add to Library Button
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop(AddToLibraryChoice.addToLibrary);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Add to Library',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Not Now Button
                  TextButton(
                    onPressed: () {
                      Navigator.of(ctx).pop(AddToLibraryChoice.notNow);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white70 : Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Not Now',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    // Rule: Dismissing the sheet behaves as Not Now
    final choice = result ?? AddToLibraryChoice.notNow;

    if (choice == AddToLibraryChoice.addToLibrary) {
      await db.setLibraryMembership(novel.id, true);
    } else {
      // Rule: Suppress repeat prompts for that novel during the current app session
      db.suppressPromptForSession(novel.id);
    }

    return choice;
  }
}
