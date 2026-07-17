(() => {
  'use strict';

  const supportedLanguages = ['en', 'de', 'fr', 'es', 'pt', 'it', 'nl', 'hbs'];
  const htmlLanguages = { en: 'en', de: 'de', fr: 'fr', es: 'es', pt: 'pt', it: 'it', nl: 'nl', hbs: 'hr' };
  const aliases = { hr: 'hbs', bs: 'hbs', sr: 'hbs', sh: 'hbs' };
  const languageKey = 'abysslTranslatorLanguage';
  const themeKey = 'abysslWebsiteTheme';

  const copy = {
    de: {
      skip: 'Zum Inhalt springen', brandHome: 'AbyssL Startseite', mainNav: 'Hauptnavigation', mobileNav: 'Mobile Navigation', footerNav: 'Fußnavigation', navFunctions: 'Funktionen', navProviders: 'KI-Anbieter', navDocs: 'Dokumentation', themeLabel: 'Farbschema: Auto, Aus oder Ein', themeAuto: 'Auto', themeLight: 'Aus', themeDark: 'Ein', language: 'Sprache', github: 'Auf GitHub ansehen', menu: 'Menü', threeAreas: 'Drei Arbeitsbereiche',
      translateTitle: 'Übersetzen', translateRail: 'Natürlich übersetzen – mit Stilvorgaben und frei wählbarem Modell.', correctTitle: 'Korrigieren', correctRail: 'Rechtschreibung, Stil und Tonfall gezielt verbessern.', documentsTitle: 'Dokumente', documentsRail: 'Dateien stapelweise bearbeiten und in gängige Formate exportieren.',
      eyebrow: 'AbyssL Desktop-App', heroTitle: 'Übersetzen. Verbessern. Ganze Dokumente verarbeiten.', heroLead: 'AbyssL bündelt Übersetzung, Korrektur und Dokumentverarbeitung in einer Desktop-App – mit KI-Anbietern, Gateways und lokalen Servern über OpenAI- oder Anthropic-kompatible APIs.', readDocs: 'Dokumentation lesen', trustChip: 'OpenAI-kompatibel · Anthropic-kompatibel · Cloud oder lokal',
      translateHeading: 'Ein klarer Arbeitsbereich für präzise Übersetzungen.', translateAlt: 'AbyssL-Übersetzungsansicht mit deutschem Ausgangstext und englischer Übersetzung', translateCaption: 'Anweisung, Sprache, Stil, Auto-Übersetzung und Alternativen bleiben an einem Ort.', correctHeading: 'Vom Rohtext zur professionellen Fassung.', correctCopy: 'Rechtschreibung, Grammatik, Ton und Stil lassen sich mit einer direkten Anweisung korrigieren oder vollständig neu formulieren.', correctAlt: 'AbyssL-Korrekturansicht mit Eingabe und korrigiertem Ergebnis', correctCaption: 'Korrigieren oder umschreiben – nachvollziehbar und kopierbereit.', documentsHeading: 'Ein ganzer Ordner wird zu einem kontrollierten Workflow.', documentsCopy: 'Dateien oder Ordner ablegen, Korrektur und Übersetzung wählen, Ausgabeformat festlegen und Ergebnisse gesammelt exportieren.', documentsAlt: 'AbyssL-Dokumentansicht mit Dateiablage und Stapelverarbeitung', documentsCaption: 'TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX und optional ODT verarbeiten.',
      seamless: 'Nahtloser Workflow', workflowTitle: 'Ein Text. Drei Schritte. Ein konsistentes Ergebnis.', workflowStep1: 'Erfassen und übersetzen', workflowStep2: 'Stil und Ton verfeinern', workflowStep3: 'Dateien gesammelt ausgeben',
      providerEyebrow: 'Offene Provider-Anbindung', providersTitle: 'Zwei API-Formate. Freie Modellwahl.', providersLead: 'Nutze kompatible Cloud-Anbieter, Gateways oder lokale Modelle. Basis-URL, Modell-ID, Authentifizierung und Timeout bleiben konfigurierbar.', openAIFormat: 'OpenAI-kompatible Chat Completions', openAIDesc: 'Für Anbieter und Gateways, die das OpenAI-Format bereitstellen.', anthropicFormat: 'Anthropic-kompatible Messages', anthropicDesc: 'Für Anbieter und Gateways mit Anthropic-kompatiblen Messages-Endpunkten.', cloud: 'Cloud', cloudDesc: 'Gehostete KI-Anbieter', gateway: 'Gateway', gatewayDesc: 'Eigene oder verwaltete Proxies', local: 'Lokal', localDesc: 'Kompatible lokale Server',
      configEyebrow: 'Konfiguration', configTitle: 'Der passende Verbindungstyp in wenigen Klicks.', configLead: 'Wähle ein API-Format, hinterlege deinen Endpunkt und teste die Verbindung direkt in AbyssL.', connectionType: 'Verbindungstyp', openAIShort: 'OpenAI-kompatibel', anthropicShort: 'Anthropic-kompatibel', localShort: 'Lokal OpenAI-kompatibel', baseUrl: 'Basis-URL', auth: 'Authentifizierung', modelId: 'Modell-ID', none: 'Keine', anthropicAlt: 'AbyssL-Einstellungen mit Anthropic-kompatibler Verbindung, x-api-key, Modell-ID und leerem API-Schlüsselfeld', anthropicCaption: 'Anthropic-kompatible Basis-URL, Modell-ID, Authentifizierung und Version – ohne sichtbaren API-Schlüssel.',
      detailsEyebrow: 'Produktiv bis ins Detail', featuresTitle: 'Weniger Wechsel. Mehr Kontrolle.', featureInstructions: 'Direkte Anweisungen', featureInstructionsDesc: 'Gib Kontext, Terminologie und gewünschte Stilregeln direkt mit.', featureAlternatives: 'Alternativen vergleichen', featureAlternativesDesc: 'Erzeuge Varianten, ohne den laufenden Arbeitskontext zu verlieren.', featureCapture: 'Global erfassen', featureCaptureDesc: 'Übernimm markierten Text per systemweitem Tastenkürzel in AbyssL.', featureSecure: 'Schlüssel sicher speichern', featureSecureDesc: 'API-Schlüssel landen im Secure Storage, nicht in normalen Einstellungen.',
      faqTitle: 'Gut zu wissen.', faqCompatibilityQ: 'Funktioniert wirklich jeder kompatible Anbieter?', faqCompatibilityA: 'Anbieter setzen Kompatibilitätsstandards unterschiedlich vollständig um. Der integrierte Verbindungstest prüft deine konkrete URL, Authentifizierung und Modell-ID. Native Bedrock-, Vertex-AI- oder Azure-IAM-Verfahren benötigen gegebenenfalls ein kompatibles Gateway.', faqLocalQ: 'Kann AbyssL vollständig mit einem lokalen Modell arbeiten?', faqLocalA: 'Ja, wenn der lokale Server einen ausreichend kompatiblen OpenAI-Chat-Completions-Endpunkt bereitstellt. Qualität und Funktionsumfang hängen vom gewählten Modell und Server ab.', faqDocsQ: 'Welche Dokumente kann ich verarbeiten?', faqDocsA: 'Unterstützt werden TXT, Markdown, AsciiDoc, HTML, RTF, PDF mit extrahierbarem Text, DOCX und XLSX; ODT benötigt LibreOffice. Gescannte PDFs werden ohne OCR nicht erkannt.', faqDownloadQ: 'Wo kann ich AbyssL herunterladen?', faqDownloadA: 'Der aktuelle Entwicklungsstand und die Build-Anleitung liegen auf GitHub. Sobald ein offizielles Release verfügbar ist, wird die Website einen direkten, überprüften Download anbieten.',
      finalTitle: 'Ein Workflow für Text, Sprache und ganze Dokumente.', finalLead: 'Open Source, transparent konfigurierbar und offen für kompatible KI-Anbieter.', developer: 'Entwickelt von Daniel Mengel.'
    },
    en: {
      skip: 'Skip to content', brandHome: 'AbyssL home page', mainNav: 'Main navigation', mobileNav: 'Mobile navigation', footerNav: 'Footer navigation', navFunctions: 'Features', navProviders: 'AI providers', navDocs: 'Documentation', themeLabel: 'Color scheme: auto, off, or on', themeAuto: 'Auto', themeLight: 'Off', themeDark: 'On', language: 'Language', github: 'View on GitHub', menu: 'Menu', threeAreas: 'Three workspaces',
      translateTitle: 'Translate', translateRail: 'Natural translations with style controls and your choice of model.', correctTitle: 'Correct', correctRail: 'Improve spelling, style, and tone with precision.', documentsTitle: 'Documents', documentsRail: 'Process files in batches and export common formats.',
      eyebrow: 'AbyssL desktop app', heroTitle: 'Translate. Improve. Process entire documents.', heroLead: 'AbyssL brings translation, correction, and document processing into one desktop app—with AI providers, gateways, and local servers through OpenAI- or Anthropic-compatible APIs.', readDocs: 'Read the documentation', trustChip: 'OpenAI-compatible · Anthropic-compatible · Cloud or local',
      translateHeading: 'A focused workspace for precise translations.', translateAlt: 'AbyssL translation view with German source text and an English translation', translateCaption: 'Instructions, language, style, auto-translate, and alternatives stay in one place.', correctHeading: 'From rough draft to professional copy.', correctCopy: 'Correct spelling, grammar, tone, and style with a direct instruction, or rewrite the text completely.', correctAlt: 'AbyssL correction view with input and corrected result', correctCaption: 'Correct or rewrite—with results that are clear and ready to copy.', documentsHeading: 'Turn an entire folder into a controlled workflow.', documentsCopy: 'Drop files or folders, choose correction and translation, set an output format, and export results together.', documentsAlt: 'AbyssL document view with file drop zone and batch processing', documentsCaption: 'Process TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX, and optional ODT.',
      seamless: 'Seamless workflow', workflowTitle: 'One text. Three steps. One consistent result.', workflowStep1: 'Capture and translate', workflowStep2: 'Refine style and tone', workflowStep3: 'Export files together',
      providerEyebrow: 'Open provider connectivity', providersTitle: 'Two API formats. Your choice of model.', providersLead: 'Use compatible cloud providers, gateways, or local models. The base URL, model ID, authentication, and timeout remain configurable.', openAIFormat: 'OpenAI-compatible Chat Completions', openAIDesc: 'For providers and gateways that expose the OpenAI format.', anthropicFormat: 'Anthropic-compatible Messages', anthropicDesc: 'For providers and gateways with Anthropic-compatible Messages endpoints.', cloud: 'Cloud', cloudDesc: 'Hosted AI providers', gateway: 'Gateway', gatewayDesc: 'Self-hosted or managed proxies', local: 'Local', localDesc: 'Compatible local servers',
      configEyebrow: 'Configuration', configTitle: 'Choose the right connection type in a few clicks.', configLead: 'Choose an API format, enter your endpoint, and test the connection directly in AbyssL.', connectionType: 'Connection type', openAIShort: 'OpenAI-compatible', anthropicShort: 'Anthropic-compatible', localShort: 'Local OpenAI-compatible', baseUrl: 'Base URL', auth: 'Authentication', modelId: 'Model ID', none: 'None', anthropicAlt: 'AbyssL settings with an Anthropic-compatible connection, x-api-key, model ID, and an empty API key field', anthropicCaption: 'Anthropic-compatible base URL, model ID, authentication, and version—with no visible API key.',
      detailsEyebrow: 'Productive down to the details', featuresTitle: 'Fewer switches. More control.', featureInstructions: 'Direct instructions', featureInstructionsDesc: 'Add context, terminology, and style rules directly.', featureAlternatives: 'Compare alternatives', featureAlternativesDesc: 'Generate variants without losing your current working context.', featureCapture: 'Capture globally', featureCaptureDesc: 'Send selected text to AbyssL with a system-wide shortcut.', featureSecure: 'Store keys securely', featureSecureDesc: 'API keys stay in secure storage, not ordinary preferences.',
      faqTitle: 'Good to know.', faqCompatibilityQ: 'Does every compatible provider really work?', faqCompatibilityA: 'Providers implement compatibility standards to varying degrees. The built-in connection test checks your exact URL, authentication, and model ID. Native Bedrock, Vertex AI, or Azure IAM methods may require a compatible gateway.', faqLocalQ: 'Can AbyssL run entirely with a local model?', faqLocalA: 'Yes, when the local server exposes a sufficiently compatible OpenAI Chat Completions endpoint. Quality and available features depend on the chosen model and server.', faqDocsQ: 'Which documents can I process?', faqDocsA: 'TXT, Markdown, AsciiDoc, HTML, RTF, PDFs with extractable text, DOCX, and XLSX are supported; ODT requires LibreOffice. Scanned PDFs are not detected without OCR.', faqDownloadQ: 'Where can I download AbyssL?', faqDownloadA: 'The current development version and build instructions are available on GitHub. Once an official release is available, the website will offer a direct, verified download.',
      finalTitle: 'One workflow for text, language, and entire documents.', finalLead: 'Open source, transparently configurable, and open to compatible AI providers.', developer: 'Developed by Daniel Mengel.'
    },
    fr: {
      skip: 'Aller au contenu', brandHome: 'Accueil AbyssL', mainNav: 'Navigation principale', mobileNav: 'Navigation mobile', footerNav: 'Navigation de pied de page', navFunctions: 'Fonctions', navProviders: 'Fournisseurs IA', navDocs: 'Documentation', themeLabel: 'Thème : auto, désactivé ou activé', themeAuto: 'Auto', themeLight: 'Désact.', themeDark: 'Activé', language: 'Langue', github: 'Voir sur GitHub', menu: 'Menu', threeAreas: 'Trois espaces de travail',
      translateTitle: 'Traduire', translateRail: 'Des traductions naturelles avec style et modèle au choix.', correctTitle: 'Corriger', correctRail: 'Améliorer précisément orthographe, style et ton.', documentsTitle: 'Documents', documentsRail: 'Traiter des fichiers par lots et exporter les formats courants.',
      eyebrow: 'Application de bureau AbyssL', heroTitle: 'Traduire. Améliorer. Traiter des documents entiers.', heroLead: 'AbyssL réunit traduction, correction et traitement de documents dans une application de bureau, avec des fournisseurs IA, passerelles et serveurs locaux via des API compatibles OpenAI ou Anthropic.', readDocs: 'Lire la documentation', trustChip: 'Compatible OpenAI · Compatible Anthropic · Cloud ou local',
      translateHeading: 'Un espace clair pour des traductions précises.', translateAlt: 'Vue de traduction AbyssL avec un texte source allemand et sa traduction anglaise', translateCaption: 'Instructions, langue, style, traduction automatique et variantes restent au même endroit.', correctHeading: 'Du brouillon à une version professionnelle.', correctCopy: 'Corrigez orthographe, grammaire, ton et style par instruction directe, ou reformulez entièrement le texte.', correctAlt: 'Vue de correction AbyssL avec entrée et résultat corrigé', correctCaption: 'Corriger ou reformuler, avec un résultat clair et prêt à copier.', documentsHeading: 'Transformez un dossier entier en flux contrôlé.', documentsCopy: 'Déposez fichiers ou dossiers, choisissez correction et traduction, définissez le format et exportez les résultats ensemble.', documentsAlt: 'Vue Documents d’AbyssL avec zone de dépôt et traitement par lots', documentsCaption: 'Traitez TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX et ODT en option.',
      seamless: 'Flux continu', workflowTitle: 'Un texte. Trois étapes. Un résultat cohérent.', workflowStep1: 'Capturer et traduire', workflowStep2: 'Affiner style et ton', workflowStep3: 'Exporter les fichiers ensemble',
      providerEyebrow: 'Connexion ouverte aux fournisseurs', providersTitle: 'Deux formats d’API. Modèle au choix.', providersLead: 'Utilisez des fournisseurs cloud, des passerelles ou des modèles locaux compatibles. URL de base, modèle, authentification et délai restent configurables.', openAIFormat: 'Chat Completions compatibles OpenAI', openAIDesc: 'Pour les fournisseurs et passerelles proposant le format OpenAI.', anthropicFormat: 'Messages compatibles Anthropic', anthropicDesc: 'Pour les fournisseurs et passerelles avec des endpoints Messages compatibles Anthropic.', cloud: 'Cloud', cloudDesc: 'Fournisseurs IA hébergés', gateway: 'Passerelle', gatewayDesc: 'Proxies privés ou gérés', local: 'Local', localDesc: 'Serveurs locaux compatibles',
      configEyebrow: 'Configuration', configTitle: 'Le bon type de connexion en quelques clics.', configLead: 'Choisissez un format d’API, saisissez l’endpoint et testez la connexion directement dans AbyssL.', connectionType: 'Type de connexion', openAIShort: 'Compatible OpenAI', anthropicShort: 'Compatible Anthropic', localShort: 'OpenAI local compatible', baseUrl: 'URL de base', auth: 'Authentification', modelId: 'ID du modèle', none: 'Aucune', anthropicAlt: 'Paramètres AbyssL avec connexion compatible Anthropic, x-api-key, modèle et champ de clé API vide', anthropicCaption: 'URL de base, modèle, authentification et version compatibles Anthropic, sans clé API visible.',
      detailsEyebrow: 'Productif jusque dans les détails', featuresTitle: 'Moins de changements. Plus de contrôle.', featureInstructions: 'Instructions directes', featureInstructionsDesc: 'Ajoutez directement contexte, terminologie et règles de style.', featureAlternatives: 'Comparer les variantes', featureAlternativesDesc: 'Générez des variantes sans perdre le contexte en cours.', featureCapture: 'Capture globale', featureCaptureDesc: 'Envoyez le texte sélectionné vers AbyssL par raccourci système.', featureSecure: 'Clés stockées en sécurité', featureSecureDesc: 'Les clés API restent dans le stockage sécurisé, pas dans les préférences ordinaires.',
      faqTitle: 'Bon à savoir.', faqCompatibilityQ: 'Tous les fournisseurs compatibles fonctionnent-ils vraiment ?', faqCompatibilityA: 'Les fournisseurs implémentent les standards de compatibilité à des degrés divers. Le test intégré vérifie votre URL, l’authentification et le modèle. Bedrock, Vertex AI ou Azure IAM natifs peuvent nécessiter une passerelle compatible.', faqLocalQ: 'AbyssL peut-il fonctionner entièrement avec un modèle local ?', faqLocalA: 'Oui, si le serveur local fournit un endpoint OpenAI Chat Completions suffisamment compatible. La qualité et les fonctions dépendent du modèle et du serveur.', faqDocsQ: 'Quels documents puis-je traiter ?', faqDocsA: 'TXT, Markdown, AsciiDoc, HTML, RTF, PDF avec texte extractible, DOCX et XLSX sont pris en charge ; ODT nécessite LibreOffice. Les PDF scannés ne sont pas reconnus sans OCR.', faqDownloadQ: 'Où télécharger AbyssL ?', faqDownloadA: 'La version de développement et les instructions de build sont sur GitHub. Dès qu’une version officielle sera disponible, le site proposera un téléchargement direct et vérifié.',
      finalTitle: 'Un flux pour le texte, les langues et les documents entiers.', finalLead: 'Open source, configurable en toute transparence et ouvert aux fournisseurs IA compatibles.', developer: 'Développé par Daniel Mengel.'
    },
    es: {
      skip: 'Saltar al contenido', brandHome: 'Página de inicio de AbyssL', mainNav: 'Navegación principal', mobileNav: 'Navegación móvil', footerNav: 'Navegación del pie', navFunctions: 'Funciones', navProviders: 'Proveedores de IA', navDocs: 'Documentación', themeLabel: 'Tema: automático, apagado o encendido', themeAuto: 'Auto', themeLight: 'Apagado', themeDark: 'Encendido', language: 'Idioma', github: 'Ver en GitHub', menu: 'Menú', threeAreas: 'Tres áreas de trabajo',
      translateTitle: 'Traducir', translateRail: 'Traducciones naturales con estilo y modelo a elección.', correctTitle: 'Corregir', correctRail: 'Mejora ortografía, estilo y tono con precisión.', documentsTitle: 'Documentos', documentsRail: 'Procesa archivos por lotes y exporta formatos habituales.',
      eyebrow: 'Aplicación de escritorio AbyssL', heroTitle: 'Traduce. Mejora. Procesa documentos completos.', heroLead: 'AbyssL reúne traducción, corrección y procesamiento de documentos en una aplicación de escritorio, con proveedores de IA, pasarelas y servidores locales mediante API compatibles con OpenAI o Anthropic.', readDocs: 'Leer la documentación', trustChip: 'Compatible con OpenAI · Compatible con Anthropic · Nube o local',
      translateHeading: 'Un espacio claro para traducciones precisas.', translateAlt: 'Vista de traducción de AbyssL con texto fuente alemán y traducción inglesa', translateCaption: 'Instrucciones, idioma, estilo, traducción automática y alternativas en un solo lugar.', correctHeading: 'Del borrador a una versión profesional.', correctCopy: 'Corrige ortografía, gramática, tono y estilo con una instrucción directa o reescribe el texto por completo.', correctAlt: 'Vista de corrección de AbyssL con entrada y resultado corregido', correctCaption: 'Corrige o reescribe, con resultados claros y listos para copiar.', documentsHeading: 'Convierte una carpeta entera en un flujo controlado.', documentsCopy: 'Suelta archivos o carpetas, elige corrección y traducción, define el formato y exporta todos los resultados.', documentsAlt: 'Vista de documentos de AbyssL con zona de archivos y procesamiento por lotes', documentsCaption: 'Procesa TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX y ODT opcional.',
      seamless: 'Flujo continuo', workflowTitle: 'Un texto. Tres pasos. Un resultado coherente.', workflowStep1: 'Capturar y traducir', workflowStep2: 'Refinar estilo y tono', workflowStep3: 'Exportar archivos juntos',
      providerEyebrow: 'Conexión abierta a proveedores', providersTitle: 'Dos formatos de API. Modelo libre.', providersLead: 'Usa proveedores en la nube, pasarelas o modelos locales compatibles. URL base, modelo, autenticación y tiempo de espera son configurables.', openAIFormat: 'Chat Completions compatibles con OpenAI', openAIDesc: 'Para proveedores y pasarelas que ofrecen el formato OpenAI.', anthropicFormat: 'Messages compatibles con Anthropic', anthropicDesc: 'Para proveedores y pasarelas con endpoints Messages compatibles con Anthropic.', cloud: 'Nube', cloudDesc: 'Proveedores de IA alojados', gateway: 'Pasarela', gatewayDesc: 'Proxies propios o gestionados', local: 'Local', localDesc: 'Servidores locales compatibles',
      configEyebrow: 'Configuración', configTitle: 'El tipo de conexión adecuado en pocos clics.', configLead: 'Elige un formato de API, introduce tu endpoint y prueba la conexión directamente en AbyssL.', connectionType: 'Tipo de conexión', openAIShort: 'Compatible con OpenAI', anthropicShort: 'Compatible con Anthropic', localShort: 'OpenAI local compatible', baseUrl: 'URL base', auth: 'Autenticación', modelId: 'ID del modelo', none: 'Ninguna', anthropicAlt: 'Ajustes de AbyssL con conexión compatible con Anthropic, x-api-key, modelo y campo de clave API vacío', anthropicCaption: 'URL base, modelo, autenticación y versión compatibles con Anthropic, sin clave API visible.',
      detailsEyebrow: 'Productividad hasta el detalle', featuresTitle: 'Menos cambios. Más control.', featureInstructions: 'Instrucciones directas', featureInstructionsDesc: 'Añade contexto, terminología y reglas de estilo directamente.', featureAlternatives: 'Comparar alternativas', featureAlternativesDesc: 'Genera variantes sin perder el contexto de trabajo.', featureCapture: 'Captura global', featureCaptureDesc: 'Envía texto seleccionado a AbyssL con un atajo del sistema.', featureSecure: 'Claves almacenadas con seguridad', featureSecureDesc: 'Las claves API permanecen en almacenamiento seguro, no en preferencias normales.',
      faqTitle: 'Conviene saberlo.', faqCompatibilityQ: '¿Funciona realmente cualquier proveedor compatible?', faqCompatibilityA: 'Los proveedores implementan los estándares de compatibilidad en distinto grado. La prueba integrada verifica URL, autenticación y modelo. Los métodos nativos de Bedrock, Vertex AI o Azure IAM pueden requerir una pasarela compatible.', faqLocalQ: '¿Puede AbyssL funcionar por completo con un modelo local?', faqLocalA: 'Sí, si el servidor local ofrece un endpoint OpenAI Chat Completions suficientemente compatible. La calidad y funciones dependen del modelo y servidor.', faqDocsQ: '¿Qué documentos puedo procesar?', faqDocsA: 'Se admiten TXT, Markdown, AsciiDoc, HTML, RTF, PDF con texto extraíble, DOCX y XLSX; ODT requiere LibreOffice. Los PDF escaneados no se detectan sin OCR.', faqDownloadQ: '¿Dónde puedo descargar AbyssL?', faqDownloadA: 'La versión de desarrollo y las instrucciones están en GitHub. Cuando exista una versión oficial, el sitio ofrecerá una descarga directa y verificada.',
      finalTitle: 'Un flujo para texto, idiomas y documentos completos.', finalLead: 'Código abierto, configuración transparente y abierto a proveedores de IA compatibles.', developer: 'Desarrollado por Daniel Mengel.'
    },
    pt: {
      skip: 'Ir para o conteúdo', brandHome: 'Página inicial do AbyssL', mainNav: 'Navegação principal', mobileNav: 'Navegação móvel', footerNav: 'Navegação do rodapé', navFunctions: 'Funcionalidades', navProviders: 'Fornecedores de IA', navDocs: 'Documentação', themeLabel: 'Tema: automático, desligado ou ligado', themeAuto: 'Auto', themeLight: 'Desligado', themeDark: 'Ligado', language: 'Idioma', github: 'Ver no GitHub', menu: 'Menu', threeAreas: 'Três áreas de trabalho',
      translateTitle: 'Traduzir', translateRail: 'Traduções naturais com estilo e modelo à escolha.', correctTitle: 'Corrigir', correctRail: 'Melhore ortografia, estilo e tom com precisão.', documentsTitle: 'Documentos', documentsRail: 'Processe ficheiros em lote e exporte formatos comuns.',
      eyebrow: 'Aplicação desktop AbyssL', heroTitle: 'Traduza. Melhore. Processe documentos inteiros.', heroLead: 'O AbyssL reúne tradução, correção e processamento de documentos numa aplicação desktop, com fornecedores de IA, gateways e servidores locais através de APIs compatíveis com OpenAI ou Anthropic.', readDocs: 'Ler a documentação', trustChip: 'Compatível com OpenAI · Compatível com Anthropic · Cloud ou local',
      translateHeading: 'Um espaço claro para traduções precisas.', translateAlt: 'Vista de tradução do AbyssL com texto de origem alemão e tradução inglesa', translateCaption: 'Instruções, idioma, estilo, tradução automática e alternativas num só lugar.', correctHeading: 'Do rascunho à versão profissional.', correctCopy: 'Corrija ortografia, gramática, tom e estilo com uma instrução direta ou reescreva o texto por completo.', correctAlt: 'Vista de correção do AbyssL com entrada e resultado corrigido', correctCaption: 'Corrija ou reescreva, com resultados claros e prontos a copiar.', documentsHeading: 'Transforme uma pasta inteira num fluxo controlado.', documentsCopy: 'Solte ficheiros ou pastas, escolha correção e tradução, defina o formato e exporte os resultados em conjunto.', documentsAlt: 'Vista de documentos do AbyssL com zona de ficheiros e processamento em lote', documentsCaption: 'Processe TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX e ODT opcional.',
      seamless: 'Fluxo contínuo', workflowTitle: 'Um texto. Três passos. Um resultado consistente.', workflowStep1: 'Capturar e traduzir', workflowStep2: 'Aperfeiçoar estilo e tom', workflowStep3: 'Exportar ficheiros em conjunto',
      providerEyebrow: 'Ligação aberta a fornecedores', providersTitle: 'Dois formatos de API. Modelo à escolha.', providersLead: 'Use fornecedores cloud, gateways ou modelos locais compatíveis. URL base, modelo, autenticação e timeout continuam configuráveis.', openAIFormat: 'Chat Completions compatíveis com OpenAI', openAIDesc: 'Para fornecedores e gateways que disponibilizam o formato OpenAI.', anthropicFormat: 'Messages compatíveis com Anthropic', anthropicDesc: 'Para fornecedores e gateways com endpoints Messages compatíveis com Anthropic.', cloud: 'Cloud', cloudDesc: 'Fornecedores de IA alojados', gateway: 'Gateway', gatewayDesc: 'Proxies próprios ou geridos', local: 'Local', localDesc: 'Servidores locais compatíveis',
      configEyebrow: 'Configuração', configTitle: 'O tipo de ligação certo em poucos cliques.', configLead: 'Escolha um formato de API, introduza o endpoint e teste a ligação diretamente no AbyssL.', connectionType: 'Tipo de ligação', openAIShort: 'Compatível com OpenAI', anthropicShort: 'Compatível com Anthropic', localShort: 'OpenAI local compatível', baseUrl: 'URL base', auth: 'Autenticação', modelId: 'ID do modelo', none: 'Nenhuma', anthropicAlt: 'Definições do AbyssL com ligação compatível com Anthropic, x-api-key, modelo e campo de chave API vazio', anthropicCaption: 'URL base, modelo, autenticação e versão compatíveis com Anthropic, sem chave API visível.',
      detailsEyebrow: 'Produtivo até ao detalhe', featuresTitle: 'Menos trocas. Mais controlo.', featureInstructions: 'Instruções diretas', featureInstructionsDesc: 'Adicione contexto, terminologia e regras de estilo diretamente.', featureAlternatives: 'Comparar alternativas', featureAlternativesDesc: 'Gere variantes sem perder o contexto de trabalho.', featureCapture: 'Captura global', featureCaptureDesc: 'Envie texto selecionado para o AbyssL com um atalho do sistema.', featureSecure: 'Guardar chaves em segurança', featureSecureDesc: 'As chaves API ficam no armazenamento seguro, não nas preferências normais.',
      faqTitle: 'É bom saber.', faqCompatibilityQ: 'Todos os fornecedores compatíveis funcionam?', faqCompatibilityA: 'Os fornecedores implementam os padrões de compatibilidade em graus diferentes. O teste integrado verifica URL, autenticação e modelo. Métodos nativos Bedrock, Vertex AI ou Azure IAM podem exigir um gateway compatível.', faqLocalQ: 'O AbyssL pode funcionar apenas com um modelo local?', faqLocalA: 'Sim, quando o servidor local disponibiliza um endpoint OpenAI Chat Completions suficientemente compatível. A qualidade e as funcionalidades dependem do modelo e servidor.', faqDocsQ: 'Que documentos posso processar?', faqDocsA: 'São suportados TXT, Markdown, AsciiDoc, HTML, RTF, PDF com texto extraível, DOCX e XLSX; ODT exige LibreOffice. PDFs digitalizados não são detetados sem OCR.', faqDownloadQ: 'Onde posso descarregar o AbyssL?', faqDownloadA: 'A versão de desenvolvimento e as instruções estão no GitHub. Quando existir uma versão oficial, o site oferecerá um download direto e verificado.',
      finalTitle: 'Um fluxo para texto, idiomas e documentos inteiros.', finalLead: 'Código aberto, configuração transparente e aberto a fornecedores de IA compatíveis.', developer: 'Desenvolvido por Daniel Mengel.'
    },
    it: {
      skip: 'Vai al contenuto', brandHome: 'Pagina iniziale AbyssL', mainNav: 'Navigazione principale', mobileNav: 'Navigazione mobile', footerNav: 'Navigazione piè di pagina', navFunctions: 'Funzioni', navProviders: 'Provider IA', navDocs: 'Documentazione', themeLabel: 'Tema: automatico, spento o acceso', themeAuto: 'Auto', themeLight: 'Spento', themeDark: 'Acceso', language: 'Lingua', github: 'Vedi su GitHub', menu: 'Menu', threeAreas: 'Tre aree di lavoro',
      translateTitle: 'Traduci', translateRail: 'Traduzioni naturali con stile e modello a scelta.', correctTitle: 'Correggi', correctRail: 'Migliora ortografia, stile e tono con precisione.', documentsTitle: 'Documenti', documentsRail: 'Elabora file in batch ed esporta i formati comuni.',
      eyebrow: 'App desktop AbyssL', heroTitle: 'Traduci. Migliora. Elabora interi documenti.', heroLead: 'AbyssL riunisce traduzione, correzione ed elaborazione documenti in un’app desktop, con provider IA, gateway e server locali tramite API compatibili OpenAI o Anthropic.', readDocs: 'Leggi la documentazione', trustChip: 'Compatibile OpenAI · Compatibile Anthropic · Cloud o locale',
      translateHeading: 'Uno spazio chiaro per traduzioni precise.', translateAlt: 'Vista di traduzione AbyssL con testo sorgente tedesco e traduzione inglese', translateCaption: 'Istruzioni, lingua, stile, traduzione automatica e alternative in un unico posto.', correctHeading: 'Dalla bozza a una versione professionale.', correctCopy: 'Correggi ortografia, grammatica, tono e stile con un’istruzione diretta oppure riscrivi completamente il testo.', correctAlt: 'Vista di correzione AbyssL con input e risultato corretto', correctCaption: 'Correggi o riscrivi, con risultati chiari e pronti da copiare.', documentsHeading: 'Trasforma un’intera cartella in un flusso controllato.', documentsCopy: 'Trascina file o cartelle, scegli correzione e traduzione, imposta il formato ed esporta insieme i risultati.', documentsAlt: 'Vista Documenti AbyssL con area file ed elaborazione batch', documentsCaption: 'Elabora TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX e ODT opzionale.',
      seamless: 'Flusso continuo', workflowTitle: 'Un testo. Tre passaggi. Un risultato coerente.', workflowStep1: 'Acquisisci e traduci', workflowStep2: 'Affina stile e tono', workflowStep3: 'Esporta i file insieme',
      providerEyebrow: 'Connessione aperta ai provider', providersTitle: 'Due formati API. Modello libero.', providersLead: 'Usa provider cloud, gateway o modelli locali compatibili. URL base, modello, autenticazione e timeout restano configurabili.', openAIFormat: 'Chat Completions compatibili OpenAI', openAIDesc: 'Per provider e gateway che offrono il formato OpenAI.', anthropicFormat: 'Messages compatibili Anthropic', anthropicDesc: 'Per provider e gateway con endpoint Messages compatibili Anthropic.', cloud: 'Cloud', cloudDesc: 'Provider IA ospitati', gateway: 'Gateway', gatewayDesc: 'Proxy propri o gestiti', local: 'Locale', localDesc: 'Server locali compatibili',
      configEyebrow: 'Configurazione', configTitle: 'Il tipo di connessione giusto in pochi clic.', configLead: 'Scegli un formato API, inserisci l’endpoint e testa la connessione direttamente in AbyssL.', connectionType: 'Tipo di connessione', openAIShort: 'Compatibile OpenAI', anthropicShort: 'Compatibile Anthropic', localShort: 'OpenAI locale compatibile', baseUrl: 'URL base', auth: 'Autenticazione', modelId: 'ID modello', none: 'Nessuna', anthropicAlt: 'Impostazioni AbyssL con connessione compatibile Anthropic, x-api-key, modello e campo chiave API vuoto', anthropicCaption: 'URL di base, modello, autenticazione e versione compatibili Anthropic, senza chiavi API visibili.',
      detailsEyebrow: 'Produttivo in ogni dettaglio', featuresTitle: 'Meno passaggi. Più controllo.', featureInstructions: 'Istruzioni dirette', featureInstructionsDesc: 'Aggiungi direttamente contesto, terminologia e regole di stile.', featureAlternatives: 'Confronta alternative', featureAlternativesDesc: 'Genera varianti senza perdere il contesto di lavoro.', featureCapture: 'Acquisizione globale', featureCaptureDesc: 'Invia il testo selezionato ad AbyssL con una scorciatoia di sistema.', featureSecure: 'Chiavi archiviate in sicurezza', featureSecureDesc: 'Le chiavi API restano nello storage sicuro, non nelle preferenze normali.',
      faqTitle: 'Buono a sapersi.', faqCompatibilityQ: 'Funziona davvero ogni provider compatibile?', faqCompatibilityA: 'I provider implementano gli standard di compatibilità in misura diversa. Il test integrato verifica URL, autenticazione e modello. I metodi nativi Bedrock, Vertex AI o Azure IAM possono richiedere un gateway compatibile.', faqLocalQ: 'AbyssL può funzionare interamente con un modello locale?', faqLocalA: 'Sì, se il server locale offre un endpoint OpenAI Chat Completions sufficientemente compatibile. Qualità e funzioni dipendono dal modello e dal server.', faqDocsQ: 'Quali documenti posso elaborare?', faqDocsA: 'Sono supportati TXT, Markdown, AsciiDoc, HTML, RTF, PDF con testo estraibile, DOCX e XLSX; ODT richiede LibreOffice. I PDF scansionati non vengono rilevati senza OCR.', faqDownloadQ: 'Dove posso scaricare AbyssL?', faqDownloadA: 'La versione di sviluppo e le istruzioni sono su GitHub. Quando sarà disponibile una release ufficiale, il sito offrirà un download diretto e verificato.',
      finalTitle: 'Un flusso per testo, lingue e interi documenti.', finalLead: 'Open source, configurabile con trasparenza e aperto ai provider IA compatibili.', developer: 'Sviluppato da Daniel Mengel.'
    },
    nl: {
      skip: 'Naar de inhoud', brandHome: 'AbyssL-startpagina', mainNav: 'Hoofdnavigatie', mobileNav: 'Mobiele navigatie', footerNav: 'Voettekstnavigatie', navFunctions: 'Functies', navProviders: 'AI-aanbieders', navDocs: 'Documentatie', themeLabel: 'Thema: automatisch, uit of aan', themeAuto: 'Auto', themeLight: 'Uit', themeDark: 'Aan', language: 'Taal', github: 'Bekijk op GitHub', menu: 'Menu', threeAreas: 'Drie werkgebieden',
      translateTitle: 'Vertalen', translateRail: 'Natuurlijke vertalingen met stijl en model naar keuze.', correctTitle: 'Corrigeren', correctRail: 'Verbeter spelling, stijl en toon gericht.', documentsTitle: 'Documenten', documentsRail: 'Verwerk bestanden in batches en exporteer gangbare formaten.',
      eyebrow: 'AbyssL-desktopapp', heroTitle: 'Vertalen. Verbeteren. Volledige documenten verwerken.', heroLead: 'AbyssL brengt vertaling, correctie en documentverwerking samen in één desktopapp, met AI-aanbieders, gateways en lokale servers via OpenAI- of Anthropic-compatibele API’s.', readDocs: 'Lees de documentatie', trustChip: 'OpenAI-compatibel · Anthropic-compatibel · Cloud of lokaal',
      translateHeading: 'Een heldere werkruimte voor nauwkeurige vertalingen.', translateAlt: 'AbyssL-vertaalscherm met Duitse brontekst en Engelse vertaling', translateCaption: 'Instructie, taal, stijl, automatisch vertalen en alternatieven blijven bij elkaar.', correctHeading: 'Van ruwe tekst naar professionele versie.', correctCopy: 'Corrigeer spelling, grammatica, toon en stijl met een directe instructie of herschrijf de tekst volledig.', correctAlt: 'AbyssL-correctiescherm met invoer en gecorrigeerd resultaat', correctCaption: 'Corrigeer of herschrijf, met duidelijke resultaten die klaar zijn om te kopiëren.', documentsHeading: 'Maak van een hele map een gecontroleerde workflow.', documentsCopy: 'Sleep bestanden of mappen, kies correctie en vertaling, stel het formaat in en exporteer de resultaten samen.', documentsAlt: 'AbyssL-documentenscherm met bestandszone en batchverwerking', documentsCaption: 'Verwerk TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX en optioneel ODT.',
      seamless: 'Naadloze workflow', workflowTitle: 'Eén tekst. Drie stappen. Eén consistent resultaat.', workflowStep1: 'Vastleggen en vertalen', workflowStep2: 'Stijl en toon verfijnen', workflowStep3: 'Bestanden samen exporteren',
      providerEyebrow: 'Open providerkoppeling', providersTitle: 'Twee API-formaten. Vrije modelkeuze.', providersLead: 'Gebruik compatibele cloudproviders, gateways of lokale modellen. Basis-URL, model, authenticatie en timeout blijven instelbaar.', openAIFormat: 'OpenAI-compatibele Chat Completions', openAIDesc: 'Voor aanbieders en gateways die het OpenAI-formaat leveren.', anthropicFormat: 'Anthropic-compatibele Messages', anthropicDesc: 'Voor aanbieders en gateways met Anthropic-compatibele Messages-endpoints.', cloud: 'Cloud', cloudDesc: 'Gehoste AI-aanbieders', gateway: 'Gateway', gatewayDesc: 'Eigen of beheerde proxy’s', local: 'Lokaal', localDesc: 'Compatibele lokale servers',
      configEyebrow: 'Configuratie', configTitle: 'Het juiste verbindingstype in enkele klikken.', configLead: 'Kies een API-formaat, voer je endpoint in en test de verbinding direct in AbyssL.', connectionType: 'Verbindingstype', openAIShort: 'OpenAI-compatibel', anthropicShort: 'Anthropic-compatibel', localShort: 'Lokaal OpenAI-compatibel', baseUrl: 'Basis-URL', auth: 'Authenticatie', modelId: 'Model-ID', none: 'Geen', anthropicAlt: 'AbyssL-instellingen met een Anthropic-compatibele verbinding, x-api-key, model-ID en leeg API-sleutelveld', anthropicCaption: 'Anthropic-compatibele basis-URL, model-ID, authenticatie en versie, zonder zichtbare API-sleutel.',
      detailsEyebrow: 'Productief tot in detail', featuresTitle: 'Minder wisselen. Meer controle.', featureInstructions: 'Directe instructies', featureInstructionsDesc: 'Voeg context, terminologie en stijlregels direct toe.', featureAlternatives: 'Alternatieven vergelijken', featureAlternativesDesc: 'Genereer varianten zonder de huidige werkcontext te verliezen.', featureCapture: 'Overal vastleggen', featureCaptureDesc: 'Stuur geselecteerde tekst met een systeembrede sneltoets naar AbyssL.', featureSecure: 'Sleutels veilig bewaren', featureSecureDesc: 'API-sleutels blijven in veilige opslag, niet in gewone voorkeuren.',
      faqTitle: 'Goed om te weten.', faqCompatibilityQ: 'Werkt echt elke compatibele aanbieder?', faqCompatibilityA: 'Aanbieders implementeren compatibiliteitsstandaarden in verschillende mate. De ingebouwde test controleert je URL, authenticatie en model. Native Bedrock-, Vertex AI- of Azure IAM-methoden kunnen een compatibele gateway vereisen.', faqLocalQ: 'Kan AbyssL volledig met een lokaal model werken?', faqLocalA: 'Ja, als de lokale server een voldoende compatibel OpenAI Chat Completions-endpoint levert. Kwaliteit en functies hangen af van model en server.', faqDocsQ: 'Welke documenten kan ik verwerken?', faqDocsA: 'TXT, Markdown, AsciiDoc, HTML, RTF, PDF met extraheerbare tekst, DOCX en XLSX worden ondersteund; ODT vereist LibreOffice. Gescande PDF’s worden zonder OCR niet herkend.', faqDownloadQ: 'Waar kan ik AbyssL downloaden?', faqDownloadA: 'De ontwikkelversie en bouwinstructies staan op GitHub. Zodra er een officiële release is, biedt de website een directe, geverifieerde download.',
      finalTitle: 'Eén workflow voor tekst, taal en volledige documenten.', finalLead: 'Open source, transparant configureerbaar en open voor compatibele AI-aanbieders.', developer: 'Ontwikkeld door Daniel Mengel.'
    },
    hbs: {
      skip: 'Pređi na sadržaj', brandHome: 'AbyssL početna stranica', mainNav: 'Glavna navigacija', mobileNav: 'Mobilna navigacija', footerNav: 'Navigacija podnožja', navFunctions: 'Funkcije', navProviders: 'AI pružaoci', navDocs: 'Dokumentacija', themeLabel: 'Tema: automatski, isključeno ili uključeno', themeAuto: 'Auto', themeLight: 'Isklj.', themeDark: 'Uklj.', language: 'Jezik', github: 'Pogledaj na GitHubu', menu: 'Meni', threeAreas: 'Tri radna područja',
      translateTitle: 'Prevedi', translateRail: 'Prirodni prevodi uz stil i model po izboru.', correctTitle: 'Ispravi', correctRail: 'Precizno poboljšaj pravopis, stil i ton.', documentsTitle: 'Dokumenti', documentsRail: 'Obradi datoteke grupno i izvezi u uobičajene formate.',
      eyebrow: 'AbyssL desktop aplikacija', heroTitle: 'Prevedi. Poboljšaj. Obradi cijele dokumente.', heroLead: 'AbyssL objedinjuje prevođenje, ispravke i obradu dokumenata u desktop aplikaciji, uz AI pružaoce, gatewaye i lokalne servere putem OpenAI ili Anthropic kompatibilnih API-ja.', readDocs: 'Pročitaj dokumentaciju', trustChip: 'OpenAI kompatibilno · Anthropic kompatibilno · Cloud ili lokalno',
      translateHeading: 'Jasan radni prostor za precizne prevode.', translateAlt: 'AbyssL prikaz prevoda s njemačkim izvornim tekstom i engleskim prevodom', translateCaption: 'Upute, jezik, stil, automatski prevod i alternative ostaju na jednom mjestu.', correctHeading: 'Od nacrta do profesionalne verzije.', correctCopy: 'Ispravi pravopis, gramatiku, ton i stil direktnom uputom ili potpuno preformuliši tekst.', correctAlt: 'AbyssL prikaz ispravke s unosom i ispravljenim rezultatom', correctCaption: 'Ispravi ili preformuliši, uz jasan rezultat spreman za kopiranje.', documentsHeading: 'Pretvori cijelu mapu u kontrolisan radni tok.', documentsCopy: 'Dodaj datoteke ili mape, izaberi ispravku i prevod, postavi format i zajedno izvezi rezultate.', documentsAlt: 'AbyssL prikaz dokumenata sa zonom za datoteke i grupnom obradom', documentsCaption: 'Obradi TXT, Markdown, AsciiDoc, HTML, RTF, PDF, DOCX, XLSX i opcionalno ODT.',
      seamless: 'Povezan radni tok', workflowTitle: 'Jedan tekst. Tri koraka. Jedan dosljedan rezultat.', workflowStep1: 'Preuzmi i prevedi', workflowStep2: 'Doradi stil i ton', workflowStep3: 'Izvezi datoteke zajedno',
      providerEyebrow: 'Otvorena veza s pružaocima', providersTitle: 'Dva API formata. Slobodan izbor modela.', providersLead: 'Koristi kompatibilne cloud pružaoce, gatewaye ili lokalne modele. Bazni URL, model, autentikacija i timeout ostaju podesivi.', openAIFormat: 'OpenAI kompatibilni Chat Completions', openAIDesc: 'Za pružaoce i gatewaye koji nude OpenAI format.', anthropicFormat: 'Anthropic kompatibilni Messages', anthropicDesc: 'Za pružaoce i gatewaye s Anthropic kompatibilnim Messages endpointima.', cloud: 'Cloud', cloudDesc: 'Hostovani AI pružaoci', gateway: 'Gateway', gatewayDesc: 'Vlastiti ili upravljani proxyji', local: 'Lokalno', localDesc: 'Kompatibilni lokalni serveri',
      configEyebrow: 'Konfiguracija', configTitle: 'Odgovarajuća veza u nekoliko klikova.', configLead: 'Izaberi API format, unesi endpoint i testiraj vezu direktno u AbyssL-u.', connectionType: 'Vrsta veze', openAIShort: 'OpenAI kompatibilno', anthropicShort: 'Anthropic kompatibilno', localShort: 'Lokalno OpenAI kompatibilno', baseUrl: 'Bazni URL', auth: 'Autentikacija', modelId: 'ID modela', none: 'Nema', anthropicAlt: 'AbyssL postavke s Anthropic kompatibilnom vezom, x-api-key autentikacijom, modelom i praznim poljem API ključa', anthropicCaption: 'Anthropic kompatibilni bazni URL, model, autentikacija i verzija, bez vidljivog API ključa.',
      detailsEyebrow: 'Produktivno do detalja', featuresTitle: 'Manje prebacivanja. Više kontrole.', featureInstructions: 'Direktne upute', featureInstructionsDesc: 'Dodaj kontekst, terminologiju i stilska pravila direktno.', featureAlternatives: 'Uporedi alternative', featureAlternativesDesc: 'Generiši varijante bez gubitka trenutnog konteksta.', featureCapture: 'Globalno preuzimanje', featureCaptureDesc: 'Pošalji označeni tekst u AbyssL sistemskom prečicom.', featureSecure: 'Sigurno čuvanje ključeva', featureSecureDesc: 'API ključevi ostaju u sigurnoj pohrani, ne u običnim postavkama.',
      faqTitle: 'Dobro je znati.', faqCompatibilityQ: 'Radi li svaki kompatibilni pružalac?', faqCompatibilityA: 'Pružaoci primjenjuju standarde kompatibilnosti u različitoj mjeri. Ugrađeni test provjerava URL, autentikaciju i model. Izvorni Bedrock, Vertex AI ili Azure IAM postupci mogu zahtijevati kompatibilan gateway.', faqLocalQ: 'Može li AbyssL raditi potpuno s lokalnim modelom?', faqLocalA: 'Da, ako lokalni server nudi dovoljno kompatibilan OpenAI Chat Completions endpoint. Kvalitet i funkcije zavise od modela i servera.', faqDocsQ: 'Koje dokumente mogu obraditi?', faqDocsA: 'Podržani su TXT, Markdown, AsciiDoc, HTML, RTF, PDF s tekstom koji se može izdvojiti, DOCX i XLSX; ODT zahtijeva LibreOffice. Skenirani PDF-ovi se bez OCR-a ne prepoznaju.', faqDownloadQ: 'Gdje mogu preuzeti AbyssL?', faqDownloadA: 'Razvojna verzija i upute za izgradnju nalaze se na GitHubu. Kada službeno izdanje bude dostupno, stranica će ponuditi direktno i provjereno preuzimanje.',
      finalTitle: 'Jedan radni tok za tekst, jezike i cijele dokumente.', finalLead: 'Otvorenog koda, transparentno podesiv i otvoren za kompatibilne AI pružaoce.', developer: 'Razvio Daniel Mengel.'
    }
  };

  const metadata = {
    de: { title: 'AbyssL – Übersetzen, korrigieren und Dokumente verarbeiten', description: 'AbyssL bündelt Übersetzung, Korrektur und Dokumentverarbeitung in einer Desktop-App – mit OpenAI- oder Anthropic-kompatiblen APIs.' },
    en: { title: 'AbyssL – Translate, correct, and process documents', description: 'AbyssL combines translation, correction, and document processing in one desktop app—with OpenAI- or Anthropic-compatible APIs.' },
    fr: { title: 'AbyssL – Traduire, corriger et traiter des documents', description: 'AbyssL réunit traduction, correction et traitement de documents dans une application de bureau compatible OpenAI ou Anthropic.' },
    es: { title: 'AbyssL – Traduce, corrige y procesa documentos', description: 'AbyssL reúne traducción, corrección y procesamiento de documentos en una aplicación compatible con OpenAI o Anthropic.' },
    pt: { title: 'AbyssL – Traduza, corrija e processe documentos', description: 'O AbyssL reúne tradução, correção e processamento de documentos numa aplicação compatível com OpenAI ou Anthropic.' },
    it: { title: 'AbyssL – Traduci, correggi ed elabora documenti', description: 'AbyssL riunisce traduzione, correzione ed elaborazione documenti in un’app compatibile OpenAI o Anthropic.' },
    nl: { title: 'AbyssL – Vertaal, corrigeer en verwerk documenten', description: 'AbyssL combineert vertaling, correctie en documentverwerking in één OpenAI- of Anthropic-compatibele desktopapp.' },
    hbs: { title: 'AbyssL – Prevedi, ispravi i obradi dokumente', description: 'AbyssL objedinjuje prevođenje, ispravke i obradu dokumenata u OpenAI ili Anthropic kompatibilnoj desktop aplikaciji.' }
  };

  const safeStorage = {
    get(key) { try { return localStorage.getItem(key); } catch (_) { return null; } },
    set(key, value) { try { localStorage.setItem(key, value); return true; } catch (_) { return false; } }
  };

  function normalizeLanguage(value) {
    const raw = String(value || '').toLowerCase();
    const primary = raw.split('-')[0];
    return aliases[raw] || aliases[primary] || (supportedLanguages.includes(raw) ? raw : supportedLanguages.includes(primary) ? primary : null);
  }

  function detectLanguage() {
    const stored = normalizeLanguage(safeStorage.get(languageKey));
    if (stored) return stored;
    const candidates = navigator.languages?.length ? navigator.languages : [navigator.language];
    for (const candidate of candidates) {
      const normalized = normalizeLanguage(candidate);
      if (normalized) return normalized;
    }
    return 'en';
  }

  function applyLanguage(language) {
    const active = supportedLanguages.includes(language) ? language : 'en';
    const translations = copy[active];
    document.documentElement.lang = htmlLanguages[active] || active;
    document.querySelectorAll('[data-i18n]').forEach((element) => {
      const value = translations[element.dataset.i18n];
      if (value) element.textContent = value;
    });
    document.querySelectorAll('[data-i18n-aria]').forEach((element) => {
      const value = translations[element.dataset.i18nAria];
      if (value) element.setAttribute('aria-label', value);
    });
    document.querySelectorAll('[data-i18n-alt]').forEach((element) => {
      const value = translations[element.dataset.i18nAlt];
      if (value) element.setAttribute('alt', value);
    });
    document.querySelectorAll('[data-language-select]').forEach((select) => { select.value = active; });
    const meta = metadata[active] || metadata.en;
    document.title = meta.title;
    document.querySelector('meta[name="description"]')?.setAttribute('content', meta.description);
    document.querySelector('meta[property="og:title"]')?.setAttribute('content', meta.title);
    document.querySelector('meta[property="og:description"]')?.setAttribute('content', meta.description);
  }

  function initLanguage() {
    let language = detectLanguage();
    applyLanguage(language);
    document.querySelectorAll('[data-language-select]').forEach((select) => {
      select.addEventListener('change', () => {
        language = normalizeLanguage(select.value) || 'en';
        safeStorage.set(languageKey, language);
        applyLanguage(language);
      });
    });
  }

  const mediaDark = window.matchMedia('(prefers-color-scheme: dark)');

  function validTheme(value) { return value === 'auto' || value === 'light' || value === 'dark' ? value : 'auto'; }

  function applyTheme(preference, persist = false) {
    const selected = validTheme(preference);
    const resolved = selected === 'dark' || (selected === 'auto' && mediaDark.matches) ? 'dark' : 'light';
    document.documentElement.dataset.themePreference = selected;
    document.documentElement.dataset.theme = resolved;
    document.documentElement.style.colorScheme = resolved === 'light' ? 'only light' : 'dark';
    document.querySelectorAll('[data-theme-value]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.themeValue === selected));
    });
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', resolved === 'dark' ? '#0d1118' : '#ffffff');
    if (persist) safeStorage.set(themeKey, selected);
  }

  function initTheme() {
    const initial = validTheme(safeStorage.get(themeKey) || document.documentElement.dataset.themePreference);
    applyTheme(initial);
    document.querySelectorAll('[data-theme-value]').forEach((button) => {
      button.addEventListener('click', () => applyTheme(button.dataset.themeValue, true));
    });
    const onSystemChange = () => {
      if (document.documentElement.dataset.themePreference === 'auto') applyTheme('auto');
    };
    if (mediaDark.addEventListener) mediaDark.addEventListener('change', onSystemChange);
    else mediaDark.addListener(onSystemChange);
  }

  function initMenu() {
    const button = document.querySelector('.menu-button');
    const menu = document.getElementById('mobileMenu');
    if (!button || !menu) return;
    const close = () => { button.setAttribute('aria-expanded', 'false'); menu.hidden = true; };
    button.addEventListener('click', () => {
      const willOpen = button.getAttribute('aria-expanded') !== 'true';
      button.setAttribute('aria-expanded', String(willOpen));
      menu.hidden = !willOpen;
    });
    menu.querySelectorAll('a').forEach((link) => link.addEventListener('click', close));
    document.addEventListener('keydown', (event) => { if (event.key === 'Escape') close(); });
  }

  function initReveal() {
    const elements = document.querySelectorAll('.reveal');
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || !('IntersectionObserver' in window)) {
      elements.forEach((element) => element.classList.add('is-visible'));
      return;
    }
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.14 });
    elements.forEach((element) => observer.observe(element));
  }

  function initStory() {
    const story = document.querySelector('.story');
    const stages = [...document.querySelectorAll('[data-story-stage]')];
    const links = [...document.querySelectorAll('[data-stage-link]')];
    if (!story || !stages.length) return;

    const setActive = (name) => {
      stages.forEach((stage) => stage.classList.toggle('is-active', stage.dataset.storyStage === name));
      links.forEach((link) => {
        const active = link.dataset.stageLink === name;
        link.classList.toggle('is-active', active);
        if (active) link.setAttribute('aria-current', 'step');
        else link.removeAttribute('aria-current');
      });
    };

    if ('IntersectionObserver' in window) {
      const observer = new IntersectionObserver((entries) => {
        const visible = entries.filter((entry) => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (visible) setActive(visible.target.dataset.storyStage);
      }, { rootMargin: '-20% 0px -35% 0px', threshold: [0.15, 0.35, 0.6] });
      stages.forEach((stage) => observer.observe(stage));
    }

    let ticking = false;
    let storyVisible = true;
    const updateProgress = () => {
      const rect = story.getBoundingClientRect();
      const total = Math.max(1, rect.height - window.innerHeight);
      const progress = Math.max(0, Math.min(1, -rect.top / total));
      story.style.setProperty('--story-progress', `${(progress * 100).toFixed(1)}%`);
      ticking = false;
    };
    if ('IntersectionObserver' in window) {
      const visibilityObserver = new IntersectionObserver(([entry]) => {
        storyVisible = entry.isIntersecting;
        if (storyVisible) updateProgress();
      }, { rootMargin: '160px 0px' });
      visibilityObserver.observe(story);
    }
    window.addEventListener('scroll', () => {
      if (storyVisible && !ticking) { requestAnimationFrame(updateProgress); ticking = true; }
    }, { passive: true });
    updateProgress();
  }

  function initParallax() {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches || !window.matchMedia('(pointer: fine)').matches) return;
    document.querySelectorAll('[data-parallax]').forEach((frame) => {
      frame.addEventListener('pointermove', (event) => {
        const rect = frame.getBoundingClientRect();
        const x = ((event.clientX - rect.left) / rect.width - 0.5) * 2;
        const y = ((event.clientY - rect.top) / rect.height - 0.5) * 2;
        frame.style.setProperty('--parallax-x', `${(x * 1.4).toFixed(2)}deg`);
        frame.style.setProperty('--parallax-y', `${(-y * 1.1).toFixed(2)}deg`);
      });
      frame.addEventListener('pointerleave', () => {
        frame.style.setProperty('--parallax-x', '0deg');
        frame.style.setProperty('--parallax-y', '0deg');
      });
    });
  }

  function initProviderTabs() {
    const tabs = [...document.querySelectorAll('[data-provider-tab]')];
    const panels = [...document.querySelectorAll('[data-provider-panel]')];
    const activate = (name, focus = false) => {
      tabs.forEach((tab) => {
        const active = tab.dataset.providerTab === name;
        tab.setAttribute('aria-selected', String(active));
        tab.tabIndex = active ? 0 : -1;
        if (active && focus) tab.focus();
      });
      panels.forEach((panel) => { panel.hidden = panel.dataset.providerPanel !== name; });
    };
    tabs.forEach((tab, index) => {
      tab.addEventListener('click', () => activate(tab.dataset.providerTab));
      tab.addEventListener('keydown', (event) => {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
        event.preventDefault();
        const offset = event.key === 'ArrowRight' ? 1 : -1;
        const next = tabs[(index + offset + tabs.length) % tabs.length];
        activate(next.dataset.providerTab, true);
      });
    });
    activate('openai');
  }

  initTheme();
  initLanguage();
  initMenu();
  initReveal();
  initStory();
  initParallax();
  initProviderTabs();
})();
