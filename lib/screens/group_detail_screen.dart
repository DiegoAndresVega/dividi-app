import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../theme/dividi_format.dart';
import '../theme/dividi_theme.dart';
import '../widgets/dividi_bits.dart';
import 'expense_form_screen.dart';
import 'members_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const GroupDetailScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final _apiClient = ApiClient();

  late Future<Map<String, dynamic>> _groupFuture;
  late Future<List<dynamic>> _expensesFuture;
  late Future<List<dynamic>> _balancesFuture;
  late Future<List<dynamic>> _settleUpFuture;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  void _loadAll() {
    _groupFuture = _apiClient.getGroup(widget.groupId);
    _expensesFuture = _apiClient.getExpenses(widget.groupId);
    _balancesFuture = _apiClient.getBalances(widget.groupId);
    _settleUpFuture = _apiClient.getSettleUp(widget.groupId);
  }

  Future<void> _refresh() async {
    setState(_loadAll);
  }

  /// Abre el formulario de gasto: para crear (expense == null) o editar.
  Future<void> _openExpenseForm({Map<String, dynamic>? expense}) async {
    final group = await _groupFuture;
    if (!mounted) return;
    final members = (group['members'] as List<dynamic>);

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          groupId: widget.groupId,
          members: members,
          expense: expense,
        ),
      ),
    );
    // refrescar siempre: aunque el gasto se cancele, pudo añadirse un
    // participante nuevo al grupo desde el formulario
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.groupName),
          actions: [
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'Miembros',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MembersScreen(
                      groupId: widget.groupId,
                      groupName: widget.groupName,
                    ),
                  ),
                );
                await _refresh();
              },
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gastos'),
              Tab(text: 'Balances'),
              Tab(text: 'Saldar'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: TabBarView(
            children: [
              _buildExpensesTab(),
              _buildBalancesTab(),
              _buildSettleUpTab(),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _openExpenseForm(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Nuevo gasto'),
        ),
      ),
    );
  }

  Widget _buildExpensesTab() {
    return FutureBuilder<List<dynamic>>(
      future: _expensesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              EstadoVacio(
                titulo: 'No se pudo cargar',
                detalle: '${snapshot.error}',
              ),
            ],
          );
        }
        final expenses = snapshot.data ?? [];
        if (expenses.isEmpty) {
          return ListView(
            children: const [
              EstadoVacio(
                titulo: 'Todavía no hay gastos en este grupo.',
                detalle: 'Apunta el primero con el botón «Nuevo gasto».',
              ),
            ],
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          itemCount: expenses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final expense = expenses[index];
            final tema = Theme.of(context);
            final categoria =
                DividiTones.of(context).categoria(expense['category']);
            return Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openExpenseForm(expense: expense),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Row(
                    children: [
                      CategoriaInsignia(categoria: expense['category']),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              expense['description'],
                              style: tema.textTheme.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${categoria.etiqueta} · ${etiquetaMetodo(expense['split_method'])}',
                              style: tema.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatearImporte(expense['amount'],
                            divisa: expense['currency']),
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBalancesTab() {
    return FutureBuilder<List<dynamic>>(
      future: _balancesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              EstadoVacio(
                titulo: 'No se pudo cargar',
                detalle: '${snapshot.error}',
              ),
            ],
          );
        }
        final balances = snapshot.data ?? [];
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          itemCount: balances.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final balance = balances[index];
            final amount = double.tryParse(balance['balance'].toString()) ?? 0;
            final label = amount > 0.004
                ? 'le deben'
                : amount < -0.004
                    ? 'debe'
                    : 'en paz con el grupo';
            final tema = Theme.of(context);
            return Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    PersonaAvatar(nombre: balance['display_name'], size: 42),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            balance['display_name'],
                            style: tema.textTheme.titleSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(label, style: tema.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SaldoChip(importe: amount),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSettleUpTab() {
    return FutureBuilder<List<dynamic>>(
      future: _settleUpFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ListView(
            children: [
              EstadoVacio(
                titulo: 'No se pudo cargar',
                detalle: '${snapshot.error}',
              ),
            ],
          );
        }
        final settlements = snapshot.data ?? [];
        if (settlements.isEmpty) {
          return ListView(
            children: const [
              EstadoVacio(
                titulo: 'Todo saldado. A otra cosa. 🎉',
                detalle: 'No hay pagos pendientes en este grupo.',
              ),
            ],
          );
        }
        final tema = Theme.of(context);
        final tonos = DividiTones.of(context);
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: tonos.positivoFondo,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                settlements.length == 1
                    ? 'Con 1 solo pago el grupo queda en paz.'
                    : 'Con ${settlements.length} pagos el grupo queda en paz '
                        '— el mínimo posible.',
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tonos.positivo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            for (final s in settlements) ...[
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      PersonaAvatar(nombre: s['from_display_name'], size: 38),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(text: s['from_display_name']),
                            TextSpan(
                              text: '  →  ',
                              style: TextStyle(
                                  color: tema.colorScheme.onSurfaceVariant),
                            ),
                            TextSpan(text: s['to_display_name']),
                          ]),
                          style: tema.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        formatearImporte(s['amount']),
                        style: tema.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 6),
            Text(
              'Sugerencias del algoritmo de settle-up: como máximo n−1 pagos.',
              textAlign: TextAlign.center,
              style: tema.textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
