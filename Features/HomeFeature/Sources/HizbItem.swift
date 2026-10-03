//
//  HizbItem.swift
//
//
//  Un hizb, et le texte de son premier verset.
//

import QuranKit
import QuranText

/// Un hizb prêt à être affiché : le groupe, et le début de son texte.
///
/// Le hizb n'est pas `Identifiable` dans `QuranKit` — contrairement à `Sura` et à `Juz` — et il
/// porte un texte comme le rubu'. Les deux raisons donnent la même forme que `QuarterItem` : un
/// enveloppe qui identifie le groupe par lui-même et qui transporte le texte déjà lu.
struct HizbItem: Identifiable {
    let hizb: Hizb
    let ayahText: QuranText

    var id: Hizb { hizb }
}
