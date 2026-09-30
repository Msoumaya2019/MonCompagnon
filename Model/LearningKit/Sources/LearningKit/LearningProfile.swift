//
//  LearningProfile.swift
//  LearningKit
//
//  Le profil d'apprentissage issu de la configuration guidée.
//

import Foundation
import QuranKit

/// L'allure à laquelle on veut avancer.
///
/// Quatre rythmes qui portent leur propre nombre, et un cinquième qui n'en porte aucun :
/// « personnalisé » tire son chiffre du **profil**, parce qu'une allure est une valeur simple qui
/// doit rester `Codable` sans cas particulier, et que le nombre, lui, doit survivre au disque.
public enum LearningPace: String, Codable, CaseIterable, Sendable {
    /// Un ou deux versets par séance — pour ne jamais se décourager.
    case tresDoux
    /// Trois versets environ par séance.
    case doux
    /// Une page environ par séance.
    case regulier
    /// Un rubu' ou plus par séance.
    case soutenu
    /// Le nombre de versets par séance est fixé par l'utilisateur.
    case personnalise

    // MARK: Public

    /// Nombre de versets visés par séance, ou `nil` quand c'est à l'utilisateur de le dire.
    ///
    /// Exprimé en versets plutôt qu'en pages : c'est l'unité la plus fine, donc tous les rythmes
    /// deviennent comparables et le calcul de dates reste exact.
    ///
    /// - Note: `.personnalise` ne rend **rien**, et c'est délibéré. Une valeur de repli se ferait
    ///   passer pour le choix de l'utilisateur ; c'est `LearningProfile.versesPerSession` qui
    ///   tranche, en lisant la valeur que le profil porte.
    public var versesPerSession: Int? {
        switch self {
        case .tresDoux: return 2
        case .doux: return 3
        case .regulier: return 8
        case .soutenu: return 20
        case .personnalise: return nil
        }
    }
}

/// Un jour de la semaine où l'on travaille.
public enum LearningDay: String, Codable, CaseIterable, Sendable {
    case lundi, mardi, mercredi, jeudi, vendredi, samedi, dimanche

    // MARK: Public

    /// Index `Calendar` (1 = dimanche … 7 = samedi).
    public var calendarWeekday: Int {
        switch self {
        case .dimanche: return 1
        case .lundi: return 2
        case .mardi: return 3
        case .mercredi: return 4
        case .jeudi: return 5
        case .vendredi: return 6
        case .samedi: return 7
        }
    }

    /// Nombre de séances par semaine pour un ensemble de jours.
    public static func sessionsPerWeek(for days: Set<LearningDay>) -> Int {
        max(1, days.count)
    }
}

/// Un intervalle du Coran, bornes incluses, tel qu'un utilisateur le désigne.
///
/// Volontairement plus large qu'une simple paire de versets : « je connais déjà Juz 'Amma » est
/// aussi naturel à exprimer que « je connais 78:1 → 78:40 ». La quantité en versets est calculée
/// à partir du `Quran`, jamais stockée.
public struct QuranRange: Codable, Equatable, Hashable, Sendable {
    // MARK: Lifecycle

    public init(firstSura: Int, firstAyah: Int, lastSura: Int, lastAyah: Int) {
        self.firstSura = firstSura
        self.firstAyah = firstAyah
        self.lastSura = lastSura
        self.lastAyah = lastAyah
    }

    /// Construit l'intervalle couvert par un groupe du Coran (sourate, juz', hizb, page…).
    public init(_ group: some QuranGroup) {
        let first = group.firstVerse
        let last = group.lastVerse
        self.init(
            firstSura: first.sura.suraNumber,
            firstAyah: first.ayah,
            lastSura: last.sura.suraNumber,
            lastAyah: last.ayah
        )
    }

    /// Construit l'intervalle qui couvre le mushaf entier.
    ///
    /// Les bornes sont **lues** dans le mushaf plutôt que codées en dur : c'est ce qui rend
    /// « tout le Coran » correct sur un autre mushaf que celui de référence, où la dernière
    /// sourate n'a pas forcément six versets.
    ///
    /// - Note: `Quran` ne conforme pas à `QuranGroup`, d'où cette surcharge plutôt qu'un cas de
    ///   plus dans l'initialiseur générique.
    public init(_ quran: Quran) {
        let first = quran.firstVerse
        let last = quran.lastVerse
        self.init(
            firstSura: first.sura.suraNumber,
            firstAyah: first.ayah,
            lastSura: last.sura.suraNumber,
            lastAyah: last.ayah
        )
    }

    // MARK: Public

    public let firstSura: Int
    public let firstAyah: Int
    public let lastSura: Int
    public let lastAyah: Int

    /// Les bornes sous forme d'`AyahNumber`, ou `nil` si elles n'existent pas dans ce mushaf.
    public func bounds(in quran: Quran) -> (first: AyahNumber, last: AyahNumber)? {
        guard
            let first = AyahNumber(quran: quran, sura: firstSura, ayah: firstAyah),
            let last = AyahNumber(quran: quran, sura: lastSura, ayah: lastAyah),
            first <= last
        else {
            return nil
        }
        return (first, last)
    }

    /// Nombre de versets couverts, dans un mushaf donné. `0` si l'intervalle est invalide.
    public func verseCount(in quran: Quran) -> Int {
        guard let bounds = bounds(in: quran) else { return 0 }
        return bounds.first.array(to: bounds.last).count
    }

    /// La quantité correspondante, dans l'unité la plus lisible.
    public func amount(in quran: Quran) -> QuranAmount {
        QuranAmount(verses: verseCount(in: quran), quran: quran)
    }
}

/// Ce que l'utilisateur connaît déjà — étape 2 de la configuration guidée.
public struct KnownRange: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(id: UUID = UUID(), range: QuranRange, label: String?, solidity: Solidity) {
        self.id = id
        self.range = range
        self.label = label
        self.solidity = solidity
    }

    // MARK: Public

    /// Solidité déclarée par l'utilisateur.
    ///
    /// Ce n'est pas un ornement : elle détermine si l'intervalle est **exclu** du programme
    /// (`.solide`) ou seulement **allégé** en révisions (`.fragile`).
    public enum Solidity: String, Codable, Sendable {
        /// Je le récite sans hésiter — ne pas le programmer.
        case solide
        /// Je le connais mais je l'oublie — le garder en révision espacée.
        case fragile
    }

    public let id: UUID
    public let range: QuranRange
    /// Nom lisible (« Juz 'Amma », « Al-Fatiha ») — purement informatif.
    public let label: String?
    public let solidity: Solidity
}

/// Ce que l'utilisateur veut apprendre — étape 3.
public struct LearningGoal: Codable, Equatable, Identifiable, Sendable {
    // MARK: Lifecycle

    public init(id: UUID = UUID(), range: QuranRange, label: String?, targetDate: Date?) {
        self.id = id
        self.range = range
        self.label = label
        self.targetDate = targetDate
    }

    // MARK: Public

    public let id: UUID
    public let range: QuranRange
    public let label: String?
    /// Échéance souhaitée, si l'utilisateur en a fixé une.
    public let targetDate: Date?
}

/// Le profil complet d'apprentissage.
public struct LearningProfile: Codable, Equatable, Sendable {
    // MARK: Lifecycle

    public init(
        knownRanges: [KnownRange] = [],
        goals: [LearningGoal] = [],
        pace: LearningPace = .regulier,
        customVersesPerSession: Int? = nil,
        days: Set<LearningDay> = Set(LearningDay.allCases),
        sessionMinutes: Int = 15,
        createdAt: Date = Date(),
        isConfigured: Bool = false
    ) {
        self.knownRanges = knownRanges
        self.goals = goals
        self.pace = pace
        self.customVersesPerSession = customVersesPerSession
        self.days = days
        self.sessionMinutes = sessionMinutes
        self.createdAt = createdAt
        self.isConfigured = isConfigured
    }

    // MARK: Public

    /// Le repli quand aucune valeur n'est disponible : le rythme de l'allure régulière.
    ///
    /// Un profil relu d'un disque abîmé peut porter `.personnalise` sans nombre. Ce repli évite
    /// alors un programme d'un verset par séance — sans jamais se faire passer pour un choix :
    /// la configuration, elle, en pose toujours un.
    public static let fallbackVersesPerSession = 8

    public var knownRanges: [KnownRange]
    public var goals: [LearningGoal]
    public var pace: LearningPace

    /// Le nombre de versets par séance choisi par l'utilisateur, quand l'allure est `.personnalise`.
    ///
    /// Conservé même lorsque l'allure change : quelqu'un qui essaie « soutenu » puis revient à
    /// « personnalisé » doit retrouver son nombre, pas un nombre oublié.
    public var customVersesPerSession: Int?

    public var days: Set<LearningDay>
    public var sessionMinutes: Int
    public let createdAt: Date
    /// `false` tant que la configuration guidée n'a pas été terminée — pilote l'affichage du
    /// parcours d'accueil plutôt que du tableau de bord.
    public var isConfigured: Bool

    /// Un profil vierge, avant toute configuration.
    public static var empty: LearningProfile { LearningProfile() }

    /// Le nombre de versets visés par séance — la valeur personnalisée si elle s'applique.
    ///
    /// C'est **la** source du rythme : le planificateur lit ce nombre et jamais
    /// `LearningPace.versesPerSession` directement, sans quoi une allure personnalisée serait
    /// ignorée au profit du repli.
    ///
    /// La valeur personnalisée ne s'applique **qu'à** `.personnalise` : sur une allure fixe, c'est
    /// l'allure qui décide. Autrement, un nombre resté d'un essai précédent se ferait passer pour
    /// le rythme choisi.
    public var versesPerSession: Int {
        if pace == .personnalise, let custom = customVersesPerSession, custom > 0 {
            return custom
        }
        return pace.versesPerSession ?? Self.fallbackVersesPerSession
    }

    /// Les intervalles à ne pas programmer : ceux déclarés solides.
    public var solidRanges: [QuranRange] {
        knownRanges.filter { $0.solidity == .solide }.map(\.range)
    }

    /// Les intervalles à garder en révision : ceux déclarés fragiles.
    public var fragileRanges: [QuranRange] {
        knownRanges.filter { $0.solidity == .fragile }.map(\.range)
    }

    /// Vrai si au moins un jour de travail est choisi.
    public var hasWorkingDays: Bool { !days.isEmpty }
}
