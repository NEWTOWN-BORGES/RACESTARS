#!/usr/bin/env bash
# Godot 4.6.3, templates oficiais, SDK Android configurado e NSIS são pré-requisitos.
set -euo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$repo_dir/build/release/windows"
godot --headless --path "$repo_dir/game" --export-release "Windows Desktop" "$repo_dir/build/release/windows/RACESTARS.exe"
godot --headless --path "$repo_dir/game" --export-release "Android" "$repo_dir/build/release/RACESTARS-0.8-unsigned.apk"
"$repo_dir/tools/package_windows.sh" 0.8
printf '%s\n' 'Assine o APK com a chave adequada antes de distribuir. O APK sem assinatura não é instalável.'
