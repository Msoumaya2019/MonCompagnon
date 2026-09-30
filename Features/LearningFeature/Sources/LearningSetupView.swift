//
//  LearningSetupView.swift
//  LearningFeature
//
//  La configuration d'un programme d'apprentissage, en une page.
//

import LearningKit
import Localization
import NoorUI
import SwiftUI
import UIx

/// La configuration d'un programme d'apprentissage.
///
/// Une **page unique**, et non un assistant : trois sections — ce que je connais, mon objectif, mon
/// rythme — puis ce que le programme contiendra, et un bouton. L'utilisateur voit donc toujours
/// l'ensemble de ce qu'il a composé, et peut corriger n'importe quel choix sans revenir en arrière.
///
/// L'écran ne décide de rien : le brouillon porte les règles, et lui seul autorise la création.
///
/// `@MainActor` comme la vue d'accueil : ses sections interrogent le modèle de vue, qui est isolé sur
/// l'acteur principal.
@MainActor
struct LearningSetupView: View {
    @StateObject var viewModel: LearningSetupViewModel

    /// Termine la configuration. Renseignée par le contrôleur une fois la vue construite.
    var finish: Action = {}

    var body: some View {
        NoorList {
            knownSection
            goalsSection
            rhythmSection
            summarySection
        }
        .safeAreaInset(edge: .bottom) {
            createBar
        }
    }

    // MARK: Private

    // MARK: - Ce que je connais déjà

    private var knownSection: some View {
        NoorBasicSection(
            title: l("learning.known.title", table: .learning),
            footer: l("learning.known.detail", table: .learning)
        ) {
            unitPicker(selection: knownUnitBinding)
            pills(viewModel.knownPills, in: .known)
            ForEach(viewModel.knownRows()) { row in
                NoorListItem(
                    title: .text(row.title),
                    subtitle: .init(text: .text(row.subtitle), location: .bottom),
                    accessory: knownAccessory(for: row),
                    action: .sync { viewModel.cycleSolidity(of: row) }
                )
            }
            NoorListItem(
                title: .text(l("learning.known.scratch", table: .learning)),
                action: .sync { viewModel.startFromScratch() }
            )
        }
    }

    /// L'état d'un morceau déclaré connu.
    ///
    /// La coche pleine dit « je le récite sans hésiter », la coche barrée « je l'oublie », et
    /// l'absence de coche « je ne me suis pas prononcé ». Les trois états se suivent au toucher, dans
    /// cet ordre : on ne saute pas de « rien » à « je l'oublie » sans passer par « je le connais ».
    private func knownAccessory(for row: LearningSetupViewModel.PieceRow) -> NoorListItem.Accessory? {
        switch row.solidity {
        case .none: return nil
        case .some(.solide): return .image(.checkmark_checked, color: .accentColor)
        case .some(.fragile): return .image(.checkmark_indeterminate, color: .orange)
        }
    }

    // MARK: - Mon objectif

    private var goalsSection: some View {
        NoorBasicSection(
            title: l("learning.goals.title", table: .learning),
            footer: l("learning.goals.detail", table: .learning)
        ) {
            unitPicker(selection: goalUnitBinding)
            pills(viewModel.goalPills, in: .goal)
            ForEach(viewModel.goalRows()) { row in
                NoorListItem(
                    title: .text(row.title),
                    subtitle: .init(text: .text(row.subtitle), location: .bottom),
                    accessory: checkmark(isOn: row.isGoal),
                    action: .sync { viewModel.toggleGoal(row) }
                )
            }
            NoorListItem(
                title: .text(l("learning.goals.continue", table: .learning)),
                subtitle: .init(text: .text(l("learning.goals.continue.detail", table: .learning)), location: .bottom),
                accessory: .disclosureIndicator,
                action: .sync { viewModel.continueThroughTheQuran() }
            )
        }
    }

    // MARK: - Mon rythme

    /// Le rythme tient en quatre sections : l'allure, les jours, la durée, l'échéance.
    ///
    /// `@ViewBuilder` est indispensable ici : la propriété rend **plusieurs** sections, et sans lui
    /// Swift ne verrait que la première comme expression rendue — les trois autres seraient des
    /// résultats abandonnés, et la propriété n'aurait aucun `return` à inférer.
    @ViewBuilder
    private var rhythmSection: some View {
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

            if viewModel.isCustomPace {
                ForEach(viewModel.customVersesChoices, id: \.self) { verses in
                    NoorListItem(
                        title: .text(lFormat("verses", table: .android, verses)),
                        accessory: checkmark(isOn: viewModel.isVersesPerSession(verses)),
                        action: .sync { viewModel.setVersesPerSession(verses) }
                    )
                }
            }
        }

        NoorBasicSection(title: l("learning.days.title", table: .learning), footer: l("learning.days.detail", table: .learning)) {
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

        NoorBasicSection(title: l("learning.goals.deadline", table: .learning), footer: l("learning.deadline.detail", table: .learning)) {
            deadlineRows
        }
    }

    /// L'échéance : la poser, ce qu'elle impose, et l'effacer.
    ///
    /// Le sélecteur de date n'apparaît qu'une fois l'échéance posée : une date vide à l'écran ne dit
    /// rien, et occuperait la place d'une question qui n'a pas encore été posée.
    @ViewBuilder
    private var deadlineRows: some View {
        if viewModel.deadline == nil {
            NoorListItem(
                title: .text(l("learning.deadline.set", table: .learning)),
                accessory: .disclosureIndicator,
                action: .sync { viewModel.setDeadline(viewModel.defaultDeadline) }
            )
        } else {
            DatePicker(
                l("learning.goals.deadline.date", table: .learning),
                selection: deadlineBinding,
                displayedComponents: .date
            )
            deadlineAdvice
            NoorListItem(
                title: .text(l("learning.deadline.clear", table: .learning)),
                action: .sync { viewModel.setDeadline(nil) }
            )
        }
    }

    /// Ce que l'échéance impose, et le geste qui l'applique.
    @ViewBuilder
    private var deadlineAdvice: some View {
        if let advice = viewModel.deadlineHint {
            if viewModel.holdsDeadline {
                NoorListItem(title: .text(advice))
            } else {
                NoorListItem(
                    title: .text(advice),
                    subtitle: .init(text: .text(l("learning.deadline.apply", table: .learning)), location: .bottom),
                    action: .sync { viewModel.applyRequiredPace() }
                )
            }
        }
    }

    // MARK: - Ce que le programme contiendra

    private var summarySection: some View {
        NoorBasicSection(title: l("learning.summary.title", table: .learning)) {
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

    private var endDateTitle: String {
        guard let date = viewModel.summary.estimatedEndDate else {
            return l("learning.summary.noDays", table: .learning)
        }
        return viewModel.endDateTitle(date)
    }

    // MARK: - Les morceaux

    /// Le sélecteur d'unité, commun aux deux sections qui désignent des morceaux.
    ///
    /// Le libellé est passé en **fonction libre**, et non en méthode du modèle de vue :
    /// `SegmentedChoicesPicker` prend un `(Item) -> String` non isolé, et une méthode d'un objet
    /// `@MainActor` ne s'y prêterait pas. Rien n'est lu ici que le nom de l'unité : il n'y a donc
    /// rien à isoler, et la fermeture ne capture rien du tout.
    private func unitPicker(selection: Binding<LearningUnit>) -> some View {
        SegmentedChoicesPicker(
            title: l("learning.unit.title", table: .learning),
            items: viewModel.units,
            selection: selection,
            label: unitTitle
        )
        .padding(.vertical, 4)
    }

    /// Les morceaux déjà désignés, en pastilles retirables.
    ///
    /// Une grille adaptative plutôt qu'une pile : les pastilles se répartissent sur la largeur
    /// disponible et passent à la ligne toutes seules, quel que soit le nombre de morceaux déclarés
    /// et la taille de l'écran.
    @ViewBuilder
    private func pills(_ pills: [LearningSetupViewModel.Pill], in section: PillSection) -> some View {
        if !pills.isEmpty {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(pills) { pill in
                    LearningPill(title: pill.title, tone: pill.tone(in: section)) {
                        viewModel.remove(pill)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Les liaisons

    private var knownUnitBinding: Binding<LearningUnit> {
        Binding(get: { viewModel.knownUnit }, set: { viewModel.select(knownUnit: $0) })
    }

    private var goalUnitBinding: Binding<LearningUnit> {
        Binding(get: { viewModel.goalUnit }, set: { viewModel.select(goalUnit: $0) })
    }

    /// L'échéance telle que le sélecteur la manipule.
    ///
    /// Le sélecteur n'accepte pas de date absente ; il en faut donc toujours une. Celle par défaut
    /// n'est écrite qu'au premier changement, et non à l'ouverture de l'écran : tant que
    /// l'utilisateur n'a pas touché la date, il n'a pas dit qu'il voulait une échéance.
    private var deadlineBinding: Binding<Date> {
        Binding(
            get: { viewModel.deadline ?? viewModel.defaultDeadline },
            set: { viewModel.setDeadline($0) }
        )
    }

    // MARK: - La barre de création

    private var createBar: some View {
        VStack(spacing: 8) {
            if let footer = createFooter {
                Text(footer)
                    .font(.footnote)
                    .foregroundColor(.secondaryLabel)
                    .multilineTextAlignment(.center)
            }

            Button(action: finish) {
                Text(l("learning.setup.create", table: .learning))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canStart)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial)
    }

    /// Ce qu'il faut lire quand le bouton est éteint.
    ///
    /// Deux raisons distinctes, et deux phrases distinctes : « aucun jour » se corrige dans la
    /// section du rythme, « rien à apprendre » dans celle des objectifs. Les confondre enverrait
    /// l'utilisateur au mauvais endroit.
    private var createFooter: String? {
        guard !viewModel.canStart else { return nil }
        if !viewModel.hasWorkingDays {
            return l("learning.summary.noDays", table: .learning)
        }
        return l("learning.summary.empty", table: .learning)
    }

    private func checkmark(isOn: Bool) -> NoorListItem.Accessory {
        .image(isOn ? .checkmark_checked : .checkmark_unchecked, color: isOn ? Color.accentColor : nil)
    }
}

/// La section d'où une pastille est montrée.
///
/// Elle ne dit pas ce que la pastille **défait** — c'est son type qui le porte — mais à quoi elle
/// sert ici, et donc de quelle couleur elle doit être.
private enum PillSection {
    case known
    case goal
}

private extension LearningSetupViewModel.Pill {
    /// La couleur d'une pastille, selon la section où elle est posée.
    ///
    /// Le type de la pastille dit ce qu'elle défait ; la section, elle, dit à quoi elle sert ici.
    /// Un même morceau déclaré fragile apparaît donc en jaune dans « je connais déjà », et en accent
    /// dans « mon objectif » s'il y est aussi visé — ce qui est exactement la différence à voir.
    func tone(in section: PillSection) -> LearningPill.Tone {
        switch (section, kind) {
        case (.goal, _): return .goal
        case (.known, .solide): return .solide
        case (.known, .fragile): return .fragile
        case (.known, .goal): return .goal
        }
    }
}

/// Le nom d'une unité de choix, dans la langue de l'utilisateur.
///
/// Fonction libre, et non méthode du modèle de vue : c'est ce qui permet de la passer telle quelle
/// à `SegmentedChoicesPicker`, dont le libellé est un `(Item) -> String` non isolé.
private func unitTitle(_ unit: LearningUnit) -> String {
    l("learning.unit.\(unit.rawValue)", table: .learning)
}
