import 'package:flutter/material.dart';

import '../theme/dividi_theme.dart';

/// Paleta de emojis para categorías inventadas: recibos y hogar, pantallas,
/// transporte y viajes, comida, salud y cuidado, compras, mascotas y dinero.
const emojisDeCategoria = [
  '💧', '⚡', '🔥', '🔌', '🛜', '💡', '🧾', '🏠',
  '📱', '💻', '📺', '🎮', '🎬', '🎵', '🎟️', '📚',
  '✈️', '🚗', '🚕', '🚆', '🛵', '⛽', '🅿️', '🧳',
  '☕', '🍕', '🍔', '🥗', '🍻', '🍷', '🧁', '🛒',
  '💊', '🏥', '🦷', '💇', '🧴', '🏋️', '🧘', '⚽',
  '👕', '👟', '🛍️', '💄', '🎁', '🌱', '🛠️', '🧹',
  '🐶', '🐱', '👶', '🧸', '💳', '🏦', '📈', '🎓',
];

/// Selector de categoría del gasto: chips con las predefinidas más «Nueva»,
/// que abre una hoja para inventarse una categoría («agua») y elegirle un
/// emoji (💧). La inventada aparece como un chip más mientras esté elegida.
class CategoriaSelector extends StatelessWidget {
  final String categoria;
  final String? emoji;
  final void Function(String categoria, String? emoji) onChanged;

  const CategoriaSelector({
    super.key,
    required this.categoria,
    required this.emoji,
    required this.onChanged,
  });

  bool get _esInventada => !DividiTones.predefinidas.contains(categoria);

  Future<void> _nuevaCategoria(BuildContext context) async {
    final resultado = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _NuevaCategoriaSheet(
        nombreInicial: _esInventada ? categoria : '',
        emojiInicial: _esInventada ? emoji : null,
      ),
    );
    if (resultado == null) return;
    onChanged(resultado.$1, resultado.$2);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final tonos = DividiTones.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final nombre in DividiTones.predefinidas)
          ChoiceChip(
            avatar: Icon(
              tonos.categoria(nombre).icono,
              size: 18,
              color: categoria == nombre
                  ? tema.colorScheme.onPrimary
                  : tonos.categoria(nombre).color,
            ),
            label: Text(tonos.categoria(nombre).etiqueta),
            selected: categoria == nombre,
            showCheckmark: false,
            onSelected: (_) => onChanged(nombre, null),
          ),
        if (_esInventada)
          ChoiceChip(
            avatar: Text(
              emoji ?? '🏷️',
              style: const TextStyle(fontSize: 16),
            ),
            label: Text(tonos.categoria(categoria).etiqueta),
            selected: true,
            showCheckmark: false,
            onSelected: (_) => _nuevaCategoria(context),
          ),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18),
          label: Text(_esInventada ? 'Cambiar' : 'Nueva'),
          onPressed: () => _nuevaCategoria(context),
        ),
      ],
    );
  }
}

/// Hoja para crear (o retocar) una categoría inventada: nombre + emoji.
class _NuevaCategoriaSheet extends StatefulWidget {
  final String nombreInicial;
  final String? emojiInicial;

  const _NuevaCategoriaSheet({
    required this.nombreInicial,
    required this.emojiInicial,
  });

  @override
  State<_NuevaCategoriaSheet> createState() => _NuevaCategoriaSheetState();
}

class _NuevaCategoriaSheetState extends State<_NuevaCategoriaSheet> {
  late final _nombre = TextEditingController(text: widget.nombreInicial);
  late String? _emoji = widget.emojiInicial;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  void _confirmar() {
    // misma normalización que la API: minúsculas y sin espacios sobrantes
    final nombre = _nombre.text.trim().toLowerCase();
    final emoji = _emoji;
    if (nombre.isEmpty || emoji == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ponle nombre a la categoría y elige un emoji.')));
      return;
    }
    Navigator.of(context).pop((nombre, emoji));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Categoría a tu manera', style: tema.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Escribe el nombre y elige su emoji.',
                style: tema.textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nombre,
                autofocus: widget.nombreInicial.isEmpty,
                maxLength: 30,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Agua, luz, gimnasio…',
                  counterText: '',
                  suffixText: _emoji,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final emoji in emojisDeCategoria)
                        _EmojiOpcion(
                          emoji: emoji,
                          elegido: _emoji == emoji,
                          onTap: () => setState(() => _emoji = emoji),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _confirmar,
                  child: const Text('Usar esta categoría'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiOpcion extends StatelessWidget {
  final String emoji;
  final bool elegido;
  final VoidCallback onTap;

  const _EmojiOpcion({
    required this.emoji,
    required this.elegido,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: elegido
              ? tema.colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: elegido ? tema.colorScheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 22)),
      ),
    );
  }
}
