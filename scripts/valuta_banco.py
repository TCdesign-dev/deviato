# Misura i rossi dei due algoritmi contro le tracce dei mezzi salvate dal banco.
# Regola (Tommaso, 30/09): un tratto fuori percorso conta solo se lo fanno
# almeno 2 mezzi distinti. Uso: python3 scripts/valuta_banco.py [prefisso data/ora] [linee,...]
import json, glob, math, os, sys, urllib.request
from collections import defaultdict
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'app', 'build', 'banco', '')
GIORNO = sys.argv[1] if len(sys.argv) > 1 else ''
SOLO = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None
VICINO = 40
K = math.cos(math.radians(45.07))
def m(p): return (p[0] * 111320.0, p[1] * 111320.0 * K)
def decodifica(t, prec=6):
    out, i, lat, lon, f = [], 0, 0, 0, 10 ** prec
    while i < len(t):
        for k in (0, 1):
            r, sh = 0, 0
            while True:
                b = ord(t[i]) - 63; i += 1
                r |= (b & 0x1f) << sh; sh += 5
                if b < 0x20: break
            v = ~(r >> 1) if r & 1 else r >> 1
            if k == 0: lat += v
            else: lon += v
        out.append((lat / f, lon / f))
    return out
def dseg(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]; l2 = dx*dx+dy*dy
    t = 0 if l2 == 0 else max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l2))
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)
def dist(p, L):
    if len(L) == 1: return math.hypot(p[0]-L[0][0], p[1]-L[0][1])
    return min(dseg(p, L[i], L[i+1]) for i in range(len(L)-1)) if L else 1e9
def dens(L, step=10):
    out = []
    for i in range(len(L)-1):
        a, b = L[i], L[i+1]; d = math.hypot(b[0]-a[0], b[1]-a[1]); n = max(1, int(d // step))
        for k in range(n): out.append((a[0]+(b[0]-a[0])*k/n, a[1]+(b[1]-a[1])*k/n))
    if L: out.append(L[-1])
    return out
d = json.load(open(BASE + 'confronti.json'))
print('confronti del', d['calcolato'])
righe = defaultdict(list)
for r in d['confronti']: righe[r['id']].append(r)
for linea, rs in sorted(righe.items()):
    if SOLO and linea not in SOLO: continue
    grezze = defaultdict(list)   # mezzo -> [lat, lon, ora, corsa, rotta]
    for f in sorted(glob.glob(BASE + 'mezzi/%s-%s*.json' % (linea, GIORNO))):
        for mz in json.load(open(f))['mezzi']:
            grezze[mz['id']] += mz['punti']
    for ps in grezze.values(): ps.sort(key=lambda x: x[2] if len(x) > 2 else '')
    tracce = {v: [m(x) for x in ps] for v, ps in grezze.items()}   # mezzo -> punti in ordine
    punti = [(v, p) for v, ps in tracce.items() for p in ps]
    if len(punti) < 50: continue
    try:
        pj = json.load(urllib.request.urlopen('https://deviato.it/v1/percorsi/%s.json' % linea, timeout=60))
        normali = [[m(q) for q in decodifica(pr['punti'])] for pr in pj['percorsi']]
    except Exception:
        normali = [[m(p) for p in r['normale']] for r in rs]
    def sulla(p): return any(dist(p, n) <= VICINO for n in normali)
    # Fuori servizio (01/10): un tratto fuori linea conta solo se il mezzo
    # rientra con la stessa corsa che faceva prima di uscire. Chi esce e non
    # rientra va al deposito, chi compare gia' fuori ne arriva.
    escluso = {}
    for v, ps in tracce.items():
        fu = [not sulla(p) for p in ps]; g = grezze[v]; e = [False] * len(ps); i = 0
        corsa = lambda k: g[k][3] if len(g[k]) > 3 else None
        while i < len(ps):
            if not fu[i]: i += 1; continue
            j = i
            while j < len(ps) and fu[j]: j += 1
            # la corsa piu' vicina dichiarata sulla linea: qualche posizione
            # in servizio arriva senza corsa anche li'
            prima = next((corsa(k) for k in range(i-1, -1, -1) if not fu[k] and corsa(k)), None)
            dopo = next((corsa(k) for k in range(j, len(ps)) if not fu[k] and corsa(k)), None)
            if not prima or prima != dopo:
                for k in range(i, j): e[k] = True
            i = j
        escluso[v] = e
    servizio = {v: [p for p, x in zip(ps, escluso[v]) if not x] for v, ps in tracce.items()}
    def passa(v, q): return len(servizio[v]) > 1 and dist(q, servizio[v]) <= VICINO
    fuori = [(v, p) for v, p in punti if not sulla(p)]
    fuori_servizio = sum(sum(e) for e in escluso.values())
    def verso_di(v, i):
        ps = tracce[v]; a, b = ps[max(0, i-1)], ps[min(len(ps)-1, i+1)]
        l = math.hypot(b[0]-a[0], b[1]-a[1])
        return (0, 0) if l < 1 else ((b[0]-a[0])/l, (b[1]-a[1])/l)
    condivisi = [(p, verso_di(v, i)) for v, ps in tracce.items() for i, p in enumerate(ps)
                 if not sulla(p) and not escluso[v][i] and any(w != v and passa(w, p) for w in tracce)]
    def sul_rosso_nel_verso(p, t, R):
        for i in range(len(R)-1):
            a, b = R[i], R[i+1]
            if dseg(p, a, b) > VICINO: continue
            l = math.hypot(b[0]-a[0], b[1]-a[1])
            if t == (0, 0) or (l > 0 and ((b[0]-a[0])*t[0] + (b[1]-a[1])*t[1]) / l > 0.5): return True
        return False
    mezzi_fuori = {v for v, p in fuori}
    print('\n%s: %d mezzi, %d posizioni, %d fuori dalla linea (%d mezzi; %d fuori servizio), %d in servizio dove e\' passato anche un altro mezzo' % (
        linea, len(tracce), len(punti), len(fuori), len(mezzi_fuori), fuori_servizio, len(condivisi)))
    for alg in ('a1', 'a2'):
        rossi = [[m(p) for p in r[alg]['geometria']] for r in rs if len(r[alg]['geometria']) > 1]
        spieg = sum(1 for p, t in condivisi if any(sul_rosso_nel_verso(p, t, R) for R in rossi))
        rfuori = [q for R in rossi for q in dens(R) if not sulla(q)]
        perc = sum(1 for q in rfuori if sum(1 for v in tracce if passa(v, q)) >= 2)
        esiti = '; '.join('dir%s %s %dm ns%d%s' % (r['dir'], r[alg]['affidabilita'][:5], r[alg]['metri'], len(r[alg]['nonServite']),
                          ' ORARI' if 'già negli orari' in (r[alg].get('perche') or '') else '') for r in rs)
        print('  %s: fuori spiegati %s, rosso fuori linea %d m percorso da 2+ mezzi %s | %s' % (alg,
              '%.0f%%' % (100*spieg/len(condivisi)) if condivisi else '-', len(rfuori)*10,
              '%.0f%%' % (100*perc/len(rfuori)) if rfuori else '-', esiti))
