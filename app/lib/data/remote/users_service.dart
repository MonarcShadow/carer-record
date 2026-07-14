import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/config.dart';

class UserModel {
  final String id;
  final String name;
  final String email;
  final String rut;
  final String role;
  final bool active;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.rut,
    required this.role,
    required this.active,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id:     json['id'],
        name:   json['name'],
        email:  json['email'],
        rut:    json['rut'],
        role:   json['role'],
        active: json['active'],
      );
}

class UsersService {
  final String _base = '${AppConfig.baseUrl}/api/v1/users';

  Future<List<UserModel>> getUsers() async {
    final res = await http.get(Uri.parse('$_base/'));
    if (res.statusCode == 200) {
      final List data = jsonDecode(res.body);
      return data.map((e) => UserModel.fromJson(e)).toList();
    }
    throw Exception('Error al cargar usuarios');
  }

  Future<UserModel> createUser({
    required String name,
    required String email,
    required String rut,
    required String role,
    required String password,
  }) async {
    final res = await http.post(
      Uri.parse('$_base/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name, 'email': email,
        'rut': rut, 'role': role, 'password': password,
      }),
    );
    if (res.statusCode == 201) return UserModel.fromJson(jsonDecode(res.body));
    final detail = jsonDecode(res.body)['detail'] ?? 'Error al crear usuario';
    throw Exception(detail);
  }

  Future<UserModel> updateUser(String id, Map<String, dynamic> fields) async {
    final res = await http.put(
      Uri.parse('$_base/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(fields),
    );
    if (res.statusCode == 200) return UserModel.fromJson(jsonDecode(res.body));
    final detail = jsonDecode(res.body)['detail'] ?? 'Error al actualizar';
    throw Exception(detail);
  }

  Future<void> deleteUser(String id) async {
    final res = await http.delete(Uri.parse('$_base/$id'));
    if (res.statusCode != 204) throw Exception('Error al eliminar usuario');
  }
}