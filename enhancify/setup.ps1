# Enhancify one-time setup (Windows PowerShell). Run from the project folder:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
$ErrorActionPreference = "Stop"
flutter create . --org com.theoccess --project-name enhancify --platforms android,ios
flutter pub get
dart run tool/setup_platforms.dart
dart run flutter_launcher_icons
Write-Host "`nDone. Plug in your phone and run:  flutter run"
