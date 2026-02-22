# =============================================================================
# OpenClaw x Google Antigravity -- Patch Script (Windows)
# For use with rdp-session.yml (windows-latest)
#
# OpenClaw is installed via: npm install -g openclaw
# with NPM_CONFIG_PREFIX=C:\Users\rdpuser\.npm-global
# so the installation lives at: C:\Users\rdpuser\.npm-global\node_modules\openclaw
#
# Run after every `npm update -g openclaw` to reapply all fixes.
# Usage: powershell -ExecutionPolicy Bypass -File patch-windows.ps1 [-DryRun]
# =============================================================================

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# =============================================================================
# Detect OpenClaw installation directory
# =============================================================================
$rdpUserHome = "C:\Users\rdpuser"
$candidatePaths = @(
    "$rdpUserHome\.npm-global\node_modules\openclaw",
    "$env:NPM_CONFIG_PREFIX\node_modules\openclaw",
    "$env:APPDATA\npm\node_modules\openclaw"
)

$OPENCLAW_DIR = $null
foreach ($p in $candidatePaths) {
    if ($p -and (Test-Path $p)) {
        $OPENCLAW_DIR = $p
        break
    }
}

# Fallback: ask npm
if (-not $OPENCLAW_DIR) {
    try {
        $npmRoot = (npm root -g 2>$null).Trim()
        $candidate = Join-Path $npmRoot "openclaw"
        if (Test-Path $candidate) {
            $OPENCLAW_DIR = $candidate
        }
    } catch {}
}

if (-not $OPENCLAW_DIR -or -not (Test-Path $OPENCLAW_DIR)) {
    Write-Host "[X] Cannot find OpenClaw installation" -ForegroundColor Red
    exit 1
}

# =============================================================================
# Detect pi-ai location
# =============================================================================
$geminiCliFiles = Get-ChildItem -Path "$OPENCLAW_DIR\node_modules" -Recurse -Filter "google-gemini-cli.js" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*\providers\*" }

if (-not $geminiCliFiles -or $geminiCliFiles.Count -eq 0) {
    Write-Host "[X] Cannot find @mariozechner/pi-ai in $OPENCLAW_DIR" -ForegroundColor Red
    exit 1
}

$geminiCliPath = $geminiCliFiles[0].FullName
# Strip \dist\providers\google-gemini-cli.js to get the pi-ai root
$PI_AI_DIR = $geminiCliPath -replace '\\dist\\providers\\google-gemini-cli\.js$', ''

$DIST = Join-Path $OPENCLAW_DIR "dist"
$ANTIGRAVITY_VERSION = "1.18.4"
$PLATFORM = "windows/amd64"

# =============================================================================
# Helpers
# =============================================================================
function Log($msg) { Write-Host "[+] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Fail($msg) { Write-Host "[X] $msg" -ForegroundColor Red; exit 1 }

function Patch-File {
    param(
        [string]$FilePath,
        [string]$From,
        [string]$To,
        [string]$Description
    )

    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8

    if ($content.Contains($From)) {
        if ($DryRun) {
            Log "[DRY RUN] Would patch: $Description"
            return
        }
        Copy-Item -Path $FilePath -Destination "$FilePath.prepatch.bak" -Force
        $patched = $content.Replace($From, $To)
        [System.IO.File]::WriteAllText($FilePath, $patched, [System.Text.UTF8Encoding]::new($false))
        Log $Description
    }
    elseif ($content.Contains($To)) {
        Warn "$Description -- already patched, skipping"
    }
    else {
        Warn "$Description -- pattern not found in $(Split-Path $FilePath -Leaf), may need manual update"
    }
}

# =============================================================================
Write-Host ""
Write-Host "OpenClaw Antigravity Patch (Windows)"
Write-Host "OpenClaw dir: $OPENCLAW_DIR"
Write-Host "pi-ai dir:    $PI_AI_DIR"
if ($DryRun) { Write-Host "DRY RUN MODE -- no files will be modified" -ForegroundColor Yellow }
Write-Host ""

# =============================================================================
# 1. google-gemini-cli.js -- version, platform
# =============================================================================
$GEMINI_CLI = Join-Path $PI_AI_DIR "dist\providers\google-gemini-cli.js"
if (-not (Test-Path $GEMINI_CLI)) { Fail "Not found: $GEMINI_CLI" }

# Version: regex match any semver DEFAULT_ANTIGRAVITY_VERSION
$geminiContent = Get-Content -Path $GEMINI_CLI -Raw -Encoding UTF8
$versionPattern = 'const DEFAULT_ANTIGRAVITY_VERSION = "(\d+\.\d+\.\d+)"'
$versionMatch = [regex]::Match($geminiContent, $versionPattern)
if ($versionMatch.Success) {
    $currentVer = $versionMatch.Groups[1].Value
    if ($currentVer -eq $ANTIGRAVITY_VERSION) {
        Warn "google-gemini-cli: version already $ANTIGRAVITY_VERSION, skipping"
    } elseif ($DryRun) {
        Log "[DRY RUN] Would patch: google-gemini-cli version $currentVer -> $ANTIGRAVITY_VERSION"
    } else {
        Copy-Item -Path $GEMINI_CLI -Destination "$GEMINI_CLI.prepatch.bak" -Force
        $geminiContent = [regex]::Replace($geminiContent, $versionPattern, "const DEFAULT_ANTIGRAVITY_VERSION = `"$ANTIGRAVITY_VERSION`"")
        [System.IO.File]::WriteAllText($GEMINI_CLI, $geminiContent, [System.Text.UTF8Encoding]::new($false))
        Log "google-gemini-cli: version $currentVer -> $ANTIGRAVITY_VERSION"
    }
} else {
    Warn "google-gemini-cli: DEFAULT_ANTIGRAVITY_VERSION pattern not found, may need manual update"
}

# Platform: regex match any platform string after antigravity/${version}
# Re-read in case version patch updated the file
$geminiContent = Get-Content -Path $GEMINI_CLI -Raw -Encoding UTF8
$platformPattern = 'antigravity/\$\{version\} ([a-z]+/[a-z0-9]+)'
$platformMatch = [regex]::Match($geminiContent, $platformPattern)
if ($platformMatch.Success) {
    $currentPlat = $platformMatch.Groups[1].Value
    if ($currentPlat -eq $PLATFORM) {
        Warn "google-gemini-cli: platform already $PLATFORM, skipping"
    } elseif ($DryRun) {
        Log "[DRY RUN] Would patch: google-gemini-cli platform $currentPlat -> $PLATFORM"
    } else {
        Copy-Item -Path $GEMINI_CLI -Destination "$GEMINI_CLI.prepatch.bak" -Force
        # Use string .Replace() to avoid regex $ interpretation issues with ${version}
        $fromStr = "antigravity/`${version} $currentPlat"
        $toStr = "antigravity/`${version} $PLATFORM"
        $geminiContent = $geminiContent.Replace($fromStr, $toStr)
        [System.IO.File]::WriteAllText($GEMINI_CLI, $geminiContent, [System.Text.UTF8Encoding]::new($false))
        Log "google-gemini-cli: platform $currentPlat -> $PLATFORM"
    }
} else {
    Warn "google-gemini-cli: platform pattern not found, may need manual update"
}

# NOTE: endpoint left as daily-cloudcode-pa.sandbox.googleapis.com (the working default)
# Previously we patched this to cloudcode-pa, but the sandbox
# endpoint is what the mjs fix scripts used when things were working.

# =============================================================================
# 2. models.generated.js -- add new models
# =============================================================================
$MODELS_JS = Join-Path $PI_AI_DIR "dist\models.generated.js"
if (-not (Test-Path $MODELS_JS)) { Fail "Not found: $MODELS_JS" }

$modelsContent = Get-Content -Path $MODELS_JS -Raw -Encoding UTF8

if ($modelsContent.Contains('"antigravity-gemini-3-pro"')) {
    Warn "models.generated.js -- new models already present, skipping"
}
else {
    if ($DryRun) {
        Log "[DRY RUN] Would add new models to models.generated.js"
    }
    else {
        Copy-Item -Path $MODELS_JS -Destination "$MODELS_JS.prepatch.bak" -Force

        # Model IDs sourced from opencode-antigravity-auth plugin v1.6.0
        # https://github.com/NoeFabris/opencode-antigravity-auth#model-reference
        #
        # Antigravity quota models:
        #   antigravity-gemini-3-pro        (variants: low, high)
        #   antigravity-gemini-3.1-pro      (variants: low, high)
        #   antigravity-gemini-3-flash      (variants: minimal, low, medium, high)
        #   antigravity-claude-sonnet-4-6   (no variants)
        #   antigravity-claude-opus-4-6-thinking (variants: low, max)
        #
        # Gemini CLI quota models (separate quota pool):
        #   gemini-2.5-flash, gemini-2.5-pro, gemini-3-flash-preview,
        #   gemini-3-pro-preview, gemini-3.1-pro-preview,
        #   gemini-3.1-pro-preview-customtools
        $newModels = @'
        "antigravity-gemini-3-pro": {
            id: "antigravity-gemini-3-pro",
            name: "Gemini 3 Pro (Antigravity)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
            contextWindow: 1048576,
            maxTokens: 65535,
        },
        "antigravity-gemini-3.1-pro": {
            id: "antigravity-gemini-3.1-pro",
            name: "Gemini 3.1 Pro (Antigravity)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
            contextWindow: 1048576,
            maxTokens: 65535,
        },
        "antigravity-gemini-3-flash": {
            id: "antigravity-gemini-3-flash",
            name: "Gemini 3 Flash (Antigravity)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 0.5, output: 3, cacheRead: 0.5, cacheWrite: 0 },
            contextWindow: 1048576,
            maxTokens: 65536,
        },
        "antigravity-claude-sonnet-4-6": {
            id: "antigravity-claude-sonnet-4-6",
            name: "Claude Sonnet 4.6 (Antigravity)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: false,
            input: ["text", "image"],
            cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
            contextWindow: 200000,
            maxTokens: 64000,
        },
        "antigravity-claude-opus-4-6-thinking": {
            id: "antigravity-claude-opus-4-6-thinking",
            name: "Claude Opus 4.6 Thinking (Antigravity)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
            contextWindow: 200000,
            maxTokens: 64000,
        },
        "gemini-2.5-flash": {
            id: "gemini-2.5-flash",
            name: "Gemini 2.5 Flash (Gemini CLI)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 0.5, output: 3, cacheRead: 0.5, cacheWrite: 0 },
            contextWindow: 1048576,
            maxTokens: 65536,
        },
        "gemini-2.5-pro": {
            id: "gemini-2.5-pro",
            name: "Gemini 2.5 Pro (Gemini CLI)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
            contextWindow: 1048576,
            maxTokens: 65536,
        },
        "gemini-3-flash-preview": {
            id: "gemini-3-flash-preview",
            name: "Gemini 3 Flash Preview (Gemini CLI)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 0.5, output: 3, cacheRead: 0.5, cacheWrite: 0 },
            contextWindow: 1048576,
            maxTokens: 65536,
        },
        "gemini-3-pro-preview": {
            id: "gemini-3-pro-preview",
            name: "Gemini 3 Pro Preview (Gemini CLI)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
            contextWindow: 1048576,
            maxTokens: 65535,
        },
        "gemini-3.1-pro-preview": {
            id: "gemini-3.1-pro-preview",
            name: "Gemini 3.1 Pro Preview (Gemini CLI)",
            api: "google-gemini-cli",
            provider: "google-antigravity",
            baseUrl: "https://daily-cloudcode-pa.sandbox.googleapis.com",
            reasoning: true,
            input: ["text", "image"],
            cost: { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
            contextWindow: 1048576,
            maxTokens: 65535,
        },
'@

        # Insert new models after the google-antigravity provider opening
        # Handle both \n and \r\n line endings
        $searchLF = '"google-antigravity": {' + "`n"
        $searchCRLF = '"google-antigravity": {' + "`r`n"
        if ($modelsContent.Contains($searchCRLF)) {
            $replaceStr = '"google-antigravity": {' + "`r`n" + $newModels + "`r`n"
            $modelsContent = $modelsContent.Replace($searchCRLF, $replaceStr)
            Log "models.generated.js -- inserted new models (CRLF)"
        } elseif ($modelsContent.Contains($searchLF)) {
            $replaceStr = '"google-antigravity": {' + "`n" + $newModels + "`n"
            $modelsContent = $modelsContent.Replace($searchLF, $replaceStr)
            Log "models.generated.js -- inserted new models (LF)"
        } else {
            Warn "models.generated.js -- could not find 'google-antigravity' insertion point, models NOT added"
        }

        # NOTE: sandbox endpoint (daily-cloudcode-pa.sandbox.googleapis.com) is left as-is
        # for existing models -- this is the working endpoint.

        [System.IO.File]::WriteAllText($MODELS_JS, $modelsContent, [System.Text.UTF8Encoding]::new($false))
        Log "models.generated.js -- added new models (sandbox endpoint preserved)"
    }
}

# =============================================================================
# 3. dist files -- endpoint + isAnthropicProvider fix
# =============================================================================

# Find all relevant dist files dynamically (hash in filename changes per version)
$distFiles = @()

# pi-embedded-*.js (excluding pi-embedded-helpers-* and *.bak)
$distFiles += Get-ChildItem -Path $DIST -Filter "pi-embedded-*.js" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "pi-embedded-helpers-*" -and $_.Name -notlike "*.bak" }

# reply-*.js (excluding reply-prefix-* and *.bak)
$distFiles += Get-ChildItem -Path $DIST -Filter "reply-*.js" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "reply-prefix-*" -and $_.Name -notlike "*.bak" }

# plugin-sdk/reply-*.js
$pluginSdkDir = Join-Path $DIST "plugin-sdk"
if (Test-Path $pluginSdkDir) {
    $distFiles += Get-ChildItem -Path $pluginSdkDir -Filter "reply-*.js" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "reply-prefix-*" -and $_.Name -notlike "*.bak" }
}

# subagent-registry-*.js
$distFiles += Get-ChildItem -Path $DIST -Filter "subagent-registry-*.js" -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notlike "*.bak" }

foreach ($f in $distFiles) {
    $name = $f.Name

    Patch-File -FilePath $f.FullName `
        -From 'options?.modelProvider?.toLowerCase().includes("google-antigravity")' `
        -To 'false' `
        -Description "$name`: isAnthropicProvider -- remove google-antigravity"
}

# =============================================================================
# 4. openclaw.json -- ensure all models are in allowlist
# =============================================================================
$OPENCLAW_JSON = Join-Path $rdpUserHome ".openclaw\openclaw.json"

if (Test-Path $OPENCLAW_JSON) {
    if ($DryRun) {
        Log "[DRY RUN] Would update $OPENCLAW_JSON allowlist"
    }
    else {
        $config = Get-Content -Path $OPENCLAW_JSON -Raw -Encoding UTF8 | ConvertFrom-Json

        # Antigravity quota models
        $modelsToAdd = @(
            "google-antigravity/antigravity-gemini-3-pro",
            "google-antigravity/antigravity-gemini-3.1-pro",
            "google-antigravity/antigravity-gemini-3-flash",
            "google-antigravity/antigravity-claude-sonnet-4-6",
            "google-antigravity/antigravity-claude-opus-4-6-thinking",
            # Gemini CLI quota models
            "google-antigravity/gemini-2.5-flash",
            "google-antigravity/gemini-2.5-pro",
            "google-antigravity/gemini-3-flash-preview",
            "google-antigravity/gemini-3-pro-preview",
            "google-antigravity/gemini-3.1-pro-preview"
        )

        # Ensure nested structure exists
        if (-not $config.agents) {
            $config | Add-Member -NotePropertyName "agents" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not $config.agents.defaults) {
            $config.agents | Add-Member -NotePropertyName "defaults" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        if (-not $config.agents.defaults.models) {
            $config.agents.defaults | Add-Member -NotePropertyName "models" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }

        $added = 0
        foreach ($m in $modelsToAdd) {
            if (-not $config.agents.defaults.models.PSObject.Properties[$m]) {
                $config.agents.defaults.models | Add-Member -NotePropertyName $m -NotePropertyValue ([PSCustomObject]@{}) -Force
                $added++
            }
        }

        $config | ConvertTo-Json -Depth 20 | Out-File -FilePath $OPENCLAW_JSON -Encoding UTF8
        Log "openclaw.json allowlist updated (added $added models)"
    }
}
else {
    Warn "$OPENCLAW_JSON not found -- skipping allowlist update"
}

# =============================================================================
# 5. models.json -- ensure file exists
# =============================================================================
$MODELS_JSON = Join-Path $rdpUserHome ".openclaw\agents\main\agent\models.json"

if (-not (Test-Path $MODELS_JSON)) {
    if ($DryRun) {
        Log "[DRY RUN] Would create $MODELS_JSON"
    }
    else {
        $modelsJsonDir = Split-Path $MODELS_JSON -Parent
        New-Item -ItemType Directory -Path $modelsJsonDir -Force | Out-Null

        $modelsJsonContent = @'
{
  "providers": {
    "google-antigravity": {
      "modelOverrides": {
        "antigravity-gemini-3-pro": {},
        "antigravity-gemini-3.1-pro": {},
        "antigravity-gemini-3-flash": {},
        "antigravity-claude-sonnet-4-6": {},
        "antigravity-claude-opus-4-6-thinking": {},
        "gemini-2.5-flash": {},
        "gemini-2.5-pro": {},
        "gemini-3-flash-preview": {},
        "gemini-3-pro-preview": {},
        "gemini-3.1-pro-preview": {}
      }
    }
  }
}
'@
        $modelsJsonContent | Out-File -FilePath $MODELS_JSON -Encoding UTF8
        Log "models.json created"
    }
}
else {
    Log "models.json already exists, skipping"
}

# =============================================================================
# 6. Validate patched JS files parse correctly
# =============================================================================
Write-Host ""
Write-Host "Validating patched files..."

$filesToValidate = @()

# models.generated.js
$modelsGenJS = Join-Path $PI_AI_DIR "dist\models.generated.js"
if (Test-Path $modelsGenJS) { $filesToValidate += $modelsGenJS }

# google-gemini-cli.js
$geminiCliJS = Join-Path $PI_AI_DIR "dist\providers\google-gemini-cli.js"
if (Test-Path $geminiCliJS) { $filesToValidate += $geminiCliJS }

$validationFailed = $false
foreach ($jsFile in $filesToValidate) {
    $jsName = Split-Path $jsFile -Leaf
    try {
        # Read first few bytes to detect if ESM (has import/export)
        $fileHead = Get-Content -Path $jsFile -TotalCount 5 -ErrorAction SilentlyContinue
        $headStr = ($fileHead -join "`n")
        $isESM = $headStr -match '^\s*(import |export )'

        if ($isESM) {
            # For ESM files, pipe content to node --check --input-type=module
            $checkResult = Get-Content -Path $jsFile -Raw | & node --check --input-type=module 2>&1
        } else {
            $checkResult = & node --check $jsFile 2>&1
        }

        if ($LASTEXITCODE -eq 0) {
            Log "Validation OK: $jsName"
        } else {
            Write-Host "[X] Validation FAILED: $jsName" -ForegroundColor Red
            Write-Host $checkResult -ForegroundColor Red
            $validationFailed = $true
        }
    } catch {
        Write-Host "[X] Validation error for $jsName`: $_" -ForegroundColor Red
        $validationFailed = $true
    }
}

if ($validationFailed) {
    Write-Host ""
    Write-Host "[X] One or more patched files have syntax errors! OpenClaw may crash on startup." -ForegroundColor Red
    Write-Host "    Check the .prepatch.bak files to restore originals." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# =============================================================================
Write-Host ""
Write-Host "Patch complete. Restart OpenClaw to apply changes." -ForegroundColor Green
Write-Host ""
