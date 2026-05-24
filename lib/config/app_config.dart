class AppConfig {
  static String get baseUrl {
    // Production Server on Google Cloud Run - USA Region
    return 'https://cultioo-app-78230737866.us-central1.run.app';
    
    // Local backend for development (commented out)
    // if (Platform.isIOS) {
    //   return 'http://192.168.0.118:3006';
    // }
    // return 'http://127.0.0.1:3006';
  }

  static String get apiUrl => '$baseUrl/api';

  // WebSocket URL for Chat (if needed)
  static String get wsUrl {
    String base = baseUrl.replaceFirst('http', 'ws');
    return '$base/ws';
  }
}
