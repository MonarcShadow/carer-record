import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';
import 'dto/auth_dto.dart';

class AuthService {
  Future<LoginResponseDto> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('${AppConfig.baseUrl}/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return LoginResponseDto.fromJson(jsonDecode(response.body));
    } else if (response.statusCode == 401) {
      throw Exception('Correo o contraseña incorrectos');
    } else {
      throw Exception('Error al conectar con el servidor');
    }
  }
}