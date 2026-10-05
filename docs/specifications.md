# Spécifications fonctionnelles et techniques

API de suivi nutritionnel permettant de calculer ses besoins caloriques et en macronutriments selon son profil et son objectif, puis de suivre ses apports quotidiens.

## 1. Objectif du projet

L'application permet à un utilisateur de :

- connaître ses besoins caloriques journaliers selon son sexe, son âge, sa taille, son poids, son niveau d'activité et son objectif (perte de gras, maintien, prise de muscle) ;
- obtenir une répartition cible en protéines, glucides et lipides adaptée à un public sportif ;
- enregistrer ses repas et comparer chaque jour ses apports à ses objectifs.

Le projet est une API REST. Aucune interface graphique n'est prévue dans le MVP ; la documentation interactive est fournie par OpenAPI (Swagger UI).

## 2. Périmètre

### Inclus dans le MVP

- Authentification par JWT (access token + refresh token avec rotation)
- Gestion du profil utilisateur et de l'historique de poids
- Calcul des besoins caloriques et des macronutriments cibles
- Catalogue d'aliments personnel
- Saisie des repas et bilan quotidien

### Hors périmètre (évolutions possibles)

- Formule de Katch-McArdle (basée sur la masse maigre)
- Import d'aliments depuis Open Food Facts
- Intensité de déficit ou de surplus choisie par l'utilisateur
- Statistiques et tendances sur plusieurs semaines
- Interface web ou mobile

## 3. Règles métier

### 3.1 Conditions d'utilisation

Les formules utilisées sont validées pour des adultes. L'utilisateur doit avoir **au moins 18 ans**.

| Donnée | Unité | Bornes acceptées |
|---|---|---|
| Taille | cm | 100 à 250 |
| Poids | kg | 30 à 300 |
| Âge (calculé) | années | 18 à 100 |

L'âge n'est jamais stocké : il est calculé à partir de la date de naissance, à la date pour laquelle l'objectif est calculé.

### 3.2 Métabolisme de base (BMR)

Formule de **Mifflin-St Jeor** (poids en kg, taille en cm, âge en années) :

- Homme : `BMR = 10 × poids + 6,25 × taille − 5 × âge + 5`
- Femme : `BMR = 10 × poids + 6,25 × taille − 5 × âge − 161`

Le calcul du BMR est isolé dans un composant dédié afin de pouvoir ajouter d'autres formules plus tard sans modifier le reste du code.

### 3.3 Dépense énergétique totale (TDEE)

`TDEE = BMR × facteur d'activité`

| Niveau | Code | Facteur |
|---|---|---|
| Sédentaire | `sedentary` | 1,2 |
| Légèrement actif (1 à 3 séances/semaine) | `light` | 1,375 |
| Modérément actif (3 à 5 séances/semaine) | `moderate` | 1,55 |
| Très actif (6 à 7 séances/semaine) | `very_active` | 1,725 |
| Extrêmement actif (travail physique + sport) | `extra_active` | 1,9 |

### 3.4 Objectif calorique

| Objectif | Code | Ajustement par défaut |
|---|---|---|
| Perte de gras | `fat_loss` | −20 % du TDEE |
| Maintien | `maintenance` | 0 % |
| Prise de muscle | `muscle_gain` | +10 % du TDEE |

**Plancher de sécurité** : l'objectif calorique ne peut jamais être inférieur au BMR. Si l'ajustement fait passer sous ce seuil, l'objectif est ramené au BMR.

### 3.5 Répartition des macronutriments

Ordre de calcul : protéines, puis lipides, puis glucides avec les calories restantes.

| Objectif | Protéines par défaut | Plage autorisée | Lipides |
|---|---|---|---|
| Perte de gras | 2,0 g/kg | 1,6 à 2,4 g/kg | 25 % des kcal |
| Maintien | 1,6 g/kg | 1,6 à 2,4 g/kg | 25 % des kcal |
| Prise de muscle | 1,8 g/kg | 1,6 à 2,4 g/kg | 25 % des kcal |

L'utilisateur peut personnaliser son ratio de protéines dans la plage autorisée ; à défaut, la valeur par défaut de son objectif s'applique.

Valeurs énergétiques : protéines 4 kcal/g, glucides 4 kcal/g, lipides 9 kcal/g.

`glucides (g) = (objectif kcal − kcal protéines − kcal lipides) / 4`

**Cas limite** : si les calories restantes pour les glucides sont négatives, les lipides sont réduits jusqu'à 20 % minimum ; si cela ne suffit pas, les glucides sont fixés à 0.

**Arrondis** : tous les calculs intermédiaires sont faits en nombres décimaux ; seuls les résultats finaux sont arrondis (kcal et grammes à l'entier).

### 3.6 Exemple de référence (cas de test)

Homme, 30 ans, 180 cm, 80 kg, modérément actif, objectif perte de gras, ratio de protéines par défaut.

| Étape | Calcul | Résultat |
|---|---|---|
| BMR | 800 + 1125 − 150 + 5 | 1780 kcal |
| TDEE | 1780 × 1,55 | 2759 kcal |
| Objectif | 2759 × 0,80 | 2207 kcal |
| Protéines | 2,0 × 80 | 160 g (640 kcal) |
| Lipides | 25 % de 2207,2 = 551,8 kcal / 9 | 61 g |
| Glucides | (2207,2 − 640 − 551,8) / 4 | 254 g |

### 3.7 Historique et instantanés

Pour que l'historique reste juste quand le profil évolue :

- **Objectifs journaliers** : l'objectif d'une date D est calculé avec le profil courant et le dernier poids enregistré à une date inférieure ou égale à D. Il est figé (instantané) lors de sa première consultation ou de la première saisie de repas du jour. Une modification du profil ou du poids recalcule uniquement l'objectif du jour courant ; les jours passés ne changent plus.
- **Repas** : à la création d'une entrée de repas, les valeurs nutritionnelles calculées (kcal et macros pour la quantité saisie) sont copiées dans l'entrée. Modifier ou supprimer un aliment du catalogue n'altère donc pas les jours passés.

## 4. Authentification

| Élément | Choix |
|---|---|
| Access token | JWT signé, durée de vie 15 minutes |
| Refresh token | Valeur aléatoire opaque, durée de vie 7 jours |
| Stockage des refresh tokens | En base, uniquement sous forme hachée |
| Mots de passe | Hachés avec Argon2 |

**Rotation** : chaque appel à `/auth/refresh` invalide le refresh token utilisé et en émet un nouveau.

**Détection de réutilisation** : si un refresh token déjà révoqué est présenté, tous les refresh tokens de l'utilisateur sont révoqués (signe probable de vol de token).

**Déconnexion** : révoque le refresh token fourni.

## 5. Modèle de données

| Table | Champs principaux | Contraintes |
|---|---|---|
| `users` | id, email, password_hash, created_at | email unique |
| `refresh_tokens` | id, user_id, token_hash, expires_at, revoked_at, created_at | token_hash unique |
| `profiles` | user_id, sex, birth_date, height_cm, activity_level, goal, protein_g_per_kg (optionnel) | un profil par utilisateur |
| `weight_entries` | id, user_id, date, weight_kg | unique (user_id, date) |
| `daily_targets` | id, user_id, date, bmr, tdee, target_kcal, protein_g, carbs_g, fat_g | unique (user_id, date) |
| `foods` | id, user_id, name, kcal_100g, protein_100g, carbs_100g, fat_100g | appartient à l'utilisateur |
| `meal_entries` | id, user_id, date, meal_type, food_id, quantity_g, kcal, protein_g, carbs_g, fat_g | valeurs copiées à la création |

Types de repas (`meal_type`) : `breakfast`, `lunch`, `dinner`, `snack`.

## 6. Endpoints de l'API

Préfixe : `/api/v1`. Tous les endpoints, sauf l'authentification et `/health`, nécessitent un access token valide.

| Méthode | Route | Description |
|---|---|---|
| GET | `/health` | État de l'API et de la base |
| POST | `/auth/register` | Inscription |
| POST | `/auth/login` | Connexion, renvoie access + refresh token |
| POST | `/auth/refresh` | Nouveau couple de tokens (rotation) |
| POST | `/auth/logout` | Révocation du refresh token |
| GET | `/me/profile` | Consulter son profil |
| PUT | `/me/profile` | Créer ou modifier son profil |
| POST | `/me/weights` | Enregistrer un poids |
| GET | `/me/weights?from=&to=` | Historique de poids |
| DELETE | `/me/weights/{id}` | Supprimer une pesée |
| GET | `/me/targets/{date}` | Objectifs caloriques et macros d'un jour |
| POST | `/foods` | Créer un aliment |
| GET | `/foods?search=` | Lister ou rechercher ses aliments |
| GET | `/foods/{id}` | Détail d'un aliment |
| PATCH | `/foods/{id}` | Modifier un aliment |
| DELETE | `/foods/{id}` | Supprimer un aliment |
| POST | `/meals` | Ajouter une entrée de repas |
| GET | `/meals?date=` | Repas d'un jour |
| PATCH | `/meals/{id}` | Modifier une entrée |
| DELETE | `/meals/{id}` | Supprimer une entrée |
| GET | `/me/summary/{date}` | Bilan du jour : objectif, consommé, restant |

## 7. Exigences techniques

### Stack

- Python 3.12+, FastAPI, Pydantic v2
- PostgreSQL 16, SQLAlchemy 2, Alembic pour les migrations
- PyJWT pour les tokens, argon2-cffi pour le hachage
- Docker et Docker Compose pour l'environnement local

### Qualité

- Lint et formatage : Ruff
- Typage : mypy en mode strict
- Tests : pytest, avec une couverture visée d'au moins 90 % sur la logique métier (calculs) et 80 % sur l'ensemble
- Logique métier écrite en fonctions pures, testables sans base de données ni FastAPI

### Outillage sans dépendance supplémentaire

- Scripts bash dans `scripts/` (`lint.sh`, `test.sh`, `check_commits.sh`), seule source de vérité appelée en local et en CI
- Hook Git natif `commit-msg` dans `scripts/hooks/`, activé via `git config core.hooksPath scripts/hooks`
- Messages de commit au format Conventional Commits : `type(scope): description`

### CI/CD (GitHub Actions)

À chaque pull request : vérification des messages de commit, lint, typage, tests avec une base PostgreSQL de service, build de l'image Docker. La branche `main` est protégée et n'accepte que des pull requests dont la CI est verte.

## 8. Découpage en features

Chaque feature est développée sur sa propre branche et intégrée par pull request.

| # | Branche | Contenu |
|---|---|---|
| 0 | `chore/project-setup` | Structure du projet, dépendances, Ruff, mypy, pytest, scripts bash, hook de commit |
| 1 | `ci/github-actions` | Pipeline CI appelant les scripts |
| 2 | `build/docker-postgres` | Dockerfile, docker-compose, connexion PostgreSQL, Alembic, endpoint `/health` |
| 3 | `feat/auth-register-login` | Modèle utilisateur, inscription, connexion, access token |
| 4 | `feat/auth-refresh-logout` | Refresh tokens, rotation, détection de réutilisation, déconnexion |
| 5 | `feat/user-profile` | Profil et validations |
| 6 | `feat/weight-history` | Historique de poids |
| 7 | `feat/nutrition-calculator` | Calculs BMR, TDEE, objectif, macros en fonctions pures + tests |
| 8 | `feat/daily-targets` | Endpoint des objectifs avec instantanés journaliers |
| 9 | `feat/food-catalog` | CRUD des aliments |
| 10 | `feat/meal-entries` | Saisie des repas avec copie des valeurs nutritionnelles |
| 11 | `feat/daily-summary` | Bilan quotidien |
| 12 | `docs/readme` | README complet : présentation, architecture, lancement, choix techniques |

## 9. Sources

- Mifflin M.D. et al. (1990), *A new predictive equation for resting energy expenditure in healthy individuals*, American Journal of Clinical Nutrition.
- Frankenfield D. et al. (2005), *Comparison of predictive equations for resting metabolic rate in healthy nonobese and obese adults: a systematic review*, Journal of the American Dietetic Association.
- Morton R.W. et al. (2018), *A systematic review, meta-analysis and meta-regression of the effect of protein supplementation on resistance training-induced gains in muscle mass and strength in healthy adults*, British Journal of Sports Medicine.
- Helms E.R. et al. (2014), *A systematic review of dietary protein during caloric restriction in resistance trained lean athletes: a case for higher intakes*, International Journal of Sport Nutrition and Exercise Metabolism.

Les valeurs calculées par l'application sont des estimations et ne remplacent pas l'avis d'un professionnel de santé ou d'un diététicien.
