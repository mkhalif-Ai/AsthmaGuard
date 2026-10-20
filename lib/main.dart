import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const AsthmaGuardApp());

class AsthmaGuardApp extends StatelessWidget {
  const AsthmaGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Asthma Guard',
      theme: ThemeData(
        colorSchemeSeed: Colors.teal,
        useMaterial3: true,
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const LeadDashboardScreen(), // Existing Dashboard
    const SymptomDiaryScreen(),  // New
    const InsightsScreen(),      // New
    const ProfileScreen(),       // New
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.book), label: 'Diary'),
          NavigationDestination(icon: Icon(Icons.timeline), label: 'Insights'),
          NavigationDestination(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}
class SymptomDiaryScreen extends StatelessWidget {
  const SymptomDiaryScreen({super.key});
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Diary')));
}

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Insights')));
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override Widget build(BuildContext context) => const Scaffold(body: Center(child: Text('Profile')));
}

/*class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleSignIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // TODO: Call backend auth provider here
      await Future.delayed(const Duration(seconds: 2)); // Mock network delay
      
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigationScreen())
      );
    } catch (e) {
      setState(() => _errorMessage = 'Authentication failed. Please check your credentials.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign In')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_errorMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.shade100,
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                keyboardType: TextInputType.emailAddress,
                validator: (val) => val == null || !val.contains('@') ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                obscureText: true, // Crucial for security
                validator: (val) => val == null || val.length < 6 ? 'Password too short' : null,
              ),
              const SizedBox(height: 24),
              _isLoading 
                  ? const CircularProgressIndicator()
                  : FilledButton(
                      onPressed: _handleSignIn,
                      child: const Text('Sign In'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}*/

/// Domain model for Environmental Data complying with brief requirements.
class EnvironmentalData {
  final int aqi;
  final String unit;
  final String source;
  final DateTime timestamp;
  final bool isStale;
  final String locationGranularity;

  const EnvironmentalData({
    required this.aqi,
    this.unit = 'AQI Index',
    required this.source,
    required this.timestamp,
    required this.isStale,
    required this.locationGranularity,
  });
}

/// API & Local Storage abstraction layer (Separation of Concerns).
class EnvironmentalRepository {
  static const String _aqiKey = 'last_aqi';
  static const String _timeKey = 'last_timestamp';
  static const String _locationKey = 'last_location';

  Future<EnvironmentalData> loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final aqi = prefs.getInt(_aqiKey) ?? 85;
    final timeStr = prefs.getString(_timeKey);
    final location = prefs.getString(_locationKey) ?? 'City Level (Default)';

    final timestamp = timeStr != null
        ? DateTime.parse(timeStr)
        : DateTime.now().subtract(const Duration(hours: 2));

    final isStale = DateTime.now().difference(timestamp).inMinutes > 60;

    return EnvironmentalData(
      aqi: aqi,
      unit: 'AQI Index',
      source: 'Mock Environmental API',
      timestamp: timestamp,
      isStale: isStale,
      locationGranularity: location,
    );
  }

  Future<EnvironmentalData> fetchUpdatedData(int currentAqi, String location) async {
    final prefs = await SharedPreferences.getInstance();
    final newAqi = currentAqi >= 120 ? 45 : currentAqi + 25;
    final now = DateTime.now();

    await prefs.setInt(_aqiKey, newAqi);
    await prefs.setString(_timeKey, now.toIso8601String());
    await prefs.setString(_locationKey, location);

    return EnvironmentalData(
      aqi: newAqi,
      unit: 'AQI Index',
      source: 'Mock Environmental API',
      timestamp: now,
      isStale: false,
      locationGranularity: location,
    );
  }
}

class LeadDashboardScreen extends StatefulWidget {
  const LeadDashboardScreen({super.key});

  @override
  State<LeadDashboardScreen> createState() => _LeadDashboardScreenState();
}

class _LeadDashboardScreenState extends State<LeadDashboardScreen> {
  final EnvironmentalRepository _repository = EnvironmentalRepository();

  EnvironmentalData? _envData;
  String _locationText = 'City Level (Default)';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final data = await _repository.loadCachedData();
    if (!mounted) return;
    setState(() {
      _envData = data;
      _locationText = data.locationGranularity;
      _isLoading = false;
    });
  }

  Future<void> _fetchLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location services are disabled. Please enable GPS.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        _showSnack('Location is required to fetch local environmental readings.');
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location access denied. Using manual/default location.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );

      final location =
          'Lat: ${position.latitude.toStringAsFixed(2)}, Lon: ${position.longitude.toStringAsFixed(2)}';

      if (!mounted) return;
      setState(() {
        _locationText = location;
      });

      await _refreshAQI();
    } catch (_) {
      _showSnack('Unable to retrieve location.');
    }
  }

  Future<void> _refreshAQI() async {
    if (_envData == null) return;
    final updated = await _repository.fetchUpdatedData(_envData!.aqi, _locationText);

    if (!mounted) return;
    setState(() {
      _envData = updated;
    });

    if (updated.aqi >= 100) {
      _showAirQualityNotice();
    }
  }

  void _showAirQualityNotice() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Air Quality Notice'),
          content: const Text(
            'The current air quality reading is elevated. Environmental conditions may affect sensitive individuals.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _getRiskLabel(int aqi) {
    if (aqi <= 50) return 'Good';
    if (aqi <= 100) return 'Moderate';
    return 'Poor';
  }

  Color _getRiskColor(int aqi) {
    if (aqi <= 50) return Colors.green;
    if (aqi <= 100) return Colors.orange;
    return Colors.red;
  }

  String _getDescriptiveStatus(int aqi) {
    if (aqi <= 50) {
      return 'Air quality index is low. Ideal conditions recorded.';
    }
    if (aqi <= 100) {
      return 'Air quality index is moderate based on recent station data.';
    }
    return 'Air quality index is elevated based on recent station data.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asthma Guard'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      body: _isLoading || _envData == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_envData!.isStale)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.history, color: Colors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Data may be outdated. Tap update to pull recent station readings.',
                                style: TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Air Quality Reading',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(999),
                                    color: _getRiskColor(_envData!.aqi).withValues(alpha: 0.15),
                                  ),
                                  child: Text(
                                    _getRiskLabel(_envData!.aqi),
                                    style: TextStyle(
                                      color: _getRiskColor(_envData!.aqi),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '${_envData!.aqi}',
                                  style: const TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _envData!.unit,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _getDescriptiveStatus(_envData!.aqi),
                              style: const TextStyle(fontSize: 14),
                            ),
                            const Divider(height: 24),
                            Text(
                              'Source: ${_envData!.source}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                            Text(
                              'Observed: ${_envData!.timestamp.hour.toString().padLeft(2, '0')}:${_envData!.timestamp.minute.toString().padLeft(2, '0')}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: ListTile(
                        leading: const Icon(
                          Icons.location_on,
                          color: Colors.blue,
                        ),
                        title: const Text('Location Scope'),
                        subtitle: Text(_locationText),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _fetchLocation,
                            icon: const Icon(Icons.my_location),
                            label: const Text('Update GPS'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _refreshAQI,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Fetch Reading'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    ),
    );
  }
}
