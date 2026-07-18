import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'openai_client.dart';

class AppSettingsStore extends ChangeNotifier {
  AppSettingsStore({
    required SharedPreferencesWithCache preferences,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) : _preferences = preferences,
       _secureStorage = secureStorage;

  static const defaultEditorFontSize = 15.0;
  static const minimumEditorFontSize = 10.0;
  static const maximumEditorFontSize = 28.0;
  static const minimumCorrectionAlternativeCount = 3;
  static const maximumCorrectionAlternativeCount = 8;
  static const currentSettingsSchemaVersion = 2;
  static const defaultCloudRequestTimeoutSeconds = 120;
  static const defaultLocalRequestTimeoutSeconds = 600;

  static const _apiKeyKey = 'abyssl.apiKey';
  static const _localApiKeyKey = 'abyssl.local.apiKey';
  static const _serverHostKey = 'abyssl.serverHost';
  static const _serverPortKey = 'abyssl.serverPort';
  static const _useHTTPSKey = 'abyssl.useHTTPS';
  static const _providerKey = 'abyssl.provider';
  static const _themeModeKey = 'abyssl.themeMode';
  static const _appLanguageKey = 'abyssl.appLanguage';
  static const _localServerHostKey = 'abyssl.local.serverHost';
  static const _localServerPortKey = 'abyssl.local.serverPort';
  static const _localUseHTTPSKey = 'abyssl.local.useHTTPS';
  static const _localModelKey = 'abyssl.local.model';
  static const _localRequestTimeoutSecondsKey =
      'abyssl.local.requestTimeoutSeconds';
  static const _settingsSchemaVersionKey = 'abyssl.settingsSchemaVersion';
  static const _selectedProviderV2Key = 'abyssl.v2.selectedProvider';
  static const _openAIBaseUrlKey =
      'abyssl.v2.provider.openAICompatible.baseUrl';
  static const _openAIModelIdKey =
      'abyssl.v2.provider.openAICompatible.modelId';
  static const _openAIAuthModeKey =
      'abyssl.v2.provider.openAICompatible.authMode';
  static const _openAITimeoutKey =
      'abyssl.v2.provider.openAICompatible.timeoutSeconds';
  static const _anthropicBaseUrlKey =
      'abyssl.v2.provider.anthropicCompatible.baseUrl';
  static const _anthropicModelIdKey =
      'abyssl.v2.provider.anthropicCompatible.modelId';
  static const _anthropicAuthModeKey =
      'abyssl.v2.provider.anthropicCompatible.authMode';
  static const _anthropicTimeoutKey =
      'abyssl.v2.provider.anthropicCompatible.timeoutSeconds';
  static const _anthropicVersionKey =
      'abyssl.v2.provider.anthropicCompatible.version';
  static const _localBaseUrlKey =
      'abyssl.v2.provider.localOpenAICompatible.baseUrl';
  static const _localModelIdKey =
      'abyssl.v2.provider.localOpenAICompatible.modelId';
  static const _localAuthModeKey =
      'abyssl.v2.provider.localOpenAICompatible.authMode';
  static const _localTimeoutKey =
      'abyssl.v2.provider.localOpenAICompatible.timeoutSeconds';
  static const _anthropicApiKeyKey = 'abyssl.anthropic.apiKey';
  static const _llmProfilesKey = 'abyssl.llmProfiles';
  static const _selectedLLMProfileIDKey = 'abyssl.selectedLLMProfileID';
  static const _llmReasoningSettingsKey = 'abyssl.llmReasoningSettings';
  static const _autoTranslateKey = 'abyssl.autoTranslate';
  static const _reasoningOnValueKey = 'abyssl.reasoningOnValue';
  static const _reasoningOffValueKey = 'abyssl.reasoningOffValue';
  static const _reasoningEnabledKey = 'abyssl.reasoningEnabled';
  static const _alternativeSuggestionCountKey =
      'abyssl.alternativeSuggestionCount';
  static const _correctionAlternativeCountKey =
      'abyssl.correctionAlternativeCount';
  static const _editorFontSizeKey = 'abyssl.editorFontSize';
  static const _captureShortcutModifierKey = 'abyssl.captureShortcut.modifier';
  static const _captureShortcutKeyKey = 'abyssl.captureShortcut.key';
  static const _selectedModelKey = 'abyssl.selectedModel';
  static const _sourceLanguageKey = 'abyssl.sourceLanguage';
  static const _targetLanguageKey = 'abyssl.targetLanguage';
  static const _styleRegisterKey = 'abyssl.styleRegister';
  static const _styleComplexityKey = 'abyssl.styleComplexity';
  static const _spellingModeKey = 'abyssl.spellingMode';

  final SharedPreferencesWithCache _preferences;
  final FlutterSecureStorage _secureStorage;

  String openAIApiKey = '';
  String anthropicApiKey = '';
  String localApiKey = '';
  String openAIBaseUrl = 'https://api.openai.com/v1';
  String openAIModelId = 'gpt-4o-mini';
  ApiAuthMode openAIAuthMode = ApiAuthMode.bearer;
  int openAIRequestTimeoutSeconds = defaultCloudRequestTimeoutSeconds;
  String anthropicBaseUrl = 'https://api.anthropic.com/v1';
  String anthropicModelId = 'claude-sonnet-4-5';
  ApiAuthMode anthropicAuthMode = ApiAuthMode.xApiKey;
  int anthropicRequestTimeoutSeconds = defaultCloudRequestTimeoutSeconds;
  String anthropicVersion = defaultAnthropicApiVersion;
  String localBaseUrl = 'http://localhost:11434/v1';
  String localModel = '';
  ApiAuthMode localAuthMode = ApiAuthMode.none;
  int localRequestTimeoutSeconds = defaultLocalRequestTimeoutSeconds;
  TranslationProvider selectedProvider = TranslationProvider.openAICompatible;
  AppThemeMode themeMode = AppThemeMode.system;
  AppLanguage appLanguage = AppLanguage.system;
  List<LLMProfile> llmProfiles = const [];
  String selectedLLMProfileID = '';
  Map<String, LLMReasoningSettings> llmReasoningSettings = const {};
  bool autoTranslateEnabled = true;
  String reasoningOnValue = 'low';
  String reasoningOffValue = 'none';
  bool reasoningEnabled = false;
  int alternativeSuggestionCount = 3;
  int correctionAlternativeCount = 3;
  double editorFontSize = defaultEditorFontSize;
  TranslationCaptureModifier captureShortcutModifier =
      TranslationCaptureModifier.control;
  String captureShortcutKey = TranslationCaptureShortcut.defaultKey;
  TranslationLanguage sourceLanguage = TranslationLanguage.automatic;
  TranslationLanguage targetLanguage = TranslationLanguage.englishUS;
  RegisterStyle styleRegister = RegisterStyle.neutral;
  ComplexityStyle styleComplexity = ComplexityStyle.neutral;
  SpellingMode spellingMode = SpellingMode.preserve;
  bool secureStorageAvailable = true;
  String? secureStorageWarning;

  StyleSettings get style => StyleSettings(
    register: styleRegister,
    complexity: styleComplexity,
    spellingMode: spellingMode,
  );

  TranslationCaptureShortcut get captureShortcut => TranslationCaptureShortcut(
    modifier: captureShortcutModifier,
    key: captureShortcutKey,
  );

  Uri baseUriFor(TranslationProvider provider) {
    final raw = baseUrlFor(provider).trim();
    final parsed = Uri.tryParse(raw);
    if (parsed == null ||
        !parsed.hasAuthority ||
        parsed.host.isEmpty ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      throw AbyssLApiException(
        '${provider.label} base URL must be an absolute HTTP or HTTPS URL.',
      );
    }
    if (parsed.query.isNotEmpty || parsed.fragment.isNotEmpty) {
      throw AbyssLApiException(
        '${provider.label} base URL must not contain a query or fragment.',
      );
    }
    final path = parsed.path.length > 1 && parsed.path.endsWith('/')
        ? parsed.path.substring(0, parsed.path.length - 1)
        : parsed.path;
    return parsed.replace(path: path);
  }

  String baseUrlFor(TranslationProvider provider) => switch (provider) {
    TranslationProvider.openAICompatible => openAIBaseUrl,
    TranslationProvider.anthropicCompatible => anthropicBaseUrl,
    TranslationProvider.localOpenAICompatible => localBaseUrl,
  };

  String modelIdFor(TranslationProvider provider) => switch (provider) {
    TranslationProvider.openAICompatible => openAIModelId,
    TranslationProvider.anthropicCompatible => anthropicModelId,
    TranslationProvider.localOpenAICompatible => localModel,
  };

  String apiKeyFor(TranslationProvider provider) => switch (provider) {
    TranslationProvider.openAICompatible => openAIApiKey,
    TranslationProvider.anthropicCompatible => anthropicApiKey,
    TranslationProvider.localOpenAICompatible => localApiKey,
  };

  ApiAuthMode authModeFor(TranslationProvider provider) => switch (provider) {
    TranslationProvider.openAICompatible => openAIAuthMode,
    TranslationProvider.anthropicCompatible => anthropicAuthMode,
    TranslationProvider.localOpenAICompatible => localAuthMode,
  };

  int timeoutSecondsFor(TranslationProvider provider) => switch (provider) {
    TranslationProvider.openAICompatible => openAIRequestTimeoutSeconds,
    TranslationProvider.anthropicCompatible => anthropicRequestTimeoutSeconds,
    TranslationProvider.localOpenAICompatible => localRequestTimeoutSeconds,
  };

  Duration? timeoutFor(TranslationProvider provider) {
    final seconds = timeoutSecondsFor(provider);
    return seconds > 0 ? Duration(seconds: seconds) : null;
  }

  ProviderRequestConfig requestConfig() => ProviderRequestConfig(
    provider: selectedProvider,
    baseUri: baseUriFor(selectedProvider),
    modelId: modelIdFor(selectedProvider).trim(),
    authMode: authModeFor(selectedProvider),
    apiKey: apiKeyFor(selectedProvider),
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    style: style,
    reasoningEnabled: reasoningEnabled,
    reasoningEffort: reasoningEnabled ? reasoningOnValue : reasoningOffValue,
    timeout: timeoutFor(selectedProvider),
    correctionAlternativeCount: correctionAlternativeCount,
    anthropicVersion: anthropicVersion,
  );

  static Future<AppSettingsStore> load({
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  }) async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final store = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    );
    await store._load();
    return store;
  }

  Future<void> _load() async {
    final storedSchemaVersion =
        _preferences.getInt(_settingsSchemaVersionKey) ?? 1;
    final legacyServerHost =
        _preferences.getString(_serverHostKey) ?? 'api.openai.com';
    final legacyServerPort = _preferences.getInt(_serverPortKey) ?? 443;
    final legacyUseHTTPS = _preferences.getBool(_useHTTPSKey) ?? true;
    final legacyLocalHost =
        _preferences.getString(_localServerHostKey) ?? 'localhost';
    final legacyLocalPort = _preferences.getInt(_localServerPortKey) ?? 11434;
    final legacyLocalUseHTTPS =
        _preferences.getBool(_localUseHTTPSKey) ?? false;

    openAIBaseUrl = _normalizedUrlOrFallback(
      _preferences.getString(_openAIBaseUrlKey) ?? '',
      _legacyBaseUrl(
        host: legacyServerHost,
        port: legacyServerPort,
        useHTTPS: legacyUseHTTPS,
      ),
    );
    openAIModelId = _nonEmpty(
      _preferences.getString(_openAIModelIdKey),
      _preferences.getString(_selectedModelKey) ?? openAIModelId,
    );
    openAIAuthMode =
        _enumByName(
          ApiAuthMode.values,
          _preferences.getString(_openAIAuthModeKey),
        ) ??
        ApiAuthMode.bearer;
    openAIRequestTimeoutSeconds =
        (_preferences.getInt(_openAITimeoutKey) ??
                defaultCloudRequestTimeoutSeconds)
            .clamp(0, 1 << 31);
    anthropicBaseUrl = _normalizedUrlOrFallback(
      _preferences.getString(_anthropicBaseUrlKey) ?? '',
      anthropicBaseUrl,
    );
    anthropicModelId = _nonEmpty(
      _preferences.getString(_anthropicModelIdKey),
      anthropicModelId,
    );
    anthropicAuthMode =
        _enumByName(
          ApiAuthMode.values,
          _preferences.getString(_anthropicAuthModeKey),
        ) ??
        ApiAuthMode.xApiKey;
    anthropicRequestTimeoutSeconds =
        (_preferences.getInt(_anthropicTimeoutKey) ??
                defaultCloudRequestTimeoutSeconds)
            .clamp(0, 1 << 31);
    anthropicVersion = _nonEmpty(
      _preferences.getString(_anthropicVersionKey),
      anthropicVersion,
    );
    localBaseUrl = _normalizedUrlOrFallback(
      _preferences.getString(_localBaseUrlKey) ?? '',
      _legacyBaseUrl(
        host: legacyLocalHost,
        port: legacyLocalPort,
        useHTTPS: legacyLocalUseHTTPS,
      ),
    );
    localModel = _nonEmpty(
      _preferences.getString(_localModelIdKey),
      _preferences.getString(_localModelKey)?.trim() ?? localModel,
    );
    localAuthMode =
        _enumByName(
          ApiAuthMode.values,
          _preferences.getString(_localAuthModeKey),
        ) ??
        ApiAuthMode.none;
    localRequestTimeoutSeconds =
        (_preferences.getInt(_localTimeoutKey) ??
                _preferences.getInt(_localRequestTimeoutSecondsKey) ??
                defaultLocalRequestTimeoutSeconds)
            .clamp(0, 1 << 31);
    selectedProvider = _loadSelectedProvider();
    themeMode =
        _enumByName(
          AppThemeMode.values,
          _preferences.getString(_themeModeKey),
        ) ??
        themeMode;
    appLanguage =
        _enumByName(
          AppLanguage.values,
          _preferences.getString(_appLanguageKey),
        ) ??
        appLanguage;
    autoTranslateEnabled =
        _preferences.getBool(_autoTranslateKey) ?? autoTranslateEnabled;
    reasoningOnValue = _nonEmpty(
      _preferences.getString(_reasoningOnValueKey),
      reasoningOnValue,
    );
    reasoningOffValue = _nonEmpty(
      _preferences.getString(_reasoningOffValueKey),
      reasoningOffValue,
    );
    reasoningEnabled =
        _preferences.getBool(_reasoningEnabledKey) ?? reasoningEnabled;
    alternativeSuggestionCount =
        (_preferences.getInt(_alternativeSuggestionCountKey) ?? 3).clamp(1, 8);
    correctionAlternativeCount =
        (_preferences.getInt(_correctionAlternativeCountKey) ?? 3).clamp(
          minimumCorrectionAlternativeCount,
          maximumCorrectionAlternativeCount,
        );
    editorFontSize =
        (_preferences.getDouble(_editorFontSizeKey) ?? defaultEditorFontSize)
            .clamp(minimumEditorFontSize, maximumEditorFontSize);
    captureShortcutModifier =
        _enumByName(
          TranslationCaptureModifier.values,
          _preferences.getString(_captureShortcutModifierKey),
        ) ??
        captureShortcutModifier;
    captureShortcutKey = TranslationCaptureShortcut.normalizeKey(
      _preferences.getString(_captureShortcutKeyKey) ?? captureShortcutKey,
    );
    sourceLanguage = TranslationLanguage.fromId(
      _preferences.getString(_sourceLanguageKey) ?? sourceLanguage.id,
    );
    targetLanguage = TranslationLanguage.fromId(
      _preferences.getString(_targetLanguageKey) ?? targetLanguage.id,
    );
    styleRegister =
        _enumByName(
          RegisterStyle.values,
          _preferences.getString(_styleRegisterKey),
        ) ??
        styleRegister;
    styleComplexity =
        _enumByName(
          ComplexityStyle.values,
          _preferences.getString(_styleComplexityKey),
        ) ??
        styleComplexity;
    spellingMode =
        _enumByName(
          SpellingMode.values,
          _preferences.getString(_spellingModeKey),
        ) ??
        spellingMode;
    llmReasoningSettings = _loadLLMReasoningSettings();
    applyStoredReasoningSettingsForModel(localModel);
    llmProfiles = _loadProfiles();
    if (llmProfiles.isEmpty) {
      final localUri = Uri.tryParse(localBaseUrl);
      llmProfiles = [
        LLMProfile(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: 'Default',
          host: localUri?.host.isNotEmpty == true
              ? localUri!.host
              : 'localhost',
          port: localUri?.hasPort == true
              ? localUri!.port
              : (localUri?.scheme == 'https' ? 443 : 80),
          useHTTPS: localUri?.scheme == 'https',
          model: localModel,
        ),
      ];
    }
    selectedLLMProfileID =
        _preferences.getString(_selectedLLMProfileIDKey) ??
        llmProfiles.first.id;
    if (!llmProfiles.any((profile) => profile.id == selectedLLMProfileID)) {
      selectedLLMProfileID = llmProfiles.first.id;
    }
    await _loadSecrets();
    if (storedSchemaVersion < currentSettingsSchemaVersion &&
        secureStorageAvailable) {
      if (localApiKey.trim().isNotEmpty) {
        localAuthMode = ApiAuthMode.bearer;
      }
      await _saveProviderPreferences();
    }
  }

  Future<void> _loadSecrets() async {
    try {
      openAIApiKey = await _secureStorage.read(key: _apiKeyKey) ?? '';
      anthropicApiKey =
          await _secureStorage.read(key: _anthropicApiKeyKey) ?? '';
      localApiKey = await _secureStorage.read(key: _localApiKeyKey) ?? '';
      secureStorageAvailable = true;
      secureStorageWarning = null;
    } catch (error) {
      secureStorageAvailable = false;
      secureStorageWarning = 'Secure storage is unavailable: $error';
      openAIApiKey = '';
      anthropicApiKey = '';
      localApiKey = '';
    }
  }

  Future<void> save() async {
    for (final provider in TranslationProvider.values) {
      baseUriFor(provider);
    }
    rememberReasoningSettingsForModel(
      localModel,
      allowedOptions: reasoningOptionsForModel(localModel),
      reasoningOnValue: reasoningOnValue,
      reasoningOffValue: reasoningOffValue,
      reasoningEnabled: reasoningEnabled,
    );
    await _saveProviderPreferences();
    await _preferences.setString(_themeModeKey, themeMode.name);
    await _preferences.setString(_appLanguageKey, appLanguage.name);
    await _preferences.setBool(_autoTranslateKey, autoTranslateEnabled);
    await _preferences.setString(
      _reasoningOnValueKey,
      reasoningOnValue.trim().isEmpty ? 'low' : reasoningOnValue.trim(),
    );
    await _preferences.setString(
      _reasoningOffValueKey,
      reasoningOffValue.trim().isEmpty ? 'none' : reasoningOffValue.trim(),
    );
    await _preferences.setBool(_reasoningEnabledKey, reasoningEnabled);
    await _preferences.setInt(
      _alternativeSuggestionCountKey,
      alternativeSuggestionCount.clamp(1, 8),
    );
    await _preferences.setInt(
      _correctionAlternativeCountKey,
      correctionAlternativeCount.clamp(
        minimumCorrectionAlternativeCount,
        maximumCorrectionAlternativeCount,
      ),
    );
    await _preferences.setDouble(
      _editorFontSizeKey,
      editorFontSize.clamp(minimumEditorFontSize, maximumEditorFontSize),
    );
    await _preferences.setString(
      _captureShortcutModifierKey,
      captureShortcutModifier.name,
    );
    await _preferences.setString(
      _captureShortcutKeyKey,
      TranslationCaptureShortcut.normalizeKey(captureShortcutKey),
    );
    await _preferences.setString(_sourceLanguageKey, sourceLanguage.id);
    await _preferences.setString(_targetLanguageKey, targetLanguage.id);
    await _preferences.setString(_styleRegisterKey, styleRegister.name);
    await _preferences.setString(_styleComplexityKey, styleComplexity.name);
    await _preferences.setString(_spellingModeKey, spellingMode.name);
    await _preferences.setString(
      _llmProfilesKey,
      jsonEncode(llmProfiles.map((profile) => profile.toJson()).toList()),
    );
    await _preferences.setString(
      _selectedLLMProfileIDKey,
      selectedLLMProfileID,
    );
    await _preferences.setString(
      _llmReasoningSettingsKey,
      jsonEncode(
        llmReasoningSettings.values
            .map((settings) => settings.toJson())
            .toList(),
      ),
    );

    try {
      await _persistSecret(_apiKeyKey, openAIApiKey);
      await _persistSecret(_anthropicApiKeyKey, anthropicApiKey);
      await _persistSecret(_localApiKeyKey, localApiKey);
      secureStorageAvailable = true;
      secureStorageWarning = null;
    } catch (error) {
      secureStorageAvailable = false;
      secureStorageWarning = 'Secure storage is unavailable: $error';
      if (openAIApiKey.trim().isNotEmpty ||
          anthropicApiKey.trim().isNotEmpty ||
          localApiKey.trim().isNotEmpty) {
        throw AbyssLApiException(
          'API keys were not saved because secure storage is unavailable: $error',
        );
      }
    } finally {
      notifyListeners();
    }
  }

  Future<void> saveAutoTranslateEnabled() async {
    await _preferences.setBool(_autoTranslateKey, autoTranslateEnabled);
  }

  Future<void> _saveProviderPreferences() async {
    anthropicVersion = _nonEmpty(anthropicVersion, defaultAnthropicApiVersion);
    await _preferences.setInt(
      _settingsSchemaVersionKey,
      currentSettingsSchemaVersion,
    );
    await _preferences.setString(_selectedProviderV2Key, selectedProvider.name);
    await _preferences.setString(
      _openAIBaseUrlKey,
      _normalizedUrlOrFallback(openAIBaseUrl, 'https://api.openai.com/v1'),
    );
    await _preferences.setString(
      _openAIModelIdKey,
      _nonEmpty(openAIModelId, 'gpt-4o-mini'),
    );
    await _preferences.setString(_openAIAuthModeKey, openAIAuthMode.name);
    await _preferences.setInt(
      _openAITimeoutKey,
      openAIRequestTimeoutSeconds.clamp(0, 1 << 31),
    );
    await _preferences.setString(
      _anthropicBaseUrlKey,
      _normalizedUrlOrFallback(
        anthropicBaseUrl,
        'https://api.anthropic.com/v1',
      ),
    );
    await _preferences.setString(
      _anthropicModelIdKey,
      _nonEmpty(anthropicModelId, 'claude-sonnet-4-5'),
    );
    await _preferences.setString(_anthropicAuthModeKey, anthropicAuthMode.name);
    await _preferences.setInt(
      _anthropicTimeoutKey,
      anthropicRequestTimeoutSeconds.clamp(0, 1 << 31),
    );
    await _preferences.setString(_anthropicVersionKey, anthropicVersion);
    await _preferences.setString(
      _localBaseUrlKey,
      _normalizedUrlOrFallback(localBaseUrl, 'http://localhost:11434/v1'),
    );
    await _preferences.setString(_localModelIdKey, localModel.trim());
    await _preferences.setString(_localAuthModeKey, localAuthMode.name);
    await _preferences.setInt(
      _localTimeoutKey,
      localRequestTimeoutSeconds.clamp(0, 1 << 31),
    );
  }

  Future<void> _persistSecret(String key, String value) async {
    if (value.trim().isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  void update(void Function(AppSettingsStore settings) change) {
    change(this);
    notifyListeners();
  }

  LLMReasoningSettings? reasoningSettingsForModel(String model) {
    final key = LLMReasoningSettings.modelKey(model);
    if (key.isEmpty) return null;
    return llmReasoningSettings[key];
  }

  List<String> reasoningOptionsForModel(String model) {
    final settings = reasoningSettingsForModel(model);
    return settings == null
        ? const []
        : List.unmodifiable(settings.allowedOptions);
  }

  void rememberReasoningSettingsForModel(
    String model, {
    List<String>? allowedOptions,
    String? reasoningOnValue,
    String? reasoningOffValue,
    bool? reasoningEnabled,
  }) {
    final key = LLMReasoningSettings.modelKey(model);
    if (key.isEmpty) return;
    final existing = llmReasoningSettings[key];
    final nextAllowed = _normalizeReasoningOptions(
      allowedOptions ?? existing?.allowedOptions ?? const [],
    );
    final next = LLMReasoningSettings(
      model: key,
      allowedOptions: nextAllowed,
      reasoningOnValue: _nonEmpty(
        reasoningOnValue,
        existing?.reasoningOnValue ?? this.reasoningOnValue,
      ),
      reasoningOffValue: _nonEmpty(
        reasoningOffValue,
        existing?.reasoningOffValue ?? this.reasoningOffValue,
      ),
      reasoningEnabled:
          reasoningEnabled ??
          existing?.reasoningEnabled ??
          this.reasoningEnabled,
    );
    llmReasoningSettings = {...llmReasoningSettings, key: next};
  }

  void applyStoredReasoningSettingsForModel(String model) {
    final stored = reasoningSettingsForModel(model);
    if (stored == null) return;
    final allowed = _normalizeReasoningOptions(stored.allowedOptions);
    if (_isReasoningValueAllowed(stored.reasoningOnValue, allowed)) {
      reasoningOnValue = stored.reasoningOnValue;
    }
    if (_isReasoningValueAllowed(stored.reasoningOffValue, allowed)) {
      reasoningOffValue = stored.reasoningOffValue;
    }
    reasoningEnabled = stored.reasoningEnabled;
  }

  void applyDetectedReasoningSettings({
    required String model,
    required LocalReasoningOptions options,
  }) {
    final resolvedModel = LLMReasoningSettings.modelKey(
      options.resolvedModelName ?? model,
    );
    if (resolvedModel.isEmpty) return;
    final allowed = _normalizeReasoningOptions(options.allowedOptions);
    final stored = reasoningSettingsForModel(resolvedModel);
    localModel = resolvedModel;
    reasoningOnValue =
        _firstAllowed([stored?.reasoningOnValue], allowed) ??
        _preferredReasoningOnValue(allowed, options.defaultOption);
    reasoningOffValue =
        _firstAllowed([stored?.reasoningOffValue], allowed) ??
        _preferredReasoningOffValue(allowed, options.defaultOption);
    reasoningEnabled = stored?.reasoningEnabled ?? false;
    rememberReasoningSettingsForModel(
      resolvedModel,
      allowedOptions: allowed,
      reasoningOnValue: reasoningOnValue,
      reasoningOffValue: reasoningOffValue,
      reasoningEnabled: reasoningEnabled,
    );
  }

  List<LLMProfile> _loadProfiles() {
    final raw = _preferences.getString(_llmProfilesKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map(LLMProfile.fromJson).nonNulls.toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  List<LLMReasoningSettings> _loadLLMReasoningSettingsList() {
    final raw = _preferences.getString(_llmReasoningSettingsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .map(LLMReasoningSettings.fromJson)
          .nonNulls
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Map<String, LLMReasoningSettings> _loadLLMReasoningSettings() {
    final entries = <String, LLMReasoningSettings>{};
    for (final settings in _loadLLMReasoningSettingsList()) {
      final key = LLMReasoningSettings.modelKey(settings.model);
      if (key.isNotEmpty) {
        entries[key] = LLMReasoningSettings(
          model: key,
          allowedOptions: _normalizeReasoningOptions(settings.allowedOptions),
          reasoningOnValue: settings.reasoningOnValue,
          reasoningOffValue: settings.reasoningOffValue,
          reasoningEnabled: settings.reasoningEnabled,
        );
      }
    }
    return entries;
  }

  TranslationProvider _loadSelectedProvider() {
    final v2Name = _preferences.getString(_selectedProviderV2Key);
    final v2Provider = _enumByName(TranslationProvider.values, v2Name);
    if (v2Provider != null) return v2Provider;
    return switch (_preferences.getString(_providerKey)) {
      'openAI' => TranslationProvider.openAICompatible,
      'localLLM' => TranslationProvider.localOpenAICompatible,
      final name =>
        _enumByName(TranslationProvider.values, name) ??
            TranslationProvider.openAICompatible,
    };
  }

  static String _legacyBaseUrl({
    required String host,
    required int port,
    required bool useHTTPS,
  }) {
    final scheme = useHTTPS ? 'https' : 'http';
    final normalizedHost = host.trim().isEmpty ? 'localhost' : host.trim();
    final defaultPort = useHTTPS ? 443 : 80;
    return Uri(
      scheme: scheme,
      host: normalizedHost,
      port: port == defaultPort ? null : port.clamp(1, 65535),
      path: '/v1',
    ).toString();
  }

  static String _normalizedUrlOrFallback(String value, String fallback) {
    final trimmed = value.trim();
    final candidate = trimmed.isEmpty ? fallback : trimmed;
    final parsed = Uri.tryParse(candidate);
    final withoutInvalidDefaultPort =
        parsed != null &&
            parsed.hasAuthority &&
            parsed.hasPort &&
            parsed.port == 0
        ? Uri(
            scheme: parsed.scheme,
            userInfo: parsed.userInfo,
            host: parsed.host,
            path: parsed.path,
            query: parsed.hasQuery ? parsed.query : null,
            fragment: parsed.hasFragment ? parsed.fragment : null,
          ).toString()
        : candidate;
    return withoutInvalidDefaultPort.length > 1 &&
            withoutInvalidDefaultPort.endsWith('/')
        ? withoutInvalidDefaultPort.substring(
            0,
            withoutInvalidDefaultPort.length - 1,
          )
        : withoutInvalidDefaultPort;
  }

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static String _nonEmpty(String? value, String fallback) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? fallback : trimmed;
  }

  static List<String> _normalizeReasoningOptions(Iterable<String> options) {
    final normalized = options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toSet()
        .toList();
    normalized.sort(LocalReasoningOptions.compareOptions);
    return normalized;
  }

  static bool _isReasoningValueAllowed(String value, List<String> allowed) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && (allowed.isEmpty || allowed.contains(trimmed));
  }

  static String? _firstAllowed(List<String?> values, List<String> allowed) {
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null &&
          trimmed.isNotEmpty &&
          (allowed.isEmpty || allowed.contains(trimmed))) {
        return trimmed;
      }
    }
    return null;
  }

  static String _preferredReasoningOnValue(
    List<String> allowed,
    String? defaultOption,
  ) {
    if (allowed.isEmpty) return 'off';
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

  static String _preferredReasoningOffValue(
    List<String> allowed,
    String? defaultOption,
  ) {
    if (allowed.isEmpty) return 'off';
    if (allowed.contains('off')) return 'off';
    if (allowed.contains('none')) return 'none';
    if (defaultOption != null && allowed.contains(defaultOption)) {
      return defaultOption;
    }
    return allowed.first;
  }
}
