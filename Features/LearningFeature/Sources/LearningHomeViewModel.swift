//
//  LearningHomeViewModel.swift
//  LearningFeature
//
//  Où en est l'utilisateur dans son programme d'apprentissage.
//

import Combine
import Foundation
import LearningKit
import LearningPersistence
import QuranKit
import QuranLocalization

/// Où en est l'utilisateur dans son programme d'apprentissage.
///
/// Le modèle de vue ne décide de rien : il lit le profil et le programme, et laisse à `LearningKit`
/// le soin de dire où en est l'utilisateur — l'état d'un passage, les révisions dues, la série.
/// C'est ce qui permet d'éprouver ces règles sans interface.
@MainActor
final class LearningHomeViewModel: ObservableObject {
    // MARK: Lifecycle

    init(persistence: LearningPersistence, calendar: Calendar = .current) {
        self.persistence = persistence
        self.calendar = calendar
        quran = persistence.quran
        profile = persistence.loadProfile()
        program = persistence.loadProgram()
    }

    // MARK: Internal

    @Published private(set) var profile: LearningProfile
    @Published private(set) var program: LearningProgram

    /// Vrai une fois la configuration guidée terminée.
    var isConfigured: Bool { profile.isConfigured }

    /// Vrai si le programme ne porte aucun passage : rien n'a été choisi, ou tout est déjà connu.
    var isProgramEmpty: Bool { program.isEmpty }

    /// L'avancement, entre 0 et 1.
    var progress: Double { program.progress(in: quran) }

    /// Le nombre de versets déjà appris.
    var learnedVerses: Int { program.learnedVerses(in: quran) }

    /// La série de jours consécutifs de travail.
    func streak(now: Date = Date()) -> Int {
        program.streak(now: now, calendar: calendar)
    }

    /// Le nombre de révisions dues à cette date.
    func dueReviewCount(now: Date = Date()) -> Int {
        program.dueReviews(now: now, calendar: calendar).count
    }

    /// Le prochain passage à apprendre, ou `nil` si tout est appris.
    var nextToLearn: LearningItem? { program.nextToLearn() }

    /// Le libellé d'un passage : sa sourate, puis la page où il commence.
    ///
    /// Le libellé du modèle — « page 582 », « 78:1-78:40 » — est un repère technique, pas du texte
    /// d'interface. Il est composé ici, dans la langue de l'utilisateur, à partir de la sourate et
    /// de la page, dont les noms sont déjà traduits.
    func label(of item: LearningItem) -> String? {
        guard let bounds = item.range.bounds(in: quran) else { return nil }
        let sura = bounds.first.sura
        return "\(sura.localizedName()) · \(bounds.first.page.localizedName)"
    }

    /// Relit le profil et le programme enregistrés.
    ///
    /// Appelé au retour de la configuration guidée : le magasin est la seule source de vérité, et
    /// c'est lui qui a été mis à jour, pas cet objet.
    func reload() {
        profile = persistence.loadProfile()
        program = persistence.loadProgram()
    }

    // MARK: Private

    private let persistence: LearningPersistence
    private let calendar: Calendar
    private let quran: Quran
}
