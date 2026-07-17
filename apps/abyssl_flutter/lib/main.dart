import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/abyssl_design.dart';
import 'src/app_update.dart';
import 'src/document_processing.dart';
import 'src/models.dart';
import 'src/openai_client.dart';
import 'src/platform_capture.dart';
import 'src/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettingsStore.load();
  runApp(AbyssLApp(settings: settings));
}

class AbyssLApp extends StatelessWidget {
  const AbyssLApp({
    super.key,
    required this.settings,
    this.apiClient,
    this.updateService,
  });

  final AppSettingsStore settings;
  final AbyssLApiClient? apiClient;
  final AppUpdateService? updateService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) => MaterialApp(
        title: 'AbyssL Translator',
        debugShowCheckedModeBanner: false,
        themeMode: _themeMode(settings.themeMode),
        theme: _themeData(Brightness.light),
        darkTheme: _themeData(Brightness.dark),
        home: MainShell(
          settings: settings,
          apiClient: apiClient,
          updateService: updateService,
        ),
      ),
    );
  }

  static ThemeData _themeData(Brightness brightness) {
    return buildAbyssLTheme(brightness);
  }

  static ThemeMode _themeMode(AppThemeMode mode) => switch (mode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };
}

class HighlightRange {
  const HighlightRange({
    required this.start,
    required this.end,
    required this.style,
  });

  final int start;
  final int end;
  final TextStyle style;
}

class HighlightingTextEditingController extends TextEditingController {
  var _highlights = <HighlightRange>[];

  void setHighlights(List<HighlightRange> highlights) {
    _highlights = List.unmodifiable(highlights);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final value = text;
    if (_highlights.isEmpty || value.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final ranges =
        _highlights
            .where(
              (range) =>
                  range.start >= 0 &&
                  range.end > range.start &&
                  range.start < value.length,
            )
            .map(
              (range) => HighlightRange(
                start: range.start,
                end: range.end.clamp(0, value.length),
                style: range.style,
              ),
            )
            .toList()
          ..sort((lhs, rhs) => lhs.start.compareTo(rhs.start));

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      if (range.start < cursor) continue;
      if (range.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, range.start)));
      }
      spans.add(
        TextSpan(
          text: value.substring(range.start, range.end),
          style: range.style,
        ),
      );
      cursor = range.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }

    return TextSpan(style: style, children: spans);
  }
}

class CorrectionIssueCard extends StatelessWidget {
  const CorrectionIssueCard({super.key, required this.issue});

  final WritingCorrectionIssue issue;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${issue.originalText} -> ${issue.correctedText}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(issue.message),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: issue.alternatives
                    .map(
                      (item) => Chip(
                        label: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: Text(
                            item,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ResultChipPanel extends StatelessWidget {
  const ResultChipPanel({
    super.key,
    required this.title,
    required this.values,
    required this.controller,
  });

  final String title;
  final List<String> values;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: controller,
        padding: const EdgeInsets.only(right: 14, bottom: 12),
        child: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              ...values.map(
                (value) => ActionChip(
                  label: Text(value),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: value)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.settings,
    this.apiClient,
    this.updateService,
  });

  final AppSettingsStore settings;
  final AbyssLApiClient? apiClient;
  final AppUpdateService? updateService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _documentService = const DocumentProcessingService();
  final _captureService = DesktopCaptureService();
  final _commandController = TextEditingController();
  final _commandFocusNode = FocusNode(debugLabel: 'AbyssL command input');
  final _styleMenuController = MenuController();
  final _sourceController = TextEditingController();
  final _translationController = TextEditingController();
  final _instructionController = TextEditingController();
  final _correctionInputController = HighlightingTextEditingController();
  final _correctionOutputController = HighlightingTextEditingController();
  final _correctionInstructionController = TextEditingController();
  final _alternativesInstructionController = TextEditingController();
  final _documentInstructionController = TextEditingController();
  final _synonymsScrollController = ScrollController();
  final _alternativesScrollController = ScrollController();
  Timer? _autoTranslateTimer;
  StreamSubscription<String>? _captureSubscription;
  late final AbyssLApiClient _apiClient;
  late final bool _ownsApiClient;

  var _selectedIndex = 0;
  var _isBusy = false;
  var _cancelRequested = false;
  var _status = '';
  var _synonyms = <String>[];
  var _alternatives = <String>[];
  var _correctionIssues = <WritingCorrectionIssue>[];
  var _rewritePreset = WritingStylePreset.standard;
  var _documentOptions = const DocumentOperationOptions();
  var _documentJobs = <DocumentJob>[];
  var _documentResults = <DocumentProcessingResult>[];
  var _documentProgress = const DocumentBatchProgress(
    total: 0,
    completed: 0,
    isRunning: false,
  );
  String? _documentOutputDirectory;
  CaptureStatus? _captureStatus;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.apiClient ?? AbyssLApiClient();
    _ownsApiClient = widget.apiClient == null;
    _captureSubscription = _captureService.capturedText.listen((text) {
      setState(() {
        _selectedIndex = 0;
        _sourceController.text = text;
      });
      if (widget.settings.autoTranslateEnabled) {
        unawaited(_translateNow());
      }
    });
    unawaited(_configureCapture());
    unawaited(_detectLocalModelAndReasoningAtStartup());
  }

  @override
  void dispose() {
    _autoTranslateTimer?.cancel();
    _captureSubscription?.cancel();
    _captureService.dispose();
    if (_ownsApiClient) {
      _apiClient.close();
    }
    _commandController.dispose();
    _commandFocusNode.dispose();
    _sourceController.dispose();
    _translationController.dispose();
    _instructionController.dispose();
    _correctionInputController.dispose();
    _correctionOutputController.dispose();
    _correctionInstructionController.dispose();
    _alternativesInstructionController.dispose();
    _documentInstructionController.dispose();
    _synonymsScrollController.dispose();
    _alternativesScrollController.dispose();
    super.dispose();
  }

  Future<void> _configureCapture() async {
    await _captureService.configure(widget.settings.captureShortcut);
    await _captureService.start();
    final status = await _captureService.platformStatus();
    if (mounted) {
      setState(() => _captureStatus = status);
    }
  }

  Future<void> _detectLocalModelAndReasoningAtStartup() async {
    if (widget.settings.selectedProvider !=
        TranslationProvider.localOpenAICompatible) {
      return;
    }
    try {
      final settings = widget.settings;
      final timeout = settings.localRequestTimeoutSeconds > 0
          ? Duration(seconds: settings.localRequestTimeoutSeconds)
          : null;
      final catalog = await _apiClient.fetchLocalModelCatalog(
        baseUri: settings.baseUriFor(TranslationProvider.localOpenAICompatible),
        apiKey: settings.localApiKey,
        authMode: settings.authModeFor(
          TranslationProvider.localOpenAICompatible,
        ),
        timeout: timeout,
      );
      final autoModel = _startupAutoModel(catalog);
      final modelName = autoModel?.requestName ?? settings.localModel.trim();
      if (modelName.isEmpty) {
        if (mounted && catalog.isNotEmpty) {
          setState(
            () => _status = 'Local LLM models found. Select one in Settings.',
          );
        }
        return;
      }

      LocalReasoningOptions? reasoningOptions;
      Object? reasoningError;
      try {
        reasoningOptions = await _apiClient.fetchLocalReasoningOptions(
          baseUri: settings.baseUriFor(
            TranslationProvider.localOpenAICompatible,
          ),
          apiKey: settings.localApiKey,
          authMode: settings.authModeFor(
            TranslationProvider.localOpenAICompatible,
          ),
          model: modelName,
          timeout: timeout,
        );
      } catch (error) {
        reasoningError = error;
      }

      final detectedReasoning = reasoningOptions;
      final resolvedModel =
          detectedReasoning?.resolvedModelName?.trim().isNotEmpty == true
          ? detectedReasoning!.resolvedModelName!.trim()
          : modelName;
      widget.settings.update((settings) {
        if (detectedReasoning == null) {
          settings.localModel = resolvedModel;
          settings.applyStoredReasoningSettingsForModel(resolvedModel);
        } else {
          settings.applyDetectedReasoningSettings(
            model: resolvedModel,
            options: detectedReasoning,
          );
        }
      });

      if (mounted) {
        setState(
          () => _status = _startupDetectionMessage(
            model: resolvedModel,
            reasoningOptions: reasoningOptions,
            reasoningError: reasoningError,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _status = 'Local LLM auto detection failed: $error');
      }
    }
  }

  LocalLLMModel? _startupAutoModel(List<LocalLLMModel> catalog) {
    final loaded = catalog.where((model) => model.isLoaded).toList();
    if (loaded.length == 1) return loaded.single;
    if (loaded.isEmpty && catalog.length == 1) return catalog.single;
    return null;
  }

  String _startupDetectionMessage({
    required String model,
    required LocalReasoningOptions? reasoningOptions,
    required Object? reasoningError,
  }) {
    if (reasoningOptions != null) {
      return 'Detected local model: $model. Reasoning options: ${reasoningOptions.allowedOptions.join(', ')}.';
    }
    if (reasoningError != null) {
      return 'Detected local model: $model. Reasoning metadata unavailable: $reasoningError';
    }
    return 'Detected local model: $model.';
  }

  ProviderRequestConfig _requestConfig() => widget.settings.requestConfig();

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_isBusy) return;
    setState(() {
      _apiClient.resetCancellation();
      _cancelRequested = false;
      _isBusy = true;
      _status = '';
    });
    try {
      await action();
    } on AbyssLRequestCancelledException {
      setState(() => _status = 'Request cancelled.');
    } catch (error) {
      setState(
        () => _status = _cancelRequested ? 'Request cancelled.' : '$error',
      );
    } finally {
      if (mounted) {
        setState(() {
          if (_cancelRequested && _status == 'Cancelling request...') {
            _status = 'Request cancelled.';
          }
          _isBusy = false;
          _cancelRequested = false;
          _apiClient.resetCancellation();
        });
      }
    }
  }

  void _cancelCurrentRequest() {
    if (!_isBusy) return;
    _autoTranslateTimer?.cancel();
    setState(() {
      _cancelRequested = true;
      _status = 'Cancelling request...';
    });
    _apiClient.cancelActiveRequests();
  }

  Widget _cancelRequestButton() {
    return OutlinedButton.icon(
      onPressed: _isBusy ? _cancelCurrentRequest : null,
      icon: const Icon(Icons.stop_circle_outlined),
      label: const Text('Cancel'),
    );
  }

  void _scheduleAutoTranslate(String _) {
    _autoTranslateTimer?.cancel();
    if (!widget.settings.autoTranslateEnabled) return;
    _autoTranslateTimer = Timer(const Duration(milliseconds: 650), () {
      if (_sourceController.text.trim().isNotEmpty) {
        unawaited(_translateNow());
      }
    });
  }

  void _setAutoTranslateEnabled(bool enabled) {
    if (!enabled) {
      _autoTranslateTimer?.cancel();
    }
    widget.settings.update(
      (settings) => settings.autoTranslateEnabled = enabled,
    );
    unawaited(_saveAutoTranslateEnabled());
  }

  Future<void> _saveAutoTranslateEnabled() async {
    try {
      await widget.settings.saveAutoTranslateEnabled();
    } catch (error) {
      if (mounted) {
        setState(
          () => _status = 'Auto translate setting was not saved: $error',
        );
      }
    }
  }

  Future<void> _translateNow() => _runBusy(() async {
    final result = await _apiClient.translate(
      text: _sourceController.text,
      instruction: _instructionController.text,
      config: _requestConfig(),
    );
    _translationController.text = result.translation;
    _synonyms = result.synonyms;
    _status = result.spellingNotes ?? '';
  });

  Future<void> _suggestAlternatives() => _runBusy(() async {
    final selection = _translationController.selection;
    final translatedText = _translationController.text;
    final selectedText = selection.isValid && !selection.isCollapsed
        ? selection.textInside(translatedText)
        : translatedText;
    _alternatives = await _apiClient.suggestAlternatives(
      selectedText: selectedText,
      targetContext: translatedText,
      userInstruction: _alternativesInstructionController.text,
      count: widget.settings.alternativeSuggestionCount,
      config: _requestConfig(),
    );
  });

  void _clearTranslatorTexts() {
    _autoTranslateTimer?.cancel();
    setState(() {
      _sourceController.clear();
      _translationController.clear();
      _synonyms = [];
      _alternatives = [];
      _status = '';
    });
  }

  bool get _canSwapTranslatorLanguages =>
      widget.settings.sourceLanguage != TranslationLanguage.automatic;

  void _swapTranslatorLanguages() {
    if (!_canSwapTranslatorLanguages) return;
    widget.settings.update((settings) {
      final source = settings.sourceLanguage;
      settings.sourceLanguage = settings.targetLanguage;
      settings.targetLanguage = source;
    });
  }

  void _clearCorrectionTexts() {
    setState(() {
      _correctionInputController.clear();
      _correctionOutputController.clear();
      _correctionInputController.setHighlights(const []);
      _correctionOutputController.setHighlights(const []);
      _correctionIssues = [];
      _status = '';
    });
  }

  void _clearCorrectionMarks() {
    if (_correctionIssues.isEmpty) return;
    setState(() {
      _correctionInputController.setHighlights(const []);
      _correctionOutputController.setHighlights(const []);
      _correctionIssues = [];
    });
  }

  Future<void> _correctWriting() => _runBusy(() async {
    final result = await _apiClient.correctWriting(
      text: _correctionInputController.text,
      instruction: _correctionInstructionController.text,
      config: _requestConfig(),
    );
    _correctionOutputController.text = result.correctedText;
    _correctionIssues = result.issues;
    _applyCorrectionHighlights(result.issues);
  });

  Future<void> _rewriteWriting() => _runBusy(() async {
    final rewritten = await _apiClient.rewriteWriting(
      text: _correctionInputController.text,
      instruction: _correctionInstructionController.text,
      stylePreset: _rewritePreset,
      config: _requestConfig(),
    );
    _correctionOutputController.text = rewritten;
    _correctionOutputController.setHighlights(const []);
    _correctionInputController.setHighlights(const []);
    _correctionIssues = [];
  });

  void _applyCorrectionHighlights(List<WritingCorrectionIssue> issues) {
    final colors = Theme.of(context).colorScheme;
    _correctionInputController.setHighlights(
      _rangesForIssues(
        issues: issues,
        text: _correctionInputController.text,
        useOriginalText: true,
        style: TextStyle(
          color: colors.error,
          fontWeight: FontWeight.w700,
          backgroundColor: colors.errorContainer.withAlpha(90),
        ),
      ),
    );
    _correctionOutputController.setHighlights(
      _rangesForIssues(
        issues: issues,
        text: _correctionOutputController.text,
        useOriginalText: false,
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: colors.primaryContainer.withAlpha(90),
        ),
      ),
    );
  }

  List<HighlightRange> _rangesForIssues({
    required List<WritingCorrectionIssue> issues,
    required String text,
    required bool useOriginalText,
    required TextStyle style,
  }) {
    final ranges = <HighlightRange>[];
    var searchStart = 0;
    for (final issue in issues) {
      final phrase = useOriginalText ? issue.originalText : issue.correctedText;
      final storedStart = useOriginalText
          ? issue.originalStart
          : issue.correctedStart ?? issue.start;
      final storedLength = useOriginalText
          ? issue.originalLength
          : issue.correctedLength ?? issue.length;
      var start = storedStart;
      var length = storedLength;
      if (start == null ||
          length == null ||
          !_isValidRange(text, start, length)) {
        final index = text.indexOf(phrase, searchStart);
        start = index >= 0 ? index : null;
        length = start == null ? null : phrase.length;
      }
      if (start == null ||
          length == null ||
          !_isValidRange(text, start, length)) {
        continue;
      }
      ranges.add(
        HighlightRange(start: start, end: start + length, style: style),
      );
      searchStart = start + length;
    }
    return ranges;
  }

  bool _isValidRange(String text, int start, int length) =>
      start >= 0 && length > 0 && start + length <= text.length;

  String _correctionIssueCountLabel() {
    final count = _correctionIssues.length;
    return count == 1 ? '1 error' : '$count errors';
  }

  Future<void> _pickDocumentFiles() async {
    final result = await FilePicker.pickFiles(allowMultiple: true);
    if (result == null) return;
    _addDocumentPaths(result.paths.nonNulls.toList());
  }

  Future<void> _pickDocumentFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    _addDocumentPaths([path]);
  }

  Future<void> _pickOutputFolder() async {
    final path = await FilePicker.getDirectoryPath();
    if (path == null) return;
    setState(() => _documentOutputDirectory = path);
  }

  void _addDocumentPaths(List<String> paths) {
    final next = DocumentProcessingService.collectJobsFromPaths(paths);
    setState(() {
      _documentJobs = [..._documentJobs, ...next];
      final hasSpreadsheet = _documentJobs.any(
        (job) => job.inputKind.isSpreadsheet,
      );
      final available = DocumentProcessingService.availableExportFormats(
        hasSpreadsheetInput: hasSpreadsheet,
      );
      if (!available.contains(_documentOptions.exportFormat)) {
        _documentOptions = _documentOptions.copyWith(
          exportFormat: available.first,
        );
      }
    });
  }

  Future<void> _processDocuments() => _runBusy(() async {
    final outputDirectory = _documentOutputDirectory;
    if (_documentJobs.isEmpty) {
      throw const DocumentProcessingException(
        'Add at least one file or folder.',
      );
    }
    if (outputDirectory == null || outputDirectory.trim().isEmpty) {
      throw const DocumentProcessingException('Choose an output folder.');
    }
    final options = _documentOptions.copyWith(
      instruction: _documentInstructionController.text,
    );
    final results = await _documentService.process(
      jobs: _documentJobs,
      destinationDirectory: outputDirectory,
      options: options,
      configuration: DocumentProcessingConfiguration(
        requestConfig: _requestConfig(),
        apiClient: _apiClient,
      ),
      onProgress: (progress) => setState(() => _documentProgress = progress),
    );
    _documentResults = results;
  });

  Future<void> _openSettings() async {
    await showDialog<void>(
      context: context,
      builder: (context) => SettingsDialog(
        settings: widget.settings,
        apiClient: _apiClient,
        updateService: widget.updateService,
        onSaved: () async {
          await _configureCapture();
          setState(() {});
        },
      ),
    );
  }

  void _focusCommand() {
    _commandFocusNode.requestFocus();
    _commandController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _commandController.text.length,
    );
  }

  void _submitCommand(String rawCommand) {
    final command = rawCommand.trim().toLowerCase();
    if (command.isEmpty) return;

    if (command.contains('setting') || command.contains('einstellung')) {
      _commandController.clear();
      unawaited(_openSettings());
      return;
    }
    if (command.startsWith('translate') || command.startsWith('übersetz')) {
      setState(() => _selectedIndex = 0);
      if (_sourceController.text.trim().isNotEmpty) {
        unawaited(_translateNow());
      }
    } else if (command.startsWith('correct') || command.startsWith('korrig')) {
      setState(() => _selectedIndex = 1);
      if (_correctionInputController.text.trim().isNotEmpty) {
        unawaited(_correctWriting());
      }
    } else if (command.startsWith('rewrite') ||
        command.startsWith('umschreib')) {
      setState(() => _selectedIndex = 1);
      if (_correctionInputController.text.trim().isNotEmpty) {
        unawaited(_rewriteWriting());
      }
    } else if (command.startsWith('document') ||
        command.startsWith('dokument')) {
      setState(() => _selectedIndex = 2);
    } else if (command.startsWith('process') ||
        command.startsWith('verarbeit')) {
      setState(() => _selectedIndex = 2);
      if (_documentJobs.isNotEmpty && _documentOutputDirectory != null) {
        unawaited(_processDocuments());
      }
    } else {
      setState(
        () => _status =
            'Unknown command. Try Translate, Correct, Rewrite, Documents, or Settings.',
      );
    }
    _commandController.clear();
  }

  void _runPrimaryAction() {
    if (_isBusy) return;
    switch (_selectedIndex) {
      case 0:
        unawaited(_translateNow());
      case 1:
        unawaited(_correctWriting());
      default:
        unawaited(_processDocuments());
    }
  }

  String get _primaryActionLabel => switch (_selectedIndex) {
    0 => 'Translate',
    1 => 'Correct',
    _ => 'Process',
  };

  IconData get _primaryActionIcon => switch (_selectedIndex) {
    0 => Icons.translate,
    1 => Icons.spellcheck,
    _ => Icons.play_arrow_rounded,
  };

  String get _styleSummary {
    final settings = widget.settings;
    final isNeutral =
        settings.styleRegister == RegisterStyle.neutral &&
        settings.styleComplexity == ComplexityStyle.neutral &&
        settings.spellingMode == SpellingMode.preserve;
    return isNeutral ? 'Neutral' : 'Custom';
  }

  void _resetStyleSettings() {
    widget.settings.update((settings) {
      settings.styleRegister = RegisterStyle.neutral;
      settings.styleComplexity = ComplexityStyle.neutral;
      settings.spellingMode = SpellingMode.preserve;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settings,
      builder: (context, _) {
        final content = switch (_selectedIndex) {
          0 => _translatorView(),
          1 => _correctionView(),
          _ => _documentView(),
        };
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            final railWidth = constraints.maxWidth >= 1200 ? 102.0 : 88.0;
            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                    _focusCommand,
                const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                    _focusCommand,
                const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                    _runPrimaryAction,
                const SingleActivator(LogicalKeyboardKey.enter, control: true):
                    _runPrimaryAction,
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  body: Column(
                    children: [
                      _workspaceTopBar(
                        width: constraints.maxWidth,
                        compact: compact,
                      ),
                      Expanded(
                        child: Row(
                          children: [
                            _workspaceRail(width: railWidth),
                            Expanded(
                              child: ColoredBox(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                child: content,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _statusBar(compact: compact),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _workspaceTopBar({required double width, required bool compact}) {
    final showLanguageControls = width >= 1200 && _selectedIndex == 0;
    final showWordmark = width >= 900;
    final barHeight = compact ? 68.0 : 84.0;
    return Container(
      key: const ValueKey('command-bar'),
      height: barHeight,
      padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
      decoration: const BoxDecoration(
        color: AbyssLPalette.ink,
        border: Border(bottom: BorderSide(color: AbyssLPalette.inkBorder)),
      ),
      child: Row(
        children: [
          KeyedSubtree(
            key: const ValueKey('app-brand'),
            child: AbyssLBrand(showWordmark: showWordmark),
          ),
          SizedBox(width: compact ? 12 : 20),
          if (compact)
            SizedBox(
              width: 126,
              height: 44,
              child: OutlinedButton.icon(
                key: const ValueKey('command-input'),
                onPressed: _focusCommand,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDCE2EC),
                  backgroundColor: AbyssLPalette.inkRaised,
                  side: const BorderSide(color: AbyssLPalette.inkBorder),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.search, size: 20),
                label: const Text('Command'),
              ),
            )
          else
            Expanded(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SizedBox(
                  height: 54,
                  child: TextField(
                    key: const ValueKey('command-input'),
                    controller: _commandController,
                    focusNode: _commandFocusNode,
                    onSubmitted: _submitCommand,
                    textInputAction: TextInputAction.done,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    decoration: InputDecoration(
                      hintText: 'Type a command or press ⌘K',
                      hintStyle: const TextStyle(color: Color(0xFFB4B8C1)),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Color(0xFFB4B8C1),
                      ),
                      suffixIcon: const Center(
                        widthFactor: 1,
                        child: AbyssLKeyboardHint('⌘K', dark: true),
                      ),
                      filled: true,
                      fillColor: AbyssLPalette.inkRaised,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AbyssLPalette.inkBorder,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AbyssLPalette.inkBorder,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: AbyssLPalette.blue,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!compact) const SizedBox(width: 14),
          if (showLanguageControls) ...[
            _topLanguagePicker(
              key: const ValueKey('source-language-top'),
              label: 'Source',
              value: widget.settings.sourceLanguage,
              values: TranslationLanguage.values,
              onChanged: (value) => widget.settings.update(
                (settings) => settings.sourceLanguage = value,
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Icon(
                Icons.arrow_forward,
                color: Color(0xFFB4B8C1),
                size: 20,
              ),
            ),
            _topLanguagePicker(
              key: const ValueKey('target-language-top'),
              label: 'Target',
              value: widget.settings.targetLanguage,
              values: TranslationLanguage.values
                  .where(
                    (language) => language != TranslationLanguage.automatic,
                  )
                  .toList(),
              onChanged: (value) => widget.settings.update(
                (settings) => settings.targetLanguage = value,
              ),
            ),
            const SizedBox(width: 16),
          ] else
            const Spacer(),
          SizedBox(
            key: const ValueKey('translate-primary'),
            height: compact ? 44 : 54,
            child: FilledButton.icon(
              onPressed: _isBusy ? null : _runPrimaryAction,
              icon: Icon(_primaryActionIcon, size: 20),
              label: Text(_primaryActionLabel),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topLanguagePicker({
    required Key key,
    required String label,
    required TranslationLanguage value,
    required List<TranslationLanguage> values,
    required ValueChanged<TranslationLanguage> onChanged,
  }) {
    return Container(
      key: key,
      width: 190,
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
      decoration: BoxDecoration(
        color: AbyssLPalette.inkRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AbyssLPalette.inkBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TranslationLanguage>(
          value: value,
          isExpanded: true,
          dropdownColor: AbyssLPalette.inkRaised,
          iconEnabledColor: const Color(0xFFB4B8C1),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          items: values
              .map(
                (language) => DropdownMenuItem(
                  value: language,
                  child: Text(language.label),
                ),
              )
              .toList(),
          selectedItemBuilder: (context) => values
              .map(
                (language) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFB4B8C1),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }

  Widget _workspaceRail({required double width}) {
    return Container(
      key: const ValueKey('workspace-rail'),
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          KeyedSubtree(
            key: const ValueKey('nav-translator'),
            child: AbyssLNavItem(
              icon: Icons.translate,
              label: 'Translate',
              selected: _selectedIndex == 0,
              onTap: () => setState(() => _selectedIndex = 0),
            ),
          ),
          const SizedBox(height: 6),
          KeyedSubtree(
            key: const ValueKey('nav-correction'),
            child: AbyssLNavItem(
              icon: Icons.edit_note_outlined,
              label: 'Correction',
              selected: _selectedIndex == 1,
              onTap: () => setState(() => _selectedIndex = 1),
            ),
          ),
          const SizedBox(height: 6),
          KeyedSubtree(
            key: const ValueKey('nav-documents'),
            child: AbyssLNavItem(
              icon: Icons.description_outlined,
              label: 'Documents',
              selected: _selectedIndex == 2,
              onTap: () => setState(() => _selectedIndex = 2),
            ),
          ),
          const Spacer(),
          KeyedSubtree(
            key: const ValueKey('nav-settings'),
            child: AbyssLNavItem(
              icon: Icons.settings_outlined,
              label: 'Settings',
              selected: false,
              onTap: _openSettings,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _statusBar({required bool compact}) {
    final message = _status;
    if (!_isBusy && message.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            if (_isBusy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (!compact && _captureStatus != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Tooltip(
                  message: _captureStatus!.message,
                  child: AbyssLKeyboardHint(
                    widget.settings.captureShortcut.displayName,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _translatorView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final tightHeight = constraints.maxHeight < 620;
        final horizontalPadding = compact ? 12.0 : 20.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            compact ? 10 : 20,
            horizontalPadding,
            compact ? 10 : 16,
          ),
          child: Column(
            children: [
              Expanded(
                flex: 58,
                child: _translatorSourcePane(compact: compact),
              ),
              SizedBox(height: compact ? 10 : 18),
              _translatorBridge(compact: compact),
              SizedBox(height: compact ? 12 : 20),
              Expanded(
                flex: 42,
                child: _translatorResultPane(
                  compact: compact,
                  tightHeight: tightHeight,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _translatorSourcePane({required bool compact}) {
    return AbyssLPane(
      key: const ValueKey('translator-source-pane'),
      headerHeight: compact ? 68 : 90,
      header: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AbyssLSectionLabel('Direct instruction'),
                const SizedBox(height: 5),
                TextField(
                  key: const ValueKey('direct-instruction'),
                  controller: _instructionController,
                  minLines: 1,
                  maxLines: 1,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText:
                        'Provide context or instructions for translation…',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _styleMenu(compact: compact),
        ],
      ),
      child: Stack(
        children: [
          TextField(
            key: const ValueKey('source-editor'),
            controller: _sourceController,
            onChanged: _scheduleAutoTranslate,
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontSize: widget.settings.editorFontSize,
              height: 1.75,
            ),
            decoration: const InputDecoration(
              hintText: 'Type or paste your source text here…',
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(32, 24, 32, 38),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 12,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _sourceController,
              builder: (context, value, _) => Text(
                '${value.text.length} / 10,000',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleMenu({required bool compact}) {
    final brightness = Theme.of(context).brightness;
    return MenuAnchor(
      controller: _styleMenuController,
      alignmentOffset: const Offset(-214, 8),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        elevation: const WidgetStatePropertyAll(12),
        backgroundColor: WidgetStatePropertyAll(
          AbyssLPalette.surfaceFor(brightness),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: AbyssLPalette.outlineFor(brightness)),
          ),
        ),
      ),
      menuChildren: [
        KeyedSubtree(
          key: const ValueKey('style-popover'),
          child: SizedBox(
            width: 320,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Translation style',
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close style options',
                        onPressed: _styleMenuController.close,
                        icon: const Icon(Icons.close, size: 19),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _styleOptionRow(
                    leading: const Icon(Icons.person_outline, size: 21),
                    field: _enumDropdown(
                      label: 'Register',
                      value: widget.settings.styleRegister,
                      values: RegisterStyle.values,
                      text: (value) => value.label,
                      onChanged: (value) => widget.settings.update(
                        (settings) => settings.styleRegister = value,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _styleOptionRow(
                    leading: const Icon(Icons.bar_chart_outlined, size: 21),
                    field: _enumDropdown(
                      label: 'Complexity',
                      value: widget.settings.styleComplexity,
                      values: ComplexityStyle.values,
                      text: (value) => value.label,
                      onChanged: (value) => widget.settings.update(
                        (settings) => settings.styleComplexity = value,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _styleOptionRow(
                    leading: const Text(
                      'ABC',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    field: _enumDropdown(
                      label: 'Spelling',
                      value: widget.settings.spellingMode,
                      values: SpellingMode.values,
                      text: (value) => value.label,
                      onChanged: (value) => widget.settings.update(
                        (settings) => settings.spellingMode = value,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _resetStyleSettings,
                      child: const Text('Reset to defaults'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      builder: (context, controller, child) => TextButton.icon(
        key: const ValueKey('style-trigger'),
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.tune, size: 19),
        label: Text(compact ? _styleSummary : 'Style: $_styleSummary'),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
    );
  }

  Widget _styleOptionRow({required Widget leading, required Widget field}) {
    return Row(
      children: [
        SizedBox(width: 24, child: Center(child: leading)),
        const SizedBox(width: 10),
        Expanded(child: field),
      ],
    );
  }

  Widget _translatorBridge({required bool compact}) {
    final brightness = Theme.of(context).brightness;
    final pickerWidth = compact ? 138.0 : 190.0;
    return Container(
      key: const ValueKey('translation-bridge'),
      height: compact ? 58 : 66,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: AbyssLPalette.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AbyssLPalette.outlineFor(brightness)),
      ),
      child: Row(
        children: [
          _bridgeLanguagePicker(
            key: const ValueKey('source-language'),
            label: 'Source',
            width: pickerWidth,
            value: widget.settings.sourceLanguage,
            values: TranslationLanguage.values,
            leading: Icons.auto_awesome,
            onChanged: (value) => widget.settings.update(
              (settings) => settings.sourceLanguage = value,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 10),
            child: Icon(
              Icons.arrow_forward,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          _bridgeLanguagePicker(
            key: const ValueKey('target-language'),
            label: 'Target',
            width: pickerWidth,
            value: widget.settings.targetLanguage,
            values: TranslationLanguage.values
                .where((language) => language != TranslationLanguage.automatic)
                .toList(),
            leading: Icons.language,
            onChanged: (value) => widget.settings.update(
              (settings) => settings.targetLanguage = value,
            ),
          ),
          SizedBox(width: compact ? 5 : 10),
          IconButton.outlined(
            key: const ValueKey('swap-languages'),
            tooltip: _canSwapTranslatorLanguages
                ? 'Swap source and target languages'
                : 'Choose a fixed source language to swap languages',
            onPressed: _isBusy || !_canSwapTranslatorLanguages
                ? null
                : _swapTranslatorLanguages,
            icon: const Icon(Icons.swap_horiz, size: 20),
          ),
          SizedBox(width: compact ? 6 : 14),
          _autoTranslateSwitch(compact: compact),
          if (!compact) ...[
            const SizedBox(width: 14),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _translationController,
              builder: (context, value, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: value.text.trim().isEmpty
                          ? Theme.of(context).colorScheme.outline
                          : AbyssLPalette.success,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    value.text.trim().isEmpty ? 'Ready' : 'Translated',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          if (compact)
            IconButton(
              tooltip: 'Clear source and translation',
              onPressed: _isBusy ? null : _clearTranslatorTexts,
              icon: const Icon(Icons.close),
            )
          else
            Tooltip(
              message: 'Clear source and translation',
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _clearTranslatorTexts,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bridgeLanguagePicker({
    required Key key,
    required String label,
    required double width,
    required TranslationLanguage value,
    required List<TranslationLanguage> values,
    required IconData leading,
    required ValueChanged<TranslationLanguage> onChanged,
  }) {
    return KeyedSubtree(
      key: key,
      child: SizedBox(
        width: width,
        child: DropdownButtonFormField<TranslationLanguage>(
          key: ValueKey(value),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(leading, size: 18),
            isDense: true,
            contentPadding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          ),
          items: values
              .map(
                (language) => DropdownMenuItem(
                  value: language,
                  child: Text(
                    language.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }

  Widget _translatorResultPane({
    required bool compact,
    required bool tightHeight,
  }) {
    final hasSuggestions = _synonyms.isNotEmpty || _alternatives.isNotEmpty;
    return AbyssLPane(
      key: const ValueKey('translator-result-pane'),
      header: Row(
        children: [
          const AbyssLSectionLabel('Translation', color: AbyssLPalette.blue),
          const Spacer(),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _translationController,
            builder: (context, value, _) {
              final enabled = value.text.trim().isNotEmpty && !_isBusy;
              if (compact) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Copy translation',
                      onPressed: enabled
                          ? () => Clipboard.setData(
                              ClipboardData(text: value.text),
                            )
                          : null,
                      icon: const Icon(Icons.copy_outlined, size: 20),
                    ),
                    IconButton(
                      tooltip: 'Alternatives',
                      onPressed: enabled ? _suggestAlternatives : null,
                      icon: const Icon(Icons.auto_awesome, size: 20),
                    ),
                  ],
                );
              }
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: enabled
                        ? () =>
                              Clipboard.setData(ClipboardData(text: value.text))
                        : null,
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? _suggestAlternatives : null,
                    icon: const Icon(Icons.auto_awesome, size: 18),
                    label: const Text('Alternatives'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      footer: hasSuggestions
          ? _translatorSuggestions(compact: compact || tightHeight)
          : null,
      child: TextField(
        key: const ValueKey('translation-editor'),
        controller: _translationController,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontSize: widget.settings.editorFontSize,
          height: 1.65,
        ),
        decoration: const InputDecoration(
          hintText: 'Your translation will appear here…',
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(20, 18, 20, 18),
        ),
      ),
    );
  }

  Widget _translatorSuggestions({required bool compact}) {
    if (compact) {
      final suggestions = [..._synonyms, ..._alternatives];
      return SizedBox(
        height: 48,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) => ActionChip(
            label: Text(suggestions[index]),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: suggestions[index])),
          ),
        ),
      );
    }
    return SizedBox(
      height: 106,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        child: Row(
          children: [
            Expanded(
              child: _chipPanel(
                title: 'Synonyms',
                values: _synonyms,
                controller: _synonymsScrollController,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  SizedBox(
                    height: 42,
                    child: TextField(
                      controller: _alternativesInstructionController,
                      decoration: const InputDecoration(
                        labelText: 'Alternative instruction',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _chipPanel(
                      title: 'Alternatives',
                      values: _alternatives,
                      controller: _alternativesScrollController,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _autoTranslateSwitch({bool compact = false}) {
    return Tooltip(
      message: widget.settings.autoTranslateEnabled
          ? 'Auto translate after Source changes'
          : 'Manual translation only',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            key: const ValueKey('auto-translate-switch'),
            value: widget.settings.autoTranslateEnabled,
            onChanged: _setAutoTranslateEnabled,
          ),
          if (!compact) ...[
            const SizedBox(width: 4),
            const Text('Auto-translate'),
          ],
        ],
      ),
    );
  }

  Widget _correctionView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final tightHeight = constraints.maxHeight < 620;
        final padding = compact ? 12.0 : 20.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            compact ? 10 : 20,
            padding,
            compact ? 10 : 16,
          ),
          child: Column(
            children: [
              Expanded(
                flex: 56,
                child: _correctionSourcePane(compact: compact),
              ),
              SizedBox(height: compact ? 10 : 18),
              _correctionBridge(compact: compact),
              SizedBox(height: compact ? 12 : 20),
              Expanded(
                flex: 44,
                child: _correctionResultPane(
                  compact: compact,
                  tightHeight: tightHeight,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _correctionSourcePane({required bool compact}) {
    return AbyssLPane(
      key: const ValueKey('correction-source-pane'),
      headerHeight: compact ? 72 : 90,
      header: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AbyssLSectionLabel('Correction instruction'),
                const SizedBox(height: 5),
                TextField(
                  key: const ValueKey('correction-instruction'),
                  controller: _correctionInstructionController,
                  minLines: 1,
                  maxLines: 1,
                  decoration: const InputDecoration(
                    hintText:
                        'Describe how the text should be corrected or rewritten…',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: compact ? 152 : 190,
            child: _enumDropdown(
              label: 'Rewrite style',
              value: _rewritePreset,
              values: WritingStylePreset.values,
              text: (value) => value.label,
              onChanged: (value) => setState(() => _rewritePreset = value),
            ),
          ),
        ],
      ),
      child: Stack(
        children: [
          TextField(
            key: const ValueKey('correction-input-editor'),
            controller: _correctionInputController,
            onChanged: (_) => _clearCorrectionMarks(),
            expands: true,
            minLines: null,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            style: TextStyle(
              fontSize: widget.settings.editorFontSize,
              height: 1.7,
            ),
            decoration: const InputDecoration(
              hintText: 'Type or paste the text you want to improve…',
              filled: true,
              fillColor: Colors.transparent,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.fromLTRB(32, 24, 32, 38),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 12,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _correctionInputController,
              builder: (context, value, _) => Text(
                '${value.text.length} characters',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _correctionBridge({required bool compact}) {
    final brightness = Theme.of(context).brightness;
    return Container(
      key: const ValueKey('correction-action-bridge'),
      height: compact ? 58 : 66,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: AbyssLPalette.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AbyssLPalette.outlineFor(brightness)),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            key: const ValueKey('rewrite-primary'),
            onPressed: _isBusy ? null : _rewriteWriting,
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text('Rewrite'),
          ),
          if (_isBusy) ...[const SizedBox(width: 8), _cancelRequestButton()],
          if (!compact && _correctionIssues.isNotEmpty) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 17,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(_correctionIssueCountLabel()),
                ],
              ),
            ),
          ],
          const Spacer(),
          if (compact)
            IconButton(
              tooltip: 'Clear input and correction',
              onPressed: _isBusy ? null : _clearCorrectionTexts,
              icon: const Icon(Icons.close),
            )
          else
            Tooltip(
              message: 'Clear input and correction',
              child: OutlinedButton.icon(
                onPressed: _isBusy ? null : _clearCorrectionTexts,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Clear'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _correctionResultPane({
    required bool compact,
    required bool tightHeight,
  }) {
    final hasIssues = _correctionIssues.isNotEmpty;
    return AbyssLPane(
      key: const ValueKey('correction-result-pane'),
      header: Row(
        children: [
          const AbyssLSectionLabel(
            'Corrected / rewritten text',
            color: AbyssLPalette.blue,
          ),
          if (hasIssues) ...[
            const SizedBox(width: 10),
            Text(
              _correctionIssueCountLabel(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const Spacer(),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _correctionOutputController,
            builder: (context, value, _) => compact
                ? IconButton(
                    tooltip: 'Copy result',
                    onPressed: value.text.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: value.text),
                          ),
                    icon: const Icon(Icons.copy_outlined, size: 20),
                  )
                : OutlinedButton.icon(
                    onPressed: value.text.isEmpty
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: value.text),
                          ),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: const Text('Copy'),
                  ),
          ),
        ],
      ),
      footer: hasIssues
          ? _correctionIssuesPanel(compact: compact || tightHeight)
          : null,
      child: TextField(
        key: const ValueKey('correction-output-editor'),
        controller: _correctionOutputController,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontSize: widget.settings.editorFontSize,
          height: 1.65,
        ),
        decoration: const InputDecoration(
          hintText: 'The corrected or rewritten text will appear here…',
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: EdgeInsets.fromLTRB(20, 18, 20, 18),
        ),
      ),
    );
  }

  Widget _correctionIssuesPanel({required bool compact}) {
    if (compact) {
      return SizedBox(
        height: 48,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          scrollDirection: Axis.horizontal,
          itemCount: _correctionIssues.length,
          separatorBuilder: (context, index) => const SizedBox(width: 6),
          itemBuilder: (context, index) {
            final issue = _correctionIssues[index];
            return Chip(
              avatar: const Icon(Icons.error_outline, size: 16),
              label: Text(
                issue.originalText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          },
        ),
      );
    }
    return SizedBox(
      height: 132,
      child: ListView.separated(
        padding: const EdgeInsets.all(10),
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) => SizedBox(
          width: 320,
          child: CorrectionIssueCard(issue: _correctionIssues[index]),
        ),
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemCount: _correctionIssues.length,
      ),
    );
  }

  Widget _documentView() {
    final hasSpreadsheet = _documentJobs.any(
      (job) => job.inputKind.isSpreadsheet,
    );
    final formats = DocumentProcessingService.availableExportFormats(
      hasSpreadsheetInput: hasSpreadsheet,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final padding = compact ? 12.0 : 20.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            padding,
            compact ? 10 : 20,
            padding,
            compact ? 10 : 16,
          ),
          child: Column(
            children: [
              Expanded(flex: 56, child: _documentIntakePane(compact: compact)),
              SizedBox(height: compact ? 10 : 18),
              _documentOptionsBridge(compact: compact, formats: formats),
              SizedBox(height: compact ? 12 : 20),
              Expanded(flex: 44, child: _documentResultsPane(compact: compact)),
            ],
          ),
        );
      },
    );
  }

  Widget _documentIntakePane({required bool compact}) {
    return DropTarget(
      key: const ValueKey('document-drop-target'),
      onDragDone: (details) =>
          _addDocumentPaths(details.files.map((file) => file.path).toList()),
      child: AbyssLPane(
        key: const ValueKey('document-intake-pane'),
        headerHeight: compact ? 96 : 100,
        header: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (compact)
                  IconButton.filled(
                    tooltip: 'Add files',
                    onPressed: _pickDocumentFiles,
                    icon: const Icon(Icons.note_add_outlined),
                  )
                else
                  FilledButton.icon(
                    onPressed: _pickDocumentFiles,
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: const Text('Add files'),
                  ),
                const SizedBox(width: 8),
                if (compact)
                  IconButton.outlined(
                    tooltip: 'Add folder',
                    onPressed: _pickDocumentFolder,
                    icon: const Icon(Icons.create_new_folder_outlined),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _pickDocumentFolder,
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 18,
                    ),
                    label: const Text('Add folder'),
                  ),
                const SizedBox(width: 8),
                if (compact)
                  IconButton.outlined(
                    tooltip: 'Output folder',
                    onPressed: _pickOutputFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _pickOutputFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Output folder'),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _documentOutputDirectory ?? 'No output folder selected',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_documentJobs.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${_documentJobs.length} queued',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 7),
            SizedBox(
              height: 38,
              child: TextField(
                key: const ValueKey('document-instruction'),
                controller: _documentInstructionController,
                decoration: const InputDecoration(
                  hintText: 'Optional instruction for all documents…',
                  prefixIcon: Icon(Icons.tune, size: 18),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        child: _documentJobList(),
      ),
    );
  }

  Widget _documentOptionsBridge({
    required bool compact,
    required List<DocumentExportFormat> formats,
  }) {
    final brightness = Theme.of(context).brightness;
    return Container(
      key: const ValueKey('document-options-bridge'),
      height: compact ? 60 : 66,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: AbyssLPalette.surfaceFor(brightness),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AbyssLPalette.outlineFor(brightness)),
      ),
      child: Row(
        children: [
          FilterChip(
            key: const ValueKey('document-correct-toggle'),
            selected: _documentOptions.shouldCorrect,
            avatar: const Icon(Icons.spellcheck, size: 17),
            label: Text(compact ? 'Correct' : 'Correct text'),
            onSelected: (value) => setState(
              () => _documentOptions = _documentOptions.copyWith(
                shouldCorrect: value,
              ),
            ),
          ),
          const SizedBox(width: 7),
          FilterChip(
            key: const ValueKey('document-translate-toggle'),
            selected: _documentOptions.shouldTranslate,
            avatar: const Icon(Icons.translate, size: 17),
            label: const Text('Translate'),
            onSelected: (value) => setState(
              () => _documentOptions = _documentOptions.copyWith(
                shouldTranslate: value,
              ),
            ),
          ),
          SizedBox(width: compact ? 7 : 12),
          SizedBox(
            width: compact ? 132 : 170,
            child: _enumDropdown(
              label: 'Export',
              value: _documentOptions.exportFormat,
              values: formats,
              text: (value) => value.label,
              onChanged: (value) => setState(
                () => _documentOptions = _documentOptions.copyWith(
                  exportFormat: value,
                ),
              ),
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            Text(
              _documentProgress.total == 0
                  ? 'Ready'
                  : '${_documentProgress.completed} / ${_documentProgress.total}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const Spacer(),
          if (_isBusy) _cancelRequestButton(),
        ],
      ),
    );
  }

  Widget _documentResultsPane({required bool compact}) {
    final progress = _documentProgress.total == 0
        ? 0.0
        : _documentProgress.completed / _documentProgress.total;
    return AbyssLPane(
      key: const ValueKey('document-results-pane'),
      header: Row(
        children: [
          const AbyssLSectionLabel(
            'Processing results',
            color: AbyssLPalette.blue,
          ),
          const Spacer(),
          if (_documentProgress.total > 0) ...[
            SizedBox(
              width: compact ? 86 : 140,
              child: LinearProgressIndicator(value: progress),
            ),
            const SizedBox(width: 10),
            Text(
              '${_documentProgress.completed} / ${_documentProgress.total}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else
            Text(
              'Results appear here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      child: _documentResultList(),
    );
  }

  Widget _documentJobList() {
    if (_documentJobs.isEmpty) {
      return const Center(child: Text('Drop files or folders here.'));
    }
    return ListView.builder(
      itemCount: _documentJobs.length,
      itemBuilder: (context, index) {
        final job = _documentJobs[index];
        return ListTile(
          dense: true,
          leading: Icon(
            job.statusMessage == null
                ? Icons.description_outlined
                : Icons.warning_amber_outlined,
          ),
          title: Text(job.displayName),
          subtitle: Text(job.statusMessage ?? job.inputKind.name),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close),
            onPressed: () => setState(
              () => _documentJobs = [..._documentJobs]..removeAt(index),
            ),
          ),
        );
      },
    );
  }

  Widget _documentResultList() {
    if (_documentResults.isEmpty) {
      return const Center(child: Text('Results appear here.'));
    }
    return ListView.builder(
      itemCount: _documentResults.length,
      itemBuilder: (context, index) {
        final result = _documentResults[index];
        return ListTile(
          dense: true,
          leading: Icon(
            result.status == DocumentResultStatus.success
                ? Icons.check_circle_outline
                : Icons.error_outline,
            color: result.status == DocumentResultStatus.success
                ? Colors.green
                : Colors.red,
          ),
          title: Text(
            result.outputPath ?? result.sourcePath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            result.message,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  Widget _chipPanel({
    required String title,
    required List<String> values,
    required ScrollController controller,
  }) {
    return ResultChipPanel(
      title: title,
      values: values,
      controller: controller,
    );
  }

  Widget _enumDropdown<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T value) text,
    required ValueChanged<T> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                text(item),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _SettingsDialogSnapshot {
  _SettingsDialogSnapshot._(this._restore);

  factory _SettingsDialogSnapshot.capture(AppSettingsStore settings) {
    final openAIApiKey = settings.openAIApiKey;
    final anthropicApiKey = settings.anthropicApiKey;
    final localApiKey = settings.localApiKey;
    final openAIBaseUrl = settings.openAIBaseUrl;
    final openAIModelId = settings.openAIModelId;
    final openAIAuthMode = settings.openAIAuthMode;
    final openAIRequestTimeoutSeconds = settings.openAIRequestTimeoutSeconds;
    final anthropicBaseUrl = settings.anthropicBaseUrl;
    final anthropicModelId = settings.anthropicModelId;
    final anthropicAuthMode = settings.anthropicAuthMode;
    final anthropicRequestTimeoutSeconds =
        settings.anthropicRequestTimeoutSeconds;
    final anthropicVersion = settings.anthropicVersion;
    final localBaseUrl = settings.localBaseUrl;
    final localModel = settings.localModel;
    final localAuthMode = settings.localAuthMode;
    final localRequestTimeoutSeconds = settings.localRequestTimeoutSeconds;
    final selectedProvider = settings.selectedProvider;
    final themeMode = settings.themeMode;
    final llmProfiles = List<LLMProfile>.unmodifiable(settings.llmProfiles);
    final selectedLLMProfileID = settings.selectedLLMProfileID;
    final llmReasoningSettings =
        Map<String, LLMReasoningSettings>.unmodifiable({
          for (final entry in settings.llmReasoningSettings.entries)
            entry.key: LLMReasoningSettings(
              model: entry.value.model,
              allowedOptions: List<String>.unmodifiable(
                entry.value.allowedOptions,
              ),
              reasoningOnValue: entry.value.reasoningOnValue,
              reasoningOffValue: entry.value.reasoningOffValue,
              reasoningEnabled: entry.value.reasoningEnabled,
            ),
        });
    final autoTranslateEnabled = settings.autoTranslateEnabled;
    final reasoningOnValue = settings.reasoningOnValue;
    final reasoningOffValue = settings.reasoningOffValue;
    final reasoningEnabled = settings.reasoningEnabled;
    final alternativeSuggestionCount = settings.alternativeSuggestionCount;
    final correctionAlternativeCount = settings.correctionAlternativeCount;
    final editorFontSize = settings.editorFontSize;
    final captureShortcutModifier = settings.captureShortcutModifier;
    final captureShortcutKey = settings.captureShortcutKey;
    final sourceLanguage = settings.sourceLanguage;
    final targetLanguage = settings.targetLanguage;
    final styleRegister = settings.styleRegister;
    final styleComplexity = settings.styleComplexity;
    final spellingMode = settings.spellingMode;

    return _SettingsDialogSnapshot._((target) {
      target.openAIApiKey = openAIApiKey;
      target.anthropicApiKey = anthropicApiKey;
      target.localApiKey = localApiKey;
      target.openAIBaseUrl = openAIBaseUrl;
      target.openAIModelId = openAIModelId;
      target.openAIAuthMode = openAIAuthMode;
      target.openAIRequestTimeoutSeconds = openAIRequestTimeoutSeconds;
      target.anthropicBaseUrl = anthropicBaseUrl;
      target.anthropicModelId = anthropicModelId;
      target.anthropicAuthMode = anthropicAuthMode;
      target.anthropicRequestTimeoutSeconds = anthropicRequestTimeoutSeconds;
      target.anthropicVersion = anthropicVersion;
      target.localBaseUrl = localBaseUrl;
      target.localModel = localModel;
      target.localAuthMode = localAuthMode;
      target.localRequestTimeoutSeconds = localRequestTimeoutSeconds;
      target.selectedProvider = selectedProvider;
      target.themeMode = themeMode;
      target.llmProfiles = llmProfiles;
      target.selectedLLMProfileID = selectedLLMProfileID;
      target.llmReasoningSettings = llmReasoningSettings;
      target.autoTranslateEnabled = autoTranslateEnabled;
      target.reasoningOnValue = reasoningOnValue;
      target.reasoningOffValue = reasoningOffValue;
      target.reasoningEnabled = reasoningEnabled;
      target.alternativeSuggestionCount = alternativeSuggestionCount;
      target.correctionAlternativeCount = correctionAlternativeCount;
      target.editorFontSize = editorFontSize;
      target.captureShortcutModifier = captureShortcutModifier;
      target.captureShortcutKey = captureShortcutKey;
      target.sourceLanguage = sourceLanguage;
      target.targetLanguage = targetLanguage;
      target.styleRegister = styleRegister;
      target.styleComplexity = styleComplexity;
      target.spellingMode = spellingMode;
    });
  }

  final void Function(AppSettingsStore settings) _restore;

  void restore(AppSettingsStore settings) => _restore(settings);
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.apiClient,
    required this.onSaved,
    this.updateService,
  });

  final AppSettingsStore settings;
  final AbyssLApiClient apiClient;
  final Future<void> Function() onSaved;
  final AppUpdateService? updateService;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final AppUpdateService _updateService;
  late final Map<TranslationProvider, TextEditingController> _baseUrls;
  late final Map<TranslationProvider, TextEditingController> _modelIds;
  late final Map<TranslationProvider, TextEditingController> _apiKeys;
  late final Map<TranslationProvider, TextEditingController> _timeouts;
  late final TextEditingController _anthropicVersion;
  late final TextEditingController _reasoningOn;
  late final TextEditingController _reasoningOff;
  late final TextEditingController _captureKey;
  late _SettingsDialogSnapshot _settingsBaseline;
  var _settingsBaselineRestored = false;
  var _localModels = <LocalLLMModel>[];
  final _providerModels = <TranslationProvider, List<LocalLLMModel>>{};
  var _reasoningOptions = <String>[
    'none',
    'off',
    'on',
    'low',
    'medium',
    'high',
  ];
  var _message = '';
  var _testing = false;
  var _settingsSection = 0;
  late TranslationProvider _providerTab;
  AppBuildInfo? _appBuildInfo;
  UpdateCheckResult? _updateCheckResult;
  var _aboutStatus =
      'Check GitHub to see whether a newer release is available.';
  var _loadingAppInfo = false;
  var _checkingForUpdates = false;
  var _startingUpdate = false;

  @override
  void initState() {
    super.initState();
    _updateService = widget.updateService ?? GitHubAppUpdateService();
    final settings = widget.settings;
    _settingsBaseline = _SettingsDialogSnapshot.capture(settings);
    _providerTab = settings.selectedProvider;
    _baseUrls = {
      for (final provider in TranslationProvider.values)
        provider: TextEditingController(text: settings.baseUrlFor(provider)),
    };
    _modelIds = {
      for (final provider in TranslationProvider.values)
        provider: TextEditingController(text: settings.modelIdFor(provider)),
    };
    _apiKeys = {
      for (final provider in TranslationProvider.values)
        provider: TextEditingController(text: settings.apiKeyFor(provider)),
    };
    _timeouts = {
      for (final provider in TranslationProvider.values)
        provider: TextEditingController(
          text: '${settings.timeoutSecondsFor(provider)}',
        ),
    };
    _anthropicVersion = TextEditingController(text: settings.anthropicVersion);
    _reasoningOn = TextEditingController(text: settings.reasoningOnValue);
    _reasoningOff = TextEditingController(text: settings.reasoningOffValue);
    _captureKey = TextEditingController(text: settings.captureShortcutKey);
    final storedReasoningOptions = settings.reasoningOptionsForModel(
      settings.localModel,
    );
    if (storedReasoningOptions.isNotEmpty) {
      _reasoningOptions = storedReasoningOptions;
    }
  }

  @override
  void dispose() {
    if (!_settingsBaselineRestored) {
      _settingsBaselineRestored = true;
      final settings = widget.settings;
      final baseline = _settingsBaseline;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        settings.update(baseline.restore);
      });
    }
    for (final controller in _baseUrls.values) {
      controller.dispose();
    }
    for (final controller in _modelIds.values) {
      controller.dispose();
    }
    for (final controller in _apiKeys.values) {
      controller.dispose();
    }
    for (final controller in _timeouts.values) {
      controller.dispose();
    }
    _anthropicVersion.dispose();
    _reasoningOn.dispose();
    _reasoningOff.dispose();
    _captureKey.dispose();
    super.dispose();
  }

  void _cancel() {
    if (!_settingsBaselineRestored) {
      _settingsBaselineRestored = true;
      widget.settings.update(_settingsBaseline.restore);
    }
    Navigator.of(context).pop();
  }

  TextEditingController _baseUrlController(TranslationProvider provider) =>
      _baseUrls[provider]!;

  TextEditingController _modelController(TranslationProvider provider) =>
      _modelIds[provider]!;

  TextEditingController _apiKeyController(TranslationProvider provider) =>
      _apiKeys[provider]!;

  TextEditingController _timeoutController(TranslationProvider provider) =>
      _timeouts[provider]!;

  TextEditingController get _localModel =>
      _modelController(TranslationProvider.localOpenAICompatible);

  TextEditingController get _localApiKey =>
      _apiKeyController(TranslationProvider.localOpenAICompatible);

  Future<void> _save() async {
    final settings = widget.settings;
    await _saveDraftOnly();
    settings.update((value) {
      value.reasoningOnValue = _reasoningOn.text;
      value.reasoningOffValue = _reasoningOff.text;
      value.rememberReasoningSettingsForModel(
        _modelController(TranslationProvider.localOpenAICompatible).text,
        allowedOptions: _reasoningOptions,
        reasoningOnValue: _reasoningOn.text,
        reasoningOffValue: _reasoningOff.text,
        reasoningEnabled: value.reasoningEnabled,
      );
      value.captureShortcutKey = TranslationCaptureShortcut.normalizeKey(
        _captureKey.text,
      );
    });
    try {
      await settings.save();
      _settingsBaseline = _SettingsDialogSnapshot.capture(settings);
      await widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  Future<void> _testConnection(TranslationProvider provider) async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      await _saveDraftOnly();
      if (!mounted) return;
      await widget.apiClient.testConnection(
        provider: provider,
        baseUri: widget.settings.baseUriFor(provider),
        apiKey: _apiKeyController(provider).text,
        authMode: widget.settings.authModeFor(provider),
        modelId: _modelController(provider).text,
        anthropicVersion: widget.settings.anthropicVersion,
        timeout: widget.settings.timeoutFor(provider),
      );
      if (mounted) {
        setState(() => _message = '${provider.label} connection OK.');
      }
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _detectLocalModelAndReasoning() async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      await _saveDraftOnly();
      if (!mounted) return;
      final settings = widget.settings;
      final timeout = settings.localRequestTimeoutSeconds > 0
          ? Duration(seconds: settings.localRequestTimeoutSeconds)
          : null;
      final catalog = await widget.apiClient.fetchLocalModelCatalog(
        baseUri: settings.baseUriFor(TranslationProvider.localOpenAICompatible),
        apiKey: _localApiKey.text,
        authMode: settings.authModeFor(
          TranslationProvider.localOpenAICompatible,
        ),
        timeout: timeout,
      );
      if (!mounted) return;

      final autoModel = _singleAutoLocalModel(catalog);
      if (autoModel != null) {
        _localModel.text = autoModel.requestName;
        await _saveDraftOnly();
        if (!mounted) return;
      }

      LocalReasoningOptions? reasoningOptions;
      Object? reasoningError;
      final modelForReasoning = _localModel.text.trim();
      if (modelForReasoning.isNotEmpty || autoModel != null) {
        try {
          reasoningOptions = await widget.apiClient.fetchLocalReasoningOptions(
            baseUri: settings.baseUriFor(
              TranslationProvider.localOpenAICompatible,
            ),
            apiKey: _localApiKey.text,
            authMode: settings.authModeFor(
              TranslationProvider.localOpenAICompatible,
            ),
            model: _localModel.text,
            timeout: timeout,
          );
          if (!mounted) return;
          _applyReasoningOptions(reasoningOptions);
          if (reasoningOptions.resolvedModelName case final resolved?) {
            _localModel.text = resolved;
            await _saveDraftOnly();
            if (!mounted) return;
          }
        } catch (error) {
          if (!mounted) return;
          reasoningError = error;
        }
      }

      setState(() {
        _localModels = catalog;
        _message = _localDetectionMessage(
          catalog: catalog,
          autoModel: autoModel,
          reasoningOptions: reasoningOptions,
          reasoningError: reasoningError,
        );
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _refreshReasoningOptions() async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      await _saveDraftOnly();
      if (!mounted) return;
      final settings = widget.settings;
      final timeout = settings.localRequestTimeoutSeconds > 0
          ? Duration(seconds: settings.localRequestTimeoutSeconds)
          : null;
      final fetched = await widget.apiClient.fetchLocalReasoningOptions(
        baseUri: settings.baseUriFor(TranslationProvider.localOpenAICompatible),
        apiKey: _localApiKey.text,
        authMode: settings.authModeFor(
          TranslationProvider.localOpenAICompatible,
        ),
        model: _localModel.text,
        timeout: timeout,
      );
      if (!mounted) return;
      _applyReasoningOptions(fetched);
      if (fetched.resolvedModelName case final resolved?) {
        _localModel.text = resolved;
        await _saveDraftOnly();
        if (!mounted) return;
      }
      setState(() {
        _message = 'Reasoning options: ${fetched.allowedOptions.join(', ')}.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  LocalLLMModel? _singleAutoLocalModel(List<LocalLLMModel> catalog) {
    final loaded = catalog.where((model) => model.isLoaded).toList();
    if (loaded.length == 1) return loaded.single;
    if (loaded.isEmpty && catalog.length == 1) return catalog.single;
    return null;
  }

  void _applyReasoningOptions(LocalReasoningOptions options) {
    final modelName = (options.resolvedModelName ?? _localModel.text).trim();
    final allowed =
        options.allowedOptions
            .map((option) => option.trim())
            .where((option) => option.isNotEmpty)
            .toSet()
            .toList()
          ..sort(LocalReasoningOptions.compareOptions);
    if (allowed.isEmpty) return;
    final stored = widget.settings.reasoningSettingsForModel(modelName);
    final storedOn = stored?.reasoningOnValue.trim();
    final storedOff = stored?.reasoningOffValue.trim();
    final nextOn = storedOn != null && allowed.contains(storedOn)
        ? storedOn
        : _preferredReasoningOnValue(allowed, options.defaultOption);
    final nextOff = storedOff != null && allowed.contains(storedOff)
        ? storedOff
        : _preferredReasoningOffValue(allowed, options.defaultOption);
    _reasoningOn.text = nextOn;
    _reasoningOff.text = nextOff;
    widget.settings.update((settings) {
      if (modelName.isNotEmpty) {
        settings.localModel = modelName;
      }
      settings.reasoningOnValue = nextOn;
      settings.reasoningOffValue = nextOff;
      settings.reasoningEnabled =
          stored?.reasoningEnabled ?? settings.reasoningEnabled;
      settings.rememberReasoningSettingsForModel(
        modelName,
        allowedOptions: allowed,
        reasoningOnValue: nextOn,
        reasoningOffValue: nextOff,
        reasoningEnabled: settings.reasoningEnabled,
      );
    });
    setState(() => _reasoningOptions = allowed);
  }

  String _preferredReasoningOnValue(
    List<String> allowed,
    String? defaultOption,
  ) {
    if (defaultOption != null && allowed.contains(defaultOption)) {
      return defaultOption;
    }
    return [
      'on',
      'low',
      'medium',
      'high',
      'off',
      'none',
    ].firstWhere(allowed.contains, orElse: () => allowed.first);
  }

  String _preferredReasoningOffValue(
    List<String> allowed,
    String? defaultOption,
  ) {
    if (allowed.contains('off')) return 'off';
    if (allowed.contains('none')) return 'none';
    if (defaultOption != null && allowed.contains(defaultOption)) {
      return defaultOption;
    }
    return allowed.first;
  }

  String _localDetectionMessage({
    required List<LocalLLMModel> catalog,
    required LocalLLMModel? autoModel,
    required LocalReasoningOptions? reasoningOptions,
    required Object? reasoningError,
  }) {
    final modelMessage = autoModel != null
        ? 'Detected local model: ${autoModel.requestName}.'
        : catalog.isEmpty
        ? 'No local models were returned by /api/v1/models or /v1/models.'
        : 'Found ${catalog.length} local models. Select one or enter the model name manually.';
    if (reasoningOptions != null) {
      return '$modelMessage Reasoning options: ${reasoningOptions.allowedOptions.join(', ')}.';
    }
    if (reasoningError != null) {
      return '$modelMessage Reasoning metadata unavailable: $reasoningError';
    }
    return modelMessage;
  }

  Future<void> _saveDraftOnly() async {
    widget.settings.update((value) {
      value.openAIBaseUrl = _baseUrlController(
        TranslationProvider.openAICompatible,
      ).text;
      value.openAIModelId = _modelController(
        TranslationProvider.openAICompatible,
      ).text;
      value.openAIApiKey = _apiKeyController(
        TranslationProvider.openAICompatible,
      ).text;
      value.openAIRequestTimeoutSeconds =
          int.tryParse(
            _timeoutController(TranslationProvider.openAICompatible).text,
          ) ??
          value.openAIRequestTimeoutSeconds;
      value.anthropicBaseUrl = _baseUrlController(
        TranslationProvider.anthropicCompatible,
      ).text;
      value.anthropicModelId = _modelController(
        TranslationProvider.anthropicCompatible,
      ).text;
      value.anthropicApiKey = _apiKeyController(
        TranslationProvider.anthropicCompatible,
      ).text;
      value.anthropicRequestTimeoutSeconds =
          int.tryParse(
            _timeoutController(TranslationProvider.anthropicCompatible).text,
          ) ??
          value.anthropicRequestTimeoutSeconds;
      value.anthropicVersion = _anthropicVersion.text;
      value.localBaseUrl = _baseUrlController(
        TranslationProvider.localOpenAICompatible,
      ).text;
      value.localApiKey = _apiKeyController(
        TranslationProvider.localOpenAICompatible,
      ).text;
      value.localModel = _modelController(
        TranslationProvider.localOpenAICompatible,
      ).text;
      value.localRequestTimeoutSeconds =
          int.tryParse(
            _timeoutController(TranslationProvider.localOpenAICompatible).text,
          ) ??
          value.localRequestTimeoutSeconds;
      value.reasoningOnValue = _reasoningOn.text;
      value.reasoningOffValue = _reasoningOff.text;
      value.rememberReasoningSettingsForModel(
        _localModel.text,
        allowedOptions: _reasoningOptions,
        reasoningOnValue: _reasoningOn.text,
        reasoningOffValue: _reasoningOff.text,
        reasoningEnabled: value.reasoningEnabled,
      );
    });
  }

  void _selectSettingsSection(int index) {
    setState(() => _settingsSection = index);
    if (index == 2) {
      unawaited(_loadAppBuildInfo());
    }
  }

  Future<AppBuildInfo?> _loadAppBuildInfo() async {
    if (_appBuildInfo != null) return _appBuildInfo;
    if (_loadingAppInfo) return null;
    setState(() => _loadingAppInfo = true);
    try {
      final buildInfo = await _updateService.loadInstalledBuild();
      if (!mounted) return buildInfo;
      setState(() {
        _appBuildInfo = buildInfo;
        _aboutStatus =
            'Installed version ${buildInfo.displayVersion}. Check GitHub for updates.';
      });
      return buildInfo;
    } catch (error) {
      if (mounted) {
        setState(() {
          _aboutStatus = 'Could not read the installed app version: $error';
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _loadingAppInfo = false);
    }
  }

  Future<void> _checkForUpdates() async {
    if (_checkingForUpdates || _startingUpdate) return;
    var buildInfo = _appBuildInfo;
    buildInfo ??= await _loadAppBuildInfo();
    if (buildInfo == null || !mounted) return;
    setState(() {
      _checkingForUpdates = true;
      _updateCheckResult = null;
      _aboutStatus = 'Checking the latest published GitHub release…';
    });
    try {
      final result = await _updateService.checkForUpdates(buildInfo);
      if (!mounted) return;
      setState(() {
        _updateCheckResult = result;
        _aboutStatus = switch (result.kind) {
          UpdateCheckKind.noPublishedRelease =>
            'No AbyssL release has been published on GitHub yet.',
          UpdateCheckKind.upToDate =>
            'AbyssL ${buildInfo!.version} is the newest published version.',
          UpdateCheckKind.updateAvailable =>
            'AbyssL ${result.release!.version} is available. The signed update can be downloaded and installed automatically.',
          UpdateCheckKind.releaseNotReady =>
            'AbyssL ${result.release!.version} is published, but its signed macOS update files are not available yet.',
        };
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _aboutStatus = '$error';
        });
      }
    } finally {
      if (mounted) setState(() => _checkingForUpdates = false);
    }
  }

  Future<void> _startAutomaticUpdate() async {
    if (_startingUpdate || _checkingForUpdates) return;
    setState(() {
      _startingUpdate = true;
      _aboutStatus =
          'Opening the secure macOS updater. It will verify, install, and relaunch AbyssL.';
    });
    try {
      await _updateService.startAutomaticInstall();
    } catch (error) {
      if (mounted) setState(() => _aboutStatus = '$error');
    } finally {
      if (mounted) setState(() => _startingUpdate = false);
    }
  }

  Future<void> _openWebsite() async {
    try {
      await _updateService.openWebsite();
    } catch (error) {
      if (mounted) setState(() => _aboutStatus = '$error');
    }
  }

  Future<void> _openLatestRelease() async {
    final release = _updateCheckResult?.release;
    if (release == null) return;
    try {
      await _updateService.openRelease(release);
    } catch (error) {
      if (mounted) setState(() => _aboutStatus = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final mediaSize = MediaQuery.sizeOf(context);
    final compact = mediaSize.width < 900 || mediaSize.height < 650;
    final horizontalInset = compact ? 12.0 : 28.0;
    final verticalInset = compact ? 12.0 : 24.0;
    final dialogWidth = (mediaSize.width - horizontalInset * 2)
        .clamp(560.0, 980.0)
        .toDouble();
    final dialogHeight = (mediaSize.height - verticalInset * 2)
        .clamp(420.0, 760.0)
        .toDouble();

    return Dialog(
      key: const ValueKey('settings-dialog'),
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Container(
              height: compact ? 62 : 72,
              padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 20),
              color: AbyssLPalette.ink,
              child: Row(
                children: [
                  const Icon(
                    Icons.settings_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (_testing) ...[
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  TextButton(
                    onPressed: _cancel,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFDCE2EC),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const ValueKey('save-settings'),
                    onPressed: _testing ? null : _save,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Save'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: compact
                  ? Column(
                      children: [
                        _settingsNavigation(compact: true),
                        Divider(
                          height: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(14),
                            child: _settingsContent(settings),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _settingsNavigation(compact: false),
                        VerticalDivider(
                          width: 1,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(22),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 760,
                                ),
                                child: _settingsContent(settings),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (settings.secureStorageWarning != null || _message.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: Text(
                  settings.secureStorageWarning ?? _message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: settings.secureStorageWarning != null
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settingsNavigation({required bool compact}) {
    const sections = [
      (Icons.tune_outlined, 'General'),
      (Icons.hub_outlined, 'AI Providers'),
      (Icons.info_outline_rounded, 'About'),
    ];
    if (compact) {
      return SizedBox(
        height: 52,
        child: Row(
          children: [
            for (var index = 0; index < sections.length; index++)
              Expanded(
                child: _settingsNavButton(
                  index: index,
                  icon: sections[index].$1,
                  label: sections[index].$2,
                  compact: true,
                ),
              ),
          ],
        ),
      );
    }
    return Container(
      width: 210,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'CONFIGURATION',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < sections.length; index++) ...[
            _settingsNavButton(
              index: index,
              icon: sections[index].$1,
              label: sections[index].$2,
              compact: false,
            ),
            const SizedBox(height: 6),
          ],
          const Spacer(),
          Text(
            'Changes are stored locally.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsNavButton({
    required int index,
    required IconData icon,
    required String label,
    required bool compact,
  }) {
    final selected = _settingsSection == index;
    return Material(
      color: selected ? AbyssLPalette.blueSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: ValueKey('settings-section-$index'),
        onTap: () => _selectSettingsSection(index),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: compact ? 10 : 12,
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected
                    ? AbyssLPalette.blue
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? AbyssLPalette.blue
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _settingsContent(AppSettingsStore settings) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      child: KeyedSubtree(
        key: ValueKey(_settingsSection),
        child: switch (_settingsSection) {
          0 => _generalSettings(settings),
          1 => _aiProviderSettings(settings),
          _ => _aboutSettings(),
        },
      ),
    );
  }

  Widget _generalSettings(AppSettingsStore settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _settingsSectionCard(
          icon: Icons.palette_outlined,
          title: 'Appearance',
          subtitle: 'Choose how AbyssL looks on this device.',
          child: _themeModePicker(settings),
        ),
        const SizedBox(height: 16),
        _settingsSectionCard(
          icon: Icons.route_outlined,
          title: 'Default provider',
          subtitle: 'Select the service used for new requests.',
          child: _settingsRow([
            DropdownButtonFormField<TranslationProvider>(
              key: ValueKey(settings.selectedProvider),
              initialValue: settings.selectedProvider,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: TranslationProvider.values
                  .map(
                    (provider) => DropdownMenuItem(
                      value: provider,
                      child: Text(provider.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  settings.update(
                    (settings) => settings.selectedProvider = value,
                  );
                }
              },
            ),
            const InputDecorator(
              decoration: InputDecoration(labelText: 'Configuration'),
              child: Text('Edit endpoints and models under AI Providers'),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        _settingsSectionCard(
          icon: Icons.text_fields_outlined,
          title: 'Editor and capture',
          subtitle: 'Tune text size and the global capture shortcut.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Editor font size',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  Text(
                    settings.editorFontSize.toStringAsFixed(0),
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: AbyssLPalette.blue),
                  ),
                ],
              ),
              Slider(
                value: settings.editorFontSize,
                min: AppSettingsStore.minimumEditorFontSize,
                max: AppSettingsStore.maximumEditorFontSize,
                divisions: 18,
                label: 'Font ${settings.editorFontSize.toStringAsFixed(0)}',
                onChanged: (value) => settings.update(
                  (settings) => settings.editorFontSize = value,
                ),
              ),
              const SizedBox(height: 8),
              _settingsRow([
                DropdownButtonFormField<TranslationCaptureModifier>(
                  key: ValueKey(settings.captureShortcutModifier),
                  initialValue: settings.captureShortcutModifier,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Capture modifier',
                  ),
                  items: TranslationCaptureModifier.values
                      .map(
                        (modifier) => DropdownMenuItem(
                          value: modifier,
                          child: Text(modifier.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      settings.update(
                        (settings) => settings.captureShortcutModifier = value,
                      );
                    }
                  },
                ),
                TextField(
                  controller: _captureKey,
                  decoration: const InputDecoration(labelText: 'Capture key'),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiProviderSettings(AppSettingsStore settings) {
    final provider = _providerTab;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          key: const ValueKey('provider-tabs'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in TranslationProvider.values)
              ChoiceChip(
                key: ValueKey(switch (option) {
                  TranslationProvider.openAICompatible => 'provider-tab-openai',
                  TranslationProvider.anthropicCompatible =>
                    'provider-tab-anthropic',
                  TranslationProvider.localOpenAICompatible =>
                    'provider-tab-local',
                }),
                selected: provider == option,
                showCheckmark: false,
                label: Text(option.label),
                onSelected: (_) => setState(() => _providerTab = option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: KeyedSubtree(
            key: ValueKey('provider-content-${provider.name}'),
            child: _providerConnectionCard(settings, provider),
          ),
        ),
        if (provider == TranslationProvider.localOpenAICompatible) ...[
          const SizedBox(height: 16),
          _localReasoningSettings(settings),
        ],
      ],
    );
  }

  Widget _providerConnectionCard(
    AppSettingsStore settings,
    TranslationProvider provider,
  ) {
    final isLocal = provider == TranslationProvider.localOpenAICompatible;
    final isAnthropic = provider == TranslationProvider.anthropicCompatible;
    final catalog = isLocal
        ? _localModels
        : (_providerModels[provider] ?? const <LocalLLMModel>[]);
    return _settingsSectionCard(
      icon: isLocal
          ? Icons.dns_outlined
          : isAnthropic
          ? Icons.auto_awesome_outlined
          : Icons.cloud_outlined,
      title: '${provider.label} connection',
      subtitle: isLocal
          ? 'Connect to an OpenAI-compatible model server on your network.'
          : 'Configure any service that implements this compatible API format.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: ValueKey('provider-base-url-${provider.name}'),
            controller: _baseUrlController(provider),
            decoration: const InputDecoration(
              labelText: 'Base URL',
              helperText: 'Include the API path, for example /v1.',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          _settingsRow([
            TextField(
              key: ValueKey('provider-model-${provider.name}'),
              controller: _modelController(provider),
              decoration: const InputDecoration(labelText: 'Model ID'),
              autocorrect: false,
            ),
            TextField(
              key: ValueKey('provider-timeout-${provider.name}'),
              controller: _timeoutController(provider),
              decoration: const InputDecoration(
                labelText: 'Timeout seconds',
                helperText: '0 uses the client default.',
              ),
              keyboardType: TextInputType.number,
            ),
          ]),
          if (catalog.isNotEmpty) ...[
            const SizedBox(height: 12),
            _providerModelDropdown(provider, catalog),
          ],
          const SizedBox(height: 12),
          _settingsRow([
            DropdownButtonFormField<ApiAuthMode>(
              key: ValueKey(
                'provider-auth-${provider.name}-${settings.authModeFor(provider).name}',
              ),
              initialValue: settings.authModeFor(provider),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Authentication'),
              items: ApiAuthMode.values
                  .map(
                    (mode) =>
                        DropdownMenuItem(value: mode, child: Text(mode.label)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) _setProviderAuthMode(provider, value);
              },
            ),
            TextField(
              key: ValueKey('provider-api-key-${provider.name}'),
              controller: _apiKeyController(provider),
              enabled: settings.authModeFor(provider) != ApiAuthMode.none,
              decoration: const InputDecoration(
                labelText: 'API key',
                helperText: 'Stored in the operating system keychain.',
              ),
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ]),
          if (isAnthropic) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('anthropic-version'),
              controller: _anthropicVersion,
              decoration: const InputDecoration(
                labelText: 'Anthropic version header',
                helperText: 'Default: 2023-06-01',
              ),
              autocorrect: false,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: ValueKey('provider-model-catalog-${provider.name}'),
                onPressed: _testing
                    ? null
                    : isLocal
                    ? _detectLocalModelAndReasoning
                    : () => _loadProviderModels(provider),
                icon: Icon(isLocal ? Icons.radar : Icons.list_alt_outlined),
                label: Text(isLocal ? 'Detect Local' : 'Load models'),
              ),
              OutlinedButton.icon(
                key: ValueKey('provider-test-${provider.name}'),
                onPressed: _testing ? null : () => _testConnection(provider),
                icon: const Icon(Icons.wifi_tethering, size: 18),
                label: const Text('Test connection'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _localReasoningSettings(AppSettingsStore settings) {
    return _settingsSectionCard(
      icon: Icons.psychology_outlined,
      title: 'Reasoning',
      subtitle: 'Map model-specific reasoning values.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _settingsRow([
            _reasoningDropdown(
              label: 'Reasoning value ON',
              controller: _reasoningOn,
            ),
            _reasoningDropdown(
              label: 'Reasoning value OFF',
              controller: _reasoningOff,
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: _testing ? null : _refreshReasoningOptions,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Refresh'),
              ),
              FilterChip(
                selected: settings.reasoningEnabled,
                label: const Text('Reasoning enabled'),
                onSelected: (value) => settings.update((settings) {
                  settings.reasoningEnabled = value;
                  settings.rememberReasoningSettingsForModel(
                    _localModel.text,
                    allowedOptions: _reasoningOptions,
                    reasoningOnValue: _reasoningOn.text,
                    reasoningOffValue: _reasoningOff.text,
                    reasoningEnabled: value,
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _setProviderAuthMode(TranslationProvider provider, ApiAuthMode mode) {
    setState(() {
      widget.settings.update((settings) {
        switch (provider) {
          case TranslationProvider.openAICompatible:
            settings.openAIAuthMode = mode;
          case TranslationProvider.anthropicCompatible:
            settings.anthropicAuthMode = mode;
          case TranslationProvider.localOpenAICompatible:
            settings.localAuthMode = mode;
        }
      });
    });
  }

  Widget _providerModelDropdown(
    TranslationProvider provider,
    List<LocalLLMModel> models,
  ) {
    final current = _modelController(provider).text.trim();
    final names = models.map((model) => model.requestName).toList();
    return DropdownButtonFormField<String>(
      key: ValueKey(
        'provider-model-options-${provider.name}-${names.join('|')}',
      ),
      initialValue: names.contains(current) ? current : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Available models'),
      items: models
          .map(
            (model) => DropdownMenuItem(
              value: model.requestName,
              child: Text(model.name, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _modelController(provider).text = value);
        }
      },
    );
  }

  Future<void> _loadProviderModels(TranslationProvider provider) async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      await _saveDraftOnly();
      if (!mounted) return;
      final models = await widget.apiClient.fetchModelCatalog(
        provider: provider,
        baseUri: widget.settings.baseUriFor(provider),
        apiKey: widget.settings.apiKeyFor(provider),
        authMode: widget.settings.authModeFor(provider),
        anthropicVersion: widget.settings.anthropicVersion,
        timeout: widget.settings.timeoutFor(provider),
      );
      if (!mounted) return;
      setState(() {
        _providerModels[provider] = models;
        _message = models.isEmpty
            ? 'No models were returned. Enter a model ID manually.'
            : 'Found ${models.length} models.';
      });
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Widget _aboutSettings() {
    final buildInfo = _appBuildInfo;
    final updateResult = _updateCheckResult;
    final release = updateResult?.release;
    final updateAvailable =
        updateResult?.kind == UpdateCheckKind.updateAvailable;
    final showReleaseButton =
        release != null &&
        updateResult?.kind == UpdateCheckKind.releaseNotReady;

    return Column(
      key: const ValueKey('settings-about-content'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _settingsSectionCard(
          icon: Icons.info_outline_rounded,
          title: 'About AbyssL',
          subtitle: 'Application details, project website, and updates.',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final logo = Container(
                width: 104,
                height: 104,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AbyssLPalette.blueSoft,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Image.asset(
                  'assets/branding/abyssl_mark.png',
                  key: const ValueKey('about-logo'),
                  semanticLabel: 'AbyssL logo',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              );
              final details = Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    'AbyssL',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Developed by Daniel Mengel',
                    key: const ValueKey('about-developer'),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _loadingAppInfo
                        ? 'Version loading…'
                        : 'Version ${buildInfo?.displayVersion ?? 'unavailable'}',
                    key: const ValueKey('about-version'),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    key: const ValueKey('about-website-link'),
                    onPressed: _openWebsite,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text(abyssLWebsiteUri),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  children: [logo, const SizedBox(height: 16), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  logo,
                  const SizedBox(width: 22),
                  Expanded(child: details),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _settingsSectionCard(
          icon: Icons.system_update_alt_rounded,
          title: 'Software updates',
          subtitle:
              'Check the latest published GitHub release and install signed macOS updates securely.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Container(
                  key: const ValueKey('update-status'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_checkingForUpdates || _startingUpdate)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          updateAvailable
                              ? Icons.new_releases_outlined
                              : Icons.info_outline,
                          size: 19,
                          color: updateAvailable
                              ? AbyssLPalette.blue
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_aboutStatus)),
                    ],
                  ),
                ),
              ),
              if (release != null &&
                  updateAvailable &&
                  release.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  release.notes,
                  key: const ValueKey('about-release-notes'),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('check-for-updates'),
                    onPressed:
                        _checkingForUpdates ||
                            _startingUpdate ||
                            _loadingAppInfo
                        ? null
                        : _checkForUpdates,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Check for updates'),
                  ),
                  if (updateAvailable &&
                      _updateService.supportsAutomaticInstall)
                    FilledButton.icon(
                      key: const ValueKey('install-update'),
                      onPressed: _startingUpdate || _checkingForUpdates
                          ? null
                          : _startAutomaticUpdate,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download and install…'),
                    ),
                  if (showReleaseButton ||
                      (updateAvailable &&
                          !_updateService.supportsAutomaticInstall))
                    TextButton.icon(
                      key: const ValueKey('open-latest-release'),
                      onPressed: _openLatestRelease,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Open GitHub release'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _settingsSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AbyssLPalette.blueSoft,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AbyssLPalette.blue, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _settingsRow(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < children.length; index++) ...[
                children[index],
                if (index != children.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < children.length; index++) ...[
              Expanded(child: children[index]),
              if (index != children.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _themeModePicker(AppSettingsStore settings) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<AppThemeMode>(
            selected: {settings.themeMode},
            segments: const [
              ButtonSegment(
                value: AppThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: AppThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: AppThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            onSelectionChanged: (selection) {
              final mode = selection.single;
              setState(() {
                settings.update((settings) => settings.themeMode = mode);
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _reasoningDropdown({
    required String label,
    required TextEditingController controller,
  }) {
    final options = _reasoningPickerOptions();
    final current = controller.text.trim();
    return DropdownButtonFormField<String>(
      key: ValueKey('$label|${options.join('|')}|$current'),
      initialValue: options.contains(current) ? current : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: options
          .map(
            (option) => DropdownMenuItem(
              value: option,
              child: Text(_reasoningOptionLabel(option)),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        controller.text = value;
        widget.settings.update((settings) {
          if (controller == _reasoningOn) {
            settings.reasoningOnValue = value;
          } else {
            settings.reasoningOffValue = value;
          }
          settings.rememberReasoningSettingsForModel(
            _localModel.text,
            allowedOptions: _reasoningOptions,
            reasoningOnValue: _reasoningOn.text,
            reasoningOffValue: _reasoningOff.text,
            reasoningEnabled: settings.reasoningEnabled,
          );
        });
      },
    );
  }

  List<String> _reasoningPickerOptions() {
    final values = {
      ..._reasoningOptions.map((option) => option.trim()),
      _reasoningOn.text.trim(),
      _reasoningOff.text.trim(),
    }..removeWhere((option) => option.isEmpty);
    final options = values.toList()..sort(LocalReasoningOptions.compareOptions);
    return options.isEmpty ? const ['off'] : options;
  }

  String _reasoningOptionLabel(String option) => switch (option) {
    'none' => 'None',
    'off' => 'Off',
    'on' => 'On',
    'low' => 'Low',
    'medium' => 'Medium',
    'high' => 'High',
    _ => option,
  };
}
