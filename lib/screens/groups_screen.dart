import 'package:flutter/material.dart';

import '../services/api_client.dart';
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
          IconButton(onPressed: _logout, icon: const Icon(Icons.logout)),
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
                  const SizedBox(height: 100),
                  Center(child: Text('Error: ${snapshot.error}')),
                ],
              );
            }
            final groups = snapshot.data ?? [];
            if (groups.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 100),
                  Center(child: Text('Todavía no tienes ningún grupo.')),
                ],
              );
            }
            return ListView.builder(
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return ListTile(
                  title: Text(group['name']),
                  subtitle: Text(group['default_currency']),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _creatingGroup ? null : _createGroup,
        child: _creatingGroup
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add),
      ),
    );
  }
}
