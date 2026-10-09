#!/usr/bin/env bash
# Package an existing Windows export. Requires NSIS (makensis) and Python 3.
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
app_version="${1:-0.9}"
payload_dir="$repo_dir/build/release/windows"
output_file="$repo_dir/build/release/RACESTARS-$app_version-Windows-Setup.exe"

if [[ ! "$app_version" =~ ^[0-9]+(\.[0-9]+){1,3}$ ]]; then
  printf 'Invalid version: %s\n' "$app_version" >&2
  exit 1
fi
if [[ ! -s "$payload_dir/RACESTARS.exe" ]]; then
  printf 'Export the game to %s/RACESTARS.exe first.\n' "$payload_dir" >&2
  exit 1
fi

makensis_bin="${MAKENSIS:-makensis}"
if ! command -v "$makensis_bin" >/dev/null 2>&1; then
  printf 'Install NSIS or set MAKENSIS to its executable (and NSISDIR for a local toolchain).\n' >&2
  exit 1
fi

scratch_dir="$(mktemp -d /tmp/racestars-installer.XXXXXX)"
trap 'rm -rf -- "$scratch_dir"' EXIT

# Record exact shipped paths so uninstall never recursively deletes user files.
payload_kib="$(python3 - "$payload_dir" "$scratch_dir/uninstall.nsh" <<'PY'
from pathlib import Path
import sys

payload, manifest = map(Path, sys.argv[1:])
files, directories = [], []
size = 0
for item in sorted(payload.rglob('*')):
    if item.is_symlink():
        raise SystemExit(f'Symlinks are not supported in the Windows export: {item}')
    relative = item.relative_to(payload).as_posix()
    if '\n' in relative or '\r' in relative or '\\' in relative:
        raise SystemExit(f'Unsupported Windows payload path: {relative!r}')
    escaped = relative.replace('$', '$$').replace('"', '$\\"').replace('/', '\\')
    if item.is_file():
        files.append(f'  Delete "$INSTDIR\\{escaped}"')
        size += item.stat().st_size
    elif item.is_dir():
        directories.append((len(item.parts), f'  RMDir "$INSTDIR\\{escaped}"'))
manifest.write_text('\n'.join(files + [line for _, line in sorted(directories, reverse=True)]) + '\n')
print((size + 1023) // 1024)
PY
)"

"$makensis_bin" -V3 \
  "-DAPP_VERSION=$app_version" \
  "-DPAYLOAD_DIR=$payload_dir" \
  "-DPAYLOAD_UNINSTALL=$scratch_dir/uninstall.nsh" \
  "-DPAYLOAD_KIB=$payload_kib" \
  "-DOUTPUT_FILE=$output_file" \
  "$repo_dir/tools/windows_installer.nsi"

printf 'Installer: %s\n' "$output_file"
