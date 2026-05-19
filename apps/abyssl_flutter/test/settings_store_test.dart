import 'package:abyssl_flutter/src/settings_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  test('persists reasoning settings per local model', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final secureStorage = _MemorySecureStorage();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    );

    settings.update((settings) {
      settings.localModel = 'qwen3-8b-loaded';
      settings.reasoningOnValue = 'on';
      settings.reasoningOffValue = 'off';
      settings.reasoningEnabled = true;
      settings.rememberReasoningSettingsForModel(
        'qwen3-8b-loaded',
        allowedOptions: const ['off', 'on'],
        reasoningOnValue: 'on',
        reasoningOffValue: 'off',
        reasoningEnabled: true,
      );
    });
    await settings.save();

    final reloaded = await AppSettingsStore.load(secureStorage: secureStorage);

    expect(reloaded.localModel, 'qwen3-8b-loaded');
    expect(reloaded.reasoningOnValue, 'on');
    expect(reloaded.reasoningOffValue, 'off');
    expect(reloaded.reasoningEnabled, isTrue);
    expect(reloaded.reasoningOptionsForModel('qwen3-8b-loaded'), ['off', 'on']);
  });

  test('persists auto translate setting independently', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SharedPreferences.setMockInitialValues({});
    final secureStorage = _MemorySecureStorage();
    final preferences = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettingsStore(
      preferences: preferences,
      secureStorage: secureStorage,
    );

    settings.update((settings) => settings.autoTranslateEnabled = false);
    await settings.saveAutoTranslateEnabled();

    final reloaded = await AppSettingsStore.load(secureStorage: secureStorage);

    expect(reloaded.autoTranslateEnabled, isFalse);
  });
}

// Test double for secure storage; secrets are not under test here.
class _MemorySecureStorage extends FlutterSecureStorage {
  final _values = <String, String>{};

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}
