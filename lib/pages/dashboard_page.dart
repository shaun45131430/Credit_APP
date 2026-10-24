import 'package:flutter/material.dart';

import 'add_customer_page.dart';
import 'customer_statement_page.dart';
import 'payment_pages.dart';
import 'profile_page.dart';
import '../models/credit_payment.dart';
import '../models/credit_sale.dart';
import '../models/customer.dart';
import '../models/reminder.dart';
import '../services/pdf_services.dart';
import '../services/reminder_scheduler.dart';
import '../services/reminder_service.dart';
import '../widgets/form_widgets.dart';

class DashboardPage extends StatefulWidget {
  final String ownerName;
  final String businessName;
  final String ownerPhone;

  const DashboardPage({
    super.key,
    required this.ownerName,
    required this.businessName,
    this.ownerPhone = '',
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final List<Customer> _customers = [];
  final List<CreditSale> _sales = [];
  final List<CreditPayment> _payments = [];
  final searchController = TextEditingController();
  int _selectedNavIndex = 0;
  bool _isSearchOpen = false;
  bool _showOverdueOnly = false;

  // ── REMINDER STATE ──────────────────────────────────────────
  final ReminderScheduler _reminderScheduler = ReminderScheduler();
  List<Reminder> _reminderLog = [];
  List<CreditSale> _dueReminders = [];

  double get totalOutstanding =>
      _customers.fold(0.0, (sum, customer) => sum + customer.amountOwed);

  double get totalOverdue => _customers
      .where((customer) => customer.dueDate.isBefore(DateTime.now()))
      .fold(0.0, (sum, customer) => sum + customer.amountOwed);

  double get collectedThisMonth => _payments
      .where(
        (payment) =>
            payment.paymentDate.year == DateTime.now().year &&
            payment.paymentDate.month == DateTime.now().month,
      )
      .fold(0.0, (sum, payment) => sum + payment.amount);

  // ── INIT / DISPOSE ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _startReminderScheduler();
  }

  Future<void> _startReminderScheduler() async {
    _reminderLog = await ReminderService.loadLog();
    if (!mounted) return;
    _reminderScheduler.start(
      invoices: () => _sales,
      payments: () => _payments,
      onDue: (due) {
        if (!mounted) return;
        setState(() => _dueReminders = due);
      },
    );
    final due = ReminderService.dueForReminder(
      invoices: _sales,
      payments: _payments,
      log: _reminderLog,
    );
    if (mounted) setState(() => _dueReminders = due);
  }

  @override
  void dispose() {
    _reminderScheduler.stop();
    searchController.dispose();
    super.dispose();
  }

  String get greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 18) return 'Good Afternoon';
    return 'Good Evening';
  }

  void _applySale(CreditSale sale) {
    setState(() {
      _sales.add(sale);
      final existingIndex = _customers.indexWhere(
        (c) => c.name.toLowerCase() == sale.customer.name.toLowerCase(),
      );
      if (existingIndex >= 0) {
        final c = _customers[existingIndex];
        _customers[existingIndex] = Customer(
          name: c.name,
          phone: c.phone.isNotEmpty ? c.phone : sale.customer.phone,
          email: c.email,
          amountOwed: c.amountOwed + sale.amount,
          dueDate: sale.dueDate.isBefore(c.dueDate) ? sale.dueDate : c.dueDate,
        );
      } else {
        _customers.add(sale.customer);
      }
    });
  }

  String _itemsForCustomer(Customer customer) {
    return _sales
        .where((s) => s.customer.name.toLowerCase() == customer.name.toLowerCase())
        .map((s) => s.itemDescription)
        .where((desc) => desc.isNotEmpty)
        .join(', ');
  }

  void _openCustomerStatement(Customer customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerStatementPage(
          customer: customer,
          sales: _sales,
          payments: _payments,
          onLogPayment: (cust) async {
            return await showDialog<CreditPayment>(
              context: context,
              builder: (context) => _LogPaymentDialog(customer: cust),
            );
          },
        ),
      ),
    );
  }

  void _openProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          ownerName: widget.ownerName,
          businessName: widget.businessName,
          ownerPhone: widget.ownerPhone,
        ),
      ),
    );
  }

  void _showReminderSheet(Customer customer) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Reminder sent to ${customer.name} successfully!')),
    );
  }

  void _showInvoiceSheet(Customer customer) {
    final customerSales = _sales
        .where((s) => s.customer.name.toLowerCase() == customer.name.toLowerCase())
        .toList();
    PdfService.shareCustomerStatement(
      businessName: widget.businessName,
      customer: customer,
      sales: customerSales,
      payments: _payments,
    );
  }

  void _runDueRemindersNow() {
    setState(() => _dueReminders.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All due reminders processed successfully!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCustomers = _customers.isNotEmpty;
    final compact = MediaQuery.sizeOf(context).width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0C1C3D),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Container(
              margin: EdgeInsets.all(compact ? 8 : 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F3F3),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFF0D1D45), width: 3),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: _selectedNavIndex == 2
                            ? _buildCustomersTab(context, compact)
                            : _selectedNavIndex == 1
                            ? _buildReportsTab(compact)
                            : SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  20,
                                  24,
                                  110,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildDashboardHeader(compact),
                                    const SizedBox(height: 22),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: StatCard(
                                            title: 'Outstanding',
                                            compact: compact,
                                            value: hasCustomers
                                                ? 'R${totalOutstanding.toStringAsFixed(2)}'
                                                : 'R0.00',
                                            color: const Color(0xFF0E2C75),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: StatCard(
                                            title: 'Overdue',
                                            compact: compact,
                                            value: hasCustomers
                                                ? 'R${totalOverdue.toStringAsFixed(2)}'
                                                : 'R0.00',
                                            color: const Color(0xFFDB3A3A),
                                            onTap: () => setState(() {
                                              _showOverdueOnly = true;
                                              _selectedNavIndex = 2;
                                              searchController.clear();
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 18),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 16,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2FAE4F),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        hasCustomers
                                            ? 'Collected this month: R${collectedThisMonth.toStringAsFixed(2)}'
                                            : 'Collected this month: R0.00',
                                        style: TextStyle(
                                          fontSize: compact ? 18 : 32,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    if (_dueReminders.isNotEmpty) ...[
                                      const SizedBox(height: 18),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF4D6),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFE6C46A),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.notifications_active,
                                              color: Color(0xFF8A6D00),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                '${_dueReminders.length} reminder${_dueReminders.length == 1 ? '' : 's'} due today',
                                                style: const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF5D4700),
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _runDueRemindersNow,
                                              child: const Text('Send now'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 30),
                                    const Text(
                                      'NEEDS ATTENTION',
                                      style: TextStyle(
                                        fontSize: 28,
                                        color: Color(0xFF1D1D1D),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 18),
                                    if (!hasCustomers)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            top: 32,
                                            bottom: 16,
                                          ),
                                          child: Text(
                                            'No customers added yet',
                                            style: TextStyle(
                                              fontSize: 22,
                                              color: Color(0xFF4E4E4E),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      )
                                    else
                                      ..._customers.map(
                                        (customer) => Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 18,
                                          ),
                                          decoration: const BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: Color(0xFFCBCBCB),
                                                width: 1.5,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      customer.name,
                                                      style: TextStyle(
                                                        fontSize: compact
                                                            ? 20
                                                            : 28,
                                                        color: const Color(
                                                          0xFF1D1D1D,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Due ${customer.formattedDueDate}',
                                                      style: TextStyle(
                                                        fontSize: compact
                                                            ? 15
                                                            : 22,
                                                        color: const Color(
                                                          0xFF3A3A3A,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.w400,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  Text(
                                                    customer.formattedAmount,
                                                    style: TextStyle(
                                                      fontSize: compact
                                                          ? 19
                                                          : 28,
                                                      color: const Color(
                                                        0xFFE33A3A,
                                                      ),
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            _showReminderSheet(
                                                          customer,
                                                        ),
                                                        style: TextButton
                                                            .styleFrom(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                          minimumSize:
                                                              Size.zero,
                                                        ),
                                                        child: Text(
                                                          'Reminder',
                                                          style: TextStyle(
                                                            fontSize: compact
                                                                ? 14
                                                                : 16,
                                                            color: const Color(
                                                              0xFF0E2C75,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                      TextButton.icon(
                                                        onPressed: () =>
                                                            _showInvoiceSheet(
                                                          customer,
                                                        ),
                                                        style: TextButton
                                                            .styleFrom(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                            horizontal: 8,
                                                            vertical: 2,
                                                          ),
                                                          minimumSize:
                                                              Size.zero,
                                                        ),
                                                        icon: const Icon(
                                                          Icons
                                                              .receipt_long_outlined,
                                                          size: 17,
                                                        ),
                                                        label: Text(
                                                          'Invoice',
                                                          style: TextStyle(
                                                            fontSize: compact
                                                                ? 14
                                                                : 16,
                                                            color: const Color(
                                                              0xFF0E2C75,
                                                            ),
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 90,
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF3F3F3),
                        border: Border(
                          top: BorderSide(
                            color: Color(0xFFCFD5DF),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Expanded(
                            child: NavItem(
                              label: 'Home',
                              icon: Icons.home_rounded,
                              selected: _selectedNavIndex == 0,
                              onTap: () =>
                                  setState(() => _selectedNavIndex = 0),
                            ),
                          ),
                          Expanded(
                            child: NavItem(
                              label: 'Reports',
                              icon: Icons.bar_chart_rounded,
                              selected: _selectedNavIndex == 1,
                              onTap: () =>
                                  setState(() => _selectedNavIndex = 1),
                            ),
                          ),
                          Expanded(
                            child: NavItem(
                              label: 'Customers',
                              icon: Icons.people_alt_outlined,
                              selected: _selectedNavIndex == 2,
                              onTap: () => setState(() {
                                _selectedNavIndex = 2;
                                _showOverdueOnly = false;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: 34,
                    bottom: 24,
                    child: FloatingActionButton(
                      tooltip: 'Add customer or record sale',
                      onPressed: () async {
                        final sale = await Navigator.of(context)
                            .push<CreditSale>(
                              MaterialPageRoute(
                                builder: (_) => AddCustomerPage(
                                  customers: List.unmodifiable(_customers),
                                ),
                              ),
                            );
                        if (sale != null) _applySale(sale);
                      },
                      backgroundColor: const Color(0xFF2FD271),
                      child: const Icon(
                        Icons.add,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomersTab(BuildContext context, bool compact) {
    final query = searchController.text.trim().toLowerCase();
    final filteredCustomers = _customers.where((customer) {
      if (_showOverdueOnly && !customer.dueDate.isBefore(DateTime.now())) {
        return false;
      }
      final items = _itemsForCustomer(customer).toLowerCase();
      return customer.name.toLowerCase().contains(query) ||
          customer.phone.toLowerCase().contains(query) ||
          items.contains(query);
    }).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? 18 : 28,
        20,
        compact ? 18 : 28,
        112,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDashboardHeader(compact),
          Row(
            children: [
              Expanded(
                child: Text(
                  _showOverdueOnly ? 'Overdue accounts' : 'Customers',
                  style: TextStyle(
                    fontSize: compact ? 26 : 34,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F2B7A),
                  ),
                ),
              ),
              IconButton(
                tooltip: _isSearchOpen ? 'Close search' : 'Search customers',
                onPressed: () => setState(() {
                  _isSearchOpen = !_isSearchOpen;
                  if (!_isSearchOpen) searchController.clear();
                }),
                icon: Icon(_isSearchOpen ? Icons.close : Icons.search),
              ),
            ],
          ),
          if (_isSearchOpen) ...[
            const SizedBox(height: 8),
            TextField(
              controller: searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search name, phone, or item',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          searchController.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close),
                      ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (filteredCustomers.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  _showOverdueOnly
                      ? 'No overdue accounts'
                      : _customers.isEmpty
                      ? 'No customers added yet'
                      : 'No customers match your search',
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 18,
                  ),
                ),
              ),
            )
          else
            ...filteredCustomers.map((customer) {
              final items = _itemsForCustomer(customer);
              return InkWell(
                onTap: () => _openCustomerStatement(customer),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFDDDDDD)),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customer.name,
                              style: TextStyle(
                                fontSize: compact ? 18 : 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Items: ${items.isEmpty ? 'No items recorded' : items}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 13 : 15,
                                color: const Color(0xFF555555),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Due ${customer.formattedDueDate}',
                              style: TextStyle(
                                fontSize: compact ? 13 : 15,
                                color: const Color(0xFF555555),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            customer.formattedAmount,
                            style: TextStyle(
                              fontSize: compact ? 17 : 21,
                              color: const Color(0xFFD52C2C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: Color(0xFF777777),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildReportsTab(bool compact) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(compact ? 18 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDashboardHeader(compact),
          const SizedBox(height: 18),
          Text(
            'Reports & Summary',
            style: TextStyle(
              fontSize: compact ? 26 : 34,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F2B7A),
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Overview',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Customers:'),
                    Text('${_customers.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Outstanding:'),
                    Text('R${totalOutstanding.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Collected This Month:'),
                    Text('R${collectedThisMonth.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader(bool compact) {
    final initial = widget.ownerName.trim().isEmpty
        ? 'U'
        : widget.ownerName.trim().characters.first.toUpperCase();

    return Row(
      children: [
        IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
          color: const Color(0xFF0E2C75),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting ${widget.ownerName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 15 : 21,
                  color: const Color(0xFF1D1D1D),
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                widget.businessName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: compact ? 21 : 30,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF0F2B7A),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FloatingActionButton.small(
          heroTag: 'dashboard-profile',
          tooltip: 'Open profile',
          onPressed: _openProfile,
          backgroundColor: const Color(0xFF202777),
          foregroundColor: Colors.white,
          child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

class _LogPaymentDialog extends StatefulWidget {
  final Customer customer;

  const _LogPaymentDialog({required this.customer});

  @override
  State<_LogPaymentDialog> createState() => _LogPaymentDialogState();
}

class _LogPaymentDialogState extends State<_LogPaymentDialog> {
  final amountController = TextEditingController();
  String method = 'Cash';

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Log Payment for ${widget.customer.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Payment Amount (R)'),
          ),
          const SizedBox(height: 12),
          DropdownButton<String>(
            value: method,
            isExpanded: true,
            items: ['Cash', 'EFT', 'Card', 'Mobile Money']
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (val) => setState(() => method = val ?? 'Cash'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final amt = double.tryParse(amountController.text) ?? 0;
            if (amt <= 0) return;
            final payment = CreditPayment(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              customer: widget.customer,
              amount: amt,
              paymentDate: DateTime.now(),
              method: method,
            );
            Navigator.of(context).pop(payment);
          },
          child: const Text('Record Payment'),
        ),
      ],
    );
  }
}
