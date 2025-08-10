#!/usr/bin/env bash
set -euo pipefail

version="1.0.0"

install_self() {
    target_dir="$HOME/.local/bin"
    mkdir -p "$target_dir"
    cp "$0" "$target_dir/muralis"
    chmod +x "$target_dir/muralis"
    echo "Installed muralis to $target_dir/muralis"
    case ":$PATH:" in
        *":$HOME/.local/bin:"*) ;; 
        *) echo "WARNING: $HOME/.local/bin is not in your PATH."; echo "Add this to your shell config:"; echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"";;
    esac
    exit 0
}

die(){ printf '%s\n' "$*" >&2; exit 1; }
log(){ printf '%s\n' "$*"; }

CONFIG_DIR="$HOME/.config/muralis"
ALLOW_FILE="$CONFIG_DIR/allowlist.txt"
DIRS_FILE="$CONFIG_DIR/dirs.txt"
mkdir -p "$CONFIG_DIR"

style="fill"; recursive=0; watch=0; dry=0; interval=0; random_seed=""; quiet=0; verbose=0
feh_bin="feh"
config_file=""
exclude_regex=""
unique=0
list_outputs_only=0
gui=0

backend="x11"
if command -v swaymsg >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    backend="sway"
fi

declare -A map
declare -a dirs
declare -a passthru

feh_flag() {
    case "$1" in
        fill) echo --bg-fill;;
        scale) echo --bg-scale;;
        center) echo --bg-center;;
        tile) echo --bg-tile;;
        max) echo --bg-max;;
        *) die "Unknown style: $1";;
    esac
}

sway_mode() {
    case "$1" in
        fill) echo fill;;
        scale) echo stretch;;
        center) echo center;;
        tile) echo tile;;
        max) echo fit;;
        *) die "Unknown style: $1";;
    esac
}

is_img() { shopt -s nocasematch; [[ $1 =~ \.(jpe?g|png|webp|bmp)$ ]]; r=$?; shopt -u nocasematch; return $r; }

collect() {
    local d="$1"
    if ((recursive)); then find "$d" -type f -print0; else find "$d" -maxdepth 1 -type f -print0; fi |
    while IFS= read -r -d '' f; do
        [[ -n "$exclude_regex" && "$f" =~ $exclude_regex ]] && continue
        is_img "$f" && printf '%s\n' "$f"
    done
}

seed_rng() { [[ -n "$random_seed" ]] && RANDOM=$((random_seed % 32768)); }

pick_random() {
    local -n arr=$1
    (( ${#arr[@]} )) || return 1
    echo "${arr[RANDOM%${#arr[@]}]}"
}

outputs() {
    if [[ $backend == sway ]]; then
        swaymsg -t get_outputs | jq -r '.[] | select(.active) | .name' || true
    else
        xrandr --listmonitors | awk 'NR>1{print $NF}' || true
    fi
}

ensure_deps() {
    if [[ $backend == sway ]]; then
        command -v swaymsg >/dev/null 2>&1 || die "swaymsg not found"
        command -v jq >/dev/null 2>&1 || die "jq not found"
    else
        command -v "$feh_bin" >/dev/null 2>&1 || die "feh not found"
        command -v xrandr >/dev/null 2>&1 || die "xrandr not found"
        if ((watch)) && ((interval==0)); then command -v xev >/dev/null 2>&1 || die "xev not found"; fi
    fi
}

apply_once() {
    readarray -t outs < <(outputs)
    (( ${#outs[@]} )) || die "No active outputs"

    pool=()
    if [[ -f "$ALLOW_FILE" ]]; then
        while IFS= read -r p; do [[ -n "$p" && -f "$p" ]] && pool+=("$p"); done < "$ALLOW_FILE"
    fi

    if (( ${#pool[@]} == 0 )); then
        if ((${#dirs[@]}==0)) && [[ -f "$DIRS_FILE" ]]; then
            while IFS= read -r d; do [[ -n "$d" && -d "$d" ]] && dirs+=("$d"); done < "$DIRS_FILE"
        fi
        while IFS= read -r -d '' f; do pool+=("$f"); done < <(
            for d in "${dirs[@]:-}"; do [[ -d "$d" ]] && collect "$d"; done
        )
    fi

    (( ${#pool[@]} == 0 && ${#map[@]} == 0 )) && die "No images found"

    imgs=()
    used=()
    for out in "${outs[@]}"; do
        sel=""
        if [[ -n "${map[$out]:-}" ]]; then
            p="${map[$out]}"
            if [[ -d "$p" ]]; then readarray -t tmp < <(collect "$p"); (( ${#tmp[@]} )) && sel=$(pick_random tmp) || true; unset tmp
            elif [[ -f "$p" ]]; then sel="$p"; fi
        fi
        if [[ -z "$sel" && ${#pool[@]} -gt 0 ]]; then
            if ((unique)); then
                for try in $(seq 1 100); do
                    cand=$(pick_random pool)
                    seen=0
                    for u in "${used[@]:-}"; do [[ "$u" == "$cand" ]] && seen=1 && break; done
                    (( seen==0 )) && sel="$cand" && break
                done
                [[ -z "$sel" ]] && sel=$(pick_random pool)
            else
                sel=$(pick_random pool)
            fi
        fi
        [[ -z "$sel" ]] && die "No image for $out"
        imgs+=("$sel"); used+=("$sel")
        ((verbose)) && log "[$out] $sel"
    done
    if [[ $backend == sway ]]; then
        for i in "${!outs[@]}"; do
            out="${outs[$i]}"
            img="${imgs[$i]}"
            if ((dry)); then
                printf 'dry-run: swaymsg output %q bg %q %q\n' "$out" "$img" "$(sway_mode "$style")"
            else
                swaymsg output "$out" bg "$img" "$(sway_mode "$style")" >/dev/null
            fi
        done
    else
        cmd=("$feh_bin" --no-fehbg "$(feh_flag "$style")" "${passthru[@]:-}" "${imgs[@]}")
        if ((dry)); then printf 'dry-run: '; printf '%q ' "${cmd[@]}"; echo; else "${cmd[@]}"; fi
    fi
}

watch_loop() {
    apply_once
    if ((interval>0)); then
        while true; do sleep "$interval"; apply_once; done
    else
        if [[ $backend == sway ]]; then
            swaymsg -m -t subscribe '["output"]' | while read -r _; do apply_once; done
        else
            xev -root -event randr | while IFS= read -r _; do apply_once; done
        fi
    fi
}

print_help() {
    cat <<EOF
muralis $version
Usage: muralis [options] [DIR ...]
  --install                 Install to ~/.local/bin/muralis
  -d, --dir DIR             Add images directory (repeatable)
  -r, --recursive           Recurse into subdirectories
  -m, --map OUT=PATH        Map output to file or directory (repeatable)
  -s, --style STYLE         fill|scale|center|tile|max (default: fill)
  -w, --watch               Watch for RandR changes or rotate on interval
      --interval SECONDS    Change wallpaper every N seconds in watch mode
      --seed N              RNG seed
      --exclude REGEX       Exclude files matching REGEX
      --unique              Avoid repeating the same file across outputs
      --feh PATH            feh binary (default: feh)
      --feh-arg ARG         Extra arg passed through to feh (repeatable)
      --config FILE         Load args from file (one per line)
      --list-outputs        Print detected outputs and exit
      --gui                 Open terminal GUI to manage folders and shuffle set
      --add-dir PATH        Persistently add a folder to the set
      --rm-dir  PATH        Persistently remove a folder from the set
  -n, --dry-run             Print the feh command and exit
  -q, --quiet               Suppress non-essential output
  -v, --verbose             Verbose logging
  -V, --version             Print version and exit
  -h, --help                Show this help
EOF
}

save_dirs_file(){ printf '%s\n' "${dirs[@]}" | sort -u > "$DIRS_FILE"; }

cmd_available(){ command -v "$1" >/dev/null 2>&1; }

pick_dialog(){ if cmd_available dialog; then echo dialog; elif cmd_available whiptail; then echo whiptail; else echo ""; fi }

list_all_images(){
    local acc=()
    if ((${#dirs[@]}==0)) && [[ -f "$DIRS_FILE" ]]; then
        while IFS= read -r d; do [[ -n "$d" && -d "$d" ]] && dirs+=("$d"); done < "$DIRS_FILE"
    fi
    while IFS= read -r -d '' f; do acc+=("$f"); done < <(
        for d in "${dirs[@]}"; do collect "$d"; done
    )
    printf '%s\n' "${acc[@]}"
}

run_gui(){
    local dlg selected opts=() ids=() mapfile
    dlg=$(pick_dialog)
    if [[ -z "$dlg" ]] && cmd_available fzf; then
        readarray -t all < <(list_all_images)
        readarray -t pre < <( [[ -f "$ALLOW_FILE" ]] && grep -v '^\s*$' "$ALLOW_FILE" || true )
        printf '%s\n' "${all[@]}" | fzf --multi --prompt="Select images (tab to mark) > " --height=90% --border | sed '/^$/d' > "$ALLOW_FILE"
        save_dirs_file
        echo "Saved selection to $ALLOW_FILE"
        return 0
    fi
    [[ -z "$dlg" ]] && die "Install 'dialog' or 'fzf' for GUI mode"
    readarray -t all < <(list_all_images)
    readarray -t allow < <( [[ -f "$ALLOW_FILE" ]] && grep -v '^\s*$' "$ALLOW_FILE" || true )
    mapfile=$(mktemp)
    : > "$mapfile"
    local idx=0; for p in "${all[@]}"; do
        ((idx++))
        ids+=("$idx")
        opts+=("$idx" "${p##*/}" "$(printf '%s\n' "${allow[@]}" | grep -Fxq "$p" && echo on || echo off)")
        printf '%s\t%s\n' "$idx" "$p" >> "$mapfile"
    done
    if [[ "$dlg" == dialog ]]; then
        selected=$(dialog --stdout --separate-output --checklist "Select wallpapers (space to toggle)" 0 0 0 "${opts[@]}") || { rm -f "$mapfile"; return 1; }
    else
        selected=$(whiptail --title "Muralis" --checklist "Select wallpapers (space to toggle)" 20 78 12 "${opts[@]}" 3>&1 1>&2 2>&3) || { rm -f "$mapfile"; return 1; }
    fi
    : > "$ALLOW_FILE"
    for id in $selected; do
        path=$(awk -v id="${id//\"/}" -F"\t" '$1==id{print $2}' "$mapfile")
        [[ -n "$path" ]] && printf '%s\n' "$path" >> "$ALLOW_FILE"
    done
    rm -f "$mapfile"
    save_dirs_file
    echo "Saved selection to $ALLOW_FILE"
}

args=()
while (($#)); do args+=("$1"); shift; done

while ((${#args[@]})); do
    a=${args[0]}; args=(${args[@]:1})
    case "$a" in
        --install) install_self;;
        -d|--dir) d=${args[0]}; args=(${args[@]:1}); dirs+=("$d");;
        -r|--recursive) recursive=1;;
        -m|--map) kv=${args[0]}; args=(${args[@]:1}); [[ "$kv" == *=* ]] || die "Bad --map"; k="${kv%%=*}"; v="${kv#*=}"; map["$k"]="$v";;
        -s|--style) style=${args[0]}; args=(${args[@]:1});;
        -w|--watch) watch=1;;
        --interval) interval=${args[0]}; args=(${args[@]:1});;
        --seed) random_seed=${args[0]}; args=(${args[@]:1});;
        --exclude) exclude_regex=${args[0]}; args=(${args[@]:1});;
        --unique) unique=1;;
        --feh) feh_bin=${args[0]}; args=(${args[@]:1});;
        --feh-arg) passthru+=("${args[0]}"); args=(${args[@]:1});;
        --config) config_file=${args[0]}; args=(${args[@]:1});;
        --list-outputs) list_outputs_only=1;;
        --gui) gui=1;;
        --add-dir) d=${args[0]}; args=(${args[@]:1}); mkdir -p "$d"; dirs+=("$d"); save_dirs_file; echo "Added $d";;
        --rm-dir) d=${args[0]}; args=(${args[@]:1}); touch "$DIRS_FILE"; grep -Fxv "$d" "$DIRS_FILE" > "$DIRS_FILE.tmp" || true; mv "$DIRS_FILE.tmp" "$DIRS_FILE"; echo "Removed $d";;
        -n|--dry-run) dry=1;;
        -q|--quiet) quiet=1;;
        -v|--verbose) verbose=1;;
        -V|--version) echo "$version"; exit 0;;
        -h|--help) print_help; exit 0;;
        *) dirs+=("$a");;
    esac
done

if [[ -z "$config_file" && -f "$HOME/.config/muralis/muralis.conf" ]]; then config_file="$HOME/.config/muralis/muralis.conf"; fi
if [[ -n "$config_file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        set -- $line
        while (($#)); do args+=("$1"); shift; done
    done < "$config_file"
    while ((${#args[@]})); do
        a=${args[0]}; args=(${args[@]:1})
        case "$a" in
            -d|--dir) d=${args[0]}; args=(${args[@]:1}); dirs+=("$d");;
            -r|--recursive) recursive=1;;
            -m|--map) kv=${args[0]}; args=(${args[@]:1}); [[ "$kv" == *=* ]] || die "Bad --map"; k="${kv%%=*}"; v="${kv#*=}"; map["$k"]="$v";;
            -s|--style) style=${args[0]}; args=(${args[@]:1});;
            -w|--watch) watch=1;;
            --interval) interval=${args[0]}; args=(${args[@]:1});;
            --seed) random_seed=${args[0]}; args=(${args[@]:1});;
            --exclude) exclude_regex=${args[0]}; args=(${args[@]:1});;
            --unique) unique=1;;
            --feh) feh_bin=${args[0]}; args=(${args[@]:1});;
            --feh-arg) passthru+=("${args[0]}"); args=(${args[@]:1});;
            *) ;;
        esac
    done
fi

(( quiet )) && exec 1>/dev/null
seed_rng
ensure_deps

if ((list_outputs_only)); then outputs; exit 0; fi

if ((gui)); then run_gui; exit 0; fi

(( watch )) && watch_loop || apply_once
