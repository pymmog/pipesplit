#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── output helpers ────────────────────────────────────────────────────
log()  { printf '\033[1;34m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m✓\033[0m %s\n' "$*"; }
info() { printf '\033[1;33m!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; }

# Restore cursor on exit/interrupt
trap 'tput cnorm 2>/dev/null || true' EXIT INT TERM

# ── multi-select widget ───────────────────────────────────────────────
# Usage: multiselect RESULT_VAR "Title" item1 item2 ...
# Populates RESULT_VAR (nameref) with selected items.
multiselect() {
    local -n _ms_result=$1
    local _ms_title=$2
    shift 2
    local _ms_items=("$@")
    local _ms_count=${#_ms_items[@]}
    local _ms_selected=()
    local _ms_cursor=0
    local _ms_key _ms_seq i

    for (( i=0; i<_ms_count; i++ )); do _ms_selected+=(0); done

    _ms_redraw() {
        printf "\033[%dF" "$((_ms_count + 2))"
        printf "\033[K\033[1m%s\033[0m\n" "$_ms_title"
        printf "\033[K  \033[2m↑↓ move   Space toggle   Enter confirm\033[0m\n"
        for (( i=0; i<_ms_count; i++ )); do
            local mark="[ ]"
            [[ ${_ms_selected[$i]} -eq 1 ]] && mark=$'\033[1;32m[x]\033[0m'
            if [[ $i -eq $_ms_cursor ]]; then
                printf "\033[K  \033[1;36m%-3s  %s\033[0m\n" "$mark" "${_ms_items[$i]}"
            else
                printf "\033[K  %-3s  %s\n" "$mark" "${_ms_items[$i]}"
            fi
        done
    }

    # Initial render
    printf "\033[1m%s\033[0m\n" "$_ms_title"
    printf "  \033[2m↑↓ move   Space toggle   Enter confirm\033[0m\n"
    for (( i=0; i<_ms_count; i++ )); do printf "  [ ]  %s\n" "${_ms_items[$i]}"; done

    tput civis 2>/dev/null || true

    while true; do
        _ms_redraw
        IFS= read -r -s -n1 _ms_key || true
        if [[ $_ms_key == $'\x1b' ]]; then
            IFS= read -r -s -n2 _ms_seq 2>/dev/null || true
            case "$_ms_seq" in
                '[A') [[ $_ms_cursor -gt 0 ]] && _ms_cursor=$((_ms_cursor - 1)) ;;
                '[B') [[ $_ms_cursor -lt $((_ms_count - 1)) ]] && _ms_cursor=$((_ms_cursor + 1)) ;;
            esac
        elif [[ $_ms_key == ' ' ]]; then
            _ms_selected[$_ms_cursor]=$(( 1 - _ms_selected[$_ms_cursor] ))
        elif [[ $_ms_key == '' ]]; then
            break
        fi
    done

    tput cnorm 2>/dev/null || true

    _ms_result=()
    for (( i=0; i<_ms_count; i++ )); do
        [[ ${_ms_selected[$i]} -eq 1 ]] && _ms_result+=("${_ms_items[$i]}")
    done
}

# ── yes/no prompt ─────────────────────────────────────────────────────
ask_yn() {
    local _answer
    while true; do
        printf '%s \033[2m[y/N]\033[0m ' "$1"
        IFS= read -r _answer || true
        case "${_answer,,}" in
            y|yes) return 0 ;;
            n|no|'') return 1 ;;
            *) printf '  Please enter y or n\n' ;;
        esac
    done
}

# ── helpers ───────────────────────────────────────────────────────────
suggest_key() {
    local node="${1#alsa_output.}"
    node="${node#usb-}"; node="${node#pci-}"; node="${node#hdmi-}"
    node="${node%%.*}"
    node=$(printf '%s' "$node" | tr '[:upper:]' '[:lower:]' | tr '-' '_')
    local result="" count=0 part
    IFS='_' read -ra _parts <<< "$node"
    for part in "${_parts[@]}"; do
        [[ $count -ge 3 ]] && break
        [[ -z "$part" ]] && continue
        # skip serial-like parts (long hex-ish strings)
        if [[ ${#part} -gt 10 ]] || { [[ "$part" =~ ^[0-9a-f]+$ ]] && [[ ${#part} -gt 6 ]]; }; then
            continue
        fi
        result="${result:+${result}_}${part}"
        count=$((count + 1))
    done
    printf '%s' "${result:-device}"
}

title_case() {
    printf '%s' "$1" | tr '_' ' ' \
        | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2); print}'
}

sink_block() {
    local name=$1 desc=$2
    printf '    {\n'
    printf '        factory = adapter\n'
    printf '        args = {\n'
    printf '            factory.name   = support.null-audio-sink\n'
    printf '            node.name       = %s\n' "$name"
    printf '            node.description = "%s"\n' "$desc"
    printf '            media.class     = Audio/Sink\n'
    printf '            audio.position  = [ FL FR ]\n'
    printf '            monitor.channel-volumes = true\n'
    printf '            monitor.passthrough = true\n'
    printf '        }\n'
    printf '    }\n'
}

# ═════════════════════════════════════════════════════════════════════
printf '\n\033[1mpipesplit — interactive installer\033[0m\n\n'

# ── Step 1: detect outputs ────────────────────────────────────────────
log "Detecting PipeWire output devices..."
mapfile -t DETECTED < <(
    pw-cli ls Node 2>/dev/null \
        | grep -oP 'node\.name = "\Kalsa_output[^"]+' || true
)

if [[ ${#DETECTED[@]} -eq 0 ]]; then
    err "No alsa_output nodes found. Is PipeWire running?"
    exit 1
fi

printf '\n\033[2mFound %d output(s):\033[0m\n' "${#DETECTED[@]}"
for d in "${DETECTED[@]}"; do printf '  %s\n' "$d"; done
printf '\n'

# ── Step 2: select outputs ────────────────────────────────────────────
SEL_OUTPUTS=()
multiselect SEL_OUTPUTS "Select output devices to configure:" "${DETECTED[@]}"

if [[ ${#SEL_OUTPUTS[@]} -eq 0 ]]; then
    err "No outputs selected. Exiting."
    exit 1
fi
printf '\n'

# ── Step 3: name each selected output ────────────────────────────────
OUT_KEYS=()
OUT_PATTERNS=()
OUT_LABELS=()

for node in "${SEL_OUTPUTS[@]}"; do
    suggested=$(suggest_key "$node")
    printf '  \033[1m%s\033[0m\n' "$node"
    printf '  Short key [%s]: ' "$suggested"
    IFS= read -r key || true
    [[ -z "$key" ]] && key="$suggested"
    key=$(printf '%s' "$key" | tr -s ' ' '_' | tr -dc 'a-zA-Z0-9_' | cut -c1-24)
    [[ -z "$key" ]] && key="$suggested"
    label=$(title_case "$key")
    OUT_KEYS+=("$key")
    OUT_PATTERNS+=("$node")
    OUT_LABELS+=("$label")
    ok "$key  →  $label"
    printf '\n'
done

# ── Step 4: select sink categories ───────────────────────────────────
ALL_CATS=(music games voice browser)
SEL_CATS=()
multiselect SEL_CATS "Select audio sink categories to create:" "${ALL_CATS[@]}"

if [[ ${#SEL_CATS[@]} -eq 0 ]]; then
    err "No categories selected. Exiting."
    exit 1
fi
printf '\n'

# ── Step 5: stream channels ───────────────────────────────────────────
printf '  Stream channels add a separate virtual sink per category\n'
printf '  (e.g. stream-music, stream-games) for streaming software.\n\n'
WANT_STREAM=false
ask_yn "Add stream channels for selected categories?" && WANT_STREAM=true || true
printf '\n'

# ── Step 6: pre-configured app routes ────────────────────────────────
declare -A DEFAULT_APPS=([music]="spotify" [games]=".exe" [browser]="chromium" [voice]="discord")

printf '  Pre-configured routes that would be added:\n'
for cat in "${SEL_CATS[@]}"; do
    [[ -v DEFAULT_APPS[$cat] ]] || continue
    printf '    \033[2m%-12s→  %s\033[0m\n' "${DEFAULT_APPS[$cat]}" "$cat"
done
printf '\n'

WANT_ROUTES=false
ask_yn "Add pre-configured app routes to routes.conf?" && WANT_ROUTES=true || true
printf '\n'

# ── Generate pipesplit.conf ───────────────────────────────────────────
GEN_PW=$(mktemp)
GEN_OUT=$(mktemp)
GEN_RT=$(mktemp)
trap 'rm -f "$GEN_PW" "$GEN_OUT" "$GEN_RT"; tput cnorm 2>/dev/null || true' EXIT INT TERM

{
    printf '# pipesplit — virtual audio sinks\n'
    printf '# Install: ~/.config/pipewire/pipewire.conf.d/pipesplit.conf\n\n'
    printf 'context.objects = [\n'
    for cat in "${SEL_CATS[@]}"; do
        desc=$(title_case "$cat")
        printf '\n'
        sink_block "${cat}" "${desc}"
        if [[ "$WANT_STREAM" == true ]]; then
            sink_block "stream-${cat}" "Stream-${desc}"
        fi
    done
    printf ']\n'
} > "$GEN_PW"

# ── Generate outputs.conf ─────────────────────────────────────────────
{
    printf '# ~/.config/pipesplit/outputs.conf\n'
    printf '#\n'
    printf '# Output devices for pipesplit.\n'
    printf '# Format: key = node_pattern, Human Label\n'
    printf '#\n'
    printf '# Devices are listed in toggle order.\n\n'
    for i in "${!OUT_KEYS[@]}"; do
        printf '%-14s= %s, %s\n' "${OUT_KEYS[$i]}" "${OUT_PATTERNS[$i]}" "${OUT_LABELS[$i]}"
    done
    printf '\n# Virtual sinks connected to the selected output device\n'
    printf 'hp_sinks ='
    for cat in "${SEL_CATS[@]}"; do printf ' %s' "$cat"; done
    printf '\n\n# Virtual sinks to verify in: pipesplit status\n'
    printf 'virtual_sinks ='
    for cat in "${SEL_CATS[@]}"; do
        printf ' %s' "$cat"
        [[ "$WANT_STREAM" == true ]] && printf ' stream-%s' "$cat"
    done
    printf '\n'
} > "$GEN_OUT"

# ── Generate routes.conf ──────────────────────────────────────────────
{
    printf '# ~/.config/pipesplit/routes.conf\n'
    printf '#\n'
    printf '# Map application node names to sink pairs.\n'
    printf '# Format: app_pattern = hp_sink[, stream_sink]\n'
    printf '#\n'
    printf '# app_pattern is matched as a substring against PipeWire node names.\n'
    printf '# Find running app names with: pw-link -ol | grep -oP '"'"'^[^:]+'"'"' | sort -u\n'
    printf '# stream_sink is optional — omit it to route only to headphones.\n\n'
    if [[ "$WANT_ROUTES" == true ]]; then
        for cat in "${SEL_CATS[@]}"; do
            [[ -v DEFAULT_APPS[$cat] ]] || continue
            app="${DEFAULT_APPS[$cat]}"
            hp="hp-${cat}"
            if [[ "$WANT_STREAM" == true ]]; then
                printf '%-16s= %s, stream-%s\n' "$app" "$cat" "$cat"
            else
                printf '%-16s= %s\n' "$app" "$cat"
            fi
        done
        printf '\n'
    fi
    printf '# Add more apps as needed:\n'
    for cat in "${SEL_CATS[@]}"; do
        if [[ "$WANT_STREAM" == true ]]; then
            printf '# myapp           = %s, stream-%s\n' "$cat" "$cat"
        else
            printf '# myapp           = %s\n' "$cat"
        fi
    done
} > "$GEN_RT"

# ── Install ───────────────────────────────────────────────────────────
log "Installing..."
printf '\n'

mkdir -p ~/.config/pipewire/pipewire.conf.d
cp "$GEN_PW" ~/.config/pipewire/pipewire.conf.d/pipesplit.conf
ok "~/.config/pipewire/pipewire.conf.d/pipesplit.conf"

mkdir -p ~/.config/pipesplit
cp "$GEN_OUT" ~/.config/pipesplit/outputs.conf
ok "~/.config/pipesplit/outputs.conf"
if [[ -f ~/.config/pipesplit/routes.conf ]]; then
    info "~/.config/pipesplit/routes.conf (exists, not overwriting)"
else
    cp "$GEN_RT" ~/.config/pipesplit/routes.conf
    ok "~/.config/pipesplit/routes.conf"
fi

mkdir -p ~/.local/bin
cp "$SCRIPT_DIR/pipesplit" ~/.local/bin/pipesplit
cp "$SCRIPT_DIR/pipesplit-router" ~/.local/bin/pipesplit-router
chmod +x ~/.local/bin/pipesplit ~/.local/bin/pipesplit-router
ok "~/.local/bin/pipesplit"
ok "~/.local/bin/pipesplit-router"

mkdir -p ~/.config/systemd/user
cp "$SCRIPT_DIR/pipesplit.service" ~/.config/systemd/user/pipesplit.service
systemctl --user daemon-reload
ok "~/.config/systemd/user/pipesplit.service"

mkdir -p ~/.local/share/applications
cp "$SCRIPT_DIR/pipesplit.desktop" ~/.local/share/applications/pipesplit.desktop
ok "~/.local/share/applications/pipesplit.desktop"

printf '\n'
ok "Installed!"
printf '\n'
printf '  Next steps:\n\n'
printf '  1. systemctl --user restart pipewire\n'
printf '  2. systemctl --user enable --now pipesplit\n'
printf '  3. pipesplit connect\n\n'
keys_str=$(IFS='|'; printf '%s' "${OUT_KEYS[*]}")
printf '  Toggle output:  pipesplit toggle   (cycles: %s)\n' "$keys_str"
printf '  Check status:   pipesplit status\n\n'
