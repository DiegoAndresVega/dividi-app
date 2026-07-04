import 'package:flutter/material.dart';

import '../services/api_client.dart';
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

    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ExpenseFormScreen(
          groupId: widget.groupId,
          members: members,
          expense: expense,
        ),
      ),
    );
    if (changed == true) await _refresh();
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
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Gastos'),
              Tab(text: 'Balances'),
              Tab(text: 'Settle up'),
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
        floatingActionButton: FloatingActionButton(
          onPressed: () => _openExpenseForm(),
          child: const Icon(Icons.add),
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
          return _errorList('Error: ${snapshot.error}');
        }
        final expenses = snapshot.data ?? [];
        if (expenses.isEmpty) {
          return _errorList('Todavía no hay gastos en este grupo.');
        }
        return ListView.builder(
          itemCount: expenses.length,
          itemBuilder: (context, index) {
            final expense = expenses[index];
            return ListTile(
              title: Text(expense['description']),
              subtitle: Text('${expense['category']} · ${expense['split_method']}'),
              trailing: Text('${expense['amount']} ${expense['currency']}'),
              onTap: () => _openExpenseForm(expense: expense),
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
          return _errorList('Error: ${snapshot.error}');
        }
        final balances = snapshot.data ?? [];
        return ListView.builder(
          itemCount: balances.length,
          itemBuilder: (context, index) {
            final balance = balances[index];
            final amount = double.tryParse(balance['balance'].toString()) ?? 0;
            final color = amount > 0
                ? Colors.green
                : amount < 0
                    ? Colors.red
                    : Colors.grey;
            final label = amount > 0
                ? 'le deben'
                : amount < 0
                    ? 'debe'
                    : 'saldado';
            return ListTile(
              title: Text(balance['display_name']),
              subtitle: Text(label),
              trailing: Text(
                '${balance['balance']} €',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
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
          return _errorList('Error: ${snapshot.error}');
        }
        final settlements = snapshot.data ?? [];
        if (settlements.isEmpty) {
          return _errorList('El grupo ya está saldado. No hay pagos pendientes.');
        }
        return ListView.builder(
          itemCount: settlements.length,
          itemBuilder: (context, index) {
            final s = settlements[index];
            return ListTile(
              leading: const Icon(Icons.arrow_forward),
              title: Text('${s['from_display_name']} → ${s['to_display_name']}'),
              trailing: Text(
                '${s['amount']} €',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          },
        );
      },
    );
  }

  Widget _errorList(String message) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        Center(child: Text(message, textAlign: TextAlign.center)),
      ],
    );
  }
}
