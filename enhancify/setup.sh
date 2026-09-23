#!/usr/bin/env bash
# Enhancify one-time setup (macOS / Linux). Run from the project folder: ./setup.sh
set -e
flutter create . --org com.theoccess --project-name enhancify --platforms android,ios
flutter pub get
dart run tool/setup_platforms.dart
dart run flutter_launcher_icons
echo ""
echo "Done. Plug in your phone and run:  flutter run"
