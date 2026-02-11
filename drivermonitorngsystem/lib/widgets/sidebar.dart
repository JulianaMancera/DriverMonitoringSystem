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
    return isMobile ? _buildMobileNavBar() : _buildDesktopSidebar();
  }

  // Mobile Bottom Navigation Bar
  Widget _buildMobileNavBar() {
    return Container(
      height: 64,
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ..._getNavItems().map((item) => _buildNavButton(
                item: item,
                isMobile: true,
              )),
          // User icon on mobile
          _buildUserButton(isMobile: true),
        ],
      ),
    );
  }

  // Desktop Side Navigation Bar
  Widget _buildDesktopSidebar() {
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
          // Logo at top
          const SizedBox(height: 32),
          const Icon(
            Icons.show_chart,
            size: 32,
            color: Color(0xFF22d3ee),
          ),
          const SizedBox(height: 32),

          // Navigation items
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: _getNavItems()
                    .map((item) => Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: _buildNavButton(
                            item: item,
                            isMobile: false,
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),

          // User icon at bottom
          _buildUserButton(isMobile: false),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Get navigation items list
  List<NavItem> _getNavItems() {
    return [
      NavItem(id: 'home', icon: Icons.home, label: 'Home'),
      NavItem(id: 'monitor', icon: Icons.videocam, label: 'Monitor'),
      NavItem(id: 'analytics', icon: Icons.analytics, label: 'Analytics'),
      NavItem(id: 'settings', icon: Icons.settings, label: 'Settings'),
    ];
  }

  // Individual navigation button
  Widget _buildNavButton({
    required NavItem item,
    required bool isMobile,
  }) {
    final isActive = activeTab == item.id;

    return _NavButton(
      item: item,
      isMobile: isMobile,
      isActive: isActive,
      onTap: () => onTabChanged(item.id),
    );
  }

  // User profile button
  Widget _buildUserButton({required bool isMobile}) {
    return Container(
      width: isMobile ? 40 : 48,
      height: isMobile ? 40 : 48,
      decoration: BoxDecoration(
        color: const Color(0xFF0f172a),
        shape: BoxShape.circle,
        boxShadow: [
          const BoxShadow(
            color: Color(0xFF0b1120),
            offset: Offset(3, 3),
            blurRadius: 6,
          ),
          const BoxShadow(
            color: Color(0xFF1e293b),
            offset: Offset(-3, -3),
            blurRadius: 6,
          ),
        ],
      ),
      child: IconButton(
        icon: const Icon(
          Icons.person_outline,
          size: 20,
          color: Color(0xFF64748b),
        ),
        onPressed: () {
          // Handle user profile action
        },
      ),
    );
  }
}

// Navigation item model
class NavItem {
  final String id;
  final IconData icon;
  final String label;

  NavItem({
    required this.id,
    required this.icon,
    required this.label,
  });
}

// Stateful navigation button with hover effect
class _NavButton extends StatefulWidget {
  final NavItem item;
  final bool isMobile;
  final bool isActive;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.isMobile,
    required this.isActive,
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
          width: widget.isMobile ? 40 : double.infinity,
          height: widget.isMobile ? 40 : 64,
          decoration: BoxDecoration(
            color: const Color(0xFF0f172a),
            borderRadius: BorderRadius.circular(16),
            boxShadow: shouldShowPressed
                ? [
                    // Pressed/Active state - inset shadows
                    const BoxShadow(
                      color: Color(0xFF0b1120),
                      offset: Offset(-3, -3),
                      blurRadius: 6,
                    ),
                    const BoxShadow(
                      color: Color(0xFF1e293b),
                      offset: Offset(3, 3),
                      blurRadius: 6,
                    ),
                  ]
                : [
                    // Normal state - raised shadows
                    const BoxShadow(
                      color: Color(0xFF0b1120),
                      offset: Offset(3, 3),
                      blurRadius: 6,
                    ),
                    const BoxShadow(
                      color: Color(0xFF1e293b),
                      offset: Offset(-3, -3),
                      blurRadius: 6,
                    ),
                  ],
          ),
          child: Center(
            child: Icon(
              widget.item.icon,
              size: widget.isMobile ? 20 : 24,
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