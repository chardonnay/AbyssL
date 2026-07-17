# Design QA — AbyssL Website

## Vergleichsgrundlage

- Referenz: Design 5, `codex-clipboard-e5aa2b39-8007-400d-95a4-41eefc885ab5.png`
- Implementierung: `docs/index.html` mit `docs/assets/site.css` und `docs/assets/site.js`
- Vergleichsviewport: 1487 × 1058 px, deutscher Inhalt, Light Theme, Story-Schritt „Übersetzen“
- Gemeinsames Vergleichsbild: `/Users/daniel/.codex/visualizations/2026/07/17/019f70bd-0ed4-7fd2-8d64-419997fb1383/abyssl-design-comparison-final.jpg`

## Sichtprüfung

- **Layout und Hierarchie:** Logo, Hauptnavigation, dreistufige linke Story-Rail, zweizeilige Hero-Headline und große App-Aufnahme entsprechen der Referenz. Die Hauptspalte beginnt bei praktisch identischer X-Position; der App-Frame ragt wie in der Vorlage leicht nach links in den Zwischenraum.
- **Typografie:** Inter/System-Sans, kräftige Display-Headline, kompakte Navigation sowie abgestufte Rail-Texte bilden die Referenzhierarchie nach. Die längere neue Provider-Botschaft bleibt klar lesbar und bricht ohne Überlauf um.
- **Abstände und Oberflächen:** Seitenränder, Rail-Abstände, feine Trennlinien, weiße Flächen, blaue Akzente, Fensterradius und Tiefenschatten entsprechen dem visuellen Charakter von Design 5.
- **Bildqualität:** Die drei Story-Schritte verwenden aktuelle, echte und befüllte App-Aufnahmen. Übersetzung, Korrektur, erfolgreiche Dokumentverarbeitung und Anthropic-Konfiguration sind scharf, passend beschnitten und enthalten keinen sichtbaren API-Schlüssel.
- **Interaktionen und Zustände:** Story-Fortschritt, Screenshot-Wechsel, Reveal, Parallax/Tiefeneffekt, Provider-Verzweigung, Provider-Tabs, Mobile-Menü und Theme-Schalter funktionieren. Reduced Motion entfernt automatische Bewegung und 3D-Transformationen.
- **Responsivität:** 1440, 1024, 768 und 390 px wurden ohne horizontalen Überlauf geprüft. Navigation, Story, Provider-Grafik, Tabs und Karten wechseln kontrolliert in Tablet- und Mobile-Layouts.
- **Barrierefreiheit:** Semantische Navigation, ein H1, fokussierbares Skip-Link-Ziel, Alt-/ARIA-Texte, Tastatursteuerung der Tabs, sichtbare Fokusmarkierungen und Reduced Motion sind vorhanden. Der korrigierte Darkmode-Aktionskontrast beträgt 5,90:1.
- **Sprachen und Inhalte:** Alle acht Sprachsätze enthalten denselben vollständigen Schlüsselumfang für UI, SEO, Provider, FAQ, Alt- und ARIA-Texte. OpenAI- und Anthropic-Kompatibilität, Cloud/Gateway/Lokal sowie der Kompatibilitätshinweis sind konsistent dargestellt.

## Verbleibende bewusste Abweichungen

- Die Website verwendet die aktuellen realen AbyssL-Screenshots statt der stilisierten Mockup-Inhalte der Referenz.
- Die Navigation enthält die zusätzlich geforderten Provider- und FAQ-Einstiege sowie Sprachwahl.
- Die drei Arbeitsbereiche werden als echte vertikale Scrollytelling-Sequenz gezeigt; dadurch folgt der Workflow-Abschnitt erst nach allen drei Story-Stufen.

final result: passed
