# TestFlight pubblico — cosa fare e cosa incollare

Tutto quello che serve per far provare DeviaTo a chiunque con un link
pubblico di TestFlight. I testi sono pronti da copiare nei campi di App
Store Connect; le voci del pannello possono avere nomi leggermente diversi.

---

## 1. Una volta sola

1. **Xcode › Impostazioni › Account › +**: aggiungi il tuo Apple ID (il
   team a pagamento è `9WHPB8DRJ9`). Serve a firmare e caricare le build
   da riga di comando senza aprire altro.
2. **Build firmata** (la fa Claude): registra da sola l'identificativo
   `dev.tcdesign.deviato` nel portale sviluppatori.
3. **App Store Connect › App › + › Nuova app**
   - Piattaforma: iOS
   - Nome: `DeviaTo` (se è già preso: `DeviaTo Torino`)
   - Lingua principale: Italiano
   - ID pacchetto: `dev.tcdesign.deviato`
   - SKU: `deviato`
   - Accesso utenti: accesso completo
4. **Caricamento** (lo fa Claude). Poi Apple elabora la build: da dieci
   minuti a un'ora. Arriva un'email quando è pronta.

La domanda sulla crittografia non compare: l'app dichiara nell'Info.plist
che usa solo quella standard (`ITSAppUsesNonExemptEncryption = NO`).

## 2. TestFlight › Informazioni sul test

**Descrizione della beta**

```text
DeviaTo ti dice se la tua fermata di bus o tram a Torino è ancora servita quando GTT devia una linea: quali fermate non sono servite, fino a quando e dove salire invece.

Aggiungi le linee che usi con +. Poi apri una linea e tocca la tua fermata sulla mappa per salvarla: la home ti risponde per quella.

È una versione di prova. I percorsi deviati sono ricostruiti in automatico dal testo degli avvisi di GTT e possono contenere errori: in caso di dubbio fa fede l'avviso originale, che trovi in fondo a ogni linea.

DeviaTo è gratuita, senza pubblicità e senza account. Non è un'app di GTT e non è collegata a GTT.
```

**Email per il feedback**: `devia.to@icloud.com` (deve essere attiva)

**URL di marketing**: `https://deviato.it/`

**URL della privacy**: `https://deviato.it/privacy.html`

## 3. Informazioni per la revisione della beta

Il test esterno — quello del link pubblico — passa da una revisione di
Apple alla prima build di ogni versione. Di solito un giorno o due.

- **Contatto**: nome, cognome, telefono ed email tuoi (li vede solo Apple).
- **Accesso richiesto**: no. L'app non ha account.
- **Note** — in inglese, perché chi rivede di solito legge quello:

```text
DeviaTo shows which bus and tram stops in Turin (Italy) are not served when the local transit operator, GTT, publishes a detour.

It uses GTT's open data (GTFS static timetables, GTFS-Realtime service alerts and vehicle positions), which GTT S.p.A. publishes for reuse with attribution: https://www.gtt.to.it/gtt_gtfs_license.html — also available under CC BY 4.0 on the City of Turin open data portal: https://aperto.comune.torino.it/dataset/feed-gtfs-trasporti-gtt
The required attribution is shown in the app (Info screen, and at the bottom of every line) and on the website.

The app is free, with no ads, no in-app purchases and no accounts, and it is not affiliated with GTT; the app and the website state this explicitly.

No login is needed. To try it: tap +, pick a line (for example 10N or 15), then open it to see the map, the stops that are not served and GTT's original notice. Location permission is optional and is only used to show your position on the map; it never leaves the device.
```

## 4. Cosa testare (per ogni build)

**Build 1.0.0 (15)** — quella da dare ai tester (dell'01/10, caricata
su TestFlight il 02/10; AAB versionCode 15 per il Play Store. Il primo
caricamento rispondeva «You do not have required contracts» e poi «PLA
Update available»: Apple aveva aggiornato l'accordo per sviluppatori, e
finché l'intestatario non lo accetta su developer.apple.com non si
carica niente): sulla mappa a tutto schermo i
tre comandi — «Tutta la linea», «Segui i mezzi», «Dove sono» — stanno in
fondo alla scheda e non più sulla cartina; la scheda si riduce verso il
basso (freccia accanto alle etichette, o trascinandola) e si riapre da
«Dettagli»; finché non si sposta la mappa, il percorso resta inquadrato
sopra la scheda.

**Build 1.0.0 (14)** (caricata il 30/09, e come AAB versionCode 14 per il
Play Store): sulla mappa a tutto schermo,
al posto del pannello dal basso, una scheda fluttuante a pagine —
Riepilogo, Fermate, Avvisi — da toccare o scorrere di lato; è alta
quanto il contenuto (al massimo metà schermo, poi scorre) e toccando una
fermata mostra quella. I comandi a destra sono stretti quanto «Tutta la
linea» (su Android «Segui i mezzi» non va più a capo).

**Build 1.0.0 (13)** (caricata il 30/09 mattina, e come AAB versionCode
13 per il Play Store): nelle Informazioni i link al
sito, alla mail («Segnala un errore o scrivici»), al codice e
all'informativa, e «© 2026 DeviaTo»; i mezzi in tempo reale dicono
«fuori dal percorso» solo se lo sono almeno due (uno solo può essere un
bus che rientra al deposito) e non dicono più che la deviazione potrebbe
essere finita; sulla mappa a tutto schermo il comando dei mezzi si
muove mentre li segue, e i tre comandi non cambiano più larghezza.

**Build 1.0.0 (12)** (caricata il 29/09 sera, e come AAB versionCode 12
per il Play Store): la schermata di avvio col logo sullo sfondo della home, chiaro o scuro (da Android 12 il simbolo su
un cerchio giallo). Per il resto uguale alla 11.

**Build 1.0.0 (11)** (caricata il 29/09, e lo stesso giorno come AAB
versionCode 11 per il Play Store): le fermate salvate raggruppate per linea nella home, una riga per fermata; niente
più «fino al» con la data finta che GTT mette agli avvisi «sino a nuove
comunicazioni». Dal 29/09 i percorsi deviati li calcola il secondo
algoritmo (lato job, non nella build): deviazioni già negli orari
riconosciute, percorso lungo le vie dell'avviso. Va compilata con
`--dart-define-from-file=chiavi.json`.

**Build 1.0.0 (10)**: mappa a tutto schermo con i comandi scritti («Tutta
la linea», «Segui i mezzi», «Dove sono»), una direzione sola e il
pannello dal basso; percorsi più spessi; cartina di CARTO chiara o scura;
mezzi in tempo reale con la direzione.

```text
Prima versione di prova. Ci aiuta soprattutto sapere:
• se le fermate indicate come non servite corrispondono a quello che trovi in strada;
• se trovi facilmente la tua linea e la tua fermata;
• qualsiasi cosa ti sembri poco chiara o sbagliata.

Per mandarci un commento basta fare uno screenshot dentro l'app: TestFlight ti propone di inviarlo.
```

## 5. Aprire il link pubblico

1. **TestFlight › Test esterno › +**: nuovo gruppo, per esempio `Pubblico`.
2. Aggiungi la build al gruppo e compila «Cosa testare».
3. **Invia per la revisione della beta.**
4. Quando Apple approva: nel gruppo, **Abilita link pubblico**. Conviene
   un limite di tester (per esempio 1.000) e, se vuoi, il vincolo
   «solo iPhone».
5. Il link (`https://testflight.apple.com/join/…`) si può mettere sul sito
   al posto di «In arrivo su App Store».

Le build di TestFlight scadono dopo **90 giorni**: prima di allora ne serve
una nuova.

## 6. Prima di aprire il link, controllare

- [x] L'icona dell'app, gialla dalla build 4.
- [x] L'email `devia.to@icloud.com` è attiva (è l'indirizzo del feedback).
- [ ] Il job su GitHub gira con regolarità: chi prova l'app deve vedere
      dati di oggi, non di ieri.
- [x] Il dominio `deviato.it` risponde, con HTTPS.
