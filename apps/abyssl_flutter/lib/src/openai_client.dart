import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'prompt_builder.dart';

class AbyssLApiException implements Exception {
  const AbyssLApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AbyssLRequestCancelledException implements Exception {
  const AbyssLRequestCancelledException();

  @override
  String toString() => 'Request cancelled.';
}

class LocalLLMModel {
  const LocalLLMModel({
    required this.id,
    required this.requestName,
    required this.name,
    required this.isLoaded,
  });

  final String id;
  final String requestName;
  final String name;
  final bool isLoaded;
}

class LocalReasoningOptions {
  const LocalReasoningOptions({
    required this.allowedOptions,
    this.defaultOption,
    this.resolvedModelName,
  });

  final List<String> allowedOptions;
  final String? defaultOption;
  final String? resolvedModelName;

  static int compareOptions(String lhs, String rhs) {
    const order = [
      'none',
      'off',
      'on',
      'minimal',
      'low',
      'medium',
      'high',
      'xhigh',
    ];
    final lhsIndex = order.indexOf(lhs);
    final rhsIndex = order.indexOf(rhs);
    final normalizedLhsIndex = lhsIndex < 0 ? order.length : lhsIndex;
    final normalizedRhsIndex = rhsIndex < 0 ? order.length : rhsIndex;
    if (normalizedLhsIndex == normalizedRhsIndex) {
      return lhs.compareTo(rhs);
    }
    return normalizedLhsIndex.compareTo(normalizedRhsIndex);
  }
}

class ProviderRequestConfig {
  const ProviderRequestConfig({
    required this.provider,
    required this.openAIBaseUri,
    required this.localBaseUri,
    required this.openAIApiKey,
    required this.localApiKey,
    required this.selectedModel,
    required this.localModel,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.style,
    required this.reasoningEnabled,
    required this.reasoningEffort,
    required this.localRequestTimeoutSeconds,
    required this.correctionAlternativeCount,
  });

  final TranslationProvider provider;
  final Uri openAIBaseUri;
  final Uri localBaseUri;
  final String openAIApiKey;
  final String localApiKey;
  final OpenAIModel selectedModel;
  final String localModel;
  final TranslationLanguage sourceLanguage;
  final TranslationLanguage targetLanguage;
  final StyleSettings style;
  final bool reasoningEnabled;
  final String reasoningEffort;
  final int localRequestTimeoutSeconds;
  final int correctionAlternativeCount;

  Uri get baseUri =>
      provider == TranslationProvider.openAI ? openAIBaseUri : localBaseUri;
  String get apiKey =>
      provider == TranslationProvider.openAI ? openAIApiKey : localApiKey;
  String get modelId => provider == TranslationProvider.openAI
      ? selectedModel.id
      : localModel.trim();
  Duration? get timeout =>
      provider == TranslationProvider.localLLM && localRequestTimeoutSeconds > 0
      ? Duration(seconds: localRequestTimeoutSeconds)
      : null;
}

class AbyssLApiClient {
  AbyssLApiClient({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  HttpClient _httpClient;
  var _cancelled = false;

  void cancelActiveRequests() {
    _cancelled = true;
    _httpClient.close(force: true);
    _httpClient = HttpClient();
  }

  void resetCancellation() {
    _cancelled = false;
  }

  void close() {
    _httpClient.close(force: true);
  }

  Future<TranslationAIResult> translate({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const AbyssLApiException('Source text is empty.');
    }
    final model = await _resolveModel(config);
    if (config.provider == TranslationProvider.openAI &&
        config.openAIApiKey.trim().isEmpty) {
      throw const AbyssLApiException('API key is missing. Add it in Settings.');
    }

    final payload = await _chat(
      config: config,
      model: model,
      messages: [
        _message(
          'system',
          PromptBuilder.translationSystemPrompt(
            source: config.sourceLanguage,
            target: config.targetLanguage,
            style: config.style,
            reasoning: config.reasoningEnabled,
            model: config.selectedModel,
          ),
        ),
        _message(
          'user',
          PromptBuilder.translationUserPayload(
            text: trimmed,
            instruction: instruction,
            target: config.targetLanguage,
            style: config.style,
          ),
        ),
      ],
    );
    final result = parseTranslationJson(payload);
    return TranslationAIResult(
      translation: preserveSourceParagraphs(
        source: trimmed,
        translation: result.translation,
      ),
      synonyms: result.synonyms,
      spellingNotes: result.spellingNotes,
      revisedSource: result.revisedSource,
    );
  }

  Future<List<String>> suggestAlternatives({
    required String selectedText,
    required String targetContext,
    required String userInstruction,
    required int count,
    required ProviderRequestConfig config,
  }) async {
    final selected = selectedText.trim();
    if (selected.isEmpty) {
      throw const AbyssLApiException(
        'Select text or provide translated text first.',
      );
    }
    final model = await _resolveModel(config);
    final raw = await _chat(
      config: config,
      model: model,
      messages: [
        _message(
          'system',
          PromptBuilder.alternativesSystemPrompt(
            target: config.targetLanguage,
            style: config.style,
            count: count,
            reasoning: config.reasoningEnabled,
            hasUserInstruction: userInstruction.trim().isNotEmpty,
          ),
        ),
        _message(
          'user',
          PromptBuilder.alternativesUserPayload(
            selectedText: selected,
            targetContext: targetContext,
            userInstruction: userInstruction,
          ),
        ),
      ],
    );
    return parseAlternatives(raw, excluding: selected, limit: count);
  }

  Future<WritingCorrectionResult> correctWriting({
    required String text,
    required String instruction,
    required ProviderRequestConfig config,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const AbyssLApiException('Correction text is empty.');
    }
    final model = await _resolveModel(config);
    final raw = await _chat(
      config: config,
      model: model,
      messages: [
        _message(
          'system',
          PromptBuilder.correctionSystemPrompt(
            source: config.sourceLanguage,
            alternativeCount: config.correctionAlternativeCount,
            reasoning: config.reasoningEnabled,
            hasUserInstruction: instruction.trim().isNotEmpty,
          ),
        ),
        _message(
          'user',
          PromptBuilder.correctionUserPayload(
            text: trimmed,
            instruction: instruction,
          ),
        ),
      ],
    );
    return parseWritingCorrectionJson(
      raw,
      fallbackText: trimmed,
      alternativeLimit: config.correctionAlternativeCount,
    );
  }

  Future<String> rewriteWriting({
    required String text,
    required String instruction,
    required WritingStylePreset stylePreset,
    required ProviderRequestConfig config,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const AbyssLApiException('Rewrite text is empty.');
    }
    final model = await _resolveModel(config);
    final raw = await _chat(
      config: config,
      model: model,
      messages: [
        _message(
          'system',
          PromptBuilder.rewriteSystemPrompt(
            stylePreset: stylePreset,
            source: config.sourceLanguage,
            reasoning: config.reasoningEnabled,
            hasUserInstruction: instruction.trim().isNotEmpty,
          ),
        ),
        _message(
          'user',
          PromptBuilder.rewriteUserPayload(
            text: trimmed,
            instruction: instruction,
          ),
        ),
      ],
    );
    return parseRewriteJson(raw, fallbackText: trimmed);
  }

  Future<void> testConnection({
    required TranslationProvider provider,
    required Uri baseUri,
    required String apiKey,
    Duration? timeout,
  }) async {
    if (provider == TranslationProvider.openAI && apiKey.trim().isEmpty) {
      throw const AbyssLApiException('API key is missing. Add it in Settings.');
    }
    final request = await _openUrl(
      'GET',
      _endpoint(baseUri, ['v1', 'models']),
      timeout,
    );
    _applyAuth(request, apiKey);
    final response = await _close(request, timeout);
    await _readCheckedResponse(response);
  }

  Future<List<String>> fetchLocalModels({
    required Uri baseUri,
    required String apiKey,
    Duration? timeout,
  }) async => (await fetchLocalModelCatalog(
    baseUri: baseUri,
    apiKey: apiKey,
    timeout: timeout,
  )).map((model) => model.requestName).toList(growable: false);

  Future<List<LocalLLMModel>> fetchLocalModelCatalog({
    required Uri baseUri,
    required String apiKey,
    Duration? timeout,
  }) async {
    try {
      final decoded = await _fetchJsonObject(
        baseUri: baseUri,
        segments: const ['api', 'v1', 'models'],
        apiKey: apiKey,
        timeout: timeout,
      );
      final metadataModels = _parseLocalMetadataModelCatalog(decoded);
      if (metadataModels.isNotEmpty) return metadataModels;
    } catch (_) {
      // Some OpenAI-compatible local servers do not provide LM Studio metadata.
    }
    return _fetchOpenAICompatibleModelCatalog(
      baseUri: baseUri,
      apiKey: apiKey,
      timeout: timeout,
    );
  }

  Future<LocalReasoningOptions> fetchLocalReasoningOptions({
    required Uri baseUri,
    required String apiKey,
    required String model,
    Duration? timeout,
  }) async {
    final decoded = await _fetchJsonObject(
      baseUri: baseUri,
      segments: const ['api', 'v1', 'models'],
      apiKey: apiKey,
      timeout: timeout,
    );
    final modelName = _requestModelName(model);
    final modelInfo = _localModelInfoFor(decoded, modelName);
    if (modelInfo == null) {
      if (modelName == null) {
        return const LocalReasoningOptions(
          allowedOptions: ['off'],
          defaultOption: 'off',
        );
      }
      throw AbyssLApiException(
        'No LM Studio metadata found for local model "$modelName".',
      );
    }

    final requestName = _localMetadataRequestModelName(modelInfo);
    final allowedOptions = _localMetadataReasoningOptions(modelInfo);
    if (allowedOptions.isEmpty) {
      return LocalReasoningOptions(
        allowedOptions: const ['off'],
        defaultOption: 'off',
        resolvedModelName: requestName,
      );
    }

    final defaultOption = _localMetadataReasoningDefault(modelInfo);
    return LocalReasoningOptions(
      allowedOptions: allowedOptions,
      defaultOption: defaultOption,
      resolvedModelName: requestName,
    );
  }

  Future<String> _chat({
    required ProviderRequestConfig config,
    required String model,
    required List<Map<String, String>> messages,
  }) async {
    final body = <String, Object?>{
      'model': model,
      'messages': messages,
      'temperature': 0.2,
      'response_format': {'type': _responseFormatType(config.provider)},
    };
    final effort = _requestReasoningEffort(
      provider: config.provider,
      reasoning: config.reasoningEnabled,
      reasoningEffort: config.reasoningEffort,
    );
    if (effort != null) {
      body['reasoning_effort'] = effort;
    }

    try {
      return await _sendChatRequest(config: config, body: body);
    } on AbyssLApiException catch (error) {
      final compatibilityBody = Map<String, Object?>.from(body);
      final removedFields = <String>[];
      if (compatibilityBody.remove('reasoning_effort') != null) {
        removedFields.add('reasoning_effort');
      }
      if (compatibilityBody.remove('response_format') != null) {
        removedFields.add('response_format');
      }
      if (config.provider != TranslationProvider.localLLM ||
          removedFields.isEmpty) {
        rethrow;
      }

      try {
        return await _sendChatRequest(config: config, body: compatibilityBody);
      } on AbyssLApiException catch (retryError) {
        throw AbyssLApiException(
          '$retryError Compatibility retry without ${removedFields.join(' and ')} also failed. First error: $error',
        );
      }
    }
  }

  Future<String> _sendChatRequest({
    required ProviderRequestConfig config,
    required Map<String, Object?> body,
  }) async {
    final String responseBody;
    try {
      _throwIfCancelled();
      final request = await _openUrl(
        'POST',
        _endpoint(config.baseUri, ['v1', 'chat', 'completions']),
        config.timeout,
      );
      _throwIfCancelled();
      request.headers.contentType = ContentType.json;
      _applyAuth(request, config.apiKey);
      request.write(jsonEncode(body));
      final response = await _close(request, config.timeout);
      _throwIfCancelled();
      responseBody = await _readCheckedResponse(response);
      _throwIfCancelled();
    } on AbyssLRequestCancelledException {
      rethrow;
    } catch (_) {
      _throwIfCancelled();
      rethrow;
    }
    final decoded = jsonDecode(responseBody);
    if (decoded is! Map<String, Object?>) {
      throw const AbyssLApiException(
        'Invalid response from chat completions endpoint.',
      );
    }
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map<String, Object?>) {
        final message = first['message'];
        if (message is Map<String, Object?>) {
          final content = message['content'];
          if (content is String && content.trim().isNotEmpty) {
            return content;
          }
        }
      }
    }
    throw const AbyssLApiException(
      'Chat completion response did not contain message content.',
    );
  }

  Future<String> _resolveModel(ProviderRequestConfig config) async {
    final model = config.modelId;
    if (model.isEmpty) {
      if (config.provider == TranslationProvider.localLLM) {
        final resolved = await _resolveLocalModelName(
          baseUri: config.localBaseUri,
          apiKey: config.localApiKey,
          timeout: config.timeout,
        );
        if (resolved != null) return resolved;
      }
      throw const AbyssLApiException(
        'Model is missing. Add it in Settings or detect the local model.',
      );
    }
    return model;
  }

  Future<String?> _resolveLocalModelName({
    required Uri baseUri,
    required String apiKey,
    Duration? timeout,
  }) async {
    try {
      final decoded = await _fetchJsonObject(
        baseUri: baseUri,
        segments: const ['api', 'v1', 'models'],
        apiKey: apiKey,
        timeout: timeout,
      );
      final modelInfo = _localModelInfoFor(decoded, null);
      if (modelInfo != null) {
        return _localMetadataRequestModelName(modelInfo);
      }
    } catch (_) {
      // Fall through to the OpenAI-compatible model catalog.
    }

    final models = await _fetchOpenAICompatibleModelCatalog(
      baseUri: baseUri,
      apiKey: apiKey,
      timeout: timeout,
    );
    return models.length == 1 ? models.single.requestName : null;
  }

  Future<Map<String, Object?>> _fetchJsonObject({
    required Uri baseUri,
    required List<String> segments,
    required String apiKey,
    Duration? timeout,
  }) async {
    final request = await _openUrl(
      'GET',
      _endpoint(baseUri, segments),
      timeout,
    );
    _applyAuth(request, apiKey);
    final response = await _close(request, timeout);
    final body = await _readCheckedResponse(response);
    final decoded = jsonDecode(body);
    final object = _asObjectMap(decoded);
    if (object == null) {
      throw const AbyssLApiException('Model endpoint returned invalid JSON.');
    }
    return object;
  }

  Future<List<LocalLLMModel>> _fetchOpenAICompatibleModelCatalog({
    required Uri baseUri,
    required String apiKey,
    Duration? timeout,
  }) async {
    final decoded = await _fetchJsonObject(
      baseUri: baseUri,
      segments: const ['v1', 'models'],
      apiKey: apiKey,
      timeout: timeout,
    );
    final data = decoded['data'];
    if (data is! List) return const [];
    final models = data
        .map(_asObjectMap)
        .nonNulls
        .map((item) => _stringField(item, 'id'))
        .where((id) => id.isNotEmpty)
        .map(
          (id) =>
              LocalLLMModel(id: id, requestName: id, name: id, isLoaded: false),
        )
        .toList();
    models.sort((lhs, rhs) => lhs.name.compareTo(rhs.name));
    return models;
  }

  List<LocalLLMModel> _parseLocalMetadataModelCatalog(
    Map<String, Object?> decoded,
  ) {
    final models = _localMetadataModels(decoded)
        .where((item) => _stringField(item, 'type') == 'llm')
        .map((item) {
          final requestName = _localMetadataRequestModelName(item);
          final key = _stringField(item, 'key');
          final displayName = _stringField(item, 'displayName');
          final name = displayName.isNotEmpty ? displayName : key;
          if (requestName.isEmpty || name.isEmpty) return null;
          return LocalLLMModel(
            id: requestName,
            requestName: requestName,
            name: name,
            isLoaded: _localMetadataLoadedInstances(item).isNotEmpty,
          );
        })
        .nonNulls
        .toList();
    models.sort((lhs, rhs) {
      if (lhs.isLoaded != rhs.isLoaded) {
        return lhs.isLoaded ? -1 : 1;
      }
      return lhs.name.compareTo(rhs.name);
    });
    return models;
  }

  Map<String, Object?>? _localModelInfoFor(
    Map<String, Object?> decoded,
    String? modelName,
  ) {
    final models = _localMetadataModels(decoded);
    if (modelName != null) {
      for (final model in models) {
        if (_localMetadataModelMatches(model, modelName)) return model;
      }
    }

    final loadedLLMs = models
        .where(
          (model) =>
              _stringField(model, 'type') == 'llm' &&
              _localMetadataLoadedInstances(model).isNotEmpty,
        )
        .toList();
    return loadedLLMs.length == 1 ? loadedLLMs.single : null;
  }

  bool _localMetadataModelMatches(
    Map<String, Object?> model,
    String modelName,
  ) {
    if (_stringField(model, 'key') == modelName) return true;
    if (_stringField(model, 'selectedVariant') == modelName) return true;
    return _localMetadataLoadedInstances(
      model,
    ).any((instance) => _stringField(instance, 'id') == modelName);
  }

  List<Map<String, Object?>> _localMetadataModels(
    Map<String, Object?> decoded,
  ) {
    final models = decoded['models'];
    if (models is! List) return const [];
    return models.map(_asObjectMap).nonNulls.toList(growable: false);
  }

  List<Map<String, Object?>> _localMetadataLoadedInstances(
    Map<String, Object?> model,
  ) {
    final loaded = _field(model, 'loadedInstances');
    if (loaded is! List) return const [];
    return loaded.map(_asObjectMap).nonNulls.toList(growable: false);
  }

  String _localMetadataRequestModelName(Map<String, Object?> model) {
    final loadedInstances = _localMetadataLoadedInstances(model);
    if (loadedInstances.isNotEmpty) {
      final loadedID = _stringField(loadedInstances.first, 'id');
      if (loadedID.isNotEmpty) return loadedID;
    }
    return _stringField(model, 'key');
  }

  List<String> _localMetadataReasoningOptions(Map<String, Object?> model) {
    final capabilities = _asObjectMap(_field(model, 'capabilities'));
    final reasoning = _asObjectMap(_field(capabilities, 'reasoning'));
    final rawOptions = _field(reasoning, 'allowedOptions');
    if (rawOptions is! List) return const [];
    final options = rawOptions
        .whereType<String>()
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toSet()
        .toList();
    options.sort(LocalReasoningOptions.compareOptions);
    return options;
  }

  String? _localMetadataReasoningDefault(Map<String, Object?> model) {
    final capabilities = _asObjectMap(_field(model, 'capabilities'));
    final reasoning = _asObjectMap(_field(capabilities, 'reasoning'));
    final value = _stringField(reasoning, 'default');
    return value.isEmpty ? null : value;
  }

  String? _requestModelName(String model) {
    final trimmed = model.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _requestReasoningEffort({
    required TranslationProvider provider,
    required bool reasoning,
    required String reasoningEffort,
  }) {
    final normalized = reasoningEffort.trim().toLowerCase();
    if (provider == TranslationProvider.localLLM && normalized == 'off') {
      return 'off';
    }
    if (!reasoning || normalized.isEmpty) return null;
    if (normalized == 'none' || normalized == 'off') return null;
    if (provider == TranslationProvider.localLLM && normalized == 'on') {
      return 'on';
    }
    if (normalized == 'on') return 'minimal';
    const allowed = {'minimal', 'low', 'medium', 'high', 'xhigh'};
    return allowed.contains(normalized) ? normalized : null;
  }

  String _responseFormatType(TranslationProvider provider) =>
      provider == TranslationProvider.localLLM ? 'text' : 'json_object';

  static Map<String, Object?>? _asObjectMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry('$key', value));
  }

  static Object? _field(Map<String, Object?>? value, String key) {
    if (value == null) return null;
    return value[key] ?? value[_toSnakeCase(key)];
  }

  static String _stringField(Map<String, Object?>? value, String key) {
    final raw = _field(value, key);
    return raw is String ? raw.trim() : '';
  }

  static String _toSnakeCase(String value) => value.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '_${match.group(0)!.toLowerCase()}',
  );

  Future<HttpClientRequest> _openUrl(
    String method,
    Uri uri,
    Duration? timeout,
  ) {
    _throwIfCancelled();
    final future = _httpClient.openUrl(method, uri);
    return timeout == null ? future : future.timeout(timeout);
  }

  Future<HttpClientResponse> _close(
    HttpClientRequest request,
    Duration? timeout,
  ) {
    _throwIfCancelled();
    final future = request.close();
    return timeout == null ? future : future.timeout(timeout);
  }

  void _throwIfCancelled() {
    if (_cancelled) throw const AbyssLRequestCancelledException();
  }

  void _applyAuth(HttpClientRequest request, String key) {
    final trimmed = key.trim();
    if (trimmed.isNotEmpty) {
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $trimmed');
    }
  }

  Future<String> _readCheckedResponse(HttpClientResponse response) async {
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String? serverMessage;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, Object?>) {
          final error = decoded['error'];
          if (error is Map<String, Object?> && error['message'] is String) {
            serverMessage = error['message'] as String;
          }
        }
      } catch (_) {
        serverMessage = null;
      }
      final suffix = serverMessage == null || serverMessage.isEmpty
          ? body
          : serverMessage;
      throw AbyssLApiException(
        'HTTP ${response.statusCode}${suffix.isEmpty ? '' : ': $suffix'}',
      );
    }
    return body;
  }

  static Map<String, String> _message(String role, String content) => {
    'role': role,
    'content': content,
  };

  static Uri _endpoint(Uri baseUri, List<String> segments) {
    final baseSegments = baseUri.pathSegments.where(
      (segment) => segment.isNotEmpty,
    );
    return baseUri.replace(pathSegments: [...baseSegments, ...segments]);
  }

  static TranslationAIResult parseTranslationJson(String raw) {
    final trimmed = raw.trim();
    final decoded = _decodeObject(trimmed);
    if (decoded == null) {
      return TranslationAIResult(translation: trimmed);
    }
    final translation = decoded['translation'];
    final synonyms = decoded['synonyms'];
    final spellingNotes = decoded['spelling_notes'] ?? decoded['spellingNotes'];
    final revisedSource = decoded['revised_source'] ?? decoded['revisedSource'];
    final cleanedSynonyms = synonyms is List
        ? synonyms
              .map((item) => item is String ? item.trim() : '')
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
        : <String>[];
    cleanedSynonyms.sort();
    return TranslationAIResult(
      translation: translation is String ? translation : trimmed,
      synonyms: cleanedSynonyms,
      spellingNotes: spellingNotes is String && spellingNotes.trim().isNotEmpty
          ? spellingNotes
          : null,
      revisedSource: revisedSource is String && revisedSource.trim().isNotEmpty
          ? revisedSource
          : null,
    );
  }

  static String preserveSourceParagraphs({
    required String source,
    required String translation,
  }) {
    final sourceParagraphs = _paragraphs(source);
    if (sourceParagraphs.length < 2) return translation;
    final translationParagraphs = _paragraphs(translation);
    if (translationParagraphs.length == sourceParagraphs.length) {
      return translation;
    }
    if (translationParagraphs.length != 1) return translation;

    final sentences = _sentences(translationParagraphs.single);
    if (sentences.length < sourceParagraphs.length) return translation;

    final sourceWeights = sourceParagraphs
        .map((paragraph) => paragraph.trim().length)
        .toList(growable: false);
    final totalWeight = sourceWeights.fold<int>(0, (sum, value) => sum + value);
    if (totalWeight <= 0) return translation;

    final groups = <String>[];
    var sentenceIndex = 0;
    for (var index = 0; index < sourceParagraphs.length; index += 1) {
      final remainingGroups = sourceParagraphs.length - index;
      final remainingSentences = sentences.length - sentenceIndex;
      final sentenceCount = index == sourceParagraphs.length - 1
          ? remainingSentences
          : (sentences.length * sourceWeights[index] / totalWeight)
                .round()
                .clamp(1, remainingSentences - remainingGroups + 1);
      groups.add(
        sentences.skip(sentenceIndex).take(sentenceCount).join(' ').trim(),
      );
      sentenceIndex += sentenceCount;
    }
    return groups.join('\n\n');
  }

  static List<String> _paragraphs(String value) => value
      .trim()
      .split(RegExp(r'(?:\r?\n){2,}'))
      .map((paragraph) => paragraph.trim())
      .where((paragraph) => paragraph.isNotEmpty)
      .toList(growable: false);

  static List<String> _sentences(String value) {
    final matches = RegExp(
      r'[^.!?。！？]+(?:[.!?。！？]+(?=\s|$)|$)',
      multiLine: true,
    ).allMatches(value.trim());
    final sentences = matches
        .map((match) => match.group(0)?.trim() ?? '')
        .where((sentence) => sentence.isNotEmpty)
        .toList(growable: false);
    return sentences.isEmpty ? [value.trim()] : sentences;
  }

  static List<String> parseAlternatives(
    String raw, {
    required String excluding,
    required int limit,
  }) {
    final decoded = _decodeObject(raw.trim());
    final source = decoded?['alternatives'];
    final values = source is List
        ? source.map((item) => '$item')
        : raw.split(RegExp(r'\r?\n'));
    final selected = excluding.trim().toLowerCase();
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final cleaned = value.trim().replaceAll(
        RegExp(r'^["`\-\u2022\d.\s]+|["`\s]+$'),
        '',
      );
      final normalized = cleaned.toLowerCase();
      if (cleaned.isEmpty || normalized == selected || !seen.add(normalized)) {
        continue;
      }
      result.add(cleaned);
      if (result.length >= limit) break;
    }
    return result;
  }

  static WritingCorrectionResult parseWritingCorrectionJson(
    String raw, {
    required String fallbackText,
    required int alternativeLimit,
  }) {
    final trimmed = raw.trim();
    final decoded = _decodeObject(trimmed);
    if (decoded == null) {
      return WritingCorrectionResult(
        correctedText: trimmed.isEmpty ? fallbackText : trimmed,
      );
    }
    final corrected = decoded['corrected_text'] ?? decoded['correctedText'];
    final correctedText = corrected is String && corrected.trim().isNotEmpty
        ? corrected.trim()
        : fallbackText;
    final corrections = decoded['corrections'];
    final issues = <WritingCorrectionIssue>[];
    var correctedSearchStart = 0;
    var originalSearchStart = 0;
    if (corrections is List) {
      for (final item in corrections) {
        if (item is! Map<String, Object?>) continue;
        final original = item['original'];
        final correctedSpan = item['corrected'];
        if (original is! String || correctedSpan is! String) continue;
        final originalText = original.trim();
        final correctedValue = correctedSpan.trim();
        if (originalText.isEmpty ||
            correctedValue.isEmpty ||
            originalText == correctedValue) {
          continue;
        }
        final alternatives = item['alternatives'];
        final cleanedAlternatives = alternatives is List
            ? alternatives
                  .map((value) => value is String ? value.trim() : '')
                  .where((value) => value.isNotEmpty && value != correctedValue)
                  .toSet()
                  .take(alternativeLimit)
                  .toList()
            : <String>[];
        final originalIndex = fallbackText.indexOf(
          originalText,
          originalSearchStart,
        );
        final originalStart = originalIndex >= 0 ? originalIndex : null;
        if (originalIndex >= 0) {
          originalSearchStart = originalIndex + originalText.length;
        }
        final correctedIndex = correctedText.indexOf(
          correctedValue,
          correctedSearchStart,
        );
        final correctedStart = correctedIndex >= 0 ? correctedIndex : null;
        if (correctedIndex >= 0) {
          correctedSearchStart = correctedIndex + correctedValue.length;
        }
        final reason = item['reason'];
        issues.add(
          WritingCorrectionIssue(
            originalText: originalText,
            correctedText: correctedValue,
            message: reason is String && reason.trim().isNotEmpty
                ? reason.trim()
                : 'Corrected wording.',
            alternatives: cleanedAlternatives,
            start: correctedStart,
            length: correctedStart == null ? null : correctedValue.length,
            originalStart: originalStart,
            originalLength: originalStart == null ? null : originalText.length,
            correctedStart: correctedStart,
            correctedLength: correctedStart == null
                ? null
                : correctedValue.length,
          ),
        );
      }
    }
    return WritingCorrectionResult(
      correctedText: correctedText,
      issues: issues,
    );
  }

  static String parseRewriteJson(String raw, {required String fallbackText}) {
    final trimmed = raw.trim();
    final decoded = _decodeObject(trimmed);
    if (decoded == null) return trimmed.isEmpty ? fallbackText : trimmed;
    final rewritten = decoded['rewritten_text'] ?? decoded['rewrittenText'];
    return rewritten is String && rewritten.trim().isNotEmpty
        ? rewritten.trim()
        : fallbackText;
  }

  static Map<String, Object?>? _decodeObject(String text) {
    final objectText = _extractJsonObject(text);
    if (objectText == null) return null;
    try {
      final decoded = jsonDecode(objectText);
      return decoded is Map<String, Object?> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inString = false;
    var escaping = false;
    for (var index = start; index < text.length; index++) {
      final char = text[index];
      if (escaping) {
        escaping = false;
        continue;
      }
      if (char == r'\') {
        escaping = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) continue;
      if (char == '{') depth++;
      if (char == '}') {
        depth--;
        if (depth == 0) {
          return text.substring(start, index + 1);
        }
      }
    }
    return null;
  }
}
