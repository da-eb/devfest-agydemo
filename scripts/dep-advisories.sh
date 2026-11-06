#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# Dependency advisories, picked from the repo's own stack
# ══════════════════════════════════════════════════════════════════════════════
# Looks for dependency manifests, works out which ecosystems the repo uses, and
# runs the matching advisory scanner for each one.
#
# Usage:  scripts/dep-advisories.sh [outfile]      (default: deps-audit.txt)
#
# Every scanner's raw output goes into <outfile>. Scanners that are missing or
# that failed are listed there too (lines starting with "#"), so a skipped
# ecosystem never looks like a clean one.
#
# Exit code: 0 if at least one scan produced output, 3 if nothing was scanned.
# ══════════════════════════════════════════════════════════════════════════════

set -uo pipefail

OUT="${1:-deps-audit.txt}"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
: > "$OUT_ABS"

SEEN=""      # "dir|command" pairs already handled, so one scanner never runs twice
FOUND=0      # manifests recognised
SCANNED=0    # scans that produced output

say() {      # print a status line and keep it in the output file for agy to read
  echo "  $1"
  echo "# $1" >> "$OUT_ABS"
}

# run <ecosystem> <dir> <binary to check for> <install hint> <command...>
run() {
  local eco=$1 dir=$2 bin=$3 hint=$4; shift 4
  case "$SEEN" in *"|$dir|$*|"*) return ;; esac
  SEEN="$SEEN|$dir|$*|"
  FOUND=$((FOUND + 1))

  if ! command -v "$bin" > /dev/null 2>&1; then
    say "NOT SCANNED  $eco in $dir: $bin is not installed ($hint)"
    return
  fi

  local out rc
  out=$(cd "$dir" && "$@" 2>&1); rc=$?

  # Scanners exit 1 (composer: up to 3) when they FIND advisories, so a low exit
  # code with output is a real scan. Empty output, a high exit code or a missing
  # lockfile means the scan didn't happen.
  if [ -z "$out" ] || [ "$rc" -gt 3 ]; then
    say "NOT SCANNED  $eco in $dir: '$*' failed (exit $rc). $(echo "$out" | head -n 1 | cut -c1-120)"
    return
  fi
  if echo "$out" | grep -q 'ENOLOCK'; then
    say "NOT SCANNED  $eco in $dir: no lockfile. Run the package manager's install first."
    return
  fi

  {
    echo "=== $eco advisories for $dir (command: $*) ==="
    echo "$out" | head -c 40000
    echo
  } >> "$OUT_ABS"
  SCANNED=$((SCANNED + 1))
  say "SCANNED      $eco in $dir: $*"
}

# Manifests up to four levels deep. Vendored and build directories are skipped.
while IFS= read -r f; do
  dir=$(dirname "$f")
  name=$(basename "$f")
  case "$name" in
    package.json)
      if [ -f "$dir/pnpm-lock.yaml" ]; then
        run javascript "$dir" pnpm "npm install -g pnpm" pnpm audit --json
      elif [ -f "$dir/yarn.lock" ] && [ -f "$dir/.yarnrc.yml" ]; then
        run javascript "$dir" yarn "enable it with: corepack enable" yarn npm audit --json
      elif [ -f "$dir/yarn.lock" ]; then
        run javascript "$dir" yarn "enable it with: corepack enable" yarn audit --json
      else
        run javascript "$dir" npm "install Node.js" npm audit --json
      fi ;;
    requirements*.txt)
      run python "$dir" pip-audit "pip install pip-audit" pip-audit -r "$name" -f json ;;
    go.mod)
      run go "$dir" govulncheck "go install golang.org/x/vuln/cmd/govulncheck@latest" govulncheck -json ./... ;;
    Cargo.lock)
      run rust "$dir" cargo-audit "cargo install cargo-audit" cargo audit --json ;;
    Gemfile.lock)
      run ruby "$dir" bundle-audit "gem install bundler-audit" bundle-audit check --format json ;;
    composer.lock)
      run php "$dir" composer "install Composer 2.4 or newer" composer audit --format=json ;;
    *.csproj)
      run dotnet "$dir" dotnet "install the .NET SDK" dotnet list "$name" package --vulnerable --include-transitive ;;
    pom.xml|build.gradle|build.gradle.kts|gradle.lockfile|poetry.lock|Pipfile.lock|uv.lock)
      run other "$dir" osv-scanner "see github.com/google/osv-scanner" osv-scanner scan source --format json -r . ;;
  esac
done < <(find . -maxdepth 5 \
  \( -name node_modules -o -name .git -o -name vendor -o -name .venv -o -name venv \
     -o -name target -o -name dist -o -name build \) -prune -o \
  -type f \( -name package.json -o -name 'requirements*.txt' -o -name go.mod \
     -o -name Cargo.lock -o -name Gemfile.lock -o -name composer.lock -o -name '*.csproj' \
     -o -name pom.xml -o -name build.gradle -o -name build.gradle.kts -o -name gradle.lockfile \
     -o -name poetry.lock -o -name Pipfile.lock -o -name uv.lock \) -print | sort)

if [ "$FOUND" -eq 0 ]; then
  say "No supported dependency manifest found (package.json, requirements.txt, go.mod, Cargo.lock, Gemfile.lock, composer.lock, *.csproj, pom.xml, build.gradle ...)."
fi

if [ "$SCANNED" -gt 0 ]; then exit 0; else exit 3; fi
