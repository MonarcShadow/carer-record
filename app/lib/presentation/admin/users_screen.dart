import 'package:flutter/material.dart';
import '../../core/theme/theme.dart';
import '../../data/remote/users_service.dart';
import 'user_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final UsersService _service = UsersService();
  List<UserModel> _users    = [];
  List<UserModel> _filtered = [];
  String _selectedRole      = 'todos';
  bool _loading             = true;
  String? _error;

  static const _roles = ['todos', 'admin', 'doctor', 'nurse', 'tech'];

  static const _roleLabels = {
    'todos':  'Todos',
    'admin':  'Administrador',
    'doctor': 'Médico',
    'nurse':  'Enfermería',
    'tech':   'Equipo Ampliado',
  };

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() { _loading = true; _error = null; });
    try {
      final users = await _service.getUsers();
      setState(() {
        _users  = users;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _applyFilter() {
    setState(() {
      _filtered = _selectedRole == 'todos'
          ? List.from(_users)
          : _users.where((u) => u.role == _selectedRole).toList();
    });
  }

  String _roleLabel(String role) => _roleLabels[role] ?? role;

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':  return Colors.purple;
      case 'doctor': return Colors.blue;
      case 'nurse':  return Colors.teal;
      case 'tech':   return Colors.orange;
      default:       return Colors.grey;
    }
  }

  Future<void> _confirmDelete(UserModel user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar a ${user.name}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteUser(user.id);
      _loadUsers();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Gestionar usuarios'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const UserFormScreen()));
          _loadUsers();
        },
        child: const Icon(Icons.person_add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : Column(
                  children: [
                    // Filtro por rol
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _roles.length,
                        itemBuilder: (_, i) {
                          final role    = _roles[i];
                          final selected = role == _selectedRole;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(_roleLabel(role)),
                              selected: selected,
                              selectedColor: AppTheme.primary,
                              labelStyle: TextStyle(
                                color: selected ? Colors.white : AppTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                              onSelected: (_) {
                                setState(() => _selectedRole = role);
                                _applyFilter();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    // Lista
                    Expanded(
                      child: _filtered.isEmpty
                          ? const Center(child: Text('No hay usuarios en este rol'))
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final u = _filtered[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: _roleColor(u.role).withValues(alpha: 0.15),
                                      child: Text(
                                        u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                            color: _roleColor(u.role),
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(u.name,
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(u.email, style: const TextStyle(fontSize: 12)),
                                        Text('RUT: ${u.rut}',
                                            style: const TextStyle(fontSize: 12)),
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _roleColor(u.role).withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            _roleLabel(u.role),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: _roleColor(u.role),
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit,
                                              color: AppTheme.primary),
                                          onPressed: () async {
                                            await Navigator.push(context,
                                              MaterialPageRoute(
                                                builder: (_) => UserFormScreen(user: u)));
                                            _loadUsers();
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete,
                                              color: Colors.red),
                                          onPressed: () => _confirmDelete(u),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}