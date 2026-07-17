import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Nuevo grupo: nombre + participantes. Puedes crearlo tú solo o añadir ya a
/// invitados sin cuenta (solo con su nombre: "Compi", "Piso 2"...). Los pesos
/// son la parte de los ingresos de cada uno y deben sumar 100 — al añadir o
/// quitar gente se reparten a partes iguales, y luego los ajustas si quieres.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _InvitadoCampos {
  final TextEditingController nombre = TextEditingController();
  final TextEditingController peso = TextEditingController();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _apiClient = ApiClient();
  final _nameController = TextEditingController();
  final _ownerPercent = TextEditingController(text: '100');
  final List<_InvitadoCampos> _invitados = [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ownerPercent.dispose();
    for (final invitado in _invitados) {
      invitado.nombre.dispose();
      invitado.peso.dispose();
    }
    super.dispose();
  }

  /// Reparte 100 a partes iguales entre tú y los invitados; el primero (tú)
  /// absorbe el redondeo para que sume 100 exacto.
  void _repartirIgual() {
    final total = _invitados.length + 1;
    final parte = double.parse((100 / total).toStringAsFixed(2));
    var asignado = 0.0;
    for (final invitado in _invitados) {
      invitado.peso.text = _fmt(parte);
      asignado += parte;
    }
    _ownerPercent.text = _fmt(100 - asignado);
  }

  String _fmt(double value) {
    final texto = value.toStringAsFixed(2);
    return texto.endsWith('.00') ? value.toStringAsFixed(0) : texto;
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  double get _suma =>
      _num(_ownerPercent) + _invitados.fold(0.0, (s, i) => s + _num(i.peso));

  void _addInvitado() {
    setState(() {
      _invitados.add(_InvitadoCampos());
      _repartirIgual();
    });
  }

  void _removeInvitado(int index) {
    setState(() {
      _invitados[index].nombre.dispose();
      _invitados[index].peso.dispose();
      _invitados.removeAt(index);
      _repartirIgual();
    });
  }

  String? _validar() {
    if (_nameController.text.trim().isEmpty) return 'Pon un nombre al grupo';
    for (final invitado in _invitados) {
      if (invitado.nombre.text.trim().isEmpty) {
        return 'Cada invitado necesita un nombre';
      }
    }
    if ((_suma - 100).abs() > 0.001) {
      return 'Los pesos deben sumar 100 (ahora: ${_suma.toStringAsFixed(2)})';
    }
    return null;
  }

  Future<void> _crear() async {
    final error = _validar();
    if (error != null) {
      _aviso(error);
      return;
    }
    setState(() => _saving = true);
    try {
      await _apiClient.createGroup(
        name: _nameController.text.trim(),
        ownerPercentage: _num(_ownerPercent).toStringAsFixed(2),
        members: _invitados
            .map((i) => {
                  'display_name': i.nombre.text.trim(),
                  'default_percentage': _num(i.peso).toStringAsFixed(2),
                })
            .toList(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _aviso(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final cuadra = (_suma - 100).abs() < 0.001;
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo grupo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre del grupo',
              helperText: 'Un piso, una pareja, un viaje...',
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 22),
          const EtiquetaSeccion('Participantes'),
          const SizedBox(height: 4),
          Text(
            'El peso de cada uno es su parte de los ingresos del hogar y suma '
            '100. Puedes añadir gente sin cuenta, solo con su nombre.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // Tú (el creador)
          Row(
            children: [
              PersonaAvatar(nombre: 'Yo', size: 34),
              const SizedBox(width: 12),
              const Expanded(child: Text('Tú')),
              SizedBox(
                width: 92,
                child: TextField(
                  controller: _ownerPercent,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.end,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                      suffixText: '%', isDense: true),
                ),
              ),
            ],
          ),
          for (final (index, invitado) in _invitados.indexed) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                IconButton(
                  onPressed: () => _removeInvitado(index),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: DividiColors.rojo,
                  tooltip: 'Quitar',
                ),
                Expanded(
                  child: TextField(
                    controller: invitado.nombre,
                    textCapitalization: TextCapitalization.words,
                    decoration:
                        const InputDecoration(hintText: 'Nombre', isDense: true),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: invitado.peso,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.end,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        suffixText: '%', isDense: true),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addInvitado,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Añadir invitado'),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: cuadra
                    ? DividiTones.of(context).positivoFondo
                    : DividiTones.of(context).negativoFondo,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                'Suma: ${_suma.toStringAsFixed(2)} / 100',
                style: TextStyle(
                  fontFamily: DividiTheme.familiaTitulares,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: cuadra
                      ? DividiTones.of(context).positivo
                      : DividiTones.of(context).negativo,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: _saving ? null : _crear,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Text('Crear grupo'),
          ),
        ],
      ),
    );
  }
}
