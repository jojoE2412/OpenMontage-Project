import 'package:flutter/material.dart';

import 'home_page.dart';
import 'projects_page.dart';
import 'library_page.dart';
import 'profile_page.dart';
import 'feature_hub_pages.dart';
import '../widgets/bottom_nav.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int currentIndex = 0;

  List<Widget> get pages => [
    HomePage(onTabSelected: changePage),
    const ProjectsPage(),
    const CreateSomethingPage(),
    const LibraryPage(),
    const ProfilePage(),
  ];

  void changePage(int index) {
    setState(() {
      currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: currentIndex, children: pages),
      bottomNavigationBar: BottomNav(
        currentIndex: currentIndex,
        onTap: changePage,
      ),
    );
  }
}
