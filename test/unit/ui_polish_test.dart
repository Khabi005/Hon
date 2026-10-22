import 'package:flutter_test/flutter_test.dart';
import 'package:hon/features/home/presentation/widgets/continue_reading_card.dart';
import 'package:hon/app/theme/reader_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4 — UI Polish & Accessibility', () {
    test('isKnownAuthor correctly identifies placeholder and unknown authors', () {
      expect(isKnownAuthor('Unknown Author'), isFalse);
      expect(isKnownAuthor('unknown author'), isFalse);
      expect(isKnownAuthor('UNKNOWN'), isFalse);
      expect(isKnownAuthor('---'), isFalse);
      expect(isKnownAuthor('--'), isFalse);
      expect(isKnownAuthor('-'), isFalse);
      expect(isKnownAuthor(''), isFalse);
      expect(isKnownAuthor('   '), isFalse);
      expect(isKnownAuthor(null), isFalse);
      expect(isKnownAuthor('None'), isFalse);
      expect(isKnownAuthor('N/A'), isFalse);

      expect(isKnownAuthor('Cuttlefish That Loves Diving'), isTrue);
      expect(isKnownAuthor('Mary Shelley'), isTrue);
      expect(isKnownAuthor('Arthur Conan Doyle'), isTrue);
    });

    test('ReaderFontFamily values are supported fonts', () {
      expect(ReaderFontFamily.values.length, 5);
      final names = ReaderFontFamily.values.map((f) => f.displayName).toList();
      expect(names, contains('Newsreader'));
      expect(names, contains('Literata'));
      expect(names, contains('System Sans'));
      expect(names, contains('Lora'));
      expect(names, contains('Libre Baskerville'));
    });
  });
}
