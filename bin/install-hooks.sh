#!/bin/bash
# Enable git hooks for jekyll-client-search
#
# Hooks live in bin/hooks/ as TRACKED files and git is pointed at them
# via core.hooksPath — no copying, so installed hooks can't drift from
# the committed ones. Run once after cloning.
#
# pre-commit:  rubocop + semgrep (fast, ~5s)
# pre-push:    rake quick (rubocop + rspec)
#
# Usage: bin/install-hooks.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

git -C "$REPO_ROOT" config core.hooksPath bin/hooks

echo "✅ Git hooks enabled (core.hooksPath=bin/hooks):"
echo "   pre-commit:  rubocop + semgrep (fast, ~5s)"
echo "   pre-push:    rake quick (rubocop + rspec)"
echo ""
echo "   Skip with: git commit --no-verify  /  git push --no-verify"
