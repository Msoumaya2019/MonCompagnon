//
//  LearningProgress.swift
//  LearningKit
//
//  Où l'utilisateur en est réellement, sourate par sourate.
//

import Foundation
import QuranKit

/// Ce qui a été appris dans une sourate, et où l'on en est.
///
/// `lastMemorizedVerse` est un **repère**, et non un journal : c'est le dernier verset appris d'un
/// trait. Tout verset qui le précède est appris *parce qu'il est avant lui*. C'est ce qui permet de
/// reprendre au verset suivant sans rien recompter — et donc de ne jamais accumuler de retard quand
/// des jours passent sans travail.
///
/// Le repère est un **numéro de verset dans la sourate**, et non un rang dans le mushaf : c'est
/// ainsi qu'un utilisateur en parle (« j'ai appris jusqu'au verset 16 »), et cela ne dépend pas du
/// mushaf choisi.
public struct SurahLearningProgress: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(
        surahId: Int,
        lastMemorizedVerse: Int,
        targetVerse: Int,
        startedAt: Date,
        updatedAt: Date
    ) {
        self.surahId = surahId
        self.lastMemorizedVerse = lastMemorizedVerse
        self.targetVerse = targetVerse
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    // MARK: Public

    /// Le numéro de la sourate — c'est aussi son identité dans la progression.
    public let surahId: Int

    /// Le dernier verset appris, bornes incluses. `0` si rien n'a encore été appris.
    ///
    /// Le zéro est un repère sûr : les versets d'une sourate sont numérotés à partir de 1.
    public let lastMemorizedVerse: Int

    /// Le dernier verset visé dans cette sourate, bornes incluses.
    ///
    /// Informatif : c'est la visée **enregistrée**, qui peut être plus lointaine que la visée
    /// courante si l'utilisateur a réduit son objectif. Le programme, lui, se règle sur les bornes
    /// de l'objectif, jamais sur ce champ.
    public let targetVerse: Int

    /// Premier jour où cette sourate a été travaillée.
    public let startedAt: Date

    /// Dernier jour où le repère a avancé.
    public let updatedAt: Date

    public var id: Int { surahId }

    /// Vrai si le repère couvre ce verset.
    ///
    /// Un verset antérieur au repère est réputé appris : le repère avance d'un trait, il ne saute
    /// pas de verset. Interroger un verset qu'aucun objectif ne couvre ne peut donc rien fausser,
    /// puisque le programme ne contient que les versets visés.
    ///
    /// - Important: cette affirmation n'est vraie que parce que le relevé la **vérifie** :
    ///   `LearningProgress.init(of:in:)` ne pose un repère que si le bloc appris part réellement du
    ///   verset 1. Un programme parcouru à rebours apprend une fin de sourate, et laisse donc le
    ///   repère à 0 — sans quoi des versets jamais travaillés passeraient pour appris, et ne
    ///   seraient plus jamais proposés.
    public func covers(verse ayah: Int) -> Bool {
        ayah >= 1 && ayah <= lastMemorizedVerse
    }

    // MARK: Internal

    /// Le relevé le plus avancé des deux, pour une même sourate.
    ///
    /// La progression ne recule jamais : fusionner garde le repère le plus avancé, la visée la plus
    /// lointaine, le premier commencement et le dernier passage.
    func merging(_ other: SurahLearningProgress) -> SurahLearningProgress {
        SurahLearningProgress(
            surahId: surahId,
            lastMemorizedVerse: max(lastMemorizedVerse, other.lastMemorizedVerse),
            targetVerse: max(targetVerse, other.targetVerse),
            startedAt: min(startedAt, other.startedAt),
            updatedAt: max(updatedAt, other.updatedAt)
        )
    }
}

/// Où en est l'utilisateur, sourate par sourate.
///
/// C'est un **relevé**, et il ne recule jamais : deux relevés fusionnés gardent, pour chaque
/// sourate, le repère le plus avancé. C'est ce qui permet à un objectif retiré puis rajouté de
/// reprendre là où il s'était arrêté, là où un programme régénéré seul ne le saurait pas.
public struct LearningProgress: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    /// Construit un relevé à partir de ses enregistrements.
    ///
    /// Deux enregistrements d'une même sourate sont **fusionnés** plutôt que refusés : un relevé
    /// relu d'un appareil ne doit jamais faire échouer le décodage, et le repère le plus avancé est
    /// de toute façon celui qui a raison.
    public init(surahs: [SurahLearningProgress] = []) {
        var bySurah: [Int: SurahLearningProgress] = [:]
        for record in surahs {
            bySurah[record.surahId] = bySurah[record.surahId].map { $0.merging(record) } ?? record
        }
        self.surahs = bySurah.values.sorted { $0.surahId < $1.surahId }
    }

    /// Relève la progression portée par un programme.
    ///
    /// Pour chaque sourate, le repère est le plus grand `k` tel que **tous** les versets `1..k`
    /// soient couverts par un passage appris du premier bloc continu. S'arrêter au premier passage
    /// non appris est ce qui rend le relevé honnête : un passage appris plus loin — parce qu'on l'a
    /// sauté — ne fait pas passer pour appris ce qui le précède. Et exiger que le bloc **parte du
    /// début** de la sourate est ce qui le rend vrai quel que soit le sens de parcours : à rebours,
    /// on apprend une *fin* de sourate, et l'annoncer comme un début ferait passer pour appris des
    /// versets jamais travaillés.
    ///
    /// Un passage peut chevaucher une fin de sourate : ses versets sont alors répartis entre les
    /// sourates qu'il traverse, chacune recevant l'étendue qui la concerne.
    public init(of program: LearningProgram, in quran: Quran) {
        var readings: [Int: [Reading]] = [:]
        var order: [Int] = []

        for item in program.items {
            guard let bounds = item.range.bounds(in: quran) else { continue }
            let learned = item.storedStatus != .notLearned
            let workedAt = item.lastWorkedAt ?? program.generatedAt ?? Date()
            for span in Self.surahSpans(of: bounds, in: quran) {
                if readings[span.surahId] == nil { order.append(span.surahId) }
                readings[span.surahId, default: []].append(
                    Reading(firstAyah: span.first, lastAyah: span.last, isLearned: learned, workedAt: workedAt)
                )
            }
        }

        self.init(surahs: order.compactMap { Self.record(forSurah: $0, readings: readings[$0] ?? []) })
    }

    /// Le relevé tel qu'il doit être relu.
    ///
    /// Le décodage passe par `init(surahs:)` : c'est ce qui garantit qu'un relevé relu est trié et
    /// sans doublon, quelle que soit la forme du JSON enregistré.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(surahs: try container.decode([SurahLearningProgress].self))
    }

    // MARK: Public

    /// Les enregistrements, rangés par numéro de sourate.
    public let surahs: [SurahLearningProgress]

    /// Un relevé vierge, avant tout apprentissage.
    public static var empty: LearningProgress { LearningProgress() }

    /// Vrai tant que rien n'a été relevé.
    public var isEmpty: Bool { surahs.isEmpty }

    /// L'enregistrement d'une sourate, ou `nil` si elle n'a jamais été travaillée.
    public func record(forSurah surahId: Int) -> SurahLearningProgress? {
        surahs.first { $0.surahId == surahId }
    }

    /// Le dernier verset appris dans une sourate. `0` si elle n'a jamais été travaillée.
    public func lastMemorizedVerse(inSurah surahId: Int) -> Int {
        record(forSurah: surahId)?.lastMemorizedVerse ?? 0
    }

    /// Le relevé le plus avancé des deux, sourate par sourate.
    ///
    /// Enregistrer un programme ne doit jamais effacer l'avancement d'un objectif qui n'y figure
    /// plus : c'est cette fusion qui fait survivre la progression d'un objectif retiré, et qui
    /// permet de le rajouter plus tard sans repartir de zéro.
    public func merging(_ other: LearningProgress) -> LearningProgress {
        LearningProgress(surahs: surahs + other.surahs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(surahs)
    }

    // MARK: Internal

    /// Vrai si tous les versets de l'intervalle sont appris, d'après le relevé.
    func covers(_ offsets: ClosedRange<Int>, in index: QuranVerseIndex) -> Bool {
        for offset in offsets {
            // `entry` et non `record` : un local nommé `record` masquerait la méthode `record(forSurah:)`
            // dans son propre initialiseur, ce que Swift refuse.
            guard let verse = index.verse(at: offset) else { return false }
            guard let entry = record(forSurah: verse.sura.suraNumber) else { return false }
            guard entry.covers(verse: verse.ayah) else { return false }
        }
        return true
    }

    /// La date à laquelle l'intervalle a été appris, ou `nil` s'il ne l'est pas.
    ///
    /// La plus **ancienne** des sourates traversées : une révision due ne doit jamais être repoussée
    /// du fait qu'un passage chevauche deux sourates travaillées à des dates différentes. C'est la
    /// même règle que celle de la reprise de progression, et pour la même raison.
    func learnedAt(_ offsets: ClosedRange<Int>, in index: QuranVerseIndex) -> Date? {
        guard covers(offsets, in: index) else { return nil }
        var dates: [Date] = []
        for offset in offsets {
            guard let verse = index.verse(at: offset) else { continue }
            guard let entry = record(forSurah: verse.sura.suraNumber) else { continue }
            dates.append(entry.updatedAt)
        }
        return dates.min()
    }

    // MARK: Private

    /// Ce qu'un passage dit d'une sourate : l'étendue qu'il y couvre, et s'il est appris.
    ///
    /// L'étendue, et non seulement sa fin : sans le premier verset, on ne peut pas dire si le bloc
    /// appris part du début de la sourate — et c'est précisément ce qui décide si le repère a le
    /// droit d'être un préfixe.
    private struct Reading {
        let firstAyah: Int
        let lastAyah: Int
        let isLearned: Bool
        let workedAt: Date
    }

    /// L'enregistrement d'une sourate, bâti sur les passages qui la traversent, dans leur ordre.
    private static func record(forSurah surahId: Int, readings: [Reading]) -> SurahLearningProgress? {
        guard let first = readings.first else { return nil }

        // Le repère s'arrête au premier passage non appris : c'est ce qui en fait un bloc continu,
        // et non le plus lointain des versets travaillés.
        var covered: Set<Int> = []
        var worked: [Date] = []
        for reading in readings {
            guard reading.isLearned else { break }
            covered.formUnion(reading.firstAyah ... reading.lastAyah)
            worked.append(reading.workedAt)
        }

        // Puis il ne retient que le début ininterrompu de ce bloc. `covers(verse:)` affirme que
        // tout verset jusqu'au repère est appris, et cette affirmation ne vaut que si le bloc
        // commence au verset 1 : un objectif qui part au milieu d'une sourate, ou qui la parcourt à
        // rebours, n'apprend pas un début. Le repère reste alors à 0, et c'est la reprise verset par
        // verset qui porte le travail fait.
        var watermark = 0
        while covered.contains(watermark + 1) {
            watermark += 1
        }

        // Les dates ne portent que sur ce qui est appris. Y compter un passage jamais travaillé
        // ferait passer pour un jour de travail le jour où le programme a été régénéré — et la
        // série de jours consécutifs s'en trouverait gonflée.
        let dates = worked.isEmpty ? [first.workedAt] : worked
        return SurahLearningProgress(
            surahId: surahId,
            lastMemorizedVerse: watermark,
            targetVerse: readings.map(\.lastAyah).max() ?? first.lastAyah,
            startedAt: dates.min() ?? first.workedAt,
            updatedAt: dates.max() ?? first.workedAt
        )
    }

    /// Les étendues couvertes par un intervalle, une par sourate traversée.
    ///
    /// Un passage qui s'arrête au milieu d'une sourate n'en couvre qu'une fin ; un passage qui la
    /// traverse en couvre une par sourate, la première et la dernière pouvant être partielles.
    private static func surahSpans(
        of bounds: (first: AyahNumber, last: AyahNumber),
        in quran: Quran
    ) -> [(surahId: Int, first: Int, last: Int)] {
        let firstSurah = bounds.first.sura.suraNumber
        let lastSurah = bounds.last.sura.suraNumber
        guard firstSurah != lastSurah else {
            return [(surahId: firstSurah, first: bounds.first.ayah, last: bounds.last.ayah)]
        }

        return quran.suras
            .filter { $0.suraNumber >= firstSurah && $0.suraNumber <= lastSurah }
            .map { sura -> (surahId: Int, first: Int, last: Int) in
                // Les étiquettes sont posées explicitement : la conversion d'un tuple non étiqueté
                // vers un tuple étiqueté n'est pas garantie dans un `map`, dont le type de retour
                // est inféré avant d'être confronté à celui de la fonction.
                let start = sura.suraNumber == firstSurah ? bounds.first.ayah : 1
                let end = sura.suraNumber == lastSurah ? bounds.last.ayah : sura.lastVerse.ayah
                return (surahId: sura.suraNumber, first: start, last: end)
            }
    }
}
