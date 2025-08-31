# workflow-chispart
Automatización de creación de Workflow IA con Blackbox usando herramientas para agentificar el desarrollo de los proyectos con agentes asíncronos y revisores: codex (chatgpt), Jules (gemini 2.5 pro) y code Rabbit.
---

## 📋 Instrucciones

1. Lee este documento completo.
2. Crea **cada archivo** en la ruta indicada con el **contenido exacto**.
3. Marca `bb_autoplan.sh`, `setup_workflow.sh` y `adapters/blackbox_api_curl.sh` como ejecutables (`chmod +x`).
4. En Termux/Linux/Mac, crea `.env` en el **root del repo** con `BLACKBOX_API_KEY`.
5. Ejecuta `./bb_autoplan.sh` según el modo (dry-run o creación real).

---

## 📁 Estructura esperada

```
.
├─ .env                                   # 🔐 Claves (NO subir a git)
├─ bb_autoplan.sh                         # 🧠 Autoplan con Blackbox (lee .env)
├─ setup_workflow.sh                      # 🧱 Bootstrap GH (labels, milestones, issues, CI)
├─ prompts/
│  └─ blackbox_autoplan_system.md         # Prompt system para el LLM
└─ adapters/
   └─ blackbox_api_curl.sh                # Cliente curl → Blackbox API (lee .env)
```

---

## 0) Archivo: `.env`

> Crear en la **raíz del repo** (y **NO** subir a git).

```bash
BLACKBOX_API_KEY=sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> Seguridad recomendada:

```bash
chmod 600 .env
echo ".env" >> .gitignore
```

---

## 1) Archivo: `adapters/blackbox_api_curl.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# Cliente mínimo para Blackbox /chat/completions
# Uso: adapters/blackbox_api_curl.sh <model> <json_payload_file>
# Carga .env si existe

if [[ -f .env ]]; then
  # Carga todas las var no comentadas (sin espacios) del .env
  export $(grep -v '^#' .env | xargs)
fi

MODEL="${1:-blackbox-ai-latest}"
PAYLOAD_FILE="${2:-/dev/stdin}"

if [[ -z "${BLACKBOX_API_KEY:-}" ]]; then
  echo "❌ BLACKBOX_API_KEY no está definido en .env" >&2
  exit 1
fi

curl -sS https://api.blackbox.ai/chat/completions \
  -H "Authorization: Bearer ${BLACKBOX_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @- <<EOF
{
  "model": "${MODEL}",
  "messages": $(cat "${PAYLOAD_FILE}"),
  "temperature": 0.2
}
EOF
```

---

## 2) Archivo: `prompts/blackbox_autoplan_system.md`

```md
Eres un analista técnico senior. Tu tarea es LEER el resumen de la codebase y proponer un PLAN DE ENTREGA accionable.

Devuelve EXCLUSIVAMENTE JSON válido con el siguiente esquema (sin texto adicional):

{
  "milestones": [
    {
      "title": "string (corto, accionable)",
      "description": "string (1-3 líneas, claro)",
      "areas": {
        "api": ["subtarea 1", "subtarea 2"],
        "cliente": [],
        "tienda": [],
        "repartidor": [],
        "infraestructura": [],
        "testing": []
      }
    }
  ],
  "labels_extra": ["opcional: etiquetas adicionales relevantes, si aplica"]
}

Reglas:
- Prioriza independencia entre áreas para evitar conflictos de merge.
- Subtareas concretas, atómicas y testeables.
- Si un área no aplica en este hito, devuelve array vacío para esa área.
- No inventes stacks; infiere desde la evidencia (package.json, docker, etc.).
- Delivery orientado a 1-2 semanas por milestone.
```

---

## 3) Archivo: `bb_autoplan.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Autoplan con Blackbox → genera milestones/issues/sub-issues en GitHub
# Lee BLACKBOX_API_KEY desde .env
# ------------------------------------------------------------
# Uso:
#   ./bb_autoplan.sh \
#     --repo OWNER/REPO \
#     --model blackbox-ai-latest \
#     [--max-kb 256] \
#     [--include "package.json,README.md,apps/*/package.json"] \
#     [--dry-run] \
#     [--create-branch] \
#     [--init-files]
#
# Requisitos:
#   - Estar en el root del repo a analizar.
#   - .env con BLACKBOX_API_KEY (no subir a git).
#   - gh, jq, curl, find, awk, sed
# ------------------------------------------------------------

# Cargar .env
if [[ -f .env ]]; then
  export $(grep -v '^#' .env | xargs)
fi

if [[ -z "${BLACKBOX_API_KEY:-}" ]]; then
  echo "❌ Falta BLACKBOX_API_KEY en .env" >&2
  exit 1
fi

REPO=""
MODEL="blackbox-ai-latest"
MAX_KB=256
INCLUDE_PATTERNS=""
DRY_RUN=false
CREATE_BRANCH=false
INIT_FILES=false

need () { command -v "$1" >/dev/null 2>&1 || { echo "❌ Falta '$1'"; exit 1; }; }

need gh; need jq; need curl; need sed; need awk; need find; need xargs

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --max-kb) MAX_KB="$2"; shift 2;;
    --include) INCLUDE_PATTERNS="$2"; shift 2;;
    --dry-run) DRY_RUN=true; shift 1;;
    --create-branch) CREATE_BRANCH=true; shift 1;;
    --init-files) INIT_FILES=true; shift 1;;
    -h|--help) sed -n '1,160p' "$0"; exit 0;;
    *) echo "Arg desconocido: $1"; exit 1;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Uso: $0 --repo OWNER/REPO [--model ...] [--max-kb 256] [--include ...] [--dry-run] [--create-branch] [--init-files]"
  exit 1
fi

echo "🔎 Analizando codebase local… (límite ${MAX_KB}KB)"
TMPDIR="$(mktemp -d)"
SUMMARY="${TMPDIR}/summary.txt"

# 1) Árbol (limitado) + archivos clave truncados
echo "### TREE" >> "$SUMMARY"
find . -maxdepth 3 -type d -name ".git" -prune -o -print | sed 's|^\./||' | awk 'length($0)<200' | head -n 800 >> "$SUMMARY"
echo -e "\n### KEYFILES" >> "$SUMMARY"

add_if_exists () {
  local path="$1"
  [[ -f "$path" ]] || return 0
  echo -e "\n--- FILE: $path ---" >> "$SUMMARY"
  head -c $(( MAX_KB * 1024 / 10 )) "$path" >> "$SUMMARY" 2>/dev/null || true
  echo -e "\n--- EOF: $path ---" >> "$SUMMARY"
}

CANDIDATES=(
  "package.json" "pnpm-workspace.yaml" "turbo.json"
  "README.md" "docs/README.md"
  "docker-compose.yml" "Dockerfile"
  "apps/cliente/package.json" "apps/tienda/package.json" "apps/repartidor/package.json"
  "apps/api/package.json" "apps/api/src/main.ts" "apps/api/src/app.ts"
  "shared/package.json" "shared/README.md"
  "vite.config.ts" "next.config.js" "next.config.mjs"
  "tsconfig.json" ".eslintrc.*" "eslint.config.*"
  "playwright.config.*" "jest.config.*"
)

if [[ -n "$INCLUDE_PATTERNS" ]]; then
  IFS=',' read -r -a MORE <<< "$INCLUDE_PATTERNS"
  for p in "${MORE[@]}"; do
    for f in $(ls -1d $p 2>/dev/null | head -n 20); do
      CANDIDATES+=("$f")
    done
  done
fi

for f in "${CANDIDATES[@]}"; do add_if_exists "$f"; done
head -c $(( MAX_KB * 1024 )) "$SUMMARY" > "${SUMMARY}.cut" || true
mv "${SUMMARY}.cut" "$SUMMARY"

# 2) Construir payload → Blackbox
echo "🧠 Consultando Blackbox (${MODEL})…"
MSGS_FILE="${TMPDIR}/messages.json"
SYSTEM_PROMPT_FILE="prompts/blackbox_autoplan_system.md"

if [[ ! -f "$SYSTEM_PROMPT_FILE" ]]; then
  echo "❌ Falta $SYSTEM_PROMPT_FILE"; exit 1
fi

SYS=$(jq -Rs . < "$SYSTEM_PROMPT_FILE")
USR=$(jq -Rs . < "$SUMMARY")

cat > "${MSGS_FILE}" <<JSON
[
  {"role":"system","content": ${SYS}},
  {"role":"user","content": ${USR}}
]
JSON

OUT_RAW="${TMPDIR}/bb_out.json"
adapters/blackbox_api_curl.sh "$MODEL" "$MSGS_FILE" > "$OUT_RAW"

ERR_MSG=$(jq -r '.error.message? // empty' "$OUT_RAW" 2>/dev/null || true)
if [[ -n "$ERR_MSG" ]]; then
  echo "❌ Blackbox API error: $ERR_MSG" >&2
  exit 1
fi

CONTENT=$(jq -r '.choices[0].message.content // empty' "$OUT_RAW")
if [[ -z "$CONTENT" ]]; then
  echo "❌ Respuesta sin contenido utilizable." >&2
  exit 1
fi

echo "$CONTENT" | jq . >/dev/null 2>&1 || {
  echo "❌ El modelo no devolvió JSON válido." >&2
  echo "$CONTENT" > "${TMPDIR}/content_nonjson.txt"
  echo "Revisa: ${TMPDIR}/content_nonjson.txt"
  exit 1
}

# 3) Iterar milestones y crear en GitHub
AUTOPLAN_DIR="${TMPDIR}/autoplan"
mkdir -p "$AUTOPLAN_DIR"

MS_COUNT=$(echo "$CONTENT" | jq '.milestones | length')
echo "📦 Milestones propuestos: $MS_COUNT"

for i in $(seq 0 $((MS_COUNT-1))); do
  TITLE=$(echo "$CONTENT" | jq -r ".milestones[$i].title")
  DESC=$(echo "$CONTENT" | jq -r ".milestones[$i].description")
  PLAN=$(echo "$CONTENT" | jq ".milestones[$i].areas")

  PLAN_JSON="${AUTOPLAN_DIR}/plan_${i}.json"
  cat > "$PLAN_JSON" <<EOF
{
  "areas": ${PLAN}
}
EOF

  echo "  • Hito [$i]: $TITLE"
  echo "    - Plan JSON: $PLAN_JSON"

  if $DRY_RUN; then
    echo "    (dry-run) Saltando creación en GitHub"
    continue
  fi

  ./setup_workflow.sh \
    --repo "$REPO" \
    --hito "$TITLE" \
    --desc "$DESC" \
    --plan "$PLAN_JSON" \
    $($CREATE_BRANCH && echo --create-branch) \
    $($INIT_FILES && echo --init-files)
done

echo "✅ Autoplan completado."
```

---

## 4) Archivo: `setup_workflow.sh`

> Bootstrap completo de labels, milestone, issues por equipo, sub-issues desde JSON, rama del hito (opcional) y `.github` (CI + auto-etiquetado). **El etiquetado inicial `codex/rabbit` es manual.**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# YEGA: Bootstrap de Workflow para GitHub (con auto-etiquetado CI)
# ------------------------------------------------------------

REPO=""
HITO=""
DESC=""
PLAN=""
CREATE_BRANCH=false
INIT_FILES=false

slugify () {
  echo "$1" | awk '{print tolower($0)}' \
    | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+|-+$//g' | sed -E 's/-{2,}/-/g'
}
need () { command -v "$1" >/dev/null 2>&1 || { echo "❌ Requiere '$1'"; exit 1; }; }
gh_api () { gh api -H "Accept: application/vnd.github+json" "$@"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2;;
    --hito) HITO="$2"; shift 2;;
    --desc) DESC="$2"; shift 2;;
    --plan) PLAN="$2"; shift 2;;
    --create-branch) CREATE_BRANCH=true; shift 1;;
    --init-files) INIT_FILES=true; shift 1;;
    -h|--help) sed -n '1,120p' "$0"; exit 0;;
    *) echo "Arg desconocido: $1"; exit 1;;
  esac
done

need gh; need jq
if $CREATE_BRANCH || $INIT_FILES; then need git; fi
if [[ -z "$REPO" || -z "$HITO" ]]; then
  echo "Uso: $0 --repo owner/repo --hito \"Nombre Hito\" [--desc \"...\" --plan ./plan.json --create-branch --init-files]"
  exit 1
fi

gh auth status >/dev/null

OWNER="${REPO%%/*}"
REPO_NAME="${REPO##*/}"
HITO_SLUG="$(slugify "$HITO")"
BRANCH_NAME="feat/hito-${HITO_SLUG}"

echo "📦 Repo: $REPO"
echo "🏁 Hito: $HITO (slug: $HITO_SLUG)"
[[ -n "$DESC" ]] && echo "📝 Desc: $DESC"
[[ -n "$PLAN" ]] && echo "🗂  Plan: $PLAN"
$CREATE_BRANCH && echo "🌱 Crear rama: $BRANCH_NAME"
$INIT_FILES && echo "🧩 Generar .github templates, CI y auto-etiquetado"

# 1) Labels
echo "🏷️  Creando labels..."
create_label () {
  local name="$1" color="$2" desc="$3"
  if gh api "repos/$OWNER/$REPO_NAME/labels" --paginate | jq -e --arg n "$name" '.[] | select(.name==$n)' >/dev/null; then
    echo "   • '$name' ya existe"
  else
    gh_api -X POST "repos/$OWNER/$REPO_NAME/labels" -f name="$name" -f color="$color" -f description="$desc" >/dev/null
    echo "   • '$name' creado"
  fi
}
create_label "codex/rabbit" "7fdbca" "PR de sub-issue lista para testing (Codex→Rabbit)"
create_label "rabbit"       "0e8a16" "Testing exitoso; listo para integración estable"
create_label "codex"        "fbca04" "Error en testing (retry por Codex)"
create_label "blackbox"     "1d76db" "Escalamiento por error persistente; Blackbox"
AREAS=("cliente" "tienda" "repartidor" "api" "infraestructura" "testing")
for area in "${AREAS[@]}"; do create_label "area/${area}" "ededed" "Área: ${area}"; done
create_label "hito/${HITO_SLUG}" "5319e7" "Hito ${HITO}"

# 2) Milestone
echo "📌 Creando milestone..."
if gh api "repos/$OWNER/$REPO_NAME/milestones" | jq -e --arg t "$HITO" '.[] | select(.title==$t)' >/dev/null; then
  M_ID=$(gh api "repos/$OWNER/$REPO_NAME/milestones" | jq -r --arg t "$HITO" '.[] | select(.title==$t) | .number')
  echo "   • Milestone ya existe (#$M_ID)"
else
  payload=( -f title="$HITO" ); [[ -n "$DESC" ]] && payload+=( -f description="$DESC" )
  M_ID=$(gh_api -X POST "repos/$OWNER/$REPO_NAME/milestones" "${payload[@]}" | jq -r '.number')
  echo "   • Milestone creado (#$M_ID)"
fi

# 3) Rama del hito (opcional)
if $CREATE_BRANCH; then
  echo "🌿 Rama $BRANCH_NAME…"
  if [[ -d .git ]] && git remote get-url origin 2>/dev/null | grep -q "${OWNER}/${REPO_NAME}"; then
    git rev-parse --verify "$BRANCH_NAME" >/dev/null 2>&1 || git checkout -b "$BRANCH_NAME"
    git push -u origin "$BRANCH_NAME" || true
    echo "   • Rama publicada"
  else
    echo "   ⚠️  No estás en el clon local del repo; omitiendo rama"
  fi
fi

# 4) Issues por equipo + sub-issues
declare -A PARENT_ISSUE_NUM
update_parent_body_with_links () {
  local parent_num="$1"; shift
  local links=("$@")
  local body; body=$(gh issue view "$parent_num" --repo "$REPO" --json body -q '.body')
  { echo "$body"; echo; echo "### Sub-issues"; for l in "${links[@]}"; do echo "- [ ] $l"; done; } > /tmp/body_${parent_num}.md
  gh issue edit "$parent_num" --repo "$REPO" --body-file /tmp/body_${parent_num}.md >/dev/null
}

echo "🧩 Issues por equipo…"
for area in "${AREAS[@]}"; do
  TITLE="[HITO] ${HITO} — ${area^}"
  if gh issue list --repo "$REPO" --state open --search "$TITLE in:title" --json number,title | jq -e --arg t "$TITLE" '.[] | select(.title==$t)' >/dev/null; then
    num=$(gh issue list --repo "$REPO" --state open --search "$TITLE in:title" --json number,title | jq -r --arg t "$TITLE" '.[] | select(.title==$t) | .number')
    echo "   • Padre (${area}) existe: #$num"
  else
    num=$(gh issue create --repo "$REPO" --title "$TITLE" --label "hito/${HITO_SLUG},area/${area}" \
      --milestone "$M_ID" --body "Issue maestro del hito **${HITO}**, equipo **${area}**.
- Rama del hito: \`$BRANCH_NAME\`
- Labels base: \`hito/${HITO_SLUG}\`, \`area/${area}\`

**Reglas**
- Sub-issues independientes (no cruzar áreas).
- Cada PR: label \`codex/rabbit\` (manual).
- Testing OK: \`rabbit\`.
- Error: \`codex\` (retry).
- Reincidencia: \`blackbox\` + ping @SebastianVernis" \
      --json number -q '.number')
    echo "   • Padre (${area}) creado: #$num"
  fi
  PARENT_ISSUE_NUM["$area"]="$num"
done

if [[ -n "$PLAN" && -f "$PLAN" ]]; then
  echo "🗺️  Sub-issues desde plan $PLAN"
  for area in "${AREAS[@]}"; do
    mapfile -t TASKS < <(jq -r --arg a "$area" '.areas[$a][]? // empty' "$PLAN")
    [[ ${#TASKS[@]} -eq 0 ]] && continue
    parent_num="${PARENT_ISSUE_NUM[$area]}"
    declare -a LINKS=()
    for t in "${TASKS[@]}"; do
      S_TITLE="[Sub] ${HITO} — ${area^}: ${t}"
      s_num=$(gh issue create --repo "$REPO" --title "$S_TITLE" \
        --label "hito/${HITO_SLUG},area/${area}" --milestone "$M_ID" \
        --body "**Contexto:** Hito: ${HITO} / Área: ${area}

**Done**
- \`pnpm test\`, \`eslint\`, \`tsc --noEmit\` OK.
- PR con label \`codex/rabbit\` (manual).
- No tocar áreas fuera de \`${area}\`." \
        --json number -q '.number')
      LINKS+=("#${s_num}")
      echo "   • Sub-issue ${area}: #$s_num — ${t}"
    done
    update_parent_body_with_links "$parent_num" "${LINKS[@]}"
  done
else
  echo "ℹ️  Sin plan JSON: solo issues padres"
fi

# 5) Archivos .github: templates + CI + auto-etiquetado
if $INIT_FILES; then
  echo "🧱 .github templates, CI y etiquetado automático por CI…"
  if [[ ! -d .git ]]; then
    echo "   ⚠️  Ejecuta --init-files dentro de un clon local del repo"; 
  else
    WORK_BRANCH="chore/init-workflow-files"
    git checkout -b "$WORK_BRANCH" || git checkout "$WORK_BRANCH"
    mkdir -p .github/ISSUE_TEMPLATE .github/PULL_REQUEST_TEMPLATE .github/workflows

    cat > .github/ISSUE_TEMPLATE/sub_issue.md <<'YML'
name: Sub-Issue (tarea individual)
description: Crear una sub-tarea alineada a un área sin cruzar límites
title: "[Sub] <Hito> — <Área>: <Tarea>"
labels: []
body:
  - type: input
    id: area
    attributes:
      label: Área
      placeholder: "cliente | tienda | repartidor | api | infraestructura | testing"
    validations:
      required: true
  - type: textarea
    id: contexto
    attributes:
      label: Contexto
      description: "Describe brevemente el objetivo de la tarea."
  - type: checkboxes
    id: done
    attributes:
      label: Definición de Done
      options:
        - label: Tests locales OK (pnpm test, eslint, tsc --noEmit)
        - label: PR creado con label codex/rabbit (manual)
        - label: No tocar áreas fuera de la declarada
YML

    cat > .github/PULL_REQUEST_TEMPLATE/pull_request_template.md <<'MD'
## 🎯 Objetivo
Describe el cambio y el sub-issue relacionado.

Closes #

## ✅ Checklist
- [ ] Tests locales OK (`pnpm test`, `eslint`, `tsc --noEmit`)
- [ ] PR con label `codex/rabbit` (manual)
- [ ] No toca áreas fuera del sub-issue
- [ ] Revisado por responsable de área

## 🔍 Notas de Testing
Resultados esperados y casos cubiertos.

## 🧩 Área
`cliente | tienda | repartidor | api | infraestructura | testing`
MD

    # CI base
    cat > .github/workflows/ci.yml <<'YML'
name: CI
on:
  pull_request:
    branches: [ "*" ]

jobs:
  lint-typecheck-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'pnpm'
      - name: Setup pnpm
        run: npm i -g pnpm@9
      - name: Install deps
        run: pnpm install --frozen-lockfile
      - name: Lint
        run: pnpm eslint .
      - name: Type Check
        run: pnpm tsc --noEmit
      - name: Unit Tests
        run: pnpm test -- --ci --reporter=dot
YML

    # Bridge: escucha resultados del CI y aplica labels/comentarios
    cat > .github/workflows/ci-label-bridge.yml <<'YML'
name: CI Label Bridge
on:
  workflow_run:
    workflows: ["CI"]
    types: [completed]

jobs:
  label-based-on-ci:
    runs-on: ubuntu-latest
    steps:
      - name: Gestionar labels según resultado del CI
        uses: actions/github-script@v7
        with:
          script: |
            const run = context.payload.workflow_run;
            const conclusion = run.conclusion; // success | failure | neutral | cancelled | timed_out | action_required | skipped
            const prs = run.pull_requests || [];
            if (!prs.length) {
              core.info('No hay PR asociado a este run.');
              return;
            }
            const pr = prs[0];
            const owner = context.repo.owner;
            const repo = context.repo.repo;
            const prNumber = pr.number;

            async function getLabels() {
              const { data } = await github.rest.issues.listLabelsOnIssue({ owner, repo, issue_number: prNumber });
              return data.map(l => l.name);
            }
            async function addLabels(labels) {
              if (!labels.length) return;
              await github.rest.issues.addLabels({ owner, repo, issue_number: prNumber, labels });
            }
            async function removeLabel(label) {
              try {
                await github.rest.issues.removeLabel({ owner, repo, issue_number: prNumber, name: label });
              } catch (e) {}
            }
            async function comment(body) {
              await github.rest.issues.createComment({ owner, repo, issue_number: prNumber, body });
            }

            const labels = await getLabels();

            if (conclusion === 'success') {
              if (!labels.includes('rabbit')) {
                await addLabels(['rabbit']);
              }
              if (labels.includes('codex')) await removeLabel('codex');
              if (labels.includes('blackbox')) await removeLabel('blackbox');
              return;
            }

            if (conclusion === 'failure' || conclusion === 'timed_out' || conclusion === 'cancelled') {
              if (!labels.includes('codex') && !labels.includes('blackbox')) {
                await addLabels(['codex']);
              } else if (labels.includes('codex') && !labels.includes('blackbox')) {
                await addLabels(['blackbox']);
                await comment('⚠️ CI falló nuevamente. Escalando a **blackbox**. cc @SebastianVernis');
              }
              if (labels.includes('rabbit')) await removeLabel('rabbit');
              return;
            }
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
YML

    git add .github
    git commit -m "chore: init templates, CI y auto-etiquetado por resultados de CI"
    git push -u origin "$WORK_BRANCH" || true

    PR_URL=$(gh pr create --repo "$REPO" --base "${BRANCH_NAME:-main}" --head "$WORK_BRANCH" \
      --title "chore: inicializar templates, CI y auto-etiquetado" \
      --body "Se agregan templates de Issue/PR, CI base y workflow que etiqueta PRs según resultados del CI:
- CI OK → \`rabbit\`
- CI fallo 1 → \`codex\`
- CI fallo 2 → \`blackbox\` + mención a @SebastianVernis
" \
      --label "rabbit" \
      --json url -q '.url' || true)

    [[ -n "$PR_URL" ]] && echo "   • PR creado: $PR_URL" || echo "   ⚠️  No se pudo crear PR (quizá ya existe)"
  fi
fi

echo "✅ Listo: '${HITO}' configurado en $REPO."
$CREATE_BRANCH && echo "   • Rama $BRANCH_NAME creada/publicada (si estabas en el repo correcto)."
$INIT_FILES && echo "   • CI + auto-etiquetado por resultados del CI listos."
```

---

## 5) Uso rápido (Termux/Linux/Mac)

### 5.1 Preparar entorno

```bash
pkg install git jq curl -y   # Termux
# o en Debian/Ubuntu: sudo apt-get install -y git jq curl
# Instala GitHub CLI si no lo tienes (desde binario oficial)
gh auth login                 # autentica GitHub CLI

chmod +x adapters/blackbox_api_curl.sh bb_autoplan.sh setup_workflow.sh
```

### 5.2 Dry-run (solo analizar y validar JSON de hitos)

```bash
./bb_autoplan.sh \
  --repo OWNER/REPO \
  --model blackbox-ai-latest \
  --max-kb 256 \
  --include "package.json,README.md,apps/*/package.json" \
  --dry-run
```

### 5.3 Creación real en GitHub

```bash
./bb_autoplan.sh \
  --repo OWNER/REPO \
  --model blackbox-ai-latest \
  --max-kb 256 \
  --include "package.json,README.md,apps/*/package.json" \
  --create-branch \
  --init-files
```

> Flujo de etiquetas (resumen):
>
> * **Inicio PR** → (manual) `codex/rabbit`
> * **CI OK** → `rabbit` (remueve `codex`/`blackbox`)
> * **CI falla** → `codex`
> * **CI falla otra vez** → `blackbox` + mención auto a `@SebastianVernis`
> * **Merge**: siempre manual

---

