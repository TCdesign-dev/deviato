# Per ogni tratto fuori linea di un mezzo: che corsa faceva prima di uscire
# e quale dopo essere rientrato. Serve a distinguere una deviazione (stessa
# corsa prima e dopo) da un mezzo che va o viene dal deposito.
# Uso: python3 scripts/tratti_fuori.py <schema ora> linea,...
import json, glob, math, os, sys, urllib.request
BASE = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'app', 'build', 'banco', '')
from collections import defaultdict, Counter
K = math.cos(math.radians(45.07))
def m(p): return (p[0]*111320.0, p[1]*111320.0*K)
def dec(t, prec=6):
    out, i, lat, lon, f = [], 0, 0, 0, 10**prec
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
        out.append((lat/f, lon/f))
    return out
def dseg(p, a, b):
    dx, dy = b[0]-a[0], b[1]-a[1]; l2 = dx*dx+dy*dy
    t = 0 if l2 == 0 else max(0, min(1, ((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l2))
    return math.hypot(p[0]-a[0]-t*dx, p[1]-a[1]-t*dy)
def dist(p, L): return min(dseg(p, L[i], L[i+1]) for i in range(len(L)-1))
def tratti(linea, schema):
    pj = json.load(urllib.request.urlopen('https://deviato.it/v1/percorsi/%s.json' % linea, timeout=60))
    normali = [[m(q) for q in dec(pr['punti'])] for pr in pj['percorsi']]
    tr = defaultdict(list)
    for f in sorted(glob.glob(BASE + 'mezzi/%s-%s*.json' % (linea, schema))):
        for mz in json.load(open(f))['mezzi']: tr[mz['id']] += mz['punti']
    out = []
    for v, ps in tr.items():
        ps.sort(key=lambda x: x[2])
        fu = [min(dist(m(p), n) for n in normali) > 40 for p in ps]
        i = 0
        while i < len(ps):
            if not fu[i]: i += 1; continue
            j = i
            while j < len(ps) and fu[j]: j += 1
            # la corsa prima: l'ultima dichiarata sulla linea prima di uscire
            prima = next((ps[k][3] for k in range(i-1, -1, -1) if not fu[k] and ps[k][3]), None)
            dopo = next((ps[k][3] for k in range(j, len(ps)) if not fu[k] and ps[k][3]), None)
            esce = i > 0; rientra = j < len(ps)
            mx = max(min(dist(m(p), n) for n in normali) for p in ps[i:j])
            if esce and rientra and prima and prima == dopo: tipo = 'stessa corsa prima e dopo'
            elif esce and rientra: tipo = 'esce e rientra, corsa diversa o assente'
            elif esce: tipo = 'esce e non rientra'
            elif rientra: tipo = 'compare fuori e poi entra'
            else: tipo = 'sempre fuori'
            out.append((v, ps[i][2][11:16], ps[j-1][2][11:16], j-i, int(mx), tipo))
            i = j
    return out
if __name__ == '__main__':
    for linea in sys.argv[2].split(','):
        t = tratti(linea, sys.argv[1])
        print('\n' + linea, dict(Counter(x[5] for x in t)))
        for x in t:
            if x[3] >= 2: print('   %s %s–%s %3d pos, max %4d m · %s' % x)
