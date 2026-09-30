//
//  UserDefaultsLearningPersistence.swift
//  LearningPersistence
//
//  Le magasin du module Apprentissage, adossé aux préférences de l'application.
//

import Foundation
import LearningKit
import QuranKit

/// Le magasin du module Apprentissage, adossé aux préférences de l'application.
///
/// Le magasin est celui de l'application entière : il n'y a qu'un profil et qu'un programme par
/// appareil, comme il n'y a qu'une préférence de lecture.
public struct UserDefaultsLearningPersistence: LearningPersistence {
    // MARK: Lifecycle

    /// - Parameters:
    ///   - quran: le mushaf de référence. Il fixe les bornes des passages, la taille des unités, et
    ///     le découpage des séances. Le changer change le programme, pas la progression : les
    ///     intervalles sont désignés par leurs coordonnées — sourate et verset — qui ne dépendent
    ///     pas du mushaf.
    ///   - calendar: le calendrier qui définit « un jour », donc les échéances de révision. Injecté
    ///     pour que les échéances soient éprouvables sans dépendre du fuseau de la machine.
    public init(quran: Quran = .hafsMadani1405, calendar: Calendar = .current) {
        self.quran = quran
        self.calendar = calendar
    }

    // MARK: Public

    /// Le mushaf de référence, qui fixe les bornes des passages et le découpage des séances.
    public let quran: Quran

    public func loadProfile() -> LearningProfile {
        preferences.profile
    }

    public func saveProfile(_ profile: LearningProfile) {
        preferences.profile = profile
    }

    public func loadProgram() -> LearningProgram {
        preferences.program
    }

    public func saveProgram(_ program: LearningProgram) {
        preferences.program = program
        // Le relevé suit le programme : c'est lui qui porte l'état de chaque passage, et donc la
        // seule source dont on puisse déduire ce qui est appris.
        saveProgress(LearningProgress(of: program, in: quran))
    }

    public func loadProgress() -> LearningProgress {
        preferences.progress
    }

    public func saveProgress(_ progress: LearningProgress) {
        preferences.progress = loadProgress().merging(progress)
    }

    @discardableResult
    public func regenerateProgram(for profile: LearningProfile, from date: Date) -> LearningProgram {
        // Le relevé est passé à la génération, et non appliqué après coup : c'est lui qui décide
        // quels passages naissent déjà appris, donc où le programme reprend. L'appliquer après
        // reviendrait à recalculer un état que le planificateur vient de poser.
        let planned = LearningPlanner(quran: quran, calendar: calendar)
            .makeProgram(for: profile, progress: loadProgress(), from: date)
        let program = LearningProgressTransfer.transfer(progressFrom: loadProgram(), to: planned, in: quran)
        saveProgram(program)
        return program
    }

    public func reset() {
        preferences.profile = .empty
        preferences.program = .empty
        preferences.progress = .empty
    }

    // MARK: Private

    /// Le calendrier qui définit « un jour ».
    private let calendar: Calendar

    private var preferences: LearningPreferences { LearningPreferences.shared }
}
