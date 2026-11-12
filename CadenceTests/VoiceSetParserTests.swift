import Testing
@testable import Cadence

@Suite("Voice set parser")
struct VoiceSetParserTests {
    let kg = VoiceParseContext(unit: .kg, currentWeightKg: 40)
    let kgNoRow = VoiceParseContext(unit: .kg, currentWeightKg: nil)
    let lb = VoiceParseContext(unit: .lb, currentWeightKg: nil)

    func parse(_ s: String, _ c: VoiceParseContext? = nil) -> VoiceParseResult {
        VoiceSetParser.parse(s, context: c ?? kg)
    }

    func lbToKg(_ v: Double) -> Double { (WeightFormatter.kilograms(from: v, in: .lb) * 1000).rounded() / 1000 }

    // MARK: Full phrases

    @Test func kilosForReps() { let r = parse("45 kilos for 8 reps"); #expect(r.weightKg == 45); #expect(r.reps == 8); #expect(r.isComplete) }
    @Test func bareForm() { let r = parse("45 for 8"); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func numberWords() { let r = parse("forty five kg eight reps"); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func numberWordsNoSeparator() { let r = parse("forty five eight", kgNoRow); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func capitalsAndPunctuation() { let r = parse("45 Kilos, for 8 reps."); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func gluedUnit() { let r = parse("45kg 8 reps"); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func timesSign() { let r = parse("45 × 8"); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func letterX() { let r = parse("45 x 8"); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func repsFirst() { let r = parse("8 reps at 45 kilos"); #expect(r.weightKg == 45); #expect(r.reps == 8) }
    @Test func timesAsReps() { let r = parse("60 kilos 10 times"); #expect(r.weightKg == 60); #expect(r.reps == 10) }
    @Test func timesBetweenNumbers() { let r = parse("60 times 10"); #expect(r.weightKg == 60); #expect(r.reps == 10) }
    @Test func singularRep() { let r = parse("100 kilos for 1 rep"); #expect(r.weightKg == 100); #expect(r.reps == 1) }

    // MARK: Decimals and halves

    @Test func decimalDigits() { #expect(parse("42.5 kilos for 10").weightKg == 42.5) }
    @Test func decimalComma() { #expect(parse("42,5 kg 10 reps").weightKg == 42.5) }
    @Test func andAHalfWords() { #expect(parse("forty two and a half kilos for ten").weightKg == 42.5) }
    @Test func andAHalfDigits() { #expect(parse("42 and a half for 10").weightKg == 42.5) }
    @Test func pointFive() { #expect(parse("forty two point five kg ten reps").weightKg == 42.5) }
    @Test func pointTwoFive() { #expect(parse("twenty two point two five kilos 8 reps").weightKg == 22.25) }
    @Test func halfSymbol() { #expect(parse("42½ kg 8 reps").weightKg == 42.5) }

    // MARK: Big numbers

    @Test func hundredWords() { #expect(parse("one hundred and twenty kilos five reps").weightKg == 120) }
    @Test func aHundred() { #expect(parse("a hundred kilos for five").weightKg == 100) }
    @Test func gymShorthandPounds() {
        let r = parse("one thirty five pounds for five", lb)
        #expect(r.weightKg == lbToKg(135)); #expect(r.reps == 5)
    }
    @Test func shorthandNeedsUnit() {
        // "five twelve" without a unit is weight 5 and 12 reps, not 512.
        let r = parse("five twelve", kgNoRow)
        #expect(r.weightKg == 5); #expect(r.reps == 12)
    }

    // MARK: Relative weights

    @Test func sameWeight() { let r = parse("same weight 10 reps"); #expect(r.weightKg == 40); #expect(r.reps == 10) }
    @Test func sameWeightNoRow() { let r = parse("same weight 10 reps", kgNoRow); #expect(r.weightKg == nil); #expect(r.missing == [.weight]) }
    @Test func addKilos() { let r = parse("add 2.5 kilos 8 reps"); #expect(r.weightKg == 42.5); #expect(r.reps == 8) }
    @Test func addWords() { let r = parse("add two and a half kilos eight reps"); #expect(r.weightKg == 42.5); #expect(r.reps == 8) }
    @Test func plusBare() { let r = parse("plus 5 for 6"); #expect(r.weightKg == 45); #expect(r.reps == 6) }
    @Test func dropWeight() { let r = parse("drop 5 kilos 10 reps"); #expect(r.weightKg == 35); #expect(r.reps == 10) }
    @Test func addNoRow() { #expect(parse("add 2.5 kilos 8 reps", kgNoRow).missing == [.weight]) }

    // MARK: Reps only and bodyweight

    @Test func repsOnlyUsesRowWeight() { let r = parse("8 reps"); #expect(r.weightKg == 40); #expect(r.reps == 8); #expect(r.isComplete) }
    @Test func loneSmallNumberIsReps() { let r = parse("twelve"); #expect(r.reps == 12); #expect(r.weightKg == 40) }
    @Test func repsNoRowNeedsWeight() { let r = parse("8 reps", kgNoRow); #expect(r.reps == 8); #expect(r.missing == [.weight]) }
    @Test func bodyweight() { let r = parse("bodyweight 12"); #expect(r.weightKg == 0); #expect(r.isBodyweight); #expect(r.reps == 12) }
    @Test func bodyTwoWords() { let r = parse("body weight for 15 reps"); #expect(r.weightKg == 0); #expect(r.reps == 15) }
    @Test func repsOnlyExercise() {
        let c = VoiceParseContext(unit: .kg, currentWeightKg: nil, tracksWeight: false)
        let r = parse("fifteen", c)
        #expect(r.reps == 15); #expect(r.weightKg == nil); #expect(r.isComplete)
    }

    // MARK: Pounds

    @Test func pounds() { let r = parse("135 pounds for 5"); #expect(r.weightKg == lbToKg(135)); #expect(r.reps == 5) }
    @Test func lbs() { #expect(parse("95 lbs 10 reps").weightKg == lbToKg(95)) }
    @Test func bareNumberUsesUserUnit() { #expect(parse("135 for 5", lb).weightKg == lbToKg(135)) }
    @Test func kilosOverrideUserUnit() { #expect(parse("60 kilos for 5", lb).weightKg == 60) }

    // MARK: Missing and invalid

    @Test func missingReps() { let r = parse("45 kilos for"); #expect(r.weightKg == 45); #expect(r.missing == [.reps]) }
    @Test func weightOnlyBig() { let r = parse("60", kgNoRow); #expect(r.weightKg == 60); #expect(r.missing == [.reps]) }
    @Test func nothingHeard() { #expect(parse("um I don't know", kgNoRow).missing == [.weight, .reps]) }
    @Test func empty() { #expect(parse("", kgNoRow).missing == [.weight, .reps]) }
    @Test func fractionalRepsRejected() { #expect(parse("45 kilos for 8.5 reps").reps == nil) }
    @Test func tooHeavyRejected() { #expect(parse("5000 kilos for 5").weightKg == nil) }

    // MARK: Number reader

    @Test(arguments: [
        ("forty five", 45.0), ("twelve", 12), ("ninety nine", 99), ("one hundred", 100),
        ("two hundred and twenty five", 225), ("seven point five", 7.5), ("zero", 0),
    ])
    func numberReader(_ text: String, _ value: Double) {
        let words = VoiceSetParser.normalize(text)
        #expect(VoiceSetParser.readNumber(words, from: 0)?.0 == value)
    }
}
