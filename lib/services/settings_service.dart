import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../utils/number_formatters.dart';

class SettingsService {
  static const String _themeKey = 'theme_mode'; // 'light', 'dark', 'system'
  static const String _textSizeKey = 'text_size'; // 'small', 'medium', 'large'
  static const String _languageKey = 'language'; // 'en', 'de'
  static const String _numberFormatKey = 'numberFormat'; // 'en', 'de'
  static const String _currencyKey = 'currency'; // 'usd', 'eur'
  static const String _accentColorKey = 'accentColor';
  static const String _syncWithBackendKey = 'syncWithBackend';
  static const String _dockEnabledKey = 'dockEnabled';

  /// Language code for [getLocalizedStrings] when preference is system / null.
  static String resolvedUiLanguageCode(String? language) {
    if (language != null && language != 'system') {
      return language;
    }
    final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
    const supported = ['en', 'de', 'es', 'fr', 'ru', 'it', 'pt'];
    return supported.contains(code) ? code : 'en';
  }

  // Load local settings
  static Future<Map<String, dynamic>> loadLocalSettings() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    return {
      'theme': prefs.getString(_themeKey) ?? 'system', // Default: follow system
      'textSize': prefs.getString(_textSizeKey) ?? 'system',
      'language': prefs.getString(_languageKey) ?? 'system',
      'numberFormat': prefs.getString(_numberFormatKey) ?? 'system',
      'currency': prefs.getString(_currencyKey) ?? 'system',
      'accentColor':
          prefs.getInt(_accentColorKey) ?? const Color(0xFF8E8E93).value,
      'syncWithBackend': prefs.getBool(_syncWithBackendKey) ?? true,
      'dockEnabled':
          prefs.getBool(_dockEnabledKey) ?? true, // Default: Dock enabled
    };
  }

  // Save local settings
  static Future<void> saveLocalSettings(Map<String, dynamic> settings) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    if (settings.containsKey('theme')) {
      await prefs.setString(_themeKey, settings['theme']);
    }
    if (settings.containsKey('textSize')) {
      await prefs.setString(_textSizeKey, settings['textSize']);
    }
    if (settings.containsKey('language')) {
      await prefs.setString(_languageKey, settings['language']);
    }
    if (settings.containsKey('numberFormat')) {
      await prefs.setString(_numberFormatKey, settings['numberFormat']);
    }
    if (settings.containsKey('currency')) {
      await prefs.setString(_currencyKey, settings['currency']);
    }
    if (settings.containsKey('accentColor')) {
      await prefs.setInt(_accentColorKey, settings['accentColor']);
    }
    if (settings.containsKey('syncWithBackend')) {
      await prefs.setBool(_syncWithBackendKey, settings['syncWithBackend']);
    }
    if (settings.containsKey('dockEnabled')) {
      await prefs.setBool(_dockEnabledKey, settings['dockEnabled']);
    }
  }

  // Sync settings with backend
  static Future<Map<String, dynamic>?> syncWithBackend({
    String? theme,
    String? textSize,
    String? language,
    String? numberFormat,
    String? currency,
    Color? accentColor,
    bool uploadToBackend = true,
  }) async {
    try {
      if (!ApiService.isLoggedIn) {
        //print('Not logged in - using local settings only');
        return await loadLocalSettings();
      }

      if (uploadToBackend) {
        // Send settings to backend
        final updateData = <String, dynamic>{};
        if (theme != null) updateData['theme'] = theme;
        if (textSize != null) updateData['textSize'] = textSize;
        if (language != null) updateData['language'] = language;
        if (numberFormat != null) updateData['numberFormat'] = numberFormat;
        if (currency != null) updateData['currency'] = currency;
        if (accentColor != null) {
          updateData['accentColor'] = accentColor.value.toString();
        }

        if (updateData.isNotEmpty) {
          await ApiService.updateUserSettings(updateData);

          // Save backend settings locally as well
          await saveLocalSettings(updateData);
          //print(' Settings successfully synced with backend');
          return updateData;
        }
      } else {
        // Load settings from backend
        final backendSettings = await ApiService.getUserSettings();
        if (backendSettings['settings'] != null) {
          final settings = backendSettings['settings'];

          // Convert backend settings to local format
          final localSettings = <String, dynamic>{};
          if (settings['theme'] != null) {
            localSettings['theme'] = settings['theme'];
          }
          if (settings['text_size'] != null) {
            localSettings['textSize'] = settings['text_size'];
          }
          if (settings['language'] != null) {
            localSettings['language'] = settings['language'];
          }
          if (settings['number_format'] != null) {
            localSettings['numberFormat'] = settings['number_format'];
          }
          if (settings['currency'] != null) {
            localSettings['currency'] = settings['currency'];
          }
          if (settings['accent_color'] != null) {
            try {
              localSettings['accentColor'] = int.parse(
                settings['accent_color'],
              );
            } catch (e) {
              localSettings['accentColor'] = const Color(0xFF8E8E93).value;
            }
          }

          // Save backend settings locally
          await saveLocalSettings(localSettings);
          //print(' Settings loaded from backend');
          return localSettings;
        }
      }
    } catch (e) {
      //print(' Error during backend synchronization: $e');
      // Use local settings on errors
      return await loadLocalSettings();
    }

    // Fallback: load local settings
    return await loadLocalSettings();
  }

  // Update all settings
  static Future<Map<String, dynamic>?> updateAllSettings({
    String? theme,
    String? textSize,
    String? language,
    String? numberFormat,
    String? currency,
    Color? accentColor,
  }) async {
    try {
      // Update local settings
      final localSettings = await loadLocalSettings();

      if (theme != null) localSettings['theme'] = theme;
      if (textSize != null) localSettings['textSize'] = textSize;
      if (language != null) localSettings['language'] = language;
      if (numberFormat != null) localSettings['numberFormat'] = numberFormat;
      if (currency != null) localSettings['currency'] = currency;
      if (accentColor != null) localSettings['accentColor'] = accentColor.value;

      await saveLocalSettings(localSettings);

      // Sync with backend (if logged in)
      if (ApiService.isLoggedIn) {
        final syncSettings = localSettings['syncWithBackend'] ?? true;
        if (syncSettings) {
          await syncWithBackend(
            theme: theme,
            textSize: textSize,
            language: language,
            numberFormat: numberFormat,
            currency: currency,
            accentColor: accentColor,
            uploadToBackend: true,
          );
        }
      }

      return localSettings;
    } catch (e) {
      //print(' Error updating settings: $e');
      return null;
    }
  }

  // Load settings on app start
  static Future<Map<String, dynamic>> initializeSettings() async {
    try {
      // Don't load tokens here - they're loaded separately for auto-login
      
      if (ApiService.isLoggedIn) {
        // Try to load backend settings
        final backendSettings = await syncWithBackend(uploadToBackend: false);
        if (backendSettings != null) {
          return backendSettings;
        }
      }

      // Fallback: local settings
      return await loadLocalSettings();
    } catch (e) {
      //print(' Error initializing settings: $e');
      return await loadLocalSettings();
    }
  }

  // Sync settings after login
  static Future<Map<String, dynamic>?> syncAfterLogin() async {
    try {
      if (!ApiService.isLoggedIn) {
        //print(' Not logged in - skipping backend synchronization');
        return null;
      }

      // Load local settings
      final localSettings = await loadLocalSettings();

      try {
        // Load backend settings (with timeout)
        final backendSettings = await syncWithBackend(uploadToBackend: false);

        if (backendSettings != null) {
          // Check if local settings have newer changes
          // For now: Backend settings take precedence
          //print(' Backend settings loaded successfully');
          return backendSettings;
        } else {
          // Upload local settings to backend
          //print('💡 Local settings uploaded to backend');
          await syncWithBackend(
            theme: localSettings['theme'],
            textSize: localSettings['textSize'],
            language: localSettings['language'],
            numberFormat: localSettings['numberFormat'],
            currency: localSettings['currency'],
            accentColor: Color(localSettings['accentColor']),
            uploadToBackend: true,
          );
          return localSettings;
        }
      } catch (e) {
        // Use local settings on backend errors
        //print('⚠️ Backend synchronization failed, using local settings: $e');
        return localSettings;
      }
    } catch (e) {
      //print(' Error during backend synchronization: $e');
      return await loadLocalSettings();
    }
  }

  // Create settings backup
  static Future<String> exportSettings() async {
    final settings = await loadLocalSettings();
    return '''
{
  "darkMode": ${settings['darkMode']},
  "language": "${settings['language']}",
  "numberFormat": "${settings['numberFormat']}",
  "accentColor": ${settings['accentColor']},
  "exportDate": "${DateTime.now().toIso8601String()}"
}
    ''';
  }

  // Restore settings from backup
  static Future<bool> importSettings(String settingsJson) async {
    try {
      final settings = Map<String, dynamic>.from(
        // JSON parsing would happen here
        {
          'darkMode': false,
          'language': 'de',
          'numberFormat': 'de',
          'accentColor': const Color(0xFF8E8E93).value,
        },
      );

      await saveLocalSettings(settings);

      // Sync with backend
      if (ApiService.isLoggedIn) {
        await syncWithBackend(
          theme: settings['theme'],
          textSize: settings['textSize'],
          language: settings['language'],
          numberFormat: settings['numberFormat'],
          accentColor: Color(settings['accentColor']),
          uploadToBackend: true,
        );
      }

      return true;
    } catch (e) {
      //print(' Error importing settings: $e');
      return false;
    }
  }

  // Reset all settings to defaults
  static Future<Map<String, dynamic>> resetToDefaults() async {
    final defaultSettings = {
      'theme': 'system',
      'textSize': 'system',
      'language': 'system',
      'numberFormat': 'system',
      'currency': 'system',
      'accentColor': const Color(0xFF8E8E93).value,
      'syncWithBackend': true,
      'dockEnabled': true, // Default: Dock enabled
    };

    await saveLocalSettings(defaultSettings);

    // Sync with backend
    if (ApiService.isLoggedIn) {
      await syncWithBackend(
        theme: defaultSettings['theme'] as String,
        textSize: defaultSettings['textSize'] as String,
        language: defaultSettings['language'] as String,
        numberFormat: defaultSettings['numberFormat'] as String,
        currency: defaultSettings['currency'] as String,
        accentColor: Color(defaultSettings['accentColor'] as int),
        uploadToBackend: true,
      );
    }

    return defaultSettings;
  }

  // Utility methods

  // Format number according to locale setting
  static String formatNumber(double number, String? format) {
    setNumberFormatStyleIndex(format == 'de' ? 1 : 0);
    return formatNumberUS(number);
  }

  // Get text scale factor based on text size setting
  static double getTextScaleFactor(String? textSize) {
    switch (textSize) {
      case 'system':
        return WidgetsBinding.instance.platformDispatcher.textScaleFactor;
      case 'small':
        return 0.85;
      case 'large':
        return 1.15;
      case 'medium':
      default:
        return 1.0;
    }
  }

  // Get localized strings – delegates to AppLocalizations translation maps
  static Map<String, String> getLocalizedStrings(String? language) {
    final lang = resolvedUiLanguageCode(language);
    final translations = _settingsTranslations[lang] ?? _settingsTranslations['en']!;
    return Map<String, String>.from(translations);
  }

  static const Map<String, Map<String, String>> _settingsTranslations = {
    'en': {
      'appearance': 'Appearance',
      'localization': 'Localization',
      'theme': 'Theme',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'theme_system': 'Phone Settings',
      'text_size': 'Text Size',
      'text_size_small': 'Small',
      'text_size_medium': 'Medium',
      'text_size_large': 'Large',
      'language': 'Language',
      'language_en': 'English',
      'language_de': 'German',
      'language_es': 'Spanish',
      'language_fr': 'French',
      'language_ru': 'Russian',
      'language_it': 'Italian',
      'language_pt': 'Portuguese',
      'number_format': 'Number Format',
      'number_format_en': 'English (1,234.56)',
      'number_format_de': 'German (1.234,56)',
      'currency': 'Currency',
      'currency_usd': 'US Dollar (\$)',
      'currency_eur': 'Euro (€)',
      'currency_rub': 'Russian Ruble (₽)',
      'currency_mxn': 'Mexican Peso (MX\$)',
      'currency_cad': 'Canadian Dollar (CA\$)',
      'currency_gbp': 'British Pound (£)',
      'currency_chf': 'Swiss Franc (CHF)',
      'settings_updated': 'Settings updated successfully',
      'settings_error': 'Failed to update settings',
    },
    'de': {
      'appearance': 'Darstellung',
      'localization': 'Lokalisierung',
      'theme': 'Design',
      'theme_light': 'Hell',
      'theme_dark': 'Dunkel',
      'theme_system': 'Systemeinstellungen',
      'text_size': 'Textgröße',
      'text_size_small': 'Klein',
      'text_size_medium': 'Standard',
      'text_size_large': 'Groß',
      'language': 'Sprache',
      'language_en': 'Englisch',
      'language_de': 'Deutsch',
      'language_es': 'Spanisch',
      'language_fr': 'Französisch',
      'language_ru': 'Russisch',
      'language_it': 'Italienisch',
      'language_pt': 'Portugiesisch',
      'number_format': 'Zahlenformat',
      'number_format_en': 'Englisch (1,234.56)',
      'number_format_de': 'Deutsch (1.234,56)',
      'currency': 'Währung',
      'currency_usd': 'US Dollar (\$)',
      'currency_eur': 'Euro (€)',
      'currency_rub': 'Russischer Rubel (₽)',
      'currency_mxn': 'Mexikanischer Peso (MX\$)',
      'currency_cad': 'Kanadischer Dollar (CA\$)',
      'currency_gbp': 'Britisches Pfund (£)',
      'currency_chf': 'Schweizer Franken (CHF)',
      'settings_updated': 'Einstellungen erfolgreich aktualisiert',
      'settings_error': 'Fehler beim Aktualisieren der Einstellungen',
    },
    'es': {
      'appearance': 'Apariencia',
      'localization': 'Localización',
      'theme': 'Tema',
      'theme_light': 'Claro',
      'theme_dark': 'Oscuro',
      'theme_system': 'Ajustes del teléfono',
      'text_size': 'Tamaño de texto',
      'text_size_small': 'Pequeño',
      'text_size_medium': 'Mediano',
      'text_size_large': 'Grande',
      'language': 'Idioma',
      'language_en': 'Inglés',
      'language_de': 'Alemán',
      'language_es': 'Español',
      'language_fr': 'Francés',
      'language_ru': 'Ruso',
      'language_it': 'Italiano',
      'language_pt': 'Portugués',
      'number_format': 'Formato numérico',
      'number_format_en': 'Inglés (1,234.56)',
      'number_format_de': 'Alemán (1.234,56)',
      'currency': 'Moneda',
      'currency_usd': 'Dólar estadounidense (\$)',
      'currency_eur': 'Euro (€)',
      'currency_rub': 'Rublo ruso (₽)',
      'currency_mxn': 'Peso mexicano (MX\$)',
      'currency_cad': 'Dólar canadiense (CA\$)',
      'currency_gbp': 'Libra esterlina (£)',
      'currency_chf': 'Franco suizo (CHF)',
      'settings_updated': 'Ajustes actualizados correctamente',
      'settings_error': 'Error al actualizar los ajustes',
    },
    'fr': {
      'appearance': 'Apparence',
      'localization': 'Localisation',
      'theme': 'Thème',
      'theme_light': 'Clair',
      'theme_dark': 'Sombre',
      'theme_system': 'Paramètres du téléphone',
      'text_size': 'Taille du texte',
      'text_size_small': 'Petit',
      'text_size_medium': 'Moyen',
      'text_size_large': 'Grand',
      'language': 'Langue',
      'language_en': 'Anglais',
      'language_de': 'Allemand',
      'language_es': 'Espagnol',
      'language_fr': 'Français',
      'language_ru': 'Russe',
      'language_it': 'Italien',
      'language_pt': 'Portugais',
      'number_format': 'Format numérique',
      'number_format_en': 'Anglais (1,234.56)',
      'number_format_de': 'Allemand (1.234,56)',
      'currency': 'Devise',
      'currency_usd': 'Dollar américain (\$)',
      'currency_eur': 'Euro (€)',
      'currency_rub': 'Rouble russe (₽)',
      'currency_mxn': 'Peso mexicain (MX\$)',
      'currency_cad': 'Dollar canadien (CA\$)',
      'currency_gbp': 'Livre sterling (£)',
      'currency_chf': 'Franc suisse (CHF)',
      'settings_updated': 'Paramètres mis à jour avec succès',
      'settings_error': 'Échec de la mise à jour des paramètres',
    },
    'ru': {
      'appearance': 'Внешний вид',
      'localization': 'Локализация',
      'theme': 'Тема',
      'theme_light': 'Светлая',
      'theme_dark': 'Тёмная',
      'theme_system': 'Настройки телефона',
      'text_size': 'Размер текста',
      'text_size_small': 'Маленький',
      'text_size_medium': 'Средний',
      'text_size_large': 'Большой',
      'language': 'Язык',
      'language_en': 'Английский',
      'language_de': 'Немецкий',
      'language_es': 'Испанский',
      'language_fr': 'Французский',
      'language_ru': 'Русский',
      'language_it': 'Итальянский',
      'language_pt': 'Португальский',
      'number_format': 'Формат чисел',
      'number_format_en': 'Английский (1,234.56)',
      'number_format_de': 'Немецкий (1.234,56)',
      'currency': 'Валюта',
      'currency_usd': 'Доллар США (\$)',
      'currency_eur': 'Евро (€)',
      'currency_rub': 'Российский рубль (₽)',
      'currency_mxn': 'Мексиканское песо (MX\$)',
      'currency_cad': 'Канадский доллар (CA\$)',
      'currency_gbp': 'Британский фунт (£)',
      'currency_chf': 'Швейцарский франк (CHF)',
      'settings_updated': 'Настройки успешно обновлены',
      'settings_error': 'Ошибка обновления настроек',
    },
    'it': {
      'appearance': 'Aspetto',
      'localization': 'Localizzazione',
      'theme': 'Tema',
      'theme_light': 'Chiaro',
      'theme_dark': 'Scuro',
      'theme_system': 'Impostazioni telefono',
      'text_size': 'Dimensione testo',
      'text_size_small': 'Piccolo',
      'text_size_medium': 'Medio',
      'text_size_large': 'Grande',
      'language': 'Lingua',
      'language_en': 'Inglese',
      'language_de': 'Tedesco',
      'language_es': 'Spagnolo',
      'language_fr': 'Francese',
      'language_ru': 'Russo',
      'language_it': 'Italiano',
      'language_pt': 'Portoghese',
      'number_format': 'Formato numerico',
      'number_format_en': 'Inglese (1,234.56)',
      'number_format_de': 'Tedesco (1.234,56)',
      'currency': 'Valuta',
      'currency_usd': 'Dollaro USA (\$)',
      'currency_eur': 'Euro (€)',
      'currency_rub': 'Rublo russo (₽)',
      'currency_mxn': 'Peso messicano (MX\$)',
      'currency_cad': 'Dollaro canadese (CA\$)',
      'currency_gbp': 'Sterlina britannica (£)',
      'currency_chf': 'Franco svizzero (CHF)',
      'settings_updated': 'Impostazioni aggiornate con successo',
      'settings_error': 'Errore nell\'aggiornamento delle impostazioni',
    },
    'pt': {
      'appearance': 'Aparência',
      'localization': 'Localização',
      'theme': 'Tema',
      'theme_light': 'Claro',
      'theme_dark': 'Escuro',
      'theme_system': 'Definições do telefone',
      'text_size': 'Tamanho do texto',
      'text_size_small': 'Pequeno',
      'text_size_medium': 'Médio',
      'text_size_large': 'Grande',
      'language': 'Idioma',
      'language_en': 'Inglês',
      'language_de': 'Alemão',
      'language_es': 'Espanhol',
      'language_fr': 'Francês',
      'language_ru': 'Russo',
      'language_it': 'Italiano',
      'language_pt': 'Português',
      'number_format': 'Formato numérico',
      'number_format_en': 'Inglês (1,234.56)',
      'number_format_de': 'Alemão (1.234,56)',
      'currency': 'Moeda',
      'currency_usd': 'Dólar americano (\$)',
      'currency_eur': 'Euro (€)',
      'currency_rub': 'Rublo russo (₽)',
      'currency_mxn': 'Peso mexicano (MX\$)',
      'currency_cad': 'Dólar canadiano (CA\$)',
      'currency_gbp': 'Libra esterlina (£)',
      'currency_chf': 'Franco suíço (CHF)',
      'settings_updated': 'Definições atualizadas com sucesso',
      'settings_error': 'Erro ao atualizar as definições',
    },
  };
}
