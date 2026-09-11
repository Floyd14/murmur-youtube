import Testing
@testable import WisperClone

struct CleanupValidatorTests {
    @Test func preservesPunctuationAndHesitations() {
        #expect(CleanupValidator.preservesWords(original: "ehm non pagare 200 euro", cleaned: "Non pagare 200 euro."))
    }

    @Test func rejectsLossNegationAndReordering() {
        #expect(!CleanupValidator.preservesWords(original: "non pagare 200 euro", cleaned: "Pagare 200 euro."))
        #expect(!CleanupValidator.preservesWords(original: "manda oggi il documento a Luca", cleaned: "Manda il documento."))
        #expect(!CleanupValidator.preservesWords(original: "Luca chiama Andrea", cleaned: "Andrea chiama Luca."))
        #expect(!CleanupValidator.preservesWords(original: "paga 200 euro", cleaned: "Paga 300 euro."))
    }
}
