# Méthodologie du score et de l'analyse de la nuit

Ce document décrit comment Nocturne estime les horaires d'une nuit et calcule son score sur 100. Chaque nuit garde la version de l'analyse et celle du score qui ont servi ; chaque changement est ajouté ici, avec son numéro de version.

Nocturne ne pose aucun diagnostic. Ces chiffres aident à suivre ses habitudes ; ils ne remplacent pas l'avis d'un professionnel.

## 1. Analyse de la nuit sans montre (version 1)

Sans Apple Watch, l'iPhone ne mesure rien du corps. Il déduit un profil de la nuit de trois indices : les mouvements du lit, les sons de la chambre et l'usage du téléphone. L'analyse se fait à l'arrêt de la nuit (ou à la reprise d'une nuit interrompue). Elle regarde la nuit par périodes de 30 secondes.

### Les mesures

| Mesure | D'où elle vient | Ce qu'elle indique |
| --- | --- | --- |
| Mouvements | Accéléromètre, moyenne de chaque période de 30 s, en millièmes de g | Sur le matelas : chaque fois qu'on se retourne. Sur la table de nuit : seulement quand on prend l'iPhone. |
| Sons | Niveau sonore de chaque seconde, comparé au bruit de fond de la chambre (20e centile sur 10 minutes) | Une seconde compte comme bruyante 10 dB au-dessus du fond. |
| Sons reconnus | Classement des sons pendant la nuit | Ronflements et respiration : signes de sommeil. Paroles : éveil probable. Toux : nuit agitée. Bruits extérieurs et sons marqués « ce n'est pas moi » : ignorés. |
| Déverrouillages | Verrouillage et déverrouillage signalés par iOS | Chaque usage du téléphone marque un éveil probable. Retenus seulement si iOS signale aussi les verrouillages (iPhone avec code). |

Le repos de la nuit est le 10e centile des mouvements : il efface le petit décalage propre à chaque accéléromètre. L'iPhone est jugé posé sur le lit s'il sent au moins 4 mouvements séparés par 5 minutes de calme pendant la nuit (2 pour une session de moins de 2 heures), sans compter les 10 premières et les 10 dernières minutes.

### L'état de chaque période

| État | Règle |
| --- | --- |
| Éveil probable | iPhone déverrouillé ; ou iPhone de la table de nuit pris en main (12 millièmes de g au-dessus du repos) ; ou, sur le lit, mouvement de 12 millièmes de g qui dure plus d'une période ; ou mouvement avec paroles, ou avec au moins la moitié des secondes bruyantes. Avec le son seul : paroles, ou la moitié des secondes bruyantes. |
| Agité | Mouvement de 4 millièmes de g au-dessus du repos, paroles ou toux, ou au moins 30 % des secondes bruyantes (15 % avec le son seul). Se retourner une fois reste « agité ». |
| Calme | Ni mouvement ni bruit notable, ou ronflement. |
| Sans mesure | Ni mouvement utile ni son (écoute coupée). |

### Les horaires

| Horaire | Règle |
| --- | --- |
| Coucher | Début de la session. |
| Endormissement | Début de la première période de 15 minutes sans éveil ni trou, calme aux trois quarts, qui commence par une période calme (5 minutes pour une sieste). La session peut donc démarrer en avance. |
| Réveil | Fin du dernier sommeil d'au moins une minute et demie avant l'arrêt. |
| Lever | Arrêt de la session. |
| Réveils dans la nuit | Suites d'éveil probable d'au moins 2 minutes entre l'endormissement et le réveil, réunies quand une seule période calme les sépare. |

### Fiabilité

| Données | Fiabilité des horaires |
| --- | --- |
| Montre (Apple Santé, lot 6) | Élevée |
| iPhone sur le lit, avec le son | Moyenne |
| Son seul, ou mouvements seuls | Faible |
| Horaires saisis ou corrigés par toi | Moyenne |

Les seuils (4 et 12 millièmes de g, 10 dB, 15 minutes…) sont des choix de départ. Ils seront réglés sur des nuits réelles pendant les essais ; chaque réglage changera le numéro de version de l'analyse.

## 2. Score sur 100 (version 1)

Le score additionne six critères pondérés. Chaque critère reçoit une note entre 0 et 1, qui varie de façon linéaire entre la borne de note maximale et celle de note nulle.

| Critère | Poids | Mesure | Note maximale si | Note nulle si |
| --- | --- | --- | --- | --- |
| Durée | 30 | Temps de sommeil comparé à l'objectif | Dans l'objectif (7 à 9 h par défaut) | 2 h sous l'objectif, ou 2 h au-dessus |
| Continuité | 20 | Moyenne de trois sous-notes : efficacité, éveil après endormissement, endormissement | Efficacité ≥ 85 %, éveil ≤ 20 min, endormissement ≤ 30 min | 65 %, 60 min, 60 min |
| Réveils | 10 | Réveils de plus de 5 min | 1 au plus | 4 ou plus |
| Régularité | 20 | Écart du milieu du sommeil à la moyenne des 7 nuits précédentes | 30 min au plus | 2 h ou plus |
| Phases | 10 | Part de profond et de paradoxal, comparée à ta médiane sur 30 nuits | Au plus 5 points sous ta médiane | 20 points sous ta médiane |
| Objectifs personnels | 10 | Écart aux heures de coucher et de lever choisies | 30 min au plus | 90 min ou plus |

Le score vaut la somme des notes multipliées par leur poids, divisée par la somme des poids des critères comptés, ramenée sur 100.

### Règles contre la fausse précision

- Un critère ne compte que si ses données ont une fiabilité au moins moyenne. Avec des horaires de fiabilité faible, les critères qui en dépendent sont retirés.
- Les phases ne comptent que si elles viennent d'une montre, après 10 nuits mesurées. L'estimation expérimentale des phases sans montre n'entre jamais dans le score.
- La régularité attend 3 nuits précédentes ; les objectifs, au moins une heure cible ; une sieste n'a ni régularité ni objectifs.
- Sans heure de coucher connue, la continuité ne repose que sur l'éveil après endormissement.
- Le poids d'un critère retiré est redistribué sur les autres. Si les critères comptés pèsent moins de 60 points, l'app affiche « Score indisponible » et la liste des données manquantes.
- La fiabilité du score est la plus faible de celles des critères comptés, baissée d'un cran si les critères comptés pèsent moins de 80 points. Si elle est faible, le score est arrondi à 5 points et précédé de « environ ».

### Qualité estimée

La qualité estimée (très bonne, bonne, moyenne, faible) ne regarde que la continuité (deux tiers) et les réveils (un tiers) : très bonne à partir de 0,85, bonne à partir de 0,7, moyenne à partir de 0,5.

### Dette de sommeil

La dette de sommeil cumule, sur 14 jours, l'écart entre ton besoin et ton sommeil. Une nuit compte pour le jour où elle se termine ; les siestes s'y ajoutent. Un jour sans nuit mesurée ne compte pas : l'app ne devine jamais un sommeil absent. Une dette ne descend jamais sous zéro.

## Références

Les mêmes que dans l'étude préalable :

- [Recommandations de durée de sommeil de la NSF (2015)](https://pubmed.ncbi.nlm.nih.gov/29073412/) : 7 à 9 h pour les adultes.
- [Recommandations de qualité du sommeil de la NSF (2017)](https://pubmed.ncbi.nlm.nih.gov/28346153/) : efficacité, endormissement, éveil après endormissement, réveils.
- [Régularité du sommeil et mortalité, Windred et al. (2024)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10782501/) : la régularité prédit mieux la mortalité que la durée.

## Historique des versions

| Date | Analyse | Score | Changement |
| --- | --- | --- | --- |
| Novembre 2026 | 1 | 1 | Première version |
