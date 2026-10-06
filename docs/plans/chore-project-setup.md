# Plan : `chore/project-setup`

Plan produit par l'agent `architect`, validé par le développeur le 2026-10-06.

## Objectif

Mettre en place l'outillage de qualité utilisé par toutes les branches suivantes : déclaration du projet et de ses dépendances, configuration de Ruff, mypy et pytest, scripts `lint.sh`, `test.sh` et `check_commits.sh`, hook `commit-msg` versionné.

La branche suivante (`ci/github-actions`) appellera ces scripts avant que le moindre code Python existe : ils doivent réussir proprement sur un dépôt sans code.

**Hors périmètre :** Docker, Docker Compose, GitHub Actions, et tout code applicatif. `app/main.py`, `app/core/config.py`, `app/core/database.py`, Alembic et `/health` relèvent de la branche 2 (`build/docker-postgres`). Les dossiers `app/`, `tests/` et `alembic/` ne sont pas créés ici.

## Décisions

| Sujet | Décision |
|---|---|
| Choix des dépendances | Délégué à l'agent `developer` (voir ci-dessous), qui justifie chaque choix dans son rapport. |
| Version de Python | 3.12 : `requires-python = ">=3.12"`, `.python-version` à `3.12`. |
| Format des commits | Scope optionnel en `[a-z0-9-]+`, `!` accepté, en-tête de 100 caractères maximum. |
| Messages générés par Git | Le hook laisse passer `Merge `, `fixup! `, `squash! `, `amend! `. `check_commits.sh` ignore les merges mais refuse `fixup!`, `squash!` et `amend!`. `Revert "..."` est refusé (à réécrire en `revert: ...`). |
| Documentation | Section « Mise en place » dans le README, et commande d'activation du hook dans la section « Commandes » de `CLAUDE.md`. |
| Tests des scripts | Pas de tests pytest ; vérifications manuelles listées plus bas. |

### Dépendances : consignes pour le `developer`

Le développeur n'a pas encore tranché ; l'agent `developer` définit les dépendances en suivant ces principes et justifie chaque choix :

- Se limiter à la stack de `CLAUDE.md` et aux outils de qualité nécessaires à cette branche.
- Recommandations de l'architecte : uv comme gestionnaire (`uv.lock` committé, `[tool.uv] package = false`, scripts lancés via `uv run`) ; `coverage` seul plutôt que `pytest-cov` ; déclarer dès maintenant les dépendances runtime de la stack (FastAPI, Pydantic v2, SQLAlchemy 2, Alembic, PyJWT, argon2-cffi).
- Ne pas ajouter ici les dépendances des branches suivantes (`psycopg[binary]`, `uvicorn`, `httpx`, `email-validator`) ; les signaler seulement.
- Si uv n'est pas installé sur la machine, s'arrêter et le signaler plutôt que l'installer.

## Fichiers

| Fichier | Rôle |
|---|---|
| `.gitignore` | `.venv/`, `__pycache__/`, `*.pyc`, `.mypy_cache/`, `.ruff_cache/`, `.pytest_cache/`, `.coverage`, `.coverage.*`, `htmlcov/`, `.env`. |
| `.gitattributes` | `* text=auto eol=lf` : un script bash en CRLF plante sous Linux. |
| `pyproject.toml` | Métadonnées, dépendances, configuration des outils. |
| `uv.lock`, `.python-version` | Si uv est retenu. |
| `scripts/lint.sh` | Format, lint, typage. Ne modifie aucun fichier. |
| `scripts/test.sh` | Tests avec couverture. |
| `scripts/check_commits.sh` | Valide les commits de `<base>..HEAD`. |
| `scripts/hooks/commit-msg` | Hook Git, seule définition de l'expression régulière. |
| `README.md`, `CLAUDE.md` | Documentation de la mise en place. |

### Configuration des outils (`pyproject.toml`)

**Ruff**
- `line-length = 88`, version cible déduite de `requires-python`.
- `[tool.ruff.lint] select = ["E", "W", "F", "I", "N", "UP", "B", "S", "C4", "SIM", "PT", "RUF"]` (pas `ANN`, redondant avec mypy strict).
- `per-file-ignores` : `"tests/**" = ["S101", "S105", "S106"]`.
- `[tool.ruff.lint.isort] known-first-party = ["app"]`.
- Format : valeurs par défaut (pas de `line-ending` forcé).

**mypy**
- `python_version = "3.12"`, `strict = true`, `warn_unreachable = true`, `explicit_package_bases = true`.
- `plugins = ["pydantic.mypy"]`.
- Pas de `files = [...]` : `lint.sh` passe les cibles.

**pytest**
- `minversion = "8.0"`, `testpaths = ["tests"]`, `pythonpath = ["."]`.
- `addopts = ["--import-mode=importlib", "--strict-markers", "--strict-config", "-ra"]`.
- `xfail_strict = true`, `filterwarnings = ["error"]`.

**coverage**
- `[tool.coverage.run]` : `source = ["app"]`, `branch = true`.
- `[tool.coverage.report]` : `fail_under = 80`, `show_missing = true`, `skip_covered = true`.

### `scripts/lint.sh`

```bash
#!/usr/bin/env bash
# Check formatting, lint and static typing. Never modifies files.
set -euo pipefail
cd "$(dirname "$0")/.."

uv run ruff format --check .
uv run ruff check .

targets=()
for dir in app tests; do
  if [ -d "$dir" ]; then targets+=("$dir"); fi
done
if [ "${#targets[@]}" -eq 0 ]; then
  echo "mypy : aucun code Python (app/, tests/), étape ignorée."
else
  uv run mypy "${targets[@]}"
fi
```

Vérifier que `ruff check` et `ruff format --check` renvoient 0 sans fichier Python ; sinon, les protéger avec la même garde.

### `scripts/test.sh`

Garde sur l'absence de fichiers de test, qui se désactive d'elle-même : dès qu'un `test_*.py` existe, un code 5 de pytest redevient une erreur.

```bash
#!/usr/bin/env bash
# Run the test suite with coverage.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ ! -d tests ] || [ -z "$(find tests -type f -name 'test_*.py' -print -quit)" ]; then
  echo "Aucun fichier de test dans tests/, étape ignorée."
  exit 0
fi

uv run coverage run -m pytest
uv run coverage report
```

### `scripts/hooks/commit-msg`

```bash
#!/usr/bin/env bash
# Validate the commit message header against Conventional Commits.
set -euo pipefail

types='feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert'
pattern="^(${types})(\([a-z0-9-]+\))?!?: [^[:space:]].*$"
max_length=100

# First non-empty, non-comment line, CR stripped (Windows editors).
header="$(sed -e 's/\r$//' -e '/^#/d' -e '/^[[:space:]]*$/d' -e q "$1")"

case "$header" in
  "Merge "* | "fixup! "* | "squash! "* | "amend! "*) exit 0 ;;
esac

if [[ ! "$header" =~ $pattern ]]; then
  echo "Message de commit invalide : « $header »" >&2
  echo "Format attendu : type(scope): description  (types : ${types//|/, })" >&2
  exit 1
fi
if [ "${#header}" -gt "$max_length" ]; then
  echo "En-tête trop long (${#header} > ${max_length} caractères)." >&2
  exit 1
fi
```

Activation, une fois par clone : `git config core.hooksPath scripts/hooks`.

### `scripts/check_commits.sh`

- Argument facultatif `base`, `main` par défaut.
- Référence inexistante (`git rev-parse --verify --quiet "$base^{commit}"`) : message et code 2.
- Parcourt `git rev-list --no-merges --reverse "$base..HEAD"`.
- Pour chaque commit : message (`git log -1 --format=%B`) dans un fichier `mktemp` supprimé par `trap ... EXIT` ; refus explicite de `fixup!`, `squash!`, `amend!` ; sinon `bash scripts/hooks/commit-msg "$tmp"`.
- Affiche `OK <sha court> <en-tête>` ou `KO ...` pour chaque commit sans s'arrêter, puis code 1 s'il y a au moins un KO.
- Aucun commit à vérifier : message et code 0.

## Étapes

1. `.gitattributes` et `.gitignore`, puis `git add --renormalize .` et `git status`.
2. Hook `commit-msg`, `git config core.hooksPath scripts/hooks`, tests manuels, `git add --chmod=+x`.
3. Projet et dépendances, puis `uv sync` et `uv lock --check`.
4. Configuration Ruff, mypy, pytest, coverage.
5. `lint.sh` et `test.sh` (`git add --chmod=+x`), vérifications sur dépôt vide et vérifications temporaires.
6. `check_commits.sh` (`git add --chmod=+x`).
7. README et `CLAUDE.md`.
8. Contrôle final : `git ls-files -s scripts` en `100755`, `git ls-files --eol scripts` en `i/lf`, puis les trois scripts.

## Vérifications

**Hook** (`bash scripts/hooks/commit-msg <fichier>`)

| Message | Attendu |
|---|---|
| `feat(auth): ajout de la rotation des refresh tokens` | 0 |
| `docs: mise à jour des spécifications` | 0 |
| `feat(meal-entries)!: changement du format` | 0 |
| `# commentaire`, ligne vide, `fix: correction` | 0 |
| `chore: test` en CRLF | 0 |
| `Merge branch 'main' into feat/x`, `fixup! feat: x` | 0 |
| `Ajout de truc`, `first commit`, `WIP` | 1 |
| `feature: x` | 1 |
| `feat:sans espace`, `feat: ` | 1 |
| `feat(): x`, `feat(Auth): x` | 1 |
| `Revert "feat: x"` | 1 |
| En-tête de 101 caractères | 1 |

**`check_commits.sh`** : 0 sur la branche ; 2 avec `nope` ; 1 sur une branche jetable avec un commit `--no-verify -m "mauvais"` ou `fixup! ...` (branche supprimée ensuite).

**Dépôt sans code** : `lint.sh` et `test.sh` renvoient 0 avec leur message d'étape ignorée.

**Vérifications temporaires, non committées** :
- `app/probe.py` avec `def f(x): return x` : `lint.sh` échoue sur mypy.
- `app/probe.py` typé et `tests/unit/test_probe.py` : `test.sh` lance pytest et affiche la couverture.
- `tests/unit/test_empty.py` sans test : `test.sh` renvoie 5.

## Risques

- **Bit exécutable** : `core.filemode = false` ; ajouter les scripts avec `git add --chmod=+x` et vérifier le mode `100755`.
- **Fins de ligne** : `.gitattributes` obligatoire ; le hook supprime les `\r`.
- **Bash sous Windows** : lancer les scripts depuis Git Bash, pas le `bash.exe` de WSL ; `find` doit être celui de GNU.
- **`--no-verify`** contourne le hook ; `check_commits.sh` en CI sert de filet.
- **Couverture** : le seuil de 80 % s'appliquera dès la branche 2.

## Commits suggérés

1. `chore: ajout du .gitignore et normalisation des fins de ligne`
2. `chore(hooks): ajout du hook commit-msg Conventional Commits`
3. `build(deps): initialisation du projet et des dépendances`
4. `chore: configuration de Ruff, mypy, pytest et coverage`
5. `chore(scripts): ajout des scripts lint.sh et test.sh`
6. `chore(scripts): ajout de check_commits.sh`
7. `docs: instructions de mise en place et d'activation du hook`
