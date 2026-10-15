import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var patchDraftCoordinator: PatchDraftCoordinator
    @EnvironmentObject private var patchStore: PatchProjectStore
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @AppStorage(FeatureVisibility.developerModeStorageKey)
    private var developerModeEnabled = false
    @State private var tabNavigation: AppTabNavigationState
    @State private var showSettings = false
    @State private var showLogs = false
    @State private var isPanelVisible = false
    @State private var accessKey = ""
    @State private var isVerifyingAccess = false
    @State private var accessError: String?
    @State private var expandedPanelCategory: RX7PanelCategory? = .weaponHolograms
    @State private var enabledPanelOptions: Set<String> = []
    @State private var activationNotice: PanelActivationNotice?
    @State private var showPatchLibrary = false
    @State private var antennaPatchActionInProgress: Set<String> = []
    @State private var antennaPatchActionError: String?
    @State private var showAntennaApplyConfirmation = false
    @State private var pendingAntennaApplyOption: String?
    @State private var pendingAntennaApplyCategory: RX7PanelCategory?
    @State private var showChangedAntennaRestoreConfirmation = false
    @State private var changedAntennaRestoreOption: String?
    @State private var changedAntennaRestoreCategory: RX7PanelCategory?
    @State private var changedAntennaRestoreCount = 0
    @State private var antennaPatchAssignments: [String: UUID] = [:]
    @AppStorage("drt.antennaPatchAssignments") private var antennaPatchAssignmentsJSON = "{}"
    @State private var weaponPatchAssignments: [String: UUID] = [:]
    @AppStorage("drt.weaponPatchAssignments") private var weaponPatchAssignmentsJSON = "{}"
    @State private var characterPatchAssignments: [String: UUID] = [:]
    @AppStorage("drt.characterPatchAssignments") private var characterPatchAssignmentsJSON = "{}"

    init() {
#if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        let initialTab: Int
        if arguments.contains("--simulate-new-tab") {
            initialTab = 1
        } else if arguments.contains("--simulate-sources-tab") {
            initialTab = 2
        } else if arguments.contains("--simulate-installed-tab")
                    || arguments.contains("--simulate-patch-tab")
                    || arguments.contains("--simulate-wallpaper-tab") {
            initialTab = 3
        } else if arguments.contains("--simulate-files-tab") {
            initialTab = 4
        } else if arguments.contains("--simulate-search-tab") {
            initialTab = 5
        } else {
            initialTab = 0
        }
        _tabNavigation = State(initialValue: AppTabNavigationState(selectedTab: initialTab))
        _showSettings = State(
            initialValue: arguments.contains("--simulate-settings")
        )
#else
        _tabNavigation = State(initialValue: AppTabNavigationState())
#endif
    }

    var body: some View {
        ZStack {
            ZStack {
                RX7PanelStyle.background
                Circle()
                    .fill(RX7PanelStyle.cyan.opacity(0.08))
                    .frame(width: 330, height: 330)
                    .blur(radius: 90)
                    .offset(x: 150, y: -310)
                Circle()
                    .fill(RX7PanelStyle.purple.opacity(0.06))
                    .frame(width: 300, height: 300)
                    .blur(radius: 90)
                    .offset(x: -160, y: 260)
            }
            .ignoresSafeArea()

            if isPanelVisible {
                optionsPanel
            } else {
                accessScreen
            }
        }
        .overlay(alignment: .top) {
            if let activationNotice, isPanelVisible {
                activationNoticeView(activationNotice)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: isPanelVisible)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activationNotice?.id)
        .sheet(isPresented: $showPatchLibrary, onDismiss: refreshProfilePatchStates) {
            PatchProjectsView()
                .patchStorePresentation(patchStore)
        }
        .alert(
            "No se pudo cambiar el patch",
            isPresented: Binding(
                get: { antennaPatchActionError != nil },
                set: { if !$0 { antennaPatchActionError = nil } }
            )
        ) {
            Button("Aceptar", role: .cancel) {
                antennaPatchActionError = nil
            }
        } message: {
            Text(antennaPatchActionError ?? "Ocurrió un error desconocido.")
        }
        .confirmationDialog(
            language.text("patch.apply_confirm_title"),
            isPresented: $showAntennaApplyConfirmation,
            titleVisibility: .visible
        ) {
            Button(language.text("patch.apply")) {
                if let option = pendingAntennaApplyOption,
                   let category = pendingAntennaApplyCategory {
                    setProfilePatch(option, in: category, enabled: true, confirmed: true)
                }
            }
            Button(language.text("common.cancel"), role: .cancel) {
                pendingAntennaApplyOption = nil
                pendingAntennaApplyCategory = nil
            }
        } message: {
            Text(language.text("patch.apply_confirm_message"))
        }
        .confirmationDialog(
            "Los archivos del patch cambiaron",
            isPresented: $showChangedAntennaRestoreConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restaurar originales de todas formas", role: .destructive) {
                restoreChangedAntennaPatch()
            }
            Button("Cancelar", role: .cancel) {
                changedAntennaRestoreOption = nil
                changedAntennaRestoreCategory = nil
                changedAntennaRestoreCount = 0
                pendingAntennaApplyOption = nil
                pendingAntennaApplyCategory = nil
            }
        } message: {
            Text("Se detectaron \(changedAntennaRestoreCount) archivos modificados desde que se aplicó el patch. Restaurarlos reemplazará esos cambios por los archivos originales.")
        }
    }

    private var accessScreen: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 12) {
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(RX7PanelStyle.gold)
                            .frame(width: 7, height: 7)
                        Text("DRT PANEL")
                            .font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .tracking(1.5)
                    }
                    .foregroundStyle(.white.opacity(0.92))

                    Spacer()

                    Text("DRT 10")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white.opacity(0.42))
                }
                .padding(.horizontal, 4)

                Image("BrandLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .shadow(color: RX7PanelStyle.gold.opacity(0.18), radius: 27, y: 8)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EL MEJOR ACCESO DRT iOS")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(RX7PanelStyle.gold)

                        Text("Bienvenido a DRT")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Introduce la key que te otorgó el creador de DRT iOS.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.64))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 3)

                    HStack {
                        Label("KEY DE ACCESO", systemImage: "key.fill")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.1)
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        HStack(spacing: 5) {
                            Circle()
                                .fill(RX7PanelStyle.gold)
                                .frame(width: 4, height: 4)
                            Text("KEY PERSONAL")
                        }
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(RX7PanelStyle.gold.opacity(0.82))
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(RX7PanelStyle.gold)
                            .frame(width: 24, height: 24)

                        SecureField("Introduce tu key", text: $accessKey)
                            .font(.system(size: 14, design: .monospaced))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit(enterPanel)
                            .onChange(of: accessKey) { _ in accessError = nil }
                            .accessibilityLabel("Key de acceso")
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 48)
                    .overlay {
                        Rectangle()
                            .stroke(.white.opacity(0.28), lineWidth: 1)
                    }

                    Text("Tu key es personal. Si no la tienes, solicítala a quien te la otorgó.")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.white.opacity(0.43))
                        .fixedSize(horizontal: false, vertical: true)

                    if let accessError {
                        Text(accessError)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isStaticText)
                    } else if !accessKey.isEmpty && !isAccessKeyFormatValid {
                        Text("Formato esperado: DRT EXTERNAL XXXXX")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: enterPanel) {
                        HStack(spacing: 10) {
                            Text(isVerifyingAccess ? "VERIFICANDO…" : "CONTINUAR")
                                .tracking(1.7)
                            if isVerifyingAccess {
                                ProgressView()
                                    .tint(.black)
                            } else {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .font(.system(size: 12, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.black.opacity(isAccessKeyFormatValid ? 0.9 : 0.56))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            LinearGradient(
                                colors: [RX7PanelStyle.gold, RX7PanelStyle.goldDeep],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Rectangle()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAccessKeyFormatValid || isVerifyingAccess)
                }
                .padding(.horizontal, 2)

                    Spacer(minLength: 12)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                        Text("PANEL DE ACCESO · VALIDACIÓN PENDIENTE")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 460)
                .frame(minHeight: max(0, geometry.size.height - 50), alignment: .top)
                .padding(.horizontal, 25)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var optionsPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("DRT IOS EL PAPÁ DE LOS POLLITOS")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.82))
                        Spacer()
                        Button {
                            isPanelVisible = false
                            accessKey = ""
                            activationNotice = nil
                        } label: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundStyle(.white.opacity(0.66))
                        }
                        .accessibilityLabel("Cerrar sesión")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.black.opacity(0.42), in: Capsule())

                    HStack(spacing: 13) {
                        Image("BrandLogo")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 58, height: 58)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PANEL RX7")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Toca un apartado para ver sus opciones")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.56))
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(RX7PanelStyle.cyan)
                    }
                    .padding(16)
                    .background(RX7PanelStyle.card, in: RoundedRectangle(cornerRadius: 23))
                    .overlay {
                        RoundedRectangle(cornerRadius: 23)
                            .stroke(RX7PanelStyle.cyan.opacity(0.18), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 16, y: 7)

                    Button {
                        showPatchLibrary = true
                    } label: {
                        Label("IMPORTAR / ADMINISTRAR PATCHES", systemImage: "shippingbox")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(RX7PanelStyle.gold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .overlay {
                                Rectangle()
                                    .stroke(RX7PanelStyle.gold.opacity(0.35), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 12) {
                        ForEach(RX7PanelCategory.visibleCases) { category in
                            categorySection(category)
                        }
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity)
            }
            .onAppear(perform: refreshProfilePatchStates)

        }
    }

    private func categorySection(_ category: RX7PanelCategory) -> some View {
        let isExpanded = expandedPanelCategory == category

        return VStack(spacing: 9) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedPanelCategory = isExpanded ? nil : category
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(RX7PanelStyle.purple)
                        .frame(width: 38, height: 38)
                        .background(
                            RX7PanelStyle.purple.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 4)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .tracking(0.5)
                            .foregroundStyle(.white)
                        Text("\(category.options.count) OPCIONES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.58))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isExpanded ? RX7PanelStyle.purple.opacity(0.62) : .white.opacity(0.14))
                        .frame(height: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Oculta las opciones" : "Muestra las opciones")

            if isExpanded {
                VStack(spacing: 9) {
                    ForEach(category.options, id: \.self) { option in
                        optionRow(option, in: category)
                    }
                }
                .padding(.leading, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func optionRow(_ option: String, in category: RX7PanelCategory) -> some View {
        if category == .antennaOptions
            || category == .weaponHolograms
            || category == .characterHolograms {
            profilePatchOptionRow(option, in: category)
        } else {
            previewOptionRow(option)
        }
    }

    private func previewOptionRow(_ option: String) -> some View {
        Toggle(
            isOn: Binding(
                get: { enabledPanelOptions.contains(option) },
                set: { isEnabled in
                    if isEnabled {
                        enabledPanelOptions.insert(option)
                    } else {
                        enabledPanelOptions.remove(option)
                    }
                    showActivationNotice(for: option, isEnabled: isEnabled)
                }
            )
        ) {
            HStack(spacing: 12) {
                Image(systemName: "sparkle")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(RX7PanelStyle.purple)
                    .frame(width: 39, height: 39)
                    .background(RX7PanelStyle.purple.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 4) {
                    Text(option)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    Text(enabledPanelOptions.contains(option) ? "SELECCIONADO" : "TOCA PARA ACTIVAR")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .tint(RX7PanelStyle.purple)
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(RX7PanelStyle.card, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .stroke(
                    enabledPanelOptions.contains(option)
                        ? RX7PanelStyle.purple.opacity(0.55)
                        : .white.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private func profilePatchOptionRow(
        _ option: String,
        in category: RX7PanelCategory
    ) -> some View {
        let assignedProjectID = profileAssignments(in: category)[option]
        let assignedItem = patchStore.items.first(where: { $0.id == assignedProjectID })
        let assignedProjectName = assignedItem?.project?.name
        let isEnabled = enabledPanelOptions.contains(option)
        let isWorking = antennaPatchActionInProgress.contains(option)
        let isConfigurationActionBlocked = !antennaPatchActionInProgress.isEmpty
            || showAntennaApplyConfirmation
            || showChangedAntennaRestoreConfirmation
        let accent: Color
        let symbol: String
        switch category {
        case .weaponHolograms:
            accent = RX7PanelStyle.purple
            symbol = "sparkles"
        case .characterHolograms:
            accent = RX7PanelStyle.cyan
            symbol = "person.fill"
        default:
            accent = RX7PanelStyle.gold
            symbol = "antenna.radiowaves.left.and.right"
        }

        return HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(accent)
                .frame(width: 39, height: 39)
                .background(accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 13))

            VStack(alignment: .leading, spacing: 5) {
                Text(option)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(isWorking
                    ? "PROCESANDO PATCH…"
                    : (assignedProjectName.map { "PATCH: \($0)" }
                        ?? (assignedProjectID == nil ? "ASIGNA UN PAQUETE .3105" : "PATCH NO DISPONIBLE")))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Menu {
                let availableProjects = assignablePatchItems(for: option, in: category)
                if availableProjects.isEmpty {
                    Text("No hay patches compatibles disponibles.")
                } else {
                    ForEach(availableProjects) { item in
                        Button {
                            assignProfilePatch(item.id, to: option, in: category)
                        } label: {
                            if assignedProjectID == item.id {
                                Label(item.project?.name ?? "Patch", systemImage: "checkmark")
                            } else {
                                Text(item.project?.name ?? "Patch")
                            }
                        }
                    }
                }
                if assignedProjectID != nil && !isEnabled {
                    Button("Quitar asignación", role: .destructive) {
                        assignProfilePatch(nil, to: option, in: category)
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .disabled(isEnabled || isConfigurationActionBlocked || patchStore.isBusy)
            .accessibilityLabel("Asignar patch a \(option)")

            Toggle(
                isOn: Binding(
                    get: { enabledPanelOptions.contains(option) },
                    set: { setProfilePatch(option, in: category, enabled: $0) }
                )
            ) {
                EmptyView()
            }
            .labelsHidden()
            .tint(accent)
            .disabled(assignedItem == nil || isConfigurationActionBlocked || patchStore.isBusy)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .background(RX7PanelStyle.card, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .stroke(
                    isEnabled ? accent.opacity(0.6) : .white.opacity(0.08),
                    lineWidth: 1
                )
        }
    }

    private func profileAssignments(in category: RX7PanelCategory) -> [String: UUID] {
        switch category {
        case .antennaOptions: return antennaPatchAssignments
        case .weaponHolograms: return weaponPatchAssignments
        case .characterHolograms: return characterPatchAssignments
        default: return [:]
        }
    }

    private func assignablePatchItems(
        for option: String,
        in category: RX7PanelCategory
    ) -> [PatchLibraryItem] {
        let assignments = profileAssignments(in: category)
        return patchStore.items.filter { item in
            guard let project = item.project,
                  project.rules.count == 1,
                  project.rules.first?.hasReplacement == true else {
                return false
            }
            return assignments.allSatisfy { assignedOption, assignedProjectID in
                assignedOption == option || assignedProjectID != item.id
            }
        }
    }

    private func assignProfilePatch(
        _ projectID: UUID?,
        to option: String,
        in category: RX7PanelCategory
    ) {
        var assignments = profileAssignments(in: category)
        if let projectID {
            guard !assignments.contains(where: { $0.key != option && $0.value == projectID }) else {
                antennaPatchActionError = "Cada opción necesita un paquete distinto."
                return
            }
            assignments[option] = projectID
        } else {
            assignments.removeValue(forKey: option)
        }

        do {
            let data = try JSONEncoder().encode(assignments)
            guard let encoded = String(data: data, encoding: .utf8) else {
                throw PatchAssignmentPersistenceError.encodingFailed
            }
            switch category {
            case .antennaOptions:
                antennaPatchAssignmentsJSON = encoded
                antennaPatchAssignments = assignments
            case .weaponHolograms:
                weaponPatchAssignmentsJSON = encoded
                weaponPatchAssignments = assignments
            case .characterHolograms:
                characterPatchAssignmentsJSON = encoded
                characterPatchAssignments = assignments
            default:
                throw PatchAssignmentPersistenceError.encodingFailed
            }
        } catch {
            antennaPatchActionError = "No se pudo guardar la asignación: \(error.localizedDescription)"
        }
    }

    private func refreshAntennaPatchState() {
        refreshProfilePatchState(in: .antennaOptions)
    }

    private func refreshWeaponPatchState() {
        refreshProfilePatchState(in: .weaponHolograms)
    }

    private func refreshCharacterPatchState() {
        refreshProfilePatchState(in: .characterHolograms)
    }

    private func refreshProfilePatchStates() {
        refreshAntennaPatchState()
        refreshWeaponPatchState()
        refreshCharacterPatchState()
    }

    private func refreshProfilePatchState(in category: RX7PanelCategory) {
        let savedAssignments: String
        switch category {
        case .antennaOptions: savedAssignments = antennaPatchAssignmentsJSON
        case .weaponHolograms: savedAssignments = weaponPatchAssignmentsJSON
        case .characterHolograms: savedAssignments = characterPatchAssignmentsJSON
        default: return
        }

        do {
            guard let data = savedAssignments.data(using: .utf8) else {
                throw PatchAssignmentPersistenceError.encodingFailed
            }
            let assignments = try JSONDecoder().decode([String: UUID].self, from: data)
            switch category {
            case .antennaOptions: antennaPatchAssignments = assignments
            case .weaponHolograms: weaponPatchAssignments = assignments
            case .characterHolograms: characterPatchAssignments = assignments
            default: return
            }

            let options = Set(category.options)
            let appliedOptions = Set(assignments.compactMap { option, projectID in
                DevicePatchService.latestReceipt(projectID: projectID) == nil ? nil : option
            })
            enabledPanelOptions.subtract(options)
            enabledPanelOptions.formUnion(appliedOptions)
        } catch {
            antennaPatchActionError = "No se pudieron leer las asignaciones guardadas: \(error.localizedDescription)"
        }
    }

    private func setProfilePatch(
        _ option: String,
        in category: RX7PanelCategory,
        enabled: Bool,
        confirmed: Bool = false
    ) {
        guard !antennaPatchActionInProgress.contains(option) else { return }
        let assignments = profileAssignments(in: category)
        if enabled && !confirmed {
            guard assignments[option] != nil else {
                antennaPatchActionError = "Asigna primero un paquete .3105 válido a esta opción."
                return
            }
            pendingAntennaApplyOption = option
            pendingAntennaApplyCategory = category
            showAntennaApplyConfirmation = true
            return
        }
        guard let targetRelativePath = category.profileTargetRelativePath,
              let projectID = assignments[option],
              let item = patchStore.items.first(where: { $0.id == projectID }),
              let baseProject = item.project else {
            antennaPatchActionError = "Asigna primero un paquete .3105 válido a esta opción."
            return
        }

        let currentAssignments = assignments
        let configurationOptions = category.options
        antennaPatchActionInProgress.insert(option)
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try LimitedCleanerService.cleanOwnTemporaryData()
                    var restoredOptions: [String] = []
                    if enabled {
                        let project = item.summary.schemaVersion >= 2 && item.canInspectContents
                            ? try PatchProjectLibrary.synchronizeWorkspace(item: item)
                            : baseProject
                        let targetProject = try DevicePatchService.profileProject(
                            from: project,
                            targetRelativePath: targetRelativePath
                        )
                        let activeOptions = configurationOptions.filter { activeOption in
                            guard activeOption != option,
                                  let activeProjectID = currentAssignments[activeOption] else {
                                return false
                            }
                            return DevicePatchService.latestReceipt(projectID: activeProjectID) != nil
                        }
                        for activeOption in activeOptions {
                            guard let activeProjectID = currentAssignments[activeOption],
                                  let receipt = DevicePatchService.latestReceipt(projectID: activeProjectID) else {
                                continue
                            }
                            let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
                            guard inspection.changedTargets.isEmpty else {
                                return AntennaPatchOperationResult(
                                    category,
                                    activeOption,
                                    inspection.changedTargets.map(\.displayPath),
                                    restoredOptions
                                )
                            }
                            try DevicePatchService.restore(receipt: receipt)
                            restoredOptions.append(activeOption)
                        }
                        _ = try DevicePatchService.apply(project: targetProject)
                        return AntennaPatchOperationResult(category, nil, [], restoredOptions)
                    } else {
                        guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else {
                            throw PatchPackageError.invalidProject
                        }
                        let inspection = try DevicePatchService.inspectRestore(receipt: receipt)
                        guard inspection.changedTargets.isEmpty else {
                            return AntennaPatchOperationResult(
                                category,
                                option,
                                inspection.changedTargets.map(\.displayPath),
                                []
                            )
                        }
                        try DevicePatchService.restore(receipt: receipt)
                        return AntennaPatchOperationResult(category, nil, [], [option])
                    }
                }.value

                for restoredOption in result.restoredOptions {
                    enabledPanelOptions.remove(restoredOption)
                }
                if !result.changedTargets.isEmpty {
                    changedAntennaRestoreOption = result.changedOption
                    changedAntennaRestoreCategory = result.category
                    changedAntennaRestoreCount = result.changedTargets.count
                    showChangedAntennaRestoreConfirmation = true
                    antennaPatchActionInProgress.remove(option)
                    return
                }

                if enabled {
                    enabledPanelOptions.insert(option)
                } else {
                    enabledPanelOptions.remove(option)
                }
                patchStore.reload()
                showActivationNotice(for: option, isEnabled: enabled, appliedPatch: true)
                if enabled {
                    pendingAntennaApplyOption = nil
                    pendingAntennaApplyCategory = nil
                }
            } catch {
                antennaPatchActionError = error.localizedDescription
                refreshProfilePatchState(in: category)
                if enabled {
                    pendingAntennaApplyOption = nil
                    pendingAntennaApplyCategory = nil
                }
            }
            antennaPatchActionInProgress.remove(option)
        }
    }

    private func restoreChangedAntennaPatch() {
        guard let option = changedAntennaRestoreOption,
              let category = changedAntennaRestoreCategory,
              let projectID = profileAssignments(in: category)[option] else {
            antennaPatchActionError = "No se encontró la asignación necesaria para restaurar el patch."
            return
        }

        antennaPatchActionInProgress.insert(option)
        var didRestore = false
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try LimitedCleanerService.cleanOwnTemporaryData()
                    guard let receipt = DevicePatchService.latestReceipt(projectID: projectID) else {
                        throw PatchPackageError.invalidProject
                    }
                    try DevicePatchService.restore(receipt: receipt, allowChangedTargets: true)
                }.value
                didRestore = true

                enabledPanelOptions.remove(option)
                patchStore.reload()
                showActivationNotice(for: option, isEnabled: false, appliedPatch: true)
            } catch {
                antennaPatchActionError = error.localizedDescription
                refreshProfilePatchState(in: category)
            }
            antennaPatchActionInProgress.remove(option)
            changedAntennaRestoreOption = nil
            changedAntennaRestoreCategory = nil
            changedAntennaRestoreCount = 0
            let optionToApply = didRestore ? pendingAntennaApplyOption : nil
            let categoryToApply = didRestore ? pendingAntennaApplyCategory : nil
            pendingAntennaApplyOption = nil
            pendingAntennaApplyCategory = nil
            if let optionToApply, let categoryToApply {
                setProfilePatch(optionToApply, in: categoryToApply, enabled: true, confirmed: true)
            }
        }
    }

    private func activationNoticeView(_ notice: PanelActivationNotice) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notice.isEnabled ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(notice.isEnabled ? RX7PanelStyle.cyan : .white.opacity(0.7))

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.appliedPatch
                    ? (notice.isEnabled ? "PATCH APLICADO" : "PATCH RESTAURADO")
                    : "VISTA PREVIA")
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(RX7PanelStyle.cyan)
                Text(notice.title)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(notice.option)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19))
        .overlay {
            RoundedRectangle(cornerRadius: 19)
                .stroke(RX7PanelStyle.cyan.opacity(0.3), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 20, y: 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func showActivationNotice(
        for option: String,
        isEnabled: Bool,
        appliedPatch: Bool = false
    ) {
        let status = isEnabled ? "ACTIVADO" : "DESACTIVADO"
        let notice = PanelActivationNotice(
            title: "DRT iOS \(status)",
            option: option,
            isEnabled: isEnabled,
            appliedPatch: appliedPatch
        )

        activationNotice = notice
        UIAccessibility.post(
            notification: .announcement,
            argument: notice.appliedPatch
                ? "\(notice.title): \(option)."
                : "\(notice.title): \(option). Vista previa; todavía no se ha aplicado ningún patch."
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.7) {
            guard self.activationNotice?.id == notice.id else { return }
            self.activationNotice = nil
        }
    }

    private var normalizedAccessKey: String {
        accessKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var isAccessKeyFormatValid: Bool {
        normalizedAccessKey.range(
            of: #"^DRT EXTERNAL [A-Z0-9]{5}$"#,
            options: .regularExpression
        ) != nil
    }

    private func enterPanel() {
        guard !isVerifyingAccess else { return }
        guard isAccessKeyFormatValid else {
            accessError = "Introduce una licencia con el formato DRT EXTERNAL XXXXX."
            return
        }
        guard let deviceID = UIDevice.current.identifierForVendor?.uuidString else {
            accessError = "No se pudo obtener el identificador de este dispositivo."
            return
        }
        guard let verifyURL = Bundle.main.object(
            forInfoDictionaryKey: "DRTLicenseVerifyURL"
        ) as? String,
              let url = URL(string: verifyURL),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else {
            accessError = "La dirección del servidor de licencias no es válida."
            return
        }

        isVerifyingAccess = true
        accessError = nil
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        do {
            request.httpBody = try JSONEncoder().encode(
                LicenseVerificationRequest(key: normalizedAccessKey, deviceID: deviceID)
            )
        } catch {
            isVerifyingAccess = false
            accessError = "No se pudo preparar la solicitud de verificación."
            return
        }

        Task { @MainActor in
            defer { isVerifyingAccess = false }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw LicenseVerificationError.invalidResponse
                }

                let result = try? JSONDecoder().decode(
                    LicenseVerificationResponse.self,
                    from: data
                )
                if result?.status == "invalid" {
                    throw LicenseVerificationError.invalidLicense
                }
                if httpResponse.statusCode == 403 || result?.status == "expired" {
                    throw LicenseVerificationError.expiredOrUsedElsewhere
                }
                if httpResponse.statusCode == 404 {
                    throw LicenseVerificationError.endpointNotFound
                }
                guard (200..<300).contains(httpResponse.statusCode),
                      result?.status == "success" else {
                    throw LicenseVerificationError.rejected(
                        result?.message ?? "El servidor no pudo verificar la licencia."
                    )
                }
                isPanelVisible = true
            } catch let error as LicenseVerificationError {
                accessError = error.localizedDescription
            } catch {
                accessError = LicenseVerificationError.connectionFailed.localizedDescription
            }
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .navigationTitle("3105")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            RepositoryHomeView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .new:
            RepositoryNewView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .sources:
            RepositorySourcesView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .installed:
            PatchProjectsView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .files:
            AppDataBrowserView(
                tabSession: filesTabSession,
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        case .search:
            RepositorySearchView(
                onOpenSettings: openSettings,
                onOpenLogs: openLogs
            )
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var filesTabSession: Binding<FilesTabSession> {
        Binding(
            get: { tabNavigation.filesTabs },
            set: { tabNavigation.setFilesTabs($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility(developerModeEnabled: developerModeActive)
    }

    private var developerModeActive: Bool {
#if targetEnvironment(simulator)
        developerModeEnabled
            || ProcessInfo.processInfo.arguments.contains("--simulate-developer-mode")
            || ProcessInfo.processInfo.arguments.contains("--simulate-files-tab")
#else
        developerModeEnabled
#endif
    }

    private var selectedVisibleSection: AppSection {
        let selected = AppSection(rawValue: tabNavigation.selectedTab)
        return selected.flatMap {
            featureVisibility.isVisible($0) ? $0 : nil
        } ?? .home
    }

    private func openSettings() {
        showSettings = true
    }

    private func openLogs() {
        showLogs = true
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private enum RX7PanelCategory: String, CaseIterable, Identifiable, Sendable {
    case primaryOptions
    case antennaOptions
    case weaponHolograms
    case characterHolograms
    case movement

    static let visibleCases: [RX7PanelCategory] = [
        .weaponHolograms,
        .characterHolograms,
        .antennaOptions
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .primaryOptions: return "OPCIONES PRINCIPALES"
        case .antennaOptions: return "CONFIGURACIÓN C"
        case .weaponHolograms: return "CONFIGURACIÓN A"
        case .characterHolograms: return "CONFIGURACIÓN B"
        case .movement: return "MOVIMIENTO"
        }
    }

    var symbol: String {
        switch self {
        case .primaryOptions, .antennaOptions: return "slider.horizontal.3"
        case .weaponHolograms: return "sparkles"
        case .characterHolograms: return "person.fill"
        case .movement: return "figure.walk"
        }
    }

    var options: [String] {
        switch self {
        case .primaryOptions:
            return (1...5).map { "Opción \($0)" }
        case .antennaOptions:
            return (1...4).map { "Configuración C · \($0)" }
        case .weaponHolograms:
            return (1...3).map { "Configuración A · \($0)" }
        case .characterHolograms:
            return ["Configuración B · 1"]
        case .movement:
            return ["Movimiento"]
        }
    }

    var profileTargetRelativePath: String? {
        switch self {
        case .weaponHolograms:
            return DevicePatchService.configurationATargetRelativePath
        case .characterHolograms:
            return DevicePatchService.configurationBTargetRelativePath
        case .antennaOptions:
            return DevicePatchService.configurationCTargetRelativePath
        default:
            return nil
        }
    }
}

private struct PanelActivationNotice: Identifiable {
    let id = UUID()
    let title: String
    let option: String
    let isEnabled: Bool
    let appliedPatch: Bool
}

private struct AntennaPatchOperationResult: Sendable {
    let category: RX7PanelCategory
    let changedOption: String?
    let changedTargets: [String]
    let restoredOptions: [String]

    init(
        _ category: RX7PanelCategory,
        _ changedOption: String?,
        _ changedTargets: [String],
        _ restoredOptions: [String]
    ) {
        self.category = category
        self.changedOption = changedOption
        self.changedTargets = changedTargets
        self.restoredOptions = restoredOptions
    }
}

private enum PatchAssignmentPersistenceError: LocalizedError {
    case encodingFailed

    var errorDescription: String? {
        "No se pudo codificar la lista de asignaciones de patches."
    }
}

private struct LicenseVerificationRequest: Encodable {
    let key: String
    let deviceID: String

    private enum CodingKeys: String, CodingKey {
        case key
        case deviceID = "device_id"
    }
}

private struct LicenseVerificationResponse: Decodable {
    let status: String
    let message: String?
}

private enum LicenseVerificationError: LocalizedError {
    case invalidResponse
    case invalidLicense
    case expiredOrUsedElsewhere
    case endpointNotFound
    case connectionFailed
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "El servidor devolvió una respuesta no válida."
        case .invalidLicense:
            return "La licencia no es válida."
        case .expiredOrUsedElsewhere:
            return "La licencia ha expirado o ya fue utilizada en otro equipo."
        case .endpointNotFound:
            return "El servidor no encontró /verify. Revisa la URL del servidor y que esté desplegada la versión correcta."
        case .connectionFailed:
            return "No se pudo contactar al servidor. Comprueba tu conexión e inténtalo de nuevo."
        case .rejected(let message):
            return message.isEmpty
                ? "El servidor rechazó la licencia."
                : message
        }
    }
}

private enum RX7PanelStyle {
    static let background = Color(red: 0.015, green: 0.035, blue: 0.055)
    static let card = Color(red: 0.045, green: 0.055, blue: 0.085).opacity(0.96)
    static let cyan = Color(red: 0.20, green: 0.78, blue: 0.94)
    static let blue = Color(red: 0.08, green: 0.42, blue: 0.56)
    static let purple = Color(red: 0.63, green: 0.22, blue: 0.96)
    static let gold = Color(red: 1.00, green: 0.76, blue: 0.34)
    static let goldDeep = Color(red: 0.96, green: 0.48, blue: 0.17)
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        case .new: return "tab.new"
        case .sources: return "tab.sources"
        case .installed: return "tab.installed"
        case .files: return "tab.files"
        case .search: return "tab.search"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .new: return "clock.fill"
        case .sources: return "shippingbox.fill"
        case .installed: return "tray.full.fill"
        case .files: return "folder.fill"
        case .search: return "magnifyingglass"
        }
    }

}
