//
//  LearningProgressTransfer.swift
//  LearningKit
//
//  Reporter sur un programme régénéré la progression déjà acquise.
//

import Foundation
import QuranKit

/// Reporte la progression d'un programme sur un autre.
///
/// Régénérer un programme — après un changement d'allure, de jours de travail ou d'objectifs —
/// produit des passages aux **identifiants neufs** et aux **bornes différentes**. Sans reprise,
/// l'utilisateur verrait s'évaporer ce qu'il a déjà appris : c'est le seul endroit du module où
/// quelque chose peut réellement se perdre.
///
/// La reprise se fait **verset par verset**, et non passage par passage. C'est ce qui permet de
/// découper un passage régénéré au ras de ce qui est acquis : un passage de 40 versets dont les 15
/// premiers sont déjà appris devient **deux** passages — l'acquis, puis le reste — là où une reprise
/// par passage aurait rendu un seul passage neuf, effaçant le travail fait.
public enum LearningProgressTransfer {
    // MARK: Public

    /// Le programme `program`, enrichi de la progression portée par `previous`.
    ///
    /// Les passages sans acquis sont rendus tels quels : un programme neuf reste neuf. Un passage
    /// dont les bornes sont **exactement** celles d'un passage antérieur garde même son
    /// identifiant : régénérer le même profil rend alors le même programme, au bit près.
    ///
    /// - Returns: `program` inchangé si l'un des deux programmes est vide — il n'y a rien à
    ///   reporter, et rien à reporter sur quoi que ce soit.
    public static func transfer(
        progressFrom previous: LearningProgram,
        to program: LearningProgram,
        in quran: Quran
    ) -> LearningProgram {
        guard !previous.isEmpty, !program.isEmpty else { return program }

        let index = QuranVerseIndex(quran: quran)
        let acquired = acquiredStates(of: previous, in: index)
        let identifiersByOffsets = identifiers(of: previous, in: index)

        var items: [LearningItem] = []
        for item in program.items {
            let own = state(of: item)

            guard let offsets = item.range.offsets(in: index) else {
                // Bornes absentes de ce mushaf : le passage est rendu tel quel. Le retirer ferait
                // disparaître un objectif de l'utilisateur sans le lui dire.
                items.append(
                    makeItem(
                        id: item.id,
                        range: item.range,
                        label: item.label,
                        position: items.count,
                        inherited: own
                    )
                )
                continue
            }

            // L'acquis antérieur prime sur l'état du passage régénéré : le planificateur rend des
            // passages neufs, sauf les révisions fragiles, qui n'ont d'état que faute d'antécédent.
            for run in runs(of: offsets, stateAt: { acquired[$0] ?? own }) {
                guard let range = QuranRange(offsets: run, in: index) else { continue }
                items.append(
                    makeItem(
                        id: identifiersByOffsets[run] ?? UUID(),
                        range: range,
                        label: LearningLabel.label(for: run, in: index) ?? item.label,
                        position: items.count,
                        inherited: acquired[run.lowerBound] ?? own
                    )
                )
            }
        }
        return LearningProgram(items: items, generatedAt: program.generatedAt)
    }

    // MARK: Private

    /// L'état d'un verset déjà travaillé, tel qu'il doit être repris.
    ///
    /// Les trois champs voyagent ensemble : un passage dont l'étape de révision ne correspond pas à
    /// sa date de révision serait incohérent, et le calcul de la révision suivante le serait aussi.
    private struct VerseState: Equatable {
        let stage: Int
        let nextReview: Date?
        let lastWorkedAt: Date?
    }

    /// L'état de chaque verset déjà travaillé du programme, indexé par son rang.
    ///
    /// Un verset peut appartenir à plusieurs passages — un passage d'objectif et un passage de
    /// révision fragile, par exemple. On retient alors l'acquis **le plus fort sur chaque axe** :
    /// l'étape la plus avancée, la révision due la plus proche, le dernier travail le plus récent.
    /// Prendre le plus faible effacerait un travail réel ; ce partage ne reporte jamais une
    /// révision due, ce qui est le seul risque qu'il ne faut pas prendre.
    private static func acquiredStates(of program: LearningProgram, in index: QuranVerseIndex) -> [Int: VerseState] {
        var states: [Int: VerseState] = [:]
        for item in program.items {
            // `itemState` et non `state` : un local nommé `state` masquerait la méthode `state(of:)`
            // dans toute la suite du corps.
            guard let itemState = state(of: item), let offsets = item.range.offsets(in: index) else { continue }
            for offset in offsets {
                states[offset] = merging(states[offset], itemState)
            }
        }
        return states
    }

    /// L'acquis d'un passage, ou `nil` s'il n'a jamais été travaillé.
    ///
    /// « À revoir » compte comme appris : c'est un état **déduit** de `learned`, jamais rangé tel
    /// quel. Le traiter comme neuf effacerait une révision due, c'est-à-dire précisément ce que la
    /// consolidation espacée cherche à faire revenir.
    private static func state(of item: LearningItem) -> VerseState? {
        guard item.storedStatus != .notLearned else { return nil }
        return VerseState(
            stage: item.reviewStage,
            nextReview: item.nextReview,
            lastWorkedAt: item.lastWorkedAt
        )
    }

    /// L'identifiant de chaque passage du programme, indexé par ses bornes.
    ///
    /// Sert à rendre la reprise **sans effet** quand un passage régénéré a exactement les mêmes
    /// bornes qu'auparavant : il garde son identifiant, donc la sélection de l'interface ne bouge
    /// pas et le programme reste comparable d'une génération à l'autre.
    private static func identifiers(of program: LearningProgram, in index: QuranVerseIndex) -> [ClosedRange<Int>: UUID] {
        var result: [ClosedRange<Int>: UUID] = [:]
        for item in program.items {
            guard let offsets = item.range.offsets(in: index) else { continue }
            result[offsets] = item.id
        }
        return result
    }

    /// Découpe un intervalle en suites maximales de versets de même état.
    ///
    /// Une suite sans état est un passage neuf ; une suite avec état est un passage acquis. C'est ce
    /// découpage qui fait qu'aucun verset travaillé n'est perdu, quelle que soit la nouvelle
    /// découpe.
    ///
    /// - Note: le paramètre s'appelle `stateAt` et non `state` : `state(of:)` est une méthode de ce
    ///   type, et un paramètre nommé `state` la masquerait dans tout le corps.
    private static func runs(
        of offsets: ClosedRange<Int>,
        stateAt: (Int) -> VerseState?
    ) -> [ClosedRange<Int>] {
        // Un intervalle d'un seul verset ne peut pas se découper — et `lowerBound + 1` dépasserait
        // sa borne haute, ce qui ferait planter la boucle ci-dessous.
        guard offsets.lowerBound < offsets.upperBound else { return [offsets] }

        var result: [ClosedRange<Int>] = []
        var start = offsets.lowerBound
        var current = stateAt(start)

        for offset in (offsets.lowerBound + 1) ... offsets.upperBound {
            let candidate = stateAt(offset)
            guard candidate != current else { continue }
            result.append(start ... (offset - 1))
            start = offset
            current = candidate
        }
        result.append(start ... offsets.upperBound)
        return result
    }

    /// Construit un passage, avec ou sans acquis.
    ///
    /// - Note: le paramètre s'appelle `inherited` et non `state` : `state(of:)` est une méthode de ce
    ///   type, et un paramètre nommé `state` la masquerait dans tout le corps.
    private static func makeItem(
        id: UUID,
        range: QuranRange,
        label: String?,
        position: Int,
        inherited: VerseState?
    ) -> LearningItem {
        var item = LearningItem(id: id, range: range, label: label, position: position)
        guard let inherited else { return item }
        item.storedStatus = .learned
        item.reviewStage = inherited.stage
        item.nextReview = inherited.nextReview
        item.lastWorkedAt = inherited.lastWorkedAt
        return item
    }

    /// Fusionne deux acquis portant sur les mêmes versets.
    private static func merging(_ existing: VerseState?, _ other: VerseState) -> VerseState {
        guard let existing else { return other }
        return VerseState(
            stage: max(existing.stage, other.stage),
            nextReview: [existing.nextReview, other.nextReview].compactMap { $0 }.min(),
            lastWorkedAt: [existing.lastWorkedAt, other.lastWorkedAt].compactMap { $0 }.max()
        )
    }
}
