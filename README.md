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
