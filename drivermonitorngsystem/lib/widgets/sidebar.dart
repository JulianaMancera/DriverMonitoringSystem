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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    // Adjusted sizes to match the goal UI proportions
    final double barHeight = isLandscape ? 56 : 72;
    final double btnSize = isLandscape ? 40 : 48;
    final double iconSize = isLandscape ? 18 : 22;

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
      decoration: const BoxDecoration(
        color: Color(0xFF0f172a),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
      color: const Color(0xFF0f172a),
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

// Neumorphic Buttons
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
    final bool isPressed = widget.isActive || isHovered;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.btnSize,
          height: widget.btnSize,
          decoration: BoxDecoration(
            color: const Color(0xFF0f172a),
            borderRadius: BorderRadius.circular(12),
            // Outward shadows for unselected state
            boxShadow: !isPressed
                ? const [
                    BoxShadow(
                        color: Color(0xFF0b1120),
                        offset: Offset(4, 4),
                        blurRadius: 8),
                    BoxShadow(
                        color: Color(0xFF1e293b),
                        offset: Offset(-4, -4),
                        blurRadius: 8),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              if (isPressed)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _InnerShadowPainter(
                      borderRadius: 12,
                      shadowColor: const Color(0xFF0b1120),
                      lightColor: const Color(0xFF1e293b),
                    ),
                  ),
                ),
              Center(
                child: Icon(
                  widget.item.icon,
                  size: widget.iconSize,
                  color: widget.isActive
                      ? const Color(0xFF22d3ee)
                      : const Color(0xFF64748b),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
              color: Color(0xFF0b1120), offset: Offset(4, 4), blurRadius: 8),
          BoxShadow(
              color: Color(0xFF1e293b), offset: Offset(-4, -4), blurRadius: 8),
        ],
      ),
      child: Icon(Icons.person_outline,
          size: iconSize, color: const Color(0xFF64748b)),
    );
  }
}

//Custom Painter for that "Sunken" Look 
class _InnerShadowPainter extends CustomPainter {
  final double borderRadius;
  final Color shadowColor;
  final Color lightColor;

  _InnerShadowPainter({
    required this.borderRadius,
    required this.shadowColor,
    required this.lightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));

    canvas.clipRRect(rrect);

    final Paint shadowPaint = Paint()
      ..color = shadowColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    final Paint lightPaint = Paint()
      ..color = lightColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    // Draws the dark inset shadow on top/left
    canvas.drawRRect(rrect.shift(const Offset(2, 2)), shadowPaint);
    // Draws the light inset highlight on bottom/right
    canvas.drawRRect(rrect.shift(const Offset(-2, -2)), lightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}