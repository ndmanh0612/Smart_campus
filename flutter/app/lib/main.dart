import 'dart:async';
import 'package:flutter/material.dart';
import 'core/campus_api.dart';
import 'features/shared.dart';
import 'features/student.dart';
import 'features/parking.dart';
import 'features/canteen.dart';
import 'features/attendance.dart';
import 'features/admin.dart';
import 'features/admin_tools.dart';
import 'features/simulation.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final api = CampusApi();
  runApp(CampusApp(api: api));
  unawaited(api.restore());
}

class CampusApp extends StatelessWidget {
  final CampusApi api;
  const CampusApp({required this.api, super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Smart Campus',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      fontFamily: 'CampusRoboto',
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff0f766e),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: const Color(0xfff8fafc),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xfff8fafc),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: api,
      builder: (context, _) =>
          api.user == null ? LoginPage(api) : CampusShell(api),
    ),
  );
}

class LoginPage extends StatefulWidget {
  final CampusApi api;
  const LoginPage(this.api, {super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.login(email.text.trim(), password.text);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LayoutBuilder(
      builder: (context, size) => Row(
        children: [
          if (size.maxWidth >= 950)
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff134e4a), Color(0xff0f766e)],
                  ),
                ),
                padding: const EdgeInsets.all(64),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.school_outlined, color: Colors.white, size: 64),
                    SizedBox(height: 32),
                    Text(
                      'SMART\nCAMPUS',
                      style: TextStyle(
                        fontSize: 64,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -2,
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Một danh tính.\nTrọn vẹn trải nghiệm khuôn viên.',
                      style: TextStyle(
                        fontSize: 23,
                        height: 1.5,
                        color: Color(0xffccfbf1),
                      ),
                    ),
                    SizedBox(height: 48),
                    Text(
                      'GỬI XE  /  CANTIN  /  ĐIỂM DANH',
                      style: TextStyle(color: Colors.white70, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Chào mừng trở lại',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Đăng nhập để sử dụng dịch vụ trong khuôn viên.',
                          style: TextStyle(
                            color: Color(0xff64748b),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 32),
                        TextFormField(
                          controller: email,
                          autofillHints: const [AutofillHints.username],
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                          validator: (v) => v == null || !v.contains('@')
                              ? 'Nhập email hợp lệ'
                              : null,
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: password,
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          decoration: const InputDecoration(
                            labelText: 'Mật khẩu',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onFieldSubmitted: (_) => unawaited(login()),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Nhập mật khẩu' : null,
                        ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: busy ? null : login,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: busy
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Đăng nhập'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'MÔI TRƯỜNG THỬ NGHIỆM',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            letterSpacing: 1.2,
                            color: Color(0xff64748b),
                          ),
                        ),
                        const SizedBox(height: 12),
                        const ModeLabels(),
                        const SizedBox(height: 12),
                        const Text(
                          'Nạp point MOCK không phải giao dịch tiền thật.',
                          style: TextStyle(color: Color(0xff64748b)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class CampusShell extends StatefulWidget {
  final CampusApi api;
  const CampusShell(this.api, {super.key});
  @override
  State<CampusShell> createState() => _CampusShellState();
}

class _CampusShellState extends State<CampusShell> {
  int selected = 0;
  CampusApi get api => widget.api;
  @override
  Widget build(BuildContext context) {
    final pages = <({String label, IconData icon, Widget page})>[
      if (api.isStudent) ...[
        (
          label: 'Tổng quan',
          icon: Icons.dashboard_outlined,
          page: StudentHome(api),
        ),
        (
          label: 'Ví & thanh toán',
          icon: Icons.account_balance_wallet_outlined,
          page: WalletPage(api),
        ),
        (label: 'Thẻ sinh viên', icon: Icons.nfc, page: CardsPage(api)),
        (
          label: 'Phương tiện',
          icon: Icons.directions_car_outlined,
          page: VehiclesPage(api),
        ),
        (label: 'Lịch sử dịch vụ', icon: Icons.history, page: HistoryPage(api)),
        (
          label: 'Dữ liệu khuôn mặt',
          icon: Icons.verified_user_outlined,
          page: ConsentPage(api),
        ),
      ],
      if (api.has('PARKING_STAFF'))
        (label: 'Bãi xe', icon: Icons.local_parking, page: ParkingPage(api)),
      if (api.has('CANTEEN_STAFF'))
        ...([
          (
            label: 'POS cantin',
            icon: Icons.point_of_sale,
            page: CanteenPage(api),
          ),
          (
            label: 'Hàng hóa & kho',
            icon: Icons.inventory_2_outlined,
            page: InventoryPage(api),
          ),
        ]),
      if (api.has('LECTURER'))
        (
          label: 'Lớp & điểm danh',
          icon: Icons.fact_check_outlined,
          page: AttendancePage(api),
        ),
      if (api.roles.contains('ADMIN'))
        (
          label: 'Cấu hình & quyền',
          icon: Icons.tune,
          page: AdminToolsPage(api),
        ),
      if (api.roles.contains('ADMIN'))
        (label: 'Báo cáo', icon: Icons.bar_chart, page: ReportsPage(api)),
      if (api.roles.contains('ADMIN'))
        ...([
          (
            label: 'Quản trị',
            icon: Icons.admin_panel_settings_outlined,
            page: AdminPage(api),
          ),
          (
            label: 'Học vụ',
            icon: Icons.school_outlined,
            page: AcademicAdminPage(api),
          ),
          (
            label: 'Nhật ký audit',
            icon: Icons.manage_search,
            page: AuditPage(api),
          ),
        ]),
      if ((api.user?['permissions'] as List? ?? []).contains('simulator.use'))
        (
          label: 'Bảng mô phỏng',
          icon: Icons.science_outlined,
          page: SimulationPage(api),
        ),
      (
        label: 'Hồ sơ & bảo mật',
        icon: Icons.settings_outlined,
        page: SecurityPage(api),
      ),
    ];
    if (selected >= pages.length) selected = 0;
    Widget navigation() => Container(
      width: 250,
      color: const Color(0xff0f172a),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Row(
                children: [
                  Icon(
                    Icons.school_outlined,
                    color: Color(0xff5eead4),
                    size: 32,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Smart Campus',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                children: pages.indexed
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 3,
                        ),
                        child: ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          selected: entry.$1 == selected,
                          selectedTileColor: const Color(0xff134e4a),
                          selectedColor: const Color(0xff5eead4),
                          textColor: const Color(0xffcbd5e1),
                          iconColor: const Color(0xff94a3b8),
                          leading: Icon(entry.$2.icon, size: 22),
                          title: Text(
                            entry.$2.label,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () {
                            setState(() => selected = entry.$1);
                            if (MediaQuery.sizeOf(context).width < 1050) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'DEVELOPMENT\nRFID thật • AI mô phỏng',
                style: TextStyle(
                  color: Colors.blueGrey.shade200,
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Scaffold(
      drawer: wide ? null : Drawer(child: navigation()),
      body: Row(
        children: [
          if (wide) navigation(),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xffe2e8f0)),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (!wide)
                        Builder(
                          builder: (context) => IconButton(
                            onPressed: () => Scaffold.of(context).openDrawer(),
                            icon: const Icon(Icons.menu),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          pages[selected].label,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Icon(
                        api.realtimeConnected ? Icons.wifi : Icons.sync_problem,
                        size: 18,
                        color: api.realtimeConnected
                            ? const Color(0xff0f766e)
                            : Colors.orange,
                      ),
                      const SizedBox(width: 12),
                      if (wide) Text(api.user?['name']?.toString() ?? ''),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Đăng xuất',
                        onPressed: () async {
                          try {
                            await api.logout();
                          } catch (_) {
                            /* Session is removed locally even when the server is unavailable. */
                          }
                        },
                        icon: const Icon(Icons.logout),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(wide ? 32 : 16),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: pages[selected].page,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
