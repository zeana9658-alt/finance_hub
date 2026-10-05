import 'package:finance_hub/features/bills/bills_page.dart';
import 'package:finance_hub/features/budget/budget_page.dart';
import 'package:finance_hub/features/dashboard/dashboard_page.dart';
import 'package:finance_hub/features/settings/settings_page.dart';
import 'package:finance_hub/features/stats/stats_page.dart';
import 'package:flutter/material.dart';

/// 应用主壳 —— 五个页面 + 快速记账入口。
///
/// 底部导航（见 docs/ARCHITECTURE.md §7.4）：
/// ```
/// 首页 | 账单 | 统计 | 预算 | 设置
/// ```
/// 「+」快速记账做成页面内 FAB（首页与账单页），
/// 避免与 5 个导航项挤在 360dp 宽的小屏上导致触控目标小于 48dp。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<Widget> _pages = <Widget>[
    DashboardPage(),
    BillsPage(),
    StatsPage(),
    BudgetPage(),
    SettingsPage(),
  ];

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.dashboard_outlined),
      selectedIcon: Icon(Icons.dashboard),
      label: '首页',
    ),
    NavigationDestination(
      icon: Icon(Icons.receipt_long_outlined),
      selectedIcon: Icon(Icons.receipt_long),
      label: '账单',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: '统计',
    ),
    NavigationDestination(
      icon: Icon(Icons.savings_outlined),
      selectedIcon: Icon(Icons.savings),
      label: '预算',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: '设置',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: _destinations,
      ),
    );
  }
}
