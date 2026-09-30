//
//  LearningLabel.swift
//  LearningKit
//
//  Le libellé technique d'un passage, partagé par le planificateur et la reprise de progression.
//

import Foundation
import QuranKit

/// Compose un libellé technique pour un passage.
///
/// Volontairement neutre (« page 582 », « 78:1-78:40 ») : ce n'est pas du texte destiné à être
/// affiché tel quel. L'interface compose son propre libellé à partir de `range`, dans la langue de
/// l'utilisateur ; ce champ sert de repère stable en journalisation, et de repli.
///
/// Vit ici, et non dans le planificateur, parce que deux chemins en ont besoin : la génération d'un
/// programme, et la reprise de progression, qui **découpe** un passage et doit donc nommer ses
/// morceaux. Laisser chacun composer le sien donnerait deux libellés pour un même passage — et le
/// morceau d'une page s'appellerait « page 582 » alors qu'il n'en est qu'une partie.
enum LearningLabel {
    // MARK: Internal

    /// Le libellé d'un intervalle de rangs, ou `nil` si les rangs sortent du mushaf.
    static func label(for offsets: ClosedRange<Int>, in index: QuranVerseIndex) -> String? {
        if let page = index.quran.pages.first(where: { index.offsets(of: $0) == offsets }) {
            return "page \(page.pageNumber)"
        }

        guard
            let first = index.verse(at: offsets.lowerBound),
            let last = index.verse(at: offsets.upperBound)
        else {
            return nil
        }
        return "\(first.nonLocalizedDescription)-\(last.nonLocalizedDescription)"
    }
}
