#include "flutter_window.h"

#include <windows.h>

#include <cctype>
#include <chrono>
#include <optional>
#include <thread>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr auto kDoubleTapWindow = std::chrono::milliseconds(450);
FlutterWindow* g_capture_window = nullptr;

std::string Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return "";
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  std::string result(size, 0);
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

LRESULT CALLBACK LowLevelKeyboardProc(int code, WPARAM wparam, LPARAM lparam) {
  if (code == HC_ACTION && wparam == WM_KEYDOWN && g_capture_window) {
    const auto* event = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
    g_capture_window->HandleKeyEvent(event->vkCode);
  }
  return CallNextHookEx(nullptr, code, wparam, lparam);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  alive_->store(false);
  StopCapture();
  JoinCaptureThreads();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  ConfigureCaptureChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  alive_->store(false);
  StopCapture();
  JoinCaptureThreads();
  capture_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_ && flutter_controller_->engine()) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ConfigureCaptureChannel() {
  capture_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "org.abyssl.translator/capture",
          &flutter::StandardMethodCodec::GetInstance());

  capture_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "platformStatus") {
          flutter::EncodableMap response;
          response[flutter::EncodableValue("supported")] =
              flutter::EncodableValue(true);
          response[flutter::EncodableValue("message")] =
              flutter::EncodableValue(
                  "Windows capture adapter is available.");
          response[flutter::EncodableValue("sessionType")] =
              flutter::EncodableValue("Windows");
          result->Success(flutter::EncodableValue(response));
          return;
        }
        if (call.method_name() == "configureCapture") {
          const auto* args =
              std::get_if<flutter::EncodableMap>(call.arguments());
          if (args) {
            auto modifier = args->find(flutter::EncodableValue("modifier"));
            if (modifier != args->end()) {
              if (const auto* value =
                      std::get_if<std::string>(&modifier->second)) {
                capture_modifier_ = *value;
              }
            }
            auto key = args->find(flutter::EncodableValue("key"));
            if (key != args->end()) {
              if (const auto* value = std::get_if<std::string>(&key->second)) {
                capture_key_ = *value;
              }
            }
          }
          if (keyboard_hook_) {
            StartCapture();
          }
          result->Success();
          return;
        }
        if (call.method_name() == "startCapture") {
          StartCapture();
          result->Success();
          return;
        }
        if (call.method_name() == "stopCapture") {
          StopCapture();
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::StartCapture() {
  StopCapture();
  g_capture_window = this;
  keyboard_hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, LowLevelKeyboardProc,
                                    GetModuleHandle(nullptr), 0);
}

void FlutterWindow::StopCapture() {
  if (keyboard_hook_) {
    UnhookWindowsHookEx(keyboard_hook_);
    keyboard_hook_ = nullptr;
  }
  if (g_capture_window == this) {
    g_capture_window = nullptr;
  }
}

void FlutterWindow::JoinCaptureThreads() {
  std::vector<std::thread> threads;
  {
    std::lock_guard<std::mutex> lock(capture_threads_mutex_);
    threads.swap(capture_threads_);
  }
  for (auto& thread : threads) {
    if (thread.joinable()) {
      thread.join();
    }
  }
}

void FlutterWindow::HandleKeyEvent(DWORD vk_code) {
  if (vk_code != KeyCode() || !ModifierPressed()) {
    return;
  }
  HandleHotKey();
}

void FlutterWindow::HandleHotKey() {
  auto now = std::chrono::steady_clock::now();
  if (last_hotkey_time_.time_since_epoch().count() != 0 &&
      now - last_hotkey_time_ <= kDoubleTapWindow) {
    last_hotkey_time_ = std::chrono::steady_clock::time_point();
    auto weak_alive = std::weak_ptr<std::atomic_bool>(alive_);
    auto* capture_channel = capture_channel_.get();
    std::thread worker([weak_alive, capture_channel]() {
      std::string text = FlutterWindow::CopySelectionFromForegroundWindow();
      auto alive = weak_alive.lock();
      if (!alive || !alive->load() || text.empty() ||
          capture_channel == nullptr) {
        return;
      }
      capture_channel->InvokeMethod(
          "captureText", std::make_unique<flutter::EncodableValue>(text));
    });
    {
      std::lock_guard<std::mutex> lock(capture_threads_mutex_);
      if (alive_->load()) {
        capture_threads_.push_back(std::move(worker));
      }
    }
    if (worker.joinable()) {
      worker.join();
    }
  } else {
    last_hotkey_time_ = now;
  }
}

std::string FlutterWindow::CopySelectionFromForegroundWindow() {
  HWND foreground = GetForegroundWindow();
  if (!foreground) {
    return "";
  }
  SetForegroundWindow(foreground);

  INPUT inputs[4] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'C';
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'C';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(4, inputs, sizeof(INPUT));
  std::this_thread::sleep_for(std::chrono::milliseconds(160));

  if (!OpenClipboard(nullptr)) {
    return "";
  }
  HANDLE handle = GetClipboardData(CF_UNICODETEXT);
  if (!handle) {
    CloseClipboard();
    return "";
  }
  LPCWSTR data = static_cast<LPCWSTR>(GlobalLock(handle));
  if (!data) {
    CloseClipboard();
    return "";
  }
  std::wstring text(data);
  GlobalUnlock(handle);
  CloseClipboard();
  return Utf8FromWide(text);
}

UINT FlutterWindow::KeyCode() const {
  if (capture_key_.empty()) {
    return 'C';
  }
  char key = static_cast<char>(toupper(capture_key_[0]));
  if ((key >= 'A' && key <= 'Z') || (key >= '0' && key <= '9')) {
    return static_cast<UINT>(key);
  }
  return 'C';
}

bool FlutterWindow::ModifierPressed() const {
  if (capture_modifier_ == "shift") {
    return (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0;
  }
  if (capture_modifier_ == "option") {
    return (GetAsyncKeyState(VK_MENU) & 0x8000) != 0;
  }
  if (capture_modifier_ == "command") {
    return (GetAsyncKeyState(VK_LWIN) & 0x8000) != 0 ||
           (GetAsyncKeyState(VK_RWIN) & 0x8000) != 0;
  }
  return (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0;
}
