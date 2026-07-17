import 'dart:convert';

import 'models.dart';

class ProviderMessage {
  const ProviderMessage(this.role, this.content);

  final String role;
  final String content;
}

class ProviderWireRequest {
  const ProviderWireRequest({
    required this.uri,
    required this.headers,
    required this.body,
    required this.optionalFields,
  });

  final Uri uri;
  final Map<String, String> headers;
  final Map<String, Object?> body;
  final Set<String> optionalFields;

  ProviderWireRequest withoutOptionalFields(Iterable<String> fields) {
    final nextBody = Map<String, Object?>.from(body);
    final removed = <String>{};
    for (final field in fields) {
      if (nextBody.remove(field) != null) removed.add(field);
    }
    return ProviderWireRequest(
      uri: uri,
      headers: headers,
      body: nextBody,
      optionalFields: optionalFields.difference(removed),
    );
  }
}

class ProviderModelRequest {
  const ProviderModelRequest({required this.uri, required this.headers});

  final Uri uri;
  final Map<String, String> headers;
}

class ProviderProtocolException implements Exception {
  const ProviderProtocolException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class ProviderWireAdapter {
  const ProviderWireAdapter();

  ProviderWireRequest buildChatRequest({
    required ProviderRequestConfig config,
    required String model,
    required List<ProviderMessage> messages,
    required String schemaName,
    required Map<String, Object?> schema,
  });

  ProviderModelRequest buildModelRequest({
    required Uri baseUri,
    required ApiAuthMode authMode,
    required String apiKey,
    required String anthropicVersion,
  });

  String parseChatContent(String responseBody);

  List<String> parseModelIds(String responseBody) {
    final decoded = decodeObject(responseBody, context: 'model endpoint');
    final data = decoded['data'];
    if (data is! List) return const [];
    final result = <String>{};
    for (final value in data) {
      final item = asObjectMap(value);
      final id = item?['id'];
      if (id is String && id.trim().isNotEmpty) result.add(id.trim());
    }
    final sorted = result.toList()..sort();
    return sorted;
  }

  Set<String> unknownOptionalFields({
    required int statusCode,
    required String responseBody,
    required Set<String> candidates,
  }) {
    if (statusCode != 400 && statusCode != 422) return const {};
    final normalized = responseBody.toLowerCase();
    final reportsUnknownField = <String>[
      'unknown',
      'unsupported',
      'unrecognized',
      'unexpected',
      'not permitted',
      'extra field',
      'extra input',
      'does not support',
    ].any(normalized.contains);
    if (!reportsUnknownField) return const {};

    final result = <String>{};
    for (final field in candidates) {
      final normalizedField = field.toLowerCase();
      if (normalized.contains(normalizedField)) result.add(field);
    }
    return result;
  }

  static Map<String, String> requestHeaders({
    required ApiAuthMode authMode,
    required String apiKey,
    String? anthropicVersion,
  }) {
    final headers = <String, String>{'content-type': 'application/json'};
    final key = apiKey.trim();
    switch (authMode) {
      case ApiAuthMode.bearer:
        if (key.isNotEmpty) headers['authorization'] = 'Bearer $key';
        break;
      case ApiAuthMode.xApiKey:
        if (key.isNotEmpty) headers['x-api-key'] = key;
        break;
      case ApiAuthMode.none:
        break;
    }
    if (anthropicVersion != null) {
      final version = anthropicVersion.trim();
      headers['anthropic-version'] = version.isEmpty
          ? defaultAnthropicApiVersion
          : version;
    }
    return headers;
  }

  static Uri appendEndpoint(Uri baseUri, String segment) =>
      appendEndpoints(baseUri, [segment]);

  static Uri appendEndpoints(Uri baseUri, Iterable<String> endpointSegments) {
    final segments = baseUri.pathSegments
        .where((value) => value.isNotEmpty)
        .toList(growable: true);
    if (segments.isEmpty) segments.add('v1');
    segments.addAll(endpointSegments);
    return baseUri.replace(pathSegments: segments);
  }

  static Map<String, Object?> decodeObject(
    String body, {
    required String context,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw ProviderProtocolException('Invalid JSON from $context.');
    }
    final object = asObjectMap(decoded);
    if (object == null) {
      throw ProviderProtocolException('Invalid response from $context.');
    }
    return object;
  }

  static Map<String, Object?>? asObjectMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry('$key', value));
  }

  static String? nonEmptyString(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
