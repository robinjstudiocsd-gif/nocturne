# Architecture

L'app est découpée en packages Swift locaux. L'interface et les services dépendent du domaine, jamais l'inverse. La cible de l'app ne fait qu'assembler les vrais services et lancer l'interface.

## Modules

| Module | Rôle | État |
| --- | --- | --- |
| `SleepDomain` | Modèles métier (session, horaires, ressenti), règles, protocoles des services, versions factices pour les tests | Lot 0 |
| `Persistence` | Base SwiftData versionnée, dépôt des sessions, journal de diagnostic | Lot 0 |
| `AppSettings` | Préférences typées et valeurs par défaut, date d'expiration de la signature, suivi des renouvellements | Lot 0 |
| `DesignSystem` | Couleurs, typographie, cartes, boutons, anneau du score | Lot 0 |
| `Features` | Un module par rubrique : Accueil, Journal, Nuit, Statistiques, Conseils, Réglages | Lot 0 (écrans de départ) |
| `SleepAnalysis` | Métriques, profil de nuit, phases estimées, score, statistiques | Lot 4 (en cours) |
| `NightRecording` | Session de nuit, capture audio, tranches AAC de 5 min, niveau sonore chaque seconde (format binaire versionné), points de reprise, détection et extraits | Lot 2 (en cours) |
| `HealthIntegration` | Lecture et écriture Santé, import de l'export Santé en repli | Lot 6 |
| `Alarms` | Alarme jouée par l'app (iOS 18) et AlarmKit (iOS 26) | Lot 5 |
| `Notifications` | Rappels, bilans | Lot 5 |

## Règles

- **Local d'abord** : aucune fonction de base ne dépend d'Internet.
- **Concurrence stricte de Swift 6** : la capture audio tourne sur ses propres files, jamais sur celle de l'interface.
- **Injection de dépendances** : `App/AppContainer.swift` assemble les vrais services ; les tests utilisent des versions factices.
- **Une correction ne détruit jamais une détection** : chaque session garde ses horaires détectés et ses horaires corrigés.
- **Base protégée « jusqu'au premier déverrouillage »**, pour rester inscriptible la nuit, écran verrouillé.

## Tests

Les modules sans interface (`SleepDomain`, `SleepAnalysis`, `Persistence`, `AppSettings`, `NightRecording`) sont testés à chaque envoi avec `swift test`, sur le Mac de GitHub. Les essais sur l'iPhone se font à la fin du développement.
