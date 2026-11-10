#!/usr/bin/env python3
"""Dalle vie di OpenStreetMap (GeoJSON a righe, da `osmium export`) al file
compatto che il job legge al posto di Overpass.

    python3 scripts/vie_da_osm.py vie.geojsonl vie.json.gz 2026-11-08

Tiene le strade con un nome (`highway` + `name`) e i binari del tram
(`railway=tram`), come le due richieste che si facevano a Overpass. Ogni
via e' [nome, latMin, lonMin, latMax, lonMax, polilinea]: il riquadro serve
a scegliere le vie di una zona senza decodificarle tutte. La polilinea e'
quella di Google a SETTE decimali, come le coordinate di OpenStreetMap: due
vie che si toccano hanno un nodo in comune, e il calcolo del percorso le
unisce proprio perche' quel punto ha le stesse coordinate.

Solo libreria standard: gira nel job senza installare niente.
"""
import gzip
import json
import sys


def polilinea(punti, precisione=7):
    """`punti` e' [(lat, lon), ...]."""
    f = 10 ** precisione
    out = []
    plat = plon = 0
    for lat, lon in punti:
        ilat, ilon = round(lat * f), round(lon * f)
        for d in (ilat - plat, ilon - plon):
            v = ~(d << 1) if d < 0 else d << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        plat, plon = ilat, ilon
    return ''.join(out)


def voce(punti):
    lat = [p[0] for p in punti]
    lon = [p[1] for p in punti]
    return [round(min(lat), 5), round(min(lon), 5),
            round(max(lat), 5), round(max(lon), 5), polilinea(punti)]


def main(entrata, uscita, data):
    vie, binari = [], []
    with open(entrata, encoding='utf-8') as f:
        for riga in f:
            riga = riga.strip('\x1e\n\r ')
            if not riga:
                continue
            g = json.loads(riga)
            geom = g.get('geometry') or {}
            if geom.get('type') != 'LineString':
                continue
            # GeoJSON scrive lon, lat.
            punti = [(c[1], c[0]) for c in geom['coordinates']]
            if len(punti) < 2:
                continue
            p = g.get('properties') or {}
            if p.get('highway') and p.get('name'):
                vie.append([p['name']] + voce(punti))
            if p.get('railway') == 'tram':
                binari.append(voce(punti))
    with gzip.open(uscita, 'wt', encoding='utf-8') as f:
        json.dump({'versione': 1, 'data': data, 'vie': vie, 'binari': binari},
                  f, ensure_ascii=False, separators=(',', ':'))
    print(f'{len(vie)} vie, {len(binari)} tratti di binario')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else '')
