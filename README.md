# WouStore

Le magasin d'applis Android de Rody-241.

- **Catalogue** : `catalog.json`. Chaque appli y est décrite (nom, description, dépôt GitHub qui publie l'APK). Modifier ce fichier met à jour WouStore pour tout le monde, sans refabriquer l'appli.
- **Installation** : par l'installateur Android sur un téléphone normal, ou directement par **Shizuku** s'il est actif sur le téléphone.
- **Fabrication** : chaque envoi sur `main` fabrique `WouStore.apk` et le publie dans les Releases.

Secret nécessaire : `WOUSTORE_KEY_PASSWORD` (Settings › Secrets and variables › Actions).
