import 'dart:io';

enum TranslationProvider {
  openAI,
  localLLM;

  String get label => switch (this) {
    TranslationProvider.openAI => 'OpenAI',
    TranslationProvider.localLLM => 'Local LLM',
  };
}

enum AppThemeMode {
  system,
  light,
  dark;

  String get label => switch (this) {
    AppThemeMode.system => 'System',
    AppThemeMode.light => 'Light',
    AppThemeMode.dark => 'Dark',
  };
}

enum OpenAIModel {
  gpt4o('gpt-4o'),
  gpt4oMini('gpt-4o-mini'),
  gpt35Turbo('gpt-3.5-turbo');

  const OpenAIModel(this.id);

  final String id;

  bool get supportsReasoningParameter => switch (this) {
    OpenAIModel.gpt4o || OpenAIModel.gpt4oMini => true,
    OpenAIModel.gpt35Turbo => false,
  };

  static OpenAIModel fromId(String value) => values.firstWhere(
    (model) => model.id == value,
    orElse: () => OpenAIModel.gpt4oMini,
  );
}

enum TranslationLanguage {
  automatic('automatic', 'auto', 'Automatic'),
  englishUS('englishUS', 'en-US', 'English (US)'),
  englishUK('englishUK', 'en-GB', 'English (UK)'),
  german('german', 'de-DE', 'German'),
  french('french', 'fr-FR', 'French'),
  spanish('spanish', 'es-ES', 'Spanish'),
  italian('italian', 'it-IT', 'Italian'),
  portuguese('portuguese', 'pt-PT', 'Portuguese'),
  dutch('dutch', 'nl-NL', 'Dutch'),
  polish('polish', 'pl-PL', 'Polish'),
  russian('russian', 'ru-RU', 'Russian'),
  japanese('japanese', 'ja-JP', 'Japanese'),
  korean('korean', 'ko-KR', 'Korean'),
  chineseSimplified('chineseSimplified', 'zh-Hans', 'Chinese Simplified'),
  chineseTraditional('chineseTraditional', 'zh-Hant', 'Chinese Traditional');

  const TranslationLanguage(this.id, this.localeTag, this.label);

  final String id;
  final String localeTag;
  final String label;

  static TranslationLanguage fromId(String value) => values.firstWhere(
    (language) => language.id == value,
    orElse: () => TranslationLanguage.automatic,
  );
}

enum RegisterStyle {
  neutral,
  formal,
  informal;

  String get label => switch (this) {
    RegisterStyle.neutral => 'Neutral',
    RegisterStyle.formal => 'Formal',
    RegisterStyle.informal => 'Informal',
  };
}

enum ComplexityStyle {
  neutral,
  technical,
  plain;

  String get label => switch (this) {
    ComplexityStyle.neutral => 'Neutral',
    ComplexityStyle.technical => 'Technical',
    ComplexityStyle.plain => 'Plain',
  };
}

enum SpellingMode {
  preserve,
  fixSource,
  fixTarget;

  String get label => switch (this) {
    SpellingMode.preserve => 'Preserve',
    SpellingMode.fixSource => 'Fix source',
    SpellingMode.fixTarget => 'Fix target',
  };
}

class StyleSettings {
  const StyleSettings({
    this.register = RegisterStyle.neutral,
    this.complexity = ComplexityStyle.neutral,
    this.spellingMode = SpellingMode.preserve,
  });

  final RegisterStyle register;
  final ComplexityStyle complexity;
  final SpellingMode spellingMode;

  StyleSettings copyWith({
    RegisterStyle? register,
    ComplexityStyle? complexity,
    SpellingMode? spellingMode,
  }) => StyleSettings(
    register: register ?? this.register,
    complexity: complexity ?? this.complexity,
    spellingMode: spellingMode ?? this.spellingMode,
  );
}

enum WritingStylePreset {
  standard,
  formal,
  concise,
  ultraShortSummary;

  String get label => switch (this) {
    WritingStylePreset.standard => 'Standard',
    WritingStylePreset.formal => 'Formal',
    WritingStylePreset.concise => 'Concise',
    WritingStylePreset.ultraShortSummary => 'Ultra Short',
  };

  String get promptInstruction => switch (this) {
    WritingStylePreset.standard =>
      "Style: preserve the author's original register and flow while making the wording clear and natural.",
    WritingStylePreset.formal =>
      'Style: rewrite in a formal, professional register suitable for business communication.',
    WritingStylePreset.concise =>
      'Style: rewrite concisely with shorter sentences and no unnecessary filler, while preserving meaning.',
    WritingStylePreset.ultraShortSummary =>
      'Style: summarize the input extremely briefly, ideally as one very short sentence or phrase. Keep only the core message, omit supporting details, and do not add facts.',
  };
}

class TranslationAIResult {
  const TranslationAIResult({
    required this.translation,
    this.synonyms = const [],
    this.spellingNotes,
    this.revisedSource,
  });

  final String translation;
  final List<String> synonyms;
  final String? spellingNotes;
  final String? revisedSource;
}

class WritingCorrectionIssue {
  const WritingCorrectionIssue({
    required this.originalText,
    required this.correctedText,
    required this.message,
    this.alternatives = const [],
    this.start,
    this.length,
    this.originalStart,
    this.originalLength,
    this.correctedStart,
    this.correctedLength,
  });

  final String originalText;
  final String correctedText;
  final String message;
  final List<String> alternatives;
  final int? start;
  final int? length;
  final int? originalStart;
  final int? originalLength;
  final int? correctedStart;
  final int? correctedLength;
}

class WritingCorrectionResult {
  const WritingCorrectionResult({
    required this.correctedText,
    this.issues = const [],
  });

  final String correctedText;
  final List<WritingCorrectionIssue> issues;
}

enum TranslationCaptureModifier {
  control,
  option,
  command,
  shift;

  String get label => switch (this) {
    TranslationCaptureModifier.control => 'Ctrl',
    TranslationCaptureModifier.option => Platform.isMacOS ? 'Option' : 'Alt',
    TranslationCaptureModifier.command => Platform.isMacOS ? 'Command' : 'Meta',
    TranslationCaptureModifier.shift => 'Shift',
  };
}

class TranslationCaptureShortcut {
  const TranslationCaptureShortcut({
    this.modifier = TranslationCaptureModifier.control,
    this.key = defaultKey,
  });

  static const defaultKey = 'c';

  final TranslationCaptureModifier modifier;
  final String key;

  String get normalizedKey => normalizeKey(key);
  String get displayName => '${modifier.label}+${normalizedKey.toUpperCase()}';

  static String normalizeKey(String value) {
    final trimmed = value.trim().toLowerCase();
    final match = RegExp(r'[a-z0-9]').firstMatch(trimmed);
    return match?.group(0) ?? defaultKey;
  }
}

class LLMProfile {
  const LLMProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.useHTTPS,
    required this.model,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final bool useHTTPS;
  final String model;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'port': port,
    'useHTTPS': useHTTPS,
    'model': model,
  };

  static LLMProfile? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final id = value['id'];
    final name = value['name'];
    final host = value['host'];
    final port = value['port'];
    final useHTTPS = value['useHTTPS'];
    final model = value['model'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.trim().isEmpty) return null;
    if (host is! String || host.trim().isEmpty) return null;
    if (port is! int || port < 1 || port > 65535) return null;
    if (useHTTPS is! bool) return null;
    if (model is! String) return null;
    return LLMProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      useHTTPS: useHTTPS,
      model: model,
    );
  }
}

class LLMReasoningSettings {
  const LLMReasoningSettings({
    required this.model,
    required this.allowedOptions,
    required this.reasoningOnValue,
    required this.reasoningOffValue,
    required this.reasoningEnabled,
  });

  final String model;
  final List<String> allowedOptions;
  final String reasoningOnValue;
  final String reasoningOffValue;
  final bool reasoningEnabled;

  Map<String, Object?> toJson() => {
    'model': model,
    'allowedOptions': allowedOptions,
    'reasoningOnValue': reasoningOnValue,
    'reasoningOffValue': reasoningOffValue,
    'reasoningEnabled': reasoningEnabled,
  };

  static LLMReasoningSettings? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final model = value['model'];
    final allowedOptions = value['allowedOptions'];
    final reasoningOnValue = value['reasoningOnValue'];
    final reasoningOffValue = value['reasoningOffValue'];
    final reasoningEnabled = value['reasoningEnabled'];
    if (model is! String || model.trim().isEmpty) return null;
    if (allowedOptions is! List) return null;
    if (reasoningOnValue is! String || reasoningOnValue.trim().isEmpty) {
      return null;
    }
    if (reasoningOffValue is! String || reasoningOffValue.trim().isEmpty) {
      return null;
    }
    if (reasoningEnabled is! bool) return null;
    return LLMReasoningSettings(
      model: model.trim(),
      allowedOptions: allowedOptions
          .whereType<String>()
          .map((option) => option.trim())
          .where((option) => option.isNotEmpty)
          .toSet()
          .toList(growable: false),
      reasoningOnValue: reasoningOnValue.trim(),
      reasoningOffValue: reasoningOffValue.trim(),
      reasoningEnabled: reasoningEnabled,
    );
  }

  static String modelKey(String model) => model.trim();
}

enum DocumentInputKind {
  plainText,
  markdown,
  asciidoc,
  html,
  rtf,
  pdf,
  docx,
  odt,
  csv,
  tsv,
  xlsx,
  pages,
  numbers,
  unsupported;

  bool get isSpreadsheet => switch (this) {
    DocumentInputKind.csv ||
    DocumentInputKind.tsv ||
    DocumentInputKind.xlsx ||
    DocumentInputKind.numbers => true,
    _ => false,
  };

  static DocumentInputKind fromExtension(String extension) =>
      switch (extension.toLowerCase()) {
        'txt' || 'text' => DocumentInputKind.plainText,
        'md' || 'markdown' => DocumentInputKind.markdown,
        'adoc' || 'asciidoc' => DocumentInputKind.asciidoc,
        'html' || 'htm' => DocumentInputKind.html,
        'rtf' => DocumentInputKind.rtf,
        'pdf' => DocumentInputKind.pdf,
        'docx' => DocumentInputKind.docx,
        'doc' => DocumentInputKind.unsupported,
        'odt' => DocumentInputKind.odt,
        'csv' => DocumentInputKind.csv,
        'tsv' => DocumentInputKind.tsv,
        'xlsx' => DocumentInputKind.xlsx,
        'pages' => DocumentInputKind.pages,
        'numbers' => DocumentInputKind.numbers,
        _ => DocumentInputKind.unsupported,
      };
}

enum DocumentExportFormat {
  pdf('pdf', 'PDF', false),
  docx('docx', 'DOCX', true),
  odt('odt', 'ODT', false),
  markdown('md', 'Markdown', true),
  html('html', 'HTML', true),
  asciidoc('adoc', 'AsciiDoc', true),
  plainText('txt', 'Plain text', false),
  rtf('rtf', 'RTF', false),
  pages('pages', 'Pages', false),
  numbers('numbers', 'Numbers', true);

  const DocumentExportFormat(
    this.fileExtension,
    this.label,
    this.supportsTables,
  );

  final String fileExtension;
  final String label;
  final bool supportsTables;
}

class DocumentNameOptions {
  const DocumentNameOptions({
    this.customizeName = false,
    this.appendTimestamp = false,
    this.appendTargetLanguage = false,
    this.customSuffix = '',
  });

  final bool customizeName;
  final bool appendTimestamp;
  final bool appendTargetLanguage;
  final String customSuffix;

  DocumentNameOptions copyWith({
    bool? customizeName,
    bool? appendTimestamp,
    bool? appendTargetLanguage,
    String? customSuffix,
  }) => DocumentNameOptions(
    customizeName: customizeName ?? this.customizeName,
    appendTimestamp: appendTimestamp ?? this.appendTimestamp,
    appendTargetLanguage: appendTargetLanguage ?? this.appendTargetLanguage,
    customSuffix: customSuffix ?? this.customSuffix,
  );
}

class DocumentOperationOptions {
  const DocumentOperationOptions({
    this.shouldCorrect = true,
    this.shouldTranslate = true,
    this.instruction = '',
    this.exportFormat = DocumentExportFormat.pdf,
    this.exportImagesForAsciiDoc = false,
    this.nameOptions = const DocumentNameOptions(),
  });

  final bool shouldCorrect;
  final bool shouldTranslate;
  final String instruction;
  final DocumentExportFormat exportFormat;
  final bool exportImagesForAsciiDoc;
  final DocumentNameOptions nameOptions;

  DocumentOperationOptions copyWith({
    bool? shouldCorrect,
    bool? shouldTranslate,
    String? instruction,
    DocumentExportFormat? exportFormat,
    bool? exportImagesForAsciiDoc,
    DocumentNameOptions? nameOptions,
  }) => DocumentOperationOptions(
    shouldCorrect: shouldCorrect ?? this.shouldCorrect,
    shouldTranslate: shouldTranslate ?? this.shouldTranslate,
    instruction: instruction ?? this.instruction,
    exportFormat: exportFormat ?? this.exportFormat,
    exportImagesForAsciiDoc:
        exportImagesForAsciiDoc ?? this.exportImagesForAsciiDoc,
    nameOptions: nameOptions ?? this.nameOptions,
  );
}

class DocumentJob {
  const DocumentJob({
    required this.sourcePath,
    required this.inputKind,
    this.rootPath,
    this.statusMessage,
  });

  final String sourcePath;
  final String? rootPath;
  final DocumentInputKind inputKind;
  final String? statusMessage;

  String get displayName => sourcePath.split(Platform.pathSeparator).last;
}

enum DocumentResultStatus { success, skipped, failed }

class DocumentProcessingResult {
  const DocumentProcessingResult({
    required this.sourcePath,
    required this.status,
    required this.message,
    this.outputPath,
  });

  final String sourcePath;
  final String? outputPath;
  final DocumentResultStatus status;
  final String message;
}

class DocumentImageAsset {
  const DocumentImageAsset({
    required this.suggestedFilename,
    required this.data,
  });

  final String suggestedFilename;
  final List<int> data;
}

sealed class DocumentBlock {
  const DocumentBlock();
}

class DocumentParagraph extends DocumentBlock {
  const DocumentParagraph(this.text);
  final String text;
}

class DocumentTable extends DocumentBlock {
  const DocumentTable(this.rows);
  final List<List<String>> rows;
}

class DocumentIR {
  const DocumentIR({
    required this.blocks,
    required this.sourceKind,
    this.images = const [],
  });

  final List<DocumentBlock> blocks;
  final List<DocumentImageAsset> images;
  final DocumentInputKind sourceKind;

  String get plainText => blocks
      .map(
        (block) => switch (block) {
          DocumentParagraph(:final text) => text,
          DocumentTable(:final rows) =>
            rows.map((row) => row.join('\t')).join('\n'),
        },
      )
      .where((text) => text.trim().isNotEmpty)
      .join('\n\n');
}
