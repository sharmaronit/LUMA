import 'package:flutter/painting.dart';

/// Unmodified Minimal Android TV Icons, bundled offline with its MIT license.
const tvIconPackNames = {
  'browser': 'browser',
  'jellyfin': 'jellyfin',
  'netflix': 'netflix',
  'nuvio': 'nuvio',
  'plex': 'plex',
  'protonvpn': 'protonvpn',
  'tizentube': 'tizentube',
  'youtube': 'youtube',
  'youtubekids': 'youtubekids',
  'youtubemusic': 'youtubemusic',
  'adguard': 'adguard',
  'primevideo': 'amazon-prime',
  'amazonprimevideo': 'amazon-prime',
  'amazonprime': 'amazon-prime',
  'appstore': 'appstore',
  'ard': 'ard',
  'bbciplayer': 'bbc-iplayer',
  'cloudstream': 'cloudstream',
  'crunchyroll': 'crunchyroll',
  'disney': 'disney',
  'disneyplus': 'disney',
  'emby': 'emby',
  'fcast': 'fcast',
  'files': 'files',
  'hbomax': 'hbo-max',
  'max': 'hbo-max',
  'kodi': 'kodi',
  'localsend': 'localsend',
  'm3u': 'm3u',
  'moonlight': 'moonlight',
  'mullvadvpn': 'mullvad-vpn',
  'nordvpn': 'nord-vpn',
  'nvidia': 'nvidia',
  'geforcenow': 'nvidia',
  'paramountplus': 'paramount',
  'pcapdroid': 'pcapdroid',
  'playstation': 'playstation',
  'rtl': 'rtl',
  'settings': 'settings',
  'skyshowtime': 'sky-showtime',
  'sling': 'sling',
  'spotify': 'spotify',
  'steam': 'steam',
  'streamfc': 'streamfc',
  'stremio': 'stremio',
  'sunshine': 'sunshine',
  'tf1plus': 'tf1-plus',
  'tivimate': 'tivimate',
  'twitch': 'twitch',
  'vlc': 'vlc',
  'vlcforandroid': 'vlc',
};
const _packages = {
  'com.netflix.ninja': 'netflix',
  'com.netflix.mediaclient': 'netflix',
  'com.google.android.youtube.tv': 'youtube',
  'com.google.android.youtube': 'youtube',
  'com.google.android.youtube.tvkids': 'youtubekids',
  'com.google.android.apps.youtube.music': 'youtubemusic',
  'com.amazon.amazonvideo.livingroom': 'primevideo',
  'com.amazon.avod.thirdpartyclient': 'primevideo',
  'com.spotify.tv.android': 'spotify',
  'com.spotify.music': 'spotify',
  'com.plexapp.android': 'plex',
  'org.videolan.vlc': 'vlc',
  'com.crunchyroll.crunchyroid': 'crunchyroll',
  'com.disney.disneyplus': 'disney',
  'org.jellyfin.androidtv': 'jellyfin',
  'org.jellyfin.mobile': 'jellyfin',
  'com.mb.android': 'emby',
  'com.mb.android.tv': 'emby',
  'org.xbmc.kodi': 'kodi',
  'com.limelight': 'moonlight',
  'com.valvesoftware.steamlink': 'steam',
  'com.nvidia.geforcenow': 'nvidia',
  'tv.twitch.android.app': 'twitch',
  'ar.tvplayer.tv': 'tivimate',
  'com.stremio.one': 'stremio',
  'com.wbd.stream': 'max',
  'com.hbo.hbonow': 'hbomax',
  'com.cbs.ott': 'paramountplus',
  'com.microsoft.emmx': 'browser',
  'com.android.tv.settings': 'settings',
};
String tvAppKey(String id, String name) =>
    _packages[id.toLowerCase()] ??
    (tvIconPackNames.containsKey(id.toLowerCase())
        ? id.toLowerCase()
        : name.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), ''));

ImageProvider? tvIconPackArtwork(String id, String name) {
  final icon = tvIconPackNames[tvAppKey(id, name)];
  return icon == null ? null : AssetImage('assets/tv-icons/$icon.png');
}

const tvAppFilters = ['all', 'entertainment', 'music', 'games', 'utilities'];
String tvFilterLabel(String id) => id[0].toUpperCase() + id.substring(1);

String classifyTvApp(
  String id,
  String name, {
  int platformCategory = -1,
  bool isGame = false,
}) {
  final key = tvAppKey(id, name);
  if (isGame ||
      platformCategory == 0 ||
      const [
        'steam',
        'moonlight',
        'playstation',
        'nvidia',
        'geforcenow',
        'sunshine',
      ].contains(key))
    return 'games';
  if (platformCategory == 1 ||
      const [
        'spotify',
        'youtubemusic',
        'deezer',
        'tidal',
        'music',
      ].contains(key))
    return 'music';
  if (platformCategory == 2 ||
      const [
        'youtube',
        'youtubekids',
        'netflix',
        'jiohotstar',
        'hotstar',
        'jiotv',
        'jiotvplus',
        'sonyliv',
        'zee5',
        'primevideo',
        'amazonprimevideo',
        'amazonprime',
        'crunchyroll',
        'appletv',
        'apple-tv',
        'plex',
        'vlc',
        'vlcforandroid',
        'disney',
        'disneyplus',
        'jellyfin',
        'nuvio',
        'tizentube',
        'ard',
        'bbciplayer',
        'cloudstream',
        'emby',
        'hbomax',
        'max',
        'kodi',
        'm3u',
        'paramountplus',
        'rtl',
        'skyshowtime',
        'sling',
        'streamfc',
        'stremio',
        'tf1plus',
        'tivimate',
        'twitch',
      ].contains(key))
    return 'entertainment';
  return 'utilities';
}
