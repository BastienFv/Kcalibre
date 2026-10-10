# Plan : `ci/github-actions`

Plan produit par l'agent `architect`, validé par le développeur le 2026-10-10.

## Objectif

Mettre en place la CI GitHub Actions demandée par la section 7 des spécifications. À chaque pull request vers `main`, elle vérifie les messages de commit, le lint et le typage, puis les tests, en appelant `scripts/check_commits.sh`, `scripts/lint.sh` et `scripts/test.sh` sans recopier leurs commandes. Elle doit passer sur le dépôt actuel, qui ne contient pas encore de code, et permettre d'ajouter ensuite PostgreSQL et le build Docker sans réorganisation.

**Dans cette branche :** le workflow et ses trois jobs `commits`, `lint` et `test` ; déclencheurs, cache, permissions et concurrence ; Dependabot pour les actions ; documentation des réglages GitHub à faire à la main.

**En branche 2 (`build/docker-postgres`) :** service PostgreSQL 17 dans le job `test`, job `docker`, check `docker` dans la protection de `main` (voir « Préparation de la branche 2 »).

**Hors périmètre :** code applicatif, Docker, Alembic, toute dépendance Python, toute modification de `CLAUDE.md`, `pyproject.toml` ou des scripts.

## Décisions

| Sujet | Décision |
|---|---|
| Déclencheurs | `pull_request` vers `main` et `push` sur `main`. Pas de filtre `paths` (un check requis qui ne se lance pas reste « Expected »). Jamais `pull_request_target`. |
| Jobs | `commits`, `lint` et `test`, indépendants et parallèles. Pas de `name:` sur les jobs : leurs identifiants sont les noms des checks requis. |
| Job `commits` | Uniquement sur `pull_request`. `fetch-depth: 0`, pas d'uv. Appelle `./scripts/check_commits.sh "origin/$BASE_REF"`, `BASE_REF` étant passé par `env` (jamais `${{ github.base_ref }}` directement dans `run:`). Le commit de fusion `refs/pull/N/merge` est écarté par `--no-merges`. |
| Push sur `main` | Seuls `lint` et `test` tournent : les commits ont été validés dans la PR et la fusion en rebase conserve les messages. |
| uv | `astral-sh/setup-uv` épinglé par SHA, `version` égale à la version locale exacte, `enable-cache: true`. Pas d'étape `uv sync` : `uv run` synchronise, `UV_LOCKED=1` fait échouer si le lock est périmé. |
| Python | Lu dans `.python-version` (3.12). Pas de `actions/setup-python` ni de matrice. |
| Épinglage | Actions par SHA complet avec le tag en commentaire (`@<sha> # vX.Y.Z`). Runner `ubuntu-24.04`. |
| Permissions | `contents: read` au niveau du workflow, `persist-credentials: false` sur chaque checkout. |
| Concurrence | Groupe `${{ github.workflow }}-${{ github.event.pull_request.number \|\| github.ref }}`, annulation des runs obsolètes en PR uniquement. |
| Shell, durée | `defaults.run.shell: bash` ; `timeout-minutes` 5 pour `commits`, 10 pour `lint` et `test`. |
| Appel des scripts | `./scripts/x.sh` (vérifie aussi le bit exécutable). |
| Langue | Identifiants et commentaires YAML en anglais, noms d'étapes en français. |
| Dependabot | Oui : écosystème `github-actions`, mensuel, mises à jour regroupées, préfixe `ci`. Ses messages (`ci(deps): bump ...`) sont en anglais : exception acceptée. |
| Fusion | Rebase uniquement, historique linéaire. |
| Outil de validation du workflow | Aucun (ni actionlint ni zizmor). |
| README | Courte section « Intégration continue », sans badge. |

## Fichiers

| Fichier | Action |
|---|---|
| `.github/workflows/ci.yml` | Créer |
| `.github/dependabot.yml` | Créer |
| `README.md` | Ajouter la section « Intégration continue » |

### `.github/workflows/ci.yml`

Les `<sha>`, `vX.Y.Z` et `<uv version>` sont à résoudre à l'étape 1, jamais à inventer.

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number || github.ref }}
  # Cancel superseded runs on pull requests only: every commit on main is checked.
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}

defaults:
  run:
    shell: bash

jobs:
  commits:
    # Commits are validated in the pull request; main only receives rebased PRs.
    if: github.event_name == 'pull_request'
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
        with:
          fetch-depth: 0 # full history: origin/<base> must exist for base..HEAD
          persist-credentials: false
      - name: Vérification des messages de commit
        env:
          BASE_REF: ${{ github.base_ref }}
        run: ./scripts/check_commits.sh "origin/$BASE_REF"

  lint:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
        with:
          persist-credentials: false
      - uses: astral-sh/setup-uv@<sha> # vX.Y.Z
        with:
          version: "<uv version>" # keep in sync with the test job and local uv
          enable-cache: true
      - name: Lint et typage
        run: ./scripts/lint.sh

  test:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
        with:
          persist-credentials: false
      - uses: astral-sh/setup-uv@<sha> # vX.Y.Z
        with:
          version: "<uv version>"
          enable-cache: true
      - name: Tests
        run: ./scripts/test.sh
```

### `.github/dependabot.yml`

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
    commit-message:
      prefix: ci
      include: scope
    groups:
      actions:
        patterns: ["*"]
```

### `README.md`

Section « Intégration continue » de quatre ou cinq lignes : le workflow tourne sur chaque PR vers `main` et chaque push sur `main` ; les checks `commits`, `lint` et `test` appellent les mêmes scripts qu'en local ; `main` est protégée (fusion par PR en rebase, CI verte obligatoire) ; les messages de commit sont revérifiés en CI, ce qui rattrape un `--no-verify`.

## Réglages GitHub (à faire par le développeur)

À faire après un premier run de la CI sur la PR de cette branche (un check n'apparaît dans la liste qu'après avoir tourné), et avant de la fusionner.

1. **Settings > Actions > General** : autoriser les actions de GitHub, `astral-sh/setup-uv@*` et `dependabot/*` ; activer « Require actions to be pinned to a full-length commit SHA » si proposé ; Workflow permissions en lecture seule ; décocher « Allow GitHub Actions to create and approve pull requests ».
2. **Settings > General > Pull Requests** : seulement « Allow rebase merging », et « Automatically delete head branches ».
3. **Settings > Rules > Rulesets**, ruleset `main` actif, sans contournement, ciblant la branche par défaut : Restrict deletions, Require linear history, Block force pushes, Require a pull request before merging (0 approbation, rebase uniquement), Require status checks to pass (branche à jour, checks `commits`, `lint`, `test`).
4. **En branche 2** : ajouter le check `docker`.

Un dépôt privé sur un compte GitHub Free n'applique pas ces protections.

## Étapes

1. Résoudre les versions : `uv --version` en local ; dernière release de `actions/checkout` et `astral-sh/setup-uv` et leur SHA de commit (`git ls-remote --tags https://github.com/<owner>/<repo> 'vX.Y.Z*'`, ligne `^{}` pour un tag annoté).
2. Écrire `.github/workflows/ci.yml` (LF, vérifié par `git ls-files --eol .github`).
3. Écrire `.github/dependabot.yml`.
4. Ajouter la section du README.
5. Pousser la branche et ouvrir la PR vers `main` ; vérifier les trois jobs.
6. Cas d'échec volontaires sur une branche jetable.
7. Réglages GitHub, puis vérifier que la protection bloque.
8. Fusionner en rebase et vérifier le run du push sur `main`.

## Vérifications

**Sur la PR de cette branche**

| Point | Attendu |
|---|---|
| `commits` | Une ligne `OK` par commit, code 0. |
| `lint` | Ruff passe, puis « mypy : aucun code Python (app/, tests/), étape ignorée. » |
| `test` | « Aucun fichier de test dans tests/, étape ignorée. » |
| « Set up job » | Permissions du jeton : `Contents: read`, `Metadata: read` seulement. |
| Cache | Absent au premier run, « Cache restored » au suivant. |
| Concurrence | Deux push rapprochés : le premier run est annulé. |

**Cas d'échec** (branche jetable `ci/test-echecs`, PR en brouillon, fermée sans fusion puis branche supprimée)

| Cas | Attendu |
|---|---|
| Commit `--no-verify -m "mauvais message"` | `commits` rouge. |
| Commit `fixup! ci: x` | `commits` rouge. |
| `app/probe.py` avec `def f(x): return x` | `lint` rouge (mypy). |
| Fichier Python mal formaté | `lint` rouge (format). |
| Test qui échoue | `test` rouge. |
| Dépendance ajoutée sans mettre à jour `uv.lock` | `lint` et `test` rouges. |
| `git update-index --chmod=-x scripts/lint.sh` | `lint` rouge. |

**Après les réglages** : une PR rouge ne peut pas être fusionnée ; `git push origin main` est refusé ; après fusion, le run `push` lance `lint` et `test`, `commits` est « skipped ».

## Préparation de la branche 2

- Job `test` : service `postgres:17` avec `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, health check `pg_isready`, port 5432, et l'URL de connexion en `env:` nommée comme dans `core/config.py`. Le mot de passe d'un conteneur jetable peut être en clair, à écrire explicitement dans le plan de la branche 2.
- Migrations lancées par `test.sh` ou les fixtures pytest, pas par une étape du workflow.
- Job `docker` : checkout puis `docker build --pull -t kcalibre:ci .`.
- Protection de `main` : ajouter le check `docker` ; ne pas renommer `test`.
- Le seuil de couverture de 80 % s'appliquera dès les premiers tests.

## Risques

- **Version d'uv** : la version CI doit être égale à la version locale (sinon `UV_LOCKED` peut échouer) ; elle figure dans deux jobs, à garder synchronisés.
- **Noms des checks** : renommer un job bloque toutes les PR tant que le ruleset n'est pas mis à jour.
- **Mise à jour de branche** : utiliser « Update branch » en mode rebase, pas merge.
- **Cache** : l'avertissement « Unable to reserve cache » entre deux jobs est sans conséquence.
- **Sécurité** : lecture seule, pas de secret, `base_ref` via `env`, jamais `pull_request_target`.
- **PR empilées** : une PR qui ne vise pas `main` ne déclenche pas la CI (voulu).

## Commits suggérés

1. `ci: ajout du workflow GitHub Actions (commits, lint, tests)`
2. `ci: mise à jour mensuelle des actions par Dependabot`
3. `docs: description de la CI et de la protection de main`
4. `docs: plan de la branche ci/github-actions`
