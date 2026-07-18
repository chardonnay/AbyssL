import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import 'models.dart';
import 'openai_client.dart';

class DocumentProcessingException implements Exception {
  const DocumentProcessingException(this.message);
  final String message;

  @override
  String toString() => message;
}

class DocumentProcessingConfiguration {
  const DocumentProcessingConfiguration({
    required this.requestConfig,
    required this.apiClient,
  });

  final ProviderRequestConfig requestConfig;
  final AbyssLApiClient apiClient;
}

class DocumentBatchProgress {
  const DocumentBatchProgress({
    required this.total,
    required this.completed,
    required this.isRunning,
    this.currentFile,
  });

  final int total;
  final int completed;
  final bool isRunning;
  final String? currentFile;
}

typedef DocumentProgressCallback =
    void Function(DocumentBatchProgress progress);

class DocumentProcessingService {
  const DocumentProcessingService();

  static const _documentChannel = MethodChannel(
    'org.abyssl.translator/document',
  );

  static DocumentInputKind inputKindForPath(String path) =>
      DocumentInputKind.fromExtension(p.extension(path).replaceFirst('.', ''));

  static bool isKindSupported(DocumentInputKind kind) => switch (kind) {
    DocumentInputKind.plainText ||
    DocumentInputKind.markdown ||
    DocumentInputKind.asciidoc ||
    DocumentInputKind.html ||
    DocumentInputKind.rtf ||
    DocumentInputKind.pdf ||
    DocumentInputKind.csv ||
    DocumentInputKind.tsv ||
    DocumentInputKind.docx ||
    DocumentInputKind.xlsx => true,
    DocumentInputKind.odt => findSofficeSync() != null,
    DocumentInputKind.pages ||
    DocumentInputKind.numbers ||
    DocumentInputKind.unsupported => false,
  };

  static String unavailableReason(DocumentInputKind kind) => switch (kind) {
    DocumentInputKind.odt =>
      'ODT requires LibreOffice soffice; no safe local converter was found.',
    DocumentInputKind.pages =>
      'Pages files are not supported by the cross-platform document path.',
    DocumentInputKind.numbers =>
      'Numbers files are not supported by the cross-platform document path.',
    DocumentInputKind.unsupported => 'Unsupported file type.',
    _ => '',
  };

  static List<DocumentExportFormat> availableExportFormats({
    required bool hasSpreadsheetInput,
  }) {
    if (hasSpreadsheetInput) {
      return const [
        DocumentExportFormat.pdf,
        DocumentExportFormat.html,
        DocumentExportFormat.plainText,
      ];
    }
    final formats = <DocumentExportFormat>[
      DocumentExportFormat.pdf,
      DocumentExportFormat.docx,
      if (findSofficeSync() != null) DocumentExportFormat.odt,
      DocumentExportFormat.markdown,
      DocumentExportFormat.html,
      DocumentExportFormat.asciidoc,
      DocumentExportFormat.plainText,
      DocumentExportFormat.rtf,
    ];
    return formats;
  }

  static List<DocumentJob> collectJobsFromPaths(List<String> paths) {
    final jobs = <DocumentJob>[];
    for (final path in paths) {
      final entityType = FileSystemEntity.typeSync(path);
      if (entityType == FileSystemEntityType.directory) {
        jobs.addAll(_collectDirectoryJobs(path));
      } else if (entityType == FileSystemEntityType.file) {
        final kind = inputKindForPath(path);
        jobs.add(
          DocumentJob(
            sourcePath: path,
            inputKind: kind,
            statusMessage: isKindSupported(kind)
                ? null
                : unavailableReason(kind),
          ),
        );
      }
    }
    jobs.sort((left, right) => left.sourcePath.compareTo(right.sourcePath));
    return jobs;
  }

  static List<DocumentJob> _collectDirectoryJobs(String rootPath) {
    final root = Directory(rootPath);
    if (!root.existsSync()) return const [];
    final jobs = <DocumentJob>[];
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      final kind = inputKindForPath(entity.path);
      jobs.add(
        DocumentJob(
          sourcePath: entity.path,
          rootPath: rootPath,
          inputKind: kind,
          statusMessage: isKindSupported(kind) ? null : unavailableReason(kind),
        ),
      );
    }
    return jobs;
  }

  Future<List<DocumentProcessingResult>> process({
    required List<DocumentJob> jobs,
    required String destinationDirectory,
    required DocumentOperationOptions options,
    required DocumentProcessingConfiguration configuration,
    DocumentProgressCallback? onProgress,
  }) async {
    final results = <DocumentProcessingResult>[];
    onProgress?.call(
      DocumentBatchProgress(total: jobs.length, completed: 0, isRunning: true),
    );
    var completed = 0;
    for (final job in jobs) {
      onProgress?.call(
        DocumentBatchProgress(
          total: jobs.length,
          completed: completed,
          isRunning: true,
          currentFile: job.displayName,
        ),
      );
      try {
        if (!isKindSupported(job.inputKind)) {
          throw DocumentProcessingException(
            job.statusMessage ?? unavailableReason(job.inputKind),
          );
        }
        if (!availableExportFormats(
          hasSpreadsheetInput: job.inputKind.isSpreadsheet,
        ).contains(options.exportFormat)) {
          throw DocumentProcessingException(
            exportUnavailableReason(options.exportFormat),
          );
        }
        var document = await loadDocument(job);
        document = await processDocument(document, options, configuration);
        final outputPath = await exportDocument(
          document,
          job: job,
          destinationDirectory: destinationDirectory,
          options: options,
          configuration: configuration.requestConfig,
        );
        results.add(
          DocumentProcessingResult(
            sourcePath: job.sourcePath,
            outputPath: outputPath,
            status: DocumentResultStatus.success,
            message: 'Processed',
          ),
        );
      } on AbyssLRequestCancelledException {
        rethrow;
      } catch (error) {
        results.add(
          DocumentProcessingResult(
            sourcePath: job.sourcePath,
            status: DocumentResultStatus.failed,
            message: '$error',
          ),
        );
      }
      completed++;
      onProgress?.call(
        DocumentBatchProgress(
          total: jobs.length,
          completed: completed,
          isRunning: true,
          currentFile: job.displayName,
        ),
      );
    }
    onProgress?.call(
      DocumentBatchProgress(
        total: jobs.length,
        completed: completed,
        isRunning: false,
      ),
    );
    return results;
  }

  Future<DocumentIR> processDocument(
    DocumentIR document,
    DocumentOperationOptions options,
    DocumentProcessingConfiguration configuration,
  ) async {
    final blocks = <DocumentBlock>[];
    for (final block in document.blocks) {
      switch (block) {
        case DocumentParagraph(:final text):
          blocks.add(
            DocumentParagraph(
              await _processTextIfNeeded(text, options, configuration),
            ),
          );
        case DocumentTable(:final rows):
          final nextRows = <List<String>>[];
          for (final row in rows) {
            final nextRow = <String>[];
            for (final cell in row) {
              if (_shouldProcessTableCell(cell)) {
                nextRow.add(
                  await _processTextIfNeeded(cell, options, configuration),
                );
              } else {
                nextRow.add(cell);
              }
            }
            nextRows.add(nextRow);
          }
          blocks.add(DocumentTable(nextRows));
      }
    }
    return DocumentIR(
      blocks: blocks,
      sourceKind: document.sourceKind,
      images: document.images,
    );
  }

  Future<String> _processTextIfNeeded(
    String text,
    DocumentOperationOptions options,
    DocumentProcessingConfiguration configuration,
  ) async {
    if (text.trim().isEmpty) return text;
    var current = text;
    if (options.shouldCorrect) {
      current = (await configuration.apiClient.correctWriting(
        text: current,
        instruction: options.instruction,
        config: configuration.requestConfig,
      )).correctedText;
    }
    if (options.shouldTranslate) {
      current = (await configuration.apiClient.translate(
        text: current,
        instruction: options.instruction,
        config: configuration.requestConfig,
      )).translation;
    }
    return current;
  }

  bool _shouldProcessTableCell(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.startsWith('=')) return false;
    if (double.tryParse(trimmed.replaceAll(',', '.')) != null) return false;
    return RegExp(r'[A-Za-z\p{L}]', unicode: true).hasMatch(trimmed);
  }

  Future<DocumentIR> loadDocument(DocumentJob job) async {
    return switch (job.inputKind) {
      DocumentInputKind.plainText ||
      DocumentInputKind.markdown ||
      DocumentInputKind.asciidoc => _loadPlainText(
        job.sourcePath,
        job.inputKind,
      ),
      DocumentInputKind.html => _loadHtml(job.sourcePath),
      DocumentInputKind.rtf => _loadRtf(job.sourcePath),
      DocumentInputKind.pdf => _loadPdf(job.sourcePath),
      DocumentInputKind.docx => _loadDocx(job.sourcePath),
      DocumentInputKind.odt => _loadOdt(job.sourcePath),
      DocumentInputKind.csv => _loadDelimited(
        job.sourcePath,
        ',',
        DocumentInputKind.csv,
      ),
      DocumentInputKind.tsv => _loadDelimited(
        job.sourcePath,
        '\t',
        DocumentInputKind.tsv,
      ),
      DocumentInputKind.xlsx => _loadXlsx(job.sourcePath),
      DocumentInputKind.pages ||
      DocumentInputKind.numbers ||
      DocumentInputKind.unsupported => throw DocumentProcessingException(
        unavailableReason(job.inputKind),
      ),
    };
  }

  Future<DocumentIR> _loadPlainText(String path, DocumentInputKind kind) async {
    final text = await File(path).readAsString();
    return DocumentIR(blocks: _paragraphs(text), sourceKind: kind);
  }

  Future<DocumentIR> _loadHtml(String path) async {
    final text = await File(path).readAsString();
    final withoutScripts = text
        .replaceAll(
          RegExp(
            r'<script\b[^>]*>.*?</script>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<style\b[^>]*>.*?</style>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        );
    final plain = withoutScripts
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');
    return DocumentIR(
      blocks: _paragraphs(_decodeHtmlEntities(plain)),
      sourceKind: DocumentInputKind.html,
    );
  }

  Future<DocumentIR> _loadRtf(String path) async {
    final text = await File(path).readAsString();
    final plain = text
        .replaceAll(RegExp(r'\\par[d]?'), '\n')
        .replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '')
        .replaceAll(RegExp(r'[{}]'), '')
        .replaceAll(r"\'", '');
    return DocumentIR(
      blocks: _paragraphs(plain),
      sourceKind: DocumentInputKind.rtf,
    );
  }

  Future<DocumentIR> _loadPdf(String path) async {
    final native = await _tryNativePdfExtraction(path);
    if (native != null && native.trim().isNotEmpty) {
      return DocumentIR(
        blocks: _paragraphs(native),
        sourceKind: DocumentInputKind.pdf,
      );
    }
    final tool = await _findExecutable(['pdftotext', 'mutool']);
    if (tool == null) {
      throw const DocumentProcessingException(
        'PDF text extraction is unavailable in this build. On macOS, rebuild and restart AbyssL to enable its built-in PDF reader. On other platforms, install Poppler (pdftotext) or MuPDF (mutool) and make it available on PATH. Scanned PDFs additionally require OCR.',
      );
    }
    final result = tool.endsWith('mutool') || p.basename(tool) == 'mutool'
        ? await Process.run(tool, ['draw', '-F', 'text', path])
        : await Process.run(tool, ['-layout', path, '-']);
    if (result.exitCode != 0) {
      throw DocumentProcessingException(
        '${result.stderr}'.trim().isEmpty
            ? 'PDF text extraction failed.'
            : '${result.stderr}',
      );
    }
    final text = '${result.stdout}'.trim();
    if (text.isEmpty) {
      throw const DocumentProcessingException(
        'Scanned PDFs without extractable text are not supported.',
      );
    }
    return DocumentIR(
      blocks: _paragraphs(text),
      sourceKind: DocumentInputKind.pdf,
    );
  }

  Future<String?> _tryNativePdfExtraction(String path) async {
    if (!Platform.isMacOS) return null;
    try {
      return await _documentChannel.invokeMethod<String>('extractPdfText', {
        'path': path,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      throw DocumentProcessingException(
        error.message ?? 'Native PDF extraction failed.',
      );
    }
  }

  Future<DocumentIR> _loadDocx(String path) async {
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final documentXml = _archiveString(archive, 'word/document.xml');
    if (documentXml == null) {
      throw const DocumentProcessingException(
        'DOCX document.xml was not found.',
      );
    }
    final blocks = _parseDocxBlocks(documentXml);
    if (blocks.isEmpty) {
      throw const DocumentProcessingException('Document is empty.');
    }
    final images = archive.files
        .where((file) => file.isFile && file.name.startsWith('word/media/'))
        .map(
          (file) => DocumentImageAsset(
            suggestedFilename: p.basename(file.name),
            data: List<int>.from(file.content as List<int>),
          ),
        )
        .toList();
    return DocumentIR(
      blocks: blocks,
      images: images,
      sourceKind: DocumentInputKind.docx,
    );
  }

  Future<DocumentIR> _loadOdt(String path) async {
    final soffice = findSofficeSync();
    if (soffice == null) {
      throw DocumentProcessingException(
        unavailableReason(DocumentInputKind.odt),
      );
    }
    final tempDir = await Directory.systemTemp.createTemp('abyssl-odt-import-');
    try {
      final result = await Process.run(soffice, [
        '--headless',
        '--convert-to',
        'txt:Text',
        '--outdir',
        tempDir.path,
        path,
      ]);
      if (result.exitCode != 0) {
        throw DocumentProcessingException(
          '${result.stderr}'.trim().isEmpty
              ? 'ODT conversion failed.'
              : '${result.stderr}',
        );
      }
      final txtPath = p.join(
        tempDir.path,
        '${p.basenameWithoutExtension(path)}.txt',
      );
      if (!File(txtPath).existsSync()) {
        throw const DocumentProcessingException(
          'ODT conversion did not produce a text file.',
        );
      }
      return _loadPlainText(txtPath, DocumentInputKind.odt);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<DocumentIR> _loadDelimited(
    String path,
    String delimiter,
    DocumentInputKind kind,
  ) async {
    final text = await File(path).readAsString();
    return DocumentIR(
      blocks: [DocumentTable(_parseDelimited(text, delimiter))],
      sourceKind: kind,
    );
  }

  Future<DocumentIR> _loadXlsx(String path) async {
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    if (_archiveString(archive, 'xl/workbook.xml') == null) {
      throw const DocumentProcessingException(
        'XLSX workbook.xml was not found.',
      );
    }
    final sharedStrings = _parseSharedStrings(
      _archiveString(archive, 'xl/sharedStrings.xml') ?? '',
    );
    final sheet = archive.files
        .where(
          (file) =>
              file.name.startsWith('xl/worksheets/sheet') &&
              file.name.endsWith('.xml'),
        )
        .map((file) => file.name)
        .firstOrNull;
    if (sheet == null) {
      throw const DocumentProcessingException(
        'XLSX worksheet XML was not found.',
      );
    }
    final table = _parseSheet(
      _archiveString(archive, sheet) ?? '',
      sharedStrings,
    );
    if (table.isEmpty) {
      throw const DocumentProcessingException('Spreadsheet is empty.');
    }
    return DocumentIR(
      blocks: [DocumentTable(table)],
      sourceKind: DocumentInputKind.xlsx,
    );
  }

  List<DocumentBlock> _parseDocxBlocks(String xml) {
    final root = XmlDocument.parse(xml);
    final blocks = <DocumentBlock>[];
    for (final node in root.descendants.whereType<XmlElement>()) {
      if (_localName(node) != 'body') continue;
      for (final child in node.childElements) {
        if (_localName(child) == 'p') {
          final text = _paragraphText(child).trim();
          if (text.isNotEmpty) blocks.add(DocumentParagraph(text));
        } else if (_localName(child) == 'tbl') {
          final rows = child.childElements
              .where((element) => _localName(element) == 'tr')
              .map((row) {
                return row.childElements
                    .where((element) => _localName(element) == 'tc')
                    .map((cell) => _paragraphText(cell).trim())
                    .toList();
              })
              .toList();
          if (rows.isNotEmpty) blocks.add(DocumentTable(rows));
        }
      }
      break;
    }
    return blocks;
  }

  String _paragraphText(XmlElement element) {
    final buffer = StringBuffer();
    for (final descendant in element.descendants.whereType<XmlElement>()) {
      if (_localName(descendant) == 'br') {
        buffer.write('\n');
      } else if (_localName(descendant) == 't') {
        buffer.write(descendant.innerText);
      }
    }
    return buffer.toString();
  }

  List<String> _parseSharedStrings(String xml) {
    if (xml.trim().isEmpty) return const [];
    final document = XmlDocument.parse(xml);
    return document.descendants
        .whereType<XmlElement>()
        .where((element) => _localName(element) == 'si')
        .map((si) {
          return si.descendants
              .whereType<XmlElement>()
              .where((element) => _localName(element) == 't')
              .map((element) => element.innerText)
              .join();
        })
        .toList();
  }

  List<List<String>> _parseSheet(String xml, List<String> sharedStrings) {
    final document = XmlDocument.parse(xml);
    final rows = <List<String>>[];
    for (final row in document.descendants.whereType<XmlElement>().where(
      (element) => _localName(element) == 'row',
    )) {
      final values = <String>[];
      for (final cell in row.childElements.where(
        (element) => _localName(element) == 'c',
      )) {
        final type = cell.getAttribute('t');
        final value =
            cell.childElements
                .where((element) => _localName(element) == 'v')
                .firstOrNull
                ?.innerText ??
            '';
        if (type == 's') {
          final index = int.tryParse(value);
          values.add(
            index == null || index < 0 || index >= sharedStrings.length
                ? ''
                : sharedStrings[index],
          );
        } else if (type == 'inlineStr') {
          values.add(
            cell.descendants
                .whereType<XmlElement>()
                .where((element) => _localName(element) == 't')
                .map((element) => element.innerText)
                .join(),
          );
        } else {
          values.add(value);
        }
      }
      if (values.any((value) => value.trim().isNotEmpty)) rows.add(values);
    }
    return rows;
  }

  Future<String> exportDocument(
    DocumentIR document, {
    required DocumentJob job,
    required String destinationDirectory,
    required DocumentOperationOptions options,
    required ProviderRequestConfig configuration,
  }) async {
    final relativeDirectory = _relativeDirectoryForOutput(job);
    final outputDirectory = Directory(
      p.join(destinationDirectory, relativeDirectory),
    );
    await outputDirectory.create(recursive: true);
    return switch (options.exportFormat) {
      DocumentExportFormat.plainText => _writeTextExport(
        document.plainText,
        job,
        outputDirectory.path,
        options,
        configuration,
        DocumentExportFormat.plainText,
      ),
      DocumentExportFormat.markdown => _writeTextExport(
        _renderMarkdown(document),
        job,
        outputDirectory.path,
        options,
        configuration,
        DocumentExportFormat.markdown,
      ),
      DocumentExportFormat.html => _writeTextExport(
        _renderHtml(document),
        job,
        outputDirectory.path,
        options,
        configuration,
        DocumentExportFormat.html,
      ),
      DocumentExportFormat.asciidoc => _exportAsciiDoc(
        document,
        job,
        outputDirectory.path,
        options,
        configuration,
      ),
      DocumentExportFormat.rtf => _writeTextExport(
        _renderRtf(document),
        job,
        outputDirectory.path,
        options,
        configuration,
        DocumentExportFormat.rtf,
      ),
      DocumentExportFormat.pdf => _exportPdf(
        document,
        job,
        outputDirectory.path,
        options,
        configuration,
      ),
      DocumentExportFormat.docx => _exportDocx(
        document,
        job,
        outputDirectory.path,
        options,
        configuration,
      ),
      DocumentExportFormat.odt => _exportOdt(
        document,
        job,
        outputDirectory.path,
        options,
        configuration,
      ),
      DocumentExportFormat.pages ||
      DocumentExportFormat.numbers => throw DocumentProcessingException(
        exportUnavailableReason(options.exportFormat),
      ),
    };
  }

  Future<String> _writeTextExport(
    String content,
    DocumentJob job,
    String outputDirectory,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
    DocumentExportFormat format,
  ) async {
    final output = _uniqueOutputPath(
      job,
      outputDirectory,
      options,
      configuration,
      format.fileExtension,
    );
    await File(output).writeAsString(content);
    return output;
  }

  Future<String> _exportAsciiDoc(
    DocumentIR document,
    DocumentJob job,
    String outputDirectory,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
  ) async {
    final adoc = _renderAsciiDoc(
      document,
      includeImageLinks:
          options.exportImagesForAsciiDoc && document.images.isNotEmpty,
    );
    if (!options.exportImagesForAsciiDoc || document.images.isEmpty) {
      return _writeTextExport(
        adoc,
        job,
        outputDirectory,
        options,
        configuration,
        DocumentExportFormat.asciidoc,
      );
    }
    final output = _uniqueOutputPath(
      job,
      outputDirectory,
      options,
      configuration,
      'zip',
    );
    final archive = Archive();
    final base = _outputBaseName(job, options, configuration);
    archive.addFile(
      ArchiveFile('$base.adoc', utf8.encode(adoc).length, utf8.encode(adoc)),
    );
    for (final image in document.images) {
      archive.addFile(
        ArchiveFile(
          'images/${image.suggestedFilename}',
          image.data.length,
          image.data,
        ),
      );
    }
    await File(output).writeAsBytes(ZipEncoder().encode(archive));
    return output;
  }

  Future<String> _exportPdf(
    DocumentIR document,
    DocumentJob job,
    String outputDirectory,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
  ) async {
    final output = _uniqueOutputPath(
      job,
      outputDirectory,
      options,
      configuration,
      DocumentExportFormat.pdf.fileExtension,
    );
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (_) => [
          pw.Text(
            document.plainText.isEmpty ? ' ' : document.plainText,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
    await File(output).writeAsBytes(await pdf.save());
    return output;
  }

  Future<String> _exportDocx(
    DocumentIR document,
    DocumentJob job,
    String outputDirectory,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
  ) async {
    final output = _uniqueOutputPath(
      job,
      outputDirectory,
      options,
      configuration,
      DocumentExportFormat.docx.fileExtension,
    );
    await _writeDocx(document, output);
    return output;
  }

  Future<String> _exportOdt(
    DocumentIR document,
    DocumentJob job,
    String outputDirectory,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
  ) async {
    final soffice = findSofficeSync();
    if (soffice == null) {
      throw DocumentProcessingException(
        exportUnavailableReason(DocumentExportFormat.odt),
      );
    }
    final tempDir = await Directory.systemTemp.createTemp('abyssl-odt-export-');
    try {
      final tempDocx = p.join(
        tempDir.path,
        '${_outputBaseName(job, options, configuration)}.docx',
      );
      await _writeDocx(document, tempDocx);
      final result = await Process.run(soffice, [
        '--headless',
        '--convert-to',
        'odt',
        '--outdir',
        tempDir.path,
        tempDocx,
      ]);
      if (result.exitCode != 0) {
        throw DocumentProcessingException(
          '${result.stderr}'.trim().isEmpty
              ? 'ODT export failed.'
              : '${result.stderr}',
        );
      }
      final generated = p.join(
        tempDir.path,
        '${p.basenameWithoutExtension(tempDocx)}.odt',
      );
      if (!File(generated).existsSync()) {
        throw const DocumentProcessingException(
          'LibreOffice did not produce an ODT file.',
        );
      }
      final output = _uniqueOutputPath(
        job,
        outputDirectory,
        options,
        configuration,
        DocumentExportFormat.odt.fileExtension,
      );
      final generatedFile = File(generated);
      try {
        await generatedFile.rename(output);
      } on FileSystemException {
        await generatedFile.copy(output);
        await generatedFile.delete();
      }
      return output;
    } finally {
      await tempDir.delete(recursive: true);
    }
  }

  Future<void> _writeDocx(DocumentIR document, String output) async {
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          '[Content_Types].xml',
          utf8.encode(_docxContentTypes()).length,
          utf8.encode(_docxContentTypes()),
        ),
      )
      ..addFile(
        ArchiveFile(
          '_rels/.rels',
          utf8.encode(_docxRootRels()).length,
          utf8.encode(_docxRootRels()),
        ),
      )
      ..addFile(
        ArchiveFile(
          'word/_rels/document.xml.rels',
          utf8.encode(_docxDocumentRels()).length,
          utf8.encode(_docxDocumentRels()),
        ),
      )
      ..addFile(
        ArchiveFile(
          'word/document.xml',
          utf8.encode(_docxDocumentXml(document)).length,
          utf8.encode(_docxDocumentXml(document)),
        ),
      );
    await File(output).writeAsBytes(ZipEncoder().encode(archive));
  }

  String _renderMarkdown(DocumentIR document) => document.blocks
      .map((block) {
        return switch (block) {
          DocumentParagraph(:final text) => text,
          DocumentTable(:final rows) => _renderMarkdownTable(rows),
        };
      })
      .join('\n\n');

  String _renderMarkdownTable(List<List<String>> rows) {
    if (rows.isEmpty) return '';
    final width = rows.map((row) => row.length).fold(0, max);
    final padded = rows
        .map((row) => [...row, ...List.filled(width - row.length, '')])
        .toList();
    final header = '| ${padded.first.map(_escapeMarkdownCell).join(' | ')} |';
    final separator = '| ${List.filled(width, '---').join(' | ')} |';
    final body = padded
        .skip(1)
        .map((row) => '| ${row.map(_escapeMarkdownCell).join(' | ')} |');
    return ([header, separator] + body.toList()).join('\n');
  }

  String _renderHtml(DocumentIR document) {
    final body = document.blocks
        .map((block) {
          return switch (block) {
            DocumentParagraph(:final text) =>
              '<p>${_escapeHtml(text).replaceAll('\n', '<br>')}</p>',
            DocumentTable(:final rows) =>
              '<table>\n${rows.map((row) => '<tr>${row.map((cell) => '<td>${_escapeHtml(cell)}</td>').join()}</tr>').join('\n')}\n</table>',
          };
        })
        .join('\n');
    return '''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<style>
body { font-family: system-ui, sans-serif; line-height: 1.45; }
table { border-collapse: collapse; margin: 1em 0; }
td, th { border: 1px solid #999; padding: 4px 8px; }
</style>
</head>
<body>
$body
</body>
</html>
''';
  }

  String _renderAsciiDoc(
    DocumentIR document, {
    required bool includeImageLinks,
  }) {
    final chunks = <String>[];
    for (final block in document.blocks) {
      switch (block) {
        case DocumentParagraph(:final text):
          chunks.add(text);
        case DocumentTable(:final rows):
          chunks.add(
            [
              '|===',
              rows.map((row) => '| ${row.join(' | ')}').join('\n'),
              '|===',
            ].join('\n'),
          );
      }
    }
    if (includeImageLinks) {
      for (final image in document.images) {
        chunks.add('image::images/${image.suggestedFilename}[]');
      }
    }
    return chunks.join('\n\n');
  }

  String _renderRtf(DocumentIR document) {
    final escaped = document.plainText
        .replaceAll(r'\', r'\\')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAll('\n', r'\par ');
    return r'{\rtf1\ansi '
        '$escaped}';
  }

  String _docxDocumentXml(DocumentIR document) {
    final body = document.blocks.map((block) {
      return switch (block) {
        DocumentParagraph(:final text) => _docxParagraphXml(text),
        DocumentTable(:final rows) =>
          '<w:tbl>${rows.map((row) => '<w:tr>${row.map((cell) => '<w:tc>${_docxParagraphXml(cell)}</w:tc>').join()}</w:tr>').join()}</w:tbl>',
      };
    }).join();
    return '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
$body
<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
</w:body>
</w:document>
''';
  }

  String _docxParagraphXml(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n');
    final content = lines.indexed.map((entry) {
      final index = entry.$1;
      final line = entry.$2;
      final br = index == 0 ? '' : '<w:br/>';
      return '$br<w:t xml:space="preserve">${_escapeXml(line)}</w:t>';
    }).join();
    return '<w:p><w:r>$content</w:r></w:p>';
  }

  String _docxContentTypes() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>
''';

  String _docxRootRels() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>
''';

  String _docxDocumentRels() => '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
''';

  List<DocumentBlock> _paragraphs(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized
        .split(RegExp(r'\n\s*\n'))
        .map((part) => DocumentParagraph(part.trim()))
        .where((block) => block.text.isNotEmpty)
        .toList();
  }

  List<List<String>> _parseDelimited(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var insideQuotes = false;
    for (var index = 0; index < text.length; index++) {
      final char = text[index];
      if (char == '"') {
        if (insideQuotes && index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index++;
        } else {
          insideQuotes = !insideQuotes;
        }
      } else if (char == delimiter && !insideQuotes) {
        row.add(field.toString());
        field.clear();
      } else if (char == '\n' && !insideQuotes) {
        row.add(field.toString());
        if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
        row = <String>[];
        field.clear();
      } else if (char != '\r') {
        field.write(char);
      }
    }
    row.add(field.toString());
    if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
    return rows;
  }

  String? _archiveString(Archive archive, String name) {
    final file = archive.findFile(name);
    if (file == null || !file.isFile) return null;
    return utf8.decode(file.content as List<int>);
  }

  String _relativeDirectoryForOutput(DocumentJob job) {
    final root = job.rootPath;
    if (root == null) return '';
    final sourceDir = p.normalize(p.dirname(job.sourcePath));
    final normalizedRoot = p.normalize(root);
    if (!p.isWithin(normalizedRoot, sourceDir) && sourceDir != normalizedRoot) {
      return '';
    }
    return p.relative(sourceDir, from: normalizedRoot);
  }

  String _uniqueOutputPath(
    DocumentJob job,
    String outputDirectory,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
    String extension,
  ) {
    final sanitized = _sanitizeFilename(
      _outputBaseName(job, options, configuration),
    );
    var candidate = p.join(outputDirectory, '$sanitized.$extension');
    var index = 2;
    while (File(candidate).existsSync()) {
      candidate = p.join(outputDirectory, '$sanitized-$index.$extension');
      index++;
    }
    return candidate;
  }

  String _outputBaseName(
    DocumentJob job,
    DocumentOperationOptions options,
    ProviderRequestConfig configuration,
  ) {
    final parts = <String>[p.basenameWithoutExtension(job.sourcePath)];
    if (!options.nameOptions.customizeName) return parts.first;
    if (options.nameOptions.appendTimestamp) {
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      parts.add(
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}',
      );
    }
    if (options.nameOptions.appendTargetLanguage && options.shouldTranslate) {
      parts.add(configuration.targetLanguage.id);
    }
    final suffix = options.nameOptions.customSuffix.trim();
    if (suffix.isNotEmpty) parts.add(suffix);
    return parts.join('-');
  }

  String _sanitizeFilename(String value) =>
      value.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '-').trim().isEmpty
      ? 'export'
      : value.replaceAll(RegExp(r'[/\\?%*:|"<>]'), '-');

  String _escapeHtml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  String _escapeXml(String value) =>
      _escapeHtml(value).replaceAll('"', '&quot;').replaceAll("'", '&apos;');
  String _escapeMarkdownCell(String value) =>
      value.replaceAll('|', r'\|').replaceAll('\n', ' ');

  String _decodeHtmlEntities(String value) => value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");

  String _localName(XmlElement element) => element.name.local;

  static String exportUnavailableReason(
    DocumentExportFormat format,
  ) => switch (format) {
    DocumentExportFormat.odt =>
      'ODT requires LibreOffice soffice; no safe local converter was found.',
    DocumentExportFormat.pages =>
      'Pages export is not supported by the cross-platform document path.',
    DocumentExportFormat.numbers =>
      'Numbers export is not supported by the cross-platform document path.',
    _ => 'Export format is unavailable on this system.',
  };

  static String? findSofficeSync() {
    final candidates = <String>[
      ..._pathCandidates('soffice'),
      if (Platform.isMacOS) ...[
        '/Applications/LibreOffice.app/Contents/MacOS/soffice',
        '/usr/local/bin/soffice',
        '/opt/homebrew/bin/soffice',
      ],
      if (Platform.isLinux) ...[
        '/usr/bin/soffice',
        '/usr/local/bin/soffice',
        '/snap/bin/libreoffice',
      ],
      if (Platform.isWindows) ...[
        r'C:\Program Files\LibreOffice\program\soffice.exe',
        r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
      ],
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (file.existsSync()) return candidate;
    }
    return null;
  }

  Future<String?> _findExecutable(List<String> names) async {
    for (final name in names) {
      for (final candidate in _pathCandidates(name)) {
        if (await File(candidate).exists()) return candidate;
      }
    }
    return null;
  }

  static Iterable<String> _pathCandidates(String executable) sync* {
    final path = Platform.environment['PATH'];
    if (path == null || path.isEmpty) return;
    for (final dir in path.split(Platform.isWindows ? ';' : ':')) {
      if (dir.trim().isEmpty) continue;
      yield p.join(
        dir,
        Platform.isWindows && !executable.endsWith('.exe')
            ? '$executable.exe'
            : executable,
      );
    }
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
