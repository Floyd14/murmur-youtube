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

    @Test("gestisce maiuscole Unicode che si espandono in più caratteri")
    func uppercaseExpansion() async {
        let output = await formatter.format("ßeta")
        #expect(output == "SSeta.")
    }

    @Test("mantiene i grafemi Unicode composti a inizio frase")
    func composedUnicodeGrapheme() async {
        let output = await formatter.format("e\u{301}lan nuova riga ßeta")
        #expect(output == "E\u{301}lan\nSSeta.")
    }
}
