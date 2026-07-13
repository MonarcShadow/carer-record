import 'package:shared_preferences/shared_preferences.dart';

class AuthPreferences {
  static const _keyBiometric = 'biometric_enabled';
  static const _keyDarkMode = 'dark_mode';
  static const _keyToken = 'auth_token';
  static const _keyUserName = 'user_name';
  static const _keyUserRole = 'user_role';
  static const _keyUserEmail = 'user_email';

  static Future<void> saveSession({
    required String token,
    required String userName,
    required String userRole,
    required String userEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setString(_keyUserName, userName);
    await prefs.setString(_keyUserRole, userRole);
    await prefs.setString(_keyUserEmail, userEmail);
  }

  static Future<Map<String, String?>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token':     prefs.getString(_keyToken),
      'userName':  prefs.getString(_keyUserName),
      'userRole':  prefs.getString(_keyUserRole),
      'userEmail': prefs.getString(_keyUserEmail),
    };
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserName);
    await prefs.remove(_keyUserRole);
    await prefs.remove(_keyUserEmail);
  }

  static Future<bool> getBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBiometric) ?? false;
  }

  static Future<void> setBiometric(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBiometric, value);
  }

  static Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? false;
  }

  static Future<void> setDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, value);
  }
}