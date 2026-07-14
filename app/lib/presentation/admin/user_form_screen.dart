import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../data/remote/users_service.dart';

class UserFormScreen extends StatefulWidget {
  final UserModel? user;
  const UserFormScreen({super.key, this.user});

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _nameCtrl      = TextEditingController();
  final _emailCtrl     = TextEditingController();
  final _rutCtrl       = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final UsersService _service = UsersService();

  String _selectedRole    = 'doctor';
  bool _obscurePassword   = true;
  bool _isLoading         = false;
  bool get _isEditing     => widget.user != null;

  static const _roles = ['admin', 'doctor', 'nurse', 'tech'];
  static const _roleLabels = {
    'admin':  'Administrador',
    'doctor': 'Médico',
    'nurse':  'Enfermería',
    'tech':   'Equipo Ampliado',
  };

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text  = widget.user!.name;
      _emailCtrl.text = widget.user!.email;
      _rutCtrl.text   = widget.user!.rut;
      _selectedRole   = widget.user!.role;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _rutCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      if (_isEditing) {
        final fields = <String, dynamic>{
          'name':  _nameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'rut':   _rutCtrl.text.trim(),
          'role':  _selectedRole,
        };
        if (_passwordCtrl.text.isNotEmpty) {
          fields['password'] = _passwordCtrl.text;
        }
        await _service.updateUser(widget.user!.id, fields);
      } else {
        await _service.createUser(
          name:     _nameCtrl.text.trim(),
          email:    _emailCtrl.text.trim(),
          rut:      _rutCtrl.text.trim(),
          role:     _selectedRole,
          password: _passwordCtrl.text,
        );
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar usuario' : 'Agregar usuario'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Ingresa el nombre' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Correo institucional',
                  prefixIcon: Icon(Icons.email),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Ingresa el correo' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _rutCtrl,
                decoration: const InputDecoration(
                  labelText: 'RUT',
                  hintText: '12.345.678-9',
                  prefixIcon: Icon(Icons.badge),
                ),
                validator: (v) => v == null || v.isEmpty ? 'Ingresa el RUT' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedRole,
                decoration: const InputDecoration(
                  labelText: 'Rol',
                  prefixIcon: Icon(Icons.work),
                ),
                items: _roles.map((role) => DropdownMenuItem(
                  value: role,
                  child: Text(_roleLabels[role] ?? role),
                )).toList(),
                onChanged: (v) => setState(() => _selectedRole = v!),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: _isEditing
                      ? 'Nueva contraseña (dejar vacío para no cambiar)'
                      : 'Contraseña',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (v) {
                  if (!_isEditing && (v == null || v.isEmpty)) {
                    return 'Ingresa una contraseña';
                  }
                  if (v != null && v.isNotEmpty && v.length < 6) {
                    return 'Mínimo 6 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : ElevatedButton(
                      onPressed: _submit,
                      child: Text(_isEditing ? 'Guardar cambios' : 'Agregar usuario'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}