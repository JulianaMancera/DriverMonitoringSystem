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
    final double barHeight = isLandscape ? 56 : 72;
    final double btnSize   = isLandscape ? 40 : 48;
    final double iconSize  = isLandscape ? 18 : 22;
    final items = _getNavItems();

    final activeIndex = items.indexWhere((i) => i.id == activeTab);

    return Container(
      height: barHeight,
      decoration: const BoxDecoration(color: Color(0xFF0f172a)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _SlidingNavBar(
            items: items,
            activeIndex: activeIndex,
            btnSize: btnSize,
            iconSize: iconSize,
            onTabChanged: onTabChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context) {
    final items       = _getNavItems();
    final activeIndex = items.indexWhere((i) => i.id == activeTab);

    return Container(
      width: 96,
      color: const Color(0xFF0f172a),
      child: Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.show_chart, size: 32, color: Color(0xFF22d3ee)),
          const SizedBox(height: 32),
          Expanded(
            child: _SlidingDesktopNav(
              items: items,
              activeIndex: activeIndex,
              onTabChanged: onTabChanged,
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
      NavItem(id: 'home',      icon: Icons.home,      label: 'Home'),
      NavItem(id: 'monitor',   icon: Icons.videocam,  label: 'Monitor'),
      NavItem(id: 'analytics', icon: Icons.analytics, label: 'Analytics'),
      NavItem(id: 'history',   icon: Icons.history,   label: 'History'),
      NavItem(id: 'settings',  icon: Icons.settings,  label: 'Settings'),
    ];
  }
}

class _SlidingNavBar extends StatefulWidget {
  final List<NavItem> items;
  final int activeIndex;
  final double btnSize;
  final double iconSize;
  final Function(String) onTabChanged;

  const _SlidingNavBar({
    required this.items,
    required this.activeIndex,
    required this.btnSize,
    required this.iconSize,
    required this.onTabChanged,
  });

  @override
  State<_SlidingNavBar> createState() => _SlidingNavBarState();
}

class _SlidingNavBarState extends State<_SlidingNavBar> {
  int get _totalItems => widget.items.length + 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth   = constraints.maxWidth;
        final itemWidth    = totalWidth / _totalItems;
        final pillWidth    = widget.btnSize;
        final pillOffset   = (itemWidth - pillWidth) / 2;
        final pillLeft     = widget.activeIndex * itemWidth + pillOffset;

        return Stack(
          alignment: Alignment.center,
          children: [

            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              left: pillLeft,
              top: (constraints.maxHeight - widget.btnSize) / 2,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeInOutCubic,
                width: pillWidth,
                height: widget.btnSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF0f172a),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0b1120).withValues(alpha: 0.9),
                      offset: const Offset(3, 3),
                      blurRadius: 6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF1e293b).withValues(alpha: 0.9),
                      offset: const Offset(-3, -3),
                      blurRadius: 6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF22d3ee).withValues(alpha: 0.12),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                ...widget.items.asMap().entries.map((entry) {
                  final i      = entry.key;
                  final item   = entry.value;
                  final active = i == widget.activeIndex;

                  return GestureDetector(
                    onTap: () => widget.onTabChanged(item.id),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: itemWidth,
                      height: widget.btnSize,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: child,
                          ),
                          child: Icon(
                            item.icon,
                            key: ValueKey('${item.id}_$active'),
                            size: active
                                ? widget.iconSize + 1
                                : widget.iconSize,
                            color: active
                                ? const Color(0xFF22d3ee)
                                : const Color(0xFF64748b),
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                SizedBox(
                  width: itemWidth,
                  height: widget.btnSize,
                  child: Center(
                    child: Icon(
                      Icons.person_outline,
                      size: widget.iconSize,
                      color: const Color(0xFF64748b),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _SlidingDesktopNav extends StatefulWidget {
  final List<NavItem> items;
  final int activeIndex;
  final Function(String) onTabChanged;

  const _SlidingDesktopNav({
    required this.items,
    required this.activeIndex,
    required this.onTabChanged,
  });

  @override
  State<_SlidingDesktopNav> createState() => _SlidingDesktopNavState();
}

class _SlidingDesktopNavState extends State<_SlidingDesktopNav> {
  static const double _btnSize    = 64.0;
  static const double _spacing    = 24.0;
  static const double _itemHeight = _btnSize + _spacing;

  @override
  Widget build(BuildContext context) {
    final pillTop = widget.activeIndex * _itemHeight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [

            AnimatedPositioned(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              top: pillTop,
              left: 0,
              right: 0,
              child: Container(
                width: _btnSize,
                height: _btnSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF0f172a),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0b1120).withValues(alpha: 0.9),  // Ln 274
                      offset: const Offset(3, 3),
                      blurRadius: 6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF1e293b).withValues(alpha: 0.9),  // Ln 279
                      offset: const Offset(-3, -3),
                      blurRadius: 6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF22d3ee).withValues(alpha: 0.12), // Ln 284
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ),

            Column(
              children: widget.items.asMap().entries.map((entry) {
                final i      = entry.key;
                final item   = entry.value;
                final active = i == widget.activeIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: _spacing),
                  child: GestureDetector(
                    onTap: () => widget.onTabChanged(item.id),
                    child: SizedBox(
                      width: _btnSize,
                      height: _btnSize,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: child,
                          ),
                          child: Icon(
                            item.icon,
                            key: ValueKey('${item.id}_$active'),
                            size: active ? 26 : 24,
                            color: active
                                ? const Color(0xFF22d3ee)
                                : const Color(0xFF64748b),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
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
              color: Color(0xFF0b1120),
              offset: Offset(4, 4),
              blurRadius: 8),
          BoxShadow(
              color: Color(0xFF1e293b),
              offset: Offset(-4, -4),
              blurRadius: 8),
        ],
      ),
      child: Icon(Icons.person_outline,
          size: iconSize, color: const Color(0xFF64748b)),
    );
  }
}