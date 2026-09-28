<div align="center">

# 🚏 DeviaTo

**Gli avvisi di deviazione di GTT (Torino) sono scritti in prosa.<br>
DeviaTo li trasforma in una mappa e risponde a una domanda sola:
la mia fermata è ancora servita?**

[![Licenza: MIT](https://img.shields.io/badge/licenza-MIT-blue.svg)](LICENSE)
[![Piattaforme](https://img.shields.io/badge/piattaforme-iOS%20%7C%20Android-lightgrey.svg)](#-scaricala)
[![Flutter](https://img.shields.io/badge/Flutter-Dart%203.12+-02569B.svg)](https://flutter.dev)
[![Test](https://img.shields.io/badge/test-374-brightgreen.svg)](#-sviluppo)
[![Dati: CC-BY](https://img.shields.io/badge/dati%20GTT-CC--BY-orange.svg)](https://www.gtt.to.it/cms/openday/open-data)

<img src="docs/img/linea-65.png" width="320"
     alt="Schermata della linea 65: la mappa con le due direzioni e le fermate,
          la posizione dell'utente, e l'esito «Adesso il percorso è regolare»">

</div>

---

## ✨ In breve

- 🔴 **Ti dice quali fermate saltano** — e dove andare al loro posto. È
  l'informazione che serve davvero, e che GTT non pubblica quasi mai.
- 🗺️ **Disegna la deviazione sulla mappa**, ricostruita dal testo
  dell'avviso: percorso normale, tratto deviato, fermate escluse.
- 🚌 **Guarda dove sono i mezzi adesso** e capisce se la deviazione è
  **già finita** — cosa che nessun'altra fonte sa dirti, perché GTT
  annuncia quando cominciano ma non quando smettono.
- 📅 **Separa ciò che è in corso da ciò che comincerà.** Il 19 % delle
  variazioni pubblicate non è ancora in vigore.
- ☁️ **Calcola una volta per tutti.** Un job su GitHub Actions legge gli
  avvisi ogni mezz'ora e pubblica i risultati: l'app li scarica in un
  secondo, senza chiavi né account. La tua posizione non lascia il
  dispositivo.
- 🤐 **Non inventa mai.** Se non riesce a ricostruire un percorso lo
  dichiara e ti mostra il testo originale di GTT.

## 📑 Indice

- [Il problema](#-il-problema)
- [Scaricala](#-scaricala)
- [Cosa fa](#-cosa-fa)
- [Come funziona](#-come-funziona)
- [Architettura](#-architettura)
- [Limiti noti](#-limiti-noti)
- [Sviluppo](#-sviluppo)
- [Da dove nasce](#-da-dove-nasce)
- [Licenze e attribuzioni](#-licenze-e-attribuzioni)

## 🎯 Il problema

L'avviso tipico di GTT si presenta così:

> *Linea 65 deviata in direzione corso Bolzano dalle 8:00 di lunedì 3 sino
> alle 18:00 di venerdì 7 agosto 2026. Da via Asinari di Bernezzo angolo
> corso Monte Grappa, per via Asinari di Bernezzo, piazza Chironi, via
> Medici, corso Lecce, via Lessona, segue percorso normale.*

È un elenco di vie. Ma chi aspetta il bus sta a una **fermata**, non su una
via, e per sapere se quella fermata è ancora servita dovrebbe ricostruire
il percorso a mente su una mappa che non ha davanti.

L'app fa quel lavoro: geocodifica i toponimi, calcola il percorso deviato
sulla rete stradale reale, lo confronta con il percorso ufficiale del GTFS
e determina quali fermate restano fuori.

> [!NOTE]
> **DeviaTo** — da «devia» e «To», che a Torino è come si scrive Torino.
> Progetto personale, non affiliato a GTT né approvato da GTT.

## 📲 Scaricala

DeviaTo è gratuita, senza pubblicità e senza account. **Arriva a breve su
App Store e Google Play**: i link compariranno qui e sul
[sito](https://deviato.it/).

Aggiungi le linee che usi con **+**: si cercano per numero o per via. Poi
apri una linea, tocca la tua fermata sulla mappa e salvala: la home ti dice
subito se è servita.

> [!IMPORTANT]
> **Privacy.** Nessun account, nessuna statistica d'uso, nessuna
> pubblicità. La posizione, se la attivi, serve solo a mostrarti sulla
> mappa: non viene salvata e non esce dal telefono. Il permesso si chiede
> quando tocchi il pulsante, non all'apertura.
> [Informativa completa](https://deviato.it/privacy.html).

## 🧭 Cosa fa

### 🔴 Fermate non servite e alternative

L'output più utile, e quello che GTT non fornisce quasi mai. Le fermate
chiuse sono riassunte **per tratti** e non avviso per avviso: quando GTT
pubblica un avviso per ogni fermata, sedici avvisi diventano «nove fermate
chiuse di fila, sali a Vibò o a Statuto Nord». Le alternative privilegiano
le fermate ancora servite dalla **stessa linea**, così da non richiedere un
cambio di mezzo, ed escludono quelle chiuse da qualunque altro avviso della
linea.

### 🌐 Mappa

Percorso normale di entrambe le direzioni con tonalità distinte, tratto
deviato in rosso, fermate toccabili per il nome, fermate saltate cerchiate,
e la tua posizione su richiesta. Si apre anche a tutto schermo, con una
direzione sola se le due si sovrappongono e un pannello che si trascina dal
basso: le fermate non servite per tratti, e quella che tocchi.

### 🚌 Osservazione dei mezzi in tempo reale

In tempo reale, finché non la interrompi, con i mezzi che si aggiornano
sulla mappa: ognuno ha una punta verso dove sta andando e il colore della
direzione che sta facendo. **Continua mentre guardi altre linee** — una alla volta, per
non raddoppiare le richieste al feed di GTT. Risponde a una domanda che nessun'altra fonte copre — **la
deviazione è già finita?** — e a una che il testo non sa rispondere bene:
**dove escono e dove rientrano davvero**. L'app lo dice con i nomi delle
fermate, e disegna il tratto realmente percorso. È l'unico dato del
sistema che non viene da un testo di GTT.

### 📅 In corso oppure in programma

Il 19 % delle variazioni pubblicate non è ancora in vigore. L'app le tiene
separate — *«comincia dopodomani»* — invece di segnalarle come attive.

### ⭐ Le tue fermate

Salvi la fermata che usi — linea, direzione, palo — e la home ti risponde
per quella: servita, non servita fino al…, e dove salire invece.

### 📄 Testo originale sempre visibile

In fondo a ogni scheda, così che il dato grezzo resti disponibile anche
quando il sistema sbaglia.

## 🧩 Come funziona

Il passaggio da testo a geometria è il punto in cui questi progetti si
fermano. Un geocoder interrogato liberamente con «via Roma» restituisce
decine di risultati in tutto il Piemonte, e la polilinea che ne esce non ha
alcun rapporto con il percorso reale della linea.

La soluzione è il **geocoding vincolato**: i toponimi si cercano
esclusivamente entro un chilometro dal percorso ufficiale di *quella* linea.
È questo vincolo — non il modello linguistico, non l'euristica — a rendere
affidabile l'intera catena.

### 📊 Le misure, sui dati reali di GTT

| Grandezza | Valore |
|---|---|
| Toponimi risolti correttamente | **150 / 150** entro 2 km |
| Distanza massima di un toponimo corretto dal percorso | **800 m** |
| Distanza minima di una via **estranea** alla linea | **1342 m** |
| Estrazione strutturata dal testo (LLM) | **34 / 34**, zero toponimi inventati |
| Copertura della tabella alias dei nomi di linea | **98,4 %** (63/64) |

Il margine fra 800 m e 1342 m è ciò che rende il filtro possibile: un
toponimo corretto e uno estraneo si separano nettamente, e il buffer di 1 km
cade in mezzo. Un buffer da 2 km lascia entrare rumore; uno da 500 m scarta
vie legittime, perché una deviazione per definizione si allontana.

### 🔗 La catena

```
avvisi GTT (due fonti)
        │
        ▼
  unione dei doppioni ......... 31 coppie su 189 avvisi
        │
        ▼
  estrazione LLM .............. testo → JSON (vie, direzione, tipo)
        │
        ▼
  geocoding VINCOLATO ......... toponimi → coordinate, entro 1 km dalla linea
        │
        ▼
  routing bus (Valhalla) ...... coordinate → polilinea sulla rete reale
        │
        ▼
  cinque validazioni .......... o si dichiara l'incertezza
        │
        ▼
  impatto sulle fermate ....... quali saltano, dove andare al loro posto
```

Il percorso ricostruito supera **cinque validazioni** prima di essere
disegnato. Se una fallisce, l'app dichiara l'incertezza e mostra il testo di
GTT. La regola è esplicita:

> ⚠️ **Meglio nessuna mappa che una mappa sbagliata.** Un falso positivo fa
> camminare l'utente ottocento metri inutilmente, e distrugge la fiducia
> nello strumento.

## 🧱 Architettura

Il sistema è organizzato attorno a un vincolo strutturale:

> **`app/lib/core/` è Dart puro.** Nessun `import 'package:flutter/…'`.

Da questo discende il resto: la logica si esegue e si testa in millisecondi
senza simulatore, si può invocare da riga di comando, e l'interfaccia è
sostituibile — con un'altra UI, con uno script, con un'implementazione
nativa — senza toccare il calcolo. Se un file di `core/` avesse bisogno di
Flutter, quel file sarebbe nel posto sbagliato.

Il calcolo gira in un posto solo: il job su GitHub. L'app legge i risultati.

```
avvisi GTT ─► job su GitHub Actions (ogni 30 min) ─► gh-pages: indice.json,
                                                     percorsi/, stato/
                                                          │
                                         app ◄────────────┘  (qualche KB)
```

```
app/tool/pubblica.dart          ← il giro del job: scarica, calcola, scrive
app/lib/
├── core/                       ← Dart puro, zero dipendenze da Flutter
│   ├── config.dart             ← tutte le soglie tarabili, in un posto solo
│   ├── models/                 ← tipi di dominio, senza comportamento di rete
│   ├── geo/
│   │   ├── projection.dart     ← gradi ↔ metri
│   │   ├── geometry.dart       ← distanze, proiezioni, Fréchet, densify
│   │   └── polyline.dart       ← codifica Google polyline
│   ├── gtfs/                   ← scarico e indicizzazione del GTFS statico
│   ├── sources/                ← una classe per fonte GTT, intercambiabili
│   ├── llm/                    ← client OpenAI-compatibile, con tetto di spesa
│   ├── io/formato_pubblicato.dart ← il formato dei file fra job e app
│   ├── publish/pubblicatore.dart  ← lo stato di tutte le linee, in un giro
│   └── pipeline/               ← un passaggio del calcolo per file
│       ├── notice_merge.dart   ← le due fonti → un avviso solo
│       ├── line_resolver.dart  ← «55» → 55U (tabella alias)
│       ├── extractor.dart      ← testo → JSON strutturato (LLM)
│       ├── geocoder.dart       ← toponimo → coordinate, VINCOLATO
│       ├── route_builder.dart  ← vie → polilinea (Valhalla) + validazioni
│       ├── rejoin_inference.dart ← dove rientra, quando GTT non lo dice
│       ├── stop_impact.dart    ← quali fermate saltano, e le alternative
│       ├── closure_summary.dart ← le fermate chiuse lette per tratti
│       └── vehicle_watch.dart  ← osservazione dei mezzi in tempo reale
├── data/                       ← dati pubblicati con copia locale, preferenze, posizione
└── ui/                         ← schermate e mappa
```

**Perché è diviso così.** Ogni file di `pipeline/` è un passaggio del
ragionamento ed è sostituibile isolatamente: se Photon cessa il servizio si
riscrive `geocoder.dart`; se Valhalla pubblico sparisce, `route_builder.dart`;
per cambiare modello linguistico, `extractor.dart`. Nessun altro file se ne
accorge.

`config.dart` esiste perché quasi tutte le soglie vanno tarate sul campo. I
valori marcati `MISURATO` vengono da rilevazioni reali, e in **sette casi
contraddicono** le stime del progetto originale — fra cui la soglia di
fuori-rotta (50 m misurati contro 80 stimati) e il buffer del geocoding
(1 km contro 2).

### 🔌 Fonti dati

| Fonte | Uso | Nota |
|---|---|---|
| GTFS statico GTT | percorsi, fermate, orari | rigenerato ogni giorno alle 04:00, CC-BY |
| `alerts.aspx` (GTFS-RT) | avvisi | porta il `route_id` canonico nel 96,7 % dei casi |
| `/cms/variazioni` (HTML) | avvisi | unica fonte con le **date d'inizio reali**; **spenta** nel job finché GTT non ne autorizza l'uso |
| `vehicle_position.aspx` | posizioni dei mezzi | si spegne di notte, il servizio no |
| [Photon](https://photon.komoot.io/) | geocoding | nessuna chiave richiesta |
| [Valhalla](https://valhalla1.openstreetmap.de/) (FOSSGIS) | routing `costing: bus` | polilinee a precisione 6 |
| [Overpass](https://overpass-api.de/) (FOSSGIS, riserva VK Maps) | forma intera delle vie degli avvisi, per gli incroci (algoritmo 2) | nessuna chiave; può essere lento |
| [OpenRouter](https://openrouter.ai) | estrazione dal testo | chiave del job, segreto di GitHub Actions |

L'OTP di GTT — che il progetto originale indicava come fonte primaria — è
stato scartato dopo verifica: espone un build più vecchio, i cui `trip_id`
non esistono nel feed corrente, e a cui mancano sette linee.

## 🚧 Limiti noti

### 🔕 Non ti avvisa da sola: devi aprirla tu

Il job su GitHub calcola ogni mezz'ora, ma l'app non manda notifiche:
i dati si vedono aprendola. Le notifiche sono il passo naturale successivo,
ora che il calcolo non sta più sul telefono.

### 📏 Le distanze a piedi sono in linea d'aria

Quando una fermata salta, l'app ti propone quelle vicine e ti dice quanto
distano — ma in linea retta, come vola un uccello, non come cammini tu. A
Torino un fiume, una ferrovia o un muro possono raddoppiare il percorso
reale. L'app scrive «in linea d'aria» ogni volta, così il numero non si
scambia per una distanza a piedi.

### 🔀 Usa il percorso principale della linea

La stessa linea ha spesso più percorsi leggermente diversi: alcune corse
si fermano prima, altre passano da una via invece che da un'altra. L'app
usa quello più frequente. Se una deviazione riguardasse **soltanto** una
di quelle corse minori, l'app la calcolerebbe come se valesse per tutte.

### 📆 Le date di inizio non sono sempre quelle vere

GTT pubblica gli avvisi in due posti, e nel feed dei dati aperti la data di
inizio non è quella vera: è l'ora in cui l'avviso è stato scritto
(verificato su 161 avvisi su 161). Le date vere stanno nella tabella del
sito di GTT, che però non è pubblicata come dato aperto: il job non la usa
finché GTT non lo autorizza. Nel frattempo una variazione annunciata in
anticipo può comparire come già in corso.

## 🧪 Sviluppo

Serve [Flutter](https://docs.flutter.dev/get-started/install) con Dart ≥ 3.12.
Il codice è lo stesso per iOS e Android: `lib/core/` è Dart puro e non sa
su cosa sta girando.

```bash
cd app && flutter test      # 374 test
cd app && flutter analyze
cd app && flutter run       # legge i dati pubblicati, nessuna chiave
```

Per provare l'app contro un giro del job lanciato sul computer:

```bash
cd app && dart run tool/pubblica.dart --uscita ../sito/v1 --gtfs ../.gtfs
python3 -m http.server 8765 --directory ../sito &
flutter run --dart-define=DATI_URL=http://localhost:8765/v1/
```

### Il job su GitHub

[`.github/workflows/pubblica.yml`](.github/workflows/pubblica.yml) esegue
[`app/tool/pubblica.dart`](app/tool/pubblica.dart) ogni mezz'ora di giorno,
ogni ora la sera e una volta di notte, e pubblica il risultato sul ramo
`gh-pages`. A lanciarlo è un servizio esterno (cron-job.org) che chiama
`workflow_dispatch`: gli orari programmati di GitHub saltano troppi giri, e
restano solo come riserva. Su un fork va configurato una volta:

1. **Settings › Pages**: «Deploy from a branch», ramo `gh-pages`, cartella
   `/`. Il ramo lo crea il primo giro.
2. **Settings › Secrets and variables › Actions**: il segreto
   `OPENROUTER_API_KEY`. Senza, si pubblicano solo le fermate sospese che GTT
   scrive col numero, e gli altri avvisi restano da leggere.

Le richieste al modello dipendono dagli avvisi **nuovi** di GTT — una
ventina al giorno, misurato il 26/09/2026 — e non da quante persone usano
l'app: un avviso già letto e non cambiato non si rilegge.

I test sulle fonti girano **offline su dati reali**: il feed protobuf e la
pagina HTML di GTT del 31 luglio 2026 stanno in `app/test/fixtures/`. I test
sul GTFS si saltano da soli se i file non ci sono.

Strumenti di misura, che interrogano i servizi veri:

```bash
cd app && dart run tool/check_pipeline_live.dart     # catena completa
cd app && dart run tool/check_merge_offline.dart     # unione delle fonti
```

> [!TIP]
> **Prima di modificare qualcosa, leggi [`CLAUDE.md`](CLAUDE.md).** Contiene
> ciò che non sta nel codice: le misure e il metodo con cui sono state
> ottenute, il ragionamento dietro le scelte, i sette punti in cui la
> specifica originale è stata smentita dai dati, e le trappole già pagate —
> per esempio il confronto per sottostringhe che faceva scattare «lavori
> **strada**li» sul capolinea «**STRADA** del Drosso», mandando l'avviso
> sulla direzione sbagliata.

Due criteri per i contributi:

1. **Le soglie si tarano misurando.** Gli script in `scripts/` e `app/tool/`
   esistono per questo. Un numero rimesso in discussione va rimisurato, non
   stimato.
2. **Dichiarare l'incertezza è un requisito, non un ripiego.** «Non lo so» è
   una risposta valida e va comunicata come tale.

**Altra documentazione:** [`app/ARCHITETTURA.md`](app/ARCHITETTURA.md) per lo
stato dei moduli · [`docs/FASE-0-RISULTATI.md`](docs/FASE-0-RISULTATI.md) per
le misure sulle fonti · [`docs/`](docs/) per la specifica originale, che va
letta sapendo che sette dei suoi assunti si sono rivelati falsi.

## 🤝 Da dove nasce

L'idea è mia, e nasce da una cosa che mi capitava di continuo: gli avvisi
di GTT ci sono, i dati aperti pure, le posizioni dei mezzi anche — ma stanno
in posti diversi e in formati diversi, e nessuno li mette insieme per
rispondere alla domanda che uno si fa davvero alla fermata. Volevo
aggregare quelle fonti e ricavarne delle funzioni utili.

Il passaggio da quell'idea a un'app che funziona l'ho fatto **insieme a
Claude** (Anthropic): l'architettura, il codice, le misure sulle fonti e le
verifiche sul campo sono venute da quel lavoro a quattro mani. Le decisioni
su cosa dovesse fare e su come dovesse comportarsi sono rimaste mie; il
mestiere per realizzarle e il rigore nel misurare invece di supporre li ha
messi lui.

Buona parte di quello che c'è scritto in [`CLAUDE.md`](CLAUDE.md) — le
misure che smentiscono le stime, le trappole trovate provando l'app invece
che leggendo il codice — è il residuo di quel processo, ed è la parte del
progetto che credo valga di più.

## 📜 Licenze e attribuzioni

| | |
|---|---|
| 🚌 Dati di trasporto | **GTT S.p.A. – Gruppo Torinese Trasporti**, [dati aperti](https://www.gtt.to.it/gtt_gtfs_license.html): CC BY 4.0 sul [portale del Comune](https://aperto.comune.torino.it/dataset/feed-gtfs-trasporti-gtt), **solo uso non commerciale** secondo la licenza di GTT. L'attribuzione è obbligatoria, e l'app non ha pubblicità né acquisti |
| 🗺️ Cartografia | **OpenStreetMap**, ODbL; immagini della cartina di **[CARTO](https://carto.com/attribution/)** (Positron e Dark Matter) |
| 🧭 Routing | **Valhalla** ospitato da [FOSSGIS](https://valhalla1.openstreetmap.de/) |
| 📍 Geocoding | **[Photon](https://photon.komoot.io/)** di Komoot |
| 🛣️ Vie per nome | **Overpass**, istanze pubbliche di [FOSSGIS](https://overpass-api.de/) e VK Maps, sui dati OpenStreetMap |

Photon, Valhalla e Overpass sono servizi offerti gratuitamente alla comunità. Li
chiama solo il job, per gli avvisi nuovi: qualche decina di richieste al
giorno, con pause fra le chiamate, uno User-Agent riconoscibile e
l'intestazione `X-Client-Id` che FOSSGIS chiede alle app pubblicate.

DeviaTo non è un'app di GTT e non è collegata a GTT.

Il codice è distribuito con licenza **MIT** — vedi [`LICENSE`](LICENSE). La
licenza riguarda il codice, non i dati.
