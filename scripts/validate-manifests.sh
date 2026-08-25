#!/usr/bin/env bash
# Validate every plugin package in this repository with THE parser that will load it.
#
# Why this exists: verify-gate v1.0.0 was committed, tagged and published declaring the parser's
# OUTPUT shape (`{kind, path}`) where its input contract wanted `{leaf}`. It could not install in any
# environment, and nothing said so until a human tried. The gate-script itself had been exercised
# across every push shape beforehand — what went untested was the PACKAGE.
#
# This repository has no Node toolchain of its own and Tachyon is not on npm, so the validator is a
# standalone bundle Tachyon builds (`dist/plugin-validate.cjs`). We call it rather than re-checking the
# schema here: a second implementation would drift, and a drifting validator reports green while the
# real loader refuses — strictly worse than having none.
#
#   TACHYON_REPO=/path/to/tachyon ./scripts/validate-manifests.sh
#
# Fail-closed: if the validator cannot be found, this REFUSES. "Could not check" is not "checked".
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${TACHYON_REPO:-$(cd .. 2>/dev/null && pwd)/tachyon}"

# Duas casas, porque o Tachyon virou monorepo (SDD 506) e o bundle passou a sair sob o app da
# extensão. A raiz continua listada primeiro: um checkout antigo, ou um bundle copiado à mão para
# lá, tem de seguir funcionando. Procurar nas duas é mais barato que exigir que o autor saiba qual
# layout o checkout dele tem.
CANDIDATOS="
$REPO/dist/plugin-validate.cjs
$REPO/apps/vscode-extension/dist/plugin-validate.cjs
"
VALIDATOR=""
for candidato in $CANDIDATOS; do
  if [ -f "$candidato" ]; then VALIDATOR="$candidato"; break; fi
done

if [ -z "$VALIDATOR" ]; then
  echo "validate-manifests: REFUSING — cannot find the Tachyon plugin validator." >&2
  for candidato in $CANDIDATOS; do echo "  looked for: $candidato" >&2; done
  echo "  Set TACHYON_REPO to a Tachyon checkout, and build it there once (npm run build)." >&2
  echo "  Not checking is not the same as checking: this refuses rather than passing silently." >&2
  exit 1
fi

# The CALLER decides what claims to be a plugin; the validator is deliberately strict about whatever
# it is handed (a directory with no manifest is an error there, not a skip). So enumerate exactly the
# directories that declare themselves.
PKGS=()
for manifest in */tachyon-plugin.json; do
  [ -e "$manifest" ] || continue
  PKGS+=("$(dirname "$manifest")")
done

if [ ${#PKGS[@]} -eq 0 ]; then
  echo "validate-manifests: REFUSING — no plugin package found. Expected at least one */tachyon-plugin.json." >&2
  exit 1
fi

# The README plugin table is the repository index. Derive its expected rows from the same package
# directories passed to the manifest validator so adding a package cannot silently leave the index
# stale. Check the reverse direction too, so deleting/renaming a package cannot leave a dead row.
README="README.md"
INDEXED_PKGS=()
while IFS= read -r plugin; do
  INDEXED_PKGS+=("$plugin")
done < <(sed -nE 's/^\| \[`([^`]+)`\]\(\.\/([^)]*)\) \|.*$/\1 \2/p' "$README" | awk '$1 == $2 { print $1 }')

for plugin in "${PKGS[@]}"; do
  if ! printf '%s\n' "${INDEXED_PKGS[@]}" | grep -Fxq "$plugin"; then
    echo "validate-manifests: REFUSING — plugin '$plugin' has tachyon-plugin.json but is missing from the README plugin table." >&2
    exit 1
  fi
done

for plugin in "${INDEXED_PKGS[@]}"; do
  if [ ! -f "$plugin/tachyon-plugin.json" ]; then
    echo "validate-manifests: REFUSING — plugin '$plugin' is in the README plugin table but has no tachyon-plugin.json." >&2
    exit 1
  fi
done

# Dívida declarada: `PENDING-MIGRATION` nomeia os pacotes que sabidamente não carregam ainda. Eles
# continuam sendo validados e continuam mostrando os erros — o que muda é só quem derruba o push.
# Sem isso, um repositório com um pacote defasado fica impossível de empurrar por qualquer razão, e
# a saída natural seria desligar o portão inteiro. Isto é mais estreito que desligar.
PENDING=()
if [ -f PENDING-MIGRATION ]; then
  while IFS= read -r linha; do
    linha="${linha%%#*}"
    linha="$(printf '%s' "$linha" | tr -d '[:space:]')"
    [ -n "$linha" ] && PENDING+=("$linha")
  done < PENDING-MIGRATION
fi

is_pending() {
  for nome in ${PENDING[@]+"${PENDING[@]}"}; do [ "$nome" = "$1" ] && return 0; done
  return 1
}

FIRMES=()
falhou_declarado=0
lista_podre=0
for plugin in "${PKGS[@]}"; do
  if is_pending "$plugin"; then
    if node "$VALIDATOR" "$plugin" >/dev/null 2>&1; then
      echo "validate-manifests: REFUSING — '$plugin' está em PENDING-MIGRATION mas JÁ carrega. Tire o nome de lá." >&2
      lista_podre=1
    else
      echo "pendente: $plugin — dívida declarada em PENDING-MIGRATION (não carrega)" >&2
      falhou_declarado=$((falhou_declarado + 1))
    fi
  else
    FIRMES+=("$plugin")
  fi
done
[ "$lista_podre" -eq 1 ] && exit 1

if [ ${#FIRMES[@]} -eq 0 ]; then
  echo "validate-manifests: REFUSING — todo pacote está em PENDING-MIGRATION; não sobrou nada validado." >&2
  exit 1
fi

if [ "$falhou_declarado" -gt 0 ]; then
  echo "" >&2
  echo "$falhou_declarado pacote(s) defasado(s) — declarados, não bloqueiam. Os demais seguem obrigatórios." >&2
  echo "" >&2
fi

exec node "$VALIDATOR" "${FIRMES[@]}"
