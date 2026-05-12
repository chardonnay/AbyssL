import 'dart:convert';
import 'dart:async';
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

  test('uses OpenAI-compatible endpoints with a local test double', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final requests = <Uri>[];
    unawaited(
      server.forEach((request) async {
        requests.add(request.uri);
        if (request.uri.path == '/v1/models') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'data': []}));
        } else if (request.uri.path == '/v1/chat/completions') {
          final body = await utf8.decoder.bind(request).join();
          expect(body, contains('"model":"gpt-4o-mini"'));
          expect(body, contains('"response_format":{"type":"json_object"}'));
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'translation': 'Hallo',
                        'synonyms': ['Hallo'],
                      }),
                    },
                  },
                ],
              }),
            );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    await client.testConnection(
      provider: TranslationProvider.localLLM,
      baseUri: base,
      apiKey: '',
    );
    final result = await client.translate(
      text: 'Hello',
      instruction: '',
      config: ProviderRequestConfig(
        provider: TranslationProvider.openAI,
        openAIBaseUri: base,
        localBaseUri: base,
        openAIApiKey: 'test-key',
        localApiKey: '',
        selectedModel: OpenAIModel.gpt4oMini,
        localModel: '',
        sourceLanguage: TranslationLanguage.automatic,
        targetLanguage: TranslationLanguage.german,
        style: const StyleSettings(),
        reasoningEnabled: false,
        reasoningEffort: 'none',
        localRequestTimeoutSeconds: 0,
        correctionAlternativeCount: 3,
      ),
    );

    expect(result.translation, 'Hallo');
    expect(
      requests.map((uri) => uri.path),
      containsAll(['/v1/models', '/v1/chat/completions']),
    );
  });

  test('detects loaded local model and reasoning metadata', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final requests = <Uri>[];
    unawaited(
      server.forEach((request) async {
        requests.add(request.uri);
        if (request.uri.path == '/api/v1/models') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'models': [
                  {
                    'key': 'embedding-model',
                    'type': 'embedding',
                    'loaded_instances': [],
                  },
                  {
                    'key': 'qwen3',
                    'type': 'llm',
                    'display_name': 'Qwen 3',
                    'selected_variant': 'qwen3-8b',
                    'loaded_instances': [
                      {'id': 'qwen3-8b-loaded'},
                    ],
                    'capabilities': {
                      'reasoning': {
                        'allowed_options': ['high', 'off', 'low'],
                        'default': 'low',
                      },
                    },
                  },
                ],
              }),
            );
        } else if (request.uri.path == '/v1/chat/completions') {
          final body = await utf8.decoder.bind(request).join();
          expect(body, contains('"model":"qwen3-8b-loaded"'));
          expect(body, contains('"response_format":{"type":"text"}'));
          expect(body, contains('"reasoning_effort":"low"'));
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'translation': 'Hallo',
                        'synonyms': ['Hallo'],
                      }),
                    },
                  },
                ],
              }),
            );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final catalog = await client.fetchLocalModelCatalog(
      baseUri: base,
      apiKey: '',
    );
    expect(catalog, hasLength(1));
    expect(catalog.single.name, 'Qwen 3');
    expect(catalog.single.requestName, 'qwen3-8b-loaded');
    expect(catalog.single.isLoaded, isTrue);

    final reasoning = await client.fetchLocalReasoningOptions(
      baseUri: base,
      apiKey: '',
      model: '',
    );
    expect(reasoning.resolvedModelName, 'qwen3-8b-loaded');
    expect(reasoning.defaultOption, 'low');
    expect(reasoning.allowedOptions, ['off', 'low', 'high']);

    final result = await client.translate(
      text: 'Hello',
      instruction: '',
      config: ProviderRequestConfig(
        provider: TranslationProvider.localLLM,
        openAIBaseUri: base,
        localBaseUri: base,
        openAIApiKey: '',
        localApiKey: '',
        selectedModel: OpenAIModel.gpt4oMini,
        localModel: '',
        sourceLanguage: TranslationLanguage.automatic,
        targetLanguage: TranslationLanguage.german,
        style: const StyleSettings(),
        reasoningEnabled: true,
        reasoningEffort: 'low',
        localRequestTimeoutSeconds: 0,
        correctionAlternativeCount: 3,
      ),
    );

    expect(result.translation, 'Hallo');
    expect(
      requests.map((uri) => uri.path),
      containsAll(['/api/v1/models', '/v1/chat/completions']),
    );
  });

  test('sends explicit local reasoning off when disabled', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    final chatBodies = <String>[];
    unawaited(
      server.forEach((request) async {
        if (request.uri.path == '/v1/chat/completions') {
          final body = await utf8.decoder.bind(request).join();
          chatBodies.add(body);
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {
                      'content': jsonEncode({
                        'translation': 'Hallo',
                        'synonyms': ['Hallo'],
                      }),
                    },
                  },
                ],
              }),
            );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final result = await client.translate(
      text: 'Hello',
      instruction: '',
      config: ProviderRequestConfig(
        provider: TranslationProvider.localLLM,
        openAIBaseUri: base,
        localBaseUri: base,
        openAIApiKey: '',
        localApiKey: '',
        selectedModel: OpenAIModel.gpt4oMini,
        localModel: 'local-model',
        sourceLanguage: TranslationLanguage.automatic,
        targetLanguage: TranslationLanguage.german,
        style: const StyleSettings(),
        reasoningEnabled: false,
        reasoningEffort: 'off',
        localRequestTimeoutSeconds: 0,
        correctionAlternativeCount: 3,
      ),
    );

    expect(result.translation, 'Hallo');
    expect(chatBodies, hasLength(1));
    expect(chatBodies.single, contains('"reasoning_effort":"off"'));
  });

  test(
    'retries local chat without optional fields after channel error',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      final chatBodies = <String>[];
      unawaited(
        server.forEach((request) async {
          if (request.uri.path == '/v1/chat/completions') {
            final body = await utf8.decoder.bind(request).join();
            chatBodies.add(body);
            if (chatBodies.length == 1) {
              request.response
                ..statusCode = 500
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'error': {'message': 'Channel Error'},
                  }),
                );
            } else {
              request.response
                ..headers.contentType = ContentType.json
                ..write(
                  jsonEncode({
                    'choices': [
                      {
                        'message': {
                          'content': jsonEncode({
                            'translation': 'Hallo',
                            'synonyms': ['Hallo'],
                          }),
                        },
                      },
                    ],
                  }),
                );
            }
          } else {
            request.response.statusCode = 404;
          }
          await request.response.close();
        }),
      );

      final client = AbyssLApiClient();
      final base = Uri.parse('http://127.0.0.1:${server.port}');
      final result = await client.translate(
        text: 'Hello',
        instruction: '',
        config: ProviderRequestConfig(
          provider: TranslationProvider.localLLM,
          openAIBaseUri: base,
          localBaseUri: base,
          openAIApiKey: '',
          localApiKey: '',
          selectedModel: OpenAIModel.gpt4oMini,
          localModel: 'qwen/qwen3-coder-next',
          sourceLanguage: TranslationLanguage.automatic,
          targetLanguage: TranslationLanguage.german,
          style: const StyleSettings(),
          reasoningEnabled: true,
          reasoningEffort: 'on',
          localRequestTimeoutSeconds: 0,
          correctionAlternativeCount: 3,
        ),
      );

      expect(result.translation, 'Hallo');
      expect(chatBodies, hasLength(2));
      expect(chatBodies.first, contains('"response_format":{"type":"text"}'));
      expect(chatBodies.first, contains('"reasoning_effort":"on"'));
      expect(chatBodies.last, isNot(contains('response_format')));
      expect(chatBodies.last, isNot(contains('reasoning_effort')));
    },
  );

  test('cancels pending local chat request and reuses client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final firstRequestStarted = Completer<void>();
    final releaseFirstRequest = Completer<void>();
    var chatCount = 0;
    addTearDown(() {
      if (!releaseFirstRequest.isCompleted) releaseFirstRequest.complete();
      server.close(force: true);
    });

    unawaited(
      server.forEach((request) async {
        if (request.uri.path != '/v1/chat/completions') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }

        chatCount++;
        await utf8.decoder.bind(request).join();
        if (chatCount == 1) {
          firstRequestStarted.complete();
          await releaseFirstRequest.future;
          return;
        }

        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': jsonEncode({
                      'translation': 'Hallo',
                      'synonyms': ['Hallo'],
                    }),
                  },
                },
              ],
            }),
          );
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final base = Uri.parse('http://127.0.0.1:${server.port}');
    final pending = client.translate(
      text: 'Hello',
      instruction: '',
      config: ProviderRequestConfig(
        provider: TranslationProvider.localLLM,
        openAIBaseUri: base,
        localBaseUri: base,
        openAIApiKey: '',
        localApiKey: '',
        selectedModel: OpenAIModel.gpt4oMini,
        localModel: 'local-model',
        sourceLanguage: TranslationLanguage.automatic,
        targetLanguage: TranslationLanguage.german,
        style: const StyleSettings(),
        reasoningEnabled: false,
        reasoningEffort: 'none',
        localRequestTimeoutSeconds: 0,
        correctionAlternativeCount: 3,
      ),
    );

    await firstRequestStarted.future.timeout(const Duration(seconds: 1));
    client.cancelActiveRequests();
    await expectLater(pending, throwsA(isA<AbyssLRequestCancelledException>()));
    releaseFirstRequest.complete();

    client.resetCancellation();
    final result = await client.translate(
      text: 'Hello',
      instruction: '',
      config: ProviderRequestConfig(
        provider: TranslationProvider.localLLM,
        openAIBaseUri: base,
        localBaseUri: base,
        openAIApiKey: '',
        localApiKey: '',
        selectedModel: OpenAIModel.gpt4oMini,
        localModel: 'local-model',
        sourceLanguage: TranslationLanguage.automatic,
        targetLanguage: TranslationLanguage.german,
        style: const StyleSettings(),
        reasoningEnabled: false,
        reasoningEffort: 'none',
        localRequestTimeoutSeconds: 0,
        correctionAlternativeCount: 3,
      ),
    );

    expect(result.translation, 'Hallo');
  });

  test('falls back to OpenAI-compatible model catalog', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    unawaited(
      server.forEach((request) async {
        if (request.uri.path == '/api/v1/models') {
          request.response.statusCode = 404;
        } else if (request.uri.path == '/v1/models') {
          request.response
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'data': [
                  {'id': 'llama-local'},
                ],
              }),
            );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      }),
    );

    final client = AbyssLApiClient();
    final catalog = await client.fetchLocalModelCatalog(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      apiKey: '',
    );

    expect(catalog, hasLength(1));
    expect(catalog.single.requestName, 'llama-local');
    expect(catalog.single.isLoaded, isFalse);
  });
}
