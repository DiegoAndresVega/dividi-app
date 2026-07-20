import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../widgets/campo_contrasena.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _apiClient = ApiClient();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  bool _loading = false;

  static const _minCaracteres = 8;

  /// Error de la confirmación, en vivo. Callado mientras el campo esté vacío:
  /// no se avisa de que no coincide antes de que dé tiempo a escribirla.
  String? get _errorConfirmacion {
    if (_confirmController.text.isEmpty) return null;
    if (_confirmController.text != _passwordController.text) {
      return 'Las dos contraseñas no coinciden';
    }
    return null;
  }

  String? _validar() {
    if (_nameController.text.trim().isEmpty) return 'Pon tu nombre';
    if (_emailController.text.trim().isEmpty) return 'Pon tu email';
    if (_passwordController.text.length < _minCaracteres) {
      return 'La contraseña necesita al menos $_minCaracteres caracteres';
    }
    if (_confirmController.text != _passwordController.text) {
      return 'Las dos contraseñas no coinciden';
    }
    return null;
  }

  Future<void> _submit() async {
    final error = _validar();
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _loading = true);
    try {
      await _apiClient.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        inviteCode: _inviteCodeController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cuenta creada. Ya puedes iniciar sesión.')),
      );
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Dividi reparte los gastos comunes según los ingresos de '
                  'cada uno: quien gana más aporta más, y a todos les cuesta '
                  'el mismo esfuerzo. Funciona por invitación: pide un código '
                  'a quien ya esté dentro.',
                  style: tema.textTheme.bodyMedium?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                CampoContrasena(
                  controller: _passwordController,
                  label: 'Contraseña (mín. $_minCaracteres caracteres)',
                  esNueva: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                CampoContrasena(
                  controller: _confirmController,
                  label: 'Repite la contraseña',
                  esNueva: true,
                  errorText: _errorConfirmacion,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _inviteCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Código de invitación',
                    helperText: 'Déjalo vacío si eres el primer usuario',
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Crear mi cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
