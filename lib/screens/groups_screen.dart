import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../widgets/dividi_bits.dart';
import 'group_detail_screen.dart';
import 'login_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _apiClient = ApiClient();
  late Future<List<dynamic>> _groupsFuture;
  bool _creatingGroup = false;

  @override
  void initState() {
    super.initState();
    _groupsFuture = _apiClient.getGroups();
  }

  Future<void> _refresh() async {
    setState(() => _groupsFuture = _apiClient.getGroups());
  }

  Future<void> _logout() async {
    await _apiClient.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _createGroup() async {
    // evita crear el grupo por duplicado si el usuario toca varias veces
    // mientras la petición sigue en curso (p.ej. servidor despertando)
    if (_creatingGroup) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nuevo grupo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Nombre del grupo'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    setState(() => _creatingGroup = true);
    try {
      await _apiClient.createGroup(name: name);
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _creatingGroup = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis grupos'),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<dynamic>>(
          future: _groupsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  EstadoVacio(
                    titulo: 'No se pudieron cargar tus grupos',
                    detalle: '${snapshot.error}',
                  ),
                ],
              );
            }
            final groups = snapshot.data ?? [];
            if (groups.isEmpty) {
              return ListView(
                children: const [
                  EstadoVacio(
                    titulo: 'Todavía no tienes ningún grupo.',
                    detalle:
                        'Crea el primero y empieza a repartir gastos sin líos.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _GrupoCard(
                  nombre: group['name'],
                  divisa: group['default_currency'],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupDetailScreen(
                        groupId: group['id'],
                        groupName: group['name'],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _creatingGroup ? null : _createGroup,
        icon: _creatingGroup
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : const Icon(Icons.add_rounded),
        label: const Text('Nuevo grupo'),
      ),
    );
  }
}

/// Tarjeta de grupo: avatar con inicial (color estable por nombre),
/// nombre en Gabarito y la divisa como dato secundario.
class _GrupoCard extends StatelessWidget {
  final String nombre;
  final String divisa;
  final VoidCallback onTap;

  const _GrupoCard({
    required this.nombre,
    required this.divisa,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              PersonaAvatar(nombre: nombre, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: tema.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text('Divisa: $divisa', style: tema.textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: tema.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
