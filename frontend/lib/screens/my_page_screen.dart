import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../utils/responsive.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';
import 'login_screen.dart';

class MyPageScreen extends StatefulWidget {
  const MyPageScreen({super.key});

  @override
  State<MyPageScreen> createState() => _MyPageScreenState();
}

class _MyPageScreenState extends State<MyPageScreen> {
  bool get _isLoggedIn => ApiClient.instance.isLoggedIn;

  Future<void> _onProfileTapped() async {
    if (!_isLoggedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
      // Coming back from login flips the profile row, so redraw.
      if (mounted) setState(() {});
      return;
    }

    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkCharcoal,
        title: const Text('로그아웃', style: TextStyle(color: AppColors.white)),
        content: const Text('로그아웃하면 이 기기로는 알림도 받지 않아요.',
            style: TextStyle(color: AppColors.lightGray)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소', style: TextStyle(color: AppColors.lightGray)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('로그아웃', style: TextStyle(color: AppColors.coralRed)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    // Hand the FCM token over so the server stops sending to this phone.
    // Losing it would leave a logged-out device still getting reminders.
    final fcmToken = await PushService.instance.currentToken();
    await AuthService.instance.logout(fcmToken: fcmToken);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: SafeArea(
        child: ResponsiveContainer(
          maxWidth: 600,
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Navigation Row (Back Arrow)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: AppColors.white,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Page Title: "My page"
              Text(
                'My page',
                style: GoogleFonts.outfit(
                  fontSize: 34,
                  fontWeight: FontWeight.w400,
                  color: AppColors.white,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 28),

              // User Profile Section (Maintains Guest Profile & Sign Up / Log In)
              GestureDetector(
                onTap: _onProfileTapped,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: AppColors.slateDarkGray.withAlpha(150),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.slateDarkGray,
                          width: 1,
                        ),
                      ),
                      child: ClipOval(
                        child: (_isLoggedIn && ApiClient.instance.currentUser?.photoUrl != null)
                            ? Image.network(
                                ApiClient.instance.currentUser!.photoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => const Icon(
                                  Icons.person_rounded,
                                  color: AppColors.lightGray,
                                  size: 36,
                                ),
                              )
                            : const Icon(
                                Icons.person_rounded,
                                color: AppColors.lightGray,
                                size: 36,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLoggedIn
                              ? (ApiClient.instance.currentUser?.displayName ?? '구글 사용자')
                              : 'GUEST',
                          style: const TextStyle(
                            fontFamily: AppFonts.pretendard,
                            fontSize: 20,
                            fontWeight: FontWeight.w400,
                            color: AppColors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isLoggedIn
                              ? (ApiClient.instance.currentUser?.email ?? 'google@gmail.com')
                              : '로그인 / 회원가입하기 >',
                          style: const TextStyle(
                            fontFamily: AppFonts.pretendard,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: AppColors.slateGray,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Card 1: 이번 주 Ritual (Light Mint Wide Card with weekly_ritual_card.png graphic)
              Container(
                width: double.infinity,
                height: 125,
                decoration: BoxDecoration(
                  color: AppColors.lightMint,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    children: [
                      // Right Side Image / Graphic (weekly_ritual_card.png matching screenshot)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Image.asset(
                          'assets/images/weekly_ritual_card.png',
                          fit: BoxFit.contain,
                          alignment: Alignment.centerRight,
                          errorBuilder: (context, error, stackTrace) => Opacity(
                            opacity: 0.3,
                            child: Row(
                              children: [
                                Transform.rotate(
                                  angle: 0.3,
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Transform.rotate(
                                  angle: -0.4,
                                  child: Container(
                                    width: 60,
                                    height: 60,
                                    decoration: BoxDecoration(
                                      color: Colors.black26,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Content Overlay
                    Padding(
                      padding: const EdgeInsets.all(18.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '이번 주 Ritual',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg,
                                ),
                              ),
                              _NorthEastButton(),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                '5',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 38,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '회',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg.withAlpha(200),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

              // Card 2 & 3: Side-by-Side Stats Cards (총 시간 & 연속 기록)
              Row(
                children: [
                  // Left Card: 총 시간 (Soft Blue)
                  Expanded(
                    child: Container(
                      height: 110,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.softBlue,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '총 시간',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg,
                                ),
                              ),
                              _NorthEastButton(),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                '326',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '분',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg.withAlpha(200),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Right Card: 연속 기록 (Pastel Yellow)
                  Expanded(
                    child: Container(
                      height: 110,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.pastelYellow,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '연속 기록',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg,
                                ),
                              ),
                              _NorthEastButton(),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              const Text(
                                '7',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 32,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '일',
                                style: TextStyle(
                                  fontFamily: AppFonts.pretendard,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.darkBg.withAlpha(200),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Menu Item: Device Settings
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: AppColors.darkCharcoal,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      color: AppColors.lightGray,
                      size: 22,
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Device Settings',
                        style: TextStyle(
                          fontFamily: AppFonts.pretendard,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.lightGray,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NorthEastButton extends StatelessWidget {
  const _NorthEastButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        color: Color(0xFF222224),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.north_east_rounded,
        color: AppColors.white,
        size: 16,
      ),
    );
  }
}
