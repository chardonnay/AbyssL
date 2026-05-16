#include "flutter_window.h"

#include <windows.h>

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstring>
#include <optional>
#include <thread>
#include <vector>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr auto kDoubleTapWindow = std::chrono::milliseconds(450);
constexpr auto kClipboardTimeout = std::chrono::milliseconds(750);
constexpr auto kInitialClipboardRetryDelay = std::chrono::milliseconds(10);
constexpr auto kMaxClipboardRetryDelay = std::chrono::milliseconds(80);
FlutterWindow* g_capture_window = nullptr;

std::mutex& ClipboardMutex() {
  static std::mutex mutex;
  return mutex;
}

class ClipboardSession {
 public:
  ClipboardSession() : opened_(OpenClipboard(nullptr) != 0) {}

  ClipboardSession(const ClipboardSession&) = delete;
  ClipboardSession& operator=(const ClipboardSession&) = delete;

  ~ClipboardSession() {
    if (opened_) {
      CloseClipboard();
    }
  }

  bool is_open() const { return opened_; }

 private:
  bool opened_;
};

class GlobalLockGuard {
 public:
  explicit GlobalLockGuard(HGLOBAL handle)
      : handle_(handle), data_(GlobalLock(handle)) {}

  GlobalLockGuard(const GlobalLockGuard&) = delete;
  GlobalLockGuard& operator=(const GlobalLockGuard&) = delete;

  ~GlobalLockGuard() {
    if (data_) {
      GlobalUnlock(handle_);
    }
  }

  void* data() const { return data_; }

 private:
  HGLOBAL handle_;
  void* data_;
};

struct ClipboardData {
  ClipboardData(UINT format, HGLOBAL handle) : format(format), handle(handle) {}

  ClipboardData(const ClipboardData&) = delete;
  ClipboardData& operator=(const ClipboardData&) = delete;

  ClipboardData(ClipboardData&& other) noexcept
      : format(other.format), handle(other.handle) {
    other.handle = nullptr;
  }

  ClipboardData& operator=(ClipboardData&& other) noexcept {
    if (this != &other) {
      ReleaseOwned();
      format = other.format;
      handle = other.handle;
      other.handle = nullptr;
    }
    return *this;
  }

  ~ClipboardData() { ReleaseOwned(); }

  HGLOBAL Release() {
    HGLOBAL released = handle;
    handle = nullptr;
    return released;
  }

  UINT format;
  HGLOBAL handle;

 private:
  void ReleaseOwned() {
    if (handle) {
      GlobalFree(handle);
      handle = nullptr;
    }
  }
};

std::optional<std::string> Utf8FromWide(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }
  int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                                 static_cast<int>(value.size()), nullptr, 0,
                                 nullptr, nullptr);
  if (size == 0) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  std::string result(size, 0);
  int written = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), result.data(),
      size, nullptr, nullptr);
  if (written == 0) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  result.resize(static_cast<size_t>(written));
  return result;
}

std::optional<ClipboardData> DuplicateClipboardFormat(UINT format) {
  HGLOBAL source = static_cast<HGLOBAL>(GetClipboardData(format));
  if (!source) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  SIZE_T size = GlobalSize(source);
  if (size == 0) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  HGLOBAL copy = GlobalAlloc(GMEM_MOVEABLE, size);
  if (!copy) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  ClipboardData copied(format, copy);
  GlobalLockGuard source_lock(source);
  if (!source_lock.data()) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  GlobalLockGuard copy_lock(copy);
  if (!copy_lock.data()) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  std::memcpy(copy_lock.data(), source_lock.data(), size);
  return std::optional<ClipboardData>(std::move(copied));
}

std::optional<std::vector<ClipboardData>> BackupClipboard() {
  ClipboardSession clipboard;
  if (!clipboard.is_open()) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }

  std::vector<ClipboardData> backup;
  UINT format = 0;
  SetLastError(ERROR_SUCCESS);
  while ((format = EnumClipboardFormats(format)) != 0) {
    auto copied = DuplicateClipboardFormat(format);
    if (!copied) {
      return std::nullopt;
    }
    backup.push_back(std::move(*copied));
    SetLastError(ERROR_SUCCESS);
  }
  if (GetLastError() != ERROR_SUCCESS) {
    return std::nullopt;
  }
  return std::optional<std::vector<ClipboardData>>(std::move(backup));
}

bool RestoreClipboard(std::vector<ClipboardData>& backup) {
  ClipboardSession clipboard;
  if (!clipboard.is_open()) {
    const DWORD error = GetLastError();
    (void)error;
    return false;
  }
  if (!EmptyClipboard()) {
    const DWORD error = GetLastError();
    (void)error;
    return false;
  }
  for (auto& item : backup) {
    if (!SetClipboardData(item.format, item.handle)) {
      const DWORD error = GetLastError();
      (void)error;
      return false;
    }
    item.Release();
  }
  return true;
}

HWND CopyTargetForForegroundWindow(HWND foreground) {
  DWORD thread_id = GetWindowThreadProcessId(foreground, nullptr);
  GUITHREADINFO info = {};
  info.cbSize = sizeof(info);
  if (GetGUIThreadInfo(thread_id, &info) && info.hwndFocus) {
    return info.hwndFocus;
  }
  return foreground;
}

bool SendCopyCommand(HWND foreground) {
  HWND target = CopyTargetForForegroundWindow(foreground);
  DWORD_PTR result = 0;
  return SendMessageTimeoutW(target, WM_COPY, 0, 0, SMTO_ABORTIFHUNG, 200,
                             &result) != 0;
}

std::optional<std::wstring> ReadUnicodeClipboardText() {
  ClipboardSession clipboard;
  if (!clipboard.is_open()) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  HGLOBAL handle = static_cast<HGLOBAL>(GetClipboardData(CF_UNICODETEXT));
  if (!handle) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  GlobalLockGuard text_lock(handle);
  if (!text_lock.data()) {
    const DWORD error = GetLastError();
    (void)error;
    return std::nullopt;
  }
  return std::wstring(static_cast<const wchar_t*>(text_lock.data()));
}

std::optional<std::string> WaitForCopiedText(DWORD initial_sequence) {
  auto deadline = std::chrono::steady_clock::now() + kClipboardTimeout;
  auto delay = kInitialClipboardRetryDelay;
  while (std::chrono::steady_clock::now() <= deadline) {
    if (GetClipboardSequenceNumber() != initial_sequence) {
      auto text = ReadUnicodeClipboardText();
      if (text) {
        return Utf8FromWide(*text);
      }
    }
    std::this_thread::sleep_for(delay);
    delay = std::min(delay * 2, kMaxClipboardRetryDelay);
  }
  return std::nullopt;
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
  {
    std::lock_guard<std::mutex> lock(capture_channel_mutex_);
    capture_channel_.reset();
  }
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
  {
    std::lock_guard<std::mutex> lock(capture_channel_mutex_);
    capture_channel_.reset();
  }
  JoinCaptureThreads();
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
  auto capture_channel =
      std::make_shared<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "org.abyssl.translator/capture",
          &flutter::StandardMethodCodec::GetInstance());
  {
    std::lock_guard<std::mutex> lock(capture_channel_mutex_);
    capture_channel_ = capture_channel;
  }

  capture_channel->SetMethodCallHandler(
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
  bool should_capture = false;
  {
    std::lock_guard<std::mutex> lock(last_hotkey_time_mutex_);
    if (last_hotkey_time_.time_since_epoch().count() != 0 &&
        now - last_hotkey_time_ <= kDoubleTapWindow) {
      last_hotkey_time_ = std::chrono::steady_clock::time_point();
      should_capture = true;
    } else {
      last_hotkey_time_ = now;
    }
  }
  if (!should_capture) {
    return;
  }

  auto weak_alive = std::weak_ptr<std::atomic_bool>(alive_);
  std::weak_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      weak_capture_channel;
  {
    std::lock_guard<std::mutex> lock(capture_channel_mutex_);
    weak_capture_channel = capture_channel_;
  }

  {
    std::lock_guard<std::mutex> lock(capture_threads_mutex_);
    if (!alive_->load()) {
      return;
    }
    capture_threads_.emplace_back([weak_alive, weak_capture_channel]() {
      auto alive = weak_alive.lock();
      if (!alive || !alive->load() || weak_capture_channel.expired()) {
        return;
      }
      std::string text = FlutterWindow::CopySelectionFromForegroundWindow();
      alive = weak_alive.lock();
      auto capture_channel = weak_capture_channel.lock();
      if (!alive || !alive->load() || text.empty() || !capture_channel) {
        return;
      }
      capture_channel->InvokeMethod(
          "captureText", std::make_unique<flutter::EncodableValue>(text));
    });
  }
}

std::string FlutterWindow::CopySelectionFromForegroundWindow() {
  HWND foreground = GetForegroundWindow();
  if (!foreground) {
    return "";
  }

  std::lock_guard<std::mutex> lock(ClipboardMutex());
  auto backup = BackupClipboard();
  if (!backup) {
    return "";
  }
  DWORD initial_sequence = GetClipboardSequenceNumber();
  if (!SendCopyCommand(foreground)) {
    RestoreClipboard(*backup);
    return "";
  }
  auto copied_text = WaitForCopiedText(initial_sequence);
  if (!RestoreClipboard(*backup) || !copied_text) {
    return "";
  }
  return *copied_text;
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
