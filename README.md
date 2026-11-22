# Nocturne

App iOS de suivi du sommeil, centrée sur l'enregistrement et la réécoute des sons de la nuit. Gratuite, sans compte : tout reste sur l'iPhone.

## Où en est le projet

- **Étude** : validée le 22 novembre 2026.
- **Maquettes** : en cours.
- **Code** : phase 0, une app de test qui vérifie sur un iPhone SE (2e génération) sous iOS 18 les sept points dont dépend le projet.

## Compilation

Il n'y a pas de Mac : chaque envoi sur `main` lance la compilation sur un Mac de GitHub (`.github/workflows/build.yml`). Le fichier `Nocturne.ipa` est publié dans la version « phase0 » du dépôt.

## Installation

Voir [Docs/INSTALLATION-WINDOWS.md](Docs/INSTALLATION-WINDOWS.md).

## Organisation

- `project.yml` : description du projet Xcode, lue par XcodeGen.
- `App/` : l'app.
- `Extensions/NocturneWidgets/` : le widget et la Live Activity.
- `Shared/` : le code commun à l'app et à l'extension.
