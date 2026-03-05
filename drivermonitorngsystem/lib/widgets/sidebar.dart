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
    return isMobile ? _buildMobileNavBar(context) : _buildDesktopSidebar(context);
  }

  // Mobile Bottom Navigation Bar — scrollable to prevent landscape overlap
  Widget _buildMobileNavBar(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      // Shorter in landscape so it doesn't eat too much vertical space
      height: isLandscape ? 52 : 64,
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 12 : 24,
            vertical: isLandscape ? 6 : 8,
          ),
          child: Row(
            children: [
              ..._getNavItems().map((item) => Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: isLandscape ? 8 : 12),
                    child: _buildNavButton(
                      item: item,
                      isMobile: true,
                      isLandscape: isLandscape,
                    ),
                  )),
              Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: isLandscape ? 8 : 12),
                child: _buildUserButton(
                    isMobile: true, isLandscape: isLandscape),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Desktop Side Navigation Bar — scrollable for smaller screens
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
          // Scrollable nav items — prevents overflow on small/landscape tablets
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: _getNavItems()
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: _buildNavButton(
                            item: item,
                            isMobile: false,
                            isLandscape: false,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
          _buildUserButton(isMobile: false, isLandscape: false),
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

  Widget _buildNavButton({
    required NavItem item,
    required bool isMobile,
    required bool isLandscape,
  }) {
    final isActive = activeTab == item.id;
    final double size = isLandscape ? 36 : (isMobile ? 40 : double.infinity);
    final double iconSize = isLandscape ? 18 : (isMobile ? 20 : 24);

    return _NavButton(
      item: item,
      isMobile: isMobile,
      isActive: isActive,
      isLandscape: isLandscape,
      size: size,
      iconSize: iconSize,
      onTap: () => onTabChanged(item.id),
    );
  }

  Widget _buildUserButton(
      {required bool isMobile, required bool isLandscape}) {
    final double btnSize = isLandscape ? 36 : (isMobile ? 40 : 48);
    final double iconSize = isLandscape ? 16 : 20;

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

class NavItem {
  final String id;
  final IconData icon;
  final String label;

  NavItem({required this.id, required this.icon, required this.label});
}

class _NavButton extends StatefulWidget {
  final NavItem item;
  final bool isMobile;
  final bool isActive;
  final bool isLandscape;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isMobile,
    required this.isActive,
    required this.isLandscape,
    required this.size,
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
          width: widget.isMobile ? widget.size : double.infinity,
          height: widget.isMobile ? widget.size : 64,
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