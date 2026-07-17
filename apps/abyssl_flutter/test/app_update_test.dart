import 'dart:convert';

import 'package:abyssl_flutter/src/app_update.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const installed = AppBuildInfo(version: '1.0.0', buildNumber: '1');

  test('treats a missing latest release as an empty release channel', () async {
    final service = GitHubAppUpdateService(
      fetcher: (_, _) async =>
          const ReleaseHttpResponse(statusCode: 404, body: '{}'),
    );

    final result = await service.checkForUpdates(installed);

    expect(result.kind, UpdateCheckKind.noPublishedRelease);
    expect(result.release, isNull);
  });

  test('finds a newer installable macOS GitHub release', () async {
    Map<String, String>? sentHeaders;
    final service = GitHubAppUpdateService(
      fetcher: (_, headers) async {
        sentHeaders = headers;
        return ReleaseHttpResponse(
          statusCode: 200,
          body: _releaseJson(tag: 'v1.2.0'),
        );
      },
    );

    final result = await service.checkForUpdates(installed);

    expect(result.kind, UpdateCheckKind.updateAvailable);
    expect(result.release?.version.toString(), '1.2.0');
    expect(
      result.release?.assetNamed(abyssLMacOSReleaseAssetName)?.size,
      42000000,
    );
    expect(sentHeaders?['Accept'], 'application/vnd.github+json');
    expect(sentHeaders?['X-GitHub-Api-Version'], '2022-11-28');
    expect(sentHeaders?['User-Agent'], 'AbyssL/1.0.0');
  });

  test('does not offer a downgrade or reinstall', () async {
    final equalService = GitHubAppUpdateService(
      fetcher: (_, _) async => ReleaseHttpResponse(
        statusCode: 200,
        body: _releaseJson(tag: 'v1.0.0'),
      ),
    );
    final olderService = GitHubAppUpdateService(
      fetcher: (_, _) async => ReleaseHttpResponse(
        statusCode: 200,
        body: _releaseJson(tag: 'v0.9.9'),
      ),
    );

    expect(
      (await equalService.checkForUpdates(installed)).kind,
      UpdateCheckKind.upToDate,
    );
    expect(
      (await olderService.checkForUpdates(installed)).kind,
      UpdateCheckKind.upToDate,
    );
  });

  test('reports a newer release without signed update assets', () async {
    final service = GitHubAppUpdateService(
      fetcher: (_, _) async => ReleaseHttpResponse(
        statusCode: 200,
        body: _releaseJson(tag: 'v1.1.0', includeAppcast: false),
      ),
    );

    final result = await service.checkForUpdates(installed);

    expect(result.kind, UpdateCheckKind.releaseNotReady);
    expect(result.release?.pageUri.host, 'github.com');
  });

  test('rejects malformed versions and GitHub rate limits clearly', () async {
    final malformedService = GitHubAppUpdateService(
      fetcher: (_, _) async => ReleaseHttpResponse(
        statusCode: 200,
        body: _releaseJson(tag: 'latest'),
      ),
    );
    final limitedService = GitHubAppUpdateService(
      fetcher: (_, _) async =>
          const ReleaseHttpResponse(statusCode: 403, body: '{}'),
    );

    await expectLater(
      malformedService.checkForUpdates(installed),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.message,
          'message',
          contains('semantic versioning'),
        ),
      ),
    );
    await expectLater(
      limitedService.checkForUpdates(installed),
      throwsA(
        isA<AppUpdateException>().having(
          (error) => error.message,
          'message',
          contains('temporarily limited'),
        ),
      ),
    );
  });

  test('opens only the configured website and release URLs', () async {
    final opened = <Uri>[];
    final service = GitHubAppUpdateService(
      uriLauncher: (uri) async {
        opened.add(uri);
        return true;
      },
      fetcher: (_, _) async => ReleaseHttpResponse(
        statusCode: 200,
        body: _releaseJson(tag: 'v1.2.0'),
      ),
    );
    final release = (await service.checkForUpdates(installed)).release!;

    await service.openWebsite();
    await service.openRelease(release);

    expect(opened, [Uri.parse(abyssLWebsiteUri), release.pageUri]);
  });
}

String _releaseJson({required String tag, bool includeAppcast = true}) {
  final assets = <Map<String, Object>>[
    {
      'name': abyssLMacOSReleaseAssetName,
      'state': 'uploaded',
      'size': 42000000,
      'browser_download_url':
          'https://github.com/chardonnay/AbyssL/releases/download/$tag/$abyssLMacOSReleaseAssetName',
      'digest': 'sha256:0123456789abcdef',
    },
    if (includeAppcast)
      {
        'name': abyssLAppcastAssetName,
        'state': 'uploaded',
        'size': 1400,
        'browser_download_url':
            'https://github.com/chardonnay/AbyssL/releases/download/$tag/$abyssLAppcastAssetName',
        'digest': 'sha256:fedcba9876543210',
      },
  ];
  return jsonEncode({
    'tag_name': tag,
    'html_url': 'https://github.com/chardonnay/AbyssL/releases/tag/$tag',
    'name': 'AbyssL $tag',
    'body': 'Highlights and fixes.',
    'assets': assets,
  });
}
