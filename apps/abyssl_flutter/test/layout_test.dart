import 'package:abyssl_flutter/main.dart';
import 'package:abyssl_flutter/src/app_update.dart';
import 'package:abyssl_flutter/src/models.dart';
import 'package:abyssl_flutter/src/openai_client.dart';
import 'package:abyssl_flutter/src/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pub_semver/pub_semver.dart';
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

  testWidgets('design 5 translator keeps source, bridge, and result ordered', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1487, 1058);
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

    expect(find.byKey(const ValueKey('command-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-rail')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-editor')), findsOneWidget);
    expect(find.byKey(const ValueKey('translation-editor')), findsOneWidget);

    final source = tester.getRect(
      find.byKey(const ValueKey('translator-source-pane')),
    );
    final bridge = tester.getRect(
      find.byKey(const ValueKey('translation-bridge')),
    );
    final result = tester.getRect(
      find.byKey(const ValueKey('translator-result-pane')),
    );
    expect(source.bottom, lessThan(bridge.top));
    expect(bridge.bottom, lessThan(result.top));
    expect(source.height / result.height, closeTo(58 / 42, 0.02));
    expect(result.bottom, closeTo(1042, 1));
  });

  testWidgets('style popover exposes translation controls', (tester) async {
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
    await tester.tap(find.byKey(const ValueKey('style-trigger')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('style-popover')), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Complexity'), findsOneWidget);
    expect(find.text('Spelling'), findsOneWidget);
    expect(find.text('Reset to defaults'), findsOneWidget);
  });

  testWidgets('workspace panes follow live desktop window resizing', (
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
    await tester.pumpAndSettle();
    final initialSource = tester.getRect(
      find.byKey(const ValueKey('translator-source-pane')),
    );
    final initialResult = tester.getRect(
      find.byKey(const ValueKey('translator-result-pane')),
    );

    tester.view.physicalSize = const Size(1800, 1300);
    await tester.pumpAndSettle();
    final expandedSource = tester.getRect(
      find.byKey(const ValueKey('translator-source-pane')),
    );
    final expandedResult = tester.getRect(
      find.byKey(const ValueKey('translator-result-pane')),
    );

    expect(expandedSource.width, greaterThan(initialSource.width + 500));
    expect(expandedSource.height, greaterThan(initialSource.height + 300));
    expect(expandedResult.width, greaterThan(initialResult.width + 500));
    expect(expandedResult.height, greaterThan(initialResult.height + 200));
    expect(expandedSource.right, closeTo(1780, 1));
    expect(expandedResult.bottom, closeTo(1284, 1));

    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    final correctionResult = tester.getRect(
      find.byKey(const ValueKey('correction-result-pane')),
    );
    expect(correctionResult.right, closeTo(1780, 1));
    expect(correctionResult.bottom, closeTo(1284, 1));

    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();
    final documentResult = tester.getRect(
      find.byKey(const ValueKey('document-results-pane')),
    );
    expect(documentResult.right, closeTo(1780, 1));
    expect(documentResult.bottom, closeTo(1284, 1));

    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: flutterErrors.map((details) => details.toString()).join('\n'),
    );
  });

  testWidgets('correction, documents, and settings fit narrow window', (
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
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('correction-source-pane')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('document-intake-pane')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-dialog')), findsOneWidget);

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
    await tester.tap(find.byKey(const ValueKey('settings-section-2')));
    await tester.pumpAndSettle();
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

  testWidgets('translator swap button exchanges source and target languages', (
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
      settings.sourceLanguage = TranslationLanguage.german;
      settings.targetLanguage = TranslationLanguage.englishUK;
    });

    await tester.pumpWidget(AbyssLApp(settings: settings));
    await tester.tap(find.byTooltip('Swap source and target languages'));
    await tester.pump();

    expect(settings.sourceLanguage, TranslationLanguage.englishUK);
    expect(settings.targetLanguage, TranslationLanguage.german);
  });

  testWidgets('auto translate switch controls source-change translations', (
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
    final apiClient = _RecordingTranslateApiClient();

    await tester.pumpWidget(
      AbyssLApp(settings: settings, apiClient: apiClient),
    );
    await tester.enterText(
      find.byKey(const ValueKey('source-editor')),
      'hello',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('auto-translate-switch')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(settings.autoTranslateEnabled, isFalse);
    expect(apiClient.translateCalls, isEmpty);

    await tester.tap(find.byKey(const ValueKey('translate-primary')));
    await tester.pumpAndSettle();

    expect(apiClient.translateCalls, ['hello']);
    expect(find.text('translated hello'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('auto-translate-switch')));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('source-editor')), 'next');
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(settings.autoTranslateEnabled, isTrue);
    expect(apiClient.translateCalls, ['hello', 'next']);
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
    await tester.enterText(
      find.byKey(const ValueKey('source-editor')),
      'source',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-editor')),
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
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('correction-input-editor')),
      'input',
    );
    await tester.enterText(
      find.byKey(const ValueKey('correction-output-editor')),
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
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('correction-input-editor')),
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

  testWidgets('about shows app details and offers a signed GitHub update', (
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
    final updateService = _FakeUpdateService();

    await tester.pumpWidget(
      AbyssLApp(settings: settings, updateService: updateService),
    );
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-section-3')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-about-content')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('about-logo')), findsOneWidget);
    expect(find.text('Developed by Daniel Mengel'), findsOneWidget);
    expect(find.text('Version 1.0.0 (1)'), findsOneWidget);
    expect(find.text(abyssLWebsiteUri), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about-website-link')));
    await tester.pump();
    expect(updateService.websiteOpenCount, 1);

    await tester.ensureVisible(find.byKey(const ValueKey('check-for-updates')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('check-for-updates')));
    await tester.pumpAndSettle();
    expect(find.textContaining('AbyssL 1.2.0 is available'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-update')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('install-update')));
    await tester.tap(find.byKey(const ValueKey('install-update')));
    await tester.pumpAndSettle();
    expect(updateService.installCount, 1);

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

// Test double for translator requests.
class _RecordingTranslateApiClient extends AbyssLApiClient {
  final translateCalls = <String>[];

  @override
  Future<TranslationAIResult> translate({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) async {
    translateCalls.add(text);
    return TranslationAIResult(
      translation: 'translated $text',
      synonyms: const [],
      spellingNotes: null,
      revisedSource: null,
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

class _FakeUpdateService implements AppUpdateService {
  var websiteOpenCount = 0;
  var installCount = 0;

  @override
  bool get supportsAutomaticInstall => true;

  @override
  Future<AppBuildInfo> loadInstalledBuild() async {
    return const AppBuildInfo(version: '1.0.0', buildNumber: '1');
  }

  @override
  Future<UpdateCheckResult> checkForUpdates(AppBuildInfo installedBuild) async {
    return UpdateCheckResult(
      kind: UpdateCheckKind.updateAvailable,
      release: GitHubRelease(
        tagName: 'v1.2.0',
        version: Version(1, 2, 0),
        pageUri: Uri.parse(
          'https://github.com/chardonnay/AbyssL/releases/tag/v1.2.0',
        ),
        title: 'AbyssL 1.2.0',
        notes: 'A signed update for macOS.',
        assets: [
          GitHubReleaseAsset(
            name: abyssLMacOSReleaseAssetName,
            downloadUri: Uri.parse(
              'https://github.com/chardonnay/AbyssL/releases/download/v1.2.0/$abyssLMacOSReleaseAssetName',
            ),
            size: 42000000,
          ),
          GitHubReleaseAsset(
            name: abyssLAppcastAssetName,
            downloadUri: Uri.parse(
              'https://github.com/chardonnay/AbyssL/releases/download/v1.2.0/$abyssLAppcastAssetName',
            ),
            size: 1400,
          ),
        ],
      ),
    );
  }

  @override
  Future<void> startAutomaticInstall() async {
    installCount += 1;
  }

  @override
  Future<void> openWebsite() async {
    websiteOpenCount += 1;
  }

  @override
  Future<void> openRelease(GitHubRelease release) async {}
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
