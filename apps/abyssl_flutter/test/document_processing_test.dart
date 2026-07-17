import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:abyssl_flutter/src/document_processing.dart';
import 'package:abyssl_flutter/src/models.dart';
import 'package:abyssl_flutter/src/openai_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects jobs and marks unsupported Apple document formats', () async {
    final directory = await Directory.systemTemp.createTemp('abyssl-doc-test-');
    addTearDown(() => directory.delete(recursive: true));
    final txt = File('${directory.path}/source.txt')
      ..writeAsStringSync('Hello');
    final pages = File('${directory.path}/legacy.pages')
      ..writeAsStringSync('x');

    final jobs = DocumentProcessingService.collectJobsFromPaths([
      txt.path,
      pages.path,
    ]);

    expect(jobs, hasLength(2));
    expect(jobs.first.inputKind, DocumentInputKind.pages);
    expect(jobs.first.statusMessage, isNotEmpty);
  });

  test('loads delimited text as a table and exports markdown', () async {
    final directory = await Directory.systemTemp.createTemp('abyssl-doc-test-');
    addTearDown(() => directory.delete(recursive: true));
    final csv = File('${directory.path}/table.csv')
      ..writeAsStringSync('Name,Value\nA,1\nB,2');
    final out = Directory('${directory.path}/out')..createSync();
    final service = const DocumentProcessingService();
    final job = DocumentJob(
      sourcePath: csv.path,
      inputKind: DocumentInputKind.csv,
    );

    final document = await service.loadDocument(job);
    final output = await service.exportDocument(
      document,
      job: job,
      destinationDirectory: out.path,
      options: const DocumentOperationOptions(
        shouldCorrect: false,
        shouldTranslate: false,
        exportFormat: DocumentExportFormat.markdown,
      ),
      configuration: ProviderRequestConfigFixture.value,
    );

    expect(File(output).readAsStringSync(), contains('| Name | Value |'));
  });

  test('loads DOCX text and exports text based formats', () async {
    final directory = await Directory.systemTemp.createTemp('abyssl-doc-test-');
    addTearDown(() => directory.delete(recursive: true));
    final docx = File('${directory.path}/sample.docx');
    await _writeZip(docx.path, {
      '[Content_Types].xml':
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
      '_rels/.rels':
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>',
      'word/document.xml': '''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
<w:p><w:r><w:t>Hello document</w:t></w:r></w:p>
<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell A</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Cell B</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
</w:body>
</w:document>
''',
    });
    final out = Directory('${directory.path}/out')..createSync();
    final service = const DocumentProcessingService();
    final job = DocumentJob(
      sourcePath: docx.path,
      inputKind: DocumentInputKind.docx,
    );
    final document = await service.loadDocument(job);

    expect(document.plainText, contains('Hello document'));
    expect(document.plainText, contains('Cell A'));

    for (final format in [
      DocumentExportFormat.plainText,
      DocumentExportFormat.html,
      DocumentExportFormat.asciidoc,
      DocumentExportFormat.rtf,
      DocumentExportFormat.docx,
      DocumentExportFormat.pdf,
    ]) {
      final output = await service.exportDocument(
        document,
        job: job,
        destinationDirectory: out.path,
        options: DocumentOperationOptions(
          shouldCorrect: false,
          shouldTranslate: false,
          exportFormat: format,
        ),
        configuration: ProviderRequestConfigFixture.value,
      );
      expect(File(output).existsSync(), isTrue, reason: format.name);
    }
  });

  test('loads XLSX shared strings as a table', () async {
    final directory = await Directory.systemTemp.createTemp('abyssl-doc-test-');
    addTearDown(() => directory.delete(recursive: true));
    final xlsx = File('${directory.path}/sample.xlsx');
    await _writeZip(xlsx.path, {
      'xl/workbook.xml':
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>',
      'xl/sharedStrings.xml': '''
<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<si><t>Name</t></si><si><t>Value</t></si><si><t>Älpha</t></si>
</sst>
''',
      'xl/worksheets/sheet1.xml': '''
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<sheetData>
<row><c t="s"><v>0</v></c><c t="s"><v>1</v></c></row>
<row><c t="s"><v>2</v></c><c><v>42</v></c></row>
</sheetData>
</worksheet>
''',
    });
    final service = const DocumentProcessingService();
    final document = await service.loadDocument(
      DocumentJob(sourcePath: xlsx.path, inputKind: DocumentInputKind.xlsx),
    );

    expect(document.plainText, contains('Name\tValue'));
    expect(document.plainText, contains('Älpha\t42'));
  });

  test('limits spreadsheet export formats to compatible outputs', () {
    expect(
      DocumentProcessingService.availableExportFormats(
        hasSpreadsheetInput: true,
      ),
      [
        DocumentExportFormat.pdf,
        DocumentExportFormat.html,
        DocumentExportFormat.plainText,
      ],
    );
  });

  for (final provider in [
    TranslationProvider.openAICompatible,
    TranslationProvider.anthropicCompatible,
  ]) {
    test('processes document text through ${provider.name}', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final operations = <String>[];
      unawaited(
        server.forEach((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, Object?>;
          final system = provider.compatibility == ApiCompatibility.openAI
              ? '${((body['messages'] as List).first as Map)['content']}'
              : '${body['system']}';
          final isCorrection = system.contains('copy editor');
          operations.add(isCorrection ? 'correct' : 'translate');
          final content = isCorrection
              ? jsonEncode({
                  'corrected_text': 'Hello',
                  'corrections': <Object?>[],
                })
              : jsonEncode({
                  'translation': 'Hallo',
                  'synonyms': <String>[],
                  'spelling_notes': null,
                  'revised_source': null,
                });
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode(
              provider.compatibility == ApiCompatibility.openAI
                  ? {
                      'choices': [
                        {
                          'finish_reason': 'stop',
                          'message': {'content': content},
                        },
                      ],
                    }
                  : {
                      'content': [
                        {'type': 'text', 'text': content},
                      ],
                      'stop_reason': 'end_turn',
                    },
            ),
          );
          await request.response.close();
        }),
      );

      final result = await const DocumentProcessingService().processDocument(
        const DocumentIR(
          blocks: [DocumentParagraph('Helo')],
          sourceKind: DocumentInputKind.plainText,
        ),
        const DocumentOperationOptions(
          shouldCorrect: true,
          shouldTranslate: true,
          exportFormat: DocumentExportFormat.plainText,
        ),
        DocumentProcessingConfiguration(
          requestConfig: ProviderRequestConfig(
            provider: provider,
            baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
            modelId: provider == TranslationProvider.anthropicCompatible
                ? 'claude-test'
                : 'gpt-test',
            authMode: ApiAuthMode.none,
            apiKey: '',
            sourceLanguage: TranslationLanguage.automatic,
            targetLanguage: TranslationLanguage.german,
            style: const StyleSettings(),
            reasoningEnabled: false,
            reasoningEffort: 'none',
            correctionAlternativeCount: 3,
          ),
          apiClient: AbyssLApiClient(),
        ),
      );

      expect((result.blocks.single as DocumentParagraph).text, 'Hallo');
      expect(operations, ['correct', 'translate']);
    });
  }
}

Future<void> _writeZip(String path, Map<String, String> entries) async {
  final archive = Archive();
  for (final entry in entries.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  await File(path).writeAsBytes(ZipEncoder().encode(archive));
}

class ProviderRequestConfigFixture {
  static final value = ProviderRequestConfig(
    provider: TranslationProvider.openAICompatible,
    baseUri: Uri.parse('https://api.openai.com/v1'),
    modelId: 'gpt-4o-mini',
    authMode: ApiAuthMode.bearer,
    apiKey: 'test',
    sourceLanguage: TranslationLanguage.automatic,
    targetLanguage: TranslationLanguage.englishUS,
    style: const StyleSettings(),
    reasoningEnabled: false,
    reasoningEffort: 'none',
    correctionAlternativeCount: 3,
  );
}
