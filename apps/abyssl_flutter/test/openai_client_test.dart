import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:abyssl_flutter/src/models.dart';
import 'package:abyssl_flutter/src/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses structured translation JSON with snake case fields', () {
    final result = AbyssLApiClient.parseTranslationJson(
      jsonEncode({
        'translation': 'Hallo',
        'synonyms': ['Guten Tag', 'Hallo', 'Hallo'],
        'spelling_notes': 'Fixed typo',
        'revised_source': 'Hello',
      }),
    );

    expect(result.translation, 'Hallo');
    expect(result.synonyms, ['Guten Tag', 'Hallo']);
    expect(result.spellingNotes, 'Fixed typo');
    expect(result.revisedSource, 'Hello');
  });

  test('preserves source paragraph breaks when translation is merged', () {
    final formatted = AbyssLApiClient.preserveSourceParagraphs(
      source:
          'First paragraph has one sentence.\n\nSecond paragraph also has one sentence.',
      translation:
          'Erster Absatz hat einen Satz. Zweiter Absatz hat ebenfalls einen Satz.',
    );

    expect(
      formatted,
      'Erster Absatz hat einen Satz.\n\nZweiter Absatz hat ebenfalls einen Satz.',
    );
  });

  test('parses correction JSON and locates corrected spans', () {
    final result = AbyssLApiClient.parseWritingCorrectionJson(
      jsonEncode({
        'corrected_text': 'This is correct.',
        'corrections': [
          {
            'original': 'corect',
            'corrected': 'correct',
            'reason': 'Spelling',
            'alternatives': ['accurate', 'right', 'correct'],
          },
        ],
      }),
      fallbackText: 'This is corect.',
      alternativeLimit: 3,
    );

    expect(result.correctedText, 'This is correct.');
    expect(result.issues, hasLength(1));
    expect(result.issues.single.start, 8);
    expect(result.issues.single.originalStart, 8);
    expect(result.issues.single.originalLength, 6);
    expect(result.issues.single.correctedStart, 8);
    expect(result.issues.single.correctedLength, 7);
    expect(result.issues.single.alternatives, ['accurate', 'right']);
  });

  test('sends OpenAI-compatible chat contract and bearer auth', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, Object?>? receivedBody;
    String? authorization;
    Uri? receivedUri;
    unawaited(
      server.forEach((request) async {
        receivedUri = request.uri;
        authorization = request.headers.value(HttpHeaders.authorizationHeader);
        receivedBody = _jsonObject(await utf8.decoder.bind(request).join());
        _writeJson(
          request.response,
          _openAIResponse(_translationJson('Hallo')),
        );
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final result = await client.translate(
      text: 'Hello',
      instruction: 'Keep it concise',
      config: _config(
        TranslationProvider.openAICompatible,
        _serverUri(server),
        apiKey: 'openai-secret',
      ),
    );

    expect(result.translation, 'Hallo');
    expect(receivedUri?.path, '/v1/chat/completions');
    expect(authorization, 'Bearer openai-secret');
    expect(receivedBody?['model'], 'gpt-test');
    expect(receivedBody?['temperature'], 0.2);
    expect(receivedBody?['response_format'], {'type': 'json_object'});
    final messages = receivedBody?['messages'] as List<Object?>;
    expect(messages, hasLength(2));
    expect(_jsonMap(messages.first)['role'], 'system');
    expect(_jsonMap(messages.last)['content'], contains('Keep it concise'));
  });

  test('sends Anthropic Messages contract and x-api-key auth', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, Object?>? receivedBody;
    String? apiKey;
    String? version;
    Uri? receivedUri;
    unawaited(
      server.forEach((request) async {
        receivedUri = request.uri;
        apiKey = request.headers.value('x-api-key');
        version = request.headers.value('anthropic-version');
        receivedBody = _jsonObject(await utf8.decoder.bind(request).join());
        _writeJson(
          request.response,
          _anthropicResponse(_translationJson('Bonjour')),
        );
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final result = await client.translate(
      text: 'Hello',
      instruction: '',
      config: _config(
        TranslationProvider.anthropicCompatible,
        _serverUri(server),
        apiKey: 'anthropic-secret',
        maxOutputTokens: 2048,
      ),
    );

    expect(result.translation, 'Bonjour');
    expect(receivedUri?.path, '/v1/messages');
    expect(apiKey, 'anthropic-secret');
    expect(version, '2023-06-01');
    expect(receivedBody?['model'], 'claude-test');
    expect(receivedBody?['max_tokens'], 2048);
    expect(receivedBody?['system'], contains('professional translator'));
    final messages = receivedBody?['messages'] as List<Object?>;
    expect(messages, hasLength(1));
    expect(_jsonMap(messages.single)['role'], 'user');
    final outputConfig = _jsonMap(receivedBody?['output_config']);
    final format = _jsonMap(outputConfig['format']);
    expect(format['type'], 'json_schema');
    expect(_jsonMap(format['schema'])['required'], contains('translation'));
  });

  test(
    'sends the default Anthropic version for a blank active value',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      String? version;
      unawaited(
        server.forEach((request) async {
          version = request.headers.value('anthropic-version');
          await utf8.decoder.bind(request).join();
          _writeJson(
            request.response,
            _anthropicResponse(_translationJson('Bonjour')),
          );
          await request.response.close();
        }),
      );

      await AbyssLApiClient().translate(
        text: 'Hello',
        instruction: '',
        config: _config(
          TranslationProvider.anthropicCompatible,
          _serverUri(server),
          apiKey: 'anthropic-secret',
          anthropicVersion: '  ',
        ),
      );

      expect(version, defaultAnthropicApiVersion);
    },
  );

  test('merges every Anthropic text content block', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        await utf8.decoder.bind(request).join();
        _writeJson(request.response, {
          'content': [
            {'type': 'thinking', 'thinking': 'not returned'},
            {'type': 'text', 'text': '{"translation":"Hallo",'},
            {'type': 'text', 'text': '"synonyms":["Guten Tag"],'},
            {
              'type': 'text',
              'text': '"spelling_notes":null,"revised_source":null}',
            },
          ],
          'stop_reason': 'end_turn',
        });
        await request.response.close();
      }),
    );

    final result = await AbyssLApiClient().translate(
      text: 'Hello',
      instruction: '',
      config: _config(
        TranslationProvider.anthropicCompatible,
        _serverUri(server),
        apiKey: 'secret',
      ),
    );

    expect(result.translation, 'Hallo');
    expect(result.synonyms, ['Guten Tag']);
  });

  test('applies every auth mode to actual provider chat requests', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final received = <Map<String, String?>>[];
    unawaited(
      server.forEach((request) async {
        await utf8.decoder.bind(request).join();
        final isAnthropic = request.uri.path.endsWith('/messages');
        received.add({
          'path': request.uri.path,
          'authorization': request.headers.value(
            HttpHeaders.authorizationHeader,
          ),
          'x-api-key': request.headers.value('x-api-key'),
          'anthropic-version': request.headers.value('anthropic-version'),
        });
        _writeJson(
          request.response,
          isAnthropic
              ? _anthropicResponse(_translationJson('Hallo'))
              : _openAIResponse(_translationJson('Hallo')),
        );
        await request.response.close();
      }),
    );

    for (final provider in [
      TranslationProvider.openAICompatible,
      TranslationProvider.anthropicCompatible,
    ]) {
      for (final authMode in ApiAuthMode.values) {
        final result = await AbyssLApiClient().translate(
          text: 'Hello',
          instruction: '',
          config: _config(
            provider,
            _serverUri(server),
            authMode: authMode,
            apiKey: 'secret',
          ),
        );
        expect(result.translation, 'Hallo');

        final request = received.last;
        expect(
          request['path'],
          provider == TranslationProvider.anthropicCompatible
              ? '/v1/messages'
              : '/v1/chat/completions',
        );
        expect(
          request['authorization'],
          authMode == ApiAuthMode.bearer ? 'Bearer secret' : isNull,
        );
        expect(
          request['x-api-key'],
          authMode == ApiAuthMode.xApiKey ? 'secret' : isNull,
        );
        expect(
          request['anthropic-version'],
          provider == TranslationProvider.anthropicCompatible
              ? '2023-06-01'
              : isNull,
        );
      }
    }

    expect(received, hasLength(6));
  });

  for (final provider in [
    TranslationProvider.openAICompatible,
    TranslationProvider.anthropicCompatible,
  ]) {
    test('${provider.name} supports every domain operation', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final schemas = <String>[];
      unawaited(
        server.forEach((request) async {
          final body = _jsonObject(await utf8.decoder.bind(request).join());
          final system = provider.compatibility == ApiCompatibility.openAI
              ? '${_jsonMap((body['messages'] as List).first)['content']}'
              : '${body['system']}';
          String content;
          if (system.contains('translation editor')) {
            schemas.add('alternatives');
            content = jsonEncode({
              'alternatives': ['Hi', 'Good day', 'Greetings'],
            });
          } else if (system.contains('copy editor')) {
            schemas.add('correction');
            content = jsonEncode({
              'corrected_text': 'This is correct.',
              'corrections': <Object?>[],
            });
          } else if (system.contains('writing editor')) {
            schemas.add('rewrite');
            content = jsonEncode({'rewritten_text': 'A shorter sentence.'});
          } else {
            schemas.add('translation');
            content = _translationJson('Hallo');
          }
          _writeJson(
            request.response,
            provider.compatibility == ApiCompatibility.openAI
                ? _openAIResponse(content)
                : _anthropicResponse(content),
          );
          await request.response.close();
        }),
      );

      final client = AbyssLApiClient();
      final config = _config(provider, _serverUri(server), apiKey: 'secret');
      expect(
        (await client.translate(
          text: 'Hello',
          instruction: '',
          config: config,
        )).translation,
        'Hallo',
      );
      expect(
        await client.suggestAlternatives(
          selectedText: 'Hello',
          targetContext: 'Hello world',
          userInstruction: '',
          count: 3,
          config: config,
        ),
        ['Hi', 'Good day', 'Greetings'],
      );
      expect(
        (await client.correctWriting(
          text: 'This is corect.',
          instruction: '',
          config: config,
        )).correctedText,
        'This is correct.',
      );
      expect(
        await client.rewriteWriting(
          text: 'This is a much longer sentence.',
          instruction: '',
          stylePreset: WritingStylePreset.concise,
          config: config,
        ),
        'A shorter sentence.',
      );
      expect(schemas, ['translation', 'alternatives', 'correction', 'rewrite']);
    });
  }

  test(
    'lists Anthropic-compatible models with versioned auth headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final versions = <String?>[];
      unawaited(
        server.forEach((request) async {
          paths.add(request.uri.path);
          versions.add(request.headers.value('anthropic-version'));
          expect(request.headers.value('x-api-key'), 'secret');
          _writeJson(request.response, {
            'data': [
              {'id': 'claude-z'},
              {'id': 'claude-a'},
            ],
          });
          await request.response.close();
        }),
      );

      final client = AbyssLApiClient();
      final models = await client.fetchModelCatalog(
        provider: TranslationProvider.anthropicCompatible,
        baseUri: _serverUri(server),
        apiKey: 'secret',
      );
      await client.testConnection(
        provider: TranslationProvider.anthropicCompatible,
        baseUri: _serverUri(server),
        apiKey: 'secret',
      );

      expect(models.map((model) => model.id), ['claude-a', 'claude-z']);
      expect(paths, ['/v1/models', '/v1/models']);
      expect(versions, everyElement('2023-06-01'));
    },
  );

  test(
    'connection test validates the configured model when provided',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      Uri? receivedUri;
      Map<String, Object?>? receivedBody;
      unawaited(
        server.forEach((request) async {
          receivedUri = request.uri;
          receivedBody = _jsonObject(await utf8.decoder.bind(request).join());
          _writeJson(request.response, _anthropicResponse('{"ok":true}'));
          await request.response.close();
        }),
      );

      await AbyssLApiClient().testConnection(
        provider: TranslationProvider.anthropicCompatible,
        baseUri: _serverUri(server),
        apiKey: 'secret',
        modelId: 'claude-configured',
        maxOutputTokens: 32,
      );

      expect(receivedUri?.path, '/v1/messages');
      expect(receivedBody?['model'], 'claude-configured');
      expect(receivedBody?['max_tokens'], 32);
      expect(receivedBody?['messages'], hasLength(1));
    },
  );

  for (final statusCode in [400, 422]) {
    test(
      'Anthropic retries once without unknown output_config after $statusCode',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final bodies = <Map<String, Object?>>[];
        unawaited(
          server.forEach((request) async {
            bodies.add(_jsonObject(await utf8.decoder.bind(request).join()));
            if (bodies.length == 1) {
              request.response.statusCode = statusCode;
              _writeJson(request.response, {
                'error': {'message': 'Unknown field: output_config.format'},
              });
            } else {
              _writeJson(
                request.response,
                _anthropicResponse(_translationJson('Hallo')),
              );
            }
            await request.response.close();
          }),
        );

        final result = await AbyssLApiClient().translate(
          text: 'Hello',
          instruction: '',
          config: _config(
            TranslationProvider.anthropicCompatible,
            _serverUri(server),
            apiKey: 'secret',
          ),
        );

        expect(result.translation, 'Hallo');
        expect(bodies, hasLength(2));
        expect(bodies.first, contains('output_config'));
        expect(bodies.last, isNot(contains('output_config')));
      },
    );
  }

  test('OpenAI retries once only for named unknown optional fields', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final bodies = <Map<String, Object?>>[];
    unawaited(
      server.forEach((request) async {
        bodies.add(_jsonObject(await utf8.decoder.bind(request).join()));
        if (bodies.length == 1) {
          request.response.statusCode = 422;
          _writeJson(request.response, {
            'error': {
              'message':
                  'Unknown parameters: response_format, reasoning_effort',
            },
          });
        } else {
          _writeJson(
            request.response,
            _openAIResponse(_translationJson('Hallo')),
          );
        }
        await request.response.close();
      }),
    );

    final result = await AbyssLApiClient().translate(
      text: 'Hello',
      instruction: '',
      config: _config(
        TranslationProvider.localOpenAICompatible,
        _serverUri(server),
        authMode: ApiAuthMode.none,
        reasoningEnabled: true,
        reasoningEffort: 'on',
      ),
    );

    expect(result.translation, 'Hallo');
    expect(bodies, hasLength(2));
    expect(bodies.first, contains('response_format'));
    expect(bodies.first, contains('reasoning_effort'));
    expect(bodies.last, isNot(contains('response_format')));
    expect(bodies.last, isNot(contains('reasoning_effort')));
  });

  for (final provider in [
    TranslationProvider.openAICompatible,
    TranslationProvider.anthropicCompatible,
  ]) {
    for (final statusCode in [401, 429, 500]) {
      test('${provider.name} never retries HTTP $statusCode', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        var requestCount = 0;
        unawaited(
          server.forEach((request) async {
            requestCount++;
            await utf8.decoder.bind(request).join();
            request.response.statusCode = statusCode;
            _writeJson(request.response, {
              'error': {'message': 'Unknown response_format'},
            });
            await request.response.close();
          }),
        );

        final future = AbyssLApiClient().translate(
          text: 'Hello',
          instruction: '',
          config: _config(provider, _serverUri(server), apiKey: 'secret'),
        );
        await expectLater(
          future,
          throwsA(
            isA<AbyssLApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              statusCode,
            ),
          ),
        );
        expect(requestCount, 1);
      });
    }
  }

  test('OpenAI does not retry an unrelated HTTP 400 error', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requestCount = 0;
    unawaited(
      server.forEach((request) async {
        requestCount++;
        await utf8.decoder.bind(request).join();
        request.response.statusCode = 400;
        _writeJson(request.response, {
          'error': {'message': 'Invalid model identifier'},
        });
        await request.response.close();
      }),
    );

    await expectLater(
      AbyssLApiClient().translate(
        text: 'Hello',
        instruction: '',
        config: _config(
          TranslationProvider.openAICompatible,
          _serverUri(server),
          apiKey: 'secret',
        ),
      ),
      throwsA(isA<AbyssLApiException>()),
    );
    expect(requestCount, 1);
  });

  test('reports Anthropic max_tokens stop reason', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        await utf8.decoder.bind(request).join();
        _writeJson(request.response, {
          'content': <Object?>[],
          'stop_reason': 'max_tokens',
        });
        await request.response.close();
      }),
    );

    await expectLater(
      AbyssLApiClient().translate(
        text: 'Hello',
        instruction: '',
        config: _config(
          TranslationProvider.anthropicCompatible,
          _serverUri(server),
          apiKey: 'secret',
        ),
      ),
      throwsA(
        isA<AbyssLApiException>().having(
          (error) => error.message,
          'message',
          contains('maximum output token'),
        ),
      ),
    );
  });

  test('reports Anthropic refusal content blocks', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        await utf8.decoder.bind(request).join();
        _writeJson(request.response, {
          'content': [
            {'type': 'refusal', 'refusal': 'Request refused by policy.'},
          ],
          'stop_reason': 'end_turn',
        });
        await request.response.close();
      }),
    );

    await expectLater(
      AbyssLApiClient().translate(
        text: 'Hello',
        instruction: '',
        config: _config(
          TranslationProvider.anthropicCompatible,
          _serverUri(server),
          apiKey: 'secret',
        ),
      ),
      throwsA(
        isA<AbyssLApiException>().having(
          (error) => error.message,
          'message',
          contains('refused by policy'),
        ),
      ),
    );
  });

  test('reports OpenAI length and refusal stop conditions', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requestCount = 0;
    unawaited(
      server.forEach((request) async {
        requestCount++;
        await utf8.decoder.bind(request).join();
        _writeJson(request.response, {
          'choices': [
            {
              'finish_reason': requestCount == 1 ? 'length' : 'content_filter',
              'message': {
                'content': '',
                if (requestCount > 1) 'refusal': 'Unsafe request refused.',
              },
            },
          ],
        });
        await request.response.close();
      }),
    );
    final client = AbyssLApiClient();
    final config = _config(
      TranslationProvider.openAICompatible,
      _serverUri(server),
      apiKey: 'secret',
    );

    await expectLater(
      client.translate(text: 'First', instruction: '', config: config),
      throwsA(
        isA<AbyssLApiException>().having(
          (error) => error.message,
          'message',
          contains('maximum output token'),
        ),
      ),
    );
    await expectLater(
      client.translate(text: 'Second', instruction: '', config: config),
      throwsA(
        isA<AbyssLApiException>().having(
          (error) => error.message,
          'message',
          contains('Unsafe request refused'),
        ),
      ),
    );
  });

  test('reports missing Anthropic text content', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        await utf8.decoder.bind(request).join();
        _writeJson(request.response, {
          'content': [
            {'type': 'thinking', 'thinking': 'hidden'},
          ],
          'stop_reason': 'end_turn',
        });
        await request.response.close();
      }),
    );

    await expectLater(
      AbyssLApiClient().translate(
        text: 'Hello',
        instruction: '',
        config: _config(
          TranslationProvider.anthropicCompatible,
          _serverUri(server),
          apiKey: 'secret',
        ),
      ),
      throwsA(
        isA<AbyssLApiException>().having(
          (error) => error.message,
          'message',
          contains('did not contain text content'),
        ),
      ),
    );
  });

  test('honors the active provider request timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    unawaited(
      server.forEach((request) async {
        await utf8.decoder.bind(request).join();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        _writeJson(
          request.response,
          _openAIResponse(_translationJson('Too late')),
        );
        await request.response.close();
      }),
    );

    await expectLater(
      AbyssLApiClient().translate(
        text: 'Hello',
        instruction: '',
        config: _config(
          TranslationProvider.openAICompatible,
          _serverUri(server),
          apiKey: 'secret',
          timeout: const Duration(milliseconds: 20),
        ),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test(
    'times out while a provider stalls after sending response headers',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      unawaited(
        server.forEach((request) async {
          await utf8.decoder.bind(request).join();
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"choices":[');
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 200));
          request.response.write(']}');
          await request.response.close();
        }),
      );

      await expectLater(
        AbyssLApiClient().translate(
          text: 'Hello',
          instruction: '',
          config: _config(
            TranslationProvider.openAICompatible,
            _serverUri(server),
            apiKey: 'secret',
            timeout: const Duration(milliseconds: 20),
          ),
        ),
        throwsA(isA<TimeoutException>()),
      );
    },
  );

  test('local metadata APIs honor explicit x-api-key authentication', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final apiKeys = <String?>[];
    final bearerHeaders = <String?>[];
    unawaited(
      server.forEach((request) async {
        apiKeys.add(request.headers.value('x-api-key'));
        bearerHeaders.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        _writeJson(request.response, {
          'models': [
            {
              'key': 'local-model',
              'type': 'llm',
              'loaded_instances': [
                {'id': 'local-model-loaded'},
              ],
              'capabilities': {
                'reasoning': {
                  'allowed_options': ['off', 'high'],
                  'default': 'off',
                },
              },
            },
          ],
        });
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final models = await client.fetchLocalModelCatalog(
      baseUri: _serverUri(server),
      apiKey: 'local-secret',
      authMode: ApiAuthMode.xApiKey,
    );
    final reasoning = await client.fetchLocalReasoningOptions(
      baseUri: _serverUri(server),
      apiKey: 'local-secret',
      authMode: ApiAuthMode.xApiKey,
      model: 'local-model-loaded',
    );

    expect(models.single.requestName, 'local-model-loaded');
    expect(reasoning.allowedOptions, ['off', 'high']);
    expect(apiKeys, ['local-secret', 'local-secret']);
    expect(bearerHeaders, [null, null]);
  });

  test('explicit local no-auth mode ignores a populated key', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? apiKeyHeader;
    String? bearerHeader;
    unawaited(
      server.forEach((request) async {
        apiKeyHeader = request.headers.value('x-api-key');
        bearerHeader = request.headers.value(HttpHeaders.authorizationHeader);
        _writeJson(request.response, {
          'models': [
            {
              'key': 'local-model',
              'type': 'llm',
              'loaded_instances': <Object?>[],
            },
          ],
        });
        await request.response.close();
      }),
    );

    await AbyssLApiClient().fetchLocalModelCatalog(
      baseUri: _serverUri(server),
      apiKey: 'must-not-be-sent',
      authMode: ApiAuthMode.none,
    );

    expect(apiKeyHeader, isNull);
    expect(bearerHeader, isNull);
  });

  test('detects loaded local model and reasoning metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <Uri>[];
    Map<String, Object?>? chatBody;
    unawaited(
      server.forEach((request) async {
        requests.add(request.uri);
        if (request.uri.path == '/api/v1/models') {
          _writeJson(request.response, {
            'models': [
              {
                'key': 'qwen3',
                'type': 'llm',
                'display_name': 'Qwen 3',
                'loaded_instances': [
                  {'id': 'qwen3-loaded'},
                ],
                'capabilities': {
                  'reasoning': {
                    'allowed_options': ['high', 'off', 'low'],
                    'default': 'low',
                  },
                },
              },
            ],
          });
        } else if (request.uri.path == '/v1/chat/completions') {
          chatBody = _jsonObject(await utf8.decoder.bind(request).join());
          _writeJson(
            request.response,
            _openAIResponse(_translationJson('Hallo')),
          );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final baseUri = _serverUri(server);
    final catalog = await client.fetchLocalModelCatalog(
      baseUri: baseUri,
      apiKey: '',
    );
    final reasoning = await client.fetchLocalReasoningOptions(
      baseUri: baseUri,
      apiKey: '',
      model: '',
    );
    final translated = await client.translate(
      text: 'Hello',
      instruction: '',
      config: _config(
        TranslationProvider.localOpenAICompatible,
        baseUri,
        modelId: '',
        authMode: ApiAuthMode.none,
        reasoningEnabled: true,
        reasoningEffort: 'low',
      ),
    );

    expect(catalog.single.name, 'Qwen 3');
    expect(catalog.single.requestName, 'qwen3-loaded');
    expect(catalog.single.isLoaded, isTrue);
    expect(reasoning.resolvedModelName, 'qwen3-loaded');
    expect(reasoning.defaultOption, 'low');
    expect(reasoning.allowedOptions, ['off', 'low', 'high']);
    expect(translated.translation, 'Hallo');
    expect(chatBody?['model'], 'qwen3-loaded');
    expect(chatBody?['reasoning_effort'], 'low');
    expect(requests.map((uri) => uri.path), contains('/api/v1/models'));
  });

  test('cancels a pending request and reuses the client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstRequestStarted = Completer<void>();
    final releaseFirstRequest = Completer<void>();
    var requestCount = 0;
    addTearDown(() async {
      if (!releaseFirstRequest.isCompleted) releaseFirstRequest.complete();
      await server.close(force: true);
    });
    unawaited(
      server.forEach((request) async {
        requestCount++;
        await utf8.decoder.bind(request).join();
        if (requestCount == 1) {
          firstRequestStarted.complete();
          await releaseFirstRequest.future;
          return;
        }
        _writeJson(
          request.response,
          _openAIResponse(_translationJson('Hallo')),
        );
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final config = _config(
      TranslationProvider.localOpenAICompatible,
      _serverUri(server),
      authMode: ApiAuthMode.none,
    );
    final pending = client.translate(
      text: 'Hello',
      instruction: '',
      config: config,
    );
    await firstRequestStarted.future.timeout(const Duration(seconds: 1));
    client.cancelActiveRequests();
    await expectLater(pending, throwsA(isA<AbyssLRequestCancelledException>()));
    releaseFirstRequest.complete();

    client.resetCancellation();
    final result = await client.translate(
      text: 'Hello',
      instruction: '',
      config: config,
    );
    expect(result.translation, 'Hallo');
  });
}

ProviderRequestConfig _config(
  TranslationProvider provider,
  Uri baseUri, {
  String? modelId,
  ApiAuthMode? authMode,
  String apiKey = '',
  Duration? timeout,
  int maxOutputTokens = 4096,
  String anthropicVersion = defaultAnthropicApiVersion,
  bool reasoningEnabled = false,
  String reasoningEffort = 'none',
}) => ProviderRequestConfig(
  provider: provider,
  baseUri: baseUri,
  modelId:
      modelId ??
      (provider == TranslationProvider.anthropicCompatible
          ? 'claude-test'
          : 'gpt-test'),
  authMode: authMode ?? provider.defaultAuthMode,
  apiKey: apiKey,
  timeout: timeout,
  maxOutputTokens: maxOutputTokens,
  anthropicVersion: anthropicVersion,
  sourceLanguage: TranslationLanguage.automatic,
  targetLanguage: TranslationLanguage.german,
  style: const StyleSettings(),
  reasoningEnabled: reasoningEnabled,
  reasoningEffort: reasoningEffort,
  correctionAlternativeCount: 3,
);

Uri _serverUri(HttpServer server) =>
    Uri.parse('http://127.0.0.1:${server.port}');

String _translationJson(String translation) => jsonEncode({
  'translation': translation,
  'synonyms': [translation],
  'spelling_notes': null,
  'revised_source': null,
});

Map<String, Object?> _openAIResponse(String content) => {
  'choices': [
    {
      'finish_reason': 'stop',
      'message': {'content': content},
    },
  ],
};

Map<String, Object?> _anthropicResponse(String content) => {
  'content': [
    {'type': 'thinking', 'thinking': 'not returned'},
    {'type': 'text', 'text': content},
  ],
  'stop_reason': 'end_turn',
};

void _writeJson(HttpResponse response, Object value) {
  response.headers.contentType = ContentType.json;
  response.write(jsonEncode(value));
}

Map<String, Object?> _jsonObject(String source) => _jsonMap(jsonDecode(source));

Map<String, Object?> _jsonMap(Object? value) =>
    (value as Map).map((key, value) => MapEntry('$key', value));
