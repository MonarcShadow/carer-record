import 'package:flutter/material.dart';
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

  Color _roleColor(String role, BuildContext context) {
    // Es buena idea adaptar ligeramente los colores según el brillo
    // pero si quieres mantener los mismos tonos, al menos aseguramos
    // que se usen de forma que destaquen.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    switch (role) {
      case 'admin':  return isDark ? Colors.purpleAccent : Colors.purple;
      case 'doctor': return isDark ? Colors.lightBlue : Colors.blue;
      case 'nurse':  return isDark ? Colors.tealAccent : Colors.teal;
      case 'tech':   return isDark ? Colors.orangeAccent : Colors.orange;
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
            // Usamos color de error del tema
            child: Text('Eliminar', style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
        SnackBar(
          content: Text(e.toString()), 
          backgroundColor: Theme.of(context).colorScheme.error
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      // Se eliminó backgroundColor fijo
      appBar: AppBar(
        title: const Text('Gestionar usuarios'),
        // Se eliminaron backgroundColor, foregroundColor y elevation fijos
      ),
      floatingActionButton: FloatingActionButton(
        // Heredará colorScheme.primary del tema automáticamente
        onPressed: () async {
          await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const UserFormScreen()));
          _loadUsers();
        },
        child: const Icon(Icons.person_add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator()) // Color dinámico
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)))
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
                              // El ChoiceChip ya maneja bien los colores si no los forzamos
                              // pero podemos asegurarnos del texto
                              labelStyle: TextStyle(
                                color: selected 
                                    ? theme.colorScheme.onPrimary 
                                    : theme.textTheme.bodyMedium?.color,
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
                          ? Center(
                              child: Text(
                                'No hay usuarios en este rol',
                                style: theme.textTheme.bodyLarge,
                              )
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                              itemCount: _filtered.length,
                              itemBuilder: (_, i) {
                                final u = _filtered[i];
                                final roleColor = _roleColor(u.role, context);
                                
                                return Card(
                                  // El color de la Card vendrá del CardTheme en theme.dart
                                  margin: const EdgeInsets.only(bottom: 10),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    leading: CircleAvatar(
                                      backgroundColor: roleColor.withValues(alpha: 0.15),
                                      child: Text(
                                        u.name.isNotEmpty ? u.name[0].toUpperCase() : '?',
                                        style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    title: Text(
                                      u.name,
                                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(u.email, style: theme.textTheme.bodySmall),
                                        Text('RUT: ${u.rut}', style: theme.textTheme.bodySmall),
                                        Container(
                                          margin: const EdgeInsets.only(top: 4),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: roleColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            _roleLabel(u.role),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: roleColor,
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: Icon(Icons.edit, color: theme.colorScheme.primary),
                                          onPressed: () async {
                                            await Navigator.push(context,
                                              MaterialPageRoute(
                                                builder: (_) => UserFormScreen(user: u)));
                                            _loadUsers();
                                          },
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.delete, color: theme.colorScheme.error),
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