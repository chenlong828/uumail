#!/usr/bin/env bash
# CI gate 2 (doc/works/2026-11-10-scene-refactor/architecture-spec.md §8).
#
# Deterministic, dependency-free checks over the source tree:
#   1. per-target import whitelist (Views -> Presentation, Scenes/Presentation -> no
#      EASClient/EASAdapter, MailStore -> no network import, Composition exceptions)
#   2. no scene-to-scene calls
#   3. AppComposition line budget (<= 200)
#   4. no switch/case over MailError/SyncState/OutboundState inside Composition
#
# Prints one line per gate and exits non-zero when any gate reports a finding.
set -uo pipefail
cd "$(dirname "$0")/.."

failures=0

pass() { printf 'PASS  %s\n' "$*"; }

fail() {
    local title=$1
    shift
    printf 'FAIL  %s\n' "$title"
    local finding
    for finding in "$@"; do
        printf '        %s\n' "$finding"
    done
    failures=$((failures + 1))
}

imports_in() {
    grep -rhoE '^import [A-Za-z_][A-Za-z0-9_]*' "$1" --include='*.swift' 2>/dev/null \
        | awk '{print $2}' | sort -u
}

# 1. Import whitelist ---------------------------------------------------------
gate_imports() {
    local findings=() dir target allowed imp file name
    for dir in Sources/*/; do
        target=${dir#Sources/}
        target=${target%/}
        case "$target" in
            MailDomain) allowed="Foundation" ;;
            HTMLSupport) allowed="Foundation MailDomain" ;;
            EASClient) allowed="Foundation" ;;
            EASAdapter) allowed="EASClient Foundation MailDomain" ;;
            MailStore) allowed="Foundation GRDB MailDomain" ;;
            SyncEngine) allowed="Foundation MailDomain" ;;
            Outbox) allowed="Foundation MailDomain MailStore" ;;
            Scenes) allowed="Foundation MailDomain MailStore Outbox SyncEngine HTMLSupport" ;;
            Presentation) allowed="Foundation HTMLSupport MailDomain Observation Scenes" ;;
            Composition)
                allowed="CryptoKit EASAdapter EASClient Foundation MailDomain MailStore Observation Outbox Presentation Scenes Security SyncEngine UserNotifications"
                ;;
            # The app target is the shell: Composition is file-level restricted below.
            uumail) allowed="AppKit Composition Foundation MailDomain Presentation SwiftUI WebKit" ;;
            # EASClient is the registered diagnostics exception (§3).
            uumailctl) allowed="Composition Darwin EASClient Foundation MailDomain Scenes" ;;
            *)
                findings+=("$target: no import whitelist registered")
                continue
                ;;
        esac
        while IFS= read -r imp; do
            [[ -z "$imp" ]] && continue
            if [[ " $allowed " != *" $imp "* ]]; then
                findings+=("$target: forbidden import $imp")
            fi
        done < <(imports_in "$dir")
    done

    # Views only see Presentation/MailDomain; the assembly call lives in UumailApp.swift.
    for file in Sources/uumail/*.swift; do
        name=$(basename "$file")
        if [[ "$name" != "UumailApp.swift" ]] && grep -qE '^import Composition' "$file"; then
            findings+=("Sources/uumail/$name: views may not import Composition (only UumailApp.swift assembles)")
        fi
    done

    if ((${#findings[@]} == 0)); then
        pass "imports: per-target whitelist"
    else
        fail "imports: per-target whitelist" "${findings[@]}"
    fi
}

# 2. No scene-to-scene calls --------------------------------------------------
gate_scenes() {
    local findings=() file own other hit
    local scene_names=(AccountSetupScene ComposeScene ReadScene SyncScene)
    for file in Sources/Scenes/*Scene.swift; do
        own=$(basename "$file" .swift)
        for other in "${scene_names[@]}"; do
            [[ "$other" == "$own" ]] && continue
            while IFS= read -r hit; do
                [[ -z "$hit" ]] && continue
                findings+=("$file:$hit references $other")
            done < <(grep -nE "\\b${other}\\b" "$file" || true)
        done
    done

    if ((${#findings[@]} == 0)); then
        pass "scenes: no scene-to-scene calls"
    else
        fail "scenes: no scene-to-scene calls" "${findings[@]}"
    fi
}

# 3. AppComposition size ------------------------------------------------------
gate_composition_size() {
    local lines
    lines=$(wc -l <Sources/Composition/AppComposition.swift | tr -d '[:space:]')
    if ((lines > 200)); then
        fail "composition size: AppComposition.swift is $lines lines (max 200)"
    else
        pass "composition size: AppComposition.swift is $lines lines (max 200)"
    fi
}

# 4. No business-state switch in Composition ----------------------------------
gate_composition_business_switch() {
    local findings=()
    local files=(Sources/Composition/*.swift Sources/Composition/Platform/*.swift)
    local business_cases='authFailed|deviceNotRegistered|policyBlocked|syncKeyInvalid|throttled|offline|unsupported|storage|invalidInput|syncingFolders|syncingMessages|failedRetryable|failedPermanent'
    local hit

    # Case labels of MailError / SyncState / OutboundState, e.g. `case .offline`,
    # `case let .throttled(seconds)`, and `if case .authFailed`.
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        findings+=("$hit")
    done < <(grep -nE "case[[:space:]]+(let[[:space:]]+)?\.($business_cases)" "${files[@]}" 2>/dev/null || true)

    # A switch whose subject is named or typed as one of the business states. Services
    # and the CLI composition legitimately switch on their own enums (`switch self`,
    # `switch status`), so the subject has to look like business state.
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        findings+=("$hit")
    done < <(
        grep -nE 'switch[[:space:]]+.*(MailError|SyncState|OutboundState|DeliveryOutcome|RefreshOutcome)' \
            "${files[@]}" 2>/dev/null || true
        grep -nE 'switch[[:space:]]+(self\.)?(mailError|error|err|syncState|outboundState|state|outcome|failure|report)([^A-Za-z0-9_]|$)' \
            "${files[@]}" 2>/dev/null || true
    )

    if ((${#findings[@]} == 0)); then
        pass "composition: no business-state switch (MailError/SyncState/OutboundState)"
    else
        fail "composition: no business-state switch (MailError/SyncState/OutboundState)" "${findings[@]}"
    fi
}

gate_imports
gate_scenes
gate_composition_size
gate_composition_business_switch

if ((failures > 0)); then
    printf '\n%d architecture gate(s) failed\n' "$failures"
    exit 1
fi
printf '\nAll 4 architecture gates passed\n'
