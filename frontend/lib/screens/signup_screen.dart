import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/responsive.dart';
import '../services/api_exception.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';

/// Sign Up Screen (회원가입 페이지 matching screenshot)
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  /// Blocks a second tap while the request is in flight — a double tap would
  /// otherwise try to create the account twice and fail on DUPLICATE_EMAIL.
  bool _isSubmitting = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  final RegExp _emailRegExp = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.coralRed,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onSignupPressed() async {
    if (_isSubmitting) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();
    final nickname = _nameController.text.trim();

    if (nickname.isEmpty) {
      _showError('이름(닉네임)을 입력해 주세요.');
      return;
    }

    if (email.isEmpty) {
      _showError('이메일을 입력해 주세요.');
      return;
    }

    if (!_emailRegExp.hasMatch(email)) {
      _showError('유효한 이메일 형식을 입력해 주세요.');
      return;
    }

    if (password.isEmpty) {
      _showError('비밀번호를 입력해 주세요.');
      return;
    }

    if (password.length < 8 || password.length > 64) {
      _showError('비밀번호는 8자 이상 64자 이하로 입력해 주세요.');
      return;
    }

    if (password != confirmPassword) {
      _showError('비밀번호가 일치하지 않습니다.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await AuthService.instance
          .signup(email: email, password: password, nickname: nickname);
      // Signup does not return a token, so log in with the same credentials
      // rather than making the user type them a second time.
      await AuthService.instance.login(email: email, password: password);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('회원가입이 성공적으로 완료되었습니다!'),
          backgroundColor: AppColors.lightMint,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    } on ApiException catch (e) {
      // DUPLICATE_EMAIL lands here with the server's own wording.
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E20), // Dark charcoal background matching design
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 600,
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Back Arrow (<)
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.chevron_left_rounded,
                      color: AppColors.white,
                      size: 28,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Scrollable Content Body
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. Heading Title: Create \n Your Account
                      Text(
                        'Create\nYour Account',
                        style: GoogleFonts.outfit(
                          fontSize: 38,
                          fontWeight: FontWeight.w400,
                          color: AppColors.white,
                          height: 1.15,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 48),

                      // 3. Name Input Field (이름 닉네임)
                      _buildPillInputField(
                        controller: _nameController,
                        hintText: '이름 (닉네임)',
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 14),

                      // 4. Email Input Field (아이디 이메일)
                      _buildPillInputField(
                        controller: _emailController,
                        hintText: '아이디 (이메일)',
                        icon: Icons.mail_outline_rounded,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),

                      // 5. Password Input Field (비밀번호)
                      _buildPillInputField(
                        controller: _passwordController,
                        hintText: '비밀번호',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        suffixIcon: GestureDetector(
                          onTap: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          child: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: const Color(0xFF8E9198),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 6. Confirm Password Input Field (비밀번호 확인)
                      _buildPillInputField(
                        controller: _confirmPasswordController,
                        hintText: '비밀번호 확인',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscureConfirmPassword,
                        suffixIcon: GestureDetector(
                          onTap: () {
                            setState(() {
                              _obscureConfirmPassword = !_obscureConfirmPassword;
                            });
                          },
                          child: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: const Color(0xFF8E9198),
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 52),

                      // 7. Main White Sign Up Button (회원가입하기)
                      GestureDetector(
                        onTap: _onSignupPressed,
                        child: Container(
                          width: double.infinity,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Center(
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                      color: Color(0xFF1E1E20),
                                    ),
                                  )
                                : const Text(
                                    '회원가입하기',
                                    style: TextStyle(
                                      fontFamily: AppFonts.pretendard,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF1E1E20),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 8. Horizontal Divider with "or" (Tightly grouped)
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              color: const Color(0xFF383A3E),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 14.0),
                            child: Text(
                              'or',
                              style: TextStyle(
                                fontFamily: AppFonts.pretendard,
                                fontSize: 13,
                                color: Color(0xFF7A7D84),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              height: 1,
                              color: const Color(0xFF383A3E),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // 9. Google Social Sign Up Pill Button (Google로 계속하기 with assets/images/ic_google.png support)
                      _buildSocialPillButton(
                        icon: Image.asset(
                          'assets/images/ic_google.png',
                          width: 22,
                          height: 22,
                          errorBuilder: (context, error, stackTrace) => const _GoogleGLogo(size: 20),
                        ),
                        text: 'Google로 시작하기',
                        onTap: () async {
                          final nav = Navigator.of(context);
                          setState(() => _isSubmitting = true);
                          try {
                            await AuthService.instance.performGoogleSignIn();
                          } catch (_) {}
                          if (!mounted) return;
                          setState(() => _isSubmitting = false);
                          nav.pushAndRemoveUntil(
                            MaterialPageRoute(builder: (context) => const HomeScreen()),
                            (route) => false,
                          );
                        },
                      ),
                      const SizedBox(height: 64),

                      // 10. Bottom Login Prompt: 이미 계정이 있으신가요? 로그인하기 (Pushed lower to bottom)
                      Center(
                        child: GestureDetector(
                          onTap: () {
                            Navigator.of(context).pop();
                          },
                          child: RichText(
                            text: const TextSpan(
                              style: TextStyle(
                                fontFamily: AppFonts.pretendard,
                                fontSize: 13,
                                color: Color(0xFF7A7D84),
                              ),
                              children: [
                                TextSpan(text: '이미 계정이 있으신가요? '),
                                TextSpan(
                                  text: '로그인하기',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Pill-shaped Input Field matching screenshot
  Widget _buildPillInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF2C2D30),
        borderRadius: BorderRadius.circular(29),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        style: const TextStyle(
          fontFamily: AppFonts.pretendard,
          fontSize: 15,
          color: AppColors.white,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: const TextStyle(
            fontFamily: AppFonts.pretendard,
            fontSize: 15,
            color: Color(0xFF7A7D84),
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 22, right: 14),
            child: Icon(
              icon,
              color: const Color(0xFF8E9198),
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 56),
          suffixIcon: suffixIcon != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 18.0),
                  child: suffixIcon,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(minWidth: 48),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }

  /// Pill-shaped Social Login Button matching screenshot
  Widget _buildSocialPillButton({
    required Widget icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 58,
        decoration: BoxDecoration(
          color: const Color(0xFF2C2D30),
          borderRadius: BorderRadius.circular(29),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              text,
              style: const TextStyle(
                fontFamily: AppFonts.pretendard,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: AppColors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom Colorful Google 'G' Logo Widget
class _GoogleGLogo extends StatelessWidget {
  final double size;

  const _GoogleGLogo({this.size = 20});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(
        painter: _GoogleGLogoPainter(),
      ),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  const _GoogleGLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.24;
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.24;
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.24;
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.24;

    final rect = Rect.fromCircle(center: center, radius: radius * 0.76);

    // Red Arc (Top)
    canvas.drawArc(rect, -2.3, 1.8, false, redPaint);
    // Yellow Arc (Left)
    canvas.drawArc(rect, 2.4, 1.4, false, yellowPaint);
    // Green Arc (Bottom)
    canvas.drawArc(rect, 0.8, 1.6, false, greenPaint);
    // Blue Arc (Right)
    canvas.drawArc(rect, -0.5, 1.3, false, bluePaint);

    // Center blue crossbar
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    final barRect = Rect.fromLTWH(w * 0.45, h * 0.4, w * 0.5, h * 0.22);
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
