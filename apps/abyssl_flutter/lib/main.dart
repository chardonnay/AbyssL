import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  const AbyssLApp({super.key, required this.settings, this.apiClient});

  final AppSettingsStore settings;
  final AbyssLApiClient? apiClient;

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
        home: MainShell(settings: settings, apiClient: apiClient),
      ),
    );
  }

  static ThemeData _themeData(Brightness brightness) {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff2f5f6f),
        brightness: brightness,
      ),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    );
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
  const MainShell({super.key, required this.settings, this.apiClient});

  final AppSettingsStore settings;
  final AbyssLApiClient? apiClient;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _documentService = const DocumentProcessingService();
  final _captureService = DesktopCaptureService();
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
    if (widget.settings.selectedProvider != TranslationProvider.localLLM) {
      return;
    }
    try {
      final settings = widget.settings;
      final timeout = settings.localRequestTimeoutSeconds > 0
          ? Duration(seconds: settings.localRequestTimeoutSeconds)
          : null;
      final catalog = await _apiClient.fetchLocalModelCatalog(
        baseUri: settings.baseUriFor(TranslationProvider.localLLM),
        apiKey: settings.localApiKey,
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
          baseUri: settings.baseUriFor(TranslationProvider.localLLM),
          apiKey: settings.localApiKey,
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
        onSaved: () async {
          await _configureCapture();
          setState(() {});
        },
      ),
    );
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
        return Scaffold(
          appBar: AppBar(
            title: const Text('AbyssL Translator'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: _selectedIndex,
                onDestinationSelected: (index) =>
                    setState(() => _selectedIndex = index),
                labelType: NavigationRailLabelType.all,
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.public),
                    label: Text('Translator'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.spellcheck),
                    label: Text('Correction'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.description_outlined),
                    label: Text('Documents'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: content),
            ],
          ),
          bottomNavigationBar: _statusBar(),
        );
      },
    );
  }

  Widget _statusBar() {
    final capture = _captureStatus;
    final message = _status.isNotEmpty
        ? _status
        : capture == null
        ? ''
        : 'Capture: ${capture.message}';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: SizedBox(
        height: 36,
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
          ],
        ),
      ),
    );
  }

  Widget _translatorView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _languageAndStyleRow(),
          const SizedBox(height: 12),
          TextField(
            controller: _instructionController,
            decoration: const InputDecoration(labelText: 'Direct instruction'),
            minLines: 1,
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _sourceController,
                    onChanged: _scheduleAutoTranslate,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    style: TextStyle(fontSize: widget.settings.editorFontSize),
                    decoration: InputDecoration(
                      labelText: 'Source',
                      suffixIcon: IconButton(
                        tooltip: 'Clear source and translation',
                        onPressed: _isBusy ? null : _clearTranslatorTexts,
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Center(
                  child: IconButton.outlined(
                    tooltip: _canSwapTranslatorLanguages
                        ? 'Swap source and target languages'
                        : 'Choose a fixed source language to swap languages',
                    onPressed: _isBusy || !_canSwapTranslatorLanguages
                        ? null
                        : _swapTranslatorLanguages,
                    icon: const Icon(Icons.swap_horiz),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _translationController,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    style: TextStyle(fontSize: widget.settings.editorFontSize),
                    decoration: const InputDecoration(labelText: 'Translation'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _isBusy ? null : _translateNow,
                icon: const Icon(Icons.translate),
                label: const Text('Translate'),
              ),
              if (_isBusy) _cancelRequestButton(),
              OutlinedButton.icon(
                onPressed: _translationController.text.trim().isEmpty || _isBusy
                    ? null
                    : _suggestAlternatives,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Alternatives'),
              ),
              IconButton.outlined(
                tooltip: 'Copy translation',
                onPressed: _translationController.text.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: _translationController.text),
                      ),
                icon: const Icon(Icons.copy),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(widget.settings.captureShortcut.displayName),
              ),
            ],
          ),
          if (_synonyms.isNotEmpty || _alternatives.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 128,
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
                        TextField(
                          controller: _alternativesInstructionController,
                          decoration: const InputDecoration(
                            labelText: 'Alternative instruction',
                          ),
                        ),
                        const SizedBox(height: 8),
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
          ],
        ],
      ),
    );
  }

  Widget _languageAndStyleRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final fieldWidth = availableWidth < 720
            ? ((availableWidth - 8) / 2).clamp(180.0, availableWidth)
            : ((availableWidth - 32) / 5).clamp(120.0, availableWidth);
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: fieldWidth,
              child: _enumDropdown(
                label: 'Source',
                value: widget.settings.sourceLanguage,
                values: TranslationLanguage.values,
                text: (value) => value.label,
                onChanged: (value) => widget.settings.update(
                  (settings) => settings.sourceLanguage = value,
                ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _enumDropdown(
                label: 'Target',
                value: widget.settings.targetLanguage,
                values: TranslationLanguage.values
                    .where(
                      (language) => language != TranslationLanguage.automatic,
                    )
                    .toList(),
                text: (value) => value.label,
                onChanged: (value) => widget.settings.update(
                  (settings) => settings.targetLanguage = value,
                ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _enumDropdown(
                label: 'Register',
                value: widget.settings.styleRegister,
                values: RegisterStyle.values,
                text: (value) => value.label,
                onChanged: (value) => widget.settings.update(
                  (settings) => settings.styleRegister = value,
                ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _enumDropdown(
                label: 'Complexity',
                value: widget.settings.styleComplexity,
                values: ComplexityStyle.values,
                text: (value) => value.label,
                onChanged: (value) => widget.settings.update(
                  (settings) => settings.styleComplexity = value,
                ),
              ),
            ),
            SizedBox(
              width: fieldWidth,
              child: _enumDropdown(
                label: 'Spelling',
                value: widget.settings.spellingMode,
                values: SpellingMode.values,
                text: (value) => value.label,
                onChanged: (value) => widget.settings.update(
                  (settings) => settings.spellingMode = value,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _correctionView() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _correctionInstructionController,
                  decoration: const InputDecoration(
                    labelText: 'Direct correction or rewrite instruction',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
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
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: TextField(
                    controller: _correctionInputController,
                    onChanged: (_) => _clearCorrectionMarks(),
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    style: TextStyle(fontSize: widget.settings.editorFontSize),
                    decoration: InputDecoration(
                      labelText: 'Input',
                      suffixIcon: IconButton(
                        tooltip: 'Clear input and correction',
                        onPressed: _isBusy ? null : _clearCorrectionTexts,
                        icon: const Icon(Icons.clear),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _correctionOutputController,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    style: TextStyle(fontSize: widget.settings.editorFontSize),
                    decoration: const InputDecoration(
                      labelText: 'Corrected / rewritten text',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isBusy ? null : _correctWriting,
                icon: const Icon(Icons.spellcheck),
                label: const Text('Correct'),
              ),
              if (_isBusy) ...[
                const SizedBox(width: 8),
                _cancelRequestButton(),
              ],
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _isBusy ? null : _rewriteWriting,
                icon: const Icon(Icons.edit_note),
                label: const Text('Rewrite'),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Copy result',
                onPressed: _correctionOutputController.text.isEmpty
                    ? null
                    : () => Clipboard.setData(
                        ClipboardData(text: _correctionOutputController.text),
                      ),
                icon: const Icon(Icons.copy),
              ),
              if (_correctionIssues.isNotEmpty) ...[
                const SizedBox(width: 12),
                Chip(
                  avatar: const Icon(Icons.error_outline, size: 18),
                  label: Text(_correctionIssueCountLabel()),
                ),
              ],
            ],
          ),
          if (_correctionIssues.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 130,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (context, index) {
                  final issue = _correctionIssues[index];
                  return SizedBox(
                    width: 320,
                    child: CorrectionIssueCard(issue: issue),
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemCount: _correctionIssues.length,
              ),
            ),
          ],
        ],
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _pickDocumentFiles,
                icon: const Icon(Icons.note_add_outlined),
                label: const Text('Add files'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickDocumentFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add folder'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _pickOutputFolder,
                icon: const Icon(Icons.folder_open),
                label: const Text('Output folder'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _documentOutputDirectory ?? 'No output folder selected',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilterChip(
                selected: _documentOptions.shouldCorrect,
                label: const Text('Correct'),
                onSelected: (value) => setState(
                  () => _documentOptions = _documentOptions.copyWith(
                    shouldCorrect: value,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilterChip(
                selected: _documentOptions.shouldTranslate,
                label: const Text('Translate'),
                onSelected: (value) => setState(
                  () => _documentOptions = _documentOptions.copyWith(
                    shouldTranslate: value,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 180,
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
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _documentInstructionController,
                  decoration: const InputDecoration(
                    labelText: 'Document instruction',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _isBusy ? null : _processDocuments,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Process'),
              ),
              if (_isBusy) ...[
                const SizedBox(width: 8),
                _cancelRequestButton(),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: DropTarget(
              onDragDone: (details) => _addDocumentPaths(
                details.files.map((file) => file.path).toList(),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(child: _documentJobList()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _documentResultList()),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _documentProgress.total == 0
                ? 0
                : _documentProgress.completed / _documentProgress.total,
          ),
        ],
      ),
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

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({
    super.key,
    required this.settings,
    required this.apiClient,
    required this.onSaved,
  });

  final AppSettingsStore settings;
  final AbyssLApiClient apiClient;
  final Future<void> Function() onSaved;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _apiKey;
  late final TextEditingController _serverHost;
  late final TextEditingController _serverPort;
  late final TextEditingController _localApiKey;
  late final TextEditingController _localHost;
  late final TextEditingController _localPort;
  late final TextEditingController _localModel;
  late final TextEditingController _timeout;
  late final TextEditingController _reasoningOn;
  late final TextEditingController _reasoningOff;
  late final TextEditingController _captureKey;
  var _localModels = <LocalLLMModel>[];
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

  @override
  void initState() {
    super.initState();
    final settings = widget.settings;
    _apiKey = TextEditingController(text: settings.apiKey);
    _serverHost = TextEditingController(text: settings.serverHost);
    _serverPort = TextEditingController(text: '${settings.serverPort}');
    _localApiKey = TextEditingController(text: settings.localApiKey);
    _localHost = TextEditingController(text: settings.localServerHost);
    _localPort = TextEditingController(text: '${settings.localServerPort}');
    _localModel = TextEditingController(text: settings.localModel);
    _timeout = TextEditingController(
      text: '${settings.localRequestTimeoutSeconds}',
    );
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
    _apiKey.dispose();
    _serverHost.dispose();
    _serverPort.dispose();
    _localApiKey.dispose();
    _localHost.dispose();
    _localPort.dispose();
    _localModel.dispose();
    _timeout.dispose();
    _reasoningOn.dispose();
    _reasoningOff.dispose();
    _captureKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = widget.settings;
    settings.update((value) {
      value.apiKey = _apiKey.text;
      value.serverHost = _serverHost.text;
      value.serverPort = int.tryParse(_serverPort.text) ?? value.serverPort;
      value.localApiKey = _localApiKey.text;
      value.localServerHost = _localHost.text;
      value.localServerPort =
          int.tryParse(_localPort.text) ?? value.localServerPort;
      value.localModel = _localModel.text;
      value.localRequestTimeoutSeconds =
          int.tryParse(_timeout.text) ?? value.localRequestTimeoutSeconds;
      value.reasoningOnValue = _reasoningOn.text;
      value.reasoningOffValue = _reasoningOff.text;
      value.rememberReasoningSettingsForModel(
        _localModel.text,
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
      await widget.onSaved();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _message = '$error');
    }
  }

  Future<void> _testConnection(TranslationProvider provider) async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      await _saveDraftOnly();
      await widget.apiClient.testConnection(
        provider: provider,
        baseUri: widget.settings.baseUriFor(provider),
        apiKey: provider == TranslationProvider.openAI
            ? _apiKey.text
            : _localApiKey.text,
        timeout:
            provider == TranslationProvider.localLLM &&
                widget.settings.localRequestTimeoutSeconds > 0
            ? Duration(seconds: widget.settings.localRequestTimeoutSeconds)
            : null,
      );
      setState(() => _message = '${provider.label} connection OK.');
    } catch (error) {
      setState(() => _message = '$error');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _detectLocalModelAndReasoning() async {
    setState(() {
      _testing = true;
      _message = '';
    });
    try {
      await _saveDraftOnly();
      final settings = widget.settings;
      final timeout = settings.localRequestTimeoutSeconds > 0
          ? Duration(seconds: settings.localRequestTimeoutSeconds)
          : null;
      final catalog = await widget.apiClient.fetchLocalModelCatalog(
        baseUri: settings.baseUriFor(TranslationProvider.localLLM),
        apiKey: _localApiKey.text,
        timeout: timeout,
      );

      final autoModel = _singleAutoLocalModel(catalog);
      if (autoModel != null) {
        _localModel.text = autoModel.requestName;
        await _saveDraftOnly();
      }

      LocalReasoningOptions? reasoningOptions;
      Object? reasoningError;
      final modelForReasoning = _localModel.text.trim();
      if (modelForReasoning.isNotEmpty || autoModel != null) {
        try {
          reasoningOptions = await widget.apiClient.fetchLocalReasoningOptions(
            baseUri: settings.baseUriFor(TranslationProvider.localLLM),
            apiKey: _localApiKey.text,
            model: _localModel.text,
            timeout: timeout,
          );
          _applyReasoningOptions(reasoningOptions);
          if (reasoningOptions.resolvedModelName case final resolved?) {
            _localModel.text = resolved;
            await _saveDraftOnly();
          }
        } catch (error) {
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
      setState(() => _message = '$error');
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
      final settings = widget.settings;
      final timeout = settings.localRequestTimeoutSeconds > 0
          ? Duration(seconds: settings.localRequestTimeoutSeconds)
          : null;
      final fetched = await widget.apiClient.fetchLocalReasoningOptions(
        baseUri: settings.baseUriFor(TranslationProvider.localLLM),
        apiKey: _localApiKey.text,
        model: _localModel.text,
        timeout: timeout,
      );
      _applyReasoningOptions(fetched);
      if (fetched.resolvedModelName case final resolved?) {
        _localModel.text = resolved;
        await _saveDraftOnly();
      }
      setState(() {
        _message = 'Reasoning options: ${fetched.allowedOptions.join(', ')}.';
      });
    } catch (error) {
      setState(() => _message = '$error');
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
      value.serverHost = _serverHost.text;
      value.serverPort = int.tryParse(_serverPort.text) ?? value.serverPort;
      value.localServerHost = _localHost.text;
      value.localServerPort =
          int.tryParse(_localPort.text) ?? value.localServerPort;
      value.localModel = _localModel.text;
      value.localRequestTimeoutSeconds =
          int.tryParse(_timeout.text) ?? value.localRequestTimeoutSeconds;
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

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return AlertDialog(
      title: const Text('Settings'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<TranslationProvider>(
                      key: ValueKey(settings.selectedProvider),
                      initialValue: settings.selectedProvider,
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
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<OpenAIModel>(
                      key: ValueKey(settings.selectedModel),
                      initialValue: settings.selectedModel,
                      decoration: const InputDecoration(
                        labelText: 'OpenAI model',
                      ),
                      items: OpenAIModel.values
                          .map(
                            (model) => DropdownMenuItem(
                              value: model,
                              child: Text(model.id),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          settings.update(
                            (settings) => settings.selectedModel = value,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _themeModePicker(settings),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _serverHost,
                      decoration: const InputDecoration(
                        labelText: 'OpenAI host',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _serverPort,
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: _protocolDropdown(
                      value: settings.useHTTPS,
                      onChanged: (value) => settings.update(
                        (settings) => settings.useHTTPS = value,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                decoration: const InputDecoration(labelText: 'OpenAI API key'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _localHost,
                      decoration: const InputDecoration(
                        labelText: 'Local host',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _localPort,
                      decoration: const InputDecoration(labelText: 'Port'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: _protocolDropdown(
                      value: settings.localUseHTTPS,
                      onChanged: (value) => settings.update(
                        (settings) => settings.localUseHTTPS = value,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _localModel,
                      decoration: const InputDecoration(
                        labelText: 'Local model',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 140,
                    child: OutlinedButton(
                      onPressed: _testing
                          ? null
                          : _detectLocalModelAndReasoning,
                      child: const Text('Detect Local'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _timeout,
                      decoration: const InputDecoration(
                        labelText: 'Timeout seconds',
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (_localModels.isNotEmpty) ...[
                const SizedBox(height: 12),
                _localModelDropdown(),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _localApiKey,
                decoration: const InputDecoration(labelText: 'Local API key'),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _reasoningDropdown(
                      label: 'Reasoning value ON',
                      controller: _reasoningOn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _reasoningDropdown(
                      label: 'Reasoning value OFF',
                      controller: _reasoningOff,
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _testing ? null : _refreshReasoningOptions,
                    child: const Text('Refresh'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: settings.reasoningEnabled,
                    label: const Text('Reasoning'),
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
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: settings.editorFontSize,
                      min: AppSettingsStore.minimumEditorFontSize,
                      max: AppSettingsStore.maximumEditorFontSize,
                      divisions: 18,
                      label:
                          'Font ${settings.editorFontSize.toStringAsFixed(0)}',
                      onChanged: (value) => settings.update(
                        (settings) => settings.editorFontSize = value,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<TranslationCaptureModifier>(
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
                              child: Text(
                                modifier.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          settings.update(
                            (settings) =>
                                settings.captureShortcutModifier = value,
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _captureKey,
                      decoration: const InputDecoration(labelText: 'Key'),
                    ),
                  ),
                ],
              ),
              if (settings.secureStorageWarning != null) ...[
                const SizedBox(height: 12),
                Text(
                  settings.secureStorageWarning!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (_message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: Text(_message)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _testing
              ? null
              : () => _testConnection(TranslationProvider.openAI),
          child: const Text('Test OpenAI'),
        ),
        TextButton(
          onPressed: _testing
              ? null
              : () => _testConnection(TranslationProvider.localLLM),
          child: const Text('Test Local'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  Widget _protocolDropdown({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return DropdownButtonFormField<bool>(
      key: ValueKey(value),
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Protocol'),
      items: const [
        DropdownMenuItem(value: false, child: Text('HTTP')),
        DropdownMenuItem(value: true, child: Text('HTTPS')),
      ],
      onChanged: (nextValue) {
        if (nextValue != null) onChanged(nextValue);
      },
    );
  }

  Widget _themeModePicker(AppSettingsStore settings) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
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

  Widget _localModelDropdown() {
    final current = _localModel.text.trim();
    final modelNames = _localModels
        .map((model) => model.requestName)
        .toList(growable: false);
    return DropdownButtonFormField<String>(
      key: ValueKey('${modelNames.join('|')}|$current'),
      initialValue: modelNames.contains(current) ? current : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Detected local models'),
      items: _localModels
          .map(
            (model) => DropdownMenuItem(
              value: model.requestName,
              child: _localModelOption(model),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) =>
          _localModels.map(_localModelOption).toList(growable: false),
      onChanged: (value) {
        if (value == null) return;
        _localModel.text = value;
        widget.settings.update((settings) {
          settings.localModel = value;
          settings.applyStoredReasoningSettingsForModel(value);
        });
        _reasoningOn.text = widget.settings.reasoningOnValue;
        _reasoningOff.text = widget.settings.reasoningOffValue;
        final storedOptions = widget.settings.reasoningOptionsForModel(value);
        if (storedOptions.isNotEmpty) {
          setState(() => _reasoningOptions = storedOptions);
        }
        unawaited(_refreshReasoningOptions());
      },
    );
  }

  Widget _localModelOption(LocalLLMModel model) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: model.isLoaded
              ? Icon(
                  Icons.check_circle,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                )
              : null,
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(model.name, overflow: TextOverflow.ellipsis)),
      ],
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
