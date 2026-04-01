#!/bin/bash
set -e

# Inkos Binary Build Script
# This script bundles the project and creates a standalone executable
# using Node.js Single Executable Application (SEA).

echo "🚀 Building Inkos binary..."

# Navigate to project root
cd "$(dirname "$0")/.."
PROJECT_ROOT=$(pwd)

# 1. Ensure build is up to date
echo "📦 Running pnpm build to compile TypeScript..."
pnpm run build

# 2. Create polyfill for import.meta.url
# Node SEA supports CommonJS, which doesn't natively have import.meta.url.
# We polyfill it so that ESM libraries checking import.meta.url won't crash.
echo "🔧 Setting up ES modules polyfill..."
cat << 'EOF' > scripts/import-meta-polyfill.js
import { pathToFileURL } from 'node:url';
export const import_meta_url = typeof __filename !== 'undefined' ? pathToFileURL(__filename).href : "file:///";
EOF

# 3. Bundle everything into a single CommonJS file using esbuild
echo "🏗️ Bundling the application with esbuild..."
mkdir -p dist

# Bundle and inject polyfill
npx -y esbuild packages/cli/dist/index.js \
    --bundle \
    --platform=node \
    --format=cjs \
    --target=node20 \
    --inject:scripts/import-meta-polyfill.js \
    --define:import.meta.url=import_meta_url \
    --outfile=dist/inkos.bundle.cjs

# 4. Create Node.js SEA configuration
echo "⚙️ Creating SEA configuration..."
cat << 'EOF' > dist/sea-config.json
{
  "main": "dist/inkos.bundle.cjs",
  "output": "dist/sea-prep.blob",
  "disableExperimentalSEAWarning": true
}
EOF

# 5. Generate the SEA blob
echo "💧 Generating SEA blob..."
node --experimental-sea-config dist/sea-config.json

# 6. Copy the active Node.js executable
echo "📄 Copying Node.js executable..."
cp $(command -v node) dist/inkos

# 7. Remove existing code signature (Required on macOS)
if [ "$(uname)" == "Darwin" ]; then
    echo "🍏 macOS detected, removing code signature..."
    codesign --remove-signature dist/inkos || true
fi

# 8. Inject the blob into the copied executable
echo "💉 Injecting blob into the executable..."
if [ "$(uname)" == "Darwin" ]; then
    npx -y postject dist/inkos NODE_SEA_BLOB dist/sea-prep.blob \
        --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2 \
        --macho-segment-name NODE_SEA
else
    npx -y postject dist/inkos NODE_SEA_BLOB dist/sea-prep.blob \
        --sentinel-fuse NODE_SEA_FUSE_fce680ab2cc467b6e072b8b5df1996b2
fi

# 9. Re-sign the executable (Required on macOS)
if [ "$(uname)" == "Darwin" ]; then
    echo "🍏 macOS detected, re-signing the new executable..."
    codesign --sign - dist/inkos || true
fi

# Make it executable
chmod +x dist/inkos

echo "✅ Standalone binary successfully generated at dist/inkos"

# 10. Link to user's local bin directory
USER_BIN="$HOME/.local/bin"
echo "🔗 Linking to $USER_BIN/inkos..."

# Create ~/.local/bin if it doesn't exist
mkdir -p "$USER_BIN"

ln -sf "$PROJECT_ROOT/dist/inkos" "$USER_BIN/inkos"
echo "🎉 Successfully linked!"

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$USER_BIN:"* ]]; then
    echo ""
    echo "⚠️  Warning: $USER_BIN is not in your PATH."
    echo "   Add the following line to your ~/.zshrc or ~/.bashrc:"
    echo ""
    echo "   export PATH=\"\$HOME/.local/bin:\$PATH\""
    echo ""
    echo "   Then run: source ~/.zshrc (or ~/.bashrc)"
else
    echo "   You can now run 'inkos' directly anywhere."
fi
