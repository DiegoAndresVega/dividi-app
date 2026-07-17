import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';

/// Apuntar o editar un gasto personal (M11): descripción, importe y
/// categoría. Nadie más lo ve; no toca ningún grupo.
class PersonalExpenseFormScreen extends StatefulWidget {
  /// Si llega un gasto, la pantalla edita; si no, crea.
  final Map<String, dynamic>? gasto;

  const PersonalExpenseFormScreen({super.key, this.gasto});

  @override
  State<PersonalExpenseFormScreen> createState() =>
      _PersonalExpenseFormScreenState();
}

class _PersonalExpenseFormScreenState extends State<PersonalExpenseFormScreen> {
  static const _categorias = [
    'comida', 'transporte', 'alojamiento', 'ocio', 'otros',
  ];

  final _apiClient = ApiClient();
  late final TextEditingController _descripcion;
  late final TextEditingController _importe;
  late String _categoria;
  bool _enviando = false;

  bool get _esEdicion => widget.gasto != null;

  @override
  void initState() {
    super.initState();
    _descripcion =
        TextEditingController(text: widget.gasto?['description'] ?? '');
    final importe = widget.gasto?['amount'];
    _importe = TextEditingController(
      text: importe == null
          ? ''
          : (double.tryParse(importe.toString()) ?? 0)
              .toStringAsFixed(2)
              .replaceAll('.00', '')
              .replaceAll('.', ','),
    );
    _categoria = widget.gasto?['category'] ?? 'otros';
  }

  @override
  void dispose() {
    _descripcion.dispose();
    _importe.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final descripcion = _descripcion.text.trim();
    final importe =
        double.tryParse(_importe.text.trim().replaceAll(',', '.'));
    if (descripcion.isEmpty || importe == null || importe <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ponle descripción y un importe mayor que cero.')));
      return;
    }

    setState(() => _enviando = true);
    try {
      if (_esEdicion) {
        await _apiClient.updatePersonalExpense(
          expenseId: widget.gasto!['id'],
          description: descripcion,
          amount: importe.toStringAsFixed(2),
          category: _categoria,
        );
      } else {
        await _apiClient.createPersonalExpense(
          description: descripcion,
          amount: importe.toStringAsFixed(2),
          category: _categoria,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _borrar() async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar este gasto?'),
        content: Text('«${widget.gasto!['description']}» desaparecerá de tu mes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (seguro != true) return;
    try {
      await _apiClient.deletePersonalExpense(widget.gasto!['id']);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tonos = DividiTones.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_esEdicion ? 'Editar gasto personal' : 'Gasto personal'),
        actions: [
          if (_esEdicion)
            IconButton(
              onPressed: _borrar,
              tooltip: 'Borrar',
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            TextField(
              controller: _descripcion,
              textCapitalization: TextCapitalization.sentences,
              autofocus: !_esEdicion,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Gimnasio, café, capricho…',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _importe,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Importe (€)'),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final categoria in _categorias)
                  ChoiceChip(
                    avatar: Icon(
                      tonos.categoria(categoria).icono,
                      size: 17,
                      color: _categoria == categoria
                          ? tonos.categoria(categoria).color
                          : null,
                    ),
                    label: Text(tonos.categoria(categoria).etiqueta),
                    selected: _categoria == categoria,
                    onSelected: (_) => setState(() => _categoria = categoria),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: _enviando ? null : _guardar,
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Text(_esEdicion ? 'Guardar cambios' : 'Apuntar gasto'),
            ),
          ],
        ),
      ),
    );
  }
}
