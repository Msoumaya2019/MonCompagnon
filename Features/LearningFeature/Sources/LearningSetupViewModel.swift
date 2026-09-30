//
//  LearningSetupViewModel.swift
//  LearningFeature
//
//  La configuration guidée d'un programme d'apprentissage.
//

import Combine
import Foundation
import LearningKit
import LearningPersistence
import Localization
import QuranKit
import QuranLocalization

/// La configuration guidée d'un programme d'apprentissage.
///
/// Le modèle de vue ne tient pas les règles : il porte le **brouillon**, qui sait seul ce qui est
/// valide, ce qu'un Juz' est devenu, et ce que le programme contiendra. L'écran ne fait que rendre
/// ce que le brouillon propose et lui transmettre les gestes.
@MainActor
final class LearningSetupViewModel: ObservableObject {
    // MARK: Lifecycle

    init(persistence: LearningPersistence, calendar: Calendar = .current, now: Date = Date()) {
        self.persistence = persistence
        // Conservé : l'annonce du récapitulatif et la génération du programme doivent partir de la
        // **même** date. Les recalculer chacune à l'heure courante les ferait diverger — un
        // franchissement de minuit suffit — et l'utilisateur verrait une fin estimée que le
        // programme engendré ne tiendrait pas.
        self.now = now
        quran = persistence.quran

        let profile = persistence.loadProfile()
        // Reprendre un profil déjà configuré n'est pas recommencer : ses choix sont tous là.
        let draft = profile.isConfigured
            ? LearningSetupDraft(editing: profile, quran: quran, calendar: calendar)
            : LearningSetupDraft(quran: quran, calendar: calendar, createdAt: now)
        self.draft = draft
        summary = draft.summary(from: now)
    }

    // MARK: Internal

    /// Une ligne de la liste des Juz' : ce que l'écran affiche, déjà composé.
    ///
    /// L'écran ne connaît ni les libellés, ni les unités : il rend cette ligne telle quelle.
    struct JuzRow: Identifiable {
        let id: Int
        let range: QuranRange
        let title: String
        let amount: String
        let solidity: KnownRange.Solidity?
        let isGoal: Bool
    }

    @Published private(set) var draft: LearningSetupDraft

    /// Le récapitulatif du programme tel qu'il serait engendré.
    ///
    /// Stocké plutôt que calculé à l'affichage : le calcul engendre le programme, et l'écran
    /// l'interroge à deux endroits — la dernière étape et l'état du bouton.
    @Published private(set) var summary: LearningSetupDraft.Summary

    // MARK: - Navigation

    var isFirstStep: Bool { draft.isFirstStep }
    var isLastStep: Bool { draft.isLastStep }

    /// Vrai si le bouton mène quelque part : l'étape suivante, ou le début du programme.
    var canGoForward: Bool {
        draft.isLastStep ? !summary.isEmpty : draft.canAdvance
    }

    func advance() {
        update { $0.advance() }
    }

    func back() {
        update { $0.back() }
    }

    /// « Étape 3 sur 5 », dans la langue de l'utilisateur.
    var stepText: String {
        let number = draft.step.rawValue + 1
        let total = LearningSetupDraft.Step.allCases.count
        return lFormat("learning.setup.step", table: .learning, number, total)
    }

    // MARK: - Ce que je connais, et ce que je veux apprendre

    /// Les Juz' du mushaf, avec l'état du brouillon pour chacun.
    ///
    /// Une seule liste pour les deux étapes : un Juz' se déclare connu et se choisit comme objectif
    /// au même endroit, ce qui évite à l'utilisateur de parcourir deux fois le mushaf.
    func juzRows() -> [JuzRow] {
        draft.choices(for: .juz).map { choice in
            JuzRow(
                id: choice.number,
                range: choice.range,
                title: juzName(choice.number),
                amount: lFormat("verses", table: .android, choice.verseCount),
                solidity: choice.solidity,
                isGoal: choice.isGoal
            )
        }
    }

    /// Le nom du Juz', « Juz' 30 » compris.
    func juzName(_ number: Int) -> String {
        let juzs = quran.juzs
        guard number >= 1, number <= juzs.count else {
            return lFormat("juz2_description", table: .android, number)
        }
        return juzs[number - 1].localizedName
    }

    /// Fait tourner l'état d'un Juz' : rien → solide → fragile → rien.
    func cycleSolidity(of row: JuzRow) {
        update { $0.cycleSolidity(for: row.range) }
    }

    /// Ajoute ou retire un Juz' des objectifs.
    func toggleGoal(_ row: JuzRow) {
        update { $0.toggleGoal(row.range) }
    }

    /// Le libellé de l'état déclaré, ou `nil` s'il n'y en a pas.
    func solidityTitle(_ solidity: KnownRange.Solidity?) -> String? {
        switch solidity {
        case .none:
            return nil
        case .some(.solide):
            return l("learning.known.solid", table: .learning)
        case .some(.fragile):
            return l("learning.known.fragile", table: .learning)
        }
    }

    // MARK: - Le rythme

    var paces: [LearningPace] { LearningPace.allCases }

    var pace: LearningPace { draft.pace }

    func select(pace: LearningPace) {
        update { $0.select(pace: pace) }
    }

    func paceTitle(_ pace: LearningPace) -> String {
        l("learning.pace.\(pace.rawValue).title", table: .learning)
    }

    func paceDetail(_ pace: LearningPace) -> String {
        l("learning.pace.\(pace.rawValue).detail", table: .learning)
    }

    /// Le nombre de versets visés par séance, dans l'unité où l'utilisateur les compte.
    ///
    /// L'allure personnalisée n'a pas de nombre à elle : elle affiche celui du brouillon, qui est
    /// exactement ce qui sera appliqué.
    func paceAmount(_ pace: LearningPace) -> String {
        let verses = pace.versesPerSession ?? draft.versesPerSession
        return lFormat("verses", table: .android, verses)
    }

    // MARK: - Les jours

    var days: [LearningDay] { LearningDay.allCases }

    func isWorking(_ day: LearningDay) -> Bool {
        draft.days.contains(day)
    }

    func toggle(day: LearningDay) {
        update { draft in
            if draft.days.contains(day) {
                draft.days.remove(day)
            } else {
                draft.days.insert(day)
            }
        }
    }

    func dayTitle(_ day: LearningDay) -> String {
        l("learning.day.\(day.rawValue)", table: .learning)
    }

    var sessionMinutesChoices: [Int] { [10, 15, 20, 30, 45] }

    var sessionMinutes: Int { draft.sessionMinutes }

    func setSessionMinutes(_ minutes: Int) {
        update { $0.sessionMinutes = minutes }
    }

    func sessionMinutesTitle(_ minutes: Int) -> String {
        lFormat("learning.days.session-minutes", table: .learning, minutes)
    }

    // MARK: - Le récapitulatif

    /// La fin estimée, dans la langue de l'utilisateur.
    func endDateTitle(_ date: Date) -> String {
        Self.endDateFormatter.string(from: date)
    }

    // MARK: - Terminer

    /// Enregistre le profil et engendre le programme correspondant.
    ///
    /// Le magasin est la seule source de vérité : c'est lui qui garde le profil et le programme, et
    /// l'écran d'accueil les relira au retour. Le programme est engendré ici, et non à l'ouverture
    /// du programme, pour qu'aucune configuration ne reste sans programme.
    func start() {
        let profile = draft.makeProfile()
        persistence.saveProfile(profile)
        persistence.regenerateProgram(for: profile, from: now)
    }

    // MARK: Private

    private static let endDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    private let persistence: LearningPersistence
    private let quran: Quran

    /// Le moment où l'écran s'est ouvert — la même date pour l'annonce et pour le programme.
    private let now: Date

    /// Applique une modification au brouillon, et remet le récapitulatif à jour.
    ///
    /// Le brouillon est un type valeur : le réécrire est ce qui prévient l'écran du changement, et
    /// c'est aussi ce qui garantit qu'aucune modification n'oublie de recalculer l'annonce.
    private func update(_ body: (inout LearningSetupDraft) -> Void) {
        var updated = draft
        body(&updated)
        draft = updated
        summary = updated.summary(from: now)
    }
}
