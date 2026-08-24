# WisperClone

**Parla. È già scritto.**

WisperClone è una dettatura push-to-talk nativa per macOS 26. Tieni premuto un tasto, parla e rilascialo: il testo viene trascritto sul dispositivo, ripulito e inserito nel campo attivo.

## Privacy

Il percorso predefinito è completamente locale:

- `SpeechAnalyzer` / `SpeechTranscriber` di Apple trascrive sul Mac;
- il modello vocale viene gestito e scaricato da macOS quando necessario;
- il formatter deterministico non usa la rete;
- la pulizia intelligente opzionale usa Apple Foundation Models sul dispositivo;
- audio e trascrizioni non vengono salvati;
- non sono presenti integrazioni con Wispr Flow, OpenAI, Anthropic o altri servizi cloud.

Il dizionario personale è l'unico contenuto persistente ed è conservato in:

```text
~/Library/Application Support/WisperClone/dictionary.txt
```

## Requisiti

- macOS 26 o successivo
- Xcode 26 o successivo
- autorizzazioni Microfono e Accessibilità

Il Mac di sviluppo usa Xcode installato in `/Applications/Xcode.app`, mentre la selezione globale può puntare alle sole Command Line Tools. In quel caso:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build
```

## Avvio rapido

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make install
```

`make app` usa un certificato Developer ID quando è disponibile e altrimenti una firma ad hoc. Con la firma ad hoc macOS può richiedere nuovamente Accessibilità dopo una ricompilazione; una firma Developer ID stabile evita questo limite.

Alla prima apertura l'onboarding di WisperClone:

1. spiega il funzionamento locale;
2. guida la concessione di Accessibilità e Microfono;
3. permette di scegliere il tasto push-to-talk;
4. porta direttamente alla prima dettatura.

## Architettura

```text
HotkeyMonitor (CGEventTap)
        ↓
DictationController
   ├── AudioCapture (AVAudioEngine)
   ├── AppleSpeechEngine (SpeechAnalyzer)
   ├── RuleBasedFormatter / FoundationModelFormatter
   ├── DictionaryStore
   ├── TextInjector (AX, fallback clipboard)
   └── HUDPanel non attivante
```

Dettagli fondamentali:

- il pannello HUD non diventa mai key window e non sottrae il focus;
- il tap globale distingue i modificatori destri e osserva pressione/rilascio;
- i buffer audio vengono copiati e consegnati al motore in ordine;
- l'inserimento Accessibility viene verificato prima del fallback clipboard;
- bundle ID e firma rimangono stabili per preservare i permessi TCC.

## Verifica

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --scratch-path "$HOME/Library/Caches/WisperCloneBuild/tests"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make app
codesign --verify --deep --strict "$HOME/Library/Caches/WisperCloneBuild/WisperClone.app"
```

La validazione end-to-end voce → testo richiede una prova manuale con microfono reale in TextEdit, Note, browser e applicazioni Electron.

Il nome tecnico e quello mostrato all'utente restano WisperClone, così bundle ID, permessi TCC e dati delle installazioni precedenti rimangono coerenti.
