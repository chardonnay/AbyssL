import 'dart:async';
import 'dart:io';

import 'package:abyssl_flutter/main.dart';
import 'package:abyssl_flutter/src/analytics.dart';
import 'package:abyssl_flutter/src/models.dart';
import 'package:abyssl_flutter/src/openai_client.dart';
import 'package:abyssl_flutter/src/settings_store.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'undecided consent prompts without tracking and Later prompts next start',
    (tester) async {
      _configureDesktopView(tester, const Size(736, 558));
      final fixture = await _createSettings();
      final firstAnalytics = _RecordingAnalyticsService();
      await firstAnalytics.initialize(fixture.settings.analyticsConsent);

      await tester.pumpWidget(
        AbyssLApp(settings: fixture.settings, analyticsService: firstAnalytics),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('analytics-consent-dialog')),
        findsOneWidget,
      );
      expect(firstAnalytics.events, isEmpty);

      await tester.tap(find.byKey(const ValueKey('analytics-consent-later')));
      await tester.pumpAndSettle();

      expect(fixture.settings.analyticsConsent, AnalyticsConsent.undecided);
      expect(fixture.preferences.getString('abyssl.analyticsConsent'), isNull);
      expect(firstAnalytics.consentChanges, isEmpty);
      expect(firstAnalytics.events, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      final secondAnalytics = _RecordingAnalyticsService();
      await secondAnalytics.initialize(fixture.settings.analyticsConsent);
      await tester.pumpWidget(
        AbyssLApp(
          settings: fixture.settings,
          analyticsService: secondAnalytics,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('analytics-consent-dialog')),
        findsOneWidget,
      );
      expect(secondAnalytics.events, isEmpty);
    },
  );

  testWidgets('Allow persists consent and emits app_started exactly once', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings();
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);

    await tester.pumpWidget(
      AbyssLApp(settings: fixture.settings, analyticsService: analytics),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics-consent-allow')));
    await tester.pumpAndSettle();

    expect(fixture.settings.analyticsConsent, AnalyticsConsent.granted);
    expect(
      fixture.preferences.getString('abyssl.analyticsConsent'),
      AnalyticsConsent.granted.name,
    );
    expect(analytics.consentChanges, [AnalyticsConsent.granted]);
    final starts = analytics.events
        .where((event) => event.name == 'app_started')
        .toList();
    expect(starts, hasLength(1));
    expect(
      starts.single.properties,
      containsPair('app_language_setting', 'system'),
    );
    expect(
      starts.single.properties,
      containsPair('app_language_resolved', 'en'),
    );
    expect(
      starts.single.properties,
      containsPair('default_provider', 'openai'),
    );

    await tester.pump();
    expect(
      analytics.events.where((event) => event.name == 'app_started'),
      hasLength(1),
    );
  });

  testWidgets('Deny persists consent without emitting an event', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings();
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);

    await tester.pumpWidget(
      AbyssLApp(settings: fixture.settings, analyticsService: analytics),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics-consent-deny')));
    await tester.pumpAndSettle();

    expect(fixture.settings.analyticsConsent, AnalyticsConsent.denied);
    expect(
      fixture.preferences.getString('abyssl.analyticsConsent'),
      AnalyticsConsent.denied.name,
    );
    expect(analytics.consentChanges, [AnalyticsConsent.denied]);
    expect(analytics.events, isEmpty);
  });

  testWidgets(
    'Privacy setting restores on cancel and activates or revokes on save',
    (tester) async {
      _configureDesktopView(tester);
      final fixture = await _createSettings(
        initialConsent: AnalyticsConsent.denied,
      );
      final analytics = _RecordingAnalyticsService();
      await analytics.initialize(fixture.settings.analyticsConsent);

      await tester.pumpWidget(
        AbyssLApp(settings: fixture.settings, analyticsService: analytics),
      );
      await tester.pumpAndSettle();

      await _openPrivacySettings(tester);
      await tester.tap(find.byKey(const ValueKey('analytics-consent-switch')));
      await tester.pump();
      expect(fixture.settings.analyticsConsent, AnalyticsConsent.granted);
      expect(analytics.consentChanges, isEmpty);
      expect(analytics.events, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fixture.settings.analyticsConsent, AnalyticsConsent.denied);
      expect(analytics.consentChanges, isEmpty);
      expect(analytics.events, isEmpty);

      await tester.tap(find.byKey(const ValueKey('nav-settings')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('app-language-system')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deutsch').last);
      await tester.pumpAndSettle();

      expect(fixture.settings.appLanguage, AppLanguage.german);
      expect(analytics.consentChanges, isEmpty);
      expect(analytics.events, isEmpty);

      await tester.tap(find.byKey(const ValueKey('settings-section-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analytics-consent-switch')));
      await tester.pump();

      expect(fixture.settings.analyticsConsent, AnalyticsConsent.granted);
      expect(analytics.consentChanges, isEmpty);
      expect(analytics.events, isEmpty);

      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pumpAndSettle();

      expect(fixture.settings.analyticsConsent, AnalyticsConsent.granted);
      expect(analytics.consentChanges, [AnalyticsConsent.granted]);
      expect(
        analytics.events.where((event) => event.name == 'app_started'),
        hasLength(1),
      );
      final appStarted = analytics.events.singleWhere(
        (event) => event.name == 'app_started',
      );
      expect(
        appStarted.properties,
        containsPair('app_language_setting', 'german'),
      );
      expect(
        appStarted.properties,
        containsPair('app_language_resolved', 'de'),
      );
      expect(
        fixture.preferences.getString('abyssl.analyticsConsent'),
        AnalyticsConsent.granted.name,
      );
      expect(find.byKey(const ValueKey('settings-dialog')), findsNothing);
      expect(
        find.byKey(const ValueKey('analytics-consent-dialog')),
        findsNothing,
      );

      await _openPrivacySettings(tester);
      await tester.tap(find.byKey(const ValueKey('analytics-consent-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('save-settings')));
      await tester.pumpAndSettle();

      expect(fixture.settings.analyticsConsent, AnalyticsConsent.denied);
      expect(analytics.consentChanges, [
        AnalyticsConsent.granted,
        AnalyticsConsent.denied,
      ]);
      expect(
        fixture.preferences.getString('abyssl.analyticsConsent'),
        AnalyticsConsent.denied.name,
      );
      expect(
        analytics.events.where((event) => event.name == 'app_started'),
        hasLength(1),
      );
    },
  );

  testWidgets('completed translation and style events exclude content data', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings(
      initialConsent: AnalyticsConsent.granted,
    );
    fixture.settings.update((settings) {
      settings.autoTranslateEnabled = false;
      settings.openAIApiKey = 'private-api-key';
      settings.openAIModelId = 'private-model-id';
      settings.openAIBaseUrl = 'https://compatible.example/private-api-path';
    });
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);
    final apiClient = _RecordingTranslateApiClient();

    await tester.pumpWidget(
      AbyssLApp(
        settings: fixture.settings,
        apiClient: apiClient,
        analyticsService: analytics,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('source-editor')),
      'private source text',
    );
    await tester.enterText(
      find.byKey(const ValueKey('direct-instruction')),
      'private translation instruction',
    );
    await tester.tap(find.byKey(const ValueKey('translate-primary')));
    await tester.pumpAndSettle();

    final completed = analytics.events.singleWhere(
      (event) => event.name == 'feature_completed',
    );
    expect(completed.properties, containsPair('feature', 'translation'));
    expect(completed.properties, containsPair('operation', 'translate'));
    expect(completed.properties, containsPair('trigger', 'manual'));
    expect(
      completed.properties,
      containsPair('provider', 'openai_compatible_other'),
    );
    expect(
      completed.properties.values,
      everyElement(anyOf(isA<String>(), isA<num>())),
    );
    _expectNoPrivateContent(completed.properties);

    await tester.tap(find.byKey(const ValueKey('style-trigger')));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<RegisterStyle>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Formal').last);
    await tester.pumpAndSettle();

    final styleChanged = analytics.events.singleWhere(
      (event) => event.name == 'translation_style_changed',
    );
    expect(styleChanged.properties, {
      'dimension': 'register',
      'from': 'neutral',
      'to': 'formal',
      'is_custom': 1,
    });
    _expectNoPrivateContent(styleChanged.properties);
  });

  testWidgets('completed correction emits exactly one safe event', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings(
      initialConsent: AnalyticsConsent.granted,
    );
    fixture.settings.update((settings) {
      settings.openAIApiKey = 'private-api-key';
      settings.openAIModelId = 'private-model-id';
    });
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);

    await tester.pumpWidget(
      AbyssLApp(
        settings: fixture.settings,
        apiClient: _CorrectionApiClient(),
        analyticsService: analytics,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('correction-input-editor')),
      'private correction source',
    );
    await tester.enterText(
      find.byKey(const ValueKey('correction-instruction')),
      'private correction instruction',
    );
    await tester.tap(find.byKey(const ValueKey('translate-primary')));
    await tester.pumpAndSettle();

    final completed = analytics.events
        .where((event) => event.name == 'feature_completed')
        .toList();
    expect(completed, hasLength(1));
    expect(completed.single.properties, containsPair('feature', 'correction'));
    expect(completed.single.properties, containsPair('operation', 'correct'));
    expect(completed.single.properties, containsPair('trigger', 'manual'));
    expect(completed.single.properties, containsPair('issue_count', 1));
    _expectNoPrivateContent(completed.single.properties);
  });

  testWidgets('completed rewrite emits exactly one safe event', (tester) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings(
      initialConsent: AnalyticsConsent.granted,
    );
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);

    await tester.pumpWidget(
      AbyssLApp(
        settings: fixture.settings,
        apiClient: _RewriteApiClient(),
        analyticsService: analytics,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('correction-input-editor')),
      'private rewrite source',
    );
    await tester.enterText(
      find.byKey(const ValueKey('correction-instruction')),
      'private rewrite instruction',
    );
    await tester.tap(find.byKey(const ValueKey('rewrite-primary')));
    await tester.pumpAndSettle();

    final completed = analytics.events
        .where((event) => event.name == 'feature_completed')
        .toList();
    expect(completed, hasLength(1));
    expect(completed.single.properties, containsPair('feature', 'correction'));
    expect(completed.single.properties, containsPair('operation', 'rewrite'));
    expect(
      completed.single.properties,
      containsPair('rewrite_preset', 'standard'),
    );
    _expectNoPrivateContent(completed.single.properties);
  });

  testWidgets('completed document batch emits exactly one safe event', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings(
      initialConsent: AnalyticsConsent.granted,
    );
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'abyssl-analytics-documents-',
    );
    addTearDown(() {
      if (temporaryDirectory.existsSync()) {
        temporaryDirectory.deleteSync(recursive: true);
      }
    });
    final inputFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}private-document.pages',
    );
    inputFile.writeAsStringSync('private document contents');
    final outputDirectory = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}output',
    );
    outputDirectory.createSync();

    const filePickerChannel = MethodChannel(
      'miguelruivo.flutter.plugins.filepicker',
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      filePickerChannel,
      (call) async => call.method == 'dir' || call.method == 'getDirectoryPath'
          ? outputDirectory.path
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        filePickerChannel,
        null,
      ),
    );

    await tester.pumpWidget(
      AbyssLApp(settings: fixture.settings, analyticsService: analytics),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('nav-documents')));
    await tester.pump();

    final dropTarget = tester.widget<DropTarget>(
      find.byKey(const ValueKey('document-drop-target')),
    );
    dropTarget.onDragDone!(
      DropDoneDetails(
        files: [DropItemFile(inputFile.path)],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Output folder'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('translate-primary')));

    for (var attempt = 0; attempt < 20; attempt++) {
      if (analytics.events.any((event) => event.name == 'feature_completed')) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 10));
    }

    final featureEvents = analytics.events
        .where((event) => event.name.startsWith('feature_'))
        .toList();
    expect(featureEvents, hasLength(1));
    final completed = featureEvents.single;
    expect(completed.name, 'feature_completed');
    expect(completed.properties.keys.toSet(), {
      'feature',
      'operation',
      'trigger',
      'provider',
      'app_language_resolved',
      'duration_ms',
      'job_count',
      'success_count',
      'failure_count',
      'skipped_count',
      'input_type',
      'export_format',
      'correction_enabled',
      'translation_enabled',
    });
    expect(completed.properties, containsPair('feature', 'documents'));
    expect(
      completed.properties,
      containsPair('operation', 'process_documents'),
    );
    expect(completed.properties, containsPair('trigger', 'manual'));
    expect(completed.properties, containsPair('provider', 'openai'));
    expect(completed.properties, containsPair('job_count', 1));
    expect(completed.properties, containsPair('success_count', 0));
    expect(completed.properties, containsPair('failure_count', 1));
    expect(completed.properties, containsPair('skipped_count', 0));
    expect(completed.properties, containsPair('input_type', 'pages'));
    expect(completed.properties, containsPair('export_format', 'pdf'));
    expect(completed.properties, containsPair('correction_enabled', 1));
    expect(completed.properties, containsPair('translation_enabled', 1));
    expect(completed.properties['duration_ms'], isA<int>());
    expect(completed.properties.toString(), isNot(contains(inputFile.path)));
    expect(
      completed.properties.toString(),
      isNot(contains(outputDirectory.path)),
    );
    expect(
      completed.properties.toString(),
      isNot(contains('private document contents')),
    );
    _expectNoPrivateContent(completed.properties);
  });

  testWidgets('provider failure emits only a safe normalized category', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings(
      initialConsent: AnalyticsConsent.granted,
    );
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);

    await tester.pumpWidget(
      AbyssLApp(
        settings: fixture.settings,
        apiClient: _FailingCorrectionApiClient(),
        analyticsService: analytics,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('correction-input-editor')),
      'private failing source',
    );
    await tester.tap(find.byKey(const ValueKey('translate-primary')));
    await tester.pumpAndSettle();

    final failed = analytics.events
        .where((event) => event.name == 'feature_failed')
        .toList();
    expect(failed, hasLength(1));
    expect(failed.single.properties, containsPair('feature', 'correction'));
    expect(failed.single.properties, containsPair('operation', 'correct'));
    expect(
      failed.single.properties,
      containsPair('failure_category', 'rate_limit'),
    );
    expect(
      analytics.events.where(
        (event) =>
            event.name == 'feature_completed' ||
            event.name == 'feature_cancelled',
      ),
      isEmpty,
    );
    _expectNoPrivateContent(failed.single.properties);
  });

  testWidgets('cancelled correction emits exactly one cancelled event', (
    tester,
  ) async {
    _configureDesktopView(tester);
    final fixture = await _createSettings(
      initialConsent: AnalyticsConsent.granted,
    );
    final analytics = _RecordingAnalyticsService();
    await analytics.initialize(fixture.settings.analyticsConsent);
    final apiClient = _PendingCorrectionApiClient();

    await tester.pumpWidget(
      AbyssLApp(
        settings: fixture.settings,
        apiClient: apiClient,
        analyticsService: analytics,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-correction')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('correction-input-editor')),
      'private cancelled source',
    );
    await tester.tap(find.byKey(const ValueKey('translate-primary')));
    await tester.pump();
    await apiClient.started.future;

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    final cancelled = analytics.events
        .where((event) => event.name == 'feature_cancelled')
        .toList();
    expect(cancelled, hasLength(1));
    expect(cancelled.single.properties, containsPair('feature', 'correction'));
    expect(cancelled.single.properties, containsPair('operation', 'correct'));
    expect(
      analytics.events.where(
        (event) =>
            event.name == 'feature_completed' || event.name == 'feature_failed',
      ),
      isEmpty,
    );
    _expectNoPrivateContent(cancelled.single.properties);
  });
}

void _configureDesktopView(
  WidgetTester tester, [
  Size size = const Size(1250, 763),
]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<_SettingsFixture> _createSettings({
  AnalyticsConsent initialConsent = AnalyticsConsent.undecided,
}) async {
  final preferences = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  final settings = AppSettingsStore(
    preferences: preferences,
    secureStorage: _MemorySecureStorage(),
  );
  if (initialConsent != AnalyticsConsent.undecided) {
    settings.update((settings) => settings.analyticsConsent = initialConsent);
    await settings.saveAnalyticsConsent();
  }
  return _SettingsFixture(settings: settings, preferences: preferences);
}

Future<void> _openPrivacySettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav-settings')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('settings-section-2')));
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('analytics-consent-switch')),
    findsOneWidget,
  );
}

void _expectNoPrivateContent(Map<String, Object> properties) {
  final encoded = properties.toString();
  for (final privateValue in [
    'private source text',
    'translated private source text',
    'private translation instruction',
    'private-api-key',
    'private-model-id',
    'compatible.example',
    '/private-api-path',
    'private correction source',
    'private corrected output',
    'private correction instruction',
    'private correction issue',
    'private rewrite source',
    'private rewritten output',
    'private rewrite instruction',
    'private failing source',
    'private raw provider error',
    'private cancelled source',
  ]) {
    expect(encoded, isNot(contains(privateValue)));
  }
}

class _SettingsFixture {
  const _SettingsFixture({required this.settings, required this.preferences});

  final AppSettingsStore settings;
  final SharedPreferencesWithCache preferences;
}

class _RecordedAnalyticsEvent {
  const _RecordedAnalyticsEvent({required this.name, required this.properties});

  final String name;
  final Map<String, Object> properties;
}

class _RecordingAnalyticsService extends AnalyticsService {
  final events = <_RecordedAnalyticsEvent>[];
  final consentChanges = <AnalyticsConsent>[];
  AnalyticsConsent consent = AnalyticsConsent.undecided;
  var flushCount = 0;
  var disposeCount = 0;

  @override
  Future<void> initialize(AnalyticsConsent consent) async {
    this.consent = consent;
  }

  @override
  Future<void> setConsent(AnalyticsConsent consent) async {
    this.consent = consent;
    consentChanges.add(consent);
  }

  @override
  Future<void> trackEvent(
    String eventName, [
    Map<String, Object> properties = const {},
  ]) async {
    events.add(
      _RecordedAnalyticsEvent(
        name: eventName,
        properties: Map<String, Object>.unmodifiable(properties),
      ),
    );
  }

  @override
  Future<void> flush() async {
    flushCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

class _RecordingTranslateApiClient extends AbyssLApiClient {
  @override
  Future<TranslationAIResult> translate({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) async {
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

class _CorrectionApiClient extends AbyssLApiClient {
  @override
  Future<WritingCorrectionResult> correctWriting({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) async => const WritingCorrectionResult(
    correctedText: 'private corrected output',
    issues: [
      WritingCorrectionIssue(
        originalText: 'private correction source',
        correctedText: 'private corrected output',
        message: 'private correction issue',
      ),
    ],
  );

  @override
  void close() {}
}

class _RewriteApiClient extends AbyssLApiClient {
  @override
  Future<String> rewriteWriting({
    required String text,
    required String instruction,
    required WritingStylePreset stylePreset,
    required ProviderRequestConfig config,
  }) async => 'private rewritten output';

  @override
  void close() {}
}

class _FailingCorrectionApiClient extends AbyssLApiClient {
  @override
  Future<WritingCorrectionResult> correctWriting({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) async {
    throw const AbyssLApiException(
      'private raw provider error',
      statusCode: 429,
    );
  }

  @override
  void close() {}
}

class _PendingCorrectionApiClient extends AbyssLApiClient {
  final started = Completer<void>();
  final _result = Completer<WritingCorrectionResult>();

  @override
  Future<WritingCorrectionResult> correctWriting({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) {
    if (!started.isCompleted) started.complete();
    return _result.future;
  }

  @override
  void cancelActiveRequests() {
    super.cancelActiveRequests();
    if (!_result.isCompleted) {
      _result.completeError(const AbyssLRequestCancelledException());
    }
  }

  @override
  void close() {}
}

class _MemorySecureStorage extends FlutterSecureStorage {
  final _values = <String, String>{};

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
