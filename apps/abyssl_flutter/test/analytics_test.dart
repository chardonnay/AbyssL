import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:abyssl_flutter/src/analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  group('provider classification', () {
    test('recognizes official OpenAI and Anthropic hosts', () {
      expect(
        classifyAnalyticsProvider(
          Uri.parse('https://api.openai.com/v1'),
          AnalyticsProviderFamily.openAICompatible,
        ),
        AnalyticsProvider.openAI,
      );
      expect(
        classifyAnalyticsProvider(
          Uri.parse('https://api.anthropic.com/v1/messages'),
          AnalyticsProviderFamily.anthropicCompatible,
        ),
        AnalyticsProvider.anthropic,
      );
    });

    test('recognizes local provider ports and safe fallbacks', () {
      expect(
        classifyAnalyticsProvider(
          Uri.parse('http://localhost:11434/v1'),
          AnalyticsProviderFamily.localCompatible,
        ),
        AnalyticsProvider.ollama,
      );
      expect(
        classifyAnalyticsProvider(
          Uri.parse('http://127.0.0.1:1234/v1'),
          AnalyticsProviderFamily.localCompatible,
        ),
        AnalyticsProvider.lmStudio,
      );
      expect(
        classifyAnalyticsProvider(
          Uri.parse('https://gateway.example/v1'),
          AnalyticsProviderFamily.openAICompatible,
        ),
        AnalyticsProvider.openAICompatibleOther,
      );
      expect(
        classifyAnalyticsProvider(
          Uri.parse('https://gateway.example/anthropic'),
          AnalyticsProviderFamily.anthropicCompatible,
        ),
        AnalyticsProvider.anthropicCompatibleOther,
      );
      expect(
        classifyAnalyticsProvider(
          Uri.parse('http://192.168.1.10:8080/v1'),
          AnalyticsProviderFamily.localCompatible,
        ),
        AnalyticsProvider.localCompatibleOther,
      );
    });
  });

  group('consent and release gating', () {
    test('does not inspect the system or queue before consent', () async {
      final preferences = await _preferences();
      var systemLoads = 0;
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        systemInfoLoader: () async {
          systemLoads++;
          return _systemInfo;
        },
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.undecided);
      await service.trackEvent('app_started', const {'analytics_schema': 1});

      expect(systemLoads, 0);
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });

    test('debug and profile builds never inspect, queue, or send', () async {
      final preferences = await _preferences();
      var systemLoads = 0;
      var clientCreations = 0;
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: false,
        systemInfoLoader: () async {
          systemLoads++;
          return _systemInfo;
        },
        httpClientFactory: () {
          clientCreations++;
          return HttpClient();
        },
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.granted);
      await service.trackEvent('app_started', const {'analytics_schema': 1});
      await service.flush();

      expect(systemLoads, 0);
      expect(clientCreations, 0);
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });

    test('rejects unknown, sensitive, or unsupported properties', () async {
      final preferences = await _preferences();
      var systemLoads = 0;
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        systemInfoLoader: () async {
          systemLoads++;
          return _systemInfo;
        },
      );
      addTearDown(service.dispose);
      await service.initialize(AnalyticsConsent.granted);

      await service.trackEvent('feature_completed', const {
        'prompt': 'must never leave the app',
      });
      await service.trackEvent('feature_completed', const {
        'style_changed': true,
      });
      await service.trackEvent('custom_event');
      await service.trackEvent('setting_changed', {
        'from': List<String>.filled(181, 'x').join(),
      });

      expect(systemLoads, 0);
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });
  });

  group('REST transport and queue', () {
    test('uses the EU endpoint and supplied client key by default', () {
      expect(
        AptabaseAnalyticsService.defaultEndpoint,
        'https://eu.aptabase.com/api/v0/events',
      );
      expect(AptabaseAnalyticsService.defaultAppKey, 'A-EU-5362022623');
    });

    test('sends a valid Aptabase payload with anonymous system data', () async {
      final server = await _AnalyticsServer.start();
      addTearDown(server.close);
      final preferences = await _preferences();
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        systemInfoLoader: () async => _systemInfo,
        sessionIdFactory: () => 'session-without-device-id',
      );
      addTearDown(service.dispose);
      await service.initialize(AnalyticsConsent.granted);

      await service.trackAppStarted(
        appLanguageSetting: 'system',
        appLanguageResolved: 'de',
        defaultProvider: AnalyticsProvider.openAI,
      );
      await service.flush();

      expect(server.requests, hasLength(1));
      final request = server.requests.single;
      expect(request.headers.value('app-key'), 'A-EU-5362022623');
      expect(request.headers.contentType?.mimeType, ContentType.json.mimeType);
      final events = jsonDecode(request.body) as List<dynamic>;
      expect(events, hasLength(1));
      final event = events.single as Map<String, dynamic>;
      expect(event['eventName'], 'app_started');
      expect(event['sessionId'], 'session-without-device-id');
      expect((event['sessionId'] as String).length, lessThanOrEqualTo(36));
      expect(event['props'], {
        'app_language_setting': 'system',
        'app_language_resolved': 'de',
        'default_provider': 'openai',
        'analytics_schema': 1,
      });
      expect(event['systemProps'], {
        'isDebug': false,
        'osName': 'TestOS',
        'osVersion': '1.2.3',
        'locale': 'de-DE',
        'appVersion': '2.4.6',
        'appBuildNumber': '42',
        'sdkVersion': 'abyssl-rest@1',
      });
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });

    test('batches at most 25 events and serializes requests', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final queued = List<String>.generate(
        30,
        (index) => _encodedEvent(now, index),
      );
      final preferences = await _preferences({
        AptabaseAnalyticsService.queueStorageKey: queued,
      });
      final server = await _AnalyticsServer.start();
      addTearDown(server.close);
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        now: () => now,
        systemInfoLoader: () async => _systemInfo,
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.granted);
      await service.flush();

      expect(server.maximumConcurrentRequests, 1);
      expect(server.requests, hasLength(2));
      expect(jsonDecode(server.requests[0].body), hasLength(25));
      expect(jsonDecode(server.requests[1].body), hasLength(5));
    });

    test('keeps events offline and sends them after a restart', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final preferences = await _preferences();
      final offlineServer = await _AnalyticsServer.start(statusCodes: [503]);
      addTearDown(offlineServer.close);
      final timers = _RetryTimerRecorder();
      final firstService = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: offlineServer.endpoint,
        now: () => now,
        systemInfoLoader: () async => _systemInfo,
        retryTimerFactory: timers.create,
      );
      await firstService.initialize(AnalyticsConsent.granted);
      await firstService.trackEvent('feature_completed', const {
        'feature': 'translation',
        'operation': 'translate',
        'trigger': 'manual',
        'provider': 'openai',
        'duration_ms': 123,
      });
      await firstService.flush();

      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        hasLength(1),
      );
      await firstService.dispose();

      final onlineServer = await _AnalyticsServer.start();
      addTearDown(onlineServer.close);
      final secondService = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: onlineServer.endpoint,
        now: () => now.add(const Duration(minutes: 2)),
        systemInfoLoader: () async => _systemInfo,
      );
      addTearDown(secondService.dispose);
      await secondService.initialize(AnalyticsConsent.granted);
      await secondService.flush();

      expect(onlineServer.requests, hasLength(1));
      final sent = jsonDecode(onlineServer.requests.single.body) as List;
      expect(
        (sent.single as Map<String, dynamic>)['timestamp'],
        now.toIso8601String(),
      );
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });

    test(
      'retains the queue when the network connection cannot be opened',
      () async {
        final now = DateTime.utc(2026, 7, 19, 12);
        final closedServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final unavailableEndpoint = Uri.parse(
          'http://${closedServer.address.address}:${closedServer.port}/api/v0/events',
        );
        await closedServer.close(force: true);
        final preferences = await _preferences();
        final timers = _RetryTimerRecorder();
        final service = AptabaseAnalyticsService(
          preferences: preferences,
          isReleaseBuild: true,
          endpoint: unavailableEndpoint,
          now: () => now,
          systemInfoLoader: () async => _systemInfo,
          retryTimerFactory: timers.create,
        );
        addTearDown(service.dispose);
        await service.initialize(AnalyticsConsent.granted);

        await service.trackEvent('feature_completed', const {
          'feature': 'translation',
          'operation': 'translate',
          'trigger': 'manual',
          'provider': 'openai',
          'duration_ms': 123,
        });
        await service.flush();

        expect(timers.durations, [const Duration(seconds: 15)]);
        expect(
          preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
          hasLength(1),
        );
      },
    );

    test('uses 15 second, 1 minute, then 5 minute retry backoff', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final preferences = await _preferences({
        AptabaseAnalyticsService.queueStorageKey: [_encodedEvent(now, 1)],
      });
      final server = await _AnalyticsServer.start(
        statusCodes: [500, 408, 429, 200],
      );
      addTearDown(server.close);
      final timers = _RetryTimerRecorder();
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        now: () => now,
        retryTimerFactory: timers.create,
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.granted);
      await service.flush();
      expect(timers.durations, [const Duration(seconds: 15)]);

      timers.fireLatest();
      await service.flush();
      expect(timers.durations, [
        const Duration(seconds: 15),
        const Duration(minutes: 1),
      ]);

      timers.fireLatest();
      await service.flush();
      expect(timers.durations, [
        const Duration(seconds: 15),
        const Duration(minutes: 1),
        const Duration(minutes: 5),
      ]);

      timers.fireLatest();
      await service.flush();
      expect(server.requests, hasLength(4));
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });

    test('discards permanent 4xx responses', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final preferences = await _preferences({
        AptabaseAnalyticsService.queueStorageKey: [_encodedEvent(now, 1)],
      });
      final server = await _AnalyticsServer.start(statusCodes: [400]);
      addTearDown(server.close);
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        now: () => now,
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.granted);
      await service.flush();

      expect(server.requests, hasLength(1));
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });

    test(
      'sanitizes restored events and rejects unknown system fields',
      () async {
        final now = DateTime.utc(2026, 7, 19, 12);
        final topLevelExtra =
            jsonDecode(_encodedEvent(now, 1)) as Map<String, dynamic>
              ..['userId'] = 'must-not-be-sent';
        final systemExtra =
            jsonDecode(_encodedEvent(now, 2)) as Map<String, dynamic>;
        (systemExtra['systemProps'] as Map<String, dynamic>)['deviceId'] =
            'must-not-be-sent';
        final preferences = await _preferences({
          AptabaseAnalyticsService.queueStorageKey: [
            jsonEncode(topLevelExtra),
            jsonEncode(systemExtra),
          ],
        });
        final server = await _AnalyticsServer.start();
        addTearDown(server.close);
        final service = AptabaseAnalyticsService(
          preferences: preferences,
          isReleaseBuild: true,
          endpoint: server.endpoint,
          now: () => now,
        );
        addTearDown(service.dispose);

        await service.initialize(AnalyticsConsent.granted);
        await service.flush();

        final sent = jsonDecode(server.requests.single.body) as List<dynamic>;
        expect(sent, hasLength(1));
        final event = sent.single as Map<String, dynamic>;
        expect(event, isNot(contains('userId')));
        expect(
          event['systemProps'] as Map<String, dynamic>,
          isNot(contains('deviceId')),
        );
        expect(
          preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
          isNull,
        );
      },
    );

    test('caps the queue at 500 and drops the oldest event first', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final queued = List<String>.generate(
        501,
        (index) => _encodedEvent(now, index),
      );
      final preferences = await _preferences({
        AptabaseAnalyticsService.queueStorageKey: queued,
      });
      final server = await _AnalyticsServer.start(statusCodes: [503]);
      addTearDown(server.close);
      final timers = _RetryTimerRecorder();
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        now: () => now,
        retryTimerFactory: timers.create,
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.granted);
      await service.flush();

      final retained = preferences.getStringList(
        AptabaseAnalyticsService.queueStorageKey,
      );
      expect(retained, hasLength(500));
      expect(
        (jsonDecode(retained!.first)['props']
            as Map<String, dynamic>)['duration_ms'],
        1,
      );
    });

    test('drops events just before the Aptabase 24 hour limit', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final preferences = await _preferences({
        AptabaseAnalyticsService.queueStorageKey: [
          _encodedEvent(
            now.subtract(const Duration(hours: 23, minutes: 54, seconds: 59)),
            0,
          ),
          _encodedEvent(now.subtract(AptabaseAnalyticsService.eventTtl), 1),
          _encodedEvent(now.subtract(const Duration(hours: 2)), 2),
        ],
      });
      final server = await _AnalyticsServer.start();
      addTearDown(server.close);
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        now: () => now,
      );
      addTearDown(service.dispose);

      await service.initialize(AnalyticsConsent.granted);
      await service.flush();

      expect(server.requests, hasLength(1));
      final sent = jsonDecode(server.requests.single.body) as List<dynamic>;
      expect(sent, hasLength(2));
      expect(
        sent
            .map(
              (event) =>
                  (event['props'] as Map<String, dynamic>)['duration_ms'],
            )
            .toList(),
        [0, 2],
      );
    });

    test(
      'rotates the anonymous session after one hour of inactivity',
      () async {
        var now = DateTime.utc(2026, 7, 19, 12);
        var sessionIndex = 0;
        final server = await _AnalyticsServer.start();
        addTearDown(server.close);
        final preferences = await _preferences();
        final service = AptabaseAnalyticsService(
          preferences: preferences,
          isReleaseBuild: true,
          endpoint: server.endpoint,
          now: () => now,
          systemInfoLoader: () async => _systemInfo,
          sessionIdFactory: () => 'session-${sessionIndex++}',
        );
        addTearDown(service.dispose);
        await service.initialize(AnalyticsConsent.granted);

        await service.trackEvent('setting_changed', const {
          'setting': 'app_language',
          'from': 'system',
          'to': 'german',
        });
        await service.flush();
        now = now.add(const Duration(minutes: 30));
        await service.trackEvent('setting_changed', const {
          'setting': 'app_language',
          'from': 'german',
          'to': 'english',
        });
        await service.flush();
        now = now.add(const Duration(hours: 1));
        await service.trackEvent('setting_changed', const {
          'setting': 'app_language',
          'from': 'english',
          'to': 'system',
        });
        await service.flush();

        final sessions = server.requests
            .expand((request) => jsonDecode(request.body) as List<dynamic>)
            .map((event) => event['sessionId'])
            .toList();
        expect(sessions, ['session-0', 'session-0', 'session-1']);
      },
    );

    test('revoking consent clears queued events and cancels retries', () async {
      final now = DateTime.utc(2026, 7, 19, 12);
      final preferences = await _preferences({
        AptabaseAnalyticsService.queueStorageKey: [_encodedEvent(now, 1)],
      });
      final server = await _AnalyticsServer.start(statusCodes: [503]);
      addTearDown(server.close);
      final timers = _RetryTimerRecorder();
      final service = AptabaseAnalyticsService(
        preferences: preferences,
        isReleaseBuild: true,
        endpoint: server.endpoint,
        now: () => now,
        retryTimerFactory: timers.create,
      );
      addTearDown(service.dispose);
      await service.initialize(AnalyticsConsent.granted);
      await service.flush();
      expect(timers.latest.isActive, isTrue);

      await service.setConsent(AnalyticsConsent.denied);

      expect(timers.latest.isActive, isFalse);
      expect(
        preferences.getStringList(AptabaseAnalyticsService.queueStorageKey),
        isNull,
      );
    });
  });
}

const _systemInfo = AnalyticsSystemInfo(
  osName: 'TestOS',
  osVersion: '1.2.3',
  locale: 'de_DE',
  appVersion: '2.4.6',
  appBuildNumber: '42',
);

Future<SharedPreferencesWithCache> _preferences([
  Map<String, Object> initialValues = const {},
]) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(initialValues);
  SharedPreferences.setMockInitialValues(initialValues);
  return SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
}

String _encodedEvent(DateTime timestamp, int duration) => jsonEncode({
  'timestamp': timestamp.toUtc().toIso8601String(),
  'sessionId': 'anonymous-session',
  'eventName': 'feature_completed',
  'systemProps': {
    'isDebug': false,
    'osName': 'TestOS',
    'osVersion': '1.2.3',
    'locale': 'de-DE',
    'appVersion': '2.4.6',
    'appBuildNumber': '42',
    'sdkVersion': 'abyssl-rest@1',
  },
  'props': {
    'feature': 'translation',
    'operation': 'translate',
    'trigger': 'manual',
    'provider': 'openai',
    'duration_ms': duration,
  },
});

class _RecordedRequest {
  const _RecordedRequest({required this.headers, required this.body});

  final HttpHeaders headers;
  final String body;
}

class _AnalyticsServer {
  _AnalyticsServer._(this._server, this._statusCodes) {
    _server.listen(_handleRequest);
  }

  final HttpServer _server;
  final List<int> _statusCodes;
  final List<_RecordedRequest> requests = [];
  var _activeRequests = 0;
  var maximumConcurrentRequests = 0;

  Uri get endpoint => Uri.parse(
    'http://${_server.address.address}:${_server.port}/api/v0/events',
  );

  static Future<_AnalyticsServer> start({
    List<int> statusCodes = const [],
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _AnalyticsServer._(server, List<int>.of(statusCodes));
  }

  Future<void> _handleRequest(HttpRequest request) async {
    _activeRequests++;
    maximumConcurrentRequests = _activeRequests > maximumConcurrentRequests
        ? _activeRequests
        : maximumConcurrentRequests;
    try {
      final body = await utf8.decoder.bind(request).join();
      requests.add(_RecordedRequest(headers: request.headers, body: body));
      request.response.statusCode = _statusCodes.isEmpty
          ? HttpStatus.ok
          : _statusCodes.removeAt(0);
      await request.response.close();
    } finally {
      _activeRequests--;
    }
  }

  Future<void> close() => _server.close(force: true);
}

class _RetryTimerRecorder {
  final List<Duration> durations = [];
  final List<_FakeTimer> timers = [];

  _FakeTimer get latest => timers.last;

  Timer create(Duration duration, void Function() callback) {
    durations.add(duration);
    final timer = _FakeTimer(callback);
    timers.add(timer);
    return timer;
  }

  void fireLatest() => latest.fire();
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool _isActive = true;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _isActive ? 0 : 1;

  @override
  void cancel() => _isActive = false;

  void fire() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _callback();
  }
}
