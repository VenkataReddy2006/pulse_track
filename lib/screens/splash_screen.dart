import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';
import 'main_nav_screen.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _tiltController;
  late AnimationController _glintController;

  late Animation<double> _logoFade;
  late Animation<double> _logoScale;
  late Animation<double> _logoTilt;
  late Animation<double> _glintPosition;

  final List<Offset> _particles = List.generate(40,
      (i) => Offset(math.Random().nextDouble(), math.Random().nextDouble()));

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _tiltController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);

    _glintController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _mainController,
          curve: const Interval(0.0, 0.5, curve: Curves.easeIn)),
    );

    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
          parent: _mainController,
          curve: const Interval(0.0, 0.6, curve: Curves.easeInOut)),
    );

    _logoTilt = Tween<double>(begin: -0.15, end: 0.15).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.easeInOut),
    );

    _glintPosition = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _glintController, curve: Curves.easeInOut),
    );

    _mainController.forward();
    _navigateToNext();
  }

  void _navigateToNext() async {
    await Provider.of<AuthProvider>(context, listen: false).loadUser();
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    Widget nextScreen;
    if (authProvider.isAuthenticated) {
      nextScreen = const MainNavScreen();
    } else if (authProvider.shouldShowOnboarding) {
      nextScreen = const OnboardingScreen();
    } else {
      nextScreen = const LoginScreen();
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 1000),
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _tiltController.dispose();
    _glintController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 3D Moving Particle Space
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _tiltController,
              builder: (context, child) {
                return CustomPaint(
                  painter:
                      ParticleSpacePainter(_particles, _tiltController.value),
                );
              },
            ),
          ),

          // Central 3D Content
          Center(
            child: FadeTransition(
              opacity: _logoFade,
              child: ScaleTransition(
                scale: _logoScale,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 3D Tilted Icon with Glint
                    AnimatedBuilder(
                      animation: _tiltController,
                      builder: (context, child) {
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.002) // Perspective
                            ..rotateY(_logoTilt.value)
                            ..rotateX(_logoTilt.value * 0.5),
                          alignment: Alignment.center,
                          child: Stack(
                            children: [
                              // Outer Glow
                              Container(
                                width: 180,
                                height: 180,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryRed
                                          .withValues(alpha: 0.2),
                                      blurRadius: 80,
                                      spreadRadius: 10,
                                    ),
                                  ],
                                ),
                              ),
                              // The Icon
                              ClipOval(
                                child: Container(
                                  width: 180,
                                  height: 180,
                                  child: Image.asset(
                                    'assets/images/app_icon.png',
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                      Icons.favorite,
                                      color: AppTheme.primaryRed,
                                      size: 100,
                                    ),
                                  ),
                                ),
                              ),
                              // Animated Glint (The Shine Effect)
                              Positioned.fill(
                                child: AnimatedBuilder(
                                  animation: _glintPosition,
                                  builder: (context, child) {
                                    return FractionallySizedBox(
                                      widthFactor: 2.0,
                                      child: Transform(
                                        transform: Matrix4.translationValues(
                                            _glintPosition.value * 180, 0, 0)
                                          ..rotateZ(0.5),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.white
                                                    .withValues(alpha: 0.0),
                                                Colors.white
                                                    .withValues(alpha: 0.3),
                                                Colors.white
                                                    .withValues(alpha: 0.0),
                                              ],
                                              stops: const [0.35, 0.5, 0.65],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 60),

                    // Futuristic Title
                    ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [
                          Colors.white,
                          Colors.white.withValues(alpha: 0.7)
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ).createShader(bounds),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'PULSE',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'TRACK',
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4,
                              color: AppTheme.primaryRed,
                              shadows: [
                                Shadow(
                                  color: AppTheme.primaryRed
                                      .withValues(alpha: 0.5),
                                  blurRadius: 15,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      'THE FUTURE OF WELLNESS',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.4),
                        letterSpacing: 8,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Progress
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _logoFade,
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 2,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryRed.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedBuilder(
                      animation: _mainController,
                      builder: (context, child) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 40 * _mainController.value,
                            color: AppTheme.primaryRed,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ParticleSpacePainter extends CustomPainter {
  final List<Offset> particles;
  final double progress;
  ParticleSpacePainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < particles.length; i++) {
      final p = particles[i];
      // Parallax effect based on index
      double speed = 0.05 + (i % 10) * 0.01;
      double x =
          (p.dx * size.width + (progress * size.width * speed)) % size.width;
      double y = p.dy * size.height;

      double opacity = 0.1 + (math.sin(progress * math.pi * 2 + i) * 0.1);
      paint.color = Colors.white.withValues(alpha: opacity);

      // Draw as small stars
      canvas.drawCircle(Offset(x, y), 0.8, paint);

      // Some glowy ones
      if (i % 5 == 0) {
        paint.color = AppTheme.primaryRed.withValues(alpha: opacity * 0.5);
        canvas.drawCircle(Offset(x, y), 1.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(ParticleSpacePainter oldDelegate) => true;
}
