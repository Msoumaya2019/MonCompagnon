//
//  LearningSetupView.swift
//  LearningFeature
//
//  La configuration guidée, en cinq étapes.
//

import LearningKit
import Localization
import NoorUI
import SwiftUI
import UIx

/// La configuration guidée, en cinq étapes : ce que je connais, ce que je veux apprendre, à quel
/// rythme, quels jours, et le récapitulatif avant de commencer.
///
/// L'écran ne décide de rien : le brouillon porte les règles — ce qui est valide, ce qui reste à
/// faire — et lui seul autorise le passage d'une étape à l'autre.
///
/// `@MainActor` comme la vue d'accueil : ses étapes interrogent le modèle de vue, qui est isolé sur
/// l'acteur principal.
@MainActor
struct LearningSetupView: View {
    @StateObject var viewModel: LearningSetupViewModel

    /// Termine la configuration. Renseignée par le contrôleur une fois la vue construite.
    var finish: Action = {}

    var body: some View {
        NoorList {
            switch viewModel.draft.step {
            case .known:
                knownStep
            case .goals:
                goalsStep
            case .pace:
                paceStep
            case .days:
                daysStep
            case .summary:
                summaryStep
            }
        }
        .safeAreaInset(edge: .bottom) {
            navigationBar
        }
    }

    // MARK: Private

    // MARK: - Ce que je connais

    private var knownStep: some View {
        NoorBasicSection(
            title: l("learning.known.title", table: .learning),
            footer: l("learning.known.detail", table: .learning)
        ) {
            juzItems
        }
    }

    // MARK: - Ce que je veux apprendre

    private var goalsStep: some View {
        NoorBasicSection(
            title: l("learning.goals.title", table: .learning),
            footer: l("learning.goals.detail", table: .learning)
        ) {
            juzItems
        }
    }

    /// Les Juz' du mushaf, avec leur état.
    ///
    /// Les deux premières étapes partagent la même liste : un Juz' se déclare connu et se choisit
    /// comme objectif au même endroit, ce qui évite de parcourir deux fois le mushaf.
    @ViewBuilder
    private var juzItems: some View {
        ForEach(viewModel.juzRows()) { row in
            NoorListItem(
                title: .text(row.title),
                subtitle: .init(text: .text(row.amount), location: .bottom),
                accessory: accessory(for: row),
                action: .sync { select(row) }
            )
        }
    }

    /// L'état d'un Juz' : sa solidité à l'étape « ce que je connais », son objectif à l'étape
    /// « ce que je veux apprendre ».
    private func accessory(for row: LearningSetupViewModel.JuzRow) -> NoorListItem.Accessory? {
        switch viewModel.draft.step {
        case .known:
            return viewModel.solidityTitle(row.solidity).map { NoorListItem.Accessory.text($0) }
        case .goals:
            return .image(
                row.isGoal ? .checkmark_checked : .checkmark_unchecked,
                color: row.isGoal ? .accentColor : nil
            )
        case .pace, .days, .summary:
            return nil
        }
    }

    private func select(_ row: LearningSetupViewModel.JuzRow) {
        switch viewModel.draft.step {
        case .known:
            viewModel.cycleSolidity(of: row)
        case .goals:
            viewModel.toggleGoal(row)
        case .pace, .days, .summary:
            break
        }
    }

    // MARK: - Le rythme

    private var paceStep: some View {
        NoorBasicSection(
            title: l("learning.pace.title", table: .learning),
            footer: l("learning.pace.detail", table: .learning)
        ) {
            ForEach(viewModel.paces, id: \.rawValue) { pace in
                NoorListItem(
                    title: .text(viewModel.paceTitle(pace)),
                    subtitle: .init(text: .text(viewModel.paceDetail(pace)), location: .bottom),
                    accessory: checkmark(isOn: viewModel.pace == pace),
                    action: .sync { viewModel.select(pace: pace) }
                )
            }
        }
    }

    // MARK: - Les jours

    @ViewBuilder
    private var daysStep: some View {
        NoorBasicSection(
            title: l("learning.days.title", table: .learning),
            footer: l("learning.days.detail", table: .learning)
        ) {
            ForEach(viewModel.days, id: \.rawValue) { day in
                NoorListItem(
                    title: .text(viewModel.dayTitle(day)),
                    accessory: checkmark(isOn: viewModel.isWorking(day)),
                    action: .sync { viewModel.toggle(day: day) }
                )
            }
        }

        NoorBasicSection(title: l("learning.days.session", table: .learning)) {
            ForEach(viewModel.sessionMinutesChoices, id: \.self) { minutes in
                NoorListItem(
                    title: .text(viewModel.sessionMinutesTitle(minutes)),
                    accessory: checkmark(isOn: viewModel.sessionMinutes == minutes),
                    action: .sync { viewModel.setSessionMinutes(minutes) }
                )
            }
        }
    }

    // MARK: - Le récapitulatif

    private var summaryStep: some View {
        NoorBasicSection(
            title: l("learning.summary.title", table: .learning),
            footer: summaryFooter
        ) {
            if viewModel.summary.isEmpty {
                NoorListItem(title: .text(l("learning.summary.empty", table: .learning)))
            } else {
                NoorListItem(
                    title: .text(l("learning.summary.sessions", table: .learning)),
                    accessory: .text("\(viewModel.summary.sessionCount)")
                )
                NoorListItem(
                    title: .text(l("learning.summary.perSession", table: .learning)),
                    accessory: .text(viewModel.paceAmount(viewModel.pace))
                )
                NoorListItem(
                    title: .text(l("learning.summary.end", table: .learning)),
                    accessory: .text(endDateTitle)
                )
            }
        }
    }

    /// Ce qu'il faut lire quand la dernière étape ne peut pas mener au programme.
    private var summaryFooter: String? {
        viewModel.draft.days.isEmpty ? l("learning.summary.noDays", table: .learning) : nil
    }

    private var endDateTitle: String {
        guard let date = viewModel.summary.estimatedEndDate else {
            return l("learning.summary.noDays", table: .learning)
        }
        return viewModel.endDateTitle(date)
    }

    // MARK: - La barre de navigation

    private var navigationBar: some View {
        VStack(spacing: 8) {
            Text(viewModel.stepText)
                .font(.footnote)
                .foregroundColor(.secondaryLabel)

            HStack(spacing: 12) {
                if !viewModel.isFirstStep {
                    Button {
                        viewModel.back()
                    } label: {
                        Text(l("learning.setup.previous", table: .learning))
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    if viewModel.isLastStep {
                        finish()
                    } else {
                        viewModel.advance()
                    }
                } label: {
                    Text(viewModel.isLastStep
                        ? l("learning.setup.start", table: .learning)
                        : l("learning.setup.next", table: .learning))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canGoForward)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func checkmark(isOn: Bool) -> NoorListItem.Accessory {
        .image(isOn ? .checkmark_checked : .checkmark_unchecked, color: isOn ? .accentColor : nil)
    }
}
