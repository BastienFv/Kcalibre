# Kcalibre

API REST de suivi nutritionnel (FastAPI / PostgreSQL). Voir `docs/specifications.md`.

## Mise en place

Prérequis : [uv](https://docs.astral.sh/uv/) et Git (sous Windows, utiliser Git Bash pour les scripts). uv installe lui-même Python 3.12 si nécessaire.

```bash
uv sync                                  # crée .venv et installe les dépendances
git config core.hooksPath scripts/hooks  # active le hook commit-msg (une fois par clone)
./scripts/lint.sh                        # Ruff (format + lint) et mypy
./scripts/test.sh                        # pytest avec couverture
./scripts/check_commits.sh [base]        # valide les messages de base..HEAD (main par défaut)
```

Les messages de commit suivent Conventional Commits : `type(scope): description` (voir `CLAUDE.md`).

## Intégration continue

Le workflow GitHub Actions (`.github/workflows/ci.yml`) s'exécute sur chaque pull request vers `main` et chaque push sur `main`.
Ses checks `commits`, `lint` et `test` appellent les mêmes scripts qu'en local (`check_commits.sh`, `lint.sh`, `test.sh`).
La branche `main` est protégée : fusion par pull request en rebase uniquement, CI verte obligatoire.
Les messages de commit sont revérifiés en CI, ce qui rattrape un `--no-verify`.
