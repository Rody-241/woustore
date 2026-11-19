import 'package:flutter/material.dart';

/// Une autorisation expliquée simplement.
class PermissionInfo {
  const PermissionInfo(this.icon, this.label, {this.sensitive = false});

  final IconData icon;
  final String label;

  /// Touche à la vie privée (position, micro, contacts…) : affichée en premier.
  final bool sensitive;
}

const _p = 'android.permission.';

/// Plusieurs autorisations techniques peuvent donner la même phrase :
/// elles sont regroupées à l'affichage.
final Map<String, PermissionInfo> permissionLabels = {
  '${_p}ACCESS_FINE_LOCATION': const PermissionInfo(Icons.location_on_outlined, 'Connaître ta position exacte', sensitive: true),
  '${_p}ACCESS_COARSE_LOCATION': const PermissionInfo(Icons.location_on_outlined, 'Connaître ta position approximative', sensitive: true),
  '${_p}ACCESS_BACKGROUND_LOCATION': const PermissionInfo(Icons.location_on_outlined, 'Connaître ta position même quand elle est fermée', sensitive: true),
  '${_p}CAMERA': const PermissionInfo(Icons.photo_camera_outlined, "Utiliser l'appareil photo", sensitive: true),
  '${_p}RECORD_AUDIO': const PermissionInfo(Icons.mic_none_rounded, 'Enregistrer avec le micro', sensitive: true),
  '${_p}READ_CONTACTS': const PermissionInfo(Icons.contacts_outlined, 'Lire tes contacts', sensitive: true),
  '${_p}WRITE_CONTACTS': const PermissionInfo(Icons.contacts_outlined, 'Modifier tes contacts', sensitive: true),
  '${_p}GET_ACCOUNTS': const PermissionInfo(Icons.contacts_outlined, 'Voir les comptes du téléphone', sensitive: true),
  '${_p}READ_SMS': const PermissionInfo(Icons.sms_outlined, 'Lire tes SMS', sensitive: true),
  '${_p}SEND_SMS': const PermissionInfo(Icons.sms_outlined, 'Envoyer des SMS (peut coûter du crédit)', sensitive: true),
  '${_p}RECEIVE_SMS': const PermissionInfo(Icons.sms_outlined, 'Recevoir tes SMS', sensitive: true),
  '${_p}CALL_PHONE': const PermissionInfo(Icons.call_outlined, 'Passer des appels (peut coûter du crédit)', sensitive: true),
  '${_p}READ_PHONE_STATE': const PermissionInfo(Icons.phone_android_outlined, "Voir l'état du téléphone et des appels", sensitive: true),
  '${_p}READ_CALL_LOG': const PermissionInfo(Icons.call_outlined, "Lire ton journal d'appels", sensitive: true),
  '${_p}READ_CALENDAR': const PermissionInfo(Icons.event_outlined, 'Lire ton agenda', sensitive: true),
  '${_p}WRITE_CALENDAR': const PermissionInfo(Icons.event_outlined, 'Modifier ton agenda', sensitive: true),
  '${_p}BODY_SENSORS': const PermissionInfo(Icons.monitor_heart_outlined, 'Lire les capteurs de santé', sensitive: true),
  '${_p}ACTIVITY_RECOGNITION': const PermissionInfo(Icons.directions_walk_rounded, 'Suivre ton activité physique', sensitive: true),
  '${_p}READ_EXTERNAL_STORAGE': const PermissionInfo(Icons.folder_outlined, 'Lire tes fichiers', sensitive: true),
  '${_p}WRITE_EXTERNAL_STORAGE': const PermissionInfo(Icons.folder_outlined, 'Modifier tes fichiers', sensitive: true),
  '${_p}MANAGE_EXTERNAL_STORAGE': const PermissionInfo(Icons.folder_outlined, 'Accéder à tous tes fichiers', sensitive: true),
  '${_p}READ_MEDIA_IMAGES': const PermissionInfo(Icons.photo_library_outlined, 'Voir tes photos', sensitive: true),
  '${_p}READ_MEDIA_VIDEO': const PermissionInfo(Icons.video_library_outlined, 'Voir tes vidéos', sensitive: true),
  '${_p}READ_MEDIA_AUDIO': const PermissionInfo(Icons.library_music_outlined, 'Voir ta musique', sensitive: true),
  '${_p}SYSTEM_ALERT_WINDOW': const PermissionInfo(Icons.picture_in_picture_alt_outlined, "S'afficher par-dessus les autres applis", sensitive: true),
  '${_p}REQUEST_INSTALL_PACKAGES': const PermissionInfo(Icons.install_mobile_rounded, "Installer d'autres applis", sensitive: true),
  '${_p}QUERY_ALL_PACKAGES': const PermissionInfo(Icons.apps_rounded, 'Voir la liste de tes applis'),
  '${_p}INTERNET': const PermissionInfo(Icons.public_rounded, 'Utiliser Internet'),
  '${_p}ACCESS_NETWORK_STATE': const PermissionInfo(Icons.wifi_rounded, 'Voir ta connexion (Wi-Fi, données)'),
  '${_p}ACCESS_WIFI_STATE': const PermissionInfo(Icons.wifi_rounded, 'Voir ta connexion (Wi-Fi, données)'),
  '${_p}CHANGE_WIFI_STATE': const PermissionInfo(Icons.wifi_rounded, 'Allumer ou éteindre le Wi-Fi'),
  '${_p}BLUETOOTH_CONNECT': const PermissionInfo(Icons.bluetooth_rounded, 'Se connecter aux appareils Bluetooth'),
  '${_p}BLUETOOTH_SCAN': const PermissionInfo(Icons.bluetooth_rounded, 'Chercher des appareils Bluetooth'),
  '${_p}NEARBY_WIFI_DEVICES': const PermissionInfo(Icons.devices_other_rounded, 'Trouver les appareils proches en Wi-Fi'),
  '${_p}POST_NOTIFICATIONS': const PermissionInfo(Icons.notifications_none_rounded, "T'envoyer des notifications"),
  '${_p}VIBRATE': const PermissionInfo(Icons.vibration_rounded, 'Faire vibrer le téléphone'),
  '${_p}WAKE_LOCK': const PermissionInfo(Icons.battery_charging_full_rounded, "Empêcher l'écran de se mettre en veille"),
  '${_p}FOREGROUND_SERVICE': const PermissionInfo(Icons.sync_rounded, 'Continuer à fonctionner en arrière-plan'),
  '${_p}RECEIVE_BOOT_COMPLETED': const PermissionInfo(Icons.power_settings_new_rounded, 'Démarrer avec le téléphone'),
  '${_p}USE_BIOMETRIC': const PermissionInfo(Icons.fingerprint_rounded, "Utiliser l'empreinte digitale"),
  '${_p}USE_FINGERPRINT': const PermissionInfo(Icons.fingerprint_rounded, "Utiliser l'empreinte digitale"),
  '${_p}NFC': const PermissionInfo(Icons.nfc_rounded, 'Utiliser le NFC'),
  '${_p}SET_WALLPAPER': const PermissionInfo(Icons.wallpaper_rounded, "Changer le fond d'écran"),
};

/// Les phrases à afficher (sans doublons, sensibles d'abord) et le nombre
/// d'autorisations techniques sans importance pour l'utilisateur.
({List<PermissionInfo> shown, int technical}) describePermissions(List<String> perms) {
  final seen = <String>{};
  final shown = <PermissionInfo>[];
  var technical = 0;
  for (final p in perms) {
    // FOREGROUND_SERVICE_DATA_SYNC, etc. → FOREGROUND_SERVICE
    final key = p.startsWith('${_p}FOREGROUND_SERVICE') ? '${_p}FOREGROUND_SERVICE' : p;
    final info = permissionLabels[key];
    if (info == null) {
      technical++;
    } else if (seen.add(info.label)) {
      shown.add(info);
    }
  }
  shown.sort((a, b) => (b.sensitive ? 1 : 0) - (a.sensitive ? 1 : 0));
  return (shown: shown, technical: technical);
}
