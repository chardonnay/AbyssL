import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';

const abyssLWebsiteUri = 'https://chardonnay.github.io/AbyssL/';
const abyssLRepositoryUri = 'https://github.com/chardonnay/AbyssL';
const abyssLLatestReleaseApiUri =
    'https://api.github.com/repos/chardonnay/AbyssL/releases/latest';
const abyssLMacOSReleaseAssetName = 'abyssl_flutter-macos-release.zip';
const abyssLAppcastAssetName = 'appcast.xml';

class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get displayVersion =>
      buildNumber.trim().isEmpty ? version : '$version ($buildNumber)';
}

class GitHubReleaseAsset {
  const GitHubReleaseAsset({
    required this.name,
    required this.downloadUri,
    required this.size,
    this.digest,
  });

  final String name;
  final Uri downloadUri;
  final int size;
  final String? digest;
}

class GitHubRelease {
  const GitHubRelease({
    required this.tagName,
    required this.version,
    required this.pageUri,
    required this.title,
    required this.notes,
    required this.assets,
  });

  final String tagName;
  final Version version;
  final Uri pageUri;
  final String title;
  final String notes;
  final List<GitHubReleaseAsset> assets;

  GitHubReleaseAsset? assetNamed(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  bool get hasInstallableMacOSUpdate =>
      assetNamed(abyssLMacOSReleaseAssetName) != null &&
      assetNamed(abyssLAppcastAssetName) != null;
}

enum UpdateCheckKind {
  noPublishedRelease,
  upToDate,
  updateAvailable,
  releaseNotReady,
}

class UpdateCheckResult {
  const UpdateCheckResult({required this.kind, this.release});

  final UpdateCheckKind kind;
  final GitHubRelease? release;
}

class ReleaseHttpResponse {
  const ReleaseHttpResponse({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

typedef ReleaseJsonFetcher =
    Future<ReleaseHttpResponse> Function(Uri uri, Map<String, String> headers);

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AppUpdateService {
  Future<AppBuildInfo> loadInstalledBuild();

  Future<UpdateCheckResult> checkForUpdates(AppBuildInfo installedBuild);

  Future<void> startAutomaticInstall();

  Future<void> openWebsite();

  Future<void> openRelease(GitHubRelease release);

  bool get supportsAutomaticInstall;
}

class GitHubAppUpdateService implements AppUpdateService {
  GitHubAppUpdateService({
    ReleaseJsonFetcher? fetcher,
    Future<bool> Function(Uri uri)? uriLauncher,
    MethodChannel? updateChannel,
  }) : _fetcher = fetcher ?? _fetchReleaseJson,
       _uriLauncher = uriLauncher ?? _launchExternalUri,
       _updateChannel =
           updateChannel ?? const MethodChannel('org.abyssl.translator/update');

  final ReleaseJsonFetcher _fetcher;
  final Future<bool> Function(Uri uri) _uriLauncher;
  final MethodChannel _updateChannel;

  @override
  bool get supportsAutomaticInstall => Platform.isMacOS;

  @override
  Future<AppBuildInfo> loadInstalledBuild() async {
    final info = await PackageInfo.fromPlatform();
    return AppBuildInfo(version: info.version, buildNumber: info.buildNumber);
  }

  @override
  Future<UpdateCheckResult> checkForUpdates(AppBuildInfo installedBuild) async {
    final response = await _fetcher(Uri.parse(abyssLLatestReleaseApiUri), {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'AbyssL/${installedBuild.version}',
    });
    if (response.statusCode == HttpStatus.notFound) {
      return const UpdateCheckResult(kind: UpdateCheckKind.noPublishedRelease);
    }
    if (response.statusCode == HttpStatus.forbidden) {
      throw const AppUpdateException(
        'GitHub has temporarily limited update checks. Please try again later.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw AppUpdateException(
        'GitHub update check failed (HTTP ${response.statusCode}).',
      );
    }

    final release = _parseRelease(response.body);
    final installedVersion = _parseVersion(installedBuild.version);
    if (release.version <= installedVersion) {
      return UpdateCheckResult(
        kind: UpdateCheckKind.upToDate,
        release: release,
      );
    }
    if (!release.hasInstallableMacOSUpdate) {
      return UpdateCheckResult(
        kind: UpdateCheckKind.releaseNotReady,
        release: release,
      );
    }
    return UpdateCheckResult(
      kind: UpdateCheckKind.updateAvailable,
      release: release,
    );
  }

  @override
  Future<void> startAutomaticInstall() async {
    if (!supportsAutomaticInstall) {
      throw const AppUpdateException(
        'Automatic installation is currently available on macOS only.',
      );
    }
    try {
      await _updateChannel.invokeMethod<void>('checkForUpdates');
    } on PlatformException catch (error) {
      throw AppUpdateException(
        error.message ?? 'The macOS updater could not be started.',
      );
    } on MissingPluginException {
      throw const AppUpdateException(
        'The macOS updater is unavailable in this build.',
      );
    }
  }

  @override
  Future<void> openWebsite() => _open(Uri.parse(abyssLWebsiteUri));

  @override
  Future<void> openRelease(GitHubRelease release) => _open(release.pageUri);

  Future<void> _open(Uri uri) async {
    if (!await _uriLauncher(uri)) {
      throw AppUpdateException('Could not open $uri');
    }
  }

  static Future<bool> _launchExternalUri(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  static Future<ReleaseHttpResponse> _fetchReleaseJson(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return ReleaseHttpResponse(statusCode: response.statusCode, body: body);
    } on TimeoutException {
      throw const AppUpdateException(
        'The GitHub update check timed out. Please try again.',
      );
    } on SocketException catch (error) {
      throw AppUpdateException('Could not reach GitHub: ${error.message}');
    } finally {
      client.close(force: true);
    }
  }

  static GitHubRelease _parseRelease(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const AppUpdateException(
        'GitHub returned invalid release information.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AppUpdateException(
        'GitHub returned invalid release information.',
      );
    }

    final tagName = decoded['tag_name'] as String?;
    final pageUri = _httpsUri(decoded['html_url']);
    if (tagName == null || tagName.trim().isEmpty || pageUri == null) {
      throw const AppUpdateException(
        'The latest GitHub release is missing required metadata.',
      );
    }
    final rawAssets = decoded['assets'];
    final assets = <GitHubReleaseAsset>[];
    if (rawAssets is List) {
      for (final rawAsset in rawAssets) {
        if (rawAsset is! Map) continue;
        final name = rawAsset['name'];
        final state = rawAsset['state'];
        final size = rawAsset['size'];
        final downloadUri = _httpsUri(rawAsset['browser_download_url']);
        if (name is! String ||
            state != 'uploaded' ||
            size is! int ||
            size <= 0 ||
            downloadUri == null) {
          continue;
        }
        final rawDigest = rawAsset['digest'];
        assets.add(
          GitHubReleaseAsset(
            name: name,
            downloadUri: downloadUri,
            size: size,
            digest: rawDigest is String ? rawDigest : null,
          ),
        );
      }
    }

    return GitHubRelease(
      tagName: tagName,
      version: _parseVersion(tagName),
      pageUri: pageUri,
      title: (decoded['name'] as String?)?.trim().isNotEmpty == true
          ? (decoded['name'] as String).trim()
          : tagName,
      notes: (decoded['body'] as String?)?.trim() ?? '',
      assets: List.unmodifiable(assets),
    );
  }

  static Version _parseVersion(String rawVersion) {
    var normalized = rawVersion.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    try {
      return Version.parse(normalized);
    } on FormatException {
      throw AppUpdateException(
        'Release version "$rawVersion" is not valid semantic versioning.',
      );
    }
  }

  static Uri? _httpsUri(Object? raw) {
    if (raw is! String) return null;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
    return uri;
  }
}
