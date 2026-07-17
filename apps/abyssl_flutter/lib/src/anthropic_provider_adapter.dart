import 'models.dart';
import 'provider_adapter.dart';

class AnthropicProviderAdapter extends ProviderWireAdapter {
  const AnthropicProviderAdapter();

  @override
  ProviderWireRequest buildChatRequest({
    required ProviderRequestConfig config,
    required String model,
    required List<ProviderMessage> messages,
    required String schemaName,
    required Map<String, Object?> schema,
  }) {
    final system = messages
        .where((message) => message.role == 'system')
        .map((message) => message.content)
        .join('\n\n');
    final conversation = messages
        .where((message) => message.role != 'system')
        .map(
          (message) => <String, Object?>{
            'role': message.role,
            'content': message.content,
          },
        )
        .toList(growable: false);
    final body = <String, Object?>{
      'model': model,
      'max_tokens': config.maxOutputTokens,
      'temperature': 0.2,
      if (system.isNotEmpty) 'system': system,
      'messages': conversation,
      'output_config': {
        'format': {'type': 'json_schema', 'schema': schema},
      },
    };

    return ProviderWireRequest(
      uri: ProviderWireAdapter.appendEndpoint(config.baseUri, 'messages'),
      headers: ProviderWireAdapter.requestHeaders(
        authMode: config.authMode,
        apiKey: config.apiKey,
        anthropicVersion: config.anthropicVersion,
      ),
      body: body,
      optionalFields: const {'temperature', 'output_config'},
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
      anthropicVersion: anthropicVersion,
    ),
  );

  @override
  String parseChatContent(String responseBody) {
    final decoded = ProviderWireAdapter.decodeObject(
      responseBody,
      context: 'Anthropic messages endpoint',
    );
    final stopReason = ProviderWireAdapter.nonEmptyString(
      decoded['stop_reason'],
    );
    if (stopReason == 'max_tokens') {
      throw const ProviderProtocolException(
        'The response reached the maximum output token limit.',
      );
    }
    if (stopReason == 'refusal') {
      throw const ProviderProtocolException(
        'The provider refused to generate this response.',
      );
    }

    final content = decoded['content'];
    if (content is! List) {
      throw const ProviderProtocolException(
        'Anthropic response did not contain content blocks.',
      );
    }
    final textBlocks = <String>[];
    for (final value in content) {
      final block = ProviderWireAdapter.asObjectMap(value);
      final type = block?['type'];
      if (type == 'refusal') {
        final refusal = ProviderWireAdapter.nonEmptyString(
          block?['refusal'] ?? block?['text'],
        );
        throw ProviderProtocolException(
          refusal ?? 'The provider refused to generate this response.',
        );
      }
      if (type != 'text') continue;
      final text = ProviderWireAdapter.nonEmptyString(block?['text']);
      if (text != null) textBlocks.add(text);
    }
    if (textBlocks.isEmpty) {
      throw const ProviderProtocolException(
        'Anthropic response did not contain text content.',
      );
    }
    return textBlocks.join('\n');
  }

  @override
  Set<String> unknownOptionalFields({
    required int statusCode,
    required String responseBody,
    required Set<String> candidates,
  }) {
    final result = super.unknownOptionalFields(
      statusCode: statusCode,
      responseBody: responseBody,
      candidates: candidates,
    );
    if (!candidates.contains('output_config') ||
        (statusCode != 400 && statusCode != 422)) {
      return result;
    }
    final normalized = responseBody.toLowerCase();
    final unknown = <String>[
      'unknown',
      'unsupported',
      'unrecognized',
      'unexpected',
      'not permitted',
      'extra field',
      'extra input',
      'does not support',
    ].any(normalized.contains);
    if (unknown && normalized.contains('format')) {
      return {...result, 'output_config'};
    }
    return result;
  }
}
