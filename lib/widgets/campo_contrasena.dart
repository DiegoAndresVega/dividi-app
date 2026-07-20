import 'package:flutter/material.dart';

/// Campo de contraseña con el botón del ojo para verla mientras se escribe.
/// Lo usan iniciar sesión y crear cuenta, para que se comporte igual en las dos.
class CampoContrasena extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final String? errorText;

  /// Al crear cuenta conviene `newPassword` para que el gestor de contraseñas
  /// ofrezca una nueva en vez de rellenar la guardada.
  final bool esNueva;

  final TextInputAction textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onSubmitted;

  const CampoContrasena({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.errorText,
    this.esNueva = false,
    this.textInputAction = TextInputAction.next,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  State<CampoContrasena> createState() => _CampoContrasenaState();
}

class _CampoContrasenaState extends State<CampoContrasena> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSubmitted?.call(),
      autofillHints: [
        widget.esNueva ? AutofillHints.newPassword : AutofillHints.password,
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          onPressed: () => setState(() => _visible = !_visible),
          icon: Icon(
            _visible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          ),
          tooltip: _visible ? 'Ocultar contraseña' : 'Ver contraseña',
        ),
      ),
    );
  }
}
