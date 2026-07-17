import 'models.dart';
import 'provider_adapter.dart';

class OpenAIProviderAdapter extends ProviderWireAdapter {
  const OpenAIProviderAdapter();

  @override
  ProviderWireRequest buildChatRequest({
    required ProviderRequestConfig config,
    required String model,
    required List<ProviderMessage> messages,
    required String schemaName,
    required Map<String, Object?> schema,
  }) {
    final body = <String, Object?>{
      'model': model,
      'messages': [
        for (final message in messages)
          {'role': message.role, 'content': message.content},
      ],
      'temperature': 0.2,
      'response_format': {
        'type': config.provider.isLocal ? 'text' : 'json_object',
      },
    };
    final reasoningEffort = _reasoningEffort(config);
    if (reasoningEffort != null) body['reasoning_effort'] = reasoningEffort;

    return ProviderWireRequest(
      uri: ProviderWireAdapter.appendEndpoints(config.baseUri, const [
        'chat',
        'completions',
      ]),
      headers: ProviderWireAdapter.requestHeaders(
        authMode: config.authMode,
        apiKey: config.apiKey,
      ),
      body: body,
      optionalFields: {
        'temperature',
        'response_format',
        if (reasoningEffort != null) 'reasoning_effort',
      },
    );
  }

  @override
  ProviderModelRequest buildModelRequest({
    required Uri baseUri,
    required ApiAuthMode authMode,
    required String apiKey,
    required String anthropicVersion,
  }) => ProviderModelRequest(
    uri: ProviderWireAdapter.appendEndpoint(baseUri, 'models'),
    headers: ProviderWireAdapter.requestHeaders(
      authMode: authMode,
      apiKey: apiKey,
    ),
  );

  @override
  String parseChatContent(String responseBody) {
    final decoded = ProviderWireAdapter.decodeObject(
      responseBody,
      context: 'chat completions endpoint',
    );
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const ProviderProtocolException(
        'Chat completion response did not contain choices.',
      );
    }
    final choice = ProviderWireAdapter.asObjectMap(choices.first);
    final finishReason = ProviderWireAdapter.nonEmptyString(
      choice?['finish_reason'],
    );
    if (finishReason == 'length') {
      throw const ProviderProtocolException(
        'The response reached the maximum output token limit.',
      );
    }
    final message = ProviderWireAdapter.asObjectMap(choice?['message']);
    final refusal = ProviderWireAdapter.nonEmptyString(message?['refusal']);
    if (refusal != null || finishReason == 'content_filter') {
      throw ProviderProtocolException(
        refusal ?? 'The provider refused to generate this response.',
      );
    }

    final content = message?['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content;
    }
    if (content is List) {
      final textBlocks = <String>[];
      for (final value in content) {
        final block = ProviderWireAdapter.asObjectMap(value);
        if (block?['type'] != 'text') continue;
        final text = ProviderWireAdapter.nonEmptyString(block?['text']);
        if (text != null) textBlocks.add(text);
      }
      if (textBlocks.isNotEmpty) return textBlocks.join('\n');
    }
    throw const ProviderProtocolException(
      'Chat completion response did not contain message content.',
    );
  }

  String? _reasoningEffort(ProviderRequestConfig config) {
    final normalized = config.reasoningEffort.trim().toLowerCase();
    if (config.provider.isLocal && normalized == 'off') return 'off';
    if (!config.reasoningEnabled || normalized.isEmpty) return null;
    if (normalized == 'none' || normalized == 'off') return null;
    if (config.provider.isLocal && normalized == 'on') return 'on';
    if (normalized == 'on') return 'minimal';
    const allowed = {'minimal', 'low', 'medium', 'high', 'xhigh'};
    return allowed.contains(normalized) ? normalized : null;
  }
}
