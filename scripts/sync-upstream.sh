#!/usr/bin/env bash
# Syncs current fork branch with upstream official supacode repository
# and mirrors official Sparkle build numbers to prevent update prompt collisions.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

config_rel="Configurations/Project.xcconfig"

echo "==> Comprobando estado de git..."
if ! git diff-index --quiet HEAD --; then
  echo "Error: Tienes cambios sin commitear en el árbol de trabajo. Guarda o haz stash de tus cambios antes de sincronizar." >&2
  exit 1
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"
echo "==> Rama actual: ${current_branch}"

if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "==> Configurando remote upstream..."
  git remote add upstream https://github.com/supabitapp/supacode.git
fi

backup_branch="backup/pre-sync-$(date +%Y%m%d-%H%M%S)"
echo "==> Creando respaldo ${backup_branch}..."
git branch "${backup_branch}"

echo "==> Descargando novedades de upstream..."
git fetch upstream main

# >>> rebase
echo "==> Aplicando rebase de ${current_branch} sobre upstream/main..."
if ! git rebase upstream/main; then
  # Each Sparkle mirror commit rewrites the same xcconfig lines upstream bumps on
  # release, so that file is the one expected conflict. Take upstream's side and
  # let the mirror step below regenerate our values. Any other conflict is yours.
  while [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; do
    conflicts="$(git diff --name-only --diff-filter=U)"
    if [ "${conflicts}" != "${config_rel}" ]; then
      echo "Error: el rebase se detuvo y requiere resolución manual." >&2
      [ -z "${conflicts}" ] || printf 'Archivos en conflicto:\n%s\n' "${conflicts}" >&2
      echo "Resuelve, luego 'git add <archivos>' y 'git rebase --continue'." >&2
      echo "Para volver atrás: 'git rebase --abort' o 'git reset --hard ${backup_branch}'." >&2
      exit 1
    fi
    echo "==> Conflicto solo en ${config_rel}: se toma la versión de upstream..."
    git checkout --ours -- "${config_rel}"
    git add "${config_rel}"
    if git diff --cached --quiet; then
      git rebase --skip
    else
      GIT_EDITOR=true git rebase --continue
    fi
  done
fi
# <<< rebase

echo "==> Actualizando submódulos..."
git submodule update --init --recursive

echo "==> Verificando que los parches de Ghostty aplican..."
ghostty_dir="${repo_root}/ThirdParty/ghostty"
for patch in "${repo_root}"/patches/ghostty/*.patch; do
  [ -e "${patch}" ] || continue
  if git -C "${ghostty_dir}" apply --reverse --check "${patch}" 2>/dev/null ||
    git -C "${ghostty_dir}" apply --check "${patch}" 2>/dev/null; then
    continue
  fi
  echo "Error: $(basename "${patch}") ya no aplica al Ghostty fijado por upstream; hay que regenerarlo." >&2
  echo "Respaldo disponible: ${backup_branch}" >&2
  exit 1
done

echo "==> Consultando la versión oficial de Sparkle (appcast.xml)..."
appcast_xml="$(curl -sSL https://supacode.sh/download/latest/appcast.xml 2>/dev/null || true)"
if [ -n "${appcast_xml}" ]; then
  latest_build="$(echo "${appcast_xml}" | grep -oE '<sparkle:version>[0-9]+</sparkle:version>' | head -n 1 | sed -E 's/.*<sparkle:version>([0-9]+)<\/sparkle:version>/\1/' || true)"
  latest_version="$(echo "${appcast_xml}" | grep -oE '<sparkle:shortVersionString>[^<]+</sparkle:shortVersionString>' | head -n 1 | sed -E 's/.*<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>/\1/' || true)"

  config_path="${repo_root}/${config_rel}"
  if [ -n "${latest_build}" ] && [ -f "${config_path}" ]; then
    echo "==> Espejando build oficial: ${latest_version} (build ${latest_build}) en ${config_rel}..."
    sed -i '' "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = ${latest_build}/g" "${config_path}"
    [ -z "${latest_version}" ] || sed -i '' "s/^MARKETING_VERSION = .*/MARKETING_VERSION = ${latest_version}/g" "${config_path}"
    if ! git diff --quiet -- "${config_rel}"; then
      git add "${config_rel}"
      git commit -q -m "build: mirror sparkle version ${latest_build} from official appcast"
      echo "==> Commit creado para el espejo de Sparkle."
    fi
  fi
fi

echo "==> Verificando dependencias con make doctor..."
make doctor

echo "==> Sincronización completada exitosamente."
echo "Respaldo previo: ${backup_branch}"
echo "Para compilar e instalar la app actualizada, ejecuta:"
echo "    make build-app && ./scripts/install-app.sh"
