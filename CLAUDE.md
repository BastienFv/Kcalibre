# Kcalibre

API REST de suivi nutritionnel : calcul des besoins caloriques et des macronutriments selon le profil et l'objectif de l'utilisateur, puis suivi des apports quotidiens.

La source de vérité fonctionnelle est `docs/specifications.md`. En cas de doute ou de contradiction entre une demande et les spécifications, poser la question plutôt que de deviner.

## Stack

- Python 3.12+, FastAPI, Pydantic v2
- PostgreSQL 17 (image Docker `postgres:17`), SQLAlchemy 2, Alembic
- PyJWT, argon2-cffi
- Ruff (lint + format), mypy (strict), pytest
- Docker, Docker Compose, GitHub Actions

**Ne jamais ajouter de dépendance sans demander l'accord explicite.** Le projet privilégie les scripts bash et la bibliothèque standard.

## Structure cible

Organisation **modulaire par fonctionnalité** : chaque module est une petite application en couches, autonome.

```
app/
  main.py              # création de l'application, inclusion des routeurs sous /api/v1, handlers d'exceptions
  core/                # transverse uniquement
    config.py          # configuration par variables d'environnement
    database.py        # moteur, session, classe Base SQLAlchemy
    security.py        # JWT, hachage des mots de passe
    exceptions.py      # exception de base AppError
  auth/                # utilisateurs, inscription, connexion, refresh tokens
  profiles/            # profil utilisateur et historique de poids
  nutrition/           # calculateur et objectifs journaliers
    calculator.py      # fonctions pures : BMR, TDEE, objectif, macros
  foods/               # catalogue d'aliments
  meals/               # entrées de repas et bilan quotidien
alembic/               # migrations
tests/
  unit/<module>/       # tests sans base de données
  integration/<module>/  # tests avec PostgreSQL
scripts/               # lint.sh, test.sh, check_commits.sh
scripts/hooks/         # hooks Git versionnés (commit-msg)
docs/                  # spécifications, plans de features
```

Chaque module contient, **uniquement selon ses besoins** :

| Fichier | Rôle |
|---|---|
| `router.py` | APIRouter du module : valide l'entrée, appelle le service, renvoie la réponse |
| `service.py` | Cas d'usage et règles métier du module |
| `schemas.py` | Modèles Pydantic d'entrée et de sortie |
| `repository.py` | Accès aux données du module |
| `models.py` | Modèles SQLAlchemy du module |
| `dependencies.py` | Dépendances FastAPI du module (ex : `get_current_user` dans `auth`) |
| `exceptions.py` | Exceptions métier du module |

## Conventions de code

- Code, identifiants et docstrings en anglais ; documentation du projet en français.
- Typage complet, compatible `mypy --strict`.
- Aucune logique métier dans un `router.py`.
- Le préfixe de version `/api/v1` est appliqué une seule fois, dans `main.py`, via `include_router(prefix=...)`.
- `core/` ne contient que du code transverse ; tout ce qui appartient à une fonctionnalité va dans son module.
- Pas de fichier ni de dossier créé « au cas où » : il n'existe que s'il contient du code utile.

### Dépendances entre modules

- Un module n'utilise un autre module que via son **service** (ou ses dépendances FastAPI publiques, comme `auth.dependencies.get_current_user`). Jamais via son repository ni ses modèles.
- Les dépendances circulaires entre modules sont interdites. Sens autorisé : `meals` → `nutrition` → `profiles` → `auth`, et `meals` → `foods`.
- `nutrition/calculator.py` ne dépend d'aucun autre module ni d'aucune bibliothèque externe.

### Exceptions

Approche basée sur la documentation FastAPI (« Handling Errors ») : `HTTPException` pour les erreurs propres à la couche HTTP, exceptions personnalisées et handlers globaux (`@app.exception_handler`) pour les erreurs métier.

- `router.py` et `dependencies.py` peuvent lever directement `HTTPException` (ex : 401 dans `get_current_user`), comme dans les exemples de la documentation FastAPI.
- Les services lèvent des exceptions métier, jamais `HTTPException` : ils ne connaissent pas HTTP.
- Les exceptions métier héritent de `AppError` (`core/exceptions.py`), qui porte le code HTTP et le message, et sont définies dans le `exceptions.py` du module concerné.
- Un seul handler global pour `AppError`, enregistré dans `main.py`, renvoie le même format JSON que les erreurs par défaut de FastAPI : `{"detail": "..."}`. Le client reçoit ainsi un format d'erreur unique.
- Les handlers par défaut de FastAPI (validation 422, `HTTPException`) ne sont pas surchargés sans raison. Si c'est nécessaire, enregistrer le handler sur `starlette.exceptions.HTTPException`, comme le précise la documentation.

### Base de données

- La classe `Base` SQLAlchemy est définie dans `core/database.py` ; chaque `models.py` en hérite.
- **Tous les `models.py` doivent être importés dans `alembic/env.py`**, sinon la génération automatique des migrations ne les détecte pas. Tout nouveau module avec des modèles implique de mettre à jour ce fichier.
- Une migration Alembic par changement de schéma, relue avant d'être committée.

### Calculs et tests

- Les calculs nutritionnels (`nutrition/calculator.py`) sont des fonctions pures, testées unitairement.
- Les calculs intermédiaires restent en décimal ; seuls les résultats finaux sont arrondis (voir spécifications, section 3.5).
- Toute nouvelle fonctionnalité est accompagnée de tests.
- Jamais de secret en dur : configuration par variables d'environnement.

## Commandes

```bash
uv sync                                  # installer les dépendances (.venv)
git config core.hooksPath scripts/hooks  # activer le hook commit-msg (une fois par clone)
./scripts/check_commits.sh [base]        # valider les messages de commit de base..HEAD
./scripts/lint.sh          # Ruff + mypy
./scripts/test.sh          # pytest avec couverture
docker compose up -d       # API + PostgreSQL en local
alembic upgrade head       # appliquer les migrations
```

Avant de considérer une tâche terminée, `./scripts/lint.sh` et `./scripts/test.sh` doivent passer.

## Git

- Ne jamais committer directement sur `main`. Une branche par feature, nommée `type/description` (ex : `feat/user-profile`).
- L'ordre des branches est défini dans `docs/specifications.md`, section 8.
- Messages au format Conventional Commits, description en français :
  `type(scope): description` avec type parmi `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
  Exemple : `feat(auth): ajout de la rotation des refresh tokens`
- Ne pas committer ni pousser sans demande explicite : proposer le message de commit, le développeur valide.

## Agents du projet

- `architect` : produit un plan d'implémentation pour une feature, sans modifier le code.
- `developer` : implémente un plan validé, avec ses tests.
- `code-reviewer` : relit les changements de la branche courante par rapport à `main`.

Flux pour chaque feature : plan par `architect`, validation humaine, implémentation par `developer`, relecture par `code-reviewer`, corrections, puis pull request.
