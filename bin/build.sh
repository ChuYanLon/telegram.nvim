#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

echo "==> Installing dependencies..."
pnpm install

# --- WS helper (pure JS, fully bundled) ---
echo "==> Bundling WS helper..."
npx esbuild bin/tg-ws-helper.js --bundle --platform=node \
  --outfile=bin/tg-ws-helper.bundle.js --minify

# --- Server bundle (all pure JS inlined) ---
echo "==> Bundling server JS..."
rm -rf dist
mkdir -p dist

npx esbuild src/server.js --bundle --platform=node \
  --outfile=dist/server.bundle.js \
  --external:tdl --external:node-gyp-build \
  --external:node-addon-api --external:prebuilt-tdlib

# --- Use pnpm deploy to generate minimal production node_modules ---
echo "==> Generating minimal node_modules via pnpm deploy..."
mkdir -p dist/deploy
cp package.json dist/deploy/
cd dist/deploy
pnpm install --prod --no-optional 2>&1 | tail -3
cd "$ROOT"

# Move the production node_modules to dist/
mv dist/deploy/node_modules dist/node_modules 2>/dev/null || true
# Ensure needed packages are there (pnpm may have different structure)
for pkg in tdl node-gyp-build node-addon-api prebuilt-tdlib; do
  if [ ! -d "dist/node_modules/$pkg" ]; then
    echo "  !! $pkg not in pnpm deploy output, copying manually"
    src=$(find node_modules/.pnpm -maxdepth 4 -type d -name "$pkg" \
      -not -path "*/node_modules/$pkg/node_modules/*" 2>/dev/null | sort -V | tail -1)
    if [ -n "$src" ]; then
      mkdir -p "dist/node_modules/$pkg"
      (cd "$src" && tar cf - --dereference .) | (cd "dist/node_modules/$pkg" && tar xf -)
    fi
  fi
done

# Ensure tdl has prebuilds
if [ -d "dist/node_modules/tdl" ] && [ ! -d "dist/node_modules/tdl/prebuilds" ]; then
  echo "  -> copying tdl prebuilds"
  src=$(find node_modules/.pnpm -maxdepth 4 -type d -name "tdl" \
    -not -path "*/node_modules/tdl/node_modules/*" 2>/dev/null | sort -V | tail -1)
  if [ -n "$src" ] && [ -d "$src/prebuilds" ]; then
    cp -r "$src/prebuilds" "dist/node_modules/tdl/"
  fi
fi

# Clean up deploy dir
rm -rf dist/deploy

# Strip dev artifacts from node_modules
find dist/node_modules -name '*.map' -o -name '*.ts' -o -name '*.flow' | xargs rm -f 2>/dev/null || true
find dist/node_modules -type d \( -name test -o -name tests -o -name example -o -name examples -o -name demo -o -name bench -o -name benchmarks \) -exec rm -rf {} + 2>/dev/null || true

# --- Copy DB/data files if present ---
for d in tdlib_db tdlib_files; do
  [ -d "$d" ] && cp -r "$d" "dist/$d"
done

echo ""
echo "==> Done"
du -sh dist/
echo ""
echo "  server.bundle.js:           $(wc -c < dist/server.bundle.js) bytes"
echo "  node_modules:               $(du -sh dist/node_modules/ | cut -f1)"
echo "  tg-ws-helper.bundle.js:     $(wc -c < bin/tg-ws-helper.bundle.js) bytes"
