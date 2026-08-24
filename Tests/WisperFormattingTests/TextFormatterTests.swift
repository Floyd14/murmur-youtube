import Testing
@testable import WisperFormatting

struct TextFormatterTests {
    private let formatter = RuleBasedFormatter()

    @Test("rimuove esitazioni e interpreta i comandi italiani")
    func italianCleanup() async {
        let output = await formatter.format("ehm ciao nuova riga come stai")
        #expect(output == "Ciao\nCome stai.")
    }

    @Test("supporta anche i comandi inglesi")
    func englishCleanup() async {
        let output = await formatter.format("um hello new paragraph how are you")
        #expect(output == "Hello\n\nHow are you.")
    }

    @Test("non altera un testo già punteggiato")
    func preservesPunctuation() async {
        let output = await formatter.format("questa frase è già pronta!")
        #expect(output == "Questa frase è già pronta!")
    }
}
