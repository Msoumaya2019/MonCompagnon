//
//  LearningCoverage.swift
//  LearningKit
//
//  Ce qu'un groupe du Coran — sourate, juz', hizb — a de connu.
//

import QuranKit

/// L'état d'un groupe du Coran au regard de ce qui est appris.
///
/// Trois cas, et **ce ne sont pas** ceux de `LearningStatus`. Celui-ci dit où en est un *passage
/// dans son cycle de révision* ; celui-là dit *quelle fraction d'un groupe est couverte*. Un groupe
/// dont tous les passages sont dus est entièrement connu **et** à revoir en même temps — les
/// confondre ferait clignoter les pastilles au gré des échéances.
public enum LearningCoverage: String, CaseIterable, Sendable {
    /// Aucun verset du groupe n'est appris.
    case inconnue
    /// Une partie des versets du groupe est apprise.
    case partielle
    /// Tous les versets du groupe sont appris.
    case complete
}

/// Ce qui est appris, prêt à répondre pour n'importe quel groupe du Coran.
///
/// Une liste affiche cent quatorze sourates, soixante hizb ou trente juz' d'un coup. Interroger le
/// programme pour chacune — en reparcourant ses passages à chaque fois — referait le même travail
/// des centaines de fois par rendu. Le relevé le fait **une fois** : il rassemble les versets
/// appris, puis chaque question n'est plus qu'un parcours des versets du groupe.
///
/// **Deux sources, et non une.** Un intervalle déclaré connu dans le profil ne devient jamais un
/// passage : le planificateur le retranche de l'objectif, précisément parce qu'il n'y a rien à y
/// apprendre. Le lire dans le seul programme ferait donc apparaître comme inconnue une sourate que
/// l'utilisateur a déclarée connue — c'est le piège que ce relevé existe pour éviter.
public struct LearningCoverageReport: Sendable {
    // MARK: Lifecycle

    /// Relève ce qui est appris, du profil et du programme réunis.
    public init(profile: LearningProfile, program: LearningProgram, quran: Quran = .hafsMadani1405) {
        var learned: Set<AyahNumber> = []

        // Déclaré connu : solide **comme** fragile. « Je l'oublie » reste « je le connais » — la
        // solidité ne décide que de ce qu'on programme, jamais de ce qu'on sait.
        for known in profile.knownRanges {
            guard let bounds = known.range.bounds(in: quran) else { continue }
            learned.formUnion(bounds.first.array(to: bounds.last))
        }

        // Appris au fil du programme. L'état **enregistré** décide, et non l'état du jour : un
        // passage dont la révision est due reste appris.
        for item in program.items where item.storedStatus != .notLearned {
            guard let bounds = item.range.bounds(in: quran) else { continue }
            learned.formUnion(bounds.first.array(to: bounds.last))
        }

        self.learned = learned
    }

    // MARK: Public

    /// Le nombre de versets du groupe qui sont appris.
    public func coveredVerses(of group: some QuranGroup) -> Int {
        let verses = group.verses
        return verses.reduce(0) { $0 + (learned.contains($1) ? 1 : 0) }
    }

    /// Le nombre de versets du groupe.
    public func verseCount(of group: some QuranGroup) -> Int {
        group.verses.count
    }

    /// L'état du groupe : inconnu, partiel ou complet.
    ///
    /// Un groupe sans verset est **inconnu** plutôt que complet : un groupe vide n'est pas quelque
    /// chose qu'on sait, et le déclarer complet afficherait une coche sans contenu.
    public func coverage(of group: some QuranGroup) -> LearningCoverage {
        let verses = group.verses
        guard !verses.isEmpty else { return .inconnue }

        let covered = verses.reduce(0) { $0 + (learned.contains($1) ? 1 : 0) }
        if covered == 0 { return .inconnue }
        return covered == verses.count ? .complete : .partielle
    }

    // MARK: Private

    /// Les versets appris, quelle que soit la façon dont ils l'ont été.
    private let learned: Set<AyahNumber>
}
