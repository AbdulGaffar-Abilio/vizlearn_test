import 'package:flutter/material.dart';
import 'device_connection_page.dart';
import 'network_mode_page.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const StandaloneModeTab(),
    const NetworkModeTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.wifi),
            label: 'Standalone Mode',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.cloud),
            label: 'Network Mode',
          ),
        ],
      ),
    );
  }
}

// Wrapper for standalone mode
class StandaloneModeTab extends StatelessWidget {
  const StandaloneModeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const DeviceConnectionPage();
  }
}

// Wrapper for network mode
class NetworkModeTab extends StatelessWidget {
  const NetworkModeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const NetworkModePage();
  }
}

