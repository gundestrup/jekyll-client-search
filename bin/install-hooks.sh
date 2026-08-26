#!/bin/bash
# Install git hooks for jekyll-client-search
# Mirrors the jekyll-documents pre-commit hook setup.
#
# Usage: bin/install-hooks.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

mkdir -p "$HOOKS_DIR"

cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
# Pre-commit hook for jekyll-client-search
# Runs quick quality checks before allowing commit

echo "🔍 Running pre-commit checks..."
echo ""

# Run quick checks (style + tests)
if bundle exec rake quick 2>&1 | grep -q "✅ Quick checks passed"; then
    echo ""
    echo "✅ Pre-commit checks passed"
    exit 0
else
    echo ""
    echo "❌ Pre-commit checks failed"
    echo ""
    echo "Fix the issues or use 'git commit --no-verify' to skip checks"
    exit 1
fi
HOOK

chmod +x "$HOOKS_DIR/pre-commit"

echo "✅ Installed pre-commit hook to $HOOKS_DIR/pre-commit"
echo "   Runs: bundle exec rake quick (rubocop + rspec)"
echo "   Skip with: git commit --no-verify"
