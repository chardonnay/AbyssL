import 'package:abyssl_flutter/main.dart';
import 'package:abyssl_flutter/src/models.dart';
import 'package:abyssl_flutter/src/openai_client.dart';
import 'package:abyssl_flutter/src/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  testWidgets('translator layout fits the narrow macOS startup window', (
    tester,
  ) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(736, 558);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);

    await tester.pumpWidget(AbyssLApp(settings: settings));
    await tester.pumpAndSettle();

    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: flutterErrors.map((details) => details.toString()).join('\n'),
    );
  });

  testWidgets('settings dialog fits desktop window with local model controls', (
    tester,
  ) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1195, 789);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);

    await tester.pumpWidget(AbyssLApp(settings: settings));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.text('Detect Local'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: flutterErrors.map((details) => details.toString()).join('\n'),
    );
  });

  testWidgets('app theme mode follows settings', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);

    await tester.pumpWidget(AbyssLApp(settings: settings));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    settings.update((settings) => settings.themeMode = AppThemeMode.dark);
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    settings.update((settings) => settings.themeMode = AppThemeMode.light);
    await tester.pump();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.light,
    );
  });

  testWidgets('appearance selector fits the narrow startup window', (
    tester,
  ) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(736, 558);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);

    await tester.pumpWidget(AbyssLApp(settings: settings));
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pump();
    await tester.tap(find.text('Light'));
    await tester.pump();

    expect(settings.themeMode, AppThemeMode.light);
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: flutterErrors.map((details) => details.toString()).join('\n'),
    );
  });

  testWidgets('startup detects local model and restores model reasoning', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);
    settings.update((settings) {
      settings.selectedProvider = TranslationProvider.localLLM;
      settings.localServerHost = '127.0.0.1';
      settings.localServerPort = 1234;
      settings.localUseHTTPS = false;
      settings.reasoningOnValue = 'low';
      settings.reasoningOffValue = 'none';
      settings.reasoningEnabled = false;
      settings.rememberReasoningSettingsForModel(
        'qwen3-8b-loaded',
        allowedOptions: const ['off', 'on'],
        reasoningOnValue: 'on',
        reasoningOffValue: 'off',
        reasoningEnabled: true,
      );
    });

    await tester.pumpWidget(
      AbyssLApp(settings: settings, apiClient: _FakeStartupApiClient()),
    );
    await tester.pumpAndSettle();

    expect(settings.localModel, 'qwen3-8b-loaded');
    expect(settings.reasoningOnValue, 'on');
    expect(settings.reasoningOffValue, 'off');
    expect(settings.reasoningEnabled, isTrue);
    expect(settings.reasoningOptionsForModel('qwen3-8b-loaded'), ['off', 'on']);
  });

  testWidgets('result chip panel scrolls when many chips are present', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 72,
            child: ResultChipPanel(
              title: 'Synonyms',
              values: List.generate(24, (index) => 'synonym $index'),
              controller: controller,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(controller.position.maxScrollExtent, greaterThan(0));

    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -48));
    await tester.pump();

    expect(controller.offset, greaterThan(0));
  });

  testWidgets('source clear button clears source and translation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 763);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);

    await tester.pumpWidget(AbyssLApp(settings: settings));
    await tester.enterText(find.widgetWithText(TextField, 'Source'), 'source');
    await tester.enterText(
      find.widgetWithText(TextField, 'Translation'),
      'translation',
    );
    await tester.tap(find.byTooltip('Clear source and translation'));
    await tester.pump();

    expect(find.text('source'), findsNothing);
    expect(find.text('translation'), findsNothing);
  });

  testWidgets('input clear button clears correction input and output', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 763);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);

    await tester.pumpWidget(AbyssLApp(settings: settings));
    await tester.tap(find.text('Correction'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Input'), 'input');
    await tester.enterText(
      find.widgetWithText(TextField, 'Corrected / rewritten text'),
      'output',
    );
    await tester.tap(find.byTooltip('Clear input and correction'));
    await tester.pump();

    expect(find.text('input'), findsNothing);
    expect(find.text('output'), findsNothing);
  });

  testWidgets('rewrite style changes reuse the original input text', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1250, 763);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(preferences: preferences);
    final apiClient = _RecordingRewriteApiClient();

    await tester.pumpWidget(
      AbyssLApp(settings: settings, apiClient: apiClient),
    );
    await tester.tap(find.text('Correction'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Input'),
      'Original long text.',
    );

    await tester.tap(find.text('Standard'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ultra Short').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rewrite'));
    await tester.pumpAndSettle();

    expect(find.text('ultra short result'), findsOneWidget);

    await tester.tap(find.text('Ultra Short'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rewrite'));
    await tester.pumpAndSettle();

    expect(apiClient.rewriteCalls, hasLength(2));
    expect(apiClient.rewriteCalls.last.text, 'Original long text.');
    expect(
      apiClient.rewriteCalls.last.stylePreset,
      WritingStylePreset.standard,
    );
    expect(find.text('standard result'), findsOneWidget);
  });

  testWidgets('correction issue cards do not overflow with long alternatives', (
    tester,
  ) async {
    final flutterErrors = <FlutterErrorDetails>[];
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      flutterErrors.add(details);
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 130);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 130,
          child: CorrectionIssueCard(
            issue: WritingCorrectionIssue(
              originalText:
                  'Synchronizitaeten der Gehirnwellen, zwischen Partnern',
              correctedText:
                  'Synchronizitat der Gehirnwellen zwischen Partnern',
              message: 'Substantivform falsch',
              alternatives: [
                'Synchronizitat der Gehirnwellen bei Partnern',
                'Abstimmung der Gehirnwellen zwischen Partnern',
                'gleichlaufende Gehirnwellen zwischen Partnern',
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Substantivform falsch'), findsOneWidget);
    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: flutterErrors.map((details) => details.toString()).join('\n'),
    );
  });
}

// Test double for startup-only local LLM detection.
class _FakeStartupApiClient extends AbyssLApiClient {
  @override
  Future<List<LocalLLMModel>> fetchLocalModelCatalog({
    required Uri baseUri,
    required String apiKey,
    Duration? timeout,
  }) async {
    return const [
      LocalLLMModel(
        id: 'qwen3-8b-loaded',
        requestName: 'qwen3-8b-loaded',
        name: 'Qwen 3',
        isLoaded: true,
      ),
    ];
  }

  @override
  Future<LocalReasoningOptions> fetchLocalReasoningOptions({
    required Uri baseUri,
    required String apiKey,
    required String model,
    Duration? timeout,
  }) async {
    return const LocalReasoningOptions(
      allowedOptions: ['off', 'on'],
      defaultOption: 'on',
      resolvedModelName: 'qwen3-8b-loaded',
    );
  }

  @override
  void close() {}
}

// Test double for correction rewrite requests.
class _RecordingRewriteApiClient extends AbyssLApiClient {
  final rewriteCalls = <_RewriteCall>[];

  @override
  Future<String> rewriteWriting({
    required String text,
    required String instruction,
    required WritingStylePreset stylePreset,
    required ProviderRequestConfig config,
  }) async {
    rewriteCalls.add(
      _RewriteCall(
        text: text,
        instruction: instruction,
        stylePreset: stylePreset,
      ),
    );
    return stylePreset == WritingStylePreset.ultraShortSummary
        ? 'ultra short result'
        : 'standard result';
  }

  @override
  void close() {}
}

class _RewriteCall {
  const _RewriteCall({
    required this.text,
    required this.instruction,
    required this.stylePreset,
  });

  final String text;
  final String instruction;
  final WritingStylePreset stylePreset;
}
