#!/usr/bin/env bash
set -euo pipefail

# fix-adaptive.sh
# Patches Claude Code's cli.js to replace type:"adaptive" with forced thinking.
# Works across versions by using regex to match minified variable names.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== Claude Code Adaptive Thinking Patcher ==="
echo ""

# --- Find cli.js ---
CLI_JS=""

# Method 1: via 'which claude'
if command -v claude &>/dev/null; then
    CLAUDE_BIN=$(which claude)
    # Resolve symlink if needed
    if [[ -L "$CLAUDE_BIN" ]]; then
        CLAUDE_BIN=$(readlink -f "$CLAUDE_BIN")
    fi
    CLAUDE_DIR=$(dirname "$CLAUDE_BIN")
    CANDIDATE="$CLAUDE_DIR/node_modules/@anthropic-ai/claude-code/cli.js"
    if [[ -f "$CANDIDATE" ]]; then
        CLI_JS="$CANDIDATE"
    fi
fi

# Method 2: common install paths
if [[ -z "$CLI_JS" ]]; then
    SEARCH_PATHS=(
        "$HOME/.claude/local/node_modules/@anthropic-ai/claude-code/cli.js"
        "$HOME/.npm-global/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        "/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"
        "/usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"
    )
    # Windows (Git Bash) paths
    if [[ -n "${APPDATA:-}" ]]; then
        APPDATA_UNIX=$(cygpath -u "$APPDATA" 2>/dev/null || echo "$APPDATA")
        SEARCH_PATHS+=("$APPDATA_UNIX/npm/node_modules/@anthropic-ai/claude-code/cli.js")
    fi

    for path in "${SEARCH_PATHS[@]}"; do
        if [[ -f "$path" ]]; then
            CLI_JS="$path"
            break
        fi
    done
fi

if [[ -z "$CLI_JS" ]]; then
    echo -e "${RED}ERROR: Could not find cli.js${NC}"
    echo "Make sure Claude Code is installed and 'claude' is in your PATH."
    exit 1
fi

echo -e "Found cli.js at: ${GREEN}$CLI_JS${NC}"

# --- Count occurrences ---
COUNT=$(grep -c 'type:"adaptive"' "$CLI_JS" || true)
echo "Found $COUNT line(s) containing type:\"adaptive\""

if [[ "$COUNT" -eq 0 ]]; then
    echo -e "${YELLOW}No adaptive thinking patterns found. Already patched or unsupported version.${NC}"
    exit 0
fi

# --- Backup ---
BACKUP="${CLI_JS}.bak"
cp "$CLI_JS" "$BACKUP"
echo ""
echo -e "${GREEN}[BACKUP] Original cli.js saved to:${NC}"
echo -e "  $BACKUP"
echo -e "${GREEN}[BACKUP] You can restore the original at any time (see end of output).${NC}"
echo ""

# --- Patch 1: Main API path ---
# The main path has this pattern near CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING:
#   if(!VAR(process.env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING)&&VAR(VAR.model))VAR={type:"adaptive"};else{...}
# We replace the condition with !1 to force the else-branch (which uses model-specific budget).
echo "Patch 1: Forcing main API path to use model-specific thinking budget..."
sed -i -E 's/![a-zA-Z0-9$_]+\(process\.env\.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING\)&&[a-zA-Z0-9$_]+\([a-zA-Z0-9$_]+\.model\)/!1/g' "$CLI_JS"

# --- Patch 2: All remaining {type:"adaptive"} ---
# Subagent and init paths use {type:"adaptive"} in ternaries and assignments.
# Replace with {type:"enabled",budget_tokens:10000}.
echo "Patch 2: Replacing remaining adaptive patterns with enabled + fixed budget..."
sed -i 's/{type:"adaptive"}/{type:"enabled",budget_tokens:10000}/g' "$CLI_JS"

# --- Patch 3: Set env var persistently ---
ENV_LINE='export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1'
SHELL_RC=""

# Detect shell profile
if [[ -n "${ZSH_VERSION:-}" ]] || [[ "$SHELL" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
elif [[ -f "$HOME/.bashrc" ]]; then
    SHELL_RC="$HOME/.bashrc"
elif [[ -f "$HOME/.bash_profile" ]]; then
    SHELL_RC="$HOME/.bash_profile"
elif [[ -f "$HOME/.profile" ]]; then
    SHELL_RC="$HOME/.profile"
fi

if [[ -n "$SHELL_RC" ]]; then
    if grep -qF 'CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING' "$SHELL_RC" 2>/dev/null; then
        echo "Patch 3: CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING already set in $SHELL_RC"
    else
        echo "" >> "$SHELL_RC"
        echo "# Disable Claude Code adaptive thinking (covers main API path)" >> "$SHELL_RC"
        echo "$ENV_LINE" >> "$SHELL_RC"
        echo -e "Patch 3: Added ${GREEN}CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1${NC} to $SHELL_RC"
    fi
else
    echo -e "${YELLOW}Patch 3: Could not detect shell profile. Manually add to your shell config:${NC}"
    echo "  $ENV_LINE"
fi

# Set for current session too
export CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1

# --- Verify ---
REMAINING=$(grep -c 'type:"adaptive"' "$CLI_JS" || true)
echo ""
if [[ "$REMAINING" -eq 0 ]]; then
    echo -e "${GREEN}SUCCESS: All adaptive thinking patterns patched.${NC}"
    PATCHED=$(grep -c 'budget_tokens:10000' "$CLI_JS" || true)
    echo "  $PATCHED replacement(s) applied."
else
    echo -e "${RED}WARNING: $REMAINING pattern(s) remain unpatched. Manual inspection needed.${NC}"
fi

echo ""
echo "==========================================="
echo -e "${GREEN}[BACKUP] Your original cli.js is backed up at:${NC}"
echo -e "  $BACKUP"
echo -e "${GREEN}[BACKUP] To restore, run:${NC}"
echo -e "  ${YELLOW}cp \"$BACKUP\" \"$CLI_JS\"${NC}"
echo "==========================================="
echo ""
echo -e "${YELLOW}Note: Auto-updates will overwrite this patch. Re-run after updating Claude Code.${NC}"
echo -e "${YELLOW}Note: This patch has no effect on Opus 4.7, which only supports adaptive thinking.${NC}"
echo -e "${YELLOW}      For Opus 4.7, use effort levels (low/medium/high/xhigh) to control reasoning depth.${NC}"
