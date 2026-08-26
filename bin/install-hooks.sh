#!/bin/bash
# Install git hooks for jekyll-client-search
#
# pre-commit:  rubocop only (fast, ~2s)
# pre-push:    rubocop + rspec (full quality gate before pushing)
#
# Usage: bin/install-hooks.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

mkdir -p "$HOOKS_DIR"

# pre-commit: fast style check only
cat > "$HOOKS_DIR/pre-commit" << 'HOOK'
#!/bin/bash
# Pre-commit hook — fast style check only
# Full tests run on pre-push and in CI

echo "🔍 Running RuboCop..."
if bundle exec rubocop --force-exclusion; then
    echo "✅ Style checks passed"
    exit 0
else
    echo "❌ Style checks failed"
    echo "Fix the issues or use 'git commit --no-verify' to skip"
    exit 1
fi
HOOK
chmod +x "$HOOKS_DIR/pre-commit"

# pre-push: full quality gate (rubocop + rspec)
cat > "$HOOKS_DIR/pre-push" << 'HOOK'
#!/bin/bash
# Pre-push hook — full quality gate before pushing
# Reads stdin (list of refs being pushed) but ignores it

echo "🔍 Running pre-push checks (rubocop + rspec)..."
echo ""

if bundle exec rake quick 2>&1 | grep -q "✅ Quick checks passed"; then
    echo ""
    echo "✅ Pre-push checks passed"
    exit 0
else
    echo ""
    echo "❌ Pre-push checks failed"
    echo ""
    echo "Fix the issues or use 'git push --no-verify' to skip"
    exit 1
fi
HOOK
chmod +x "$HOOKS_DIR/pre-push"

echo "✅ Installed git hooks:"
echo "   pre-commit:  rubocop only (fast, ~2s)"
echo "   pre-push:    rubocop + rspec (full quality gate)"
echo ""
echo "   Skip with: git commit --no-verify  /  git push --no-verify"
