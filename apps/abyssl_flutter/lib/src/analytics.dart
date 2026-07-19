import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AnalyticsConsent { undecided, granted, denied }

enum AnalyticsFeature { translation, correction, documents }

enum AnalyticsOperation { translate, correct, rewrite, processDocuments }

enum AnalyticsTrigger { manual, command, autoTranslate, capture }

enum AnalyticsResult { completed, failed, cancelled }

enum AnalyticsProvider {
  openAI,
  anthropic,
  ollama,
  lmStudio,
  openAICompatibleOther,
  anthropicCompatibleOther,
  localCompatibleOther,
}

enum AnalyticsProviderFamily {
  openAICompatible,
  anthropicCompatible,
  localCompatible,
}

enum AnalyticsFailureCategory {
  timeout,
  network,
  auth,
  rateLimit,
  provider5xx,
  parsing,
  unknown,
}

enum AnalyticsStyleDimension { register, complexity, spellingMode, all }

enum AnalyticsSetting { appLanguage, defaultProvider }

extension AnalyticsFeatureValue on AnalyticsFeature {
  String get analyticsValue => name;
}

extension AnalyticsOperationValue on AnalyticsOperation {
  String get analyticsValue => switch (this) {
    AnalyticsOperation.translate => 'translate',
    AnalyticsOperation.correct => 'correct',
    AnalyticsOperation.rewrite => 'rewrite',
    AnalyticsOperation.processDocuments => 'process_documents',
  };
}

extension AnalyticsTriggerValue on AnalyticsTrigger {
  String get analyticsValue => switch (this) {
    AnalyticsTrigger.manual => 'manual',
    AnalyticsTrigger.command => 'command',
    AnalyticsTrigger.autoTranslate => 'auto_translate',
    AnalyticsTrigger.capture => 'capture',
  };
}

extension AnalyticsResultValue on AnalyticsResult {
  String get eventName => switch (this) {
    AnalyticsResult.completed => 'feature_completed',
    AnalyticsResult.failed => 'feature_failed',
    AnalyticsResult.cancelled => 'feature_cancelled',
  };
}

extension AnalyticsProviderValue on AnalyticsProvider {
  String get analyticsValue => switch (this) {
    AnalyticsProvider.openAI => 'openai',
    AnalyticsProvider.anthropic => 'anthropic',
    AnalyticsProvider.ollama => 'ollama',
    AnalyticsProvider.lmStudio => 'lm_studio',
    AnalyticsProvider.openAICompatibleOther => 'openai_compatible_other',
    AnalyticsProvider.anthropicCompatibleOther => 'anthropic_compatible_other',
    AnalyticsProvider.localCompatibleOther => 'local_compatible_other',
  };
}

extension AnalyticsFailureCategoryValue on AnalyticsFailureCategory {
  String get analyticsValue => switch (this) {
    AnalyticsFailureCategory.timeout => 'timeout',
    AnalyticsFailureCategory.network => 'network',
    AnalyticsFailureCategory.auth => 'auth',
    AnalyticsFailureCategory.rateLimit => 'rate_limit',
    AnalyticsFailureCategory.provider5xx => 'provider_5xx',
    AnalyticsFailureCategory.parsing => 'parsing',
    AnalyticsFailureCategory.unknown => 'unknown',
  };
}

extension AnalyticsStyleDimensionValue on AnalyticsStyleDimension {
  String get analyticsValue => switch (this) {
    AnalyticsStyleDimension.register => 'register',
    AnalyticsStyleDimension.complexity => 'complexity',
    AnalyticsStyleDimension.spellingMode => 'spelling_mode',
    AnalyticsStyleDimension.all => 'all',
  };
}

extension AnalyticsSettingValue on AnalyticsSetting {
  String get analyticsValue => switch (this) {
    AnalyticsSetting.appLanguage => 'app_language',
    AnalyticsSetting.defaultProvider => 'default_provider',
  };
}

/// Classifies a provider without exposing its full endpoint to analytics.
AnalyticsProvider classifyAnalyticsProvider(
  Uri endpoint,
  AnalyticsProviderFamily family,
) {
  final host = endpoint.host.toLowerCase();
  if (host == 'api.openai.com') {
    return AnalyticsProvider.openAI;
  }
  if (host == 'api.anthropic.com') {
    return AnalyticsProvider.anthropic;
  }
  if (family == AnalyticsProviderFamily.localCompatible) {
    if (endpoint.port == 11434) {
      return AnalyticsProvider.ollama;
    }
    if (endpoint.port == 1234) {
      return AnalyticsProvider.lmStudio;
    }
  }
  return switch (family) {
    AnalyticsProviderFamily.openAICompatible =>
      AnalyticsProvider.openAICompatibleOther,
    AnalyticsProviderFamily.anthropicCompatible =>
      AnalyticsProvider.anthropicCompatibleOther,
    AnalyticsProviderFamily.localCompatible =>
      AnalyticsProvider.localCompatibleOther,
  };
}

class AnalyticsFeatureEvent {
  const AnalyticsFeatureEvent({
    required this.feature,
    required this.operation,
    required this.trigger,
    required this.provider,
    required this.duration,
    this.properties = const {},
  });

  final AnalyticsFeature feature;
  final AnalyticsOperation operation;
  final AnalyticsTrigger trigger;
  final AnalyticsProvider provider;
  final Duration duration;
  final Map<String, Object> properties;

  Map<String, Object> toProperties() => <String, Object>{
    ...properties,
    'feature': feature.analyticsValue,
    'operation': operation.analyticsValue,
    'trigger': trigger.analyticsValue,
    'provider': provider.analyticsValue,
    'duration_ms': max(0, duration.inMilliseconds),
  };
}

abstract class AnalyticsService {
  const AnalyticsService();

  Future<void> initialize(AnalyticsConsent consent);

  Future<void> setConsent(AnalyticsConsent consent);

  Future<void> trackEvent(
    String eventName, [
    Map<String, Object> properties = const {},
  ]);

  Future<void> flush();

  Future<void> onAppResumed() => flush();

  Future<void> dispose();

  Future<void> trackAppStarted({
    required String appLanguageSetting,
    required String appLanguageResolved,
    required AnalyticsProvider defaultProvider,
  }) => trackEvent('app_started', <String, Object>{
    'app_language_setting': appLanguageSetting,
    'app_language_resolved': appLanguageResolved,
    'default_provider': defaultProvider.analyticsValue,
    'analytics_schema': 1,
  });

  Future<void> trackFeatureCompleted(AnalyticsFeatureEvent event) =>
      trackEvent('feature_completed', event.toProperties());

  Future<void> trackFeatureFailed(
    AnalyticsFeatureEvent event,
    AnalyticsFailureCategory failure,
  ) => trackEvent('feature_failed', <String, Object>{
    ...event.toProperties(),
    'failure_category': failure.analyticsValue,
  });

  Future<void> trackFeatureCancelled(AnalyticsFeatureEvent event) =>
      trackEvent('feature_cancelled', event.toProperties());

  Future<void> trackTranslationStyleChanged({
    required AnalyticsStyleDimension dimension,
    required String from,
    required String to,
    required bool isCustom,
  }) => trackEvent('translation_style_changed', <String, Object>{
    'dimension': dimension.analyticsValue,
    'from': from,
    'to': to,
    'is_custom': isCustom ? 1 : 0,
  });

  Future<void> trackSettingChanged({
    required AnalyticsSetting setting,
    required String from,
    required String to,
  }) => trackEvent('setting_changed', <String, Object>{
    'setting': setting.analyticsValue,
    'from': from,
    'to': to,
  });
}

class NoOpAnalyticsService extends AnalyticsService {
  const NoOpAnalyticsService();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> flush() async {}

  @override
  Future<void> initialize(AnalyticsConsent consent) async {}

  @override
  Future<void> setConsent(AnalyticsConsent consent) async {}

  @override
  Future<void> trackEvent(
    String eventName, [
    Map<String, Object> properties = const {},
  ]) async {}
}

class AnalyticsSystemInfo {
  const AnalyticsSystemInfo({
    required this.osName,
    required this.osVersion,
    required this.locale,
    required this.appVersion,
    required this.appBuildNumber,
  });

  final String osName;
  final String osVersion;
  final String locale;
  final String appVersion;
  final String appBuildNumber;

  static Future<AnalyticsSystemInfo> fromPlatform() async {
    PackageInfo? packageInfo;
    try {
      packageInfo = await PackageInfo.fromPlatform();
    } on Object {
      // Analytics must remain optional even when platform metadata is absent.
    }

    return AnalyticsSystemInfo(
      osName: _platformOSName(),
      osVersion: Platform.operatingSystemVersion,
      locale: _normalizedLocale(Platform.localeName),
      appVersion: packageInfo?.version ?? '',
      appBuildNumber: packageInfo?.buildNumber ?? '',
    );
  }
}

typedef AnalyticsSystemInfoLoader = Future<AnalyticsSystemInfo> Function();
typedef AnalyticsHttpClientFactory = HttpClient Function();
typedef AnalyticsRetryTimerFactory =
    Timer Function(Duration duration, void Function() callback);

class AptabaseAnalyticsService extends AnalyticsService {
  AptabaseAnalyticsService({
    required SharedPreferencesWithCache preferences,
    bool isReleaseBuild = kReleaseMode,
    String appKey = defaultAppKey,
    Uri? endpoint,
    AnalyticsSystemInfoLoader? systemInfoLoader,
    AnalyticsHttpClientFactory? httpClientFactory,
    AnalyticsRetryTimerFactory? retryTimerFactory,
    DateTime Function()? now,
    String Function()? sessionIdFactory,
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _preferences = preferences,
       _isReleaseBuild = isReleaseBuild,
       _appKey = appKey,
       _endpoint = endpoint ?? Uri.parse(defaultEndpoint),
       _systemInfoLoader = systemInfoLoader ?? AnalyticsSystemInfo.fromPlatform,
       _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _retryTimerFactory = retryTimerFactory ?? Timer.new,
       _now = now ?? _utcNow,
       _sessionIdFactory = sessionIdFactory ?? _newSessionId,
       _requestTimeout = requestTimeout;

  // Aptabase app keys identify a client application and are safe to ship.
  static const defaultAppKey = String.fromEnvironment(
    'ABYSSL_APTABASE_APP_KEY',
    defaultValue: 'A-EU-5362022623',
  );
  static const defaultEndpoint = 'https://eu.aptabase.com/api/v0/events';
  static const queueStorageKey = 'abyssl.analytics.queue.v1';
  static const sdkVersion = 'abyssl-rest@1';
  static const queueLimit = 500;
  static const batchSize = 25;
  static const eventTtl = Duration(hours: 23, minutes: 55);
  static const sessionTimeout = Duration(hours: 1);
  static const retryDelays = <Duration>[
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  static const _allowedEventNames = <String>{
    'app_started',
    'feature_completed',
    'feature_failed',
    'feature_cancelled',
    'translation_style_changed',
    'setting_changed',
  };

  static const _allowedPropertyNames = <String>{
    'analytics_schema',
    'app_language_resolved',
    'app_language_setting',
    'complexity',
    'correction_enabled',
    'default_provider',
    'dimension',
    'duration_ms',
    'export_format',
    'failure_category',
    'failure_count',
    'feature',
    'from',
    'input_type',
    'is_custom',
    'issue_count',
    'job_count',
    'operation',
    'provider',
    'register',
    'rewrite_preset',
    'setting',
    'skipped_count',
    'source_language',
    'spelling_mode',
    'style_custom',
    'success_count',
    'target_language',
    'to',
    'translation_enabled',
    'trigger',
  };

  final SharedPreferencesWithCache _preferences;
  final bool _isReleaseBuild;
  final String _appKey;
  final Uri _endpoint;
  final AnalyticsSystemInfoLoader _systemInfoLoader;
  final AnalyticsHttpClientFactory _httpClientFactory;
  final AnalyticsRetryTimerFactory _retryTimerFactory;
  final DateTime Function() _now;
  final String Function() _sessionIdFactory;
  final Duration _requestTimeout;

  AnalyticsConsent _consent = AnalyticsConsent.undecided;
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;
  int _retryAttempt = 0;
  Timer? _retryTimer;
  HttpClient? _activeHttpClient;
  Future<void>? _activeFlush;
  bool _flushRequested = false;
  Future<void> _storageTail = Future<void>.value();
  Future<AnalyticsSystemInfo>? _systemInfoFuture;
  String? _sessionId;
  DateTime? _lastSessionActivity;

  bool get isEnabled =>
      _initialized &&
      !_disposed &&
      _isReleaseBuild &&
      _consent == AnalyticsConsent.granted;

  AnalyticsConsent get consent => _consent;

  static Future<AptabaseAnalyticsService> create({
    required AnalyticsConsent consent,
    bool isReleaseBuild = kReleaseMode,
    String appKey = defaultAppKey,
    Uri? endpoint,
  }) async {
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final service = AptabaseAnalyticsService(
      preferences: preferences,
      isReleaseBuild: isReleaseBuild,
      appKey: appKey,
      endpoint: endpoint,
    );
    await service.initialize(consent);
    return service;
  }

  @override
  Future<void> initialize(AnalyticsConsent consent) async {
    if (_disposed) {
      return;
    }
    _initialized = true;
    await _applyConsent(consent);
  }

  @override
  Future<void> setConsent(AnalyticsConsent consent) async {
    if (_disposed) {
      return;
    }
    await _applyConsent(consent);
  }

  Future<void> _applyConsent(AnalyticsConsent consent) async {
    _consent = consent;
    if (consent == AnalyticsConsent.granted) {
      if (isEnabled) {
        unawaited(_startFlush(requestAnotherIfActive: false));
      }
      return;
    }

    _generation++;
    _flushRequested = false;
    _cancelRetry(resetAttempt: true);
    _abortActiveRequest();
    _systemInfoFuture = null;
    _sessionId = null;
    _lastSessionActivity = null;
    try {
      await _withStorageLock(() => _writeQueue(const []));
    } on Object {
      // Consent changes must never make the application unusable.
    }
  }

  @override
  Future<void> trackEvent(
    String eventName, [
    Map<String, Object> properties = const {},
  ]) async {
    if (!isEnabled) {
      return;
    }

    final validatedProperties = _validatedProperties(properties);
    if (!_allowedEventNames.contains(eventName) ||
        validatedProperties == null) {
      return;
    }

    final generation = _generation;
    try {
      final systemInfo = await (_systemInfoFuture ??= _systemInfoLoader());
      if (!isEnabled || generation != _generation) {
        return;
      }

      final timestamp = _now().toUtc();
      final event = <String, Object?>{
        'timestamp': timestamp.toIso8601String(),
        'sessionId': _evaluateSessionId(timestamp),
        'eventName': eventName,
        'systemProps': <String, Object>{
          'isDebug': false,
          'osName': _limited(systemInfo.osName, 30),
          'osVersion': _limited(systemInfo.osVersion, 100),
          'locale': _limited(_normalizedLocale(systemInfo.locale), 10),
          'appVersion': _limited(systemInfo.appVersion, 50),
          'appBuildNumber': _limited(systemInfo.appBuildNumber, 20),
          'sdkVersion': sdkVersion,
        },
        'props': validatedProperties,
      };
      final encoded = jsonEncode(event);

      await _withStorageLock(() async {
        if (!isEnabled || generation != _generation) {
          return;
        }
        final queue = _readValidQueue(timestamp);
        final nextQueue = <String>[
          ...queue.map((event) => event.encoded),
          encoded,
        ];
        if (nextQueue.length > queueLimit) {
          nextQueue.removeRange(0, nextQueue.length - queueLimit);
        }
        await _writeQueue(nextQueue);
      });
      if (isEnabled && generation == _generation) {
        unawaited(_startFlush(requestAnotherIfActive: true));
      }
    } on Object {
      // Tracking must never affect translation, correction, or documents.
    }
  }

  @override
  Future<void> flush() => _startFlush(requestAnotherIfActive: false);

  Future<void> _startFlush({required bool requestAnotherIfActive}) {
    if (!isEnabled) {
      return Future<void>.value();
    }
    final active = _activeFlush;
    if (active != null) {
      if (requestAnotherIfActive) {
        _flushRequested = true;
      }
      return active;
    }

    _cancelRetry(resetAttempt: false);
    late final Future<void> operation;
    operation = _flushLoop().catchError((Object _) {}).whenComplete(() {
      if (identical(_activeFlush, operation)) {
        _activeFlush = null;
      }
      if (_flushRequested && isEnabled) {
        _flushRequested = false;
        unawaited(_startFlush(requestAnotherIfActive: false));
      }
    });
    _activeFlush = operation;
    return operation;
  }

  Future<void> _flushLoop() async {
    while (isEnabled) {
      final generation = _generation;
      final batch = await _withStorageLock(() async {
        final queue = _readValidQueue(_now().toUtc());
        final encodedQueue = queue.map((event) => event.encoded).toList();
        final storedQueue = _preferences.getStringList(queueStorageKey) ?? [];
        if (!_sameStrings(encodedQueue, storedQueue)) {
          await _writeQueue(encodedQueue);
        }
        return queue.take(batchSize).toList(growable: false);
      });
      if (batch.isEmpty || !isEnabled || generation != _generation) {
        return;
      }

      int statusCode;
      try {
        statusCode = await _postBatch(
          batch.map((event) => event.decoded).toList(growable: false),
        );
      } on Object {
        if (isEnabled && generation == _generation) {
          _scheduleRetry();
        }
        return;
      }
      if (!isEnabled || generation != _generation) {
        return;
      }

      if (_shouldRetry(statusCode)) {
        _scheduleRetry();
        return;
      }

      if ((statusCode >= 200 && statusCode < 300) ||
          (statusCode >= 400 && statusCode < 500)) {
        await _withStorageLock(() => _removeBatch(batch));
        _cancelRetry(resetAttempt: true);
        continue;
      }

      _scheduleRetry();
      return;
    }
  }

  Future<int> _postBatch(List<Map<String, Object?>> events) async {
    final client = _httpClientFactory();
    client.connectionTimeout = _requestTimeout;
    _activeHttpClient = client;
    try {
      final request = await client.postUrl(_endpoint).timeout(_requestTimeout);
      request
        ..followRedirects = true
        ..headers.set('App-Key', _appKey)
        ..headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=UTF-8',
        )
        ..headers.set(HttpHeaders.userAgentHeader, sdkVersion)
        ..add(utf8.encode(jsonEncode(events)));
      final response = await request.close().timeout(_requestTimeout);
      final statusCode = response.statusCode;
      await response.drain<void>().timeout(_requestTimeout);
      return statusCode;
    } finally {
      client.close(force: true);
      if (identical(_activeHttpClient, client)) {
        _activeHttpClient = null;
      }
    }
  }

  Future<void> _removeBatch(List<_StoredAnalyticsEvent> batch) async {
    final queue = _preferences.getStringList(queueStorageKey) ?? <String>[];
    for (final sentEvent in batch) {
      final index = queue.indexOf(sentEvent.encoded);
      if (index >= 0) {
        queue.removeAt(index);
      }
    }
    await _writeQueue(queue);
  }

  List<_StoredAnalyticsEvent> _readValidQueue(DateTime now) {
    final encodedEvents =
        _preferences.getStringList(queueStorageKey) ?? const <String>[];
    final valid = <_StoredAnalyticsEvent>[];
    for (final encoded in encodedEvents) {
      final event = _StoredAnalyticsEvent.tryParse(encoded, now);
      if (event != null) {
        valid.add(event);
      }
    }
    if (valid.length <= queueLimit) {
      return valid;
    }
    return valid.sublist(valid.length - queueLimit);
  }

  Future<void> _writeQueue(List<String> queue) async {
    if (queue.isEmpty) {
      await _preferences.remove(queueStorageKey);
    } else {
      await _preferences.setStringList(queueStorageKey, queue);
    }
  }

  Future<T> _withStorageLock<T>(Future<T> Function() action) {
    final previous = _storageTail;
    final completer = Completer<void>();
    _storageTail = completer.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        completer.complete();
      }
    }();
  }

  String _evaluateSessionId(DateTime now) {
    final lastActivity = _lastSessionActivity;
    if (_sessionId == null ||
        lastActivity == null ||
        now.difference(lastActivity) >= sessionTimeout) {
      final candidate = _sessionIdFactory();
      _sessionId = candidate.isNotEmpty && candidate.length <= 36
          ? candidate
          : _newSessionId();
    }
    _lastSessionActivity = now;
    return _sessionId!;
  }

  void _scheduleRetry() {
    if (!isEnabled || _retryTimer != null) {
      return;
    }
    final delay = retryDelays[min(_retryAttempt, retryDelays.length - 1)];
    _retryAttempt = min(_retryAttempt + 1, retryDelays.length - 1);
    _retryTimer = _retryTimerFactory(delay, () {
      _retryTimer = null;
      if (isEnabled) {
        unawaited(_startFlush(requestAnotherIfActive: false));
      }
    });
  }

  void _cancelRetry({required bool resetAttempt}) {
    _retryTimer?.cancel();
    _retryTimer = null;
    if (resetAttempt) {
      _retryAttempt = 0;
    }
  }

  void _abortActiveRequest() {
    _activeHttpClient?.close(force: true);
    _activeHttpClient = null;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _initialized = false;
    _generation++;
    _flushRequested = false;
    _cancelRetry(resetAttempt: false);
    _abortActiveRequest();
  }

  static Map<String, Object>? _validatedProperties(
    Map<String, Object> properties,
  ) {
    final result = <String, Object>{};
    for (final entry in properties.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!_allowedPropertyNames.contains(key) ||
          key.trim().isEmpty ||
          key.length > 40) {
        return null;
      }
      if (value is String) {
        if (value.length > 180) {
          return null;
        }
        result[key] = value;
      } else if (value is num) {
        if (value is double && !value.isFinite) {
          return null;
        }
        result[key] = value;
      } else {
        return null;
      }
    }
    return result;
  }

  static bool _shouldRetry(int statusCode) =>
      statusCode == 408 || statusCode == 429 || statusCode >= 500;
}

class _StoredAnalyticsEvent {
  const _StoredAnalyticsEvent({required this.encoded, required this.decoded});

  final String encoded;
  final Map<String, Object?> decoded;

  static _StoredAnalyticsEvent? tryParse(String encoded, DateTime now) {
    try {
      final value = jsonDecode(encoded);
      if (value is! Map<String, dynamic>) {
        return null;
      }
      final timestampValue = value['timestamp'];
      final sessionId = value['sessionId'];
      final eventName = value['eventName'];
      final systemProps = value['systemProps'];
      final props = value['props'];
      if (timestampValue is! String ||
          sessionId is! String ||
          sessionId.isEmpty ||
          sessionId.length > 36 ||
          eventName is! String ||
          !AptabaseAnalyticsService._allowedEventNames.contains(eventName) ||
          systemProps is! Map<String, dynamic> ||
          props is! Map<String, dynamic>) {
        return null;
      }
      final timestamp = DateTime.tryParse(timestampValue)?.toUtc();
      if (timestamp == null ||
          now.difference(timestamp) >= AptabaseAnalyticsService.eventTtl ||
          timestamp.isAfter(now.add(const Duration(minutes: 10)))) {
        return null;
      }
      final validatedProperties = AptabaseAnalyticsService._validatedProperties(
        Map<String, Object>.from(props),
      );
      if (!_validSystemProps(systemProps) || validatedProperties == null) {
        return null;
      }
      return _StoredAnalyticsEvent(
        encoded: encoded,
        decoded: <String, Object?>{
          'timestamp': timestampValue,
          'sessionId': sessionId,
          'eventName': eventName,
          'systemProps': Map<String, Object>.from(systemProps),
          'props': validatedProperties,
        },
      );
    } on Object {
      return null;
    }
  }

  static bool _validSystemProps(Map<String, dynamic> props) {
    const allowedKeys = <String>{
      'isDebug',
      'osName',
      'osVersion',
      'locale',
      'appVersion',
      'appBuildNumber',
      'sdkVersion',
    };
    if (props.length != allowedKeys.length ||
        props.keys.any((key) => !allowedKeys.contains(key))) {
      return false;
    }
    final isDebug = props['isDebug'];
    final osName = props['osName'];
    final osVersion = props['osVersion'];
    final locale = props['locale'];
    final appVersion = props['appVersion'];
    final appBuildNumber = props['appBuildNumber'];
    final sdk = props['sdkVersion'];
    return isDebug == false &&
        osName is String &&
        osName.length <= 30 &&
        osVersion is String &&
        osVersion.length <= 100 &&
        locale is String &&
        locale.length <= 10 &&
        appVersion is String &&
        appVersion.length <= 50 &&
        appBuildNumber is String &&
        appBuildNumber.length <= 20 &&
        sdk == AptabaseAnalyticsService.sdkVersion;
  }
}

DateTime _utcNow() => DateTime.now().toUtc();

String _newSessionId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
}

String _platformOSName() {
  if (Platform.isMacOS) {
    return 'macOS';
  }
  if (Platform.isWindows) {
    return 'Windows';
  }
  if (Platform.isLinux) {
    return 'Linux';
  }
  if (Platform.isAndroid) {
    return 'Android';
  }
  if (Platform.isIOS) {
    return 'iOS';
  }
  return _limited(Platform.operatingSystem, 30);
}

String _normalizedLocale(String locale) {
  final withoutEncoding = locale.split('.').first.split('@').first;
  return withoutEncoding.replaceAll('_', '-');
}

String _limited(String value, int maximumLength) =>
    value.length <= maximumLength ? value : value.substring(0, maximumLength);

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}
