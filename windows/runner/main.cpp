#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Open at up to 1280x800 logical pixels, centered, and never larger than
  // ~92% of the primary monitor's work area. Win32Window::Create multiplies
  // by the monitor scale (125%/150% on most laptops), so the work area is
  // converted to logical pixels first.
  RECT work = {0, 0, 1280, 800};
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work, 0);
  const POINT primary = {work.left + 1, work.top + 1};
  const double scale =
      FlutterDesktopGetDpiForMonitor(
          ::MonitorFromPoint(primary, MONITOR_DEFAULTTOPRIMARY)) /
      96.0;
  const int work_w = static_cast<int>((work.right - work.left) / scale);
  const int work_h = static_cast<int>((work.bottom - work.top) / scale);
  const int width = (std::min)(1280, work_w * 92 / 100);
  const int height = (std::min)(800, work_h * 92 / 100);
  Win32Window::Point origin(
      static_cast<int>(work.left / scale) + (work_w - width) / 2,
      static_cast<int>(work.top / scale) + (work_h - height) / 2);
  Win32Window::Size size(width, height);
  if (!window.Create(L"HK Tools", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
