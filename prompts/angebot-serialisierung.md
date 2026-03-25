# Vorlage: Angebote als Text für Vector Embeddings serialisieren

Jedes Angebot wird als natürlichsprachlicher Text gespeichert – **NICHT als JSON** –
da Embedding-Modelle (insbesondere `text-embedding-3-small`) auf natürliche Sprache
optimiert sind und bei JSON-Syntax schlechtere Semantic-Ähnlichkeitswerte liefern.

## Grundprinzipien

1. **Natürliche Sprache bevorzugen**: Fließtext statt Schlüssel-Wert-Paare
2. **Kategorien immer ausschreiben**: Lesbarkeit vor Kürze
3. **Mengen immer angeben**: `5x Dell OptiPlex` statt nur `Dell OptiPlex`
4. **Leere Kategorien weglassen**: Nicht `Kabel & Zubehör: (keine)` schreiben
5. **Gesamtwert und Status immer am Ende**: Normalisierte Position für Filterbarkeit

## Template

```
{angebot_typ} Angebot{[ für {branche}]}, {anzahl} Positionen:
Hardware: {menge}x {bezeichnung}[, {menge}x {bezeichnung}...]
Peripherie: {menge}x {bezeichnung}[, ...]
Kabel & Zubehör: {menge}x {bezeichnung}[, ...]
Lizenzen: {menge}x {bezeichnung}[, ...]
Service: {menge}x {bezeichnung}[, ...]
Netzwerk: {menge}x {bezeichnung}[, ...]
Gesamtwert: {summe}€ netto, Status: {status}
```

_Kategorien in eckigen Klammern sind optional._

## Reihenfolge der Kategorien

Immer in dieser festen Reihenfolge ausgeben (hilft dem Embedding-Modell,
ähnliche Angebote strukturell zu vergleichen):

1. Hardware
2. Peripherie
3. Kabel & Zubehör
4. Lizenzen
5. Service
6. Netzwerk
7. (sonstige Kategorien alphabetisch am Ende)

## Beispiel: PC-Arbeitsplatz Angebot

```
PC-Arbeitsplatz Angebot für Kanzlei, 11 Positionen:
Hardware: 5x Dell OptiPlex 7020 Desktop PC (Intel Core i5-13500, 16GB RAM, 512GB NVMe SSD, Windows 11 Pro)
Peripherie: 5x Dell P2425H 24" FHD IPS Monitor, 5x Logitech MK270 Tastatur+Maus Set (kabellos), 5x Dell WD19S 180W Docking Station
Kabel & Zubehör: 5x HDMI-Kabel 2m (Monitor-Anschluss), 5x Cat6A Patchkabel 3m (Netzwerk), 5x Kaltgerätekabel 1,5m
Lizenzen: 5x Microsoft 365 Business Standard (Jahresabonnement), 5x Windows 11 Pro OEM
Service: 1x Einrichtungspauschale (5 Arbeitsplätze inkl. Domain-Join und Software-Setup), 1x 3 Jahre Vor-Ort-Service Next Business Day
Gesamtwert: 12450€ netto, Status: gewonnen
```

## Beispiel: Server Angebot

```
Server Angebot für Mittelständler, 8 Positionen:
Hardware: 1x HPE ProLiant DL380 Gen11 (2x Intel Xeon Silver 4416+, 256GB RAM, 8x 960GB SAS SSD), 1x HPE MSA 2060 SAN Speichersystem (12x 4TB SAS)
Netzwerk: 1x HPE Aruba 2930F 24G PoE+ Switch, 2x HPE SFP+ 10GbE Transceiver
Lizenzen: 1x Microsoft Windows Server 2022 Standard (16 Core), 1x Microsoft SQL Server 2022 Standard
Service: 1x Server-Installation und Grundkonfiguration, 1x 5 Jahre Hardware Support (HPE Care Pack)
Gesamtwert: 28900€ netto, Status: offen
```

## Beispiel: Netzwerk Angebot

```
Netzwerk Angebot für Handwerksbetrieb, 6 Positionen:
Netzwerk: 1x Fortinet FortiGate 60F Firewall (inkl. UTM 1 Jahr), 2x Cisco Catalyst 1000-24T-4G Switch, 3x Ubiquiti UniFi U6 Pro Access Point
Hardware: 1x Ubiquiti UniFi Dream Machine Pro SE (Controller)
Kabel & Zubehör: 20x Cat6A Verlegekabel 10m (Netzwerk-Infrastruktur), 1x 19" Patchpanel 24-Port
Service: 1x Netzwerk-Planung und Installation (Pauschal)
Gesamtwert: 5840€ netto, Status: gewonnen
```

## Häufige Fehler vermeiden

| Falsch | Richtig |
|--------|---------|
| `"ItemDescription": "Dell OptiPlex"` | `5x Dell OptiPlex 7020` |
| `PC-Arbeitsplatz, 5 Positionen` | `PC-Arbeitsplatz Angebot für Kanzlei, 5 Positionen:` |
| `Lizenzen: Microsoft 365` | `Lizenzen: 5x Microsoft 365 Business Standard (Jahresabonnement)` |
| `Gesamtwert: 12450` | `Gesamtwert: 12450€ netto, Status: gewonnen` |
| Alle Positionen in einer Zeile | Jede Kategorie auf eigener Zeile |

## n8n Code-Node für Serialisierung

```javascript
function serialisiereAngebot(angebot) {
  const gruppen = {};
  for (const pos of (angebot.positionen || [])) {
    const kat = pos.kategorie || 'Sonstige';
    if (!gruppen[kat]) gruppen[kat] = [];
    const preisText = pos.preis ? ` (${pos.preis}€)` : '';
    gruppen[kat].push(`${pos.menge}x ${pos.bezeichnung}${preisText}`);
  }

  const katReihenfolge = [
    'Hardware', 'Peripherie', 'Kabel & Zubehör',
    'Lizenzen', 'Service', 'Netzwerk'
  ];

  let text = `${angebot.angebot_typ} Angebot`;
  if (angebot.branche) text += ` für ${angebot.branche}`;
  text += `, ${(angebot.positionen || []).length} Positionen:\n`;

  for (const kat of katReihenfolge) {
    if (gruppen[kat]?.length) {
      text += `${kat}: ${gruppen[kat].join(', ')}\n`;
      delete gruppen[kat];
    }
  }

  // Restliche Kategorien
  for (const [kat, posen] of Object.entries(gruppen)) {
    text += `${kat}: ${posen.join(', ')}\n`;
  }

  text += `Gesamtwert: ${angebot.gesamtwert || 0}€ netto, Status: ${angebot.status || 'offen'}`;
  return text.trim();
}
```
