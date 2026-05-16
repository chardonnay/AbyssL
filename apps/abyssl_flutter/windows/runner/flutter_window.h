#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void ConfigureCaptureChannel();
  void StartCapture();
  void StopCapture();
  void JoinCaptureThreads();
  void HandleHotKey();
  void HandleKeyEvent(DWORD vk_code);
  // Returns an empty string when no text was copied or clipboard access fails.
  static std::string CopySelectionFromForegroundWindow();
  UINT KeyCode() const;
  bool ModifierPressed() const;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::shared_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      capture_channel_;
  std::mutex capture_channel_mutex_;
  std::string capture_modifier_ = "control";
  std::string capture_key_ = "c";
  HHOOK keyboard_hook_ = nullptr;
  std::chrono::steady_clock::time_point last_hotkey_time_;
  std::mutex last_hotkey_time_mutex_;
  std::shared_ptr<std::atomic_bool> alive_ =
      std::make_shared<std::atomic_bool>(true);
  std::mutex capture_threads_mutex_;
  std::vector<std::thread> capture_threads_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
