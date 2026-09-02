import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'core/app_state.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1320, 900),
    minimumSize: Size(900, 620),
    center: false,
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden, // native baslik cubugu yerine kendi cizdigimiz kullanilir
    title: 'Network Console',
  );
  windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const NetworkConsoleApp());
}

class NetworkConsoleApp extends StatefulWidget {
  const NetworkConsoleApp({super.key});
  @override
  State<NetworkConsoleApp> createState() => _NetworkConsoleAppState();
}

class _NetworkConsoleAppState extends State<NetworkConsoleApp> {
  final AppState _state = AppState();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _state.init().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _state,
      child: Consumer<AppState>(
        builder: (context, state, _) {
          final theme = AppTheme(state.isDark);
          return MaterialApp(
            title: 'Network Console',
            debugShowCheckedModeBanner: false,
            theme: theme.themeData,
            home: _ready
                ? const AppShell()
                : Container(
                    color: theme.c.bgDeep,
                    alignment: Alignment.center,
                    child: CircularProgressIndicator(color: theme.c.accent),
                  ),
          );
        },
      ),
    );
  }
}
