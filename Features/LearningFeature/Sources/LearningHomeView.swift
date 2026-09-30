//
//  LearningHomeView.swift
//  LearningFeature
//
//  Le tableau de bord de l'apprentissage.
//

import LearningKit
import Localization
import NoorUI
import SwiftUI
import UIx

/// Le tableau de bord : ce qu'il y a à faire aujourd'hui, ce qui est fragile, ce qui est dû, et où
/// en est le programme.
///
/// L'écran ne dit jamais « en retard ». Aucune séance n'est rattachée à un jour : le programme
/// avance avec les versets réellement appris, et reprend là où l'utilisateur s'est arrêté. C'est
/// pourquoi « Aujourd'hui » annonce la prochaine séance et les révisions dues, sans rien reprocher
/// pour les jours manqués.
///
/// Tant que la configuration n'est pas terminée, il n'y a rien à récapituler : l'écran propose de la
/// commencer. C'est le seul état où il n'y a pas de programme à montrer.
///
/// `@MainActor` comme le modèle de vue, qui est isolé sur l'acteur principal.
@MainActor
struct LearningHomeView: View {
    @StateObject var viewModel: LearningHomeViewModel

    /// Ouvre la configuration du programme.
    ///
    /// Renseignée par le contrôleur une fois la vue construite : capturer `self` dans
    /// l'initialiseur du contrôleur serait refusé par Swift.
    var editProgram: Action = {}

    /// Ouvre le planning : ce qui vient, ce qui est fait, et ce qui est dû.
    ///
    /// Renseignée par le contrôleur, comme `editProgram` — la vue ne sait pas naviguer.
    var openPlanning: Action = {}

    /// Ouvre le Coran sur un passage.
    ///
    /// Renseignée par le contrôleur, comme `editProgram` : la vue ne sait pas naviguer, et ne doit
    /// pas le savoir. Le navigateur appartient à l'onglet, pas à l'écran.
    ///
    /// Une seule porte vers le lecteur : « Commencer maintenant » lui donne le passage choisi par
    /// le programme, les lignes de « À consolider » et de « Révision » lui donnent le leur.
    var open: ItemAction<LearningItem> = { _ in }

    var body: some View {
        NoorList {
            if !viewModel.isConfigured {
                NoorBasicSection {
                    configureItem
                }
            } else if viewModel.isProgramEmpty {
                NoorBasicSection {
                    NoorListItem(title: .text(l("learning.dashboard.empty", table: .learning)))
                    editItem
                }
            } else {
                todaySection
                consolidateSection
                reviewSection
                programSection
                NoorBasicSection {
                    planningItem
                    editItem
                }
            }
        }
    }

    // MARK: Private

    /// Ce qu'il y a à faire aujourd'hui.
    ///
    /// Deux choses, et deux seulement : la prochaine séance à apprendre, et les révisions dues.
    /// Quand il n'y a ni l'une ni l'autre, l'écran le dit plutôt que de rester muet — un écran vide
    /// se lit comme une panne.
    private var todaySection: some View {
        NoorBasicSection(title: l("learning.dashboard.today", table: .learning), footer: todayFooter) {
            if let next = viewModel.nextToLearn, let label = viewModel.label(of: next) {
                NoorListItem(
                    title: .text(label),
                    subtitle: .init(
                        text: .text(l("learning.dashboard.toLearn", table: .learning)),
                        location: .bottom
                    )
                )
            } else {
                NoorListItem(title: .text(l("learning.dashboard.finished", table: .learning)))
            }

            if let next = viewModel.nextToWork {
                NoorListItem(
                    title: .text(l("learning.dashboard.start", table: .learning)),
                    accessory: .disclosureIndicator,
                    action: .sync { open(next) }
                )
            }

            if viewModel.dueReviewCount() > 0 {
                NoorListItem(
                    title: .text(l("learning.dashboard.reviews", table: .learning)),
                    accessory: .text("\(viewModel.dueReviewCount())")
                )
            }
        }
    }

    /// Les acquis fragiles, qui reviennent en révision dès le premier jour.
    private var consolidateSection: some View {
        let items = viewModel.toConsolidate()
        return NoorBasicSection(
            title: l("learning.dashboard.consolidate", table: .learning),
            footer: items.isEmpty ? l("learning.dashboard.consolidate.none", table: .learning) : nil
        ) {
            rows(for: items)
        }
    }

    /// Les révisions dues d'un passage déjà travaillé.
    private var reviewSection: some View {
        let items = viewModel.reviews()
        return NoorBasicSection(
            title: l("learning.dashboard.review", table: .learning),
            footer: items.isEmpty ? l("learning.dashboard.none", table: .learning) : nil
        ) {
            rows(for: items)
        }
    }

    /// Où en est le programme.
    private var programSection: some View {
        NoorBasicSection(title: l("learning.dashboard.program", table: .learning)) {
            NoorListItem(
                title: .text(l("learning.dashboard.progress", table: .learning)),
                accessory: .text(progressText)
            )
            NoorListItem(
                title: .text(l("learning.dashboard.learned", table: .learning)),
                accessory: .text(lFormat("verses", table: .android, viewModel.learnedVerses))
            )
            NoorListItem(
                title: .text(l("learning.dashboard.consolidated", table: .learning)),
                accessory: .text("\(viewModel.consolidatedCount)")
            )
            NoorListItem(
                title: .text(l("learning.dashboard.streak", table: .learning)),
                accessory: .text("\(viewModel.streak())")
            )
        }
    }

    /// Les passages d'une liste, sous leur libellé lisible.
    ///
    /// Le libellé est composé par le modèle de vue — sourate, puis page — parce que le libellé du
    /// modèle, lui, est un repère technique : « page 582 » ou « 78:1-78:40 » ne se lisent pas.
    ///
    /// Chaque ligne ouvre le Coran sur son passage : c'est tout l'intérêt de la section — voir ce
    /// qui est fragile ou dû, et le travailler sans avoir à le retrouver dans le mushaf.
    @ViewBuilder
    private func rows(for items: [LearningItem]) -> some View {
        ForEach(items) { item in
            if let label = viewModel.label(of: item) {
                NoorListItem(
                    title: .text(label),
                    accessory: .disclosureIndicator,
                    action: .sync { open(item) }
                )
            }
        }
    }

    /// Le pied de la section du jour : ce qu'il faut lire quand il n'y a rien à faire.
    private var todayFooter: String? {
        viewModel.dueReviewCount() == 0 && viewModel.nextToLearn == nil
            ? l("learning.dashboard.none", table: .learning)
            : nil
    }

    /// Le bouton qui ouvre la configuration, quand il n'y en a pas encore.
    private var configureItem: some View {
        NoorListItem(
            title: .text(l("learning.setup.title", table: .learning)),
            subtitle: .init(
                text: .text(l("learning.row.detail", table: .learning)),
                location: .bottom
            ),
            accessory: .disclosureIndicator,
            action: .sync { editProgram() }
        )
    }

    /// Le bouton qui ouvre le planning.
    ///
    /// Il n'est proposé qu'une fois le programme en place : un planning vide n'apprendrait rien, et
    /// l'écran qui le porte dirait « rien à réviser » sur un programme qui n'existe pas encore.
    private var planningItem: some View {
        NoorListItem(
            title: .text(l("learning.planning.title", table: .learning)),
            subtitle: .init(
                text: .text(l("learning.planning.detail", table: .learning)),
                location: .bottom
            ),
            accessory: .disclosureIndicator,
            action: .sync { openPlanning() }
        )
    }

    /// Le bouton qui rouvre la configuration, une fois le programme en place.
    private var editItem: some View {
        NoorListItem(
            title: .text(l("learning.dashboard.edit", table: .learning)),
            accessory: .disclosureIndicator,
            action: .sync { editProgram() }
        )
    }

    private var progressText: String {
        let percent = Int((viewModel.progress * 100).rounded())
        return lFormat("learning.dashboard.progress.value", table: .learning, percent)
    }
}
