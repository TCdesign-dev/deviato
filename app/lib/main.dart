import 'dart:async';

import 'package:flutter/material.dart';

import 'data/app_repository.dart';
import 'data/settings.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';
import 'ui/watch_banner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();
  final repo = AppRepository(settings);
  // L'avvio non blocca la prima schermata: il GTFS pesa 24 MB e l'utente
  // deve vedere l'avanzamento, non una pagina bianca.
  unawaited(repo.initialise());
  runApp(GttApp(repo: repo));
}

class GttApp extends StatefulWidget {
  const GttApp({required this.repo, super.key});

  final AppRepository repo;

  @override
  State<GttApp> createState() => _GttAppState();
}

class _GttAppState extends State<GttApp> {
  // Tornando all'app si riscaricano i dati, se sono di qualche minuto fa:
  // cosi' «Aggiorna» serve solo quando qualcosa non e' andato.
  late final AppLifecycleListener _ciclo;

  @override
  void initState() {
    super.initState();
    _ciclo = AppLifecycleListener(onResume: widget.repo.aggiornaSeServe);
  }

  @override
  void dispose() {
    _ciclo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.repo;
    return MaterialApp(
      title: 'DeviaTo',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // La striscia dell'osservazione sta QUI e non nelle schermate:
      // deve comparire sopra tutte, comprese quelle che ancora non
      // esistono, e nessuna di loro deve saperne niente.
      builder: (context, child) =>
          WatchBanner(repo: repo, child: child ?? const SizedBox.shrink()),
      home: HomeScreen(repo: repo),
    );
  }
}
