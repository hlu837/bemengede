import 'package:flutter/material.dart';
import 'landing_components.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {
    'how-it-works': GlobalKey(),
    'about': GlobalKey(),
    'safety': GlobalKey(),
  };

  void scrollToSection(String sectionId) {
    final key = _sectionKeys[sectionId];
    if (key != null) {
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverToBoxAdapter(
            child: Navbar(onScrollToSection: scrollToSection),
          ),
          const SliverToBoxAdapter(child: HeroSection()),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _sectionKeys['how-it-works'],
              child: const HowItWorks(),
            ),
          ),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _sectionKeys['about'],
              child: const AboutSection(),
            ),
          ),
          const SliverToBoxAdapter(child: WhyChooseUs()),
          const SliverToBoxAdapter(child: Testimonials()),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _sectionKeys['safety'],
              child: const SafetySection(),
            ),
          ),
          const SliverToBoxAdapter(child: CTASection()),
          const SliverToBoxAdapter(child: Footer()),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
