# 0001 · Tous les essais sur l'iPhone à la fin du développement

**Date** : 22 novembre 2026
**Décision de** : Robin

## Décision

L'app est développée entièrement, puis tous les essais sur l'iPhone SE (2e génération) sont faits à la fin, y compris ceux de la phase 0 : nuit enregistrée écran verrouillé, alarme d'iOS 18, notification, Live Activity, widget, lecture de Santé et renouvellement après 7 jours.

## Conséquences

- Pendant le développement, chaque version est compilée et testée automatiquement sur le Mac de GitHub. Une version n'est dite « fonctionne » qu'après l'essai sur l'iPhone.
- Le choix de la version d'iOS reste ouvert jusqu'aux essais : l'alarme est développée pour iOS 18 (jouée par l'app) et pour iOS 26 (AlarmKit).
- L'accès à Santé est isolé dans `HealthIntegration`, pour pouvoir le remplacer par l'import de l'export Santé si la signature gratuite le refuse.
- L'audio est enregistré en tranches de 5 minutes, avec les trous notés : une coupure ne fait perdre que quelques minutes.
- L'export et l'archive des nuits sont prêts avant la campagne d'essais.
- Le renouvellement de la signature prend une semaine de calendrier : prévoir cette semaine dans la campagne d'essais.
