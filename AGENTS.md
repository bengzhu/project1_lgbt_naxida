# Repository Guidelines

## Project Structure & Module Organization

This repository contains a SwiftUI iOS prototype named `AITRANS`. App code lives under `AITRANS/`: `App/` contains the entry point, `Views/` holds SwiftUI screens and UI styling, `Services/` contains OCR, local model, download, probe, and persistence logic, `Models/` contains shared data types, and `Resources/` contains `Info.plist` and asset catalogs. `AITRANS.xcodeproj` defines the single `AITRANS` scheme/target. `build-apple/` stores the bundled `llama.xcframework`; rebuild it with `Tools/build-llama-ios-xcframework.sh` only when updating llama artifacts. `test/` contains bundled probe fixtures such as OCR images and ground truth JSON. Generated probe exports belong in `output/`.

## Build, Test, and Development Commands

- `open AITRANS.xcodeproj`: open the app in Xcode for simulator or device runs.
- `xcodebuild -list -project AITRANS.xcodeproj`: confirm available schemes and configurations.
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project AITRANS.xcodeproj -scheme AITRANS -destination 'generic/platform=iOS Simulator' -derivedDataPath .derivedData CODE_SIGNING_ALLOWED=NO build`: command-line simulator build without signing.
- `bash scripts/export-probe-output.sh`: export the latest probe artifacts from the app output area when available.

There is currently no dedicated XCTest target. Treat successful builds and probe runs as the minimum verification.

## Coding Style & Naming Conventions

Use Swift defaults: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for properties/functions, and descriptive enum cases. Keep SwiftUI views small enough to scan; move shared UI into `Views/AppTheme.swift` or focused helper views. Keep model/runtime code in `Services/`, and avoid mixing probe-only diagnostics into user-facing UI paths unless gated.

## Testing Guidelines

Place durable OCR/audio fixtures in `test/`; rebuild and reinstall because the folder is bundled as a resource. For manga/OCR work, update or verify `test/1.ground_truth.json`, run the in-app probe, and inspect `probe_report.json`, overlay PNGs, and any exported `output/` files. Do not commit transient simulator data or large generated artifacts unless they document an intentional regression/probe result.

## Commit & Pull Request Guidelines

Git history uses short, informal progress commits, often in Chinese. Keep commits concise and outcome-focused, for example `优化 OCR 探针判定` or `Fix local model download state`. PRs should include a summary, verification steps (`xcodebuild`, probe run, screenshots for UI changes), linked issues if any, and notes about model/framework asset changes. Mention any required App Store Connect, signing, or local GGUF setup.

## Security & Configuration Tips

Do not commit secrets, signing identities, downloaded private models, or App Store credentials. Keep `IPA_PASSWORD` in GitHub Actions secrets. Local model files should remain in the app sandbox or ignored local paths, not in the repository.
