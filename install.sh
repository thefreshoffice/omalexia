#!/usr/bin/env bash
# Install Omalexia: dyslexia-friendly reading, dictation and layout for Omarchy.
#
# Safe to re-run. Package installation needs sudo (through omarchy-pkg-add),
# so run this from a terminal. Every other step is per-user and reversible;
# `omalexia off` puts the visual changes back.
#
#   ./install.sh              full install
#   ./install.sh --no-pkgs    skip package installation (already done / no sudo)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

skip_pkgs=false
for arg in "$@"; do
  case "$arg" in
    --no-pkgs) skip_pkgs=true ;;
    -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

BIN_DIR="$HOME/.local/bin"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/omalexia"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omalexia"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omalexia"
FIRST_RUN_MARKER="$STATE_DIR/profile-applied"
stamp="$(date +%Y%m%d-%H%M%S)"

say() { echo -e "\e[32m\n$*\e[0m"; }
note() { echo "  $*"; }

backup_if_differs() {
  local src="$1" dest="$2"
  if [[ -f $dest ]] && ! cmp -s "$src" "$dest"; then
    cp "$dest" "$dest.bak.$stamp"
    note "backed up $(basename "$dest")"
  fi
}

# ---------------------------------------------------------------------------
say "Omalexia: packages"
# ---------------------------------------------------------------------------

if $skip_pkgs; then
  note "skipping packages (--no-pkgs)"
else
  # Fonts: Atkinson Hyperlegible (default reading font), OpenDyslexic and
  # Inter as alternatives, plus Nerd-Font-patched monospace companions so
  # terminal icons keep working. Spell checking and Dutch OCR for the rest.
  omarchy-pkg-add \
    ttf-atkinson-hyperlegible otf-atkinsonhyperlegiblemono-nerd \
    otf-opendyslexic-nerd inter-font \
    hunspell-en_us hunspell-nl tesseract-data-nld \
    speech-dispatcher wl-clipboard wtype grim slurp tesseract jq

  # Piper (neural TTS) is an AUR package. Skip when the python module exists
  # already (Omarchy ships python-onnxruntime; piper-tts builds on it).
  if ! /usr/bin/python3 -c 'import piper' 2>/dev/null; then
    note "installing piper-tts from the AUR (builds a small wheel, a minute or two)"
    omarchy-pkg-aur-add piper-tts || echo "  ! piper-tts failed to install; read-aloud will not work until it does" >&2
  fi

  # Voxtype dictation, same packages omarchy-voxtype-install uses.
  if ! command -v voxtype >/dev/null; then
    note "installing voxtype"
    omarchy-pkg-aur-add wtype voxtype-bin || echo "  ! voxtype-bin failed to install" >&2
  fi
fi

# ---------------------------------------------------------------------------
say "Omalexia: commands"
# ---------------------------------------------------------------------------

mkdir -p "$BIN_DIR" "$DATA_DIR" "$STATE_DIR" "$CONFIG_DIR"
for f in bin/*; do
  [[ -f $f ]] || continue
  install -m 755 "$f" "$BIN_DIR/$(basename "$f")"
done
install -m 644 config/kokoro/worker.py "$DATA_DIR/kokoro-worker.py"
note "installed $(find bin -maxdepth 1 -type f -printf '%f ')to ~/.local/bin"

[[ -f $CONFIG_DIR/config.toml ]] || install -m 644 config/omalexia.toml "$CONFIG_DIR/config.toml"
[[ -f $CONFIG_DIR/replacements.txt ]] || install -m 644 config/replacements.txt "$CONFIG_DIR/replacements.txt"

# foot: let read-aloud ask the terminal for its visible text, which gives
# the highlighter exact word positions with no OCR. The chord is untypeable
# on purpose; omalexia-locate presses it via wtype. New terminals only:
# foot reads its config at startup.
foot_ini="${XDG_CONFIG_HOME:-$HOME/.config}/foot/foot.ini"
if [[ -f $foot_ini ]] && ! grep -q omalexia-foot-visible "$foot_ini"; then
  cp "$foot_ini" "$foot_ini.bak.$stamp"
  if grep -q '^\[key-bindings\]' "$foot_ini"; then
    sed -i '/^\[key-bindings\]/a pipe-visible=[omalexia-foot-visible] Control+Shift+F34' "$foot_ini"
  else
    printf '\n[key-bindings]\npipe-visible=[omalexia-foot-visible] Control+Shift+F34\n' >>"$foot_ini"
  fi
  note "added the foot pipe-visible binding (applies to new terminals)"
fi

# ---------------------------------------------------------------------------
say "Omalexia: bar plugin"
# ---------------------------------------------------------------------------

# Copied into the user plugin directory (Omarchy's validator refuses symlinked
# plugin folders). Re-running this installer updates it; the shell hot-reloads
# plugin files on save. Anything in the way that is not ours is left alone.
plugin_id="thefreshoffice.omalexia"
plugin_dest="$HOME/.config/omarchy/plugins/$plugin_id"
mkdir -p "$(dirname "$plugin_dest")"
# The widget was first published as husense.omalexia; retire that copy.
old_plugin="$HOME/.config/omarchy/plugins/husense.omalexia"
if [[ -e $old_plugin ]]; then
  omarchy plugin disable husense.omalexia >/dev/null 2>&1 || true
  rm -rf "$old_plugin"
  note "removed the old husense.omalexia widget"
fi
if [[ -L $plugin_dest ]]; then
  rm -f "$plugin_dest"
fi
if [[ -e $plugin_dest && ! -d $plugin_dest/.git ]] && grep -q "\"id\": \"$plugin_id\"" "$plugin_dest/manifest.json" 2>/dev/null; then
  rm -rf "$plugin_dest"
fi
if [[ ! -e $plugin_dest ]]; then
  mkdir -p "$plugin_dest"
  cp plugin/manifest.json plugin/*.qml plugin/status.py plugin/README.md "$plugin_dest/"
  note "installed the bar plugin to $plugin_dest"
else
  note "$plugin_dest is not managed by this installer; leaving it"
fi
omarchy-shell -q shell rescanPlugins
if ! grep -q "\"$plugin_id\"" "$HOME/.config/omarchy/shell.json" 2>/dev/null; then
  enabled=false
  for _ in 1 2 3 4 5; do
    sleep 1
    if omarchy plugin enable "$plugin_id" >/dev/null 2>&1; then enabled=true; break; fi
  done
  if $enabled; then note "enabled the Omalexia bar widget (right section)"; else
    note "could not enable the bar widget yet; run: omarchy plugin enable $plugin_id"; fi
else
  note "bar widget already enabled"
fi

# ---------------------------------------------------------------------------
say "Omalexia: voices"
# ---------------------------------------------------------------------------

if /usr/bin/python3 -c 'import piper' 2>/dev/null; then
  # Reads the configured voices so a changed choice survives re-runs.
  voices="$(/usr/bin/python3 - "$CONFIG_DIR/config.toml" <<'PY'
import sys, tomllib
try:
    cfg = tomllib.load(open(sys.argv[1], "rb"))
    print(" ".join(cfg.get("tts", {}).get("voices", {}).values()))
except Exception:
    print("en_US-lessac-medium nl_NL-pim-medium")
PY
)"
  # shellcheck disable=SC2086
  "$BIN_DIR/omalexia-voice" install $voices || echo "  ! voice download failed (offline?); rerun later: omalexia voice install $voices" >&2
else
  note "piper not available; skipping voice download"
fi

# ---------------------------------------------------------------------------
say "Omalexia: read-aloud daemon"
# ---------------------------------------------------------------------------

mkdir -p "$HOME/.config/systemd/user"
install -m 644 config/systemd/omalexia-speakd.service "$HOME/.config/systemd/user/omalexia-speakd.service"
systemctl --user daemon-reload
systemctl --user enable omalexia-speakd.service >/dev/null 2>&1 || true
if systemctl --user is-active --quiet omalexia-speakd.service; then
  systemctl --user restart omalexia-speakd.service
else
  systemctl --user start omalexia-speakd.service || true
fi
note "omalexia-speakd: $(systemctl --user is-active omalexia-speakd.service || true)"

# ---------------------------------------------------------------------------
say "Omalexia: Speech Dispatcher (Firefox Narrate, Orca, spd-say)"
# ---------------------------------------------------------------------------

sd_dir="$HOME/.config/speech-dispatcher"
mkdir -p "$sd_dir/modules"
install -m 644 config/speech-dispatcher/omalexia.conf "$sd_dir/modules/omalexia.conf"
if [[ ! -f $sd_dir/speechd.conf ]]; then
  cp /etc/speech-dispatcher/speechd.conf "$sd_dir/speechd.conf"
fi
if ! grep -q '^AddModule "omalexia"' "$sd_dir/speechd.conf"; then
  cat >>"$sd_dir/speechd.conf" <<'EOF'

# omalexia: route everything through the local Omalexia voice.
AddModule "omalexia" "sd_generic" "omalexia.conf"
DefaultModule omalexia
EOF
  note "added omalexia module to speechd.conf"
fi
systemctl --user try-restart speech-dispatcher.service 2>/dev/null || true

# ---------------------------------------------------------------------------
say "Omalexia: Hyprland keys and look"
# ---------------------------------------------------------------------------

hypr_dir="$HOME/.config/hypr"
backup_if_differs config/hypr/omalexia.lua "$hypr_dir/omalexia.lua"
install -m 644 config/hypr/omalexia.lua "$hypr_dir/omalexia.lua"
if ! grep -q 'hypr.omalexia' "$hypr_dir/hyprland.lua"; then
  if grep -q 'require("hypr.autostart")' "$hypr_dir/hyprland.lua"; then
    sed -i '/require("hypr.autostart")/a require("hypr.omalexia") -- Omalexia: F10 read aloud, Super+R reading mode' "$hypr_dir/hyprland.lua"
  else
    printf '\nrequire("hypr.omalexia") -- Omalexia: F10 read aloud, Super+R reading mode\n' >>"$hypr_dir/hyprland.lua"
  fi
  note "added require(\"hypr.omalexia\") to hyprland.lua"
fi
if [[ ! -f $FIRST_RUN_MARKER ]]; then
  # Keep a lone window from stretching across a wide monitor (Super+Ctrl+Backspace toggles).
  omarchy-hyprland-toggle single-window-aspect-ratio on >/dev/null 2>&1 || true
fi
hyprctl reload >/dev/null 2>&1 || true
if errors="$(hyprctl configerrors 2>/dev/null)" && [[ -n $errors && $errors != "no errors" ]]; then
  echo "  ! Hyprland reported config errors:" >&2
  echo "$errors" >&2
fi

# ---------------------------------------------------------------------------
say "Omalexia: menu"
# ---------------------------------------------------------------------------

menu="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
mkdir -p "$(dirname "$menu")"
[[ -f $menu ]] || printf '{\n}\n' >"$menu"
/usr/bin/python3 - "$menu" config/omarchy-menu.jsonc <<'PY'
import re, sys
menu_path, block_path = sys.argv[1], sys.argv[2]
block = open(block_path).read().rstrip("\n")
text = open(menu_path).read()
begin, end = "// omalexia:begin", "// omalexia:end"
if begin in text and end in text:
    text = re.sub(r"[ \t]*" + re.escape(begin) + r".*?" + re.escape(end) + r"[^\n]*", block, text, flags=re.S)
else:
    idx = text.rstrip().rfind("}")
    text = text[:idx].rstrip("\n") + "\n\n" + block + "\n" + text[idx:]
open(menu_path, "w").write(text)
PY
omarchy-menu refresh >/dev/null 2>&1 || true
note "Omalexia entry added to the Omarchy menu (Super+Alt+A)"

# ---------------------------------------------------------------------------
say "Omalexia: dictation (voxtype)"
# ---------------------------------------------------------------------------

if command -v voxtype >/dev/null; then
  vx_dir="$HOME/.config/voxtype"
  mkdir -p "$vx_dir"
  backup_if_differs config/voxtype/config.toml "$vx_dir/config.toml"
  install -m 644 config/voxtype/config.toml "$vx_dir/config.toml"

  parakeet_model="$(sed -n 's/^model = "\(parakeet[^"]*\)"/\1/p' config/voxtype/config.toml | head -n1)"

  # Parakeet lives in voxtype's ONNX binary variant. Switching to it replaces
  # /usr/bin/voxtype, hence sudo; the model can only be downloaded afterwards.
  onnx_active() { voxtype setup onnx --status 2>/dev/null | grep -q 'Active engine: ONNX'; }
  if ! onnx_active && ! $skip_pkgs; then
    note "switching voxtype to its ONNX binary (sudo)"
    sudo voxtype setup onnx --enable >/dev/null || echo "  ! could not enable the ONNX variant" >&2
  fi

  if onnx_active; then
    if [[ -d $HOME/.local/share/voxtype/models/$parakeet_model ]]; then
      note "parakeet model present"
    else
      note "downloading $parakeet_model (about 700 MB, once)"
      voxtype setup --download --model "$parakeet_model" --quiet --no-post-install ||
        echo "  ! model download failed (offline?); rerun this installer later" >&2
    fi
  else
    note "Parakeet needs the ONNX variant: rerun without --no-pkgs (or: sudo voxtype setup onnx --enable)"
  fi
  if [[ ! -d $HOME/.local/share/voxtype/models/$parakeet_model ]]; then
    note "using Whisper base.en for now"
    voxtype config set engine whisper >/dev/null 2>&1 || true
  fi
  if [[ ! -f $HOME/.config/systemd/user/voxtype.service ]]; then
    voxtype setup systemd >/dev/null 2>&1 || true
  fi
  systemctl --user restart voxtype.service 2>/dev/null || true
  note "voxtype: $(systemctl --user is-active voxtype.service || true), engine $(sed -n 's/^engine = "\(.*\)"/\1/p' "$vx_dir/config.toml")"
  omarchy-restart-shell >/dev/null 2>&1 || true
else
  note "voxtype not installed; dictation skipped (rerun without --no-pkgs)"
fi

# ---------------------------------------------------------------------------
say "Omalexia: reading font and text size"
# ---------------------------------------------------------------------------

if [[ ! -f $FIRST_RUN_MARKER ]]; then
  if fc-list : family | grep -qi 'Atkinson Hyperlegible'; then
    "$BIN_DIR/omalexia-font" atkinson >/dev/null && note "reading font: Atkinson Hyperlegible"
  else
    note "Atkinson Hyperlegible not installed yet; run: omalexia font atkinson"
  fi
  current_size="$(omarchy-display-text-size 2>/dev/null | grep -oE '[0-9]+' | head -n1 || echo 12)"
  if [[ ${current_size:-12} -le 12 ]]; then
    omarchy-display-text-size 14 >/dev/null 2>&1 && note "text size: 14 (omarchy display text size reset to undo)"
  fi
  : >"$FIRST_RUN_MARKER"
else
  note "profile already applied once; leaving your font and text size alone"
fi

# ---------------------------------------------------------------------------
say "Omalexia installed."
# ---------------------------------------------------------------------------

"$BIN_DIR/omalexia" keys
echo
echo "Try it: select any text and press F10.   Everything: omalexia --help"
