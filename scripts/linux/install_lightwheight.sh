#!/usr/bin/env bash
# =============================================================================
# SAICC XVI — Flutter para desktop Linux (Ubuntu 22.04 · laboratório)
# =============================================================================
# Instala só o necessário para compilar e rodar apps Flutter no Linux.
# Não instala Android Studio, Android SDK, emulador, JDK nem KVM.
#
# Pacotes (toolchain de desktop):
#   curl git unzip xz-utils zip libglu1-mesa
#   clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev build-essential
#
# Uso (sudo obrigatório):
#   chmod +x scripts/linux/install-linux-desktop.sh
#   sudo ./scripts/linux/install-linux-desktop.sh
#   sudo ./scripts/linux/install-linux-desktop.sh --system
#
# Variáveis:
#   FLUTTER_VERSION=3.47.7
#   INSTALL_MODE=user|system
#   SKIP_VSCODE=1
# =============================================================================
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
VSCODE_FLUTTER_EXT="${VSCODE_FLUTTER_EXT:-Dart-Code.flutter}"
VSCODE_DART_EXT="${VSCODE_DART_EXT:-Dart-Code.dart}"
INSTALL_MODE="${INSTALL_MODE:-user}"
SKIP_VSCODE="${SKIP_VSCODE:-0}"
SHARE_GROUP="${SHARE_GROUP:-saicc}"

for arg in "$@"; do
  case "$arg" in
    --system) INSTALL_MODE=system ;;
    --user) INSTALL_MODE=user ;;
    --skip-vscode) SKIP_VSCODE=1 ;;
    -h|--help)
      sed -n '2,24p' "$0"
      exit 0
      ;;
    *)
      echo "Argumento desconhecido: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Este script precisa ser executado com sudo." >&2
  echo "  sudo $0 $*" >&2
  exit 1
fi
if [[ -z "${SUDO_USER:-}" || "$SUDO_USER" == "root" ]]; then
  echo "Execute com sudo a partir de um usuário comum (não como root puro)." >&2
  echo "Exemplo: sudo $0 --system" >&2
  exit 1
fi

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_RESET=$'\033[0m'
else
  C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_RESET=''
fi

log()  { echo -e "${C_BLUE}==>${C_RESET} $*"; }
ok()   { echo -e "${C_GREEN}✓${C_RESET} $*"; }
warn() { echo -e "${C_YELLOW}!${C_RESET} $*"; }
err()  { echo -e "${C_RED}✗${C_RESET} $*" >&2; }

REAL_USER="$SUDO_USER"
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
if [[ -z "$REAL_HOME" || ! -d "$REAL_HOME" ]]; then
  err "Não achei o home de ${REAL_USER}."
  exit 1
fi

if [[ "$INSTALL_MODE" == "system" ]]; then
  OPT_ROOT="/opt/saicc"
  FLUTTER_HOME="${OPT_ROOT}/flutter"
  ENV_FILE="/etc/profile.d/saicc-flutter-linux.sh"
  DOWNLOAD_DIR="/var/tmp/saicc-install"
else
  OPT_ROOT="${REAL_HOME}/saicc-dev"
  FLUTTER_HOME="${OPT_ROOT}/flutter"
  ENV_FILE="${REAL_HOME}/.saicc-flutter-linux-env.sh"
  DOWNLOAD_DIR="${REAL_HOME}/.cache/saicc-install"
fi

case "$(uname -m)" in
  x86_64) FLUTTER_ARCHIVE="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" ;;
  aarch64|arm64) FLUTTER_ARCHIVE="flutter_linux_arm64_${FLUTTER_VERSION}-stable.tar.xz" ;;
  *)
    err "Arquitetura não suportada: $(uname -m)"
    exit 1
    ;;
esac

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    warn "SO ${ID:-desconhecido}. Testado em Ubuntu 22.04."
  fi
fi

mkdir -p "$DOWNLOAD_DIR" "$OPT_ROOT"

run_as_user() {
  sudo -u "$REAL_USER" -H -- "$@"
}

download() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    ok "Já baixado: $(basename "$dest")"
    return 0
  fi
  log "Baixando $(basename "$dest")..."
  curl -fL --retry 3 --retry-delay 2 -o "${dest}.partial" "$url"
  mv "${dest}.partial" "$dest"
}

apt_install() {
  log "Instalando pacotes para build Linux (sem Android)..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends \
    curl ca-certificates git unzip xz-utils zip \
    libglu1-mesa \
    clang cmake ninja-build pkg-config \
    libgtk-3-dev liblzma-dev \
    build-essential
  ok "Pacotes apt instalados"
}

share_tree() {
  [[ "$INSTALL_MODE" == "system" ]] || return 0
  if ! getent group "$SHARE_GROUP" >/dev/null; then
    groupadd --system "$SHARE_GROUP"
  fi
  usermod -aG "$SHARE_GROUP" "$REAL_USER" || true
  chown -R root:"$SHARE_GROUP" "$OPT_ROOT"
  chmod -R g+rwX "$OPT_ROOT"
  find "$OPT_ROOT" -type d -exec chmod g+s {} +
  ok "Grupo ${SHARE_GROUP} pode escrever em ${OPT_ROOT}"
}

install_flutter() {
  log "Instalando Flutter ${FLUTTER_VERSION}..."
  if [[ -x "${FLUTTER_HOME}/bin/flutter" ]]; then
    ok "Flutter já presente em ${FLUTTER_HOME}"
  else
    local tarball="${DOWNLOAD_DIR}/${FLUTTER_ARCHIVE}"
    download "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/${FLUTTER_ARCHIVE}" "$tarball"
    rm -rf "$FLUTTER_HOME"
    tar -xJf "$tarball" -C "$OPT_ROOT"
  fi
  if [[ "$INSTALL_MODE" == "user" ]]; then
    chown -R "$REAL_USER":"$REAL_USER" "$FLUTTER_HOME"
  fi
  ok "Flutter OK"
}

write_env() {
  log "Gravando ambiente em ${ENV_FILE}"
  cat > "$ENV_FILE" <<EOF
# Gerado por SAICC XVI install-linux-desktop.sh — $(date -Iseconds)
export FLUTTER_HOME="${FLUTTER_HOME}"
export PATH="\${FLUTTER_HOME}/bin:\${PATH}"
EOF
  chmod 644 "$ENV_FILE"

  local marker="# >>> saicc-flutter-linux >>>"
  local rc
  if [[ "$INSTALL_MODE" == "user" ]]; then
    rc="${REAL_HOME}/.bashrc"
    touch "$rc"
    if ! grep -qF "$marker" "$rc"; then
      cat >> "$rc" <<EOF

${marker}
[[ -f "${ENV_FILE}" ]] && source "${ENV_FILE}"
# <<< saicc-flutter-linux <<<
EOF
    fi
    chown "$REAL_USER":"$REAL_USER" "$ENV_FILE" "$rc"
  fi
  ok "Ambiente configurado"
}

enable_linux_desktop() {
  log "Habilitando desktop Linux e baixando artefatos..."
  local flutter_bin="${FLUTTER_HOME}/bin/flutter"
  run_as_user env HOME="$REAL_HOME" PATH="${FLUTTER_HOME}/bin:${PATH}" \
    "$flutter_bin" config --enable-linux-desktop >/dev/null
  run_as_user env HOME="$REAL_HOME" PATH="${FLUTTER_HOME}/bin:${PATH}" \
    "$flutter_bin" precache --linux || warn "flutter precache --linux falhou (pode rodar depois)"
  ok "Desktop Linux habilitado"
}

install_vscode_extensions() {
  if [[ "$SKIP_VSCODE" == "1" ]]; then
    warn "Extensões do VS Code ignoradas."
    return 0
  fi
  if ! command -v code >/dev/null 2>&1; then
    warn "VS Code (comando code) não está no PATH. Extensões não instaladas."
    return 0
  fi
  log "Instalando extensões Dart e Flutter no VS Code..."
  run_as_user env HOME="$REAL_HOME" code --install-extension "$VSCODE_DART_EXT" --force
  run_as_user env HOME="$REAL_HOME" code --install-extension "$VSCODE_FLUTTER_EXT" --force
  ok "Extensões do VS Code instaladas"
}

print_summary() {
  echo
  echo "============================================================"
  echo " Flutter Linux desktop pronto"
  echo "============================================================"
  echo " Flutter:  ${FLUTTER_HOME}"
  echo " Env:      ${ENV_FILE}"
  echo
  echo " Não foram instalados Android Studio, SDK, emulador nem JDK."
  echo
  echo " Abra um novo terminal e rode:"
  if [[ "$INSTALL_MODE" == "system" ]]; then
    echo "   source /etc/profile.d/saicc-flutter-linux.sh"
  else
    echo "   source ${ENV_FILE}"
  fi
  echo "   flutter doctor -v"
  echo "   cd todo_app && flutter build linux"
  echo "============================================================"
  run_as_user env HOME="$REAL_HOME" PATH="${FLUTTER_HOME}/bin:${PATH}" \
    "${FLUTTER_HOME}/bin/flutter" doctor || true
}

log "Modo: ${INSTALL_MODE} | usuário: ${REAL_USER} | Flutter Linux desktop (sudo)"
apt_install
install_flutter
if [[ "$INSTALL_MODE" == "system" ]]; then
  share_tree
fi
write_env
enable_linux_desktop
install_vscode_extensions
print_summary
