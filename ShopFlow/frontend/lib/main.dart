import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:dio/browser.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// =====================================================
// SHOPFLOW CONFIGURATION
// =====================================================

const String apiUrl = 'http://localhost:5050/api';

const Color primaryBlue = Color(0xFF2563EB);
const Color darkNavy = Color(0xFF172554);
const Color backgroundColor = Color(0xFFF4F7FB);

// =====================================================
// INVOICE PDF & RECEIPT PRINTING
// =====================================================

class InvoicePrintService {
  static String _money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return 'LKR ${amount.toStringAsFixed(2)}';
  }

  static String _date(dynamic value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed == null) return '-';
    final date = parsed.toLocal();
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  static Future<Uint8List> buildPdf(
    Map<String, dynamic> sale, {
    required String shopName,
    Map<String, dynamic>? company,
    bool thermal = false,
    double paperWidthMm = 80,
  }) async {
    final document = pw.Document();
    final items = List<dynamic>.from(sale['items'] ?? []);
    final invoiceNumber = sale['invoiceNumber']?.toString() ?? '-';
    final date = _date(sale['createdAt']);
    final customer = sale['customerSnapshot'] is Map
        ? Map<String, dynamic>.from(sale['customerSnapshot'] as Map)
        : <String, dynamic>{};
    final pageFormat = thermal
        ? PdfPageFormat(
            paperWidthMm * PdfPageFormat.mm,
            250 * PdfPageFormat.mm,
            marginAll: 4 * PdfPageFormat.mm,
          )
        : PdfPageFormat.a4;

    document.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(thermal ? 4 * PdfPageFormat.mm : 32),
        build: (context) => [
          if (thermal) ...[
            pw.Center(
              child: pw.Text(
                shopName.isEmpty ? 'SHOP' : shopName,
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Center(
              child: pw.Text(
                'SALES RECEIPT',
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Divider(),
          ] else ...[
            pw.Text(
              shopName.isEmpty ? 'ShopFlow' : shopName,
              style: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text('SALES INVOICE', style: pw.TextStyle(fontSize: 17)),
            pw.SizedBox(height: 18),
          ],
          if ((company?['address'] ?? '').toString().trim().isNotEmpty)
            pw.Text(company!['address'].toString()),
          if ((company?['phone'] ?? '').toString().trim().isNotEmpty)
            pw.Text('Phone: ${company!['phone']}'),
          if ((company?['email'] ?? '').toString().trim().isNotEmpty)
            pw.Text('Email: ${company!['email']}'),
          pw.Text('Invoice: $invoiceNumber'),
          pw.Text('Date: $date'),
          if ((customer['name'] ?? '').toString().trim().isNotEmpty) ...[
            pw.Text('Customer: ${customer['name']}'),
            if ((customer['phone'] ?? '').toString().trim().isNotEmpty)
              pw.Text('Phone: ${customer['phone']}'),
            if ((customer['address'] ?? '').toString().trim().isNotEmpty)
              pw.Text('Address: ${customer['address']}'),
          ],
          pw.Text('Payment: ${sale['paymentMethod'] ?? '-'}'),
          pw.Text('Status: ${sale['paymentStatus'] ?? 'PAID'}'),
          pw.SizedBox(height: 12),
          pw.Table(
            border: thermal
                ? null
                : pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: thermal
                ? {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1.5),
                  }
                : {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(1),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.5),
                  },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children:
                    (thermal
                            ? ['Item', 'Qty', 'Total']
                            : ['Product', 'Qty', 'Unit price', 'Total'])
                        .map(
                          (label) => pw.Padding(
                            padding: const pw.EdgeInsets.all(5),
                            child: pw.Text(
                              label,
                              style: pw.TextStyle(
                                fontWeight: pw.FontWeight.bold,
                                fontSize: thermal ? 8 : 10,
                              ),
                            ),
                          ),
                        )
                        .toList(),
              ),
              ...items.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final cells = thermal
                    ? [
                        item['name']?.toString() ?? '',
                        item['quantity']?.toString() ?? '0',
                        _money(item['lineTotal']),
                      ]
                    : [
                        item['name']?.toString() ?? '',
                        item['quantity']?.toString() ?? '0',
                        _money(item['unitPrice']),
                        _money(item['lineTotal']),
                      ];
                return pw.TableRow(
                  children: cells
                      .map(
                        (cell) => pw.Padding(
                          padding: const pw.EdgeInsets.all(5),
                          child: pw.Text(
                            cell,
                            style: pw.TextStyle(fontSize: thermal ? 7 : 9),
                          ),
                        ),
                      )
                      .toList(),
                );
              }),
            ],
          ),
          pw.SizedBox(height: 12),
          _pdfSummaryRow('Subtotal', sale['subtotal'], thermal),
          _pdfSummaryRow('Discount', sale['discountAmount'], thermal),
          pw.Divider(),
          _pdfSummaryRow('TOTAL', sale['totalAmount'], thermal, bold: true),
          _pdfSummaryRow('Amount paid', sale['amountPaid'], thermal),
          _pdfSummaryRow('Change', sale['changeAmount'], thermal),
          if ((sale['note'] ?? '').toString().trim().isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Note: ${sale['note']}', style: pw.TextStyle(fontSize: 8)),
          ],
          pw.SizedBox(height: 18),
          pw.Center(
            child: pw.Text(
              'Thank you for your business!',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontSize: thermal ? 9 : 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  static pw.Widget _pdfSummaryRow(
    String label,
    dynamic value,
    bool thermal, {
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      fontSize: thermal ? 8 : 10,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text(_money(value), style: style),
        ],
      ),
    );
  }

  static Future<void> printInvoice(
    Map<String, dynamic> sale, {
    required String shopName,
    Map<String, dynamic>? company,
    bool thermal = false,
    double paperWidthMm = 80,
  }) async {
    final bytes = await buildPdf(
      sale,
      shopName: shopName,
      company: company,
      thermal: thermal,
      paperWidthMm: paperWidthMm,
    );
    final format = thermal
        ? PdfPageFormat(paperWidthMm * PdfPageFormat.mm, 250 * PdfPageFormat.mm)
        : PdfPageFormat.a4;
    await Printing.layoutPdf(
      name: 'Invoice_${sale['invoiceNumber'] ?? 'ShopFlow'}',
      format: format,
      onLayout: (_) async => bytes,
    );
  }

  static Future<void> shareInvoice(
    Map<String, dynamic> sale, {
    required String shopName,
    Map<String, dynamic>? company,
  }) async {
    final bytes = await buildPdf(sale, shopName: shopName, company: company);
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Invoice_${sale['invoiceNumber'] ?? 'ShopFlow'}.pdf',
    );
  }
}

// =====================================================
// AUTHENTICATION SERVICE
// =====================================================

class AuthService {
  AuthService._() {
    dio = Dio(
      BaseOptions(
        baseUrl: apiUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.httpClientAdapter = BrowserHttpClientAdapter()..withCredentials = true;

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          final options = error.requestOptions;

          final shouldRefresh =
              error.response?.statusCode == 401 &&
              !options.path.contains('/auth/') &&
              options.extra['retry'] != true;

          if (!shouldRefresh) {
            return handler.next(error);
          }

          try {
            final refreshDio = Dio(BaseOptions(baseUrl: apiUrl));

            refreshDio.httpClientAdapter = BrowserHttpClientAdapter()
              ..withCredentials = true;

            final response = await refreshDio.post('/auth/refresh');

            final data = Map<String, dynamic>.from(response.data['data']);

            accessToken = data['accessToken'];

            options.headers['Authorization'] = 'Bearer $accessToken';

            options.extra['retry'] = true;

            final retryResponse = await dio.fetch(options);

            return handler.resolve(retryResponse);
          } catch (_) {
            accessToken = null;
            return handler.next(error);
          }
        },
      ),
    );
  }

  static final AuthService instance = AuthService._();

  late final Dio dio;

  String? accessToken;

  Options get authOptions =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});

  Future<Map<String, dynamic>> login({
    required String shopSlug,
    required String email,
    required String password,
  }) async {
    final response = await dio.post(
      '/auth/login',
      data: {'shopSlug': shopSlug, 'email': email, 'password': password},
    );

    final data = Map<String, dynamic>.from(response.data['data']);

    accessToken = data['accessToken'];

    return data;
  }


  Future<Map<String, dynamic>> registerShop({
    required String shopName,
    required String ownerName,
    required String email,
    required String phone,
    required String password,
    required String businessType,
  }) async {
    final response = await dio.post(
      '/auth/register',
      data: {
        'shopName': shopName,
        'ownerName': ownerName,
        'email': email,
        'phone': phone,
        'password': password,
        'businessType': businessType,
      },
    );
    final data = Map<String, dynamic>.from(response.data['data']);
    accessToken = data['accessToken']?.toString();
    return data;
  }

  Future<Map<String, dynamic>?> restoreSession() async {
    try {
      final response = await dio.post('/auth/refresh');

      final data = Map<String, dynamic>.from(response.data['data']);

      accessToken = data['accessToken'];

      return data;
    } catch (_) {
      accessToken = null;
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await dio.post('/auth/logout');
    } finally {
      accessToken = null;
    }
  }

  Future<List<dynamic>> getProducts({String search = ''}) async {
    final response = await dio.get(
      '/products',
      queryParameters: {if (search.isNotEmpty) 'search': search},
      options: authOptions,
    );

    return List<dynamic>.from(response.data['data']);
  }

  Future<List<dynamic>> getLowStock() async {
    final response = await dio.get('/products/low-stock', options: authOptions);

    return List<dynamic>.from(response.data['data']);
  }

  // Dashboard metrics are scoped by the authenticated tenant on the server.
  Future<Map<String, dynamic>> getDashboardSummary() async {
    final response = await dio.get(
      '/dashboard/summary',
      options: authOptions,
    );
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  Future<void> saveProduct(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await dio.post('/products', data: data, options: authOptions);
    } else {
      await dio.put('/products/$id', data: data, options: authOptions);
    }
  }

  Future<void> deleteProduct(String id) async {
    await dio.delete('/products/$id', options: authOptions);
  }


  // CUSTOMER MANAGEMENT
  Future<List<dynamic>> getCustomers({String search = ''}) async {
    final response = await dio.get(
      '/customers',
      queryParameters: {if (search.trim().isNotEmpty) 'search': search.trim()},
      options: authOptions,
    );
    return List<dynamic>.from(response.data['data'] ?? []);
  }

  Future<void> saveCustomer(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await dio.post('/customers', data: data, options: authOptions);
    } else {
      await dio.put('/customers/$id', data: data, options: authOptions);
    }
  }

  Future<void> deleteCustomer(String id) async {
    await dio.delete('/customers/$id', options: authOptions);
  }

  Future<List<dynamic>> getCustomerSales(String id) async {
    final response = await dio.get('/customers/$id/sales', options: authOptions);
    return List<dynamic>.from(response.data['data'] ?? []);
  }

  // COMPANY PROFILE
  Future<Map<String, dynamic>> getCompanySettings() async {
    final response = await dio.get('/company', options: authOptions);
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  Future<Map<String, dynamic>> saveCompanySettings(
    Map<String, dynamic> data,
  ) async {
    final response = await dio.put('/company', data: data, options: authOptions);
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  // GET SALES / INVOICE HISTORY
  Future<Map<String, dynamic>> getSales({
    int page = 1,
    int limit = 100,
    String search = '',
  }) async {
    final response = await dio.get(
      '/sales',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (search.trim().isNotEmpty) 'search': search.trim(),
      },
      options: authOptions,
    );

    return {
      'sales': List<dynamic>.from(response.data['data'] ?? []),
      'pagination': Map<String, dynamic>.from(
        response.data['pagination'] ?? {},
      ),
    };
  }

  // STAFF MANAGEMENT (owner only)
  Future<List<dynamic>> getStaff() async {
    final response = await dio.get('/staff', options: authOptions);
    return List<dynamic>.from(response.data['data'] ?? []);
  }

  Future<void> saveStaff(Map<String, dynamic> data, {String? id}) async {
    if (id == null) {
      await dio.post('/staff', data: data, options: authOptions);
    } else {
      await dio.put('/staff/$id', data: data, options: authOptions);
    }
  }

  Future<void> disableStaff(String id) async {
    await dio.delete('/staff/$id', options: authOptions);
  }

  Future<void> setStaffStatus(String id, String status) async {
    await dio.put('/staff/$id', data: {'status': status}, options: authOptions);
  }

  // REPORTS AND EXPENSES (owner / manager)
  Future<Map<String, dynamic>> getReport({String period = 'daily', DateTime? date}) async {
    final dateText = date == null ? null : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final response = await dio.get('/reports/summary', queryParameters: { 'period': period, if (dateText != null) 'date': dateText }, options: authOptions);
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  Future<void> createExpense(Map<String, dynamic> data) async {
    await dio.post('/reports/expenses', data: data, options: authOptions);
  }

  Future<Map<String, dynamic>> createSale({
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    required double amountPaid,
    double discountAmount = 0,
    String note = '',
    String? customerId,
  }) async {
    final response = await dio.post(
      '/sales',
      data: {
        'items': items,
        'paymentMethod': paymentMethod,
        'amountPaid': amountPaid,
        'discountAmount': discountAmount,
        'note': note,
        if (customerId != null && customerId.isNotEmpty) 'customerId': customerId,
      },
      options: authOptions,
    );

    return Map<String, dynamic>.from(response.data['data']);
  }
}


// =====================================================
// CUSTOMER MANAGEMENT
// =====================================================

class CustomerManagementPage extends StatefulWidget {
  const CustomerManagementPage({super.key});

  @override
  State<CustomerManagementPage> createState() => _CustomerManagementPageState();
}

class _CustomerManagementPageState extends State<CustomerManagementPage> {
  final searchController = TextEditingController();
  List<dynamic> customers = [];
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadCustomers();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadCustomers({String search = ''}) async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final result = await AuthService.instance.getCustomers(search: search);
      if (!mounted) return;
      setState(() {
        customers = result;
        loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = e.response?.data?['message']?.toString() ??
            'Unable to load customers';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Unable to load customers';
      });
    }
  }

  Future<void> showCustomerDialog({Map<String, dynamic>? customer}) async {
    final name = TextEditingController(text: customer?['name']?.toString() ?? '');
    final phone = TextEditingController(text: customer?['phone']?.toString() ?? '');
    final email = TextEditingController(text: customer?['email']?.toString() ?? '');
    final address = TextEditingController(text: customer?['address']?.toString() ?? '');
    final notes = TextEditingController(text: customer?['notes']?.toString() ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(customer == null ? 'Add Customer' : 'Edit Customer'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Customer name *',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Customer name is required'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: address,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: notes,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              try {
                await AuthService.instance.saveCustomer({
                  'name': name.text.trim(),
                  'phone': phone.text.trim(),
                  'email': email.text.trim(),
                  'address': address.text.trim(),
                  'notes': notes.text.trim(),
                }, id: customer?['_id']?.toString());
                if (dialogContext.mounted) Navigator.pop(dialogContext, true);
              } catch (_) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to save customer')),
                );
              }
            },
            child: const Text('Save Customer'),
          ),
        ],
      ),
    );

    for (final c in [name, phone, email, address, notes]) {
      c.dispose();
    }
    if (saved == true && mounted) {
      await loadCustomers(search: searchController.text);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer saved successfully')),
      );
    }
  }

  Future<void> deleteCustomer(Map<String, dynamic> customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Delete ${customer['name']}? Past invoices will be retained.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AuthService.instance.deleteCustomer(customer['_id'].toString());
      await loadCustomers(search: searchController.text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to delete customer')),
        );
      }
    }
  }

  Future<void> showCustomerHistory(Map<String, dynamic> customer) async {
    try {
      final sales = await AuthService.instance.getCustomerSales(
        customer['_id'].toString(),
      );
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${customer['name']} – Purchase History'),
          content: SizedBox(
            width: 520,
            child: sales.isEmpty
                ? const Text('No purchases recorded for this customer yet.')
                : SizedBox(
                    height: 420,
                    child: ListView.builder(
                      itemCount: sales.length,
                      itemBuilder: (context, index) {
                        final sale = Map<String, dynamic>.from(sales[index] as Map);
                        return ListTile(
                          leading: const Icon(Icons.receipt_long),
                          title: Text(sale['invoiceNumber']?.toString() ?? '-'),
                          subtitle: Text(
                            DateTime.tryParse(sale['createdAt']?.toString() ?? '')
                                    ?.toLocal()
                                    .toString() ??
                                '-',
                          ),
                          trailing: Text(
                            'LKR ${((sale['totalAmount'] as num?) ?? 0).toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to load customer history')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Customer Management',
                        style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                    SizedBox(height: 5),
                    Text('Manage customers and view their purchase history',
                        style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => showCustomerDialog(),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add Customer'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: searchController,
            onSubmitted: (value) => loadCustomers(search: value),
            decoration: InputDecoration(
              hintText: 'Search name, phone or email...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () {
                  searchController.clear();
                  loadCustomers();
                },
                icon: const Icon(Icons.clear),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(errorMessage!),
                            TextButton(
                              onPressed: () => loadCustomers(search: searchController.text),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : customers.isEmpty
                        ? const Center(child: Text('No customers found. Add your first customer.'))
                        : ListView.separated(
                            itemCount: customers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final customer = Map<String, dynamic>.from(customers[index] as Map);
                              return Card(
                                child: ListTile(
                                  leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                                  title: Text(customer['name']?.toString() ?? '',
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text([
                                    customer['phone']?.toString() ?? '',
                                    customer['email']?.toString() ?? '',
                                  ].where((v) => v.isNotEmpty).join(' • ')),
                                  onTap: () => showCustomerHistory(customer),
                                  trailing: Wrap(
                                    spacing: 0,
                                    children: [
                                      IconButton(
                                        tooltip: 'Purchase history',
                                        onPressed: () => showCustomerHistory(customer),
                                        icon: const Icon(Icons.history),
                                      ),
                                      IconButton(
                                        tooltip: 'Edit',
                                        onPressed: () => showCustomerDialog(customer: customer),
                                        icon: const Icon(Icons.edit_outlined, color: primaryBlue),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        onPressed: () => deleteCustomer(customer),
                                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// COMPANY SETTINGS
// =====================================================

class CompanySettingsPage extends StatefulWidget {
  const CompanySettingsPage({super.key});

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage> {
  final shopName = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final address = TextEditingController();
  final logoUrl = TextEditingController();
  final website = TextEditingController();

  bool loading = true;
  bool saving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadSettings();
  }

  @override
  void dispose() {
    for (final c in [shopName, email, phone, address, logoUrl, website]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> loadSettings() async {
    try {
      final data = await AuthService.instance.getCompanySettings();
      if (!mounted) return;
      shopName.text = data['shopName']?.toString() ?? '';
      email.text = data['email']?.toString() ?? '';
      phone.text = data['phone']?.toString() ?? '';
      address.text = data['address']?.toString() ?? '';
      logoUrl.text = data['logoUrl']?.toString() ?? '';
      website.text = data['website']?.toString() ?? '';
      setState(() => loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Unable to load company settings';
      });
    }
  }

  Future<void> saveSettings() async {
    if (shopName.text.trim().isEmpty || email.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shop name and business email are required')),
      );
      return;
    }
    setState(() => saving = true);
    try {
      await AuthService.instance.saveCompanySettings({
        'shopName': shopName.text.trim(),
        'email': email.text.trim(),
        'phone': phone.text.trim(),
        'address': address.text.trim(),
        'logoUrl': logoUrl.text.trim(),
        'website': website.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Company settings saved successfully')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save company settings')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(TextEditingController controller, String label,
      {int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (errorMessage != null) return Center(child: Text(errorMessage!));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Company Settings',
                      style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('These details belong to the currently signed-in shop.',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 22),
                  field(shopName, 'Shop / Company Name'),
                  field(phone, 'Contact Number', keyboardType: TextInputType.phone),
                  field(email, 'Business Email', keyboardType: TextInputType.emailAddress),
                  field(address, 'Business Address', maxLines: 3),
                  field(website, 'Website'),
                  field(logoUrl, 'Company Logo URL'),
                  if (logoUrl.text.trim().isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 80,
                        width: 140,
                        child: Image.network(
                          logoUrl.text.trim(),
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Text('Logo preview unavailable'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: saving ? null : saveSettings,
                      icon: saving
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: Text(saving ? 'Saving...' : 'Save Settings'),
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
}


class InvoiceHistoryPage extends StatefulWidget {
  final String shopName;

  const InvoiceHistoryPage({super.key, required this.shopName});

  @override
  State<InvoiceHistoryPage> createState() => _InvoiceHistoryPageState();
}

class _InvoiceHistoryPageState extends State<InvoiceHistoryPage> {
  final searchController = TextEditingController();

  List<dynamic> sales = [];
  Map<String, dynamic> company = {};

  bool loading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    loadSales();
    loadCompany();
  }

  Future<void> loadCompany() async {
    try {
      final result = await AuthService.instance.getCompanySettings();
      if (mounted) setState(() => company = result);
    } catch (_) {
      // Company header falls back to the shop name if settings are unavailable.
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadSales({String search = ''}) async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final result = await AuthService.instance.getSales(search: search);

      if (!mounted) return;

      setState(() {
        sales = result['sales'] as List<dynamic>;
        loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage =
            e.response?.data?['message']?.toString() ??
            'Unable to load invoice history';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage = 'Something went wrong';
      });
    }
  }

  String money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;

    return 'Rs. ${amount.toStringAsFixed(2)}';
  }

  String formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');

    if (date == null) return '-';

    final d = date.toLocal();

    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> printInvoice(
    Map<String, dynamic> sale, {
    bool thermal = false,
    double paperWidthMm = 80,
  }) async {
    try {
      await InvoicePrintService.printInvoice(
        sale,
        shopName: company['shopName']?.toString() ?? widget.shopName,
        company: company,
        thermal: thermal,
        paperWidthMm: paperWidthMm,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unable to print invoice: $e')));
      }
    }
  }

  Future<void> downloadInvoice(Map<String, dynamic> sale) async {
    try {
      await InvoicePrintService.shareInvoice(
        sale,
        shopName: company['shopName']?.toString() ?? widget.shopName,
        company: company,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to create invoice PDF: $e')),
        );
      }
    }
  }

  void showInvoice(Map<String, dynamic> sale) {
    final items = (sale['items'] as List?) ?? [];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invoice Details'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sale['invoiceNumber']?.toString() ?? '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text('Date: ${formatDate(sale['createdAt'])}'),
                if (sale['customerSnapshot'] is Map &&
                    (sale['customerSnapshot']['name'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Customer: ${sale['customerSnapshot']['name']}'),
                  if ((sale['customerSnapshot']['phone'] ?? '').toString().isNotEmpty)
                    Text('Phone: ${sale['customerSnapshot']['phone']}'),
                  if ((sale['customerSnapshot']['address'] ?? '').toString().isNotEmpty)
                    Text('Address: ${sale['customerSnapshot']['address']}'),
                ],
                Text('Payment: ${sale['paymentMethod'] ?? '-'}'),
                Text('Status: ${sale['paymentStatus'] ?? '-'}'),
                const Divider(height: 24),
                const Text(
                  'Products',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ...items.map((rawItem) {
                  final item = Map<String, dynamic>.from(rawItem as Map);

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${item['name']} × ${item['quantity']}'),
                        ),
                        Text(money(item['lineTotal'])),
                      ],
                    ),
                  );
                }),
                const Divider(height: 24),
                _invoiceRow('Subtotal', sale['subtotal']),
                _invoiceRow('Discount', sale['discountAmount']),
                const Divider(),
                _invoiceRow('Total Amount', sale['totalAmount'], bold: true),
                _invoiceRow('Amount Paid', sale['amountPaid']),
                _invoiceRow('Change', sale['changeAmount']),
                if ((sale['note'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Note: ${sale['note']}'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => downloadInvoice(sale),
            child: const Text('PDF'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Print invoice',
            onSelected: (choice) {
              if (choice == 'a4') {
                printInvoice(sale);
              } else if (choice == '80') {
                printInvoice(sale, thermal: true, paperWidthMm: 80);
              } else if (choice == '58') {
                printInvoice(sale, thermal: true, paperWidthMm: 58);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'a4', child: Text('Print A4 invoice')),
              PopupMenuItem(value: '80', child: Text('Print 80mm receipt')),
              PopupMenuItem(value: '58', child: Text('Print 58mm receipt')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text('Print'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _invoiceRow(String label, dynamic value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            money(value),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSales = sales.fold<double>(0, (sum, raw) {
      final sale = Map<String, dynamic>.from(raw as Map);
      final amount = sale['totalAmount'];

      return sum +
          (amount is num
              ? amount.toDouble()
              : double.tryParse(amount?.toString() ?? '') ?? 0);
    });

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Invoice History',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          const Text(
            'View and manage your shop sales invoices',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Invoices'),
                        Text(
                          '${sales.length}',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Sales Total'),
                        Text(
                          money(totalSales),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  onSubmitted: (value) => loadSales(search: value),
                  decoration: const InputDecoration(
                    hintText: 'Search invoice number...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Search',
                onPressed: () => loadSales(search: searchController.text),
                icon: const Icon(Icons.search),
              ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => loadSales(search: searchController.text),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(errorMessage!),
                        const SizedBox(height: 10),
                        ElevatedButton(
                          onPressed: () => loadSales(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : sales.isEmpty
                ? const Center(child: Text('No invoices found'))
                : RefreshIndicator(
                    onRefresh: () => loadSales(search: searchController.text),
                    child: ListView.builder(
                      itemCount: sales.length,
                      itemBuilder: (context, index) {
                        final sale = Map<String, dynamic>.from(
                          sales[index] as Map,
                        );

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.receipt_long),
                            ),
                            title: Text(
                              sale['invoiceNumber']?.toString() ?? '-',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${formatDate(sale['createdAt'])}\n'
                              '${sale['paymentMethod'] ?? '-'} '
                              '• ${sale['paymentStatus'] ?? '-'}',
                            ),
                            isThreeLine: true,
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  money(sale['totalAmount']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: primaryBlue,
                                  ),
                                ),
                                const Text(
                                  'View Invoice',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ],
                            ),
                            onTap: () => showInvoice(sale),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// MAIN APPLICATION
// =====================================================

void main() {
  runApp(const ShopFlowApp());
}

class ShopFlowApp extends StatefulWidget {
  const ShopFlowApp({super.key});

  @override
  State<ShopFlowApp> createState() => _ShopFlowAppState();
}

class _ShopFlowAppState extends State<ShopFlowApp> {
  bool checkingSession = true;

  String? token;
  String? userName;
  String? userEmail;
  String? userRole;
  String? shopName;
  String? shopSlug;

  @override
  void initState() {
    super.initState();
    restoreLogin();
  }

  Future<void> restoreLogin() async {
    final result = await AuthService.instance.restoreSession();

    if (!mounted) return;

    if (result != null) {
      final user = Map<String, dynamic>.from(result['user']);
      final shop = Map<String, dynamic>.from(result['shop']);

      token = AuthService.instance.accessToken;
      userName = user['name'];
      userEmail = user['email'];
      userRole = user['role'];
      shopName = shop['shopName'];
      shopSlug = shop['slug'];
    }

    setState(() {
      checkingSession = false;
    });
  }

  Future<void> handleLogin(String shopId, String email, String password) async {
    final result = await AuthService.instance.login(
      shopSlug: shopId,
      email: email,
      password: password,
    );

    final user = Map<String, dynamic>.from(result['user']);
    final shop = Map<String, dynamic>.from(result['shop']);

    if (!mounted) return;

    setState(() {
      token = AuthService.instance.accessToken;
      userName = user['name'];
      userEmail = user['email'];
      userRole = user['role'];
      shopName = shop['shopName'];
      shopSlug = shop['slug'];
    });
  }


  Future<void> handleRegistration(Map<String, dynamic> details) async {
    final result = await AuthService.instance.registerShop(
      shopName: details['shopName'] as String,
      ownerName: details['ownerName'] as String,
      email: details['email'] as String,
      phone: details['phone'] as String,
      password: details['password'] as String,
      businessType: details['businessType'] as String,
    );

    final user = Map<String, dynamic>.from(result['user']);
    final shop = Map<String, dynamic>.from(result['shop']);

    if (!mounted) return;

    setState(() {
      token = AuthService.instance.accessToken;
      userName = user['name']?.toString();
      userEmail = user['email']?.toString();
      userRole = user['role']?.toString();
      shopName = shop['shopName']?.toString();
      shopSlug = shop['slug']?.toString();
    });
  }

  Future<void> handleLogout() async {
    await AuthService.instance.logout();

    if (!mounted) return;

    setState(() {
      token = null;
      userName = null;
      userEmail = null;
      userRole = null;
      shopName = null;
      shopSlug = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopFlow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: primaryBlue,
        scaffoldBackgroundColor: backgroundColor,
        fontFamily: 'Arial',
      ),
      home: checkingSession
          ? const LoadingPage()
          : token != null
          ? DashboardPage(
              userName: userName ?? '',
              userEmail: userEmail ?? '',
              role: userRole ?? '',
              shopName: shopName ?? '',
              shopSlug: shopSlug ?? '',
              onLogout: handleLogout,
            )
          : LoginPage(
              onLogin: handleLogin,
              onRegister: handleRegistration,
            ),
    );
  }
}

// =====================================================
// LOADING PAGE
// =====================================================

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, color: primaryBlue, size: 55),
            SizedBox(height: 20),
            CircularProgressIndicator(),
            SizedBox(height: 15),
            Text('Restoring your ShopFlow session...'),
          ],
        ),
      ),
    );
  }
}

// =====================================================
// LOGIN PAGE
// =====================================================

class LoginPage extends StatefulWidget {
  final Future<void> Function(String shopId, String email, String password)
  onLogin;
  final Future<void> Function(Map<String, dynamic> details) onRegister;

  const LoginPage({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final shopController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  bool obscurePassword = true;
  String? errorMessage;

  Future<void> login() async {
    if (shopController.text.trim().isEmpty ||
        emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      setState(() {
        errorMessage = 'Please complete all fields.';
      });
      return;
    }

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      await widget.onLogin(
        shopController.text.trim(),
        emailController.text.trim(),
        passwordController.text,
      );
    } on DioException catch (e) {
      final data = e.response?.data;

      setState(() {
        errorMessage = data is Map
            ? data['message']?.toString() ?? 'Login failed'
            : 'Cannot connect to ShopFlow server.';
      });
    } catch (_) {
      setState(() {
        errorMessage = 'Login failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Widget loginField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool password = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 9),
        TextField(
          controller: controller,
          obscureText: password && obscurePassword,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            prefixIcon: Icon(icon),
            suffixIcon: password
                ? IconButton(
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    shopController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Container(
              padding: const EdgeInsets.all(36),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .05),
                    blurRadius: 30,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    size: 65,
                    color: primaryBlue,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'ShopFlow',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: darkNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Manage your business smarter.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 35),
                  loginField(
                    label: 'Shop ID',
                    icon: Icons.store_outlined,
                    controller: shopController,
                  ),
                  const SizedBox(height: 20),
                  loginField(
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    controller: emailController,
                  ),
                  const SizedBox(height: 20),
                  loginField(
                    label: 'Password',
                    icon: Icons.lock_outline,
                    controller: passwordController,
                    password: true,
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 30),
                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed: loading ? null : login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: loading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Sign In',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RegistrationPage(
                            onRegister: widget.onRegister,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add_business_outlined),
                    label: const Text("New to ShopFlow? Create your shop"),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Secure Business Management Platform',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// =====================================================
// PUBLIC SHOP REGISTRATION
// =====================================================

class RegistrationPage extends StatefulWidget {
  final Future<void> Function(Map<String, dynamic> details) onRegister;

  const RegistrationPage({super.key, required this.onRegister});

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final shopNameController = TextEditingController();
  final ownerNameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  String businessType = 'general';
  bool loading = false;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  String? errorMessage;

  @override
  void dispose() {
    shopNameController.dispose();
    ownerNameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> submitRegistration() async {
    final shopName = shopNameController.text.trim();
    final ownerName = ownerNameController.text.trim();
    final email = emailController.text.trim().toLowerCase();
    final phone = phoneController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (shopName.isEmpty || ownerName.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => errorMessage = 'Please complete all required fields.');
      return;
    }

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => errorMessage = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 8) {
      setState(() => errorMessage = 'Password must contain at least 8 characters.');
      return;
    }

    if (password != confirmPassword) {
      setState(() => errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      await widget.onRegister({
        'shopName': shopName,
        'ownerName': ownerName,
        'email': email,
        'phone': phone,
        'password': password,
        'businessType': businessType,
      });
      // The app root has switched to the authenticated dashboard.
      if (mounted) Navigator.of(context).pop();
    } on DioException catch (error) {
      final data = error.response?.data;
      if (mounted) {
        setState(() {
          errorMessage = data is Map
              ? data['message']?.toString() ?? 'Registration failed.'
              : 'Cannot connect to ShopFlow server.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => errorMessage = 'Registration failed. Please try again.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Widget buildField({
    required String label,
    required IconData icon,
    required TextEditingController controller,
    bool requiredField = false,
    bool password = false,
    bool obscure = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          requiredField ? '$label *' : label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            prefixIcon: Icon(icon),
            suffixIcon: password
                ? IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                  )
                : null,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create your ShopFlow account'),
        backgroundColor: backgroundColor,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .05),
                    blurRadius: 25,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    color: primaryBlue,
                    size: 54,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Create Your Shop',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                      color: darkNavy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Register your business and start using ShopFlow.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 26),
                  buildField(
                    label: 'Shop / Business Name',
                    icon: Icons.store_outlined,
                    controller: shopNameController,
                    requiredField: true,
                  ),
                  const SizedBox(height: 16),
                  buildField(
                    label: 'Owner Full Name',
                    icon: Icons.person_outline,
                    controller: ownerNameController,
                    requiredField: true,
                  ),
                  const SizedBox(height: 16),
                  buildField(
                    label: 'Email Address',
                    icon: Icons.email_outlined,
                    controller: emailController,
                    requiredField: true,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  buildField(
                    label: 'Phone Number',
                    icon: Icons.phone_outlined,
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Business Type',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: businessType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'general', child: Text('General Retail')),
                      DropdownMenuItem(value: 'grocery', child: Text('Grocery')),
                      DropdownMenuItem(value: 'electronics', child: Text('Electronics')),
                      DropdownMenuItem(value: 'fashion', child: Text('Fashion')),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
                    ],
                    onChanged: loading
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => businessType = value);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  buildField(
                    label: 'Password',
                    icon: Icons.lock_outline,
                    controller: passwordController,
                    requiredField: true,
                    password: true,
                    obscure: obscurePassword,
                    onToggleObscure: () {
                      setState(() => obscurePassword = !obscurePassword);
                    },
                  ),
                  const SizedBox(height: 16),
                  buildField(
                    label: 'Confirm Password',
                    icon: Icons.lock_reset_outlined,
                    controller: confirmPasswordController,
                    requiredField: true,
                    password: true,
                    obscure: obscureConfirmPassword,
                    onToggleObscure: () {
                      setState(() {
                        obscureConfirmPassword = !obscureConfirmPassword;
                      });
                    },
                  ),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: loading ? null : submitRegistration,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              height: 21,
                              width: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'CREATE MY SHOP',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your shop and owner account will be created immediately.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// DASHBOARD
// =====================================================

class DashboardPage extends StatefulWidget {
  final String userName;
  final String userEmail;
  final String role;
  final String shopName;
  final String shopSlug;
  final Future<void> Function() onLogout;

  const DashboardPage({
    super.key,
    required this.userName,
    required this.userEmail,
    required this.role,
    required this.shopName,
    required this.shopSlug,
    required this.onLogout,
  });

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int selectedIndex = 0;

  final searchController = TextEditingController();

  bool productsLoading = false;
  String? productsError;

  List<dynamic> products = [];
  List<dynamic> lowStockProducts = [];

  bool dashboardLoading = true;
  String? dashboardError;
  Map<String, dynamic> dashboardData = {};
  List<dynamic> dashboardRecentSales = [];
  List<dynamic> dashboardWeeklySales = [];

  final List<Map<String, dynamic>> menuItems = [
    {'name': 'Dashboard', 'icon': Icons.dashboard_outlined},
    {'name': 'Products', 'icon': Icons.inventory_2_outlined},
    {'name': 'Sales & POS', 'icon': Icons.point_of_sale},
    {'name': 'Inventory', 'icon': Icons.warehouse_outlined},
    {'name': 'Customers', 'icon': Icons.people_outline},
    {'name': 'Suppliers', 'icon': Icons.local_shipping_outlined},
    {'name': 'Purchases', 'icon': Icons.shopping_bag_outlined},
    {'name': 'Expenses', 'icon': Icons.account_balance_wallet_outlined},
    {'name': 'Reports', 'icon': Icons.analytics_outlined},
    {'name': 'Staff', 'icon': Icons.groups_outlined},
    {'name': 'Settings', 'icon': Icons.settings_outlined},
    {'name': 'Invoice History', 'icon': Icons.receipt_long},
  ];

  @override
  void initState() {
    super.initState();
    if (widget.role == 'cashier') selectedIndex = 2;
    loadProducts();
    loadDashboard();
  }

  Future<void> loadDashboard() async {
    if (mounted) {
      setState(() {
        dashboardLoading = true;
        dashboardError = null;
      });
    }

    try {
      final result = await AuthService.instance.getDashboardSummary();
      if (!mounted) return;
      setState(() {
        dashboardData = Map<String, dynamic>.from(result);
        dashboardRecentSales =
            List<dynamic>.from(result['recentSales'] ?? []);
        dashboardWeeklySales =
            List<dynamic>.from(result['weeklySales'] ?? []);
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        dashboardError = e.response?.data is Map
            ? e.response?.data['message']?.toString() ??
                'Unable to load dashboard data.'
            : 'Cannot connect to ShopFlow server.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => dashboardError = 'Unable to load dashboard data.');
    } finally {
      if (mounted) setState(() => dashboardLoading = false);
    }
  }

  String dashboardMoney(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return 'LKR ${amount.toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadProducts({String search = ''}) async {
    setState(() {
      productsLoading = true;
      productsError = null;
    });

    try {
      final result = await AuthService.instance.getProducts(search: search);

      final lowStock = await AuthService.instance.getLowStock();

      if (!mounted) return;

      setState(() {
        products = result;
        lowStockProducts = lowStock;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        productsError = 'Unable to load products. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => productsLoading = false);
      }
    }
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> showProductDialog({Map<String, dynamic>? product}) async {
    final name = TextEditingController(
      text: product?['name']?.toString() ?? '',
    );
    final sku = TextEditingController(text: product?['sku']?.toString() ?? '');
    final barcode = TextEditingController(
      text: product?['barcode']?.toString() ?? '',
    );
    final category = TextEditingController(
      text: product?['category']?.toString() ?? '',
    );
    final brand = TextEditingController(
      text: product?['brand']?.toString() ?? '',
    );
    final purchase = TextEditingController(
      text: product?['purchasePrice']?.toString() ?? '',
    );
    final selling = TextEditingController(
      text: product?['sellingPrice']?.toString() ?? '',
    );
    final stock = TextEditingController(
      text: product?['stockQuantity']?.toString() ?? '0',
    );
    final minimum = TextEditingController(
      text: product?['minStockLevel']?.toString() ?? '5',
    );
    final unit = TextEditingController(
      text: product?['unit']?.toString() ?? 'pcs',
    );
    final description = TextEditingController(
      text: product?['description']?.toString() ?? '',
    );

    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(product == null ? 'Add New Product' : 'Edit Product'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    formInput(name, 'Product Name'),
                    formInput(sku, 'SKU'),
                    formInput(barcode, 'Barcode'),
                    formInput(category, 'Category'),
                    formInput(brand, 'Brand'),
                    formInput(purchase, 'Purchase Price', numeric: true),
                    formInput(selling, 'Selling Price', numeric: true),
                    formInput(stock, 'Stock Quantity', numeric: true),
                    formInput(minimum, 'Minimum Stock', numeric: true),
                    formInput(unit, 'Unit'),
                    formInput(description, 'Description'),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final data = {
                  'name': name.text.trim(),
                  'sku': sku.text.trim(),
                  'barcode': barcode.text.trim(),
                  'category': category.text.trim(),
                  'brand': brand.text.trim(),
                  'purchasePrice': double.tryParse(purchase.text) ?? 0,
                  'sellingPrice': double.tryParse(selling.text) ?? 0,
                  'stockQuantity': double.tryParse(stock.text) ?? 0,
                  'minStockLevel': double.tryParse(minimum.text) ?? 5,
                  'unit': unit.text.trim(),
                  'description': description.text.trim(),
                };

                try {
                  await AuthService.instance.saveProduct(
                    data,
                    id: product?['_id']?.toString(),
                  );

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } catch (e) {
                  showMessage('Unable to save product. Check SKU and values.');
                }
              },
              child: const Text('Save Product'),
            ),
          ],
        );
      },
    );

    for (final controller in [
      name,
      sku,
      barcode,
      category,
      brand,
      purchase,
      selling,
      stock,
      minimum,
      unit,
      description,
    ]) {
      controller.dispose();
    }

    if (saved == true && mounted) {
      await loadProducts(search: searchController.text);
      showMessage('Product saved successfully');
    }
  }

  Widget formInput(
    TextEditingController controller,
    String label, {
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        validator: (value) {
          if (['Product Name', 'SKU', 'Category'].contains(label) &&
              (value == null || value.trim().isEmpty)) {
            return '$label is required';
          }

          if (numeric &&
              (value == null ||
                  double.tryParse(value) == null ||
                  double.parse(value) < 0)) {
            return 'Enter a valid value';
          }

          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> deleteProduct(Map<String, dynamic> product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete ${product['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await AuthService.instance.deleteProduct(product['_id'].toString());

      await loadProducts(search: searchController.text);

      showMessage('Product deleted successfully');
    } catch (_) {
      showMessage('Unable to delete product');
    }
  }

  Future<void> logout() async {
    await widget.onLogout();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = constraints.maxWidth < 850;

        return Scaffold(
          drawer: mobile ? Drawer(child: buildSidebar()) : null,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: mobile
                ? Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  )
                : null,
            title: Row(
              children: [
                if (!mobile) const Icon(Icons.storefront, color: primaryBlue),
                const SizedBox(width: 10),
                const Text(
                  'ShopFlow',
                  style: TextStyle(
                    color: darkNavy,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_none),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CircleAvatar(
                  backgroundColor: const Color(0xFFDBEAFE),
                  child: Text(
                    widget.userName.isNotEmpty
                        ? widget.userName[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: primaryBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Row(
            children: [
              if (!mobile) SizedBox(width: 245, child: buildSidebar()),
              Expanded(
                child: selectedIndex == 0
                    ? buildDashboard()
                    : selectedIndex == 1
                    ? buildProductsPage()
                    : selectedIndex == 2
                    ? PosPage(
                        shopName: widget.shopName,
                        onSaleCompleted: () async {
                          await loadProducts();
                          await loadDashboard();
                        },
                      )
                    : selectedIndex == 4
                    ? const CustomerManagementPage()
                    : selectedIndex == 10
                    ? const CompanySettingsPage()
                    : selectedIndex == 11
                    ? InvoiceHistoryPage(shopName: widget.shopName)
                    : selectedIndex == 9 && widget.role == 'owner'
                    ? const StaffManagementPage()
                    : (selectedIndex == 8 || selectedIndex == 7) && (widget.role == 'owner' || widget.role == 'manager')
                    ? const ReportsPage()
                    : buildPlaceholder(menuItems[selectedIndex]['name']),
              ),
            ],
          ),
        );
      },
    );
  }

  // =================================================
  // SIDEBAR
  // =================================================

  Widget buildSidebar() {
    return Container(
      color: darkNavy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 24, 22, 12),
            child: Text(
              'MAIN MENU',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(
            child: Builder(
              builder: (context) {
                final visibleIndexes = List<int>.generate(menuItems.length, (i) => i).where((i) {
                  if (widget.role == 'owner') return true;
                  if (widget.role == 'manager') return ![9, 10].contains(i);
                  return [2, 4, 11].contains(i);
                }).toList();
                return ListView.builder(
              itemCount: visibleIndexes.length,
              itemBuilder: (context, displayIndex) {
                final index = visibleIndexes[displayIndex];
                final selected = selectedIndex == index;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 3,
                  ),
                  child: ListTile(
                    selected: selected,
                    selectedTileColor: primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    leading: Icon(
                      menuItems[index]['icon'],
                      color: selected ? Colors.white : Colors.white70,
                      size: 21,
                    ),
                    title: Text(
                      menuItems[index]['name'],
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.white70,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                    onTap: () {
                      setState(() => selectedIndex = index);

                      if (index == 0) {
                        loadDashboard();
                      }

                      if (index == 1) {
                        loadProducts();
                      }

                      if (Scaffold.of(context).isDrawerOpen) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                );
              },
            );
              },
            ),
          ),
          const Divider(color: Colors.white24),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF334155),
                  child: Icon(Icons.person, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.userName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        widget.role.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: logout,
                  icon: const Icon(Icons.logout, color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =================================================
  // DASHBOARD OVERVIEW
  // =================================================

  Widget buildDashboard() {
    final todayRevenue = dashboardData['todayRevenue'] ?? 0;
    final totalProducts = dashboardData['totalProducts'] ?? 0;
    final totalCustomers = dashboardData['totalCustomers'] ?? 0;
    final lowStockCount = dashboardData['lowStockCount'] ?? 0;

    return RefreshIndicator(
      onRefresh: loadDashboard,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 12,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dashboard Overview',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: darkNavy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Welcome back, ${widget.userName}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      'Shop ID: ${widget.shopSlug}',
                      style: const TextStyle(
                        color: primaryBlue,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.store, size: 17),
                      label: Text(widget.shopName),
                      backgroundColor: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Refresh dashboard',
                      onPressed: loadDashboard,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (dashboardError != null)
              Card(
                color: const Color(0xFFFFF7ED),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, color: Colors.deepOrange),
                      const SizedBox(width: 10),
                      Expanded(child: Text(dashboardError!)),
                      TextButton(
                        onPressed: loadDashboard,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 1000
                    ? 4
                    : constraints.maxWidth > 550
                        ? 2
                        : 1;
                final width =
                    (constraints.maxWidth - (columns - 1) * 16) / columns;

                return Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: width,
                      child: StatCard(
                        title: "Today's Sales",
                        value: dashboardLoading
                            ? 'Loading...'
                            : dashboardMoney(todayRevenue),
                        change:
                            '${dashboardData['todayInvoiceCount'] ?? 0} invoices today',
                        icon: Icons.trending_up,
                        color: const Color(0xFF2563EB),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: StatCard(
                        title: 'Total Products',
                        value: dashboardLoading
                            ? 'Loading...'
                            : totalProducts.toString(),
                        change: 'Active products in this shop',
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFF8B5CF6),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: StatCard(
                        title: 'Total Customers',
                        value: dashboardLoading
                            ? 'Loading...'
                            : totalCustomers.toString(),
                        change: 'Active customer records',
                        icon: Icons.people_outline,
                        color: const Color(0xFF0891B2),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: StatCard(
                        title: 'Low Stock Items',
                        value: dashboardLoading
                            ? 'Loading...'
                            : lowStockCount.toString(),
                        change: 'Needs attention',
                        icon: Icons.warning_amber_rounded,
                        color: const Color(0xFFEA580C),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth > 850;
                final chart = SalesChart(salesByDay: dashboardWeeklySales);
                final lowStock = LowStockCard(products: lowStockProducts);

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: chart),
                      const SizedBox(width: 18),
                      Expanded(flex: 2, child: lowStock),
                    ],
                  );
                }

                return Column(
                  children: [
                    chart,
                    const SizedBox(height: 18),
                    lowStock,
                  ],
                );
              },
            ),
            const SizedBox(height: 26),
            RecentTransactions(
              sales: dashboardRecentSales,
              loading: dashboardLoading,
            ),
            const SizedBox(height: 30),
            const Center(
              child: Text(
                'ShopFlow Business Management Platform',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =================================================
  // PRODUCTS MANAGEMENT
  // =================================================

  Widget buildProductsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 15,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Products Management',
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      color: darkNavy,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Manage your shop products and inventory',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: () => showProductDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 25),

          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFFE8EDF5)),
            ),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  onSubmitted: (value) => loadProducts(search: value),
                  decoration: InputDecoration(
                    hintText: 'Search by product, SKU or barcode...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        searchController.clear();
                        loadProducts();
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                if (productsLoading)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: CircularProgressIndicator(),
                  )
                else if (productsError != null)
                  Column(
                    children: [
                      Text(productsError!),
                      TextButton(
                        onPressed: () => loadProducts(),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                else if (products.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(30),
                    child: Text('No products found.'),
                  )
                else
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFF8FAFC),
                      ),
                      columns: const [
                        DataColumn(label: Text('Product')),
                        DataColumn(label: Text('SKU')),
                        DataColumn(label: Text('Category')),
                        DataColumn(label: Text('Purchase')),
                        DataColumn(label: Text('Selling')),
                        DataColumn(label: Text('Stock')),
                        DataColumn(label: Text('Actions')),
                      ],
                      rows: products.map((item) {
                        final product = Map<String, dynamic>.from(item);

                        final stock = product['stockQuantity'] ?? 0;

                        final minimum = product['minStockLevel'] ?? 5;

                        final low = (stock as num) <= (minimum as num);

                        return DataRow(
                          cells: [
                            DataCell(Text(product['name'] ?? '')),
                            DataCell(Text(product['sku'] ?? '')),
                            DataCell(Text(product['category'] ?? '')),
                            DataCell(Text('LKR ${product['purchasePrice']}')),
                            DataCell(
                              Text(
                                'LKR ${product['sellingPrice']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryBlue,
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: low
                                      ? const Color(0xFFFEE2E2)
                                      : const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  stock.toString(),
                                  style: TextStyle(
                                    color: low ? Colors.red : Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Edit',
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: primaryBlue,
                                    ),
                                    onPressed: () =>
                                        showProductDialog(product: product),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => deleteProduct(product),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '${products.length} products displayed',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget buildPlaceholder(String title) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.construction_outlined, size: 60, color: primaryBlue),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: darkNavy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This module is coming soon.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// POINT OF SALE (POS)
// =====================================================

class PosPage extends StatefulWidget {
  final String shopName;
  final Future<void> Function() onSaleCompleted;

  const PosPage({
    super.key,
    required this.shopName,
    required this.onSaleCompleted,
  });

  @override
  State<PosPage> createState() => _PosPageState();
}

class _PosPageState extends State<PosPage> {
  final searchController = TextEditingController();
  final discountController = TextEditingController(text: '0');
  final paymentController = TextEditingController();

  bool loadingProducts = true;
  bool submitting = false;
  String? errorMessage;
  String paymentMethod = 'cash';

  List<dynamic> products = [];
  List<dynamic> customers = [];
  String? selectedCustomerId;
  final Map<String, Map<String, dynamic>> cart = {};

  double get subtotal {
    double value = 0;
    for (final entry in cart.values) {
      final product = entry['product'] as Map<String, dynamic>;
      final quantity = entry['quantity'] as int;
      value += (product['sellingPrice'] as num).toDouble() * quantity;
    }
    return value;
  }

  double get discount => double.tryParse(discountController.text.trim()) ?? 0;

  double get total =>
      (subtotal - discount).clamp(0, double.infinity).toDouble();

  double get amountPaid => double.tryParse(paymentController.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    loadProducts();
    loadCustomers();
    discountController.addListener(_refresh);
    paymentController.addListener(_refresh);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    searchController.dispose();
    discountController.dispose();
    paymentController.dispose();
    super.dispose();
  }

  Future<void> loadProducts({String search = ''}) async {
    setState(() {
      loadingProducts = true;
      errorMessage = null;
    });

    try {
      final result = await AuthService.instance.getProducts(search: search);
      if (!mounted) return;
      setState(() => products = result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        errorMessage = 'Unable to load products. Please try again.';
      });
    } finally {
      if (mounted) setState(() => loadingProducts = false);
    }
  }

  Future<void> loadCustomers() async {
    try {
      final result = await AuthService.instance.getCustomers();
      if (!mounted) return;
      setState(() => customers = result);
    } catch (_) {
      // Customer selection is optional; POS remains available if this fails.
    }
  }

  void addToCart(Map<String, dynamic> product) {
    final id = product['_id']?.toString() ?? '';
    if (id.isEmpty) return;

    final stock = (product['stockQuantity'] as num?)?.toInt() ?? 0;
    if (stock <= 0) {
      showMessage('This product is out of stock.');
      return;
    }

    final existing = cart[id];
    final currentQuantity = existing?['quantity'] as int? ?? 0;

    if (currentQuantity >= stock) {
      showMessage('Available stock is only $stock.');
      return;
    }

    setState(() {
      cart[id] = {'product': product, 'quantity': currentQuantity + 1};
    });
  }

  void changeQuantity(String id, int change) {
    final entry = cart[id];
    if (entry == null) return;

    final product = entry['product'] as Map<String, dynamic>;
    final current = entry['quantity'] as int;
    final stock = (product['stockQuantity'] as num?)?.toInt() ?? 0;
    final next = current + change;

    if (next <= 0) {
      setState(() => cart.remove(id));
      return;
    }

    if (next > stock) {
      showMessage('Available stock is only $stock.');
      return;
    }

    setState(() => cart[id] = {'product': product, 'quantity': next});
  }

  void showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String money(num value) => 'LKR ${value.toStringAsFixed(2)}';

  Future<void> completeSale() async {
    if (cart.isEmpty) {
      showMessage('Add at least one product to the cart.');
      return;
    }

    if (discount < 0 || discount > subtotal) {
      showMessage('Enter a valid discount amount.');
      return;
    }

    final paid = paymentMethod == 'cash' ? amountPaid : total;

    if (paid < total) {
      showMessage('Paid amount cannot be less than the total.');
      return;
    }

    setState(() => submitting = true);

    try {
      final sale = await AuthService.instance.createSale(
        items: cart.entries.map((entry) {
          return {'productId': entry.key, 'quantity': entry.value['quantity']};
        }).toList(),
        paymentMethod: paymentMethod,
        amountPaid: paid,
        discountAmount: discount,
        note: 'ShopFlow POS sale',
        customerId: selectedCustomerId,
      );

      if (!mounted) return;

      setState(() => cart.clear());
      discountController.text = '0';
      paymentController.clear();

      await widget.onSaleCompleted();
      await loadProducts(search: searchController.text);

      if (!mounted) return;
      await showInvoiceDialog(sale);
    } on DioException catch (e) {
      final data = e.response?.data;
      final message = data is Map
          ? data['message']?.toString() ?? 'Unable to complete sale.'
          : 'Cannot connect to ShopFlow server.';
      showMessage(message);
    } catch (_) {
      showMessage('Unable to complete sale. Please try again.');
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  Future<void> printCompletedInvoice(
    Map<String, dynamic> sale, {
    bool thermal = false,
    double paperWidthMm = 80,
  }) async {
    try {
      await InvoicePrintService.printInvoice(
        sale,
        shopName: widget.shopName,
        thermal: thermal,
        paperWidthMm: paperWidthMm,
      );
    } catch (e) {
      if (mounted) showMessage('Unable to print invoice: $e');
    }
  }

  Future<void> downloadCompletedInvoice(Map<String, dynamic> sale) async {
    try {
      await InvoicePrintService.shareInvoice(sale, shopName: widget.shopName);
    } catch (e) {
      if (mounted) showMessage('Unable to create PDF: $e');
    }
  }

  Future<void> showInvoiceDialog(Map<String, dynamic> sale) async {
    final items = List<dynamic>.from(sale['items'] ?? []);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Text('Sale completed'),
          ],
        ),
        content: SizedBox(
          width: 430,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sale['invoiceNumber']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: primaryBlue,
                  ),
                ),
                if (sale['customerSnapshot'] is Map &&
                    (sale['customerSnapshot']['name'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Customer: ${sale['customerSnapshot']['name']}'),
                  if ((sale['customerSnapshot']['phone'] ?? '').toString().isNotEmpty)
                    Text('Phone: ${sale['customerSnapshot']['phone']}'),
                ],
                const Divider(height: 24),
                ...items.map((raw) {
                  final item = Map<String, dynamic>.from(raw);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${item['name']} × ${item['quantity']}'),
                        ),
                        Text(moneyStatic(item['lineTotal'] as num)),
                      ],
                    ),
                  );
                }),
                const Divider(height: 24),
                _invoiceLine('Subtotal', sale['subtotal']),
                _invoiceLine('Discount', sale['discountAmount']),
                _invoiceLine('Total', sale['totalAmount'], bold: true),
                _invoiceLine('Paid', sale['amountPaid']),
                _invoiceLine('Change', sale['changeAmount']),
                const SizedBox(height: 12),
                const Text(
                  'Payment status: PAID',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          TextButton.icon(
            onPressed: () => downloadCompletedInvoice(sale),
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('PDF'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Print invoice',
            onSelected: (choice) {
              Navigator.pop(dialogContext);
              if (choice == 'a4') {
                printCompletedInvoice(sale);
              } else if (choice == '80') {
                printCompletedInvoice(sale, thermal: true, paperWidthMm: 80);
              } else if (choice == '58') {
                printCompletedInvoice(sale, thermal: true, paperWidthMm: 58);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'a4', child: Text('Print A4 invoice')),
              PopupMenuItem(value: '80', child: Text('Print 80mm receipt')),
              PopupMenuItem(value: '58', child: Text('Print 58mm receipt')),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.print),
                  SizedBox(width: 6),
                  Text('Print'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _invoiceLine(String label, dynamic value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(moneyStatic((value as num?) ?? 0), style: style),
        ],
      ),
    );
  }

  static String moneyStatic(num value) => 'LKR ${value.toStringAsFixed(2)}';

  Widget buildProductPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Products',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkNavy,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: searchController,
            onSubmitted: (value) => loadProducts(search: value.trim()),
            decoration: InputDecoration(
              hintText: 'Search product, SKU or barcode...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () {
                  searchController.clear();
                  loadProducts();
                },
                icon: const Icon(Icons.clear),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(11),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (loadingProducts)
            const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (errorMessage != null)
            SizedBox(
              height: 300,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage!),
                    TextButton(
                      onPressed: () =>
                          loadProducts(search: searchController.text.trim()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (products.isEmpty)
            const SizedBox(
              height: 300,
              child: Center(child: Text('No products found.')),
            )
          else
            SizedBox(
              height: 420,
              child: ListView.separated(
                itemCount: products.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = Map<String, dynamic>.from(products[index]);
                  final stock =
                      (product['stockQuantity'] as num?)?.toInt() ?? 0;
                  final id = product['_id']?.toString() ?? '';
                  final inCart = cart[id]?['quantity'] as int? ?? 0;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    leading: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        color: primaryBlue,
                      ),
                    ),
                    title: Text(
                      product['name']?.toString() ?? 'Unnamed product',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${product['sku'] ?? ''}  •  Stock: $stock',
                      style: TextStyle(
                        color: stock <= 0 ? Colors.red : Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          money((product['sellingPrice'] as num?) ?? 0),
                          style: const TextStyle(
                            color: primaryBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          inCart > 0 ? 'In cart: $inCart' : 'Tap + to add',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                    onTap: stock > 0 ? () => addToCart(product) : null,
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Tap a product to add it to the cart.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget buildCartPanel() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Current Sale',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: darkNavy,
                  ),
                ),
              ),
              TextButton(
                onPressed: cart.isEmpty
                    ? null
                    : () => setState(() => cart.clear()),
                child: const Text('Clear'),
              ),
            ],
          ),
          const Divider(),
          if (cart.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 35),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_cart_outlined,
                      size: 42,
                      color: Colors.grey,
                    ),
                    SizedBox(height: 8),
                    Text('Your cart is empty'),
                  ],
                ),
              ),
            )
          else
            ...cart.entries.map((entry) {
              final product = entry.value['product'] as Map<String, dynamic>;
              final quantity = entry.value['quantity'] as int;
              final price = (product['sellingPrice'] as num).toDouble();

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name']?.toString() ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '${money(price)} × $quantity',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => changeQuantity(entry.key, -1),
                      icon: const Icon(Icons.remove_circle_outline),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text('$quantity'),
                    IconButton(
                      onPressed: () => changeQuantity(entry.key, 1),
                      icon: const Icon(Icons.add_circle_outline),
                      visualDensity: VisualDensity.compact,
                    ),
                    Text(
                      money(price * quantity),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              );
            }),
          const Divider(height: 24),
          DropdownButtonFormField<String?>(
            initialValue: selectedCustomerId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Customer (optional)',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Walk-in Customer'),
              ),
              ...customers.map((raw) {
                final customer = Map<String, dynamic>.from(raw as Map);
                return DropdownMenuItem<String?>(
                  value: customer['_id']?.toString(),
                  child: Text(
                    '${customer['name'] ?? 'Customer'}'
                    '${(customer['phone'] ?? '').toString().isNotEmpty ? ' • ${customer['phone']}' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
            ],
            onChanged: (value) => setState(() => selectedCustomerId = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: discountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Discount (LKR)',
              prefixIcon: Icon(Icons.discount_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'bank', child: Text('Bank transfer')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                paymentMethod = value;
                if (value != 'cash') {
                  paymentController.text = total.toStringAsFixed(2);
                }
              });
            },
          ),
          if (paymentMethod == 'cash') ...[
            const SizedBox(height: 12),
            TextField(
              controller: paymentController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount received (LKR)',
                prefixIcon: Icon(Icons.payments_outlined),
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _summaryLine('Subtotal', subtotal),
          _summaryLine('Discount', discount),
          const Divider(height: 20),
          _summaryLine('Total', total, bold: true),
          if (paymentMethod == 'cash')
            _summaryLine(
              'Change',
              amountPaid >= total ? amountPaid - total : 0,
            ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: submitting ? null : completeSale,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              icon: submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.point_of_sale),
              label: Text(submitting ? 'Processing...' : 'Complete Sale'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, double value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 17 : 14,
      color: bold ? darkNavy : Colors.black87,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(money(value), style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1050;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Point of Sale',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: darkNavy,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Create a sale, collect payment and update stock.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 22),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: buildProductPanel()),
                    const SizedBox(width: 18),
                    Expanded(flex: 5, child: buildCartPanel()),
                  ],
                )
              else
                Column(
                  children: [
                    buildProductPanel(),
                    const SizedBox(height: 18),
                    buildCartPanel(),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

// =====================================================
// STAFF MANAGEMENT (Owner only)
// =====================================================

class StaffManagementPage extends StatefulWidget {
  const StaffManagementPage({super.key});
  @override
  State<StaffManagementPage> createState() => _StaffManagementPageState();
}

class _StaffManagementPageState extends State<StaffManagementPage> {
  bool loading = true;
  String? error;
  List<dynamic> staff = [];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try { staff = await AuthService.instance.getStaff(); }
    catch (e) { error = 'Unable to load staff. Check backend connection and owner permission.'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> openStaffDialog({Map<String, dynamic>? member}) async {
    final name = TextEditingController(text: member?['name']?.toString() ?? '');
    final email = TextEditingController(text: member?['email']?.toString() ?? '');
    final password = TextEditingController();
    String role = member?['role']?.toString() ?? 'cashier';
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialog) => AlertDialog(
      title: Text(member == null ? 'Add Staff Member' : 'Edit Staff Member'),
      content: SizedBox(width: 420, child: Form(key: formKey, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null),
        TextFormField(controller: email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress, validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null),
        if (member == null) TextFormField(controller: password, decoration: const InputDecoration(labelText: 'Temporary password (minimum 8 characters)'), obscureText: true, validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null),
        if (member != null) TextFormField(controller: password, decoration: const InputDecoration(labelText: 'New password (leave blank to keep current)'), obscureText: true),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: role, decoration: const InputDecoration(labelText: 'Role'), items: const [DropdownMenuItem(value: 'manager', child: Text('Manager')), DropdownMenuItem(value: 'cashier', child: Text('Cashier'))], onChanged: (v) { if (v != null) setDialog(() => role = v); }),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (formKey.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save Staff'))],
    )));
    if (saved == true) {
      try {
        final data = <String, dynamic>{'name': name.text.trim(), 'email': email.text.trim(), 'role': role};
        if (password.text.isNotEmpty) data['password'] = password.text;
        await AuthService.instance.saveStaff(data, id: member?['id']?.toString());
        await load();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Staff account saved')));
      } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to save staff: $e'))); }
    }
    name.dispose(); email.dispose(); password.dispose();
  }

  Future<void> disable(Map<String, dynamic> member) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Disable Staff Account'), content: Text('Disable ${member['name']}? They will no longer be able to log in.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disable'))]));
    if (ok != true) return;
    try { await AuthService.instance.disableStaff(member['id'].toString()); await load(); }
    catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to disable staff: $e'))); }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Staff Management', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: darkNavy)), SizedBox(height: 5), Text('Create Manager and Cashier accounts. Only the Owner can manage staff.', style: TextStyle(color: Colors.grey))])), ElevatedButton.icon(onPressed: () => openStaffDialog(), icon: const Icon(Icons.person_add_alt_1), label: const Text('Add Staff'))]),
    const SizedBox(height: 20),
    if (loading) const Center(child: CircularProgressIndicator()) else if (error != null) Card(child: ListTile(title: Text(error!), trailing: IconButton(onPressed: load, icon: const Icon(Icons.refresh)))) else if (staff.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No staff accounts yet. Add your first Manager or Cashier.')))) else ...staff.map((raw) { final m = Map<String,dynamic>.from(raw); final active = m['status'] == 'active'; return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: CircleAvatar(child: Icon(m['role'] == 'manager' ? Icons.manage_accounts : Icons.point_of_sale)), title: Text(m['name']?.toString() ?? ''), subtitle: Text('${m['email']} • ${(m['role'] ?? '').toString().toUpperCase()} • ${active ? 'ACTIVE' : 'DISABLED'}'), trailing: Wrap(spacing: 0, children: [IconButton(tooltip: 'Edit', onPressed: () => openStaffDialog(member: m), icon: const Icon(Icons.edit_outlined)), if (active) IconButton(tooltip: 'Disable', onPressed: () => disable(m), icon: const Icon(Icons.person_off_outlined, color: Colors.red)) else IconButton(tooltip: 'Activate', onPressed: () async { try { await AuthService.instance.setStaffStatus(m['id'].toString(), 'active'); await load(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to activate staff: $e'))); } }, icon: const Icon(Icons.check_circle_outline, color: Colors.green))]))); }),
  ]));
}

// =====================================================
// ADVANCED REPORTS + EXPENSE ENTRY (Owner / Manager)
// =====================================================

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String period = 'daily';
  bool loading = true;
  String? error;
  Map<String, dynamic> report = {};

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try { report = await AuthService.instance.getReport(period: period); }
    catch (e) { error = 'Unable to load report. Only Owner and Manager can view reports. $e'; }
    if (mounted) setState(() => loading = false);
  }

  String money(dynamic v) { final n = v is num ? v.toDouble() : double.tryParse(v?.toString() ?? '') ?? 0; return 'LKR ${n.toStringAsFixed(2)}'; }

  Future<void> addExpense() async {
    final title = TextEditingController(); final amount = TextEditingController(); final category = TextEditingController(text: 'General'); final note = TextEditingController();
    final key = GlobalKey<FormState>();
    final saved = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: const Text('Record Expense'), content: SizedBox(width: 420, child: Form(key: key, child: Column(mainAxisSize: MainAxisSize.min, children: [TextFormField(controller: title, decoration: const InputDecoration(labelText: 'Expense title'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a title' : null), TextFormField(controller: category, decoration: const InputDecoration(labelText: 'Category')), TextFormField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Amount (LKR)'), validator: (v) => (double.tryParse(v ?? '') ?? 0) <= 0 ? 'Enter a valid amount' : null), TextFormField(controller: note, decoration: const InputDecoration(labelText: 'Note (optional)'))]))), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (key.currentState!.validate()) Navigator.pop(ctx, true); }, child: const Text('Save Expense'))]));
    if (saved == true) { try { await AuthService.instance.createExpense({'title': title.text.trim(), 'category': category.text.trim(), 'amount': double.parse(amount.text), 'note': note.text.trim(), 'expenseDate': DateTime.now().toUtc().toIso8601String()}); await load(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense saved'))); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unable to save expense: $e'))); } }
    title.dispose(); amount.dispose(); category.dispose(); note.dispose();
  }

  Widget metric(String label, dynamic value, IconData icon, {bool highlight = false}) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: highlight ? Colors.green : primaryBlue), const SizedBox(height: 12), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)), const SizedBox(height: 5), Text(money(value), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: highlight ? Colors.green.shade800 : darkNavy))])));

  @override
  Widget build(BuildContext context) => RefreshIndicator(onRefresh: load, child: ListView(padding: const EdgeInsets.all(24), children: [
    Row(children: [const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Advanced Reports', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, color: darkNavy)), SizedBox(height: 5), Text('Sales, cost of goods, gross profit and recorded expenses.', style: TextStyle(color: Colors.grey))])), ElevatedButton.icon(onPressed: addExpense, icon: const Icon(Icons.add), label: const Text('Add Expense'))]),
    const SizedBox(height: 16),
    Row(children: [const Text('Period: '), const SizedBox(width: 10), DropdownButton<String>(value: period, items: const [DropdownMenuItem(value: 'daily', child: Text('Daily')), DropdownMenuItem(value: 'weekly', child: Text('Weekly')), DropdownMenuItem(value: 'monthly', child: Text('Monthly'))], onChanged: (v) { if (v != null) { setState(() => period = v); load(); } }), const Spacer(), IconButton(onPressed: load, icon: const Icon(Icons.refresh))]),
    if (loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())) else if (error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(error!))) else ...[
      Wrap(spacing: 10, runSpacing: 10, children: [SizedBox(width: 230, child: metric('Sales Revenue', report['revenue'], Icons.point_of_sale)), SizedBox(width: 230, child: metric('Cost of Goods', report['costOfGoods'], Icons.inventory_2_outlined)), SizedBox(width: 230, child: metric('Gross Profit', report['grossProfit'], Icons.trending_up, highlight: true)), SizedBox(width: 230, child: metric('Expenses', report['expenses'], Icons.money_off)), SizedBox(width: 230, child: metric('Net Profit', report['netProfit'], Icons.account_balance, highlight: true))]),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 24, runSpacing: 10, children: [Text('Invoices: ${report['invoiceCount'] ?? 0}'), Text('Units sold: ${report['unitsSold'] ?? 0}'), Text('Expense records: ${report['expenseCount'] ?? 0}'), Text('Discounts: ${money(report['discounts'])}')]))),
      const SizedBox(height: 18),
      const Text('Recorded Expenses', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkNavy)),
      const SizedBox(height: 8),
      if ((report['expenseItems'] as List? ?? []).isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('No expenses recorded for this period.'),
          ),
        )
      else
        ...(report['expenseItems'] as List).map<Widget>((raw) {
          final expense = Map<String, dynamic>.from(raw);
          final expenseDate = DateTime.tryParse(
            expense['expenseDate']?.toString() ?? '',
          )?.toLocal();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: primaryBlue),
              title: Text(expense['title']?.toString() ?? ''),
              subtitle: Text(
                '${expense['category'] ?? 'General'} • ${expenseDate?.toString().split(' ').first ?? ''}',
              ),
              trailing: Text(
                money(expense['amount']),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
      const SizedBox(height: 18),
      const Text(
        'Recent Sales',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: darkNavy),
      ),
      const SizedBox(height: 8),
      if ((report['recentSales'] as List? ?? []).isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('No sales in this period.'),
          ),
        )
      else
        ...(report['recentSales'] as List).map<Widget>((raw) {
          final sale = Map<String, dynamic>.from(raw);
          final saleDate = DateTime.tryParse(
            sale['createdAt']?.toString() ?? '',
          )?.toLocal();
          return Card(
            child: ListTile(
              leading: const Icon(Icons.receipt, color: primaryBlue),
              title: Text(sale['invoiceNumber']?.toString() ?? ''),
              subtitle: Text(saleDate?.toString() ?? ''),
              trailing: Text(
                money(sale['totalAmount']),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }),
    ],
  ]));
}

// =====================================================
// STATISTICS CARDS
// =====================================================

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String change;
  final IconData icon;
  final Color color;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.change,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            value,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.bold,
              color: darkNavy,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            change,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// SALES CHART
// =====================================================

class SalesChart extends StatelessWidget {
  final List<dynamic> salesByDay;

  const SalesChart({super.key, required this.salesByDay});

  double _amount(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _dayLabel(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '-';
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return labels[date.toLocal().weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    final values = salesByDay.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return _amount(map['revenue']);
    }).toList();
    final maxValue = values.isEmpty
        ? 0.0
        : values.fold<double>(0, (max, value) => value > max ? value : max);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sales Overview',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkNavy,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Actual sales for the last 7 days',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 30),
          if (salesByDay.isEmpty || maxValue <= 0)
            const SizedBox(
              height: 175,
              child: Center(
                child: Text(
                  'No sales recorded in the last 7 days.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SizedBox(
              height: 175,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(salesByDay.length, (index) {
                  final entry =
                      Map<String, dynamic>.from(salesByDay[index] as Map);
                  final amount = _amount(entry['revenue']);
                  final factor = (amount / maxValue).clamp(0.0, 1.0);

                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: factor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: index == salesByDay.length - 1
                                        ? primaryBlue
                                        : const Color(0xFFBFDBFE),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(7),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _dayLabel(entry['date']),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// =====================================================
// LOW STOCK ALERTS
// =====================================================

class LowStockCard extends StatelessWidget {
  final List<dynamic> products;

  const LowStockCard({super.key, required this.products});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Low Stock Alerts',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkNavy,
            ),
          ),
          const SizedBox(height: 18),
          if (products.isEmpty)
            const Text(
              'No low stock products.',
              style: TextStyle(color: Colors.grey),
            ),
          ...products.take(5).map((item) {
            final product = Map<String, dynamic>.from(item);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.orange,
                    size: 21,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      product['name']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    '${product['stockQuantity']} left',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// =====================================================
// RECENT TRANSACTIONS
// =====================================================

class RecentTransactions extends StatelessWidget {
  final List<dynamic> sales;
  final bool loading;

  const RecentTransactions({
    super.key,
    required this.sales,
    required this.loading,
  });

  String _money(dynamic value) {
    final amount = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0;
    return 'LKR ${amount.toStringAsFixed(2)}';
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '-';
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Transactions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkNavy,
            ),
          ),
          const SizedBox(height: 20),
          if (loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'No sales have been recorded for this shop yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Invoice')),
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Amount')),
                  DataColumn(label: Text('Status')),
                ],
                rows: sales.map((raw) {
                  final sale = Map<String, dynamic>.from(raw as Map);
                  final customer = sale['customerSnapshot'] is Map
                      ? Map<String, dynamic>.from(
                          sale['customerSnapshot'] as Map,
                        )
                      : <String, dynamic>{};
                  final customerName =
                      customer['name']?.toString().trim().isNotEmpty == true
                          ? customer['name'].toString()
                          : 'Walk-in customer';
                  final status =
                      sale['paymentStatus']?.toString().toUpperCase() ??
                          'PAID';

                  return DataRow(
                    cells: [
                      DataCell(
                        Text(sale['invoiceNumber']?.toString() ?? '-'),
                      ),
                      DataCell(Text(customerName)),
                      DataCell(Text(_date(sale['createdAt']))),
                      DataCell(Text(_money(sale['totalAmount']))),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            status,
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
