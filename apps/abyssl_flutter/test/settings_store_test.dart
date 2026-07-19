import 'package:abyssl_flutter/src/analytics.dart';
import 'package:abyssl_flutter/src/models.dart';
import 'package:abyssl_flutter/src/openai_client.dart';
import 'package:abyssl_flutter/src/settings_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('persists reasoning settings per local model', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final secureStorage = _MemorySecureStorage();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    );

    settings.update((settings) {
      settings.localModel = 'qwen3-8b-loaded';
      settings.reasoningOnValue = 'on';
      settings.reasoningOffValue = 'off';
      settings.reasoningEnabled = true;
      settings.rememberReasoningSettingsForModel(
        'qwen3-8b-loaded',
        allowedOptions: const ['off', 'on'],
        reasoningOnValue: 'on',
        reasoningOffValue: 'off',
        reasoningEnabled: true,
      );
    });
    await settings.save();

    final reloaded = await AppSettingsStore.load(secureStorage: secureStorage);

    expect(reloaded.localModel, 'qwen3-8b-loaded');
    expect(reloaded.reasoningOnValue, 'on');
    expect(reloaded.reasoningOffValue, 'off');
    expect(reloaded.reasoningEnabled, isTrue);
    expect(reloaded.reasoningOptionsForModel('qwen3-8b-loaded'), ['off', 'on']);
  });

  test('persists auto translate setting independently', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final secureStorage = _MemorySecureStorage();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    );

    settings.update((settings) => settings.autoTranslateEnabled = false);
    await settings.saveAutoTranslateEnabled();

    final reloaded = await AppSettingsStore.load(secureStorage: secureStorage);

    expect(reloaded.autoTranslateEnabled, isFalse);
  });

  test('persists the application-language preference', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final secureStorage = _MemorySecureStorage();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    )..appLanguage = AppLanguage.croatian;

    await settings.save();

    final reloaded = await AppSettingsStore.load(secureStorage: secureStorage);
    expect(reloaded.appLanguage, AppLanguage.croatian);
  });

  test('defaults missing or invalid analytics consent to undecided', () async {
    for (final initialValues in <Map<String, Object>>[
      const {},
      const {'abyssl.analyticsConsent': 'invalid'},
    ]) {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(initialValues);
      SharedPreferences.setMockInitialValues(initialValues);

      final settings = await AppSettingsStore.load(
        secureStorage: _MemorySecureStorage(),
      );

      expect(settings.analyticsConsent, AnalyticsConsent.undecided);
    }
  });

  for (final consent in [AnalyticsConsent.granted, AnalyticsConsent.denied]) {
    test(
      'persists ${consent.name} analytics consent with all settings',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.empty();
        SharedPreferences.setMockInitialValues({});
        final secureStorage = _MemorySecureStorage();
        final preferences = await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(),
        );
        final settings = AppSettingsStore(
          preferences: preferences,
          secureStorage: secureStorage,
        )..analyticsConsent = consent;

        await settings.save();

        final reloaded = await AppSettingsStore.load(
          secureStorage: secureStorage,
        );
        expect(reloaded.analyticsConsent, consent);
      },
    );
  }

  test('persists analytics consent independently', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final secureStorage = _MemorySecureStorage();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    )..analyticsConsent = AnalyticsConsent.granted;

    await settings.saveAnalyticsConsent();

    expect(
      preferences.getString('abyssl.analyticsConsent'),
      AnalyticsConsent.granted.name,
    );
    final reloaded = await AppSettingsStore.load(secureStorage: secureStorage);
    expect(reloaded.analyticsConsent, AnalyticsConsent.granted);
  });

  test(
    'persists provider schema v2 and keeps all secrets out of preferences',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      SharedPreferences.setMockInitialValues({});
      final secureStorage = _MemorySecureStorage();
      final preferences = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );
      final settings = AppSettingsStore(
        preferences: preferences,
        secureStorage: secureStorage,
      );

      settings.update((settings) {
        settings.selectedProvider = TranslationProvider.anthropicCompatible;
        settings.openAIBaseUrl = 'https://gateway.example/openai/v1/';
        settings.openAIModelId = 'custom-openai-model';
        settings.openAIAuthMode = ApiAuthMode.bearer;
        settings.openAIRequestTimeoutSeconds = 90;
        settings.openAIApiKey = 'openai-secret';
        settings.anthropicBaseUrl = 'https://gateway.example/anthropic/v1';
        settings.anthropicModelId = 'custom-claude';
        settings.anthropicAuthMode = ApiAuthMode.xApiKey;
        settings.anthropicRequestTimeoutSeconds = 75;
        settings.anthropicVersion = '2023-06-01';
        settings.anthropicApiKey = 'anthropic-secret';
        settings.localBaseUrl = 'http://127.0.0.1:1234/v1';
        settings.localModel = 'qwen-local';
        settings.localAuthMode = ApiAuthMode.none;
        settings.localRequestTimeoutSeconds = 450;
        settings.localApiKey = 'local-secret';
      });
      await settings.save();

      final reloaded = await AppSettingsStore.load(
        secureStorage: secureStorage,
      );

      expect(
        reloaded.selectedProvider,
        TranslationProvider.anthropicCompatible,
      );
      expect(reloaded.openAIBaseUrl, 'https://gateway.example/openai/v1');
      expect(reloaded.openAIModelId, 'custom-openai-model');
      expect(reloaded.openAIRequestTimeoutSeconds, 90);
      expect(reloaded.anthropicBaseUrl, 'https://gateway.example/anthropic/v1');
      expect(reloaded.anthropicModelId, 'custom-claude');
      expect(reloaded.anthropicAuthMode, ApiAuthMode.xApiKey);
      expect(reloaded.anthropicRequestTimeoutSeconds, 75);
      expect(reloaded.localBaseUrl, 'http://127.0.0.1:1234/v1');
      expect(reloaded.localModel, 'qwen-local');
      expect(reloaded.localRequestTimeoutSeconds, 450);
      expect(reloaded.openAIApiKey, 'openai-secret');
      expect(reloaded.anthropicApiKey, 'anthropic-secret');
      expect(reloaded.localApiKey, 'local-secret');

      await preferences.reloadCache();
      expect(preferences.getInt('abyssl.settingsSchemaVersion'), 2);
      expect(
        preferences.keys.where((key) => key.toLowerCase().contains('apikey')),
        isEmpty,
      );
      expect(secureStorage.valueFor('abyssl.apiKey'), 'openai-secret');
      expect(
        secureStorage.valueFor('abyssl.anthropic.apiKey'),
        'anthropic-secret',
      );
      expect(secureStorage.valueFor('abyssl.local.apiKey'), 'local-secret');
    },
  );

  test('normalizes a blank Anthropic version in memory when saving', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings =
        AppSettingsStore(
            preferences: preferences,
            secureStorage: _MemorySecureStorage(),
          )
          ..selectedProvider = TranslationProvider.anthropicCompatible
          ..anthropicVersion = '   ';

    await settings.save();

    expect(settings.anthropicVersion, defaultAnthropicApiVersion);
    expect(
      settings.requestConfig().anthropicVersion,
      defaultAnthropicApiVersion,
    );
    expect(
      preferences.getString('abyssl.v2.provider.anthropicCompatible.version'),
      defaultAnthropicApiVersion,
    );
  });

  test(
    'migrates legacy provider values without deleting legacy keys',
    () async {
      final legacyValues = <String, Object>{
        'abyssl.provider': 'localLLM',
        'abyssl.serverHost': 'openai-proxy.example',
        'abyssl.serverPort': 8443,
        'abyssl.useHTTPS': true,
        'abyssl.selectedModel': 'legacy-openai-model',
        'abyssl.local.serverHost': '127.0.0.1',
        'abyssl.local.serverPort': 1234,
        'abyssl.local.useHTTPS': false,
        'abyssl.local.model': 'legacy-local-model',
        'abyssl.local.requestTimeoutSeconds': 321,
      };
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(legacyValues);
      SharedPreferences.setMockInitialValues(legacyValues);
      final secureStorage = _MemorySecureStorage();
      await secureStorage.write(
        key: 'abyssl.apiKey',
        value: 'legacy-openai-key',
      );
      await secureStorage.write(
        key: 'abyssl.local.apiKey',
        value: 'legacy-local-key',
      );

      final migrated = await AppSettingsStore.load(
        secureStorage: secureStorage,
      );

      expect(
        migrated.selectedProvider,
        TranslationProvider.localOpenAICompatible,
      );
      expect(migrated.openAIBaseUrl, 'https://openai-proxy.example:8443/v1');
      expect(migrated.openAIModelId, 'legacy-openai-model');
      expect(migrated.localBaseUrl, 'http://127.0.0.1:1234/v1');
      expect(migrated.localModel, 'legacy-local-model');
      expect(migrated.localRequestTimeoutSeconds, 321);
      expect(migrated.localAuthMode, ApiAuthMode.bearer);
      expect(migrated.openAIApiKey, 'legacy-openai-key');
      expect(migrated.localApiKey, 'legacy-local-key');

      final preferences = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );
      expect(preferences.getInt('abyssl.settingsSchemaVersion'), 2);
      expect(preferences.getString('abyssl.provider'), 'localLLM');
      expect(preferences.getString('abyssl.local.model'), 'legacy-local-model');
      expect(
        preferences.getString('abyssl.v2.selectedProvider'),
        'localOpenAICompatible',
      );
    },
  );

  test('migrates legacy default ports without emitting port zero', () async {
    final legacyValues = <String, Object>{
      'abyssl.provider': 'openAI',
      'abyssl.serverHost': 'api.openai.com',
      'abyssl.serverPort': 443,
      'abyssl.useHTTPS': true,
      'abyssl.local.serverHost': 'local.example',
      'abyssl.local.serverPort': 80,
      'abyssl.local.useHTTPS': false,
    };
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(legacyValues);
    SharedPreferences.setMockInitialValues(legacyValues);

    final migrated = await AppSettingsStore.load(
      secureStorage: _MemorySecureStorage(),
    );

    expect(migrated.selectedProvider, TranslationProvider.openAICompatible);
    expect(migrated.openAIBaseUrl, 'https://api.openai.com/v1');
    expect(migrated.localBaseUrl, 'http://local.example/v1');
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    expect(
      preferences.getString('abyssl.v2.selectedProvider'),
      'openAICompatible',
    );
    expect(
      preferences.getString('abyssl.v2.provider.openAICompatible.baseUrl'),
      'https://api.openai.com/v1',
    );
    expect(
      preferences.getString('abyssl.v2.provider.localOpenAICompatible.baseUrl'),
      'http://local.example/v1',
    );
  });

  test('repairs an explicit zero port left by the legacy migration', () async {
    final values = <String, Object>{
      'abyssl.settingsSchemaVersion': 2,
      'abyssl.v2.provider.openAICompatible.baseUrl':
          'https://api.openai.com:0/v1',
    };
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(values);
    SharedPreferences.setMockInitialValues(values);
    final secureStorage = _MemorySecureStorage();

    final settings = await AppSettingsStore.load(secureStorage: secureStorage);

    expect(settings.openAIBaseUrl, 'https://api.openai.com/v1');
    await settings.save();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    expect(
      preferences.getString('abyssl.v2.provider.openAICompatible.baseUrl'),
      'https://api.openai.com/v1',
    );
  });

  test(
    'reports secure storage read failures without exposing secrets',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      SharedPreferences.setMockInitialValues({});

      final settings = await AppSettingsStore.load(
        secureStorage: _FailingSecureStorage(failReads: true),
      );

      expect(settings.secureStorageAvailable, isFalse);
      expect(settings.secureStorageWarning, contains('read failed'));
      expect(settings.openAIApiKey, isEmpty);
      expect(settings.anthropicApiKey, isEmpty);
      expect(settings.localApiKey, isEmpty);
    },
  );

  test(
    'fails saving a non-empty key when secure storage is unavailable',
    () async {
      const initialValues = {'abyssl.analyticsConsent': 'denied'};
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(initialValues);
      SharedPreferences.setMockInitialValues(initialValues);
      final preferences = await SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(),
      );
      final settings =
          AppSettingsStore(
              preferences: preferences,
              secureStorage: _FailingSecureStorage(failWrites: true),
            )
            ..analyticsConsent = AnalyticsConsent.granted
            ..openAIApiKey = 'must-not-enter-preferences';

      await expectLater(
        settings.save(),
        throwsA(
          isA<AbyssLApiException>().having(
            (error) => error.message,
            'message',
            contains('were not saved'),
          ),
        ),
      );

      await preferences.reloadCache();
      expect(settings.secureStorageAvailable, isFalse);
      expect(settings.secureStorageWarning, contains('write failed'));
      expect(
        preferences.keys.where((key) => key.toLowerCase().contains('apikey')),
        isEmpty,
      );
      expect(
        preferences.keys.any(
          (key) => preferences.get(key) == 'must-not-enter-preferences',
        ),
        isFalse,
      );
      expect(
        preferences.getString('abyssl.analyticsConsent'),
        AnalyticsConsent.denied.name,
      );
    },
  );
}

// Test double for secure storage; secrets are not under test here.
class _MemorySecureStorage extends FlutterSecureStorage {
  final _values = <String, String>{};

  String? valueFor(String key) => _values[key];

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

class _FailingSecureStorage extends FlutterSecureStorage {
  const _FailingSecureStorage({
    this.failReads = false,
    this.failWrites = false,
  });

  final bool failReads;
  final bool failWrites;

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
    if (failWrites) throw StateError('secure storage write failed');
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
    if (failReads) throw StateError('secure storage read failed');
    return null;
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
    if (failWrites) throw StateError('secure storage write failed');
  }
}
