import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettingsStore
    private let localLLMService = LocalLLMService()

    @State private var isTestingConnection = false
    @State private var connectionTestMessage: String?
    @State private var connectionTestIsError = false
    @State private var isRefreshingReasoningOptions = false
    @State private var reasoningOptions = ["none", "off", "on", "low", "medium", "high"]
    @State private var reasoningOptionsMessage: String?
    @State private var reasoningOptionsIsError = false
    @State private var availableLocalModels: [LocalLLMModel] = []

    var body: some View {
        TabView {
            connectionTab
                .tabItem {
                    Label(String(localized: "settings.tab.connection", bundle: .module), systemImage: "network")
                }

            defaultsTab
                .tabItem {
                    Label(String(localized: "settings.tab.defaults", bundle: .module), systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 820, height: 720)
        .onChange(of: settings.selectedLLMProfileID) { _, _ in
            availableLocalModels = []
            connectionTestMessage = nil
            reasoningOptionsMessage = nil
        }
    }

    private var connectionTab: some View {
        Form {
            Section(String(localized: "settings.section.provider", bundle: .module)) {
                Picker(String(localized: "picker.provider", bundle: .module), selection: $settings.selectedProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(String(localized: String.LocalizationValue(provider.localizationKey), bundle: .module))
                            .tag(provider)
                    }
                }
            }

            Section(String(localized: "settings.section.openai", bundle: .module)) {
                SecureField(String(localized: "settings.apiKey", bundle: .module), text: $settings.apiKey)
                    .textFieldStyle(.roundedBorder)

                Text(String(localized: "settings.apiKey.help", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "settings.section.endpoint", bundle: .module)) {
                TextField(String(localized: "settings.host", bundle: .module), text: $settings.serverHost)
                    .textFieldStyle(.roundedBorder)

                TextField(
                    String(localized: "settings.port", bundle: .module),
                    value: $settings.serverPort,
                    formatter: portFormatter
                )
                .textFieldStyle(.roundedBorder)

                Toggle(String(localized: "settings.https", bundle: .module), isOn: $settings.useHTTPS)

                Text(String(localized: "settings.endpoint.help", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "settings.section.localLLM", bundle: .module)) {
                Picker(String(localized: "settings.llmProfile", bundle: .module), selection: $settings.selectedLLMProfileID) {
                    ForEach(settings.llmProfiles) { profile in
                        Text(profile.name)
                            .tag(profile.id)
                    }
                }

                HStack(spacing: 10) {
                    TextField(String(localized: "settings.llmProfile.name", bundle: .module), text: selectedProfileNameBinding)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        settings.addLLMProfile()
                    } label: {
                        Label(String(localized: "settings.llmProfile.add", bundle: .module), systemImage: "plus")
                    }

                    Button {
                        settings.deleteSelectedLLMProfile()
                    } label: {
                        Label(String(localized: "settings.llmProfile.delete", bundle: .module), systemImage: "trash")
                    }
                    .disabled(settings.llmProfiles.count <= 1)
                }

                TextField(String(localized: "settings.local.host", bundle: .module), text: $settings.localServerHost)
                    .textFieldStyle(.roundedBorder)

                TextField(
                    String(localized: "settings.local.port", bundle: .module),
                    value: $settings.localServerPort,
                    formatter: portFormatter
                )
                .textFieldStyle(.roundedBorder)

                Toggle(String(localized: "settings.local.https", bundle: .module), isOn: $settings.localUseHTTPS)

                TextField(String(localized: "settings.local.model", bundle: .module), text: $settings.localModel)
                    .textFieldStyle(.roundedBorder)

                SecureField(String(localized: "settings.local.apiKey", bundle: .module), text: $settings.localApiKey)
                    .textFieldStyle(.roundedBorder)

                TextField(
                    String(localized: "settings.local.timeoutSeconds", bundle: .module),
                    value: $settings.localRequestTimeoutSeconds,
                    formatter: timeoutFormatter
                )
                .textFieldStyle(.roundedBorder)

                Text(String(localized: "settings.local.timeout.help", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "settings.reasoningOn", bundle: .module), selection: $settings.reasoningOnValue) {
                    ForEach(reasoningPickerOptions, id: \.self) { option in
                        Text(reasoningOptionLabel(option)).tag(option)
                    }
                }

                Picker(String(localized: "settings.reasoningOff", bundle: .module), selection: $settings.reasoningOffValue) {
                    ForEach(reasoningPickerOptions, id: \.self) { option in
                        Text(reasoningOptionLabel(option)).tag(option)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await refreshReasoningOptions(reportErrors: true) }
                    } label: {
                        Label(
                            String(localized: "settings.reasoning.refresh", bundle: .module),
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .disabled(isRefreshingReasoningOptions)

                    if isRefreshingReasoningOptions {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let reasoningOptionsMessage {
                        Text(reasoningOptionsMessage)
                            .foregroundStyle(reasoningOptionsIsError ? .red : .green)
                            .font(.callout)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await testCurrentProviderConnection() }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(String(localized: "settings.testConnection", bundle: .module))
                        }
                    }
                    .disabled(isTestingConnection)

                    if let connectionTestMessage {
                        Text(connectionTestMessage)
                            .foregroundStyle(connectionTestIsError ? .red : .green)
                            .font(.callout)
                    }
                }

                if !availableLocalModels.isEmpty {
                    AvailableLocalModelsView(models: availableLocalModels)
                }

                Text(String(localized: "settings.local.help", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task {
            await refreshReasoningOptions(reportErrors: false)
        }
    }

    private var defaultsTab: some View {
        Form {
            Section(String(localized: "settings.section.models", bundle: .module)) {
                Picker(String(localized: "picker.model", bundle: .module), selection: $settings.selectedModel) {
                    ForEach(OpenAIModel.allCases) { model in
                        Text(String(localized: String.LocalizationValue(model.localizationKey), bundle: .module))
                            .tag(model)
                    }
                }

                Toggle(String(localized: "toggle.reasoning", bundle: .module), isOn: $settings.reasoningEnabled)
                Toggle(String(localized: "settings.autoTranslate", bundle: .module), isOn: $settings.autoTranslateEnabled)
                Stepper(
                    value: $settings.alternativeSuggestionCount,
                    in: 1 ... 8
                ) {
                    Text(
                        String(
                            format: String(localized: "settings.alternativeSuggestionCount", bundle: .module),
                            settings.alternativeSuggestionCount
                        )
                    )
                }

                Stepper(
                    value: $settings.correctionAlternativeCount,
                    in: AppSettingsStore.minimumCorrectionAlternativeCount ... AppSettingsStore.maximumCorrectionAlternativeCount
                ) {
                    Text(
                        String(
                            format: String(localized: "settings.correctionAlternativeCount", bundle: .module),
                            settings.correctionAlternativeCount
                        )
                    )
                }
            }

            Section(String(localized: "settings.section.display", bundle: .module)) {
                Stepper(
                    value: $settings.editorFontSize,
                    in: AppSettingsStore.minimumEditorFontSize ... AppSettingsStore.maximumEditorFontSize,
                    step: 1
                ) {
                    Text(
                        String(
                            format: String(localized: "settings.editorFontSize", bundle: .module),
                            settings.editorFontSize
                        )
                    )
                }
            }

            Section(String(localized: "settings.section.captureShortcut", bundle: .module)) {
                Picker(String(localized: "settings.captureShortcut.modifier", bundle: .module), selection: $settings.captureShortcutModifier) {
                    ForEach(TranslationCaptureModifier.allCases) { modifier in
                        Text(String(localized: String.LocalizationValue(modifier.localizationKey), bundle: .module))
                            .tag(modifier)
                    }
                }

                TextField(String(localized: "settings.captureShortcut.key", bundle: .module), text: $settings.captureShortcutKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 120)

                Text(
                    String(
                        format: String(localized: "settings.captureShortcut.current", bundle: .module),
                        captureShortcutDisplayName
                    )
                )
                .font(.callout)

                Text(String(localized: "settings.captureShortcut.help", bundle: .module))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section(String(localized: "settings.section.languages", bundle: .module)) {
                Picker(String(localized: "pane.source", bundle: .module), selection: $settings.sourceLanguage) {
                    ForEach(TranslationLanguage.allCases) { language in
                        Text(String(localized: String.LocalizationValue(language.displayNameKey), bundle: .module))
                            .tag(language)
                    }
                }

                Picker(String(localized: "pane.target", bundle: .module), selection: $settings.targetLanguage) {
                    ForEach(TranslationLanguage.allCases.filter { $0 != .automatic }) { language in
                        Text(String(localized: String.LocalizationValue(language.displayNameKey), bundle: .module))
                            .tag(language)
                    }
                }
            }

            Section(String(localized: "settings.section.style", bundle: .module)) {
                Picker(String(localized: "style.register", bundle: .module), selection: $settings.styleRegister) {
                    ForEach(RegisterStyle.allCases) { value in
                        Text(String(localized: String.LocalizationValue(value.localizationKey), bundle: .module))
                            .tag(value)
                    }
                }

                Picker(String(localized: "style.complexity", bundle: .module), selection: $settings.styleComplexity) {
                    ForEach(ComplexityStyle.allCases) { value in
                        Text(String(localized: String.LocalizationValue(value.localizationKey), bundle: .module))
                            .tag(value)
                    }
                }

                Picker(String(localized: "spelling.mode", bundle: .module), selection: $settings.spellingMode) {
                    ForEach(SpellingMode.allCases) { value in
                        Text(String(localized: String.LocalizationValue(value.localizationKey), bundle: .module))
                            .tag(value)
                    }
                }
            }
        }
        .padding()
    }
}

private struct AvailableLocalModelsView: View {
    let models: [LocalLLMModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "settings.local.models.available", bundle: .module))
                .font(.headline)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(models) { model in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(model.isLoaded ? Color.green : Color.clear)
                                .overlay(Circle().stroke(model.isLoaded ? Color.green : Color.secondary, lineWidth: 1))
                                .frame(width: 10, height: 10)
                            Text(model.name)
                                .fontWeight(model.isLoaded ? .semibold : .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 90, maxHeight: 150)
        }
    }
}

extension SettingsView {
    private var selectedProfileNameBinding: Binding<String> {
        Binding(
            get: { settings.selectedLLMProfileName },
            set: { settings.renameSelectedLLMProfile(to: $0) }
        )
    }

    private var reasoningPickerOptions: [String] {
        var values = reasoningOptions
        values.append(settings.reasoningOnValue)
        values.append(settings.reasoningOffValue)
        return Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted(by: LocalReasoningOptions.sortOptions)
    }

    private var portFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        formatter.minimum = 1
        formatter.maximum = 65_535
        return formatter
    }

    private var timeoutFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 0
        formatter.minimum = 0
        return formatter
    }

    private var captureShortcutDisplayName: String {
        let modifier = String(localized: String.LocalizationValue(settings.captureShortcutModifier.localizationKey), bundle: .module)
        let key = settings.captureShortcut.normalizedKey.uppercased()
        return "\(modifier)+\(key)+\(key)"
    }

    private func reasoningOptionLabel(_ option: String) -> String {
        switch option {
        case "none":
            return String(localized: "settings.reasoning.option.none", bundle: .module)
        case "off":
            return String(localized: "settings.reasoning.option.off", bundle: .module)
        case "on":
            return String(localized: "settings.reasoning.option.on", bundle: .module)
        case "low":
            return String(localized: "settings.reasoning.option.low", bundle: .module)
        case "medium":
            return String(localized: "settings.reasoning.option.medium", bundle: .module)
        case "high":
            return String(localized: "settings.reasoning.option.high", bundle: .module)
        default:
            return option
        }
    }

    @MainActor
    private func testCurrentProviderConnection() async {
        isTestingConnection = true
        connectionTestMessage = nil
        connectionTestIsError = false
        defer { isTestingConnection = false }

        do {
            try await settings.testConnection(for: settings.selectedProvider)
            if settings.selectedProvider == .localLLM {
                let baseURL = try settings.baseURL(for: .localLLM)
                availableLocalModels = try await localLLMService.fetchModelCatalog(
                    apiKey: settings.localApiKey,
                    baseURL: baseURL,
                    timeoutSeconds: settings.localRequestTimeoutSeconds
                )
                useSingleLoadedLocalModelIfNeeded(availableLocalModels)
            } else {
                availableLocalModels = []
            }
            connectionTestMessage = String(localized: "settings.testConnection.success", bundle: .module)
            connectionTestIsError = false
        } catch {
            availableLocalModels = []
            connectionTestMessage = error.localizedDescription
            connectionTestIsError = true
        }
    }

    @MainActor
    private func refreshReasoningOptions(reportErrors: Bool) async {
        guard !isRefreshingReasoningOptions else { return }
        isRefreshingReasoningOptions = true
        if reportErrors {
            reasoningOptionsMessage = nil
            reasoningOptionsIsError = false
        }
        defer { isRefreshingReasoningOptions = false }

        do {
            let baseURL = try settings.baseURL(for: .localLLM)
            let fetched = try await localLLMService.fetchReasoningOptions(
                model: settings.localModel,
                apiKey: settings.localApiKey,
                baseURL: baseURL,
                timeoutSeconds: settings.localRequestTimeoutSeconds
            )

            guard !fetched.allowedOptions.isEmpty else {
                if reportErrors {
                    reasoningOptionsMessage = String(localized: "settings.reasoning.unavailable", bundle: .module)
                    reasoningOptionsIsError = true
                }
                return
            }

            reasoningOptions = fetched.allowedOptions
            if let resolvedModelName = fetched.resolvedModelName,
               resolvedModelName != settings.localModel
            {
                settings.localModel = resolvedModelName
            }
            applyFetchedReasoningOptions(fetched)
            if reportErrors {
                reasoningOptionsMessage = String(localized: "settings.reasoning.refresh.success", bundle: .module)
                reasoningOptionsIsError = false
            }
        } catch {
            if reportErrors {
                reasoningOptionsMessage = error.localizedDescription
                reasoningOptionsIsError = true
            }
        }
    }

    @MainActor
    private func applyFetchedReasoningOptions(_ options: LocalReasoningOptions) {
        let allowed = options.allowedOptions
        guard !allowed.isEmpty else { return }

        if !allowed.contains(settings.reasoningOnValue) {
            settings.reasoningOnValue = preferredReasoningOnValue(from: allowed, defaultOption: options.defaultOption)
        }
        if !allowed.contains(settings.reasoningOffValue) {
            settings.reasoningOffValue = preferredReasoningOffValue(from: allowed, defaultOption: options.defaultOption)
        }
    }

    @MainActor
    private func useSingleLoadedLocalModelIfNeeded(_ models: [LocalLLMModel]) {
        let loadedModels = models.filter(\.isLoaded)
        let modelToUse: LocalLLMModel?
        if loadedModels.count == 1 {
            modelToUse = loadedModels[0]
        } else if loadedModels.isEmpty, models.count == 1 {
            modelToUse = models[0]
        } else {
            modelToUse = nil
        }

        guard let modelToUse else {
            return
        }

        let currentModelName = settings.localModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentModelName.isEmpty || currentModelName != modelToUse.requestName else { return }
        settings.localModel = modelToUse.requestName
    }

    private func preferredReasoningOnValue(from allowed: [String], defaultOption: String?) -> String {
        if let defaultOption, allowed.contains(defaultOption) {
            return defaultOption
        }
        return ["on", "low", "medium", "high", "off", "none"].first(where: allowed.contains) ?? allowed[0]
    }

    private func preferredReasoningOffValue(from allowed: [String], defaultOption: String?) -> String {
        if allowed.contains("off") {
            return "off"
        }
        if allowed.contains("none") {
            return "none"
        }
        if let defaultOption, allowed.contains(defaultOption) {
            return defaultOption
        }
        return allowed[0]
    }
}
