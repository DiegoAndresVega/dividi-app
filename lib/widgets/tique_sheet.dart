import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';

/// Hoja del tique (M8): ver, hacer/elegir la foto o quitarla.
/// Devuelve `true` si algo cambió (para que el llamante refresque).
Future<bool> mostrarTiqueSheet(
  BuildContext context, {
  required ApiClient apiClient,
  required String groupId,
  required Map<String, dynamic> gasto,
}) async {
  final tiene = gasto['receipt_image_url'] != null;
  final accion = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.receipt_long_rounded),
            title: Text(gasto['description']),
            subtitle: const Text('Foto del tique'),
          ),
          const Divider(height: 1),
          if (tiene)
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Ver tique'),
              onTap: () => Navigator.of(context).pop('ver'),
            ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(tiene ? 'Repetir la foto' : 'Hacer una foto'),
            onTap: () => Navigator.of(context).pop('camara'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Elegir de la galería'),
            onTap: () => Navigator.of(context).pop('galeria'),
          ),
          if (tiene)
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Quitar el tique'),
              onTap: () => Navigator.of(context).pop('quitar'),
            ),
        ],
      ),
    ),
  );
  if (accion == null || !context.mounted) return false;

  Future<bool> subir(ImageSource origen) async {
    final imagen = await ImagePicker().pickImage(
      source: origen,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (imagen == null) return false;
    await apiClient.uploadReceipt(
      groupId: groupId,
      expenseId: gasto['id'],
      filePath: imagen.path,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tique guardado.')));
    }
    return true;
  }

  try {
    switch (accion) {
      case 'ver':
        final headers = await apiClient.authHeaders();
        if (!context.mounted) return false;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _TiqueViewer(
              titulo: gasto['description'],
              url: '${ApiClient.baseUrl}${gasto['receipt_image_url']}',
              headers: headers,
            ),
          ),
        );
        return false;
      case 'camara':
        return await subir(ImageSource.camera);
      case 'galeria':
        return await subir(ImageSource.gallery);
      case 'quitar':
        await apiClient.deleteReceipt(groupId: groupId, expenseId: gasto['id']);
        return true;
      default:
        return false;
    }
  } on ApiException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return false;
  }
}

class _TiqueViewer extends StatelessWidget {
  final String titulo;
  final String url;
  final Map<String, String> headers;

  const _TiqueViewer({
    required this.titulo,
    required this.url,
    required this.headers,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tique · $titulo')),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.network(
            url,
            headers: headers,
            loadingBuilder: (context, hijo, progreso) => progreso == null
                ? hijo
                : const Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
            errorBuilder: (context, _, _) => const Padding(
              padding: EdgeInsets.all(40),
              child: Text('No se pudo cargar el tique.'),
            ),
          ),
        ),
      ),
    );
  }
}
