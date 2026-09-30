//
//  LearningPlanningView.swift
//  LearningFeature
//
//  Le planning de l'apprentissage.
//

import LearningKit
import Localization
import NoorUI
import SwiftUI
import UIx

/// Le planning : ce qui vient, ce qui est fait, et ce qui est dû.
///
/// Quatre vues d'un même programme, sous un sélecteur unique. « À venir » et « Terminés » le lisent
/// par état ; « Semaine » et « Mois » par échéance, et ceux-là portent une grille — les jours de la
/// période, avec une pastille là où quelque chose est dû.
///
/// La grille est là pour situer, la liste pour agir : une case dit **quand**, une ligne dit **quoi**
/// et ouvre le Coran dessus. Aucune des deux ne répète l'autre.
///
/// `@MainActor` comme le modèle de vue, qui est isolé sur l'acteur principal.
@MainActor
struct LearningPlanningView: View {
    @StateObject var viewModel: LearningPlanningViewModel

    /// Ouvre le Coran sur un passage.
    ///
    /// Renseignée par le contrôleur une fois la vue construite : capturer `self` dans
    /// l'initialiseur du contrôleur serait refusé par Swift.
    var open: ItemAction<LearningItem> = { _ in }

    var body: some View {
        NoorList {
            tabsSection

            if viewModel.isEmpty {
                NoorBasicSection {
                    NoorListItem(title: .text(viewModel.emptyMessage))
                }
            } else if viewModel.showsCalendar {
                calendarSection

                ForEach(viewModel.sections) { section in
                    NoorBasicSection(title: section.title) {
                        rows(section.rows)
                    }
                }
            } else {
                NoorBasicSection {
                    rows(viewModel.rows)
                }
            }
        }
    }

    // MARK: Private

    /// Le sélecteur des quatre vues.
    private var tabsSection: some View {
        NoorBasicSection {
            Picker("", selection: tabBinding) {
                ForEach(viewModel.tabs, id: \.self) { tab in
                    Text(viewModel.title(of: tab)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .accessibilityLabel(l("learning.planning.title", table: .learning))
        }
    }

    /// La grille des jours de la période.
    ///
    /// Les initiales de tête viennent des jours eux-mêmes, et non d'une liste écrite en dur : c'est
    /// le calendrier de l'utilisateur qui décide quel jour commence la semaine, et le formateur du
    /// système qui en donne l'initiale dans sa langue.
    private var calendarSection: some View {
        NoorBasicSection {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(viewModel.weekdayHeaders.enumerated()), id: \.offset) { _, header in
                        Text(header)
                            .font(.caption2)
                            .foregroundColor(.secondaryLabel)
                            .frame(maxWidth: .infinity)
                    }
                }

                ForEach(Array(viewModel.grid.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(week) { cell in
                            dayCell(cell)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// Une case de la grille : le numéro du jour, et une pastille s'il porte quelque chose.
    ///
    /// La pastille est un ornement, pas une information : le compte est dit à voix haute par
    /// l'étiquette d'accessibilité, et écrit dans la liste juste en dessous.
    private func dayCell(_ cell: LearningPlanningViewModel.DayCell) -> some View {
        VStack(spacing: 4) {
            Text(cell.number)
                .font(.footnote)
                .foregroundColor(cell.isToday ? Color.white : Color.primary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(cell.isToday ? Color.accentColor : Color.clear))

            Circle()
                .fill(cell.dueCount > 0 ? Color.accentColor : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.accessibilityLabel)
    }

    /// Les passages d'une liste, sous leur libellé lisible.
    ///
    /// Chaque ligne ouvre le Coran sur son passage : c'est tout l'intérêt de l'écran — voir ce qui
    /// vient ou ce qui est dû, et le travailler sans avoir à le retrouver dans le mushaf.
    @ViewBuilder
    private func rows(_ items: [LearningPlanningViewModel.Row]) -> some View {
        ForEach(items) { row in
            NoorListItem(
                title: .text(row.title),
                subtitle: row.subtitle.map { .init(text: .text($0), location: .bottom) },
                accessory: .disclosureIndicator,
                action: .sync { open(row.item) }
            )
        }
    }

    private var tabBinding: Binding<LearningPlanningViewModel.Tab> {
        Binding(
            get: { viewModel.tab },
            set: { viewModel.select($0) }
        )
    }
}
