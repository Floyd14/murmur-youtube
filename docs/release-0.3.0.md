# WisperClone 0.3.0

> **Aggiornamento successivo:** la 0.3.0 è crashata al primo callback audio reale alle 20:54:19 dell’11 settembre. I controlli riportati sotto sono storici e non attestano il funzionamento della dettatura. La causa è una closure AVAudio che ereditava il MainActor, invocata dalla coda audio. La correzione e le nuove verifiche sono descritte nella [release 0.3.1](release-0.3.1.md). Il rapporto macOS grezzo rimane locale.

Stato: versione pubblicata e installata, firma verificata e registrazione al login attiva. Vedi [audit dopo pubblicazione](audit-post-release-2026-09-11.md) per evidenze, ripristino dei permessi TCC e verifiche manuali rimanenti.

## Cosa cambia

- L'acquisizione audio entra nella coda prima dell'avvio completo del motore di trascrizione, riducendo la perdita del parlato immediato dopo Alt.
- Le sessioni brevi non vengono più scartate per una soglia fissa di 350 ms.
- Le code audio FIFO hanno capacità 512; un overflow interrompe la sessione con errore visibile invece di perdere buffer in silenzio.
- La conversione audio avviene fuori dal callback e il tail viene drenato al rilascio.
- L'esito dell'inserimento viene atteso. Se AX non conferma il risultato o l'operazione fallisce, l'HUD mostra l'errore e il testo resta copiabile dal menu per cinque minuti.
- La pulizia intelligente rifiuta risultati non strutturati o poco conservativi, applica un timeout e ricade sul formatter deterministico.
- Il dizionario usa una scrittura transazionale e due watcher per seguire sia sostituzioni sia modifiche dirette; la capitalizzazione supporta espansioni Unicode.
- L'avvio al login usa lo stato reale di `SMAppService.mainApp`. È disponibile dalle Impostazioni e non viene registrato automaticamente; `--enable-login-item` è una scelta esplicita.
- L'HUD mostra gli errori; l'indicatore di registrazione è rosso, senza gradiente.

## Verifica

La suite automatizzata ha superato 29 test in 8 suite. La build release è la 0.3.0 (build 12). Sono passati anche `make app` e `codesign --verify --deep --strict` sull'app assemblata. I test aggiunti per questa correzione e i test del dizionario hanno superato il controllo QA.

Il comportamento end-to-end con microfono reale, Alt fisico, autorizzazioni TCC, TextEdit, Note, browser, editor Electron e nuovo login a macOS resta da verificare manualmente. Il report di audit precedente documenta il baseline; questa nota descrive solo il comportamento della build corretta.

## Identità e rollback

La build mantiene l'identità `com.andreavisini.wisperclone.app`, l'eseguibile `WisperClone` e l'installazione in `/Applications/WisperClone.app`. Il rollback previsto è la copia firmata precedente, quando disponibile:

```text
/Users/andreavisini/Library/Caches/WisperCloneBuild/rollback/WisperClone-0.2.9.app
```

La pubblicazione è disponibile sul branch `feature/wisperclone-onboarding` con tag `wisperclone-v0.3.0`; i riscontri di pubblicazione e installazione sono riportati nell’audit dopo pubblicazione.
