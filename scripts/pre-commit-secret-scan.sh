#!/usr/bin/env bash
# Pre-commit hook: scan staged additions for secrets/credentials.
# Install: ln -sf ../../scripts/pre-commit-secret-scan.sh .git/hooks/pre-commit

set -uo pipefail
IFS=$'\n'

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Regex patterns for high-signal secrets
CRITICAL_PATTERNS=(
    '(gh[ps]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,})'
    '(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}'
    '------BEGIN\s?(RSA|DSA|EC|OPENSSH|PGP)\s?PRIVATE KEY------'
    'xox[baprs]-[A-Za-z0-9-]{10,}'
    'sk-[a-zA-Z0-9]{20,}([A-Za-z0-9_-]{20,})?'
)

HIGH_PATTERNS=(
    '(password|passwd|pwd|secret|token|apikey|api_key)[\s:=,]+['"'"'"\"]?.{8,}'
    'mongodb(\+srv)?://[^\s]+@'
    'postgres(ql)?://[^\s]+@'
    'mysql://[^\s]+@'
    'redis:***@'
)

staged_files=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null)
[ -z "$staged_files" ] && exit 0

issues=()

for file in $staged_files; do
    while IFS= read -r raw_line; do
        [ -z "$raw_line" ] && continue
        # Format: "42:+content" from grep -n (lineno:+staged_line)
        lineno="${raw_line%%:*}"
        content="${raw_line#*:}"     # e.g. "+api_key = \"sk-...\""
        stripped="${content:1}"      # remove leading '+'
        [ -z "$stripped" ] && continue

        for pat in "${CRITICAL_PATTERNS[@]}"; do
            if echo "$stripped" | grep -qE "$pat" 2>/dev/null; then
                issues+=("CRITICAL|$file|$lineno|$stripped")
                break
            fi
        done
    done < <(git diff --cached --diff-filter=ACMR -U0 "$file" 2>/dev/null | grep -n '^+[^+]')
done

[ ${#issues[@]} -eq 0 ] && exit 0

echo ""
echo "⚠️  SECRET SCAN BLOCKED — potential secrets in staged changes:"
echo ""
for issue in "${issues[@]}"; do
    IFS='|' read -r level file lineno snippet <<< "$issue"
    color="$YELLOW"
    [ "$level" = "CRITICAL" ] && color="$RED"
    display="${snippet:0:80}"
    echo "  ${color}${level}${NC}  ${file}:${lineno}"
    echo "       ${display}"
    echo ""
done
echo "❌ Commit blocked: ${#issues[@]} potential secret(s) found."
echo "   Review flagged lines above."
echo "   To skip (if false positive): git commit --no-verify"
exit 1
