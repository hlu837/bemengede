import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../utils/constants.dart';

// ============================================================
// NAVBAR COMPONENT
// ============================================================

class Navbar extends StatefulWidget {
  final Function(String) onScrollToSection;

  const Navbar({
    super.key,
    required this.onScrollToSection,
  });

  @override
  State<Navbar> createState() => _NavbarState();
}

class _NavbarState extends State<Navbar> {
  bool isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Container(
      color: Colors.white.withOpacity(0.95),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Center(
                            child: Text(
                              'B',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF34C759),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Bemngede',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF34C759),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '(በመንገዴ)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF34C759).withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDesktop)
                    Row(
                      children: [
                        _navLink('How It Works', 'how-it-works'),
                        _navLink('About Us', 'about'),
                        _navLink('Safety', 'safety'),
                        const SizedBox(width: 20),
                        TextButton(
                          onPressed: () => context.go(AppConstants.routeAuth),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.grey.shade700,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                          ),
                          child: const Text(
                            'Log In',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => context
                              .go('${AppConstants.routeAuth}?mode=signup'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF34C759),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    )
                  else
                    IconButton(
                      icon: Icon(
                        isMenuOpen ? Icons.close : Icons.menu,
                        color: Colors.grey.shade800,
                      ),
                      onPressed: () => setState(() => isMenuOpen = !isMenuOpen),
                    ),
                ],
              ),
            ),
            if (!isDesktop && isMenuOpen)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _mobileNavItem('How It Works', 'how-it-works'),
                    _mobileNavItem('About Us', 'about'),
                    _mobileNavItem('Safety', 'safety'),
                    const Divider(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => context.go(AppConstants.routeAuth),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text('Log In'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context
                            .go('${AppConstants.routeAuth}?mode=signup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF34C759),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Sign Up'),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(duration: 200.ms).slideY(begin: -0.1, end: 0),
          ],
        ),
      ),
    );
  }

  Widget _navLink(String label, String sectionId) {
    return TextButton(
      onPressed: () => widget.onScrollToSection(sectionId),
      style: TextButton.styleFrom(
        foregroundColor: Colors.grey.shade700,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _mobileNavItem(String label, String sectionId) {
    return InkWell(
      onTap: () {
        widget.onScrollToSection(sectionId);
        setState(() => isMenuOpen = false);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HERO SECTION
// ============================================================

class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 768;

    // NOTE: this used to be a hard `height: size.height` with `Stack(fit:
    // StackFit.expand)`, forcing every device to fit the badge + two title
    // lines + description + buttons + stats into exactly one screen height
    // with zero tolerance. Any screen shorter than that content (smaller
    // phones, ones with a tall status bar, etc.) overflowed and rendered
    // clipped/broken. `minHeight` keeps the "full-bleed hero" look on
    // screens tall enough for it, but lets the section grow instead of
    // clipping on ones that aren't.
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: size.height),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/hero-bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey.shade300,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported,
                          size: 64,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Hero image not found\nPlace hero-bg.jpg in assets/images/',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.55),
                    Colors.black.withOpacity(0.45),
                    Colors.black.withOpacity(0.65),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 60),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(
                        color: Colors.amber.shade400.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🇪🇹', style: TextStyle(fontSize: 20)),
                        const SizedBox(width: 8),
                        Text(
                          "Ethiopia's First Peer-to-Peer Delivery",
                          style: TextStyle(
                            color: Colors.amber.shade400,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 200.ms)
                      .slideY(begin: 0.3, end: 0),
                  const SizedBox(height: 32),
                  Text(
                    'Send & Receive',
                    style: TextStyle(
                      fontSize: isDesktop ? 64 : 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: -1,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 400.ms)
                      .slideY(begin: 0.3, end: 0),
                  const SizedBox(height: 8),
                  Text(
                    'Packages Faster',
                    style: TextStyle(
                      fontSize: isDesktop ? 56 : 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade400,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 500.ms)
                      .slideY(begin: 0.3, end: 0),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Text(
                      'Connect with verified travelers heading your way. Save up to 70% on delivery costs while supporting your community.',
                      style: TextStyle(
                        fontSize: isDesktop ? 18 : 16,
                        color: Colors.white.withOpacity(0.85),
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms, delay: 600.ms)
                      .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 40),
                  if (isDesktop)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _heroButton(
                          icon: Icons.flight_takeoff,
                          label: "I'm a Traveler",
                          onTap: () => context
                              .go('${AppConstants.routeAuth}?mode=signup'),
                        ),
                        const SizedBox(width: 16),
                        _heroButton(
                          icon: Icons.local_shipping,
                          label: 'Send a Package',
                          onTap: () => context
                              .go('${AppConstants.routeAuth}?mode=signup'),
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 700.ms)
                        .slideY(begin: 0.2, end: 0)
                  else
                    Column(
                      children: [
                        _heroButton(
                          icon: Icons.flight_takeoff,
                          label: "I'm a Traveler",
                          onTap: () => context
                              .go('${AppConstants.routeAuth}?mode=signup'),
                          fullWidth: true,
                        ),
                        const SizedBox(height: 12),
                        _heroButton(
                          icon: Icons.local_shipping,
                          label: 'Send a Package',
                          onTap: () => context
                              .go('${AppConstants.routeAuth}?mode=signup'),
                          fullWidth: true,
                        ),
                      ],
                    )
                        .animate()
                        .fadeIn(duration: 600.ms, delay: 700.ms)
                        .slideY(begin: 0.2, end: 0),
                  const SizedBox(height: 64),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: isDesktop
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _statItem('70%', 'Cost Savings'),
                              _verticalDivider(),
                              _statItem('100%', 'KYC Verified'),
                              _verticalDivider(),
                              _statItem('100%', 'Escrow Secure'),
                            ],
                          )
                        : Column(
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  _statItem('70%', 'Cost Savings'),
                                  _statItem('100%', 'KYC Verified'),
                                ],
                              ),
                              const SizedBox(height: 20),
                              _statItem('100%', 'Escrow Secure'),
                            ],
                          ),
                  ).animate().fadeIn(duration: 600.ms, delay: 900.ms),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _heroButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF34C759),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  static Widget _statItem(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Color(0xFF34C759),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.7),
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  static Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 40,
      color: Colors.white.withOpacity(0.2),
    );
  }
}

// ============================================================
// HOW IT WORKS
// ============================================================

class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key});

  static const List<Map<String, dynamic>> steps = [
    {
      'icon': Icons.person_add_outlined,
      'title': 'Sign Up',
      'description': 'Create your account as a traveler or sender in minutes.',
    },
    {
      'icon': Icons.search_outlined,
      'title': 'Find a Match',
      'description': 'Browse verified travelers heading to your destination.',
    },
    {
      'icon': Icons.local_shipping_outlined,
      'title': 'Send Package',
      'description': 'Hand over your package with secure escrow protection.',
    },
    {
      'icon': Icons.check_circle_outline,
      'title': 'Confirm Delivery',
      'description':
          'Track and confirm safe delivery. Release payment upon receipt.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 768;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        children: [
          const Text(
            'SIMPLE PROCESS',
            style: TextStyle(
              color: Color(0xFF34C759),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'How It Works',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'Get your packages delivered by trusted travelers in 4 simple steps',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 56),
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: steps.asMap().entries.map((entry) {
                return Expanded(
                  child: _stepCard(
                    index: entry.key,
                    icon: entry.value['icon'] as IconData,
                    title: entry.value['title'] as String,
                    description: entry.value['description'] as String,
                    showConnector: entry.key < steps.length - 1,
                  ),
                );
              }).toList(),
            )
          else
            Column(
              children: steps.asMap().entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: _stepCard(
                    index: entry.key,
                    icon: entry.value['icon'] as IconData,
                    title: entry.value['title'] as String,
                    description: entry.value['description'] as String,
                    showConnector: false,
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  static Widget _stepCard({
    required int index,
    required IconData icon,
    required String title,
    required String description,
    required bool showConnector,
  }) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: const Color(0xFF34C759),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade500,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (showConnector)
          Positioned(
            right: -8,
            top: 0,
            bottom: 0,
            child: Center(
              child: Container(
                width: 16,
                height: 2,
                color: Colors.grey.shade300,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================
// ABOUT SECTION
// ============================================================

class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  static const List<Map<String, dynamic>> features = [
    {
      'icon': Icons.public_outlined,
      'title': 'Connecting Ethiopia',
      'description':
          'Bridging distances across cities with trusted peer delivery.',
    },
    {
      'icon': Icons.people_outline,
      'title': 'Community Driven',
      'description': 'Built by Ethiopians, for Ethiopians. Powered by trust.',
    },
    {
      'icon': Icons.favorite_border,
      'title': 'Trust & Care',
      'description':
          'Every package is handled with care and verified delivery.',
    },
    {
      'icon': Icons.track_changes_outlined,
      'title': 'Our Mission',
      'description':
          'Making delivery accessible, affordable, and reliable for everyone.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      color: const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: const TextSpan(
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
              children: [
                TextSpan(text: 'About '),
                TextSpan(
                  text: 'Bemngede',
                  style: TextStyle(color: Color(0xFF34C759)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Text(
              "Ethiopia's trusted peer-to-peer delivery platform connecting senders with verified travelers.",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 56),
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _storyColumn()),
                const SizedBox(width: 48),
                Expanded(
                  child: GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 1.15,
                    children: features.map((f) => _featureCard(f)).toList(),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _storyColumn(),
                const SizedBox(height: 32),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.05,
                  children: features.map((f) => _featureCard(f)).toList(),
                ),
              ],
            ),
          const SizedBox(height: 56),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
            decoration: BoxDecoration(
              color: const Color(0xFF34C759),
              borderRadius: BorderRadius.circular(20),
            ),
            child: isDesktop
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _statItem('500+', 'Packages Delivered'),
                      _statItem('200+', 'Verified Travelers'),
                      _statItem('50%', 'Average Savings'),
                      _statItem('4.9★', 'User Rating'),
                    ],
                  )
                : GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    childAspectRatio: 2.2,
                    children: [
                      _statItem('500+', 'Packages Delivered'),
                      _statItem('200+', 'Verified Travelers'),
                      _statItem('50%', 'Average Savings'),
                      _statItem('4.9★', 'User Rating'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static Widget _storyColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Our Story',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Bemngede was born from a simple idea: why let empty luggage space go to waste when someone needs to send a package?',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade500,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "We started in Addis Ababa, connecting travelers with people who needed to send items across Ethiopia. Today, we're growing to serve the entire country.",
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade500,
            height: 1.7,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Our platform ensures every transaction is safe, verified, and fair for both travelers and senders.',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade500,
            height: 1.7,
          ),
        ),
      ],
    );
  }

  static Widget _featureCard(Map<String, dynamic> feature) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              feature['icon'] as IconData,
              color: const Color(0xFF34C759),
              size: 22,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            feature['title'] as String,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            feature['description'] as String,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _statItem(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.75),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// WHY CHOOSE US
// ============================================================

class WhyChooseUs extends StatelessWidget {
  const WhyChooseUs({super.key});

  static const List<Map<String, dynamic>> features = [
    {
      'icon': Icons.attach_money_outlined,
      'title': 'Save Up to 70%',
      'description':
          'Peer-to-peer delivery costs a fraction of traditional shipping.',
    },
    {
      'icon': Icons.verified_user_outlined,
      'title': 'Secure & Verified',
      'description': 'All travelers undergo KYC verification for your safety.',
    },
    {
      'icon': Icons.timer_outlined,
      'title': 'Fast Delivery',
      'description':
          'Packages travel with real people, not through warehouses.',
    },
    {
      'icon': Icons.people_outline,
      'title': 'Community Trust',
      'description': 'Ratings and reviews build a trusted network.',
    },
    {
      'icon': Icons.public_outlined,
      'title': 'Global Reach',
      'description': 'Connect with travelers heading anywhere in Ethiopia.',
    },
    {
      'icon': Icons.headset_mic_outlined,
      'title': 'Dedicated Support',
      'description': 'Our team is available to help you every step of the way.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        children: [
          const Text(
            'WHY CHOOSE US',
            style: TextStyle(
              color: Color(0xFF34C759),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Why Bemngede?',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'We combine technology with community trust to deliver the best peer-to-peer experience.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 56),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: isDesktop ? 3 : 1,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
            childAspectRatio: isDesktop ? 1.35 : 2.2,
            children: features.map((f) => _featureCard(f)).toList(),
          ),
        ],
      ),
    );
  }

  static Widget _featureCard(Map<String, dynamic> feature) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              feature['icon'] as IconData,
              size: 26,
              color: const Color(0xFF34C759),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            feature['title'] as String,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            feature['description'] as String,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TESTIMONIALS
// ============================================================

class Testimonials extends StatelessWidget {
  const Testimonials({super.key});

  static const List<String> senderBenefits = [
    'Save up to 70% on delivery costs',
    'Track your package in real-time',
    'Secure escrow payment protection',
    'Verified traveler network',
  ];

  static const List<String> travelerBenefits = [
    'Earn money while you travel',
    'Flexible scheduling',
    'KYC verified for trust',
    'Instant payout on delivery',
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        children: [
          const Text(
            'TESTIMONIALS',
            style: TextStyle(
              color: Color(0xFF34C759),
              fontWeight: FontWeight.w600,
              fontSize: 13,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'What Our Users Say',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              'Join thousands of happy senders and travelers across Ethiopia.',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade500,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 56),
          if (isDesktop)
            Row(
              children: [
                Expanded(
                  child: _benefitCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'For Senders',
                    benefits: senderBenefits,
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _benefitCard(
                    icon: Icons.flight_takeoff,
                    title: 'For Travelers',
                    benefits: travelerBenefits,
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                _benefitCard(
                  icon: Icons.local_shipping_outlined,
                  title: 'For Senders',
                  benefits: senderBenefits,
                ),
                const SizedBox(height: 20),
                _benefitCard(
                  icon: Icons.flight_takeoff,
                  title: 'For Travelers',
                  benefits: travelerBenefits,
                ),
              ],
            ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(50),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.verified_user,
                  color: Color(0xFF34C759),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  'Trusted by 500+ users across Ethiopia',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _benefitCard({
    required IconData icon,
    required String title,
    required List<String> benefits,
  }) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFF34C759),
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ...benefits.map((benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 2),
                      child: const Icon(
                        Icons.check_circle,
                        color: Color(0xFF22C55E),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        benefit,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade700,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

// ============================================================
// SAFETY SECTION
// ============================================================

class SafetySection extends StatelessWidget {
  const SafetySection({super.key});

  static const List<Map<String, dynamic>> safetyFeatures = [
    {
      'icon': Icons.person_search_outlined,
      'title': 'KYC Verified Travelers',
      'description':
          'Every traveler undergoes identity verification before they can carry packages.',
    },
    {
      'icon': Icons.lock_outline,
      'title': 'Escrow Payments',
      'description':
          'Your payment is held securely until the package is safely delivered.',
    },
    {
      'icon': Icons.fact_check_outlined,
      'title': 'Delivery Proof',
      'description':
          'Photo confirmation and recipient signature required for every delivery.',
    },
    {
      'icon': Icons.account_balance_outlined,
      'title': 'Manual Review',
      'description':
          'Our team manually reviews every transaction for added security.',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _contentColumn()),
                const SizedBox(width: 48),
                Expanded(child: _safetyVisual()),
              ],
            )
          : Column(
              children: [
                _contentColumn(),
                const SizedBox(height: 48),
                _safetyVisual(),
              ],
            ),
    );
  }

  static Widget _contentColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF34C759).withOpacity(0.15),
            borderRadius: BorderRadius.circular(50),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.verified_user,
                color: Color(0xFF34C759),
                size: 16,
              ),
              const SizedBox(width: 8),
              const Text(
                'Safety First',
                style: TextStyle(
                  color: Color(0xFF34C759),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Your Safety is Our Priority',
          style: TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "We've built multiple layers of security to ensure every package and every traveler is protected.",
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade400,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 40),
        ...safetyFeatures.map((f) => _safetyItem(f)),
      ],
    );
  }

  static Widget _safetyItem(Map<String, dynamic> feature) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              feature['icon'] as IconData,
              color: const Color(0xFF34C759),
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature['title'] as String,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  feature['description'] as String,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _safetyVisual() {
    return Container(
      width: double.infinity,
      height: 320,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF34C759).withOpacity(0.15),
            const Color(0xFF34C759).withOpacity(0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ...List.generate(3, (i) {
            return Container(
              width: 160.0 + (i * 60),
              height: 160.0 + (i * 60),
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withOpacity(0.06 - (i * 0.015)),
                shape: BoxShape.circle,
              ),
            )
                .animate(
                  onPlay: (controller) => controller.repeat(),
                )
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.05, 1.05),
                  duration: 3000.ms,
                  delay: (i * 400).ms,
                );
          }),
          const Icon(
            Icons.verified_user,
            size: 72,
            color: Color(0xFF34C759),
          ),
          Positioned(
            top: 30,
            right: 40,
            child: _floatingIcon(Icons.person_search_outlined),
          ),
          Positioned(
            bottom: 40,
            left: 30,
            child: _floatingIcon(Icons.lock_outline),
          ),
          Positioned(
            top: 100,
            right: 20,
            child: _floatingIcon(Icons.fact_check_outlined, size: 40),
          ),
          Positioned(
            bottom: 80,
            right: 50,
            child: _floatingIcon(Icons.account_balance_outlined, size: 40),
          ),
        ],
      ),
    );
  }

  static Widget _floatingIcon(IconData icon, {double size = 48}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        icon,
        color: const Color(0xFF34C759),
        size: size * 0.45,
      ),
    )
        .animate(
          onPlay: (controller) => controller.repeat(reverse: true),
        )
        .moveY(
          begin: -6,
          end: 6,
          duration: 2500.ms,
        );
  }
}

// ============================================================
// CTA SECTION
// ============================================================

class CTASection extends StatelessWidget {
  const CTASection({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF34C759),
            Color(0xFF2aa846),
          ],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
      child: Column(
        children: [
          const Text(
            'Ready to Get Started?',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Text(
              "Join Ethiopia's fastest growing peer-to-peer delivery community today.",
              style: TextStyle(
                fontSize: 18,
                color: Colors.white.withOpacity(0.8),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 40),
          if (isDesktop)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ctaButton(
                  icon: Icons.flight_takeoff,
                  label: "I'm a Traveler",
                  onTap: () =>
                      context.go('${AppConstants.routeAuth}?mode=signup'),
                ),
                const SizedBox(width: 16),
                _ctaButton(
                  icon: Icons.local_shipping,
                  label: 'Send a Package',
                  onTap: () =>
                      context.go('${AppConstants.routeAuth}?mode=signup'),
                ),
              ],
            )
          else
            Column(
              children: [
                _ctaButton(
                  icon: Icons.flight_takeoff,
                  label: "I'm a Traveler",
                  onTap: () =>
                      context.go('${AppConstants.routeAuth}?mode=signup'),
                  fullWidth: true,
                ),
                const SizedBox(height: 12),
                _ctaButton(
                  icon: Icons.local_shipping,
                  label: 'Send a Package',
                  onTap: () =>
                      context.go('${AppConstants.routeAuth}?mode=signup'),
                  fullWidth: true,
                ),
              ],
            ),
        ],
      ),
    );
  }

  static Widget _ctaButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 16),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF34C759),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// FOOTER
// ============================================================

class Footer extends StatelessWidget {
  const Footer({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 768;

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 24),
      child: Column(
        children: [
          if (isDesktop)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _brandColumn(),
                ),
                Expanded(
                  child: _linkColumn(
                    'Quick Links',
                    [
                      'How It Works',
                      'About Us',
                      'Safety',
                      'Terms',
                      'Become a Traveler',
                      'Send Package',
                    ],
                  ),
                ),
                Expanded(
                  child: _contactColumn(),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _brandColumn(),
                const SizedBox(height: 40),
                _linkColumn(
                  'Quick Links',
                  [
                    'How It Works',
                    'About Us',
                    'Safety',
                    'Terms',
                    'Become a Traveler',
                    'Send Package',
                  ],
                ),
                const SizedBox(height: 40),
                _contactColumn(),
              ],
            ),
          const SizedBox(height: 48),
          const Divider(color: Color(0xFF334155)),
          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} Bemngede (በመንገዴ). All rights reserved.',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _brandColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFF34C759).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text(
                  'B',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF34C759),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bemngede',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF34C759),
                  ),
                ),
                Text(
                  '(በመንገዴ)',
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF34C759).withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(
            "Ethiopia's trusted peer-to-peer delivery platform. Connecting travelers with senders safely and affordably.",
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            _socialButton(Icons.facebook),
            const SizedBox(width: 10),
            _socialButton(Icons.chat_bubble_outline),
            const SizedBox(width: 10),
            _socialButton(Icons.camera_alt_outlined),
          ],
        ),
      ],
    );
  }

  static Widget _linkColumn(String title, List<String> links) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        ...links.map((link) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () {},
                child: Text(
                  link,
                  style: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                  ),
                ),
              ),
            )),
      ],
    );
  }

  static Widget _contactColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Contact Us',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        _contactItem(Icons.location_on_outlined, 'Addis Ababa, Ethiopia'),
        const SizedBox(height: 14),
        _contactItem(Icons.phone_outlined, '+251 91 234 5678'),
        const SizedBox(height: 14),
        _contactItem(Icons.email_outlined, 'support@bemngede.com'),
      ],
    );
  }

  static Widget _contactItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: const Color(0xFF34C759),
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  static Widget _socialButton(IconData icon) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}