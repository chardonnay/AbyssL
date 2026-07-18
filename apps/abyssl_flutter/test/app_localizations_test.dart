import 'package:abyssl_flutter/src/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all supported app languages cover the primary desktop interface', () {
    const requiredCopy = <String>[
      'Translate',
      'Correction',
      'Documents',
      'Settings',
      'Command',
      'Type a command or press ⌘K',
      'Direct instruction',
      'Provide context or instructions for translation…',
      'Type or paste your source text here…',
      'Translation style',
      'Style',
      'Source',
      'Target',
      'Automatic',
      'Ready',
      'Translated',
      'Translation',
      'Your translation will appear here…',
      'Copy',
      'More alternatives',
      'Auto-translate',
      'Clear',
      'Correction instruction',
      'Describe how the text should be corrected or rewritten…',
      'Rewrite style',
      'Standard',
      'Type or paste the text you want to improve…',
      'characters',
      'Rewrite',
      'Corrected / rewritten text',
      'The corrected or rewritten text will appear here…',
      'Add files',
      'Add folder',
      'Output folder',
      'No output folder selected',
      'Optional instruction for all documents…',
      'Correct text',
      'Export',
      'Processing results',
      'Results appear here',
      'Drop files or folders here.',
      'Process',
      'General',
      'AI Providers',
      'About',
      'Appearance',
      'Application language',
      'Language',
      'Default provider',
      'Provider',
      'Configuration',
      'Editor and capture',
      'Base URL',
      'Model ID',
      'Timeout seconds',
      'Authentication',
      'API key',
      'Load models',
      'Test connection',
      'Reasoning',
      'About AbyssL',
      'Software updates',
      'Check for updates',
    ];

    for (final locale in AbyssLAppLocalizations.supportedLocales) {
      if (locale == const Locale('en')) continue;
      final localizations = AbyssLAppLocalizations(locale);
      final missing = requiredCopy
          .where((key) => !localizations.hasTranslation(key))
          .toList();
      expect(
        missing,
        isEmpty,
        reason: 'Missing ${locale.languageCode}: $missing',
      );
    }
  });
}
