# DeviaTo — quello che serve sapere

Trasforma gli avvisi di deviazione di GTT (Torino) in geometria georiferita
e risponde a una domanda sola: **la mia fermata è ancora servita?**

Questo file raccoglie ciò che *non* sta nel codice: le misure, le decisioni
e il perché, i punti in cui la specifica sbaglia, e le trappole che hanno
già fatto perdere tempo. Leggilo prima di modificare qualcosa.

---

## 1. Dove sta cosa

```
docs/SPECIFICA-…md      il progetto originale. NON è la verità: vedi §4
docs/FASE-0-RISULTATI   le misure sulle fonti, 31/07/2026
scripts/*.py            Python. Misure e validazione, non fanno parte dell'app
app/                    l'app Flutter (iOS + Android)
app/ARCHITETTURA.md     struttura dei moduli e stato
app/tool/pubblica.dart  il giro del job che calcola per tutti
.github/workflows/      il job su GitHub Actions che lo lancia
validation/             snapshot GTFS giornalieri (test del Segnale A)
```

**Due mondi separati e va bene così.** Gli script Python servono a *misurare*
(quanto è preciso il GPS, quanti toponimi si risolvono, quale modello sbaglia
meno). L'app non li usa e non li userà: sono strumenti da banco.

## 2. Come funziona, in breve

Tutto avviene **per singola linea, su richiesta** — e si può controllare
una linea sola senza toccare le altre, che con 50 richieste LLM al giorno
non è un dettaglio. Non si monitora la rete.
È questa scelta a rendere affidabile il resto: il vincolo geografico del
geocoding è il percorso di *quella* linea.

```
avviso GTT ──► LLM: testo → JSON ──► geocoding VINCOLATO al percorso
                                          │
                                          ▼
                              routing bus (Valhalla) ──► 5 validazioni
                                          │
                                          ▼
                        quali fermate saltano + alternative + mappa
```

Con una **scorciatoia**: se l'avviso nomina solo delle fermate sospese
("Fermata 3445 Sabotino sospesa") non c'è nessun percorso da ricostruire.
Il codice si legge dal testo e si cerca nel GTFS — nessun LLM, nessuna
rete oltre a quella già fatta. È il ramo di massima confidenza, e l'unico
che funziona anche a quota esaurita.

E con un passaggio prima di tutto il resto: **le due fonti si uniscono**.
La stessa variazione arriva spesso sia dal feed sia dalla tabella (31
coppie su 189 avvisi), e le due copie si contraddicono sulle date. Si
tiene il testo più completo e le date della tabella, che sono le uniche
inserite a mano — quelle del feed sono l'ora di pubblicazione. Vale anche una richiesta LLM risparmiata a coppia.

In parallelo, su richiesta: **osservazione dei mezzi** per qualche minuto —
**una linea alla volta**, e continua mentre si guardano le altre.
Dice se la deviazione è in corso o — cosa che nessun'altra fonte sa — se è
**già finita**. E dice **dove i mezzi escono e dove rientrano**, che è
l'unico dato del sistema a non venire da un testo: non è dedotto da come
GTT ha scritto l'avviso, è quello che i bus hanno fatto.

**Il calcolo sta in un job su GitHub, non sul telefono.** Dal 26/09/2026
`.github/workflows/pubblica.yml` esegue `app/tool/pubblica.dart` ogni
mezz'ora di giorno, ogni ora la sera e una volta nel cuore della notte:
scarica il GTFS del giorno, legge gli avvisi, calcola lo stato di
**tutte** le linee e pubblica tre tipi di file JSON sul ramo `gh-pages`
(`indice.json`, `percorsi/<linea>.json`, `stato/<linea>.json`, formato in
`core/io/formato_pubblicato.dart`). L'app li scarica — qualche KB — e ne
tiene una copia per quando non c'è rete. Niente chiavi sul telefono, niente
24 MB di orari, niente quota per utente: le richieste al modello dipendono
dagli avvisi nuovi di GTT (una ventina al giorno), non da quante persone
usano l'app. Geocoding con Photon, routing con Valhalla FOSSGIS, LLM via
OpenRouter: li chiama solo il job.

Resta sul telefono l'**osservazione dei mezzi**, che legge il feed di GTT
direttamente.

## 3. I fatti misurati (31/07/2026)

Non sono stime. Se li rimetti in discussione, rimisurali.

| Cosa | Valore | Dove |
|---|---|---|
| GPS: distanza dal percorso teorico | mediana **3,6 m**, 99° pct 28 m | `burst_probe.py` |
| Posizioni spazzatura (`lat=0,lon=0`) | **~3%** dei mezzi | idem |
| `trip_id` popolato nel feed veicoli | 76,6% | `validate_sources.py` |
| `route_id` negli alert | **96,7%** | idem |
| `trip_id` RT risolti in `trips.txt` | **100%** (251/251) | idem |
| Geocoding vincolato, toponimi reali | **150/150** entro 2 km | `test_geocoding.py` |
| Toponimi corretti: distanza dal percorso | max **800 m** | idem |
| Vie estranee alla linea | **1342 m** o più | idem (controllo) |
| Copertura alias nomi linea | **98,4%** (63/64) | test Dart |
| Estrazione LLM (nemotron-3-super:free) | 34/34, **0 toponimi inventati** | `eval_extractor.dart` |
| Quota gratuita OpenRouter | **50 richieste/giorno** in totale | misurato sul campo |
| Avvisi di **sola fermata sospesa** | **14 su 198** | conteggio sul feed |
| Aggiornamento del feed posizioni | **~20 s** | polling allineato |
| Variazioni **non ancora iniziate** (tabella) | **9 su 47** (19%) | misura 01/08 |
| `active_period.start` negli alert | **161 su 161 nel passato** | idem |
| Variazioni pubblicate da **entrambe** le fonti | **31 coppie** su 189 avvisi | `check_merge_offline.dart` |
| Di queste, quelle in cui la data d'inizio cambia | **17** (fino a 3 mesi) | idem |
| Test | **315** | `flutter test` |
| Somiglianza fra le vie nominate: coppie vere | **0,67 – 1,00** e ≥3 vie | idem |
| Idem, coppie false | **0,67 con 2 vie**, o 3 vie a **0,38** | idem |
| Data d'inizio estraibile a regex dal testo | **40%** — troppo poco | idem |
| Rientro non nominato negli avvisi | **24 su 28** | fixture annotate |
| Rientro — ultima via nominata, distanza dal percorso | mediana **10 m**, 32/50 ≤ 100 m | `check_rejoin_live.dart` |
| Rientro — casi rifiutati dalla guardia dei 300 m | **9 su 50** (18%) | idem |

## 4. Dove la specifica sbaglia

Il documento in `docs/` è il progetto originale. **Sette punti sono stati
smentiti dalle misure.** Non "adattati": smentiti.

1. **L'OTP di GTT non va messo al centro.** È un build più vecchio: i suoi
   `trip_id` non esistono nel feed odierno, mancano 7 linee, e solo il 78%
   dei pattern ha una shape equivalente. La fonte primaria è il **GTFS
   statico**, rigenerato ogni giorno alle 04:00 e CC-BY.
2. **Il ponte `trip_id` passa dal GTFS statico**, non dall'OTP: 100% contro 0%.
3. **`alerts.aspx` non dichiara le fermate impattate.** Gli `stop_id` sono
   *tutte* le fermate della linea (verificato sulla 82: 31 dichiarate = 31
   totali). I codici veri stanno nel **testo**.
4. **Buffer del geocoding: 1 km, non 2.** A 2 km entra spazzatura, a 500 m
   si scartano vie legittime (una deviazione si allontana per definizione).
5. **Soglia fuori-rotta: 50 m, non 80.** Il GPS è molto più pulito del
   previsto.
6. **"Max 20% di sovrapposizione col percorso normale" non regge.** Gli
   avvisi dicono spesso "prosegue per la stessa via": le tre deviazioni
   reali provate condividevano 36%, 38% e 66% ed erano tutte corrette.
   Sostituita con: deve esistere un tratto **continuo** fuori percorso di
   almeno 150 m.
7. **"Non più lungo di 3× la linea d'aria" non regge sugli anelli.** La 2C
   fa 4,3 km per 0,8 km in linea d'aria. Si confronta col **tratto di
   percorso che sostituisce**.

## 5. Trappole già pagate

Ognuna di queste è costata tempo. Sono tutte silenziose: non danno errore.

- **Valhalla usa polilinee a precisione 6**, non 5. Con 5 il primo punto
  finisce a latitudine 450 e la mappa resta vuota senza eccezioni.
- **Photon risponde 400 a `lang=it`** (accetta solo default/de/en/fr). Se
  non controlli lo status sembra "nessun risultato": mi ha fatto misurare
  uno 0% di copertura inesistente.
- **`\b` dopo un punto letterale non trova mai un confine di parola.**
  `\bstr\.\b` non sostituiva niente: dopo il punto viene uno spazio, e
  nessuno dei due è alfanumerico.
- **I file GTFS di GTT hanno il BOM e usano le virgolette.** Uno split su
  virgola sfasa tutte le colonne in silenzio.
- **Il confronto per sottostringhe è pericoloso**: "lavori **strada**li"
  faceva scattare il capolinea "**STRADA** del Drosso" e mandava l'avviso
  sulla direzione sbagliata. Parole intere, e scarta i qualificatori
  generici.
- **La Fréchet discreta misura anche il campionamento.** Densifica prima di
  confrontare, o misuri i vertici invece della forma.
- **Il `Marker` di flutter_map usa le sue dimensioni come area toccabile.**
  Con 11 px non si prende mai su un telefono.
- **Il feed delle posizioni si spegne di notte, il servizio no.** Dopo le
  23:30 `vehicle_position` torna 15 byte vuoti mentre la linea 15 ha corse
  fino alle 01:52. "Feed spento" ≠ "nessun mezzo".
- **`direction: 0` fisso** faceva calcolare le fermate saltate sempre
  sull'andata, anche per gli avvisi che riguardano il ritorno. GTT scrive
  avvisi *per direzione*.
- **Non tutto deve passare dalla geometria.** Il caso più *certo* di tutti
  — "Fermata 3445 Sabotino sospesa", il numero scritto da GTT — si perdeva
  perché il flusso passava dal ricostruire un percorso che lì non esiste.
  Un codice fermata lo prende una regex: niente LLM, niente geocoding,
  niente routing. Vale anche a LLM spento, ed è proprio quando serve.
- **Due riconoscitori diversi per la stessa domanda.** La watchlist
  passava da `GtfsParser`, che confrontava i nomi a mano con un
  maiuscolo-senza-spazi, mentre `LineResolver` aveva già tutte le regole.
  Chi aggiungeva «10N» non vedeva comparire niente: la notturna nel GTFS
  si chiama **N10**. Stessa sorte per «N8» (il GTFS ha N08) e «58
  barrata». Ora `GtfsParser` usa `LineResolver.matchIn`.
- **GTT mette la N delle notturne sia davanti sia dietro**, e le due
  famiglie sono diverse: `N04`, `N08`, `N10` sono le notturne vere
  («notturna, piazza Vittorio Veneto – …»), mentre `1N`, `4N`, `19N`,
  `35N`, `36N` sono altro. **`N04` e `4N` coesistono e non sono la stessa
  linea**: lo scambio prefisso↔suffisso va tentato per ultimo, dopo lo
  zero-padding, o «N4» finirebbe sulla 4N invece che sulla N04.
- **Una rotella muta è indistinguibile da un'app bloccata.** Il
  controllo di una linea può durare mezzo minuto — LLM, geocoding via per
  via, routing — e mostrava solo un cerchietto che gira. `statusOf`
  aveva già un `onProgress` e **non lo passava nessuno**. Ora dice «avviso
  2 di 4: cerco «corso Lecce» sulla mappa», con una barra.
- **Un'attesa lunga rende un pulsante indistinguibile da uno rotto.**
  L'osservazione dormiva 20 s filati fra un campione e l'altro senza
  sentire «basta così»: premevi e non succedeva niente. L'attesa ora si
  sveglia ogni 200 ms.
- **Una scorciatoia "tanto abbiamo già capito" ha reso muto un comando.**
  L'osservazione si fermava appena due mezzi avevano due punti: su una
  linea in servizio succede al secondo campione, cioè dopo **31 secondi**,
  sia che si fossero chiesti 1 o 10 minuti. Il selettore di durata non
  serviva a niente e nessun test se ne accorgeva, perché il test asseriva
  proprio quella scorciatoia. Se l'utente sceglie un numero, quel numero
  vince.
- **`active_period.start` degli alert è l'ora di PUBBLICAZIONE**, non
  l'inizio della variazione. Misurato l'01/08: 161 alert su 161 hanno lo
  start nel passato, e la 65 — il cui testo dice "dalle 8:00 di lunedì 3"
  — risultava già attiva. La data vera d'inizio la dà solo la tabella
  `/cms/variazioni`, che ce l'ha in colonna.
- **Le due fonti datano cose diverse, non una giusta e una sbagliata.**
  La tabella dà l'inizio dei *lavori interi* (la 46: piazza Baldissera dal
  15/09/2025), l'alert descrive la *fase corrente* (dal 26/05/2026). Si
  tiene quella della tabella perché è un campo vero e non un timestamp di
  pubblicazione, e perché sbaglia dalla parte sicura: al più mostra come
  "in corso" qualcosa di programmato, mai il contrario.
- **Il capolinea che sta dopo "direzione" non è una via percorsa.**
  Riconoscendo i doppioni fra le due fonti, "Direzione via Moncalieri
  (Grugliasco)" faceva somigliare fra loro tutte le deviazioni della 55
  in quel senso di marcia: i lavori sui binari di luglio e la deviazione
  del 3-7 agosto finivano uniti in un avviso solo, con le date di uno e
  il percorso dell'altro. Contano le vie **percorse**, non quelle che
  dicono dove va il mezzo.
- **Chi sta fuori dal Navigator non si accorge che una schermata se n'è
  andata.** La striscia dell'osservazione vive nel `builder` di
  `MaterialApp` e si ricostruisce solo quando il repository notifica:
  uscendo dal dettaglio non ricompariva finché non capitava un altro
  aggiornamento — aprire un'altra linea, ricontrollare qualcosa. Il
  `dispose` deve **notificare**, dopo il frame. Il commento che avevo
  lasciato («chi resta viene ricostruito comunque dal Navigator») era
  proprio sbagliato: il Navigator ricostruisce ciò che sta dentro di sé.
- **Apple pretende la stringa anche per i permessi che non chiedi.**
  L'analisi statica del caricamento (avviso 90683) guarda le API
  *referenziate* dal binario, non quelle usate: `geolocator` contiene una
  chiamata a `requestAlwaysAuthorization` in un ramo che con
  `NSLocationWhenInUseUsageDescription` presente non viene mai eseguito, e
  tanto basta a pretendere `NSLocationAlwaysAndWhenInUseUsageDescription`.
  Il plugin ha il flag `BYPASS_PERMISSION_LOCATION_ALWAYS` per compilare
  via quel codice, ma si iniettava dal `Podfile` — e qui Flutter usa
  **Swift Package Manager**, dove non si passano define alle dipendenze.
  Quindi la chiave c'è, col testo dell'altra. Verificato che il permesso
  richiesto resti «quando utilizzi l'app»: la finestra è identica.
- **Chi mette qualcosa sopra le schermate deve togliere il padding che
  ha consumato.** La striscia dell'osservazione si prende la barra di
  stato, ma ogni `AppBar` sotto continuava a spaziarsi come se fosse lei
  in cima: una sessantina di punti di vuoto su ogni schermata. Si risolve
  avvolgendo il figlio in `MediaQuery.removePadding(removeTop: true)`.
- **I `Tooltip` non funzionano nel `builder` di `MaterialApp`.** Il
  `builder` avvolge il Navigator, e l'`Overlay` che i tooltip pretendono
  lo fornisce il Navigator: quindi si sta *sopra* di esso. Con `tooltip:`
  sul pulsante della striscia l'app si apriva sulla schermata rossa —
  `No Overlay widget found`. Si usa `Semantics(label: …)`, che dà
  l'etichetta ai lettori di schermo senza pretendere nulla.
- **Lo stato che deve sopravvivere alla navigazione non va nella
  schermata.** L'osservazione dei mezzi viveva in `_LineScreenState` e
  moriva al primo `Navigator.pop`: uno la faceva partire, andava a
  guardare un'altra linea, e tornando non c'era più. Ora sta in
  `AppRepository`, che vive quanto l'app. Vale come regola: se una cosa
  deve continuare mentre l'utente si sposta, la schermata è il posto
  sbagliato.
- **Le escursioni vanno confrontate con TUTTE le varianti, non con la
  principale.** Visto sul campo appena scritto il rilevatore: la 65 diceva
  «3 mezzi seguono il percorso normale» e subito sotto «lasciano il
  percorso a Collegno». Il mezzo stava su una diramazione legittima —
  lontano dalla variante principale, ma sulla sua. È lo stesso falso
  positivo che `VehicleTrack.isOffRoute` evitava già; il rilevatore nuovo
  lo aveva reintrodotto. Le posizioni si **misurano** sulla principale (o
  non sarebbero confrontabili), ma «è fuori?» si decide sulla variante più
  vicina.
- **La deduzione del rientro regge sulla mediana, non sulla coda.**
  Misurato su 50 casi veri (`check_rejoin_live.dart`, senza LLM e senza
  le annotazioni): mediana 10 m, ma 75° pct 237 m e massimo 793 m. Solo
  32 su 50 stanno entro 100 m. Due cause distinte, tutte e due reali:
  **le vie lunghe** — Photon dà due punti per corso Matteotti, distanti
  1 km — e **i nomi ambigui col nome di città**: «via Torino» restituisce
  Stadio Olimpico e Porta Nuova, il che colpisce le extraurbane. La
  guardia dei 300 m ne rifiuta 9 su 50 e dichiara di non sapere; restano
  9 casi fra 100 e 300 m accettati, che sono il rischio residuo.
  ⚠️ **Una nota precedente diceva «mediana 1 m, 21/22 ≤ 100 m»: era
  misurata sulle fixture annotate dall'LLM, cioè su un campione più
  piccolo e non indipendente.** La misura sopra la sostituisce.
- **Il rientro va cercato A VALLE dello stacco.** Una linea puo' passare
  due volte vicino alla stessa via: senza il vincolo si sceglie il
  passaggio già fatto. Con la direzione sbagliata la deduzione finisce a
  2 km — verificato, e la guardia l'ha rifiutata invece di piazzarla lì.
- **Ogni avviso sa solo delle sue fermate chiuse.** Le alternative si
  calcolavano avviso per avviso. Il 26/09 GTT ha pubblicato per la 10N
  **sedici avvisi, uno per fermata**, e per Verolengo le prime due
  alternative proposte erano Largo Giachino Sud e Brin: chiuse anche
  loro, dagli avvisi accanto. Ora `DeviationReport.reconcileAlternatives`
  le rifà guardando la linea intera, anche sugli esiti già salvati.
- **Sedici avvisi non sono sedici notizie.** Per chi aspetta il bus erano
  una cosa sola: nove fermate chiuse di fila in una direzione. Il
  dettaglio ora apre con `ClosureSummary` (per tratti, con le fermate
  aperte ai capi) e raccoglie gli avvisi in una voce chiusa quando sono
  più di tre. Con tratti sparsi (la 68: quattro verso Frejus) si va per
  righe, una per tratto: una striscia di ventisette pallini non si legge.
- **Una schermata di caricamento sopra la lista nasconde tutto.** «Controlla
  tutte» copriva la home: spariti i risultati già pronti, nessun modo di
  fermarsi, e col modello gratuito durava dieci minuti (sei per la sola
  10N). Ora la lista resta, ogni riga dice a che punto è e da quanto, e
  in fondo c'è il conto con «Annulla». Il testo sui 24 MB compariva a
  ogni controllo: ora solo durante il download vero.
- **Il GTFS dice già tipo di mezzo, colore e ordine delle linee.**
  `route_type`, `route_color`, `route_sort_order`: l'app li ignorava,
  metteva tutte le etichette dello stesso azzurro e ordinava per nome (la
  4 dopo la 15). Il colore del *testo* di GTT invece non va usato:
  `route_text_color` è 0000FF, blu su arancio, 3,3:1.
- **I colori scritti a mano non passano il contrasto e non cambiano al
  buio.** `orange.shade800` sullo sfondo dell'app fa 2,93:1. Stanno in
  `ui/theme.dart`, misurati in chiaro e in scuro.
- **Una `ShaderMask` col nero colora, non sfuma.** Il testo di GTT
  richiuso usava un gradiente nero: in chiaro non si notava, al buio il
  testo diventava nero su nero. Per sfumare serve `BlendMode.dstIn`, che
  usa solo l'opacità.
- **La spaziatura fra lettere di Material 3 è pensata per Roboto.** Su
  iOS allarga il San Francisco e le scritte piccole sembrano spaziate a
  mano: il tema la azzera.
- **Una linea non risponde per la fermata.** «16 fermate non servite»
  sulla 10N è vero, ma chi aspetta a Mortara non sa se c'è anche la sua.
  Le **fermate salvate** (linea + direzione + palo, `SavedStop`) stanno in
  cima alla home con la loro risposta (`StopAnswer`): servita, non servita
  fino al…, dove salire. Si salvano toccando la fermata sulla mappa del
  dettaglio. La direzione conta: le banchine opposte hanno id diversi, e
  una deviazione è quasi sempre per un senso di marcia solo.
- **Aggiungere una linea non deve ricaricare tutto, toglierla non deve
  cancellare le altre.** L'aggiunta passava dalle impostazioni, col nome
  scritto a memoria, e rileggeva gli orari di tutte le linee dietro una
  schermata a pieno schermo; la rimozione svuotava la cache di TUTTE —
  togliere la 65 costava la ricontrollata della 10N, sedici richieste
  delle cinquanta. Ora si cerca dalla home (`LineSearch`, per numero o per
  via, sulle 216 linee di `routes.txt`), si leggono gli orari della sola
  linea nuova, e si toglie scorrendo con «Annulla», che rimette anche
  l'esito e le fermate salvate.
- **`Dismissible` pretende che la riga sparisca subito.** Se al primo
  aggiornamento dello schermo la linea tolta è ancora nell'elenco, Flutter
  si ferma con un errore. Per questo `removeLine` toglie dalla memoria
  *prima* di qualunque `await` su disco.
- **Un avviso non letto non vuol dire «fermate servite».** Con la quota
  esaurita l'avviso della 7 («sospesa domenica 27») restava solo testo, e
  la home diceva «Deviata, fermate servite»: la riga cadeva nel caso
  «avvisi ma nessuna fermata saltata», che però vale solo se l'avviso è
  stato letto. Ora dice «Avviso in corso», e una fermata salvata su quella
  direzione risponde «Avviso in corso: controlla i dettagli», non
  «Servita».
- **La quota si consumava tre volte più del necessario, e un
  aggiornamento fallito cancellava quelli riusciti.** Tre difetti, tutti
  vecchi, visti insieme il 26/09: (1) ogni avviso si leggeva **una volta
  per direzione** — la 10N, sedici avvisi, costava trentadue richieste
  delle cinquanta; (2) ogni «Aggiorna» **rileggeva anche gli avvisi
  identici**; (3) un aggiornamento a quota esaurita **sostituiva** gli esiti
  buoni (15, 55, 68) con «non letto». Ora il testo si legge una volta per
  avviso, un avviso uguale (testo, date, direzioni) non si rilegge, e i
  fallimenti che passano — quota, rete, servizi giù — sono marcati
  `retryable` e si ritentano al giro dopo. Gli esiti salvati prima di
  questa correzione non hanno il segnale: si ritenta, una volta, ciò che
  non era verificato.
- **Un file che cambia a ogni giro riscrive tutto il sito.** Lo stato di
  una linea non contiene l'ora del giro: quella sta solo nell'indice. Così
  `pubblica.dart` riscrive un file solo quando il contenuto cambia, e il
  secondo giro di prova ha cambiato zero file su 432. Il ramo `gh-pages`
  tiene un commit solo, riscritto ogni volta (`--amend` e `push -f`): la
  storia dei dati non serve e farebbe crescere il repository di continuo.
- **Il job gira su un server che non sta a Torino.** Le date degli avvisi
  vanno lette in ora di Torino: nel workflow c'è `TZ: Europe/Rome`, e nei
  file le date si scrivono in UTC con la «Z» e si rileggono in ora locale.
- **Il repository si chiama `deviato` dal 27/09/2026** (prima
  `gtt-deviazioni`). GitHub rimanda dal vecchio indirizzo del codice, ma
  **non da quello di Pages**: un'app compilata con l'indirizzo vecchio
  resta senza dati. La cartella locale e gli script di misura hanno
  tenuto il nome vecchio, di proposito.
- **La build definitiva Android non aveva il permesso internet.** Flutter
  lo mette nei manifest di prova (`debug/`, `profile/`), non in `main/`:
  l'app lanciata con `flutter run` funzionava, l'APK definitivo diceva
  «Nessuna connessione» con la rete accesa. Visto alla prima build, il
  27/09. Se ne accorge solo chi prova il file che va sullo store.
- **Uno SnackBar con un pulsante non sparisce più da solo.** Nelle
  versioni recenti di Flutter `persist` vale `true` quando c'è un'`action`:
  «Fermata rimossa» con «Annulla» restava sopra la home finché non lo si
  chiudeva a mano. Ora dura cinque secondi, e resta solo con VoiceOver o
  TalkBack (`MediaQuery.accessibleNavigationOf`), dove raggiungere il
  pulsante richiede tempo. Vale per ogni SnackBar nuovo con un'azione.
- **Un tema generato da un colore di partenza tinge tutto, anche gli
  sfondi.** Con `ColorScheme.fromSeed` blu l'app sembrava azzurra
  ovunque. Dal 27/09 la tavolozza è scritta ruolo per ruolo in
  `ui/theme.dart` (grafite, giallo, grigi neutri, come logo e sito), con
  i contrasti misurati. Il giallo non fa mai da testo su fondo chiaro
  (1,45:1).
- **La cartina resta chiara anche col tema scuro.** I segni disegnati
  sopra non devono seguire il tema: al buio la fermata chiusa diventava
  `colorScheme.error` scuro, cioè rosa pallido su strade chiare. Seguono
  la cartina, non il tema: `Cartina.of` in `ui/cartina.dart`.
- **I dati restavano quelli dell'apertura.** L'app scaricava solo
  all'avvio e con «Aggiorna»: iOS la tiene in memoria per ore, e chi la
  riapriva la sera vedeva gli avvisi del mattino. Ora riscarica tornando
  in primo piano (`AppRepository.aggiornaSeServe`, se l'ultimo tentativo
  ha più di due minuti o non era riuscito), si aggiorna tirando giù home
  e dettaglio, e il pulsante compare solo dopo un tentativo fallito.
- **Un comando in fondo alla lista non lo trova nessuno.** I mezzi in
  tempo reale erano una scheda dopo tutti gli avvisi: con due avvisi
  aperti bisognava scorrere fino alla fine. Ora si aprono da un pulsante
  che fluttua in basso al centro del dettaglio, che dice anche a che punto
  è l'osservazione; partendo, il pannello si chiude e la pagina scorre
  alla mappa, dove i mezzi compaiono.
- **Interrompere a mano buttava via l'esito.** `stopWatch` svuota
  `watchingRouteId` subito, e il ciclo che finiva dopo non riconosceva
  più la sua linea: l'esito andava perso. Con le durate succedeva solo
  premendo «Interrompi»; dal 27/09, senza durate (si guarda finché non si
  interrompe, con un tetto di sicurezza di due ore), sarebbe successo
  sempre. Ora si butta solo se nel frattempo si è passati a un'altra linea.
- **La rotta dei mezzi si misura, non si legge.** Il segno del mezzo ha
  una punta verso dove va e il colore della direzione che sta facendo
  (`VehicleHeading`): la rotta viene dallo spostamento fra due campioni
  distanti almeno 15 m — sotto è rumore del GPS — e solo in mancanza da
  quella dichiarata nel feed. La direzione si assegna confrontandola col
  verso del percorso nel punto più vicino, entro 60 m e 60°: sulla via
  percorsa nei due sensi è l'unico modo di separare andata e ritorno.
  Attenzione agli assi: in `Projection.toMeters` `x` è il nord.
- **Le immagini della cartina vengono da CARTO dal 27/09** (`ui/cartina.dart`):
  Positron in chiaro e Dark Matter in scuro, gratuite per uso non
  commerciale fino a 5 milioni al mese, con una chiave. Prima erano quelle
  di OpenStreetMap, un servizio volontario che non ha la versione scura:
  la cartina restava chiara anche col tema scuro. I colori dei segni
  cambiano con la cartina (`Cartina.of`), non col tema. L'attribuzione è
  una scritta nostra in alto a sinistra, sempre visibile: CARTO non la
  vuole dietro un tocco (l'icona «i» di `RichAttributionWidget`),
  `SimpleAttributionWidget` mette davanti «flutter_map | ©», e in basso la
  coprirebbe il pulsante dei mezzi.
- **Una mappa alta 280 punti non basta a leggere una deviazione.** Dal
  27/09 c'è la mappa a tutto schermo (`ui/full_map_screen.dart`): si apre
  dal pulsante in angolo o toccando un punto vuoto della mappa del
  dettaglio. In alto si può tenere una direzione sola — dove andata e
  ritorno passano per le stesse vie (la 9, la 15) le due linee si coprono —
  e in basso un pannello si trascina — o si apre toccando «Più
  dettagli» —: chiuso una riga, a metà le fermate per tratti (toccandone
  uno la mappa lo inquadra), e la fermata toccata. I comandi della mappa
  hanno la scritta: «Tutta la linea», «Segui i mezzi», «Dove sono». È la stessa `LineMap` del dettaglio in
  modalità `fullScreen`, e lo stesso riassunto, spostato in `riassunto.dart`
  perché lo usano tutte e due. Il pulsante con le quattro frecce che
  inquadrava il percorso sembrava «ingrandisci»: nel dettaglio ora
  ingrandisce davvero, e l'inquadratura è rimasta a tutto schermo.
- **Gli orari programmati di GitHub sono una promessa debole.** Nelle
  prime dodici ore, coi minuti 5/25/45, sono partiti **3 giri su 27**:
  nessun errore, nessun giro annullato, semplicemente non lanciati.
  GitHub dichiara che sotto carico li ritarda e li salta, soprattutto
  vicino all'inizio dell'ora. Nemmeno i minuti 13/43 sono bastati: dalle
  8:29 alle 17 del 27/09 non ne è partito nessuno. Da allora il giro lo
  lancia **cron-job.org** (account di Tommaso, due attività in ora di
  Roma) chiamando `workflow_dispatch` con un token a grana fine, solo
  «Actions: read and write» su questo repository, che **scade il
  26/09/2027**. L'intestazione `X-GitHub-Api-Version: 2022-11-28` è
  deprecata e smette di funzionare il 10/03/2028: al rinnovo del token va
  aggiornata. Gli orari di GitHub restano come riserva, ogni tre ore.

## 6. Le regole di condotta del sistema

Non sono stile: sono il motivo per cui questa cosa può essere usata.

> **Meglio nessuna mappa che una mappa sbagliata.** Un falso positivo fa
> camminare l'utente 800 metri per niente e non si fida mai più (§11.4).

In pratica:

- Se un toponimo non si risolve o una validazione fallisce, si **dichiara
  l'incertezza**. Mai una geometria inventata.
- Il **testo originale di GTT** si mostra sempre, in fondo a tutto: se il
  sistema sbaglia, il dato grezzo resta.
- I nomi di linea non risolti si **segnalano**, non si indovinano.
- I messaggi d'errore distinguono ciò su cui l'utente **può agire** (quota,
  chiave, rete) da ciò su cui non può.
- **"Non lo so" è una risposta valida** e va detta come tale: "nessun mezzo
  osservato" non è "va tutto bene".
- Gli orari si dicono in **ora locale**: "mezzanotte UTC" all'una di notte
  sembra una bugia.

### Chi la usa

Non solo chi è cresciuto coi telefoni: alla fermata ci sono anche persone
anziane, e l'app deve funzionare per loro senza spiegazioni.

- **I comandi dicono cosa fanno con una parola**, non solo con un'icona:
  «Dove sono», non un mirino. Dove lo spazio manca (la mappa piccola del
  dettaglio) l'icona resta, ma con la descrizione per i lettori di schermo.
- **Bersagli da almeno 44–48 punti** e scritte dei comandi a 15.
- **Nessun gesto senza alternativa visibile**: il pannello che si trascina
  si apre anche toccando «Più dettagli».
- **Le linee sulla mappa si vedono senza cercarle**: spesse 5,5 punti,
  quasi piene.

### Come si scrivono i testi dell'app

Sono testi da applicazione, non spiegazioni: brevi, al presente, con il
«tu» negli inviti («Aggiungi le tue linee»), mai in prima persona. Le
etichette senza punto finale, le frasi di dettaglio con il punto. Il
perché delle scelte sta nei commenti del codice, non sullo schermo.

| Si dice | Non si dice |
|---|---|
| **Aggiorna**, Aggiornamento…, aggiornata alle 17:22 | controlla, ricontrolla, controllata |
| **Riprova** (solo dopo un aggiornamento non riuscito) | un «Aggiorna» sempre in vista |
| Tocca per aggiornare (linea mai aggiornata) | Da controllare |
| **fermata non servita** | saltata, chiusa (in interfaccia) |
| sospesa da GTT (solo per le fermate dichiarate) | — |
| **Mezzi in tempo reale**, Segui i mezzi, Interrompi | osservazione, Guarda adesso, Basta così |
| Rimuovi, Linea 65 rimossa | Togli, Tolta la 65 |
| avviso di GTT, Testo originale | nomi delle fonti (feed, tabella variazioni) |
| Verificato · Da confermare · Solo il testo di GTT | ricostruita, geometria, validazione |
| In vigore dal 12/10 · fra 16 giorni | Non ancora in vigore — comincia… |

Nessun nome tecnico sullo schermo — LLM, GTFS, Valhalla, Photon, soglie,
«max 3x» — salvo i crediti nelle impostazioni, che la licenza richiede
(«© contributori di OpenStreetMap»). Gli errori dicono cosa è successo e
cosa fare («Nessuna connessione. Riprova quando sei online.»); il testo
dell'eccezione va nel log, mai sullo schermo.

## 7. Cosa NON fa (ancora)

Per non fraintendere quello che c'è in `config.dart`:

- **niente notifiche.** Il calcolo periodico ora c'è (il job su GitHub),
  ma nessuno manda le notifiche: servirebbe un servizio push. È il passo
  naturale successivo.
- **su Android è stata provata solo sul telefono virtuale** (27/09/2026,
  API 36): dati, aggiunta di una linea, mappa. Mai su un telefono vero,
  mai la posizione né i mezzi in tempo reale. Java 17 è quello di Temurin
  (`flutter config --jdk-dir`). La chiave per il Play Store sta in
  `~/deviato-upload.jks`, e `android/key.properties` (escluso da git) dice
  dove e con che password: senza quel file si firma con la chiave di prova.
  **`flutter build appbundle` finisce con «failed to strip debug symbols»
  ma l'AAB è buono**: le librerie sono alleggerite (verificato con `file`)
  e i simboli stanno a parte in `BUNDLE-METADATA`. È il controllo di
  Flutter a fallire, perché usa `apkanalyzer` di `cmdline-tools`, che qui
  manca.
- **distanze a piedi in linea d'aria**, non reali. L'interfaccia lo dichiara.
- **dentro una direzione usa solo la variante principale.** Una deviazione
  che riguardasse la sola corsa limitata verrebbe calcolata sul percorso
  intero — lo stesso errore corretto un livello più in alto.
- **il Segnale A ha una prima risposta** (01/08: 7 cambiamenti su 16 CD,
  65, 73, uno dei quali combacia con un avviso dello stesso giorno), ma
  servono più giorni per la latenza. Un
  LaunchAgent gira alle 05:00 (`com.tommaso.gtt-deviazioni.snapshot`), e
  una routine cloud esiste ma non ha mai girato con successo.

## 8. Come si lavora

```bash
cd app && flutter test          # 315 test, devono passare tutti
cd app && flutter analyze       # deve essere pulito
```

**Ogni build dell'app va fatta con le chiavi**: `--dart-define-from-file=chiavi.json`
(`flutter run`, `flutter build ipa`, `flutter build appbundle`). Il file sta in
`app/chiavi.json`, escluso da git; il modello è `app/chiavi.esempio.json`.
Oggi contiene solo `CARTO_KEY`, la chiave gratuita delle immagini della
cartina: senza, l'app torna alle cartine di OpenStreetMap e funziona lo
stesso, ma una build per lo store fatta così cambierebbe cartina di nascosto.

Misure offline, su fixture e GTFS già scaricati:

```bash
cd app && dart run tool/check_merge_offline.dart   # unione delle due fonti
cd app && dart run tool/check_rejoin_live.dart     # qualità del rientro dedotto
```

Verifiche dal vivo, che usano servizi veri:

```bash
cd app && dart run tool/check_pipeline_live.dart      # catena completa
cd app && dart run tool/check_geocoding_live.dart     # solo geocoding
OPENROUTER_API_KEY=... dart run tool/eval_extractor.dart --provider openrouter
```

Il GTFS per i test sta in `data/gtfs/` e si estrae da `data/gtt_gtfs-*.zip`.
I test che ne hanno bisogno si **saltano da soli** se non c'è.

### Come si verifica sul serio

Le prove più utili di questa sessione sono venute dal **far girare l'app sul
simulatore iOS** e guardare cosa succede, non dai test. Il bersaglio delle
fermate troppo piccolo, il feed spento di notte, la chiave rovinata, la home
bianca all'avvio: nessuno di questi sarebbe emerso da un test scritto a
tavolino.

Quando qualcosa sembra rotto, **guarda i log prima di toccare il codice**:
una volta ho creduto che l'osservazione fosse bloccata, e invece stavo
facendo gli screenshot troppo presto.

## 9. Note pratiche

- I dati GTT sono **CC-BY**: citare la fonte (già nel piè di pagina).
- **La posizione dell'utente non esce dal telefono.** Serve solo a
  disegnare un punto sulla mappa: non si salva, non entra in nessuna
  richiesta di rete, e Photon e Valhalla ricevono i toponimi degli avvisi
  e il percorso della linea, mai dove sei tu. Il permesso si chiede al
  tocco del pulsante, non all'apertura: una richiesta che arriva senza
  che tu abbia chiesto niente si nega per riflesso, e poi è finita.
  `geolocator` è un plugin Flutter, quindi `user_location.dart` sta in
  `data/` e non in `core/`.
- Photon e Valhalla sono **servizi di cortesia**: pause fra le chiamate,
  User-Agent identificabile, e sempre un ripiego se cadono.
- La chiave OpenRouter sta **solo nei segreti di GitHub Actions**
  (`OPENROUTER_API_KEY`), mai nel codice né sul telefono. Le versioni
  precedenti la salvavano nelle preferenze: `Settings.load` la cancella.
- **Licenza dei dati.** CC BY 4.0 sul portale del Comune, ma la pagina di GTT
  (`gtt_gtfs_license.html`) dice «non-commercial use only»: l'app resta
  gratuita, senza pubblicità né acquisti. Attribuzione obbligatoria: «Data
  source: GTT S.p.A. – Gruppo Torinese Trasporti» con link — sta nelle
  Informazioni, in fondo al dettaglio e nell'`indice.json`.
- **La tabella `/cms/variazioni` è spenta nel job** (`USA_TABELLA_VARIAZIONI`):
  non è un dato aperto, e le note legali del sito proteggono i contenuti. Si
  accende quando GTT lo autorizza. Senza, le date d'inizio vengono solo dal
  feed, che dà l'ora di pubblicazione.
- Le 34 fixture annotate in `tests/fixtures/annotations.json` **le ho
  scritte io, non un umano**: vanno riviste prima di usarle come verità.

---

*Ultimo aggiornamento: 27 settembre 2026. 315 test.*
