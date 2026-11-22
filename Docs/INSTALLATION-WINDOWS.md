# Installer Nocturne sur l'iPhone depuis Windows

Ce guide sert pour chaque version de l'app. Tu ne donnes jamais ton mot de passe Apple à personne : tu le tapes seulement dans Sideloadly, sur ton PC.

## Une seule fois : préparer le PC

1. Installe **iTunes, version du site d'Apple** (pas celle du Microsoft Store) : https://www.apple.com/itunes/download/win64. Si la version du Microsoft Store est déjà installée, désinstalle-la avant.
2. Installe **Sideloadly** depuis son site officiel : https://sideloadly.io. Si Windows bloque l'installateur, ne désactive aucune protection : préviens-moi et on passera à un autre outil.
3. Branche l'iPhone en USB, déverrouille-le et touche **Faire confiance**.
4. Facultatif, pour le renouvellement par Wi-Fi : dans iTunes, sélectionne l'iPhone, puis **Résumé**, puis **Options**, et coche **Synchroniser avec cet iPhone en Wi-Fi**. Le PC et l'iPhone doivent être sur le même réseau.

## Installer l'app

5. Télécharge l'app : https://github.com/robinjstudiocsd-gif/nocturne/releases/download/developpement/Nocturne.ipa
6. Ouvre Sideloadly, l'iPhone toujours branché.
7. Glisse **Nocturne.ipa** sur la grande icône IPA de Sideloadly.
8. Vérifie que ton iPhone est choisi, puis tape l'adresse de ton identifiant Apple dédié dans le champ du compte Apple.
9. Clique sur **Start**. Sideloadly demande le mot de passe de cet identifiant, puis le code de validation envoyé sur tes appareils : tape-les dans Sideloadly.
10. Attends la fin : Sideloadly affiche que c'est terminé.

## Une seule fois : autoriser l'app sur l'iPhone

11. **Réglages > Confidentialité et sécurité > Mode développeur** : active-le. L'iPhone redémarre ; à l'allumage, confirme **Activer**.
12. **Réglages > Général > VPN et gestion de l'appareil** : touche ton identifiant Apple dédié, puis **Faire confiance**.
13. Ouvre Nocturne.

## Les essais

Tous les essais sur l'iPhone se font à la fin du développement (décision du 22 novembre 2026, voir `Docs/decisions/0001-essais-a-la-fin.md`). La liste détaillée des essais sera ajoutée ici à ce moment-là.

## Bon à savoir

- Avec un identifiant Apple gratuit, une app reste signée 7 jours. Il faut la renouveler avant, en recommençant les étapes 5 à 10 avec le même fichier, ou avec le renouvellement automatique de Sideloadly.
- Un identifiant gratuit permet 3 apps installées ainsi, et 10 identifiants d'app par semaine. Nocturne en utilise 2 : l'app et son widget.
- Si l'app ne s'ouvre plus, la signature a expiré : réinstalle-la avec Sideloadly. Tes données restent sur l'iPhone.
