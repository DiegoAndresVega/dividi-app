import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Gastos recurrentes del grupo (M7): el alquiler se apunta solo.
/// Cada regla crea su gasto el día del mes elegido, con el reparto
/// vigente ese día; aquí se crean, pausan y borran.
class RecurringScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  final List<dynamic> miembros;

  const RecurringScreen({
    super.key,
    required this.groupId,
    required this.groupName,
    required this.miembros,
  });

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  final _apiClient = ApiClient();
  late Future<List<dynamic>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _apiClient.getRecurring(widget.groupId);
  }

  Future<void> _refresh() async {
    final futuro = _apiClient.getRecurring(widget.groupId);
    setState(() {
      _futuro = futuro;
    });
    await futuro;
  }

  Future<void> _nuevaRegla() async {
    final creada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _RecurringFormScreen(
          groupId: widget.groupId,
          miembros: widget.miembros,
        ),
      ),
    );
    if (creada == true && mounted) await _refresh();
  }

  Future<void> _alternar(Map<String, dynamic> regla, bool activa) async {
    try {
      await _apiClient.updateRecurring(
        groupId: widget.groupId,
        ruleId: regla['id'],
        active: activa,
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _borrar(Map<String, dynamic> regla) async {
    final seguro = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Borrar esta regla?'),
        content: Text(
            '«${regla['description']}» dejará de apuntarse solo. '
            'Los gastos ya creados se quedan.'),
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
      await _apiClient.deleteRecurring(
          groupId: widget.groupId, ruleId: regla['id']);
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _nombreMiembro(String? miembroId) {
    for (final m in widget.miembros) {
      if (m['id'] == miembroId) return m['display_name'] as String;
    }
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Recurrentes · ${widget.groupName}')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<dynamic>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(children: [
                EstadoVacio(
                  titulo: 'No se pudieron cargar las reglas',
                  detalle: '${snapshot.error}',
                  onRetry: _refresh,
                ),
              ]);
            }
            final reglas = snapshot.data ?? [];
            if (reglas.isEmpty) {
              return ListView(children: const [
                EstadoVacio(
                  titulo: 'Nada se apunta solo todavía.',
                  detalle:
                      'El alquiler, la luz, la suscripción de siempre: crea '
                      'una regla y cada mes el gasto aparecerá él solito, '
                      'repartido con los porcentajes de ese día.',
                ),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
              itemCount: reglas.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final regla = reglas[index] as Map<String, dynamic>;
                final activa = regla['active'] == true;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
                    child: Row(
                      children: [
                        CategoriaInsignia(
                            categoria: regla['category'], size: 42),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                regla['description'],
                                style: tema.textTheme.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                activa
                                    ? '${formatearImporte(regla['amount'])} · '
                                        'paga ${_nombreMiembro(regla['paid_by_id'])} · '
                                        'día ${regla['day_of_month']} · '
                                        'próximo: ${mesDePeriodo(regla['next_period'])}'
                                    : '${formatearImporte(regla['amount'])} · en pausa',
                                style: tema.textTheme.bodySmall,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: activa,
                          onChanged: (valor) => _alternar(regla, valor),
                        ),
                        IconButton(
                          onPressed: () => _borrar(regla),
                          tooltip: 'Borrar regla',
                          icon: const Icon(Icons.delete_outline_rounded, size: 21),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nuevaRegla,
        icon: const Icon(Icons.event_repeat_rounded),
        label: const Text('Nueva regla'),
      ),
    );
  }
}

/// Formulario de regla recurrente: qué, cuánto, quién paga, qué día
/// y cómo se reparte (Ingresos o a partes iguales).
class _RecurringFormScreen extends StatefulWidget {
  final String groupId;
  final List<dynamic> miembros;

  const _RecurringFormScreen({required this.groupId, required this.miembros});

  @override
  State<_RecurringFormScreen> createState() => _RecurringFormScreenState();
}

class _RecurringFormScreenState extends State<_RecurringFormScreen> {
  static const _categorias = [
    'comida', 'transporte', 'alojamiento', 'ocio', 'otros',
  ];

  final _apiClient = ApiClient();
  final _descripcion = TextEditingController();
  final _importe = TextEditingController();
  String _categoria = 'alojamiento';
  String _metodo = 'percentage';
  late String _pagador = widget.miembros.first['id'] as String;
  int _dia = 1;
  bool _enviando = false;

  @override
  void dispose() {
    _descripcion.dispose();
    _importe.dispose();
    super.dispose();
  }

  Future<void> _crear() async {
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
      await _apiClient.createRecurring(
        groupId: widget.groupId,
        description: descripcion,
        amount: importe.toStringAsFixed(2),
        category: _categoria,
        paidBy: _pagador,
        splitMethod: _metodo,
        dayOfMonth: _dia,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva regla recurrente')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
          children: [
            TextField(
              controller: _descripcion,
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Descripción',
                hintText: 'Alquiler, luz, internet…',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _importe,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Importe (€)'),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final categoria in _categorias)
                  ChoiceChip(
                    label: Text(tonos.categoria(categoria).etiqueta),
                    selected: _categoria == categoria,
                    onSelected: (_) => setState(() => _categoria = categoria),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              initialValue: _pagador,
              decoration: const InputDecoration(labelText: 'Quién lo paga'),
              items: [
                for (final m in widget.miembros)
                  DropdownMenuItem(
                    value: m['id'] as String,
                    child: Text(m['display_name'] as String),
                  ),
              ],
              onChanged: (valor) => setState(() => _pagador = valor!),
            ),
            const SizedBox(height: 18),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'percentage', label: Text('Ingresos')),
                ButtonSegment(value: 'equal', label: Text('A partes iguales')),
              ],
              selected: {_metodo},
              onSelectionChanged: (valores) =>
                  setState(() => _metodo = valores.first),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text('Se apunta el día $_dia de cada mes',
                      style: tema.textTheme.titleSmall),
                ),
                DropdownButton<int>(
                  value: _dia,
                  items: [
                    for (var dia = 1; dia <= 28; dia++)
                      DropdownMenuItem(value: dia, child: Text('$dia')),
                  ],
                  onChanged: (valor) => setState(() => _dia = valor!),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'El reparto se calcula con los porcentajes del grupo vigentes '
              'ese día — partes justas, también sin acordarse.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _enviando ? null : _crear,
              child: _enviando
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Crear regla'),
            ),
          ],
        ),
      ),
    );
  }
}
