import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

// Key is injected at build/run time via --dart-define=GEMINI_API_KEY=...
// It is NEVER stored in any source file. See README for run instructions.
const String _kGeminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: '',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Call runApp() IMMEDIATELY — never block on network calls before this!
  runApp(const DevForceApp());
}

class DevForceApp extends StatefulWidget {
  const DevForceApp({super.key});

  @override
  State<DevForceApp> createState() => _DevForceAppState();
}

class _DevForceAppState extends State<DevForceApp> {
  Widget _homeScreen = const _LoadingScreen();

  @override
  void initState() {
    super.initState();
    _determineHomeScreen();
  }

  Future<void> _determineHomeScreen() async {
    Widget destination;

    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        destination = const EventLandingScreen();
      } else {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .get();

        destination = doc.exists ? const MainScreen() : const OnboardingScreen();
      }
    } catch (_) {
      destination = const EventLandingScreen();
    }

    if (mounted) {
      setState(() => _homeScreen = destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DevForce',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: _homeScreen,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        // This ensures 100% responsiveness on Desktop/Web by clamping max width
        return Container(
          color: Colors.grey.shade900, // Sleek dark backdrop for wide screens
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600), // Mobile/Tablet width
              child: ClipRect(child: child!),
            ),
          ),
        );
      },
    );
  }
}

/// Simple loading indicator shown while checking auth state.
class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'DevForce',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            SizedBox(height: 24),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Controllers to capture user input
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _gdgIdController = TextEditingController();
  final TextEditingController _roleController = TextEditingController();
  final TextEditingController _githubController = TextEditingController();
  final TextEditingController _linkedinController = TextEditingController();
  final TextEditingController _experienceController = TextEditingController();
  final TextEditingController _skillsController = TextEditingController();
  final TextEditingController _interestsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';

      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          if (data['gdgId'] != null) _gdgIdController.text = data['gdgId'];
          
          final id = data['developerIdentity'] as Map?;
          if (id != null) {
             _roleController.text = id['role'] ?? '';
             _githubController.text = id['githubId'] ?? '';
             _linkedinController.text = id['linkedInId'] ?? '';
          }
          
          final md = data['matchmakerData'] as Map?;
          if (md != null) {
             _experienceController.text = md['experienceLevel'] ?? '';
             _skillsController.text = (md['primarySkills'] as List?)?.join(', ') ?? '';
             _interestsController.text = (md['hackathonInterests'] as List?)?.join(', ') ?? '';
          }
        });
      }
    }
  }

  Future<void> _saveProfileToFirebase() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return; // Safety check

      final String? photoUrl = currentUser.photoURL;

      // Use the user's UID as the document ID — this is the key change!
      // Now the profile is tied to their Google account, not the device.
      // .set() is idempotent: safe to call even if the doc already exists.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
            'uid': currentUser.uid,
            'fullName': _nameController.text,
            'email': _emailController.text,
            'gdgId': _gdgIdController.text,
            if (photoUrl != null) 'photoUrl': photoUrl,
            'developerIdentity': {
              'role': _roleController.text,
              'githubId': _githubController.text,
              'linkedInId': _linkedinController.text,
            },
            'matchmakerData': {
              'experienceLevel': _experienceController.text,
              'primarySkills': _skillsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
              'hackathonInterests': _interestsController.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
            },
            'createdAt': DateTime.now(),
          }, SetOptions(merge: true));

      // Save location silently in background
      _saveLocationInBackground(currentUser.uid);

      if (mounted) {
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
      }
    }
  }

  void _saveLocationInBackground(String uid) async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'location': {'lat': pos.latitude, 'lng': pos.longitude}
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void _nextPage() {
    // ── Validation ────────────────────────────────────────────────────
    if (_currentPage == 0 && _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your full name to continue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (_currentPage == 2 && _skillsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least one primary skill.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // ── Navigation ────────────────────────────────────────────────────
    if (_currentPage < 2) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _saveProfileToFirebase();
    }
  }

  // RESTORED BUILD METHOD
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${_currentPage + 1} of 3'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_currentPage + 1) / 3),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (int page) {
                setState(() {
                  _currentPage = page;
                });
              },
              children: [
                _buildFormPage(
                  title: 'Who are you?',
                  fields: [
                    _buildTextField('Full Name', _nameController),
                    _buildTextField('Email ID', _emailController),
                    _buildTextField('GDG ID (Optional)', _gdgIdController),
                  ],
                ),
                _buildFormPage(
                  title: 'Your Developer Identity',
                  fields: [
                    _buildTextField('Designation / Role', _roleController),
                    _buildTextField('GitHub ID', _githubController),
                    _buildTextField('LinkedIn ID', _linkedinController),
                  ],
                ),
                _buildFormPage(
                  title: 'Matchmaker Data',
                  fields: [
                    _buildTextField(
                      'Experience Level (e.g., Beginner, Pro)',
                      _experienceController,
                    ),
                    _buildTextField(
                      'Primary Skills (comma separated)',
                      _skillsController,
                    ),
                    _buildTextField(
                      'Hackathon Interests (comma separated)',
                      _interestsController,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _nextPage,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentPage < 2 ? "Next" : "Save Profile",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormPage({required String title, required List<Widget> fields}) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          ...fields,
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
} // End of _OnboardingScreenState

// THE MAIN NAVIGATION HUB
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  int _unreadCount = 0;
  StreamSubscription? _unreadSub;

  List<Widget> get _screens => const [
    SwipeScreen(),
    DevMapScreen(),
    ConnectionsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _listenForUnread();
    _setupFCM();
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  void _setupFCM() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (mounted) {
        final title = message.notification?.title ?? 'New Message';
        final body = message.notification?.body ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.chat, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                      if (body.isNotEmpty) Text(body, style: const TextStyle(color: Colors.white70), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                setState(() => _selectedIndex = 2); // Go to Connections
              },
            ),
          ),
        );
      }
    });
  }

  void _listenForUnread() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _unreadSub = FirebaseFirestore.instance
        .collection('chats')
        .where('users', arrayContains: uid)
        .snapshots()
        .listen((snapshot) {
      int count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final lastSenderId = data['lastSenderId'] as String?;
        if (lastSenderId == null || lastSenderId == uid) continue;

        final lastUpdated = data['lastUpdated'] as Timestamp?;
        final lastReadMap = data['lastRead'] as Map<String, dynamic>?;
        final myLastRead = lastReadMap?[uid] as Timestamp?;

        if (lastUpdated != null) {
          if (myLastRead == null || lastUpdated.compareTo(myLastRead) > 0) {
            // Count unread messages for this chat
            final unread = data['unreadCount_$uid'] as int? ?? 1;
            count += unread;
          }
        }
      }
      if (mounted) setState(() => _unreadCount = count);
    });
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _selectedIndex.clamp(0, _screens.length - 1);
    return Scaffold(
      body: _screens[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.explore), label: 'Discover'),
          const BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _unreadCount > 0,
              label: Text('$_unreadCount', style: const TextStyle(fontSize: 10)),
              child: const Icon(Icons.forum),
            ),
            label: 'Connections',
          ),
        ],
      ),
    );
  }
}

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  List<Map<String, dynamic>> _potentialTeammates = [];
  Map<String, dynamic>? _myProfile;
  // uid → Gemini analysis (score, headline, reason, suggestedRole, projectIdea)
  final Map<String, Map<String, dynamic>> _geminiAnalyses = {};
  bool _isLoading = true;
  String? _errorMessage;

  final CardSwiperController controller = CardSwiperController();

  @override
  void initState() {
    super.initState();
    _fetchUsersFromFirebase();
  }

  Future<void> _fetchUsersFromFirebase() async {
    try {
      final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

      if (currentUid == null) throw Exception("User not logged in");

      // 1. Fetch the user's existing chats to know who to exclude from Discover
      final chatSnapshot = await FirebaseFirestore.instance
          .collection('chats')
          .where('users', arrayContains: currentUid)
          .get();

      final Set<String> matchedUids = {};
      for (final doc in chatSnapshot.docs) {
        final users = doc.data()['users'] as List<dynamic>? ?? [];
        for (final u in users) {
          if (u.toString() != currentUid) {
            matchedUids.add(u.toString());
          }
        }
      }

      // 2. Fetch all users
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .get();

      Map<String, dynamic>? myProfile;

      for (final doc in snapshot.docs) {
        if (doc.data()['uid'] == currentUid) {
          myProfile = doc.data();
          break;
        }
      }

      final rejections = myProfile?['rejections'] as List<dynamic>? ?? [];
      final rejectionSet = rejections.map((e) => e.toString()).toSet();

      final List<Map<String, dynamic>> freshProfiles = [];
      final List<Map<String, dynamic>> rejectedProfiles = [];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final uid = data['uid'] as String?;
        final privacy = data['privacy'] as Map<String, dynamic>? ?? {};
        final showInDiscover = privacy['showInDiscover'] ?? true;
        
        if (uid == currentUid) {
          myProfile = data; // Save own profile for match scoring
        } else if (uid != null && !matchedUids.contains(uid) && showInDiscover) {
          if (rejectionSet.contains(uid)) {
            rejectedProfiles.add(data);
          } else {
            freshProfiles.add(data);
          }
        }
      }

      final List<Map<String, dynamic>> others = [...freshProfiles, ...rejectedProfiles];

      // Smart sorting: proximity + skill complementarity
      final myLoc = myProfile?['location'] as Map<String, dynamic>?;
      final mySkillsSet = ((myProfile?['matchmakerData'] as Map?)?['primarySkills'] as List?)
          ?.map((e) => e.toString().trim().toLowerCase()).toSet() ?? <String>{};

      others.sort((a, b) {
        double scoreA = _proximitySkillScore(a, myLoc, mySkillsSet);
        double scoreB = _proximitySkillScore(b, myLoc, mySkillsSet);
        return scoreB.compareTo(scoreA); // Higher score = higher priority
      });

      if (mounted) {
        setState(() {
          _myProfile = myProfile;
          _potentialTeammates = others;
          _isLoading = false;
        });
        // Kick off Gemini analyses in the background — cards show immediately
        _computeGeminiAnalyses();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  double _proximitySkillScore(Map<String, dynamic> user, Map<String, dynamic>? myLoc, Set<String> mySkills) {
    double score = 0;

    // Proximity bonus (max 50 pts)
    final uLoc = user['location'] as Map<String, dynamic>?;
    if (myLoc != null && uLoc != null) {
      final dist = Geolocator.distanceBetween(
        (myLoc['lat'] as num).toDouble(),
        (myLoc['lng'] as num).toDouble(),
        (uLoc['lat'] as num).toDouble(),
        (uLoc['lng'] as num).toDouble(),
      );
      final km = dist / 1000;
      if (km < 5) score += 50;
      else if (km < 20) score += 40;
      else if (km < 50) score += 30;
      else if (km < 100) score += 15;
      else score += 5;
    }

    // Complementary skill bonus (max 50 pts)
    final uSkills = ((user['matchmakerData'] as Map?)?['primarySkills'] as List?)
        ?.map((e) => e.toString().trim().toLowerCase()).toSet() ?? <String>{};
    final complementary = uSkills.difference(mySkills);
    final shared = uSkills.intersection(mySkills);
    score += (complementary.length * 10).clamp(0, 30).toDouble();
    score += (shared.length * 5).clamp(0, 20).toDouble();

    return score;
  }

  /// Runs Gemini analysis for each teammate sequentially (respects rate limits).
  Future<void> _computeGeminiAnalyses() async {
    if (_myProfile == null || _kGeminiApiKey.isEmpty) {
      return;
    }
    final model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: _kGeminiApiKey,
      generationConfig: GenerationConfig(responseMimeType: 'application/json'),
    );
    for (final teammate in _potentialTeammates) {
      final uid = teammate['uid'] as String? ?? '';
      if (uid.isEmpty || _geminiAnalyses.containsKey(uid)) continue;
      try {
        final result = await _getGeminiAnalysis(model, teammate);
        if (mounted) setState(() => _geminiAnalyses[uid] = result);
      } catch (_) {
        /* silently fall back to local score */
      }
    }
  }

  Future<Map<String, dynamic>> _getGeminiAnalysis(
    GenerativeModel model,
    Map<String, dynamic> other,
  ) async {
    final myMD = _myProfile!['matchmakerData'] as Map? ?? {};
    final myID = _myProfile!['developerIdentity'] as Map? ?? {};
    final thMD = other['matchmakerData'] as Map? ?? {};
    final thID = other['developerIdentity'] as Map? ?? {};

    final prompt =
        '''
You are an expert GDG hackathon team-formation AI.
Analyze compatibility between two developers. Return ONLY valid JSON, no markdown.

Developer A:
  Name: ${_myProfile!['fullName']}, Role: ${myID['role']}
  Skills: ${(myMD['primarySkills'] as List?)?.join(', ')}
  Experience: ${myMD['experienceLevel']}
  Interests: ${(myMD['hackathonInterests'] as List?)?.join(', ')}

Developer B:
  Name: ${other['fullName']}, Role: ${thID['role']}
  Skills: ${(thMD['primarySkills'] as List?)?.join(', ')}
  Experience: ${thMD['experienceLevel']}
  Interests: ${(thMD['hackathonInterests'] as List?)?.join(', ')}

Return JSON:
{
  "score": <40-99>,
  "headline": "<≤8 word reason they match>",
  "reason": "<2 sentences: technical + interest fit>",
  "suggestedRole": "<role Developer B would play>",
  "projectIdea": "<one creative Google-tech GDG hackathon project idea>"
}
''';
    final resp = await model.generateContent([Content.text(prompt)]);
    final text = (resp.text ?? '{}')
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// Computes a real match score and reason between the current user and another.
  /// Logic:
  ///   - +15 per shared hackathon interest   (max 45 pts)
  ///   - +10 per complementary skill          (unique to either side)
  ///   - +10 per shared skill                 (collaboration boost)
  ///   - Base score of 40
  ///   - Capped at 99%
  Map<String, dynamic> _calculateMatch(Map<String, dynamic> other) {
    if (_myProfile == null) {
      return {'score': 70, 'reason': 'Great potential match!'};
    }

    final myMatchData = _myProfile!['matchmakerData'] as Map? ?? {};
    final theirMatchData = other['matchmakerData'] as Map? ?? {};

    final mySkills =
        (myMatchData['primarySkills'] as List?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .toSet() ??
        {};
    final theirSkills =
        (theirMatchData['primarySkills'] as List?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .toSet() ??
        {};
    final myInterests =
        (myMatchData['hackathonInterests'] as List?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .toSet() ??
        {};
    final theirInterests =
        (theirMatchData['hackathonInterests'] as List?)
            ?.map((e) => e.toString().trim().toLowerCase())
            .toSet() ??
        {};

    final sharedInterests = myInterests.intersection(theirInterests);
    final sharedSkills = mySkills.intersection(theirSkills);
    final complementarySkills = mySkills
        .union(theirSkills)
        .difference(sharedSkills);

    int score = 40;
    score += (sharedInterests.length * 15).clamp(0, 45);
    score += (sharedSkills.length * 10).clamp(0, 20);
    score += (complementarySkills.length * 5).clamp(0, 25);
    score = score.clamp(40, 99);

    // Build a human-readable reason
    final List<String> reasons = [];
    if (sharedInterests.isNotEmpty) {
      final listed = sharedInterests
          .take(2)
          .map((s) => _capitalize(s))
          .join(' & ');
      reasons.add('Both interested in $listed');
    }
    if (complementarySkills.isNotEmpty) {
      final listed = complementarySkills
          .take(2)
          .map((s) => _capitalize(s))
          .join(' + ');
      reasons.add('Complementary skills: $listed');
    }
    if (sharedSkills.isNotEmpty && reasons.isEmpty) {
      final listed = sharedSkills
          .take(2)
          .map((s) => _capitalize(s))
          .join(' & ');
      reasons.add('Shared expertise in $listed');
    }
    final reason = reasons.isNotEmpty
        ? '${reasons.join('. ')}.'
        : 'Strong overall profile alignment.';

    return {'score': score, 'reason': reason};
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 28),
            const SizedBox(width: 8),
            const Text('DevForce', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: AnimatedMeshBackground(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                    // ── ERROR STATE ──────────────────────────────────────────
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.cloud_off,
                                size: 64,
                                color: Colors.redAccent,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Could not load profiles',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    _isLoading = true;
                                    _errorMessage = null;
                                  });
                                  _fetchUsersFromFirebase();
                                },
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _potentialTeammates.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              "No more matches in your area! 😭",
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isLoading = true;
                                });
                                _fetchUsersFromFirebase();
                              },
                              icon: const Icon(Icons.refresh),
                              label: const Text('Refresh'),
                            ),
                          ],
                        ),
                      )
                    // ── SWIPER ───────────────────────────────────────────────
                    : CardSwiper(
                        controller: controller,
                        cardsCount: _potentialTeammates.length,
                        numberOfCardsDisplayed: _potentialTeammates.length == 1 ? 1 : 2,
                        onSwipe: _onSwipe,
                        onEnd: () {
                          setState(() {
                            _potentialTeammates.clear();
                          });
                        },
                        padding: const EdgeInsets.all(24.0),
                        cardBuilder:
                            (
                              context,
                              index,
                              horizontalOffsetPercentage,
                              verticalOffsetPercentage,
                            ) {
                              return _buildTeammateCard(
                                _potentialTeammates[index],
                              );
                            },
                      ),
              ),

              // The Action Buttons (Now wired to the swiper controller!)
              Padding(
                padding: const EdgeInsets.only(bottom: 40.0, top: 20.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                  FloatingActionButton(
                    heroTag: 'no',
                    onPressed: () => controller.swipe(CardSwiperDirection.left),
                    backgroundColor: Colors.redAccent,
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  FloatingActionButton(
                    heroTag: 'undo',
                    onPressed: () => controller.undo(),
                    backgroundColor: Colors.amber.shade400,
                    child: const Icon(
                      Icons.undo,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  FloatingActionButton(
                    heroTag: 'yes',
                    onPressed: () =>
                        controller.swipe(CardSwiperDirection.right),
                    backgroundColor: Colors.greenAccent,
                    child: const Icon(
                      Icons.favorite,
                      color: Colors.white,
                      size: 30,
                    ),
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

  // Handle what happens when a card is swiped
  bool _onSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) {
    final swipedUser = _potentialTeammates[previousIndex];
    final uid = swipedUser['uid'] as String? ?? '';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (direction == CardSwiperDirection.right) {
      // ── CREATE CHAT DOCUMENT on right swipe (Match) ──────────────────
      if (currentUid != null && uid.isNotEmpty) {
        final chatId = [currentUid, uid]..sort();
        FirebaseFirestore.instance.collection('chats').doc(chatId.join('_')).set({
          'users': [currentUid, uid],
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => MatchDialog(
          matchedUser: swipedUser,
          myProfile: _myProfile,
          geminiAnalysis: _geminiAnalyses[uid],
        ),
      );
    } else if (direction == CardSwiperDirection.left) {
      // ── RECORD REJECTION on left swipe ───────────────────────────────
      // This ensures rejected profiles stay at the bottom of the stack
      // on subsequent fetches (via the rejectionSet logic in _fetchUsersFromFirebase)
      if (currentUid != null && uid.isNotEmpty) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(currentUid)
            .set({
          'rejections': FieldValue.arrayUnion([uid]),
        }, SetOptions(merge: true));
      }
    }
    return true;
  }

  // Card UI — Gemini-powered when analysis is ready, local score as instant fallback
  Widget _buildTeammateCard(Map<String, dynamic> user) {
    final identity = user['developerIdentity'] ?? {};
    final matchData = user['matchmakerData'] ?? {};
    final primarySkills = matchData['primarySkills'] != null
        ? List<String>.from(matchData['primarySkills'])
        : ['Unknown'];
    final String? photoUrl = user['photoUrl'] as String?;
    final String experienceLevel = matchData['experienceLevel'] ?? '';
    final String uid = user['uid'] as String? ?? '';
    final Map<String, dynamic>? gemini = _geminiAnalyses[uid];

    // Build initials as fallback
    final String name = user['fullName'] ?? 'U';
    final List<String> parts = name
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    final String initials = parts.length > 1
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : parts.isNotEmpty
        ? parts[0][0].toUpperCase()
        : 'U';

    // Use Gemini result when available, local algorithm as instant fallback
    final localMatch = _calculateMatch(user);
    final int matchScore =
        (gemini?['score'] as num?)?.toInt() ?? localMatch['score'] as int;
    final String matchReason =
        (gemini?['reason'] as String?) ?? localMatch['reason'] as String;
    final String? projectIdea = gemini?['projectIdea'] as String?;
    final String? suggestedRole = gemini?['suggestedRole'] as String?;
    final bool geminiReady = gemini != null;

    final Color scoreColor = matchScore >= 80
        ? Colors.green
        : matchScore >= 60
        ? Colors.amber.shade700
        : Colors.redAccent;
    final Color scoreBg = matchScore >= 80
        ? Colors.greenAccent.withValues(alpha: 0.15)
        : matchScore >= 60
        ? Colors.amber.withValues(alpha: 0.15)
        : Colors.red.withValues(alpha: 0.1);

    return GlassCard(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(24.0),
        child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── Match score badge ─────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scoreBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$matchScore% Match',
                  style: TextStyle(
                    color: scoreColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              if (geminiReady) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 12,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Gemini',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.blue.shade300,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // ── Profile picture ───────────────────────────────────────────
          CircleAvatar(
            radius: 48,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            child: photoUrl == null
                ? Text(
                    initials,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),

          // ── Name ──────────────────────────────────────────────────────
          Text(
            name,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),

          // ── Role + Experience badge ───────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                identity['role'] ?? 'Developer',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              if (experienceLevel.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    experienceLevel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // ── Skills chips ──────────────────────────────────────────────
          Wrap(
            spacing: 6.0,
            runSpacing: 6.0,
            alignment: WrapAlignment.center,
            children: primarySkills.take(4).map((skill) {
              return Chip(
                label: Text(skill, style: const TextStyle(fontSize: 12)),
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // ── Match reason ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(
              matchReason,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          // ── Gemini project idea ───────────────────────────────────────
          if (projectIdea != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.purple.shade50],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      projectIdea,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (suggestedRole != null) ...[
            const SizedBox(height: 6),
            Text(
              '🎯 Team role: $suggestedRole',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
      ),
    );
  }
}

// THE "IT'S A MATCH" POPUP — powered by Gemini
class MatchDialog extends StatefulWidget {
  final Map<String, dynamic> matchedUser;
  final Map<String, dynamic>? myProfile;
  final Map<String, dynamic>? geminiAnalysis;

  const MatchDialog({
    super.key,
    required this.matchedUser,
    this.myProfile,
    this.geminiAnalysis,
  });

  @override
  State<MatchDialog> createState() => _MatchDialogState();
}

class _MatchDialogState extends State<MatchDialog> {
  final TextEditingController _messageController = TextEditingController();
  bool _isGenerating = false;

  Future<void> _generateGeminiIcebreaker() async {
    setState(() => _isGenerating = true);

    try {
      if (_kGeminiApiKey.isEmpty) {
        throw Exception('No API key');
      }
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _kGeminiApiKey,
      );

      final myID = widget.myProfile?['developerIdentity'] as Map? ?? {};
      final myMD = widget.myProfile?['matchmakerData'] as Map? ?? {};
      final thID = widget.matchedUser['developerIdentity'] as Map? ?? {};
      final thMD = widget.matchedUser['matchmakerData'] as Map? ?? {};
      final projectIdea =
          widget.geminiAnalysis?['projectIdea'] as String? ?? '';

      final prompt =
          '''
Write a short, professional outreach message (3 sentences max) from ${widget.myProfile?['fullName'] ?? 'me'} 
to ${widget.matchedUser['fullName']}, inviting them to team up for a GDG Hackathon.

Context:
- I am a ${myID['role']} skilled in ${(myMD['primarySkills'] as List?)?.join(', ')}.
- They are a ${thID['role']} skilled in ${(thMD['primarySkills'] as List?)?.join(', ')}.
${projectIdea.isNotEmpty ? '- Suggested project idea: $projectIdea' : ''}

Tone: professional but friendly. Be specific about their skills. No emojis.
''';
      final resp = await model.generateContent([Content.text(prompt)]);
      if (mounted) {
        setState(() => _messageController.text = resp.text?.trim() ?? '');
      }
    } catch (_) {
      // Graceful fallback
      final name = widget.matchedUser['fullName'] ?? 'Teammate';
      final role =
          (widget.matchedUser['developerIdentity'] as Map?)?['role'] ??
          'Developer';
      if (mounted) {
        setState(
          () => _messageController.text =
              'Hi $name! I came across your profile on DevForce and think we would make a great team. '
              'Your experience as a $role perfectly complements my skillset. '
              'Would you be open to collaborating at this weekend\'s GDG Hackathon?',
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.matchedUser['email'] ?? 'No email provided';
    final identity = widget.matchedUser['developerIdentity'] as Map? ?? {};
    final github = identity['githubId'] ?? 'No GitHub';
    final projectIdea = widget.geminiAnalysis?['projectIdea'] as String?;
    final firstName =
        widget.matchedUser['fullName']?.split(' ')[0] ?? 'this developer';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Match Confirmed',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.auto_awesome, color: Colors.blue.shade400, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You and $firstName are a recommended fit.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 16),

            // Project Idea from Gemini
            if (projectIdea != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade50, Colors.purple.shade50],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lightbulb,
                          size: 14,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Gemini Project Idea',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(projectIdea, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Contact info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Email: $email',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'GitHub: github.com/$github',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _messageController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: "Write a message to introduce yourself...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateGeminiIcebreaker,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade50,
                  foregroundColor: Colors.blue.shade800,
                  elevation: 0,
                  side: BorderSide(color: Colors.blue.shade200),
                ),
                icon: _isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.memory, color: Colors.blue),
                label: Text(
                  _isGenerating ? "Generating..." : "Draft Intro with AI",
                ),
              ),
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Keep Swiping"),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final text = _messageController.text.trim();
                      if (text.isNotEmpty) {
                        final currentUid = FirebaseAuth.instance.currentUser?.uid;
                        final receiverUid = widget.matchedUser['uid'];
                        if (currentUid != null && receiverUid != null) {
                          final chatId = [currentUid, receiverUid]..sort();
                          
                          // Write message to subcollection
                          FirebaseFirestore.instance
                              .collection('chats')
                              .doc(chatId.join('_'))
                              .collection('messages')
                              .add({
                            'senderId': currentUid,
                            'receiverId': receiverUid,
                            'text': text,
                            'timestamp': FieldValue.serverTimestamp(),
                          });
                          
                          // Update parent chat document
                          FirebaseFirestore.instance
                              .collection('chats')
                              .doc(chatId.join('_'))
                              .set({
                            'users': [currentUid, receiverUid],
                            'lastMessage': text,
                            'lastUpdated': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        }
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message sent successfully.'),
                        ),
                      );
                    },
                    child: const Text("Send"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class EventLandingScreen extends StatelessWidget {
  const EventLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 28),
            const SizedBox(width: 8),
            const Text(
              'DevForce',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. CALL THE HERO SECTION WIDGET HERE
              const HeroSection(),

              const SizedBox(height: 32),

              // 2. UPCOMING EVENTS HEADER
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  "Active GDG Hackathons",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),

              // 3. DYNAMIC EVENTS LIST FROM FIREBASE
              FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance.collection('events').get(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(child: Text("Error loading events."));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Text("No upcoming events found."),
                    );
                  }

                  final events = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: events.length,
                    itemBuilder: (context, index) {
                      final eventData =
                          events[index].data() as Map<String, dynamic>;
                      return _buildEventCard(context, eventData);
                    },
                  );
                },
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventCard(BuildContext context, Map<String, dynamic> event) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              event['title'] ?? 'Unnamed Event',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.calendar_today, event['date'] ?? 'Dates TBD'),
            const SizedBox(height: 12),
            _buildInfoRow(
              Icons.location_on,
              event['location'] ?? 'Location TBD',
            ),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.group, event['status'] ?? 'Registration Open'),
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    // 1. Create the instance
                    final GoogleSignIn googleSignIn = GoogleSignIn();

                    // 2. Trigger the login popup
                    final GoogleSignInAccount? googleUser = await googleSignIn
                        .signIn();

                    if (googleUser != null) {
                      // 3. Get the auth tokens
                      final GoogleSignInAuthentication googleAuth =
                          await googleUser.authentication;

                      // 4. Sign into Firebase
                      final AuthCredential credential =
                          GoogleAuthProvider.credential(
                            accessToken: googleAuth.accessToken,
                            idToken: googleAuth.idToken,
                          );

                      final userCredential = await FirebaseAuth.instance
                          .signInWithCredential(credential);
                      final uid = userCredential.user?.uid;

                      if (uid != null && context.mounted) {
                        // 5. Check if this Google account already has a profile
                        final doc = await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .get();

                        if (!context.mounted) return;

                        if (doc.exists) {
                          // Returning user — skip onboarding, go straight to app
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const MainScreen(),
                            ),
                          );
                        } else {
                          // New user — collect their profile details
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OnboardingScreen(),
                            ),
                          );
                        }
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Login failed: $e')),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Join Event",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// STANDALONE HERO SECTION WIDGET
class HeroSection extends StatelessWidget {
  const HeroSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Column(
        children: [
          // Logo/Icon
          Container(
            height: 80,
            width: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  spreadRadius: 2,
                )
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset('assets/logo.png', fit: BoxFit.cover),
          ),
          const SizedBox(height: 24),

          // Title
          const Text(
            "Build Your Dream Team",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Professional Description
          const Text(
            "DevForce is the official matching engine for GDG Hackathons. Stop scrolling through chat groups and let our system find developers with the exact skills your project needs.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black87, height: 1.5),
          ),
          const SizedBox(height: 32),

          // 3-Step Visual
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFeatureItem(context, Icons.event, "Join\nEvent"),
              _buildFeatureItem(context, Icons.swipe, "Swipe\nMatches"),
              _buildFeatureItem(context, Icons.chat, "Connect\n& Build"),
            ],
          ),
        ],
      ),
    );
  }

  // Helper widget for the icons
  Widget _buildFeatureItem(BuildContext context, IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}

// THE DEVELOPER MAP SCREEN (Free OpenStreetMap)
class DevMapScreen extends StatefulWidget {
  const DevMapScreen({super.key});

  @override
  State<DevMapScreen> createState() => _DevMapScreenState();
}

class _DevMapScreenState extends State<DevMapScreen> {
  final MapController _mapController = MapController();
  LatLng _myPosition = const LatLng(20.5937, 78.9629);
  List<Marker> _markers = [];
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    // Load location in background AFTER first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocation());
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Turn on Location/GPS in phone settings')),
          );
        }
        setState(() => _locating = false);
        return;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Location permission required. Please allow in settings.')),
          );
        }
        setState(() => _locating = false);
        return;
      }

      // Try getCurrentPosition with timeout, fallback to lastKnown
      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
        ).timeout(const Duration(seconds: 10));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }

      // Validate the position is real
      if (pos == null || pos.latitude.isNaN || pos.longitude.isNaN ||
          pos.latitude == 0.0 && pos.longitude == 0.0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('⚠️ Could not get GPS. Try again outside.')),
          );
        }
        setState(() => _locating = false);
        return;
      }

      _myPosition = LatLng(pos.latitude, pos.longitude);

      // Save to Firestore
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        FirebaseFirestore.instance.collection('users').doc(uid).set({
          'location': {'lat': pos.latitude, 'lng': pos.longitude}
        }, SetOptions(merge: true));
      }

      // Fetch devs
      await _loadDevMarkers();

      // Move camera to my location
      if (mounted) {
        if (_myPosition.latitude.isFinite && _myPosition.longitude.isFinite) {
          try { _mapController.move(_myPosition, 14); } catch (_) {}
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Location saved!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint("MAP ERROR: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Location error: $e')),
        );
      }
    }
    if (mounted) setState(() => _locating = false);
  }

  /// Safely parse a Firestore value to double. Returns null if invalid.
  double? _safeDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final d = value.toDouble();
      return d.isFinite ? d : null;
    }
    if (value is String) {
      final d = double.tryParse(value);
      return (d != null && d.isFinite) ? d : null;
    }
    return null;
  }

  Future<void> _loadDevMarkers() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final markers = <Marker>[];

    // My blue marker - only add if position is valid
    if (_myPosition.latitude.isFinite && _myPosition.longitude.isFinite) {
      markers.add(Marker(
        point: _myPosition,
        width: 60,
        height: 60,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_pin_circle, color: Colors.blue, size: 40),
            Text('You', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue)),
          ],
        ),
      ));
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final uid = data['uid'] as String?;
      if (uid == null || uid == currentUid) continue;

      final loc = data['location'];
      if (loc == null || loc is! Map<String, dynamic>) continue;

      final lat = _safeDouble(loc['lat']);
      final lng = _safeDouble(loc['lng']);
      if (lat == null || lng == null) continue;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;

      final name = data['fullName'] ?? 'Developer';
      final role = (data['developerIdentity'] as Map?)?['role'] ?? '';
      final skills = ((data['matchmakerData'] as Map?)?['primarySkills'] as List?)
          ?.take(3).join(', ') ?? '';

      double distKm = 0;
      if (_myPosition.latitude.isFinite && _myPosition.longitude.isFinite) {
        final dist = Geolocator.distanceBetween(
          _myPosition.latitude, _myPosition.longitude, lat, lng,
        );
        distKm = dist / 1000;
      }
      final km = distKm.toStringAsFixed(1);

      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 120,
        height: 70,
        child: GestureDetector(
          onTap: () {
            showModalBottomSheet(
              context: context,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              builder: (_) => Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    if (role.isNotEmpty) Text(role, style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('📍 ${km}km away', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                    ),
                    if (skills.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('Skills: $skills', style: const TextStyle(fontSize: 14)),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, color: Colors.red, size: 36),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
                ),
                child: Text(
                  name.split(' ').first,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ));
    }

    if (mounted) {
      setState(() => _markers = markers);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 28),
            const SizedBox(width: 8),
            const Text('Nearby Devs', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _myPosition,
          initialZoom: 5,
          minZoom: 2,
          maxZoom: 18,
          // Constrain camera to valid world bounds to prevent NaN
          cameraConstraint: CameraConstraint.contain(
            bounds: LatLngBounds(
              const LatLng(-85, -180),
              const LatLng(85, 180),
            ),
          ),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.alphaarchives.devforce',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _locating ? null : _loadLocation,
        icon: _locating
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.my_location),
        label: Text(_locating ? 'Locating...' : 'Save My Location'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
// THE CONNECTIONS / MESSAGES TAB
class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Your Connections',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [IconButton(icon: const Icon(Icons.search), onPressed: () {})],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .where('users', arrayContains: FirebaseAuth.instance.currentUser?.uid)
            .orderBy('lastUpdated', descending: true)
            .snapshots(),
        builder: (context, chatSnapshot) {
          if (chatSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (chatSnapshot.hasError) {
            return Center(child: Text("Error: ${chatSnapshot.error}"));
          }

          final chats = chatSnapshot.data?.docs ?? [];

          if (chats.isEmpty) {
            return const Center(
              child: Text("No connections yet. Start swiping!"),
            );
          }

          final String? currentUid = FirebaseAuth.instance.currentUser?.uid;

          return ListView.builder(
            itemCount: chats.length,
            itemBuilder: (context, index) {
              final chatData = chats[index].data() as Map<String, dynamic>;
              final users = List<String>.from(chatData['users'] ?? []);
              final otherUid = users.firstWhere(
                (id) => id != currentUid,
                orElse: () => '',
              );

              if (otherUid.isEmpty) return const SizedBox.shrink();

              // Fetch the matched user's profile data
              return FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUid)
                    .get(),
                builder: (context, userSnapshot) {
                  if (!userSnapshot.hasData) {
                    return const ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      leading: CircleAvatar(
                        radius: 28,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      title: Text('Loading...'),
                    );
                  }

                  final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                  final name = userData['fullName'] ?? 'Unknown Developer';
                  final identity = userData['developerIdentity'] ?? {};
                  final role = identity['role'] ?? 'Developer';
                  final String? photoUrl = userData['photoUrl'] as String?;

                  // Initials fallback
                  String initials = "U";
                  final String cleanName = name.trim();
                  if (cleanName.isNotEmpty) {
                    final List<String> names = cleanName
                        .split(' ')
                        .where((s) => s.isNotEmpty)
                        .toList();
                    if (names.length > 1) {
                      initials = "${names[0][0]}${names[1][0]}".toUpperCase();
                    } else if (names.isNotEmpty) {
                      initials = names[0][0].toUpperCase();
                    }
                  }

                  final lastMessage = chatData['lastMessage'] ?? role;
                  final lastSenderId = chatData['lastSenderId'] as String?;
                  final lastUpdated = chatData['lastUpdated'] as Timestamp?;
                  final unreadCount = chatData['unreadCount_$currentUid'] as int? ?? 0;
                  final bool hasUnread = unreadCount > 0 && lastSenderId != currentUid;

                  // Time ago
                  String timeAgo = '';
                  if (lastUpdated != null) {
                    final diff = DateTime.now().difference(lastUpdated.toDate());
                    if (diff.inMinutes < 1) {
                      timeAgo = 'now';
                    } else if (diff.inMinutes < 60) {
                      timeAgo = '${diff.inMinutes}m';
                    } else if (diff.inHours < 24) {
                      timeAgo = '${diff.inHours}h';
                    } else {
                      timeAgo = '${diff.inDays}d';
                    }
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    leading: Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                          child: photoUrl == null
                              ? Text(
                                  initials,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                )
                              : null,
                        ),
                        if (hasUnread)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        fontWeight: hasUnread ? FontWeight.w900 : FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: hasUnread ? Colors.black87 : Colors.grey.shade600,
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (timeAgo.isNotEmpty)
                          Text(
                            timeAgo,
                            style: TextStyle(
                              fontSize: 12,
                              color: hasUnread ? Theme.of(context).colorScheme.primary : Colors.grey,
                              fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        const SizedBox(height: 4),
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 18,
                          color: hasUnread ? Theme.of(context).colorScheme.primary : Colors.grey,
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ChatScreen(receiverData: userData),
                        ),
                      );
                    },
                    onLongPress: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              DeveloperProfileScreen(userData: userData),
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// THE DETAILED DEVELOPER PROFILE SCREEN
class DeveloperProfileScreen extends StatelessWidget {
  final Map<String, dynamic> userData;

  const DeveloperProfileScreen({super.key, required this.userData});

  @override
  Widget build(BuildContext context) {
    final name = userData['fullName'] ?? 'Unknown Developer';
    final identity = userData['developerIdentity'] ?? {};
    final role = identity['role'] ?? 'Developer';
    final github = identity['githubId'] ?? 'Not provided';
    final linkedin = identity['linkedInId'] ?? 'Not provided';
    final String? photoUrl = userData['photoUrl'] as String?;

    final matchData = userData['matchmakerData'] ?? {};
    final experience = matchData['experienceLevel'] ?? 'Not specified';
    final primarySkills = matchData['primarySkills'] != null
        ? List<String>.from(matchData['primarySkills'])
        : ['Unknown'];
    final interests = matchData['hackathonInterests'] != null
        ? List<String>.from(matchData['hackathonInterests'])
        : ['General'];

    // Generate Initials (fallback when no photo)
    String initials = "U";
    String cleanName = name.trim();
    if (cleanName.isNotEmpty) {
      List<String> names = cleanName
          .split(' ')
          .where((s) => s.isNotEmpty)
          .toList();
      initials = names.length > 1
          ? "${names[0][0]}${names[1][0]}".toUpperCase()
          : names[0][0].toUpperCase();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Section
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.primaryContainer,
                    // Show Google profile picture if available
                    backgroundImage: photoUrl != null
                        ? NetworkImage(photoUrl)
                        : null,
                    child: photoUrl == null
                        ? Text(
                            initials,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    role,
                    style: const TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // About Section
            const Text(
              "Experience Level",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(experience, style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 24),

            const Text(
              "Primary Skills",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: primarySkills.map((skill) {
                return Chip(
                  label: Text(skill),
                  backgroundColor: Colors.grey.shade100,
                  side: BorderSide.none,
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            const Text(
              "Hackathon Interests",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: interests.map((interest) {
                return Chip(
                  label: Text(interest),
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  side: BorderSide.none,
                );
              }).toList(),
            ),
            const SizedBox(height: 32),

            // Links Section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  _buildLinkRow(Icons.code, "GitHub", github),
                  const Divider(height: 24),
                  _buildLinkRow(Icons.work, "LinkedIn", linkedin),
                ],
              ),
            ),
            const SizedBox(height: 40),

            // Action Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(receiverData: userData),
                    ),
                  );
                },
                icon: const Icon(Icons.chat),
                label: const Text(
                  "Send Message",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkRow(IconData icon, String platform, String handle) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600),
        const SizedBox(width: 16),
        Text(platform, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        Text(handle, style: const TextStyle(color: Colors.blue)),
      ],
    );
  }
}

// THE USER SETTINGS SCREEN
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Grab the currently logged-in Google user
    final User? currentUser = FirebaseAuth.instance.currentUser;

    // 2. Extract their specific Google data
    final String? photoUrl = currentUser?.photoURL;
    final String displayName =
        currentUser?.displayName ?? "My DevForce Account";
    final String email = currentUser?.email ?? "Not signed in";

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('My Profile Settings'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const SizedBox(height: 16),
          // Dynamic Profile Avatar
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              // If they have a Google photo, show it. Otherwise, show the icon.
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? Icon(
                      Icons.person,
                      size: 50,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          // Dynamic Name and Email
          Center(
            child: Text(
              displayName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              email,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
          ),
          const SizedBox(height: 32),

          _buildSettingsTile(context, Icons.edit, "Edit Profile Data", () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
          }),
          _buildSettingsTile(context, Icons.build, "Manage Skills & Interests", () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const OnboardingScreen()));
          }),
          _buildSettingsTile(context, Icons.notifications, "Notifications", () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          }),
          _buildSettingsTile(context, Icons.security, "Privacy & Security", () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacySecurityScreen()));
          }),

          const SizedBox(height: 32),

          // Fully Functional Logout Button
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Log Out & Reset",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onTap: () async {
              // Sign out of both Google and Firebase
              await GoogleSignIn().signOut();
              await FirebaseAuth.instance.signOut();

              // Return to Landing Page
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EventLandingScreen(),
                  ),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile(BuildContext context, IconData icon, String title, [VoidCallback? onTap]) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap ?? () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Feature available in production version.'),
            ),
          );
        },
      ),
    );
  }
}

// --- CHAT SCREEN ---
class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> receiverData;

  const ChatScreen({super.key, required this.receiverData});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final String _currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final String _chatId;

  @override
  void initState() {
    super.initState();
    final receiverUid = widget.receiverData['uid'] ?? '';
    final uids = [_currentUid, receiverUid]..sort();
    _chatId = uids.join('_');
    // Mark as read when opening the chat
    _markAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    // Mark as read when leaving the chat too
    _markAsRead();
    super.dispose();
  }

  void _markAsRead() {
    if (_currentUid.isEmpty) return;
    FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
      'lastRead': {_currentUid: FieldValue.serverTimestamp()},
      'unreadCount_$_currentUid': 0,
    }, SetOptions(merge: true));
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _currentUid.isEmpty) return;

    _messageController.clear();
    final receiverUid = widget.receiverData['uid'] ?? '';
    final senderName = FirebaseAuth.instance.currentUser?.displayName ?? 'Someone';

    final message = {
      'senderId': _currentUid,
      'receiverId': receiverUid,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .add(message);
        
    // Update the parent chat document with the last message,
    // sender info, and increment unread count for receiver
    await FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
      'users': [_currentUid, receiverUid],
      'lastMessage': text,
      'lastSenderId': _currentUid,
      'lastSenderName': senderName,
      'lastUpdated': FieldValue.serverTimestamp(),
      'unreadCount_$receiverUid': FieldValue.increment(1),
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final receiverName = widget.receiverData['fullName'] ?? 'Developer';
    final String? photoUrl = widget.receiverData['photoUrl'];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
              child: photoUrl == null
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                receiverName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final messages = snapshot.data?.docs ?? [];
                if (messages.isEmpty) {
                  return Center(
                    child: Text('Start the conversation with $receiverName!'),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == _currentUid;
                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(20),
                            topRight: const Radius.circular(20),
                            bottomLeft:
                                isMe ? const Radius.circular(20) : Radius.zero,
                            bottomRight:
                                isMe ? Radius.zero : const Radius.circular(20),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          data['text'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.shade200,
                  offset: const Offset(0, -2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white),
                      onPressed: _sendMessage,
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

// ── CREATIVE WIDGETS (ANIMATED MESH & GLASSMORPHISM) ──

class AnimatedMeshBackground extends StatefulWidget {
  final Widget child;
  const AnimatedMeshBackground({super.key, required this.child});

  @override
  State<AnimatedMeshBackground> createState() => _AnimatedMeshBackgroundState();
}

class _AnimatedMeshBackgroundState extends State<AnimatedMeshBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Alignment> _topAlignmentAnimation;
  late Animation<Alignment> _bottomAlignmentAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _topAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.topLeft, end: Alignment.topRight), weight: 1),
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.topRight, end: Alignment.bottomRight), weight: 1),
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.bottomRight, end: Alignment.bottomLeft), weight: 1),
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.bottomLeft, end: Alignment.topLeft), weight: 1),
    ]).animate(_controller);

    _bottomAlignmentAnimation = TweenSequence<Alignment>([
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.bottomRight, end: Alignment.bottomLeft), weight: 1),
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.bottomLeft, end: Alignment.topLeft), weight: 1),
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.topLeft, end: Alignment.topRight), weight: 1),
      TweenSequenceItem(tween: Tween<Alignment>(begin: Alignment.topRight, end: Alignment.bottomRight), weight: 1),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.purpleAccent.withValues(alpha: 0.15),
                Colors.blueAccent.withValues(alpha: 0.15),
                Colors.pinkAccent.withValues(alpha: 0.10),
                Colors.white,
              ],
              begin: _topAlignmentAnimation.value,
              end: _bottomAlignmentAnimation.value,
              stops: const [0.0, 0.4, 0.7, 1.0],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _pushEnabled = true;
  bool _emailEnabled = false;
  bool _matchAlerts = true;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    final status = await Permission.notification.status;
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
      if (status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Notifications enabled!'), backgroundColor: Colors.green),
        );
        // Get FCM token
        final token = await FirebaseMessaging.instance.getToken();
        debugPrint("FCM Token: $token");
        // Save token to Firestore
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && token != null) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'fcmToken': token,
          }, SetOptions(merge: true));
        }
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable notifications in App Settings')),
          );
          openAppSettings();
        }
      }
    }
  }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      final prefs = doc.data()?['notifications'] as Map<String, dynamic>? ?? {};
      setState(() {
        _pushEnabled = prefs['push'] ?? true;
        _emailEnabled = prefs['email'] ?? false;
        _matchAlerts = prefs['match'] ?? true;
      });
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'notifications': {key: value}
    }, SetOptions(merge: true));

    // Subscribe/unsubscribe to FCM topics
    final messaging = FirebaseMessaging.instance;
    switch (key) {
      case 'push':
        if (value) {
          await messaging.subscribeToTopic('general');
        } else {
          await messaging.unsubscribeFromTopic('general');
        }
        break;
      case 'match':
        if (value) {
          await messaging.subscribeToTopic('matches');
        } else {
          await messaging.unsubscribeFromTopic('matches');
        }
        break;
      case 'email':
        // Email is handled server-side, just save the preference
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Permission Banner
          if (!_permissionGranted)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notifications Disabled', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade900)),
                        const SizedBox(height: 4),
                        Text('Allow notifications to stay updated', style: TextStyle(fontSize: 13, color: Colors.orange.shade700)),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _requestNotificationPermission,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Allow'),
                  ),
                ],
              ),
            ),

          const Text("Notification Preferences", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Push Notifications"),
                  subtitle: const Text("Receive alerts on your device"),
                  secondary: const Icon(Icons.notifications_active),
                  value: _pushEnabled,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    if (!_permissionGranted) {
                      _requestNotificationPermission();
                      return;
                    }
                    setState(() => _pushEnabled = val);
                    _updateSetting('push', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text("Email Updates"),
                  subtitle: const Text("Weekly hackathon news"),
                  secondary: const Icon(Icons.email_outlined),
                  value: _emailEnabled,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _emailEnabled = val);
                    _updateSetting('email', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text("Match Alerts"),
                  subtitle: const Text("When someone swipes right on you"),
                  secondary: const Icon(Icons.favorite_border),
                  value: _matchAlerts,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    if (!_permissionGranted) {
                      _requestNotificationPermission();
                      return;
                    }
                    setState(() => _matchAlerts = val);
                    _updateSetting('match', val);
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          const Text("About Notifications", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("You'll receive notifications for:", style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text("• New matches from team discovery"),
                  Text("• Chat messages from teammates"),
                  Text("• GDG Hackathon updates & deadlines"),
                  Text("• New developers joining near you"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PrivacySecurityScreen extends StatefulWidget {
  const PrivacySecurityScreen({super.key});

  @override
  State<PrivacySecurityScreen> createState() => _PrivacySecurityScreenState();
}

class _PrivacySecurityScreenState extends State<PrivacySecurityScreen> {
  bool _showInDiscover = true;
  bool _incognitoMode = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && mounted) {
      final prefs = doc.data()?['privacy'] as Map<String, dynamic>? ?? {};
      setState(() {
        _showInDiscover = prefs['showInDiscover'] ?? true;
        _incognitoMode = prefs['incognitoMode'] ?? false;
      });
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'privacy': {key: value}
    }, SetOptions(merge: true));
  }

  Future<void> _deleteAccount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
      await user.delete();
      await GoogleSignIn().signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const EventLandingScreen()),
          (r) => false
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Re-authenticate to delete.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text("Visibility", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text("Show me in Discover"),
                  subtitle: const Text("Turn off to hide your profile from others"),
                  value: _showInDiscover,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _showInDiscover = val);
                    _updateSetting('showInDiscover', val);
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text("Incognito Mode"),
                  subtitle: const Text("Only show me to people I've already matched with"),
                  value: _incognitoMode,
                  activeColor: Theme.of(context).colorScheme.primary,
                  onChanged: (val) {
                    setState(() => _incognitoMode = val);
                    _updateSetting('incognitoMode', val);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text("Danger Zone", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.shade200),
            ),
            child: ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Delete Account", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () {
                 showDialog(
                   context: context,
                   builder: (ctx) => AlertDialog(
                     title: const Text("Delete Account?"),
                     content: const Text("Are you sure? This action cannot be undone."),
                     actions: [
                       TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
                       TextButton(
                         onPressed: () {
                           Navigator.pop(ctx);
                           _deleteAccount();
                         },
                         child: const Text("Delete", style: TextStyle(color: Colors.red)),
                       ),
                     ],
                   )
                 );
              },
            ),
          )
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  const GlassCard({super.key, required this.child, this.borderRadius = 28});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 24,
                spreadRadius: -5,
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
