# Google Play — cosa fare e cosa incollare

Come [TESTFLIGHT.md](TESTFLIGHT.md), ma per la Play Console. I testi sono
pronti da copiare; le voci della Console possono avere nomi leggermente
diversi. Le risposte sono vere per l'app di oggi: se un giorno arrivano
statistiche, account o pubblicità, vanno riviste (sicurezza dei dati
per prima).

---

## 1. Crea app (fatto il 30/09/2026)

- Nome app: `DeviaTo` — senza «GTT»: Google non ama i nomi che sembrano
  di un altro marchio, e le parole per la ricerca stanno nella descrizione.
- Nome pacchetto: `dev.tcdesign.deviato` (quello dell'AAB, per sempre).
- Lingua predefinita: Italiano – it-IT.
- App, **senza costi** (dopo la pubblicazione non si torna indietro; la
  licenza di GTT vieta comunque di farla pagare).

## 2. Contenuti dell'app (le voci della dashboard)

| Voce | Risposta |
|---|---|
| **Norme sulla privacy** | `https://deviato.it/privacy.html` |
| **Accesso alle app** | Tutte le funzionalità sono disponibili senza restrizioni di accesso (niente account). |
| **Annunci** | No, l'app non contiene annunci. |
| **ID pubblicità** | No: nessuna libreria lo usa, e il permesso `AD_ID` non c'è nel manifest. |
| **Pubblico di destinazione** | 13–15, 16–17, 18 e oltre. **Non** sotto i 13: farebbe scattare le norme per le famiglie, che per un'app di orari non servono. «Potrebbe attrarre involontariamente i bambini?» No. |
| **App di notizie** | No. |
| **App governative** | No (non è di GTT né del Comune). |
| **Funzionalità finanziarie** | Nessuna. |
| **App per la salute** | No. |

**Classificazione dei contenuti** (questionario IARC): email
`devia.to@icloud.com`, categoria «Utilità, produttività, comunicazione o
altro». Tutte le risposte sono **no**: niente violenza, sesso, linguaggio,
droghe, gioco d'azzardo; gli utenti non comunicano fra loro, non si
scambiano contenuti, non condividono la posizione con altri; niente
acquisti. Esito atteso: PEGI 3.

Se da qualche parte chiede di **IA generativa**: nell'app non ce n'è
(niente chat, niente testi o immagini generati su richiesta). Un modello
linguistico legge gli avvisi di GTT nel job su GitHub e ne estrae vie e
fermate; l'app mostra il risultato e sempre il testo originale di GTT.

**Sicurezza dei dati**: «La tua app raccoglie o condivide uno dei tipi
di dati utente richiesti?» → **No**. Il perché, se serve spiegarlo:

- Linee e fermate salvate restano sul telefono.
- La posizione è usata solo sul telefono per il punto blu: non viene
  salvata né inviata (per Google, un dato che non lascia il telefono non
  è «raccolto»).
- Le richieste di rete scaricano dati pubblici (GitHub Pages, CARTO per
  la mappa, GTT per i mezzi) e non portano dati dell'utente. Niente
  statistiche, niente librerie di terze parti che raccolgono dati.

È la stessa cosa che dice l'informativa sul sito.

**Stato di commerciante (DSA, Unione Europea)**: la Console chiede se
pubblichi come commerciante. Per un'app gratuita, senza entrate, fatta da
un privato, la risposta di solito è **non commerciante**: la decisione è
di Tommaso.

## 3. Scheda dello Store principale

**Nome**: `DeviaTo`

**Descrizione breve** (massimo 80 caratteri):

```text
Bus e tram deviati a Torino: scopri se la tua fermata è ancora servita
```

**Descrizione completa** (massimo 4000):

```text
Bus o tram deviato? DeviaTo ti dice subito se la tua fermata a Torino è ancora servita e, se non lo è, dove salire invece.

Gli avvisi di deviazione di GTT sono elenchi di vie e incroci, difficili da capire al volo mentre aspetti. DeviaTo li legge per te e li trasforma in una risposta chiara, sulla mappa.

Cosa puoi fare
• Aggiungere le linee che usi: appena apri l'app vedi se il percorso è regolare, se la linea è deviata o se qualche fermata non è servita.
• Salvare le tue fermate: l'app risponde per quelle, nella direzione che prendi.
• Vedere sulla mappa il percorso deviato, le fermate saltate e le più vicine dove salire.
• Seguire i mezzi in tempo reale, per vedere dove passano davvero.
• Leggere sempre l'avviso originale di GTT.
• Consultare gli ultimi dati anche senza connessione.

Gratis, senza pubblicità, senza account
DeviaTo non ha statistiche d'uso né tracciamento. Linee e fermate salvate restano sul telefono; la posizione, se la attivi, serve solo a mostrarti sulla mappa e non lascia il telefono.

Da sapere
I percorsi deviati sono ricostruiti in automatico dal testo degli avvisi e possono contenere errori: in caso di dubbio fa fede l'avviso originale di GTT, che l'app mostra sempre.

DeviaTo non è un'app di GTT e non è collegata a GTT. Usa i dati aperti di GTT S.p.A. (orari, avvisi e posizioni dei mezzi) secondo la loro licenza. Mappe © contributori di OpenStreetMap · © CARTO.

Hai trovato un errore o hai un suggerimento? Scrivi a devia.to@icloud.com
```

**Grafica**

- **Icona** 512 × 512: [`play/icona-512.png`](play/icona-512.png) (la
  stessa dell'app; gli angoli li arrotonda Google).
- **Grafica in primo piano** 1024 × 500:
  [`play/grafica-1024x500.png`](play/grafica-1024x500.png) — logo, la
  domanda del sito e il cartello giallo con la 91.
- **Screenshot del telefono** 1080 × 1920 (9:16), nell'ordine:
  1. [`screenshot-1-home.png`](play/screenshot-1-home.png) — «La tua fermata è ancora servita?»
  2. [`screenshot-2-linea.png`](play/screenshot-2-linea.png) — «Quali fermate saltano»
  3. [`screenshot-3-mappa.png`](play/screenshot-3-mappa.png) — «Il giro deviato sulla mappa»
  4. [`screenshot-4-fermata.png`](play/screenshot-4-fermata.png) — «Tocca la tua fermata»
  5. [`screenshot-5-avviso.png`](play/screenshot-5-avviso.png) — «Sempre l'avviso originale»

  Fatti il 30/09 sera sul telefono virtuale Android (build 14, linea 91
  deviata) e montati nello stile del sito: fondo grafite, titoli in
  Boldonse, la cornice del telefono della pagina «Come si usa». Google
  vuole al massimo il doppio fra lato lungo e corto: gli screenshot
  grezzi (1080 × 2400) non passano, per questo la cornice.

**Categoria**: App › Mappe e navigazione.

**Contatti**: email `devia.to@icloud.com`, sito `https://deviato.it`,
telefono no.

## 4. Test

**Test interno** (subito, fino a 100 persone, niente revisione lunga):

1. Test › Test interno › Crea release.
2. Alla prima release Google propone la **firma delle app di Google
   Play**: accettare. La chiave `~/deviato-upload.jks` resta quella di
   caricamento; la chiave di firma la tiene Google.
3. Carica `app/build/app/outputs/bundle/release/app-release.aab`
   (versionCode 14 il 30/09). Nome release: `1.0.0 (14)`.
4. Note di rilascio:

   ```text
   <it-IT>
   Prima versione di prova. Se una fermata risulta non servita ma il bus passa (o il contrario), scrivici a devia.to@icloud.com.
   </it-IT>
   ```

5. Tester: una lista di email (account Google). Ognuno accetta dal link
   di adesione e poi installa dal Play Store.

**Test chiuso, prima della produzione.** Per gli account personali nuovi
Google chiedeva almeno **12 tester iscritti per 14 giorni di fila** prima
di poter chiedere l'accesso alla produzione: la dashboard dice se vale
ancora. I tester devono accettare l'invito e tenere l'app installata;
conviene averne qualcuno in più di 12. Alla fine Google fa qualche
domanda sul test (chi erano i tester, cosa è cambiato con il loro
riscontro).

**Paesi**: Italia (è un'app per Torino).
