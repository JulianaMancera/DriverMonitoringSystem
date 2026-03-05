import 'package:flutter/material.dart';

class Sidebar extends StatelessWidget {
  final String activeTab;
  final Function(String) onTabChanged;
  final bool isMobile;

  const Sidebar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    this.isMobile = false,
  });

  @override
  Widget build(BuildContext context) {
    return isMobile
        ? _buildMobileNavBar(context)
        : _buildDesktopSidebar(context);
  }

  Widget _buildMobileNavBar(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    // Portrait: bigger buttons, centered with spaceAround
    // Landscape: smaller buttons, scrollable horizontally
    final double barHeight = isLandscape ? 48 : 64;
    final double btnSize = isLandscape ? 32 : 40;
    final double iconSize = isLandscape ? 16 : 20;

    final List<Widget> items = [
      ..._getNavItems().map((item) => _NavButton(
            item: item,
            isMobile: true,
            isActive: activeTab == item.id,
            btnSize: btnSize,
            iconSize: iconSize,
            onTap: () => onTabChanged(item.id),
          )),
      _UserButton(btnSize: btnSize, iconSize: iconSize),
    ];

    return Container(
      height: barHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            offset: const Offset(0, -4),
            blurRadius: 15,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: isLandscape
            // Landscape: scrollable so nothing overflows
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: items
                      .map((w) =>
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: w))
                      .toList(),
                ),
              )
            // Portrait: full width, evenly spaced and centered
            : Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: items,
                ),
              ),
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
    return Container(
      width: 96,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            offset: const Offset(4, 0),
            blurRadius: 15,
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.show_chart, size: 32, color: Color(0xFF22d3ee)),
          const SizedBox(height: 32),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _getNavItems()
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: _NavButton(
                            item: item,
                            isMobile: false,
                            isActive: activeTab == item.id,
                            btnSize: 64,
                            iconSize: 24,
                            onTap: () => onTabChanged(item.id),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          const _UserButton(btnSize: 48, iconSize: 20),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  List<NavItem> _getNavItems() {
    return [
      NavItem(id: 'home', icon: Icons.home, label: 'Home'),
      NavItem(id: 'monitor', icon: Icons.videocam, label: 'Monitor'),
      NavItem(id: 'analytics', icon: Icons.analytics, label: 'Analytics'),
      NavItem(id: 'settings', icon: Icons.settings, label: 'Settings'),
    ];
  }
}

class NavItem {
  final String id;
  final IconData icon;
  final String label;
  NavItem({required this.id, required this.icon, required this.label});
}

class _UserButton extends StatelessWidget {
  final double btnSize;
  final double iconSize;
  const _UserButton({required this.btnSize, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: btnSize,
      height: btnSize,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(3, 3), blurRadius: 6),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-3, -3),
              blurRadius: 6),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(Icons.person_outline,
            size: iconSize, color: const Color(0xFF64748b)),
        onPressed: () {},
      ),
    );
  }
}

class _NavButton extends StatefulWidget {
  final NavItem item;
  final bool isMobile;
  final bool isActive;
  final double btnSize;
  final double iconSize;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isMobile,
    required this.isActive,
    required this.btnSize,
    required this.iconSize,
    required this.onTap,
  });

  @override
  State<_NavButton> createState() => _NavButtonState();
}

class _NavButtonState extends State<_NavButton> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    final shouldShowPressed = widget.isActive || isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          width: widget.isMobile ? widget.btnSize : double.infinity,
          height: widget.btnSize,
          decoration: BoxDecoration(
            color: const Color(0xFF0f172a),
            borderRadius: BorderRadius.circular(16),
            boxShadow: shouldShowPressed
                ? const [
                    BoxShadow(
                        color: Color(0xFF0b1120),
                        offset: Offset(-3, -3),
                        blurRadius: 6),
                    BoxShadow(
                        color: Color(0xFF1e293b),
                        offset: Offset(3, 3),
                        blurRadius: 6),
                  ]
                : const [
                    BoxShadow(
                        color: Color(0xFF0b1120),
                        offset: Offset(3, 3),
                        blurRadius: 6),
                    BoxShadow(
                        color: Color(0xFF1e293b),
                        offset: Offset(-3, -3),
                        blurRadius: 6),
                  ],
          ),
          child: Center(
            child: Icon(
              widget.item.icon,
              size: widget.iconSize,
              color: widget.isActive
                  ? const Color(0xFF22d3ee)
                  : const Color(0xFF64748b),
            ),
          ),
        ),
      ),
    );
  }
}