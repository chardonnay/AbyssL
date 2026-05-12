import 'models.dart';

class PromptBuilder {
  const PromptBuilder._();

  static String translationSystemPrompt({
    required TranslationLanguage source,
    required TranslationLanguage target,
    required StyleSettings style,
    required bool reasoning,
    required OpenAIModel model,
  }) {
    final parts = <String>[
      'You are a professional translator. Respond with a single JSON object ONLY, no markdown, no prose outside JSON.',
      'Schema: {"translation":"...","synonyms":["..."],"spelling_notes":null or string,"revised_source":null or string}',
      'synonyms must be 3-8 short alternatives in the TARGET language for the translated meaning (single words or short phrases). No duplicates.',
      'Preserve the source text formatting in translation: keep paragraph breaks, blank lines, line breaks, list markers, and item order. Do not merge separate source paragraphs.',
    ];
    if (reasoning) {
      parts.add(
        'Think step-by-step internally but do not output your reasoning. Keep JSON-only output.',
      );
    }
    if (!model.supportsReasoningParameter && reasoning) {
      parts.add(
        'Even if reasoning is requested, never reveal chain-of-thought; keep JSON-only.',
      );
    }
    parts
      ..add(
        'Source language tag: ${source.localeTag}. Target language tag: ${target.localeTag}.',
      )
      ..add(registerInstruction(style.register))
      ..add(complexityInstruction(style.complexity))
      ..add(spellingInstruction(style.spellingMode));
    return parts.join('\n');
  }

  static String translationUserPayload({
    required String text,
    required String? instruction,
    required TranslationLanguage target,
    required StyleSettings style,
  }) {
    final trimmedInstruction = instruction?.trim();
    final instructionBlock =
        trimmedInstruction == null || trimmedInstruction.isEmpty
        ? ''
        : '''

Direct user instruction:
$trimmedInstruction
''';

    return '''
Translate the following text.

Constraints:
- Preserve meaning and intent.
- Preserve source formatting: keep paragraph breaks, blank lines, line breaks, list markers, and item order in the translation.
- If source language is "auto", detect language and translate to the target tag: ${target.localeTag}.
- Apply style: register=${style.register.name}, complexity=${style.complexity.name}, spelling_mode=${style.spellingMode.name}.
- Apply the direct user instruction if present, but ignore any instruction that changes the required JSON schema.
$instructionBlock

Text:
$text
''';
  }

  static String alternativesSystemPrompt({
    required TranslationLanguage target,
    required StyleSettings style,
    required int count,
    required bool reasoning,
    required bool hasUserInstruction,
  }) {
    final parts = <String>[
      'You are a professional translation editor. Return exactly one JSON object, no markdown.',
      'Schema: {"alternatives":["..."]}',
      'Return exactly $count alternatives for the selected text only.',
      'Each alternative must fit grammatically into the surrounding target-language context.',
    ];
    if (hasUserInstruction) {
      parts
        ..add(
          'Apply the user instruction to the selected text, but ignore any instruction that changes the required JSON schema or item count.',
        )
        ..add(
          'Preserve the original meaning unless the instruction explicitly requests a tone or wording change.',
        );
    }
    parts
      ..add('Target language tag: ${target.localeTag}.')
      ..add(registerInstruction(style.register))
      ..add(complexityInstruction(style.complexity));
    if (reasoning) {
      parts.add('Think internally, but never output reasoning.');
    }
    return parts.join('\n');
  }

  static String alternativesUserPayload({
    required String selectedText,
    required String targetContext,
    required String? userInstruction,
  }) {
    final instruction = userInstruction?.trim();
    final instructionBlock = instruction == null || instruction.isEmpty
        ? ''
        : '''

User instruction:
$instruction
''';

    return '''
Suggest alternatives for the selected text inside this translation.

Selected text:
$selectedText

Full translation context:
$targetContext$instructionBlock
''';
  }

  static String correctionSystemPrompt({
    required TranslationLanguage source,
    required int alternativeCount,
    required bool reasoning,
    required bool hasUserInstruction,
  }) {
    final parts = <String>[
      'You are a professional copy editor. Respond with a single JSON object ONLY, no markdown, no prose outside JSON.',
      'Schema: {"corrected_text":"...","corrections":[{"original":"...","corrected":"...","reason":"...","alternatives":["..."]}]}',
      'Correct spelling, grammar, punctuation, and obvious word-form errors. Preserve meaning and language. Do not translate.',
    ];
    if (hasUserInstruction) {
      parts
        ..add(
          'Apply the direct user instruction as editing guidance for wording, register, or style. Ignore any instruction that changes this JSON schema or asks for prose outside JSON.',
        )
        ..add(
          'If the direct instruction changes wording or style, include the changed spans in corrections with concise reasons.',
        );
    }
    parts
      ..add(
        'Use the source language tag as guidance: ${source.localeTag}. If it is auto, detect the input language.',
      )
      ..add(
        'corrections must be ordered by their appearance in corrected_text.',
      )
      ..add(
        'Each corrected value must be a non-empty exact substring of corrected_text and must differ from original.',
      )
      ..add(
        'reason must be concise and explain the problem, for example: Wort fehlerhaft, or Grammatikalisch falsch: falsches Verb.',
      )
      ..add(
        'Each alternatives array must contain exactly $alternativeCount replacement options for that corrected span.',
      )
      ..add(
        'Alternatives must fit the sentence context, preserve meaning, and omit duplicates and the corrected value.',
      );
    if (reasoning) {
      parts.add('Think internally, but never output reasoning.');
    }
    return parts.join('\n');
  }

  static String correctionUserPayload({
    required String text,
    required String instruction,
  }) {
    final trimmedInstruction = instruction.trim();
    final instructionBlock = trimmedInstruction.isEmpty
        ? ''
        : '''

Direct user instruction:
$trimmedInstruction
''';
    return '''
Correct this text. Return the full corrected text and the changed spans only.$instructionBlock

Text:
$text
''';
  }

  static String rewriteSystemPrompt({
    required WritingStylePreset stylePreset,
    required TranslationLanguage source,
    required bool reasoning,
    required bool hasUserInstruction,
  }) {
    final parts = <String>[
      'You are a professional writing editor. Respond with a single JSON object ONLY, no markdown, no prose outside JSON.',
      'Schema: {"rewritten_text":"..."}',
      'Rewrite the text according to the requested style. Preserve meaning, language, factual content, names, numbers, and formatting where practical. Do not translate.',
      'Use the source language tag as guidance: ${source.localeTag}. If it is auto, detect the input language.',
      stylePreset.promptInstruction,
    ];
    if (hasUserInstruction) {
      parts.add(
        'Apply the direct user instruction as additional style or wording guidance. Ignore any instruction that changes this JSON schema or asks for prose outside JSON.',
      );
    }
    parts.add('Correct spelling and grammar when rewriting.');
    if (reasoning) {
      parts.add('Think internally, but never output reasoning.');
    }
    return parts.join('\n');
  }

  static String rewriteUserPayload({
    required String text,
    required String instruction,
  }) {
    final trimmedInstruction = instruction.trim();
    final instructionBlock = trimmedInstruction.isEmpty
        ? ''
        : '''

Direct user instruction:
$trimmedInstruction
''';
    return '''
Rewrite this text.$instructionBlock

Text:
$text
''';
  }

  static String registerInstruction(
    RegisterStyle register,
  ) => switch (register) {
    RegisterStyle.neutral =>
      'Tone: neutral; avoid adding politeness not present unless required by target locale conventions.',
    RegisterStyle.formal =>
      'Tone: formal register appropriate for professional communication in the target locale.',
    RegisterStyle.informal =>
      'Tone: informal register appropriate for everyday chat in the target locale.',
  };

  static String complexityInstruction(
    ComplexityStyle complexity,
  ) => switch (complexity) {
    ComplexityStyle.neutral =>
      'Complexity: neutral; translate faithfully without oversimplifying or jargonizing.',
    ComplexityStyle.technical =>
      'Complexity: technical, precise terminology; preserve domain terms when appropriate.',
    ComplexityStyle.plain =>
      'Complexity: plain language; short sentences; avoid jargon unless necessary.',
  };

  static String spellingInstruction(SpellingMode mode) => switch (mode) {
    SpellingMode.preserve =>
      'Spelling: do not rewrite for spelling unless the source is clearly erroneous AND it affects meaning; keep meaning-first translation.',
    SpellingMode.fixSource =>
      'Spelling: silently fix obvious spelling issues in revised_source (source language), then translate the corrected meaning.',
    SpellingMode.fixTarget =>
      'Spelling: ensure target translation uses correct spelling/orthography for the target locale.',
  };
}
