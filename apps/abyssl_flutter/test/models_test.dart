import 'package:abyssl_flutter/src/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capture shortcut display name includes the key once', () {
    const shortcut = TranslationCaptureShortcut(
      modifier: TranslationCaptureModifier.control,
      key: 'c',
    );

    expect(shortcut.displayName, 'Ctrl+C');
  });

  test('document input extensions distinguish docx from legacy doc', () {
    expect(DocumentInputKind.fromExtension('docx'), DocumentInputKind.docx);
    expect(
      DocumentInputKind.fromExtension('doc'),
      DocumentInputKind.unsupported,
    );
  });
}
