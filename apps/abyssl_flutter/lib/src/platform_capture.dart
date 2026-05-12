import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'models.dart';

class CaptureStatus {
  const CaptureStatus({
    required this.supported,
    required this.message,
    this.sessionType,
  });

  final bool supported;
  final String message;
  final String? sessionType;
}

class DesktopCaptureService {
  DesktopCaptureService() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const _channel = MethodChannel('org.abyssl.translator/capture');
  final _captureController = StreamController<String>.broadcast();

  Stream<String> get capturedText => _captureController.stream;

  Future<CaptureStatus> platformStatus() async {
    try {
      final result =
          await _channel.invokeMapMethod<String, Object?>('platformStatus') ??
          const {};
      return CaptureStatus(
        supported: result['supported'] == true,
        message:
            result['message'] as String? ?? 'No platform status was returned.',
        sessionType: result['sessionType'] as String?,
      );
    } on MissingPluginException {
      return CaptureStatus(
        supported: false,
        message: _defaultUnsupportedMessage(),
        sessionType: Platform.environment['XDG_SESSION_TYPE'],
      );
    } catch (error) {
      return CaptureStatus(
        supported: false,
        message: 'Capture adapter failed: $error',
        sessionType: Platform.environment['XDG_SESSION_TYPE'],
      );
    }
  }

  Future<void> configure(TranslationCaptureShortcut shortcut) async {
    try {
      await _channel.invokeMethod<void>('configureCapture', {
        'modifier': shortcut.modifier.name,
        'key': shortcut.normalizedKey,
      });
    } on MissingPluginException {
      return;
    }
  }

  Future<void> start() async {
    try {
      await _channel.invokeMethod<void>('startCapture');
    } on MissingPluginException {
      return;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopCapture');
    } on MissingPluginException {
      return;
    }
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'captureText') {
      final text = call.arguments;
      if (text is String && text.trim().isNotEmpty) {
        _captureController.add(text);
      }
    }
  }

  String _defaultUnsupportedMessage() {
    if (Platform.isLinux) {
      final session = Platform.environment['XDG_SESSION_TYPE'] ?? 'unknown';
      return 'Linux global capture requires a native adapter for the active display server. Current session: $session.';
    }
    if (Platform.isWindows) {
      return 'Windows capture adapter is not registered.';
    }
    if (Platform.isMacOS) {
      return 'macOS capture adapter is not registered.';
    }
    return 'Global capture is not supported on this platform.';
  }

  void dispose() {
    _captureController.close();
  }
}
