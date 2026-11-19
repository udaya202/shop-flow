import 'package:material_ui/material_ui.dart';
import 'package:dio/dio.dart';
import 'package:dio/browser.dart';

const String superAdminApiUrl = 'http://localhost:5050/api';

class SuperAdminApi {
  SuperAdminApi._() {
    dio = Dio(
      BaseOptions(
        baseUrl: superAdminApiUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );
    dio.httpClientAdapter = BrowserHttpClientAdapter();
  }

  static final SuperAdminApi instance = SuperAdminApi._();

  late final Dio dio;
  String? token;

  Options get authOptions =>
      Options(headers: {'Authorization': 'Bearer $token'});

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await dio.post(
      '/super-admin/auth/login',
      data: {'email': email.trim(), 'password': password},
    );
    final data = Map<String, dynamic>.from(response.data['data'] as Map);
    token = data['accessToken']?.toString();
    if (token == null || token!.isEmpty) {
      throw Exception('The server did not return an access token.');
    }
    return Map<String, dynamic>.from(data['admin'] as Map);
  }

  Future<Map<String, dynamic>> getOverview() async {
    final response = await dio.get(
      '/super-admin/overview',
      options: authOptions,
    );
    return Map<String, dynamic>.from(response.data['data'] as Map);
  }

  Future<List<Map<String, dynamic>>> getShops({
    int page = 1,
    int limit = 50,
    String search = '',
    String? status,
  }) async {
    final response = await dio.get(
      '/super-admin/shops',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (status != null && status != 'all') 'status': status,
      },
      options: authOptions,
    );
    final raw = response.data['data'] as List? ?? [];
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> getOwners({
    int page = 1,
    int limit = 50,
    String search = '',
  }) async {
    final response = await dio.get(
      '/super-admin/owners',
      queryParameters: {
        'page': page,
        'limit': limit,
        if (search.trim().isNotEmpty) 'search': search.trim(),
      },
      options: authOptions,
    );
    final raw = response.data['data'] as List? ?? [];
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> updateShopStatus(String shopId, String status) async {
    await dio.patch(
      '/super-admin/shops/$shopId/status',
      data: {'status': status},
      options: authOptions,
    );
  }

  void logout() {
    token = null;
  }
}

String _apiError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    if (error.response?.statusCode == 401) {
      return 'Session expired or login details are incorrect.';
    }
    return error.response == null
        ? 'Cannot connect to the ShopFlow server.'
        : 'Request failed (${error.response?.statusCode}).';
  }
  return error.toString().replaceFirst('Exception: ', '');
}

class SuperAdminLoginPage extends StatefulWidget {
  const SuperAdminLoginPage({super.key});

  @override
  State<SuperAdminLoginPage> createState() => _SuperAdminLoginPageState();
}

class _SuperAdminLoginPageState extends State<SuperAdminLoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool loading = false;
  bool obscurePassword = true;
  String? errorMessage;

  Future<void> signIn() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.isEmpty) {
      setState(() => errorMessage = 'Enter your email and password.');
      return;
    }

    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final admin = await SuperAdminApi.instance.login(
        email: emailController.text,
        password: passwordController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SuperAdminDashboardPage(admin: admin),
        ),
      );
    } catch (error) {
      if (mounted) setState(() => errorMessage = _apiError(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings_rounded,
                      size: 64,
                      color: Color(0xFF2563EB),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'ShopFlow Admin',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF172554),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Platform administrator sign in',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 30),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Admin email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => signIn(),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: passwordController,
                      obscureText: obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => obscurePassword = !obscurePassword,
                          ),
                          icon: Icon(
                            obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => signIn(),
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: loading ? null : signIn,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          foregroundColor: Colors.white,
                        ),
                        child: loading
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Sign in to Admin Panel'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: loading
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Back to Shop Login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SuperAdminDashboardPage extends StatefulWidget {
  final Map<String, dynamic> admin;

  const SuperAdminDashboardPage({super.key, required this.admin});

  @override
  State<SuperAdminDashboardPage> createState() =>
      _SuperAdminDashboardPageState();
}

class _SuperAdminDashboardPageState extends State<SuperAdminDashboardPage> {
  int selectedIndex = 0;
  bool loading = true;
  String? errorMessage;
  Map<String, dynamic> overview = {};
  List<Map<String, dynamic>> shops = [];
  List<Map<String, dynamic>> owners = [];
  String shopSearch = '';
  String shopStatus = 'all';

  static const Color navy = Color(0xFF172554);
  static const Color blue = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    loadAll();
  }

  Future<void> loadAll() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final results = await Future.wait([
        SuperAdminApi.instance.getOverview(),
        SuperAdminApi.instance.getShops(search: shopSearch, status: shopStatus),
        SuperAdminApi.instance.getOwners(),
      ]);
      if (!mounted) return;
      setState(() {
        overview = results[0] as Map<String, dynamic>;
        shops = results[1] as List<Map<String, dynamic>>;
        owners = results[2] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => errorMessage = _apiError(error));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changeShopStatus(
    Map<String, dynamic> shop,
    String nextStatus,
  ) async {
    final shopId = shop['id']?.toString() ?? '';
    if (shopId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          '${nextStatus == 'suspended' ? 'Suspend' : 'Activate'} shop?',
        ),
        content: Text(
          'Are you sure you want to ${nextStatus == 'suspended' ? 'suspend' : 'activate'} ${shop['shopName'] ?? 'this shop'}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await SuperAdminApi.instance.updateShopStatus(shopId, nextStatus);
      await loadAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Shop $nextStatus successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_apiError(error))));
      }
    }
  }

  void logout() {
    SuperAdminApi.instance.logout();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Widget metricCard(String title, dynamic value, IconData icon, Color color) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: .12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value?.toString() ?? '0',
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                        color: navy,
                      ),
                    ),
                    Text(title, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildOverview() {
    return RefreshIndicator(
      onRefresh: loadAll,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Platform Overview',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Welcome, ${widget.admin['name'] ?? 'Administrator'}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 22),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              metricCard(
                'Registered Shops',
                overview['totalShops'],
                Icons.store,
                blue,
              ),
              metricCard(
                'Active Shops',
                overview['activeShops'],
                Icons.check_circle,
                Colors.green,
              ),
              metricCard(
                'Suspended Shops',
                overview['suspendedShops'],
                Icons.pause_circle,
                Colors.orange,
              ),
              metricCard(
                'Total Owners',
                overview['totalOwners'],
                Icons.people,
                Colors.purple,
              ),
              metricCard(
                'Total Users',
                overview['totalUsers'],
                Icons.groups,
                Colors.teal,
              ),
              metricCard(
                'Total Products',
                overview['totalProducts'],
                Icons.inventory_2,
                Colors.indigo,
              ),
              metricCard(
                'Total Sales',
                overview['totalSales'],
                Icons.point_of_sale,
                Colors.deepOrange,
              ),
              metricCard(
                'Total Revenue',
                'LKR ${(overview['totalRevenue'] ?? 0)}',
                Icons.payments,
                Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Recently Registered Shops',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: loadAll,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
          ...shops.take(5).map(shopTile),
        ],
      ),
    );
  }

  Widget shopTile(Map<String, dynamic> shop) {
    final status = shop['status']?.toString() ?? 'unknown';
    final owner = shop['owner'] is Map
        ? Map<String, dynamic>.from(shop['owner'] as Map)
        : <String, dynamic>{};
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFEFF6FF),
          child: Icon(Icons.storefront, color: blue),
        ),
        title: Text(shop['shopName']?.toString() ?? 'Unnamed shop'),
        subtitle: Text(
          '${shop['slug'] ?? '-'} • ${owner['email'] ?? 'No owner email'}',
        ),
        trailing: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              label: Text(status),
              backgroundColor: status == 'active'
                  ? Colors.green.shade50
                  : Colors.orange.shade50,
            ),
            PopupMenuButton<String>(
              tooltip: 'Change shop status',
              onSelected: (value) => changeShopStatus(shop, value),
              itemBuilder: (_) => [
                if (status != 'active')
                  const PopupMenuItem(value: 'active', child: Text('Activate')),
                if (status != 'suspended')
                  const PopupMenuItem(
                    value: 'suspended',
                    child: Text('Suspend'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildShops() {
    return RefreshIndicator(
      onRefresh: loadAll,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Shop Management',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search shops by name, email or slug',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) {
              shopSearch = value;
              loadAll();
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: shopStatus,
            decoration: const InputDecoration(
              labelText: 'Shop status',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('All shops')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
            ],
            onChanged: (value) {
              if (value == null) return;
              shopStatus = value;
              loadAll();
            },
          ),
          const SizedBox(height: 16),
          ...shops.map(shopTile),
          if (shops.isEmpty && !loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No shops found.'),
            ),
        ],
      ),
    );
  }

  Widget buildOwners() {
    return RefreshIndicator(
      onRefresh: loadAll,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Owner Management',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: navy,
            ),
          ),
          const SizedBox(height: 16),
          ...owners.map((owner) {
            final shop = owner['shop'] is Map
                ? Map<String, dynamic>.from(owner['shop'] as Map)
                : <String, dynamic>{};
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(owner['name']?.toString() ?? 'Unknown owner'),
                subtitle: Text(
                  '${owner['email'] ?? '-'}\nShop: ${shop['shopName'] ?? 'Unknown'} • ${shop['slug'] ?? '-'}',
                ),
                isThreeLine: true,
                trailing: Chip(
                  label: Text(owner['status']?.toString() ?? 'unknown'),
                ),
              ),
            );
          }),
          if (owners.isEmpty && !loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No owners found.'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = [buildOverview(), buildShops(), buildOwners()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('ShopFlow Super Admin'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: loadAll,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh data',
          ),
          IconButton(
            onPressed: logout,
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: loading && overview.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null && overview.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(errorMessage!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: loadAll,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          : Row(
              children: [
                NavigationRail(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) =>
                      setState(() => selectedIndex = index),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: Text('Overview'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.store_outlined),
                      selectedIcon: Icon(Icons.store),
                      label: Text('Shops'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Owners'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: errorMessage != null
                      ? Center(child: Text(errorMessage!))
                      : pages[selectedIndex],
                ),
              ],
            ),
    );
  }
}
