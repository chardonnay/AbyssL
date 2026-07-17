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
  static const defaultLocalRequestTimeoutSeconds = 600;

  static const _apiKeyKey = 'abyssl.apiKey';
  static const _localApiKeyKey = 'abyssl.local.apiKey';
  static const _serverHostKey = 'abyssl.serverHost';
  static const _serverPortKey = 'abyssl.serverPort';
  static const _useHTTPSKey = 'abyssl.useHTTPS';
  static const _providerKey = 'abyssl.provider';
  static const _themeModeKey = 'abyssl.themeMode';
  static const _localServerHostKey = 'abyssl.local.serverHost';
  static const _localServerPortKey = 'abyssl.local.serverPort';
  static const _localUseHTTPSKey = 'abyssl.local.useHTTPS';
  static const _localModelKey = 'abyssl.local.model';
  static const _localRequestTimeoutSecondsKey =
      'abyssl.local.requestTimeoutSeconds';
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

  String apiKey = '';
  String localApiKey = '';
  String serverHost = 'api.openai.com';
  int serverPort = 443;
  bool useHTTPS = true;
  TranslationProvider selectedProvider = TranslationProvider.openAI;
  AppThemeMode themeMode = AppThemeMode.system;
  String localServerHost = 'localhost';
  int localServerPort = 11434;
  bool localUseHTTPS = false;
  String localModel = '';
  int localRequestTimeoutSeconds = defaultLocalRequestTimeoutSeconds;
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
  OpenAIModel selectedModel = OpenAIModel.gpt4oMini;
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
    final scheme = provider == TranslationProvider.openAI
        ? (useHTTPS ? 'https' : 'http')
        : (localUseHTTPS ? 'https' : 'http');
    final host =
        (provider == TranslationProvider.openAI ? serverHost : localServerHost)
            .trim();
    if (host.isEmpty) {
      throw const AbyssLApiException('Server host is empty.');
    }
    final port = provider == TranslationProvider.openAI
        ? serverPort
        : localServerPort;
    final defaultPort = scheme == 'https' ? 443 : 80;
    return Uri(
      scheme: scheme,
      host: host,
      port: port == defaultPort ? 0 : port,
    );
  }

  ProviderRequestConfig requestConfig() => ProviderRequestConfig(
    provider: selectedProvider,
    openAIBaseUri: baseUriFor(TranslationProvider.openAI),
    localBaseUri: baseUriFor(TranslationProvider.localLLM),
    openAIApiKey: apiKey,
    localApiKey: localApiKey,
    selectedModel: selectedModel,
    localModel: localModel,
    sourceLanguage: sourceLanguage,
    targetLanguage: targetLanguage,
    style: style,
    reasoningEnabled: reasoningEnabled,
    reasoningEffort: reasoningEnabled ? reasoningOnValue : reasoningOffValue,
    localRequestTimeoutSeconds: localRequestTimeoutSeconds,
    correctionAlternativeCount: correctionAlternativeCount,
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
    serverHost = _preferences.getString(_serverHostKey) ?? serverHost;
    serverPort = _preferences.getInt(_serverPortKey) ?? serverPort;
    useHTTPS = _preferences.getBool(_useHTTPSKey) ?? useHTTPS;
    selectedProvider =
        _enumByName(
          TranslationProvider.values,
          _preferences.getString(_providerKey),
        ) ??
        selectedProvider;
    themeMode =
        _enumByName(
          AppThemeMode.values,
          _preferences.getString(_themeModeKey),
        ) ??
        themeMode;
    localServerHost =
        _preferences.getString(_localServerHostKey) ?? localServerHost;
    localServerPort =
        _preferences.getInt(_localServerPortKey) ?? localServerPort;
    localUseHTTPS = _preferences.getBool(_localUseHTTPSKey) ?? localUseHTTPS;
    localModel = _preferences.getString(_localModelKey)?.trim() ?? localModel;
    localRequestTimeoutSeconds =
        (_preferences.getInt(_localRequestTimeoutSecondsKey) ??
                defaultLocalRequestTimeoutSeconds)
            .clamp(0, 1 << 31);
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
    selectedModel = OpenAIModel.fromId(
      _preferences.getString(_selectedModelKey) ?? selectedModel.id,
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
      llmProfiles = [
        LLMProfile(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: 'Default',
          host: localServerHost,
          port: localServerPort,
          useHTTPS: localUseHTTPS,
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
  }

  Future<void> _loadSecrets() async {
    try {
      apiKey = await _secureStorage.read(key: _apiKeyKey) ?? '';
      localApiKey = await _secureStorage.read(key: _localApiKeyKey) ?? '';
      secureStorageAvailable = true;
      secureStorageWarning = null;
    } catch (error) {
      secureStorageAvailable = false;
      secureStorageWarning = 'Secure storage is unavailable: $error';
      apiKey = '';
      localApiKey = '';
    }
  }

  Future<void> save() async {
    rememberReasoningSettingsForModel(
      localModel,
      allowedOptions: reasoningOptionsForModel(localModel),
      reasoningOnValue: reasoningOnValue,
      reasoningOffValue: reasoningOffValue,
      reasoningEnabled: reasoningEnabled,
    );
    await _preferences.setString(
      _serverHostKey,
      serverHost.trim().isEmpty ? 'api.openai.com' : serverHost.trim(),
    );
    await _preferences.setInt(_serverPortKey, serverPort.clamp(1, 65535));
    await _preferences.setBool(_useHTTPSKey, useHTTPS);
    await _preferences.setString(_providerKey, selectedProvider.name);
    await _preferences.setString(_themeModeKey, themeMode.name);
    await _preferences.setString(
      _localServerHostKey,
      localServerHost.trim().isEmpty ? 'localhost' : localServerHost.trim(),
    );
    await _preferences.setInt(
      _localServerPortKey,
      localServerPort.clamp(1, 65535),
    );
    await _preferences.setBool(_localUseHTTPSKey, localUseHTTPS);
    await _preferences.setString(_localModelKey, localModel.trim());
    await _preferences.setInt(
      _localRequestTimeoutSecondsKey,
      localRequestTimeoutSeconds.clamp(0, 1 << 31),
    );
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
    await _preferences.setString(_selectedModelKey, selectedModel.id);
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
      await _persistSecret(_apiKeyKey, apiKey);
      await _persistSecret(_localApiKeyKey, localApiKey);
      secureStorageAvailable = true;
      secureStorageWarning = null;
    } catch (error) {
      secureStorageAvailable = false;
      secureStorageWarning = 'Secure storage is unavailable: $error';
      if (apiKey.trim().isNotEmpty || localApiKey.trim().isNotEmpty) {
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
