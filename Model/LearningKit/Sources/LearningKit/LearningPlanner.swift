//
//  LearningPlanner.swift
//  LearningKit
//
//  Génération du programme d'apprentissage à partir du profil.
//

import Foundation
import QuranKit

/// Construit un programme d'apprentissage à partir d'un profil.
///
/// Le planificateur n'a pas d'état : deux appels avec le même profil et la même date produisent
/// les mêmes passages. C'est ce qui le rend éprouvable, et ce qui permet de régénérer un
/// programme après modification du profil sans effet de bord.
public struct LearningPlanner {
    // MARK: Lifecycle

    public init(quran: Quran = .hafsMadani1405, calendar: Calendar = .current) {
        self.quran = quran
        self.calendar = calendar
        index = QuranVerseIndex(quran: quran)
    }

    // MARK: Public

    /// Le mushaf de référence, qui définit les bornes et la taille des unités.
    public let quran: Quran

    /// Le calendrier qui définit ce qu'est « un jour » — et donc les échéances de révision.
    public let calendar: Calendar

    /// Construit le programme correspondant au profil, sans reprise.
    ///
    /// Équivalent à `makeProgram(for:progress:from:)` avec un relevé vierge. Réservé à l'aperçu
    /// d'une configuration et aux tests : l'application, elle, passe toujours le relevé enregistré,
    /// sans quoi un programme régénéré reproposerait à neuf ce qui est déjà appris.
    public func makeProgram(for profile: LearningProfile, from date: Date = Date()) -> LearningProgram {
        makeProgram(for: profile, progress: .empty, from: date)
    }

    /// Construit le programme correspondant au profil, en reprenant au repère atteint.
    ///
    /// Le programme **couvre toujours l'objectif entier** : la reprise ne retire aucun passage, elle
    /// marque comme appris ceux qui le sont déjà. C'est ce qui rend la progression monotone — elle
    /// ne retombe jamais à zéro parce que le programme se serait raccourci — et ce qui fait qu'un
    /// jour manqué n'ajoute aucun retard : le programme est le même, seul le nombre de passages
    /// appris a changé.
    ///
    /// Trois temps, dans cet ordre :
    ///
    /// 1. les objectifs sont fusionnés puis **retranchés** de tout ce qui est déjà connu, solide
    ///    comme fragile. On ne programme jamais ce que l'utilisateur récite sans hésiter, et on ne
    ///    repropose pas comme « à apprendre » ce qu'il connaît déjà ;
    /// 2. chaque morceau restant est **découpé en séances** de la taille de l'allure choisie,
    ///    une séance s'arrêtant de préférence sur une fin de page ; celles que le relevé couvre
    ///    sont marquées apprises ;
    /// 3. les intervalles **fragiles** sont ajoutés en fin de programme, déjà marqués appris et
    ///    dus en révision : l'utilisateur les connaît mais les oublie, donc ils doivent revenir.
    ///
    /// Les passages portent des identifiants neufs à chaque génération. Reporter la progression
    /// antérieure sur un programme régénéré est le rôle de `LearningProgressTransfer`, qui compare
    /// les intervalles verset par verset ; le planificateur, lui, ne connaît que le profil et le
    /// relevé, et rend toujours des passages neufs.
    ///
    /// - Returns: un programme vide si le profil n'a aucun objectif, ou si tout ce qu'il vise est
    ///   déjà connu **et solide**. Un acquis fragile reste un passage à revoir : il suffit
    ///   donc à rendre le programme non vide.
    public func makeProgram(
        for profile: LearningProfile,
        progress: LearningProgress,
        from date: Date = Date()
    ) -> LearningProgram {
        let targets = QuranRangeAlgebra.merged(profile.goals.compactMap { $0.range.offsets(in: index) })
        guard !targets.isEmpty else { return .empty }

        let known = QuranRangeAlgebra.merged(
            (profile.solidRanges + profile.fragileRanges).compactMap { $0.offsets(in: index) }
        )
        let remaining = targets.flatMap { QuranRangeAlgebra.subtracting(known, from: $0) }

        // Pas de sortie si `remaining` est vide : les acquis fragiles sont ajoutés plus bas,
        // et un objectif entièrement fragile n'a plus rien à apprendre mais tout à revoir.
        // Sortir ici perdait ces révisions, et le programme passait pour vide.
        var items: [LearningItem] = []
        for interval in remaining {
            for chunk in sessions(in: interval, targetVerses: profile.pace.targetVersesPerSession) {
                guard let range = QuranRange(offsets: chunk, in: index) else { continue }
                var item = LearningItem(
                    range: range,
                    label: LearningLabel.label(for: chunk, in: index),
                    position: items.count
                )
                if let learnedAt = progress.learnedAt(chunk, in: index) {
                    markLearned(&item, at: learnedAt)
                }
                items.append(item)
            }
        }
        items.append(contentsOf: reviewItems(for: profile, at: date, startingAt: items.count))

        guard !items.isEmpty else { return .empty }
        return LearningProgram(items: items, generatedAt: date)
    }

    /// Date estimée de fin du programme, au rythme et sur les jours choisis.
    ///
    /// L'estimation compte les **séances restantes**, puis les répartit sur les seuls jours de
    /// travail. Un programme déjà terminé se termine aujourd'hui.
    ///
    /// - Returns: `nil` si aucun jour de travail n'est choisi — sans jour, il n'y a pas de fin.
    public func estimatedEndDate(
        for program: LearningProgram,
        profile: LearningProfile,
        from date: Date = Date()
    ) -> Date? {
        let remaining = program.totalVerses(in: quran) - program.learnedVerses(in: quran)
        guard remaining > 0 else { return calendar.startOfDay(for: date) }

        let perSession = max(1, profile.pace.targetVersesPerSession)
        // Arrondi au supérieur : une séance entamée est une séance à faire.
        let sessions = (remaining + perSession - 1) / perSession
        return dateOfSession(sessions, workingDays: profile.days, from: date)
    }

    // MARK: Private

    private let index: QuranVerseIndex

    /// Découpe un intervalle en séances d'environ `targetVerses` versets.
    ///
    /// Une séance ne s'arrête pas au verset exactement compté : elle cherche la **fin de page la
    /// plus proche**, sans jamais dépasser le double de la cible. Sans cet arrondi, le programme
    /// proposerait « les versets 5 à 12 de la page 582 » — illisible sur un mushaf.
    ///
    /// Le découpage couvre l'intervalle **exactement** : pas de trou, pas de recouvrement, et
    /// aucune séance ne dépasse le double de la cible.
    private func sessions(in interval: ClosedRange<Int>, targetVerses: Int) -> [ClosedRange<Int>] {
        let target = max(1, targetVerses)
        var result: [ClosedRange<Int>] = []
        var cursor = interval.lowerBound

        while cursor <= interval.upperBound {
            let ideal = cursor + target - 1
            let limit = min(interval.upperBound, cursor + 2 * target - 1)
            let end = pageEnd(nearest: ideal, from: cursor, through: limit) ?? min(ideal, interval.upperBound)
            result.append(cursor ... end)
            cursor = end + 1
        }
        return result
    }

    /// La fin de page la plus proche de `offset`, entre `lower` et `upper` inclus.
    ///
    /// À égalité de distance, la **première** est retenue. Le résultat ne dépend donc pas de
    /// l'ordre de parcours : deux exécutions produisent le même découpage.
    private func pageEnd(nearest offset: Int, from lower: Int, through upper: Int) -> Int? {
        var best: Int?
        for candidate in index.pageEndOffsets where candidate >= lower && candidate <= upper {
            guard let current = best else {
                best = candidate
                continue
            }
            if abs(candidate - offset) < abs(current - offset) {
                best = candidate
            }
        }
        return best
    }

    /// Marque un passage comme déjà appris, à la date où il l'a été.
    ///
    /// Reproduit ici la transition de `LearningProgram.markLearned`, et pour la même raison : un
    /// passage appris reçoit sa première révision à J+1. La date est celle du **dernier jour de
    /// travail de la sourate**, et non celle du jour : reprendre un programme ne doit pas repousser
    /// une révision due, ni en faire naître une le jour même pour un travail de la veille.
    private func markLearned(_ item: inout LearningItem, at date: Date) {
        item.storedStatus = .learned
        item.reviewStage = 0
        item.lastWorkedAt = date
        item.nextReview = LearningConsolidation.nextReview(afterSuccessAt: 0, from: date, calendar: calendar)
    }

    /// Les acquis fragiles, ajoutés au programme en révision.
    ///
    /// Ils ne sont pas marqués comme travaillés : déclarer « je le connais mais je l'oublie » n'est
    /// pas un jour de travail, et le compter fausserait la série.
    private func reviewItems(for profile: LearningProfile, at date: Date, startingAt position: Int) -> [LearningItem] {
        let solid = QuranRangeAlgebra.merged(profile.solidRanges.compactMap { $0.offsets(in: index) })
        var items: [LearningItem] = []

        for range in profile.fragileRanges {
            guard let offsets = range.offsets(in: index) else { continue }
            // Ce qui est déclaré solide ne revient pas en révision, même si le même verset a aussi
            // été déclaré fragile : les deux déclarations se contredisent, et c'est la plus forte
            // qui doit décider. Sans ce retranchement, un verset que l'utilisateur récite sans
            // hésiter lui serait proposé à revoir — et le compte des révisions mentirait.
            for piece in QuranRangeAlgebra.subtracting(solid, from: offsets) {
                guard let range = QuranRange(offsets: piece, in: index) else { continue }
                var item = LearningItem(
                    range: range,
                    label: LearningLabel.label(for: piece, in: index),
                    position: position + items.count
                )
                // Déjà connu : jamais « à apprendre ». Dû dès aujourd'hui, puisque l'utilisateur a
                // précisément déclaré qu'il l'oublie.
                item.storedStatus = .learned
                item.reviewStage = 0
                item.nextReview = calendar.startOfDay(for: date)
                items.append(item)
            }
        }
        return items
    }

    /// La date de la n-ième séance, en ne comptant que les jours de travail.
    ///
    /// La première séance peut avoir lieu aujourd'hui : si le jour courant est un jour de travail,
    /// `sessions == 1` rend aujourd'hui.
    ///
    /// - Note: le nom porte `OfSession` et non `date` seul : un paramètre nommé `date` masquerait
    ///   la méthode dans `estimatedEndDate`, et l'appel se lirait comme celui d'un `Date`.
    private func dateOfSession(_ sessions: Int, workingDays: Set<LearningDay>, from start: Date) -> Date? {
        let weekdays = Set(workingDays.map(\.calendarWeekday))
        guard !weekdays.isEmpty else { return nil }

        var remaining = sessions
        var cursor = calendar.startOfDay(for: start)
        // Borne explicite. La boucle s'arrête d'elle-même dès que les jours se répètent — une
        // semaine au plus — mais une borne rend la terminaison vérifiable sans raisonner sur le
        // calendrier.
        var budget = sessions * 7 + 7

        while budget > 0 {
            if weekdays.contains(calendar.component(.weekday, from: cursor)) {
                remaining -= 1
                if remaining <= 0 { return cursor }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
            budget -= 1
        }
        return nil
    }
}
