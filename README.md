# Fix Claude Code Adaptive Thinking

Claude Code uses `type:"adaptive"` to dynamically decide whether to engage reasoning (thinking tokens) for each request. In practice, the adaptive classifier is too aggressive — it suppresses thinking on 60-80% of "easy" tasks and gets them wrong.

The `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` environment variable only covers 1 of the 4 code paths that set `type:"adaptive"`. These scripts patch all of them.

## What the patch does

1. **Main API path**: Forces the else-branch that uses the model-specific thinking budget (`Math.min(max_tokens - 1, model_default)`) instead of adaptive classification.
2. **Subagent/init paths**: Replaces `{type:"adaptive"}` with `{type:"enabled",budget_tokens:10000}` — a fixed budget that ensures thinking is always active.

The scripts use regex to match the minified variable names dynamically, so they work across different cli.js versions.

## Usage

### Windows (PowerShell)

```powershell
.\fix-adaptive.ps1
```

If you get an execution policy error:

```powershell
powershell -ExecutionPolicy Bypass -File .\fix-adaptive.ps1
```

### Linux / macOS / Git Bash (Windows)

```bash
chmod +x fix-adaptive.sh
./fix-adaptive.sh
```

## Restoring the original

Both scripts create a `.bak` backup next to `cli.js`. To restore:

**PowerShell:**
```powershell
Copy-Item "path\to\cli.js.bak" "path\to\cli.js" -Force
```

**Bash:**
```bash
cp "path/to/cli.js.bak" "path/to/cli.js"
```

The restore command with the full path is printed at the end of each script run.

## Important notes

- **Auto-updates overwrite the patch.** Re-run the script after Claude Code updates.
- **Version-independent.** The scripts use regex patterns anchored to stable strings (`CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `type:"adaptive"`) rather than minified variable names, so they should work across versions.
- **Backup is always created** before patching. If 0 patterns are found, the script exits without modifying anything.
- **No effect on Opus 4.7.** Opus 4.7 only supports adaptive thinking — it's baked into the model architecture and cannot be overridden via `cli.js` or env vars. Sending `type:"enabled"` with a fixed budget returns a 400 error. For Opus 4.7, use effort levels (`low` / `medium` / `high` / `xhigh`) to control reasoning depth instead.

## Credits

Based on benchmark research from [GitHub issue discussion](https://github.com/anthropics/claude-code/issues) comparing patched vs unpatched Claude Code across accuracy, cost, and latency.
