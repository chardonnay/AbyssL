# AbyssL Flutter

Current Flutter desktop implementation of AbyssL Translator for macOS, Windows, and Linux.

## Implemented scope

- Translator, spelling correction, rewriting, and document processing workspaces.
- OpenAI-compatible API calls using the existing endpoints:
  - `/v1/chat/completions`
  - `/v1/models`
  - `/api/v1/models`
- Cross-platform settings with non-secret preferences in `shared_preferences` and API keys in `flutter_secure_storage`.
- Portable document IR with TXT, Markdown, AsciiDoc, HTML, RTF, CSV, TSV, DOCX, XLSX, PDF export, and optional ODT via LibreOffice `soffice`.
- macOS global capture adapter using Accessibility/Input Monitoring and clipboard copy.
- Windows capture adapter using a low-level keyboard hook and clipboard copy.
- Linux capture status adapter that reports Wayland/X11 limitations instead of claiming unsupported behavior works.

## Build and validation

```bash
flutter analyze
flutter test
flutter build macos --debug
```

The repository macOS release helper runs the Flutter build from the repo root:

```bash
bash scripts/build-macos-release.sh
```

Windows and Linux builds must be validated on their respective hosts:

```bash
flutter build windows --debug
flutter build linux --debug
```

Manual capture validation:

1. Start the Flutter app.
2. Open Settings and confirm the capture shortcut.
3. Select text in a native editor.
4. Trigger the shortcut twice.
5. Verify the selected text appears in the Translator source field.

Linux note: Wayland does not provide a generic safe global text-capture API to this app. Validate the status message on each target desktop session and use manual copy/paste where capture is blocked by the display server.
