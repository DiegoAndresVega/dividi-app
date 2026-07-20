import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';

/// Nuevo grupo: nombre + participantes. Puedes crearlo tú solo, meter ya a tus
/// amigos por su cuenta (les llega un aviso) o añadir participantes
/// personalizados, que solo existen dentro del grupo y son un nombre suelto
/// ("Compi", "Piso 2"...). Los pesos son la parte de los ingresos de cada uno
/// y deben sumar 100 — al añadir o quitar gente se reparten a partes iguales,
/// y luego los ajustas si quieres.
class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

/// Un participante del grupo nuevo: o un amigo con cuenta (`userId`), o uno
/// personalizado sin cuenta, del que solo tenemos el nombre.
class _Participante {
  final String? userId;
  final TextEditingController nombre;
  final TextEditingController peso = TextEditingController();

  _Participante.amigo({required String this.userId, required String nombreAmigo})
      : nombre = TextEditingController(text: nombreAmigo);

  _Participante.personalizado()
      : userId = null,
        nombre = TextEditingController();

  bool get esAmigo => userId != null;

  void dispose() {
    nombre.dispose();
    peso.dispose();
  }
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _apiClient = ApiClient();
  final _nameController = TextEditingController();
  final _ownerPercent = TextEditingController(text: '100');
  final List<_Participante> _participantes = [];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _ownerPercent.dispose();
    for (final participante in _participantes) {
      participante.dispose();
    }
    super.dispose();
  }

  /// Reparte 100 a partes iguales entre tú y los participantes; tú absorbes el
  /// redondeo para que sume 100 exacto.
  void _repartirIgual() {
    final total = _participantes.length + 1;
    final parte = double.parse((100 / total).toStringAsFixed(2));
    var asignado = 0.0;
    for (final participante in _participantes) {
      participante.peso.text = _fmt(parte);
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
      _num(_ownerPercent) + _participantes.fold(0.0, (s, p) => s + _num(p.peso));

  void _addPersonalizado() {
    setState(() {
      _participantes.add(_Participante.personalizado());
      _repartirIgual();
    });
  }

  /// Elige un amigo de tu lista y lo mete ya en el grupo, sin pasos extra.
  Future<void> _addAmigo() async {
    final yaEstan =
        _participantes.where((p) => p.esAmigo).map((p) => p.userId).toSet();
    try {
      final amigos = await _apiClient.getFriends();
      final disponibles =
          amigos.where((a) => !yaEstan.contains(a['user_id'])).toList();
      if (!mounted) return;
      if (disponibles.isEmpty) {
        _aviso(amigos.isEmpty
            ? 'Aún no tienes amigos. Añádelos desde tu perfil.'
            : 'Ya has añadido a todos tus amigos.');
        return;
      }

      final elegido = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Añadir un amigo'),
          children: [
            for (final amigo in disponibles)
              SimpleDialogOption(
                onPressed: () =>
                    Navigator.of(ctx).pop(amigo as Map<String, dynamic>),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      PersonaAvatar(nombre: amigo['name'], size: 34),
                      const SizedBox(width: 12),
                      Expanded(child: Text(amigo['name'])),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
      if (elegido == null || !mounted) return;

      setState(() {
        _participantes.add(_Participante.amigo(
          userId: elegido['user_id'] as String,
          nombreAmigo: elegido['name'] as String,
        ));
        _repartirIgual();
      });
    } on ApiException catch (e) {
      if (mounted) _aviso(e.message);
    }
  }

  void _remove(int index) {
    setState(() {
      _participantes[index].dispose();
      _participantes.removeAt(index);
      _repartirIgual();
    });
  }

  String? _validar() {
    if (_nameController.text.trim().isEmpty) return 'Pon un nombre al grupo';
    for (final participante in _participantes) {
      if (participante.nombre.text.trim().isEmpty) {
        return 'Cada participante personalizado necesita un nombre';
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
        members: _participantes
            .map((p) => {
                  'display_name': p.nombre.text.trim(),
                  'default_percentage': _num(p.peso).toStringAsFixed(2),
                  if (p.esAmigo) 'user_id': p.userId,
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

  /// Fila de un participante: el nombre (fijo si es amigo, editable si es
  /// personalizado) y su peso.
  Widget _filaParticipante(int index, _Participante participante) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _remove(index),
            icon: const Icon(Icons.remove_circle_outline),
            color: DividiColors.rojo,
            tooltip: 'Quitar',
          ),
          Expanded(
            child: participante.esAmigo
                ? Row(
                    children: [
                      PersonaAvatar(nombre: participante.nombre.text, size: 30),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          participante.nombre.text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                : TextField(
                    controller: participante.nombre,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                        hintText: 'Nombre', isDense: true),
                  ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 92,
            child: TextField(
              controller: participante.peso,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(suffixText: '%', isDense: true),
            ),
          ),
        ],
      ),
    );
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
            '100. Puedes meter a tus amigos por su cuenta o crear '
            'participantes personalizados, que solo existen en este grupo.',
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
          for (final (index, participante) in _participantes.indexed)
            _filaParticipante(index, participante),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                onPressed: _addAmigo,
                icon: const Icon(Icons.group_add_rounded),
                label: const Text('Añadir amigo'),
              ),
              TextButton.icon(
                onPressed: _addPersonalizado,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Participante personalizado'),
              ),
            ],
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
