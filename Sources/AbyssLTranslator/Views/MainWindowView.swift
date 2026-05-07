import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
    @ObservedObject private var settings: AppSettingsStore
    @StateObject private var viewModel: TranslationViewModel
    @State private var sourceInjectedText: String?
    @State private var windowChromeTopInset: CGFloat = Self.minimumWindowChromeTopInset

    fileprivate static let minimumWindowChromeTopInset: CGFloat = 36
    fileprivate static let minimumWindowContentSize = NSSize(width: 880, height: 700)

    init(settings: AppSettingsStore) {
        self.settings = settings
        _viewModel = StateObject(wrappedValue: TranslationViewModel(settings: settings))
    }

    var body: some View {
        ZStack {
            DockReopenRegistration()
            WindowFrameAutosaveRegistration(
                name: "AbyssLTranslator.mainWindow",
                minimumContentSize: Self.minimumWindowContentSize
            )
            WindowChromeInsetReader(topInset: $windowChromeTopInset)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                header
                switch viewModel.activeMode {
                case .translator:
                    HStack(alignment: .top, spacing: 12) {
                        sourcePane
                        targetPane
                    }
                    synonymsSection
                case .correction:
                    WritingCorrectionPaneView(settings: settings, viewModel: viewModel)
                case .document:
                    DocumentProcessingPaneView(settings: settings, viewModel: viewModel)
                }
                footerStatus
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .padding(.top, 16 + max(windowChromeTopInset, Self.minimumWindowChromeTopInset))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            syncFromStore()
        }
        .onDisappear {
            viewModel.persistLanguagesAndStyle()
        }
        .onChange(of: settings.sourceLanguage) { _, newValue in
            viewModel.sourceLanguage = newValue
        }
        .onChange(of: settings.targetLanguage) { _, newValue in
            viewModel.targetLanguage = newValue
        }
        .onChange(of: settings.autoTranslateEnabled) { _, newValue in
            viewModel.autoTranslateEnabled = newValue
        }
        .onChange(of: settings.reasoningOnValue) { _, newValue in
            viewModel.reasoningOnValue = newValue
        }
        .onChange(of: settings.reasoningOffValue) { _, newValue in
            viewModel.reasoningOffValue = newValue
        }
        .onChange(of: settings.localModel) { _, newValue in
            viewModel.localModel = newValue
        }
        .onChange(of: settings.selectedLLMProfileID) { _, _ in
            viewModel.localModel = settings.localModel
            viewModel.handleModelOrReasoningChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .abysslTranslateSelection)) { notification in
            if let text = notification.object as? String {
                injectAndTranslate(text)
            } else {
                captureAndTranslateSelection(copySelectionFirst: (notification.object as? Bool) ?? true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .abysslTranslateNow)) { _ in
            viewModel.translateNow()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButton(
                    title: primaryToolbarTitle,
                    systemImage: primaryToolbarSystemImage,
                    isDisabled: !viewModel.canRunPrimaryAction
                ) {
                    switch viewModel.activeMode {
                    case .translator:
                        viewModel.translateNow()
                    case .correction:
                        viewModel.correctWritingNow()
                    case .document:
                        viewModel.startDocumentProcessing()
                    }
                }
            }
        }
    }

    private var primaryToolbarTitle: String {
        switch viewModel.activeMode {
        case .translator:
            return String(localized: "action.translateNow", bundle: .module)
        case .correction:
            return String(localized: "action.correctWriting", bundle: .module)
        case .document:
            return String(localized: "document.action.start", bundle: .module)
        }
    }

    private var primaryToolbarSystemImage: String {
        switch viewModel.activeMode {
        case .translator:
            return "arrow.right"
        case .correction:
            return "checkmark.circle"
        case .document:
            return "play.fill"
        }
    }

    private var header: some View {
        HeaderView(settings: settings, status: viewModel.status, viewModel: viewModel)
    }

    private var sourcePane: some View {
        SourcePaneView(
            sourceLanguage: $viewModel.sourceLanguage,
            injectedText: $sourceInjectedText,
            fontSize: settings.editorFontSize,
            onSourceChanged: { viewModel.onSourceChanged(to: $0) },
            onClear: {
                sourceInjectedText = ""
                viewModel.clearSourceContent()
            }
        )
        .onChange(of: viewModel.sourceLanguage) { _, _ in
            settings.sourceLanguage = viewModel.sourceLanguage
            viewModel.handleLanguageChange()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stylePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker(String(localized: "style.register", bundle: .module), selection: viewModel.registerStyleBinding) {
                    ForEach(RegisterStyle.allCases) { value in
                        Text(String(localized: String.LocalizationValue(value.localizationKey), bundle: .module))
                            .tag(value)
                    }
                }
                .frame(minWidth: 200)

                Picker(String(localized: "style.complexity", bundle: .module), selection: viewModel.complexityStyleBinding) {
                    ForEach(ComplexityStyle.allCases) { value in
                        Text(String(localized: String.LocalizationValue(value.localizationKey), bundle: .module))
                            .tag(value)
                    }
                }
                .frame(minWidth: 220)
            }

            Picker(String(localized: "spelling.mode", bundle: .module), selection: viewModel.spellingModeBinding) {
                ForEach(SpellingMode.allCases) { value in
                    Text(String(localized: String.LocalizationValue(value.localizationKey), bundle: .module))
                        .tag(value)
                }
            }
        }
        .onChange(of: viewModel.style.register) { _, _ in
            persistStyle()
            viewModel.handleStyleChange()
        }
        .onChange(of: viewModel.style.complexity) { _, _ in
            persistStyle()
            viewModel.handleStyleChange()
        }
        .onChange(of: viewModel.style.spellingMode) { _, _ in
            persistStyle()
            viewModel.handleStyleChange()
        }
    }

    private var targetPane: some View {
        TargetPaneView(settings: settings, viewModel: viewModel, output: viewModel.output)
    }

    private var synonymsSection: some View {
        AlternativesSectionView(
            output: viewModel.output,
            fontSize: settings.editorFontSize,
            onPrevious: viewModel.selectPreviousAlternative,
            onNext: viewModel.selectNextAlternative,
            onReload: viewModel.reloadAlternatives,
            onInstructionSubmit: viewModel.suggestAlternativesForSelectedTarget(userInstruction:),
            onApplyAlternative: viewModel.applySynonym
        )
    }

    private var footerStatus: some View {
        FooterStatusView(output: viewModel.output)
    }

    private func persistStyle() {
        settings.styleRegister = viewModel.style.register
        settings.styleComplexity = viewModel.style.complexity
        settings.spellingMode = viewModel.style.spellingMode
    }

    private func syncFromStore() {
        sourceInjectedText = nil
        viewModel.sourceLanguage = settings.sourceLanguage
        viewModel.targetLanguage = settings.targetLanguage
        viewModel.selectedProvider = settings.selectedProvider
        viewModel.selectedModel = settings.selectedModel
        viewModel.localModel = settings.localModel
        viewModel.autoTranslateEnabled = settings.autoTranslateEnabled
        viewModel.reasoningOnValue = settings.reasoningOnValue
        viewModel.reasoningOffValue = settings.reasoningOffValue
        viewModel.reasoningEnabled = settings.reasoningEnabled
        viewModel.style = StyleSettings(
            register: settings.styleRegister,
            complexity: settings.styleComplexity,
            spellingMode: settings.spellingMode
        )
    }

    private func captureAndTranslateSelection(copySelectionFirst: Bool) {
        if copySelectionFirst {
            PasteboardHelper.copyFrontmostSelectionToPasteboard()
        }
        let delay: DispatchTimeInterval = copySelectionFirst ? .milliseconds(80) : .milliseconds(0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let text = PasteboardHelper.stringFromPasteboard(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                injectAndTranslate(text)
            }
        }
    }

    private func injectAndTranslate(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sourceInjectedText = text
        viewModel.onSourceChanged(to: text)
        viewModel.translateNow()
    }
}

private struct PrimaryToolbarButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(isDisabled)
    }
}

private struct HeaderView: View {
    @ObservedObject var settings: AppSettingsStore
    let status: TranslationStatusState
    @ObservedObject var viewModel: TranslationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "app.title", bundle: .module))
                    .font(.title2.bold())
                Picker("", selection: $viewModel.activeMode) {
                    ForEach(MainWorkspaceMode.allCases) { mode in
                        Label(
                            String(localized: String.LocalizationValue(mode.localizationKey), bundle: .module),
                            systemImage: mode.systemImage
                        )
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 430)
                Spacer()
                TranslationProgressView(status: status)
            }

            HStack(spacing: 12) {
                Picker(String(localized: "picker.provider", bundle: .module), selection: $viewModel.selectedProvider) {
                    ForEach(TranslationProvider.allCases) { provider in
                        Text(String(localized: String.LocalizationValue(provider.localizationKey), bundle: .module))
                            .tag(provider)
                    }
                }
                .frame(minWidth: 160)

                if viewModel.selectedProvider == .openAI {
                    Picker(String(localized: "picker.model", bundle: .module), selection: $viewModel.selectedModel) {
                        ForEach(OpenAIModel.allCases) { model in
                            Text(String(localized: String.LocalizationValue(model.localizationKey), bundle: .module))
                                .tag(model)
                        }
                    }
                    .frame(minWidth: 220)
                } else {
                    Picker(String(localized: "settings.llmProfile", bundle: .module), selection: $settings.selectedLLMProfileID) {
                        ForEach(settings.llmProfiles) { profile in
                            Text(profile.name)
                                .tag(profile.id)
                        }
                    }
                    .frame(minWidth: 160)

                    TextField(String(localized: "local.model.placeholder", bundle: .module), text: $viewModel.localModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 220)
                }

                Toggle(String(localized: "toggle.reasoning", bundle: .module), isOn: $viewModel.reasoningEnabled)
                    .help(String(localized: "toggle.reasoning.help", bundle: .module))

                Spacer()

                SettingsLink {
                    Label(String(localized: "settings.open", bundle: .module), systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            .onChange(of: viewModel.selectedModel) { _, _ in
                settings.selectedModel = viewModel.selectedModel
                viewModel.handleModelOrReasoningChange()
            }
            .onChange(of: viewModel.selectedProvider) { _, _ in
                settings.selectedProvider = viewModel.selectedProvider
                viewModel.handleModelOrReasoningChange()
            }
            .onChange(of: viewModel.localModel) { _, _ in
                settings.localModel = viewModel.localModel
                viewModel.handleModelOrReasoningChange()
            }
            .onChange(of: viewModel.autoTranslateEnabled) { _, _ in
                settings.autoTranslateEnabled = viewModel.autoTranslateEnabled
            }
            .onChange(of: viewModel.reasoningEnabled) { _, _ in
                settings.reasoningEnabled = viewModel.reasoningEnabled
                viewModel.handleModelOrReasoningChange()
            }
        }
    }
}

private struct TranslationProgressView: View {
    @ObservedObject var status: TranslationStatusState

    var body: some View {
        ProgressView()
            .scaleEffect(0.85)
            .opacity(status.isTranslating ? 1 : 0)
            .accessibilityHidden(!status.isTranslating)
            .frame(width: 20, height: 20)
    }
}

private struct TargetPaneView: View {
    let settings: AppSettingsStore
    @ObservedObject var viewModel: TranslationViewModel
    @ObservedObject var output: TranslationOutputState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "pane.target", bundle: .module))
                    .font(.headline)
                Spacer()
                Picker(String(localized: "picker.language", bundle: .module), selection: $viewModel.targetLanguage) {
                    ForEach(TranslationLanguage.allCases.filter { $0 != .automatic }) { language in
                        Text(String(localized: String.LocalizationValue(language.displayNameKey), bundle: .module))
                            .tag(language)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 180)

                Button {
                    viewModel.suggestAlternativesForSelectedTarget()
                } label: {
                    if output.isSuggestingAlternatives {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Label(String(localized: "action.suggestAlternatives", bundle: .module), systemImage: "sparkles")
                    }
                }
                .disabled(output.selectedTargetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || output.isSuggestingAlternatives)
                .help(String(localized: "action.suggestAlternatives.help", bundle: .module))

                Button {
                    PasteboardHelper.setString(output.targetText)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(output.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(String(localized: "action.copyTranslation.help", bundle: .module))
                .accessibilityLabel(String(localized: "action.copyTranslation", bundle: .module))
            }

            InsertableTextEditor(
                text: $output.targetText,
                pendingInsertion: $output.pendingTargetInsertion,
                selectedText: $output.selectedTargetText,
                fontSize: settings.editorFontSize
            )
                .frame(minHeight: 260)
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
                .onChange(of: viewModel.targetLanguage) { _, _ in
                    settings.targetLanguage = viewModel.targetLanguage
                    viewModel.handleLanguageChange()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WritingCorrectionPaneView: View {
    let settings: AppSettingsStore
    @ObservedObject var viewModel: TranslationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "mode.correction", bundle: .module))
                    .font(.headline)

                Spacer()

                Picker(String(localized: "writing.style.preset", bundle: .module), selection: $viewModel.selectedWritingStylePreset) {
                    ForEach(WritingStylePreset.allCases) { preset in
                        Text(String(localized: String.LocalizationValue(preset.localizationKey), bundle: .module))
                            .tag(preset)
                    }
                }
                .frame(minWidth: 190)

                Button {
                    viewModel.correctWritingNow()
                } label: {
                    if viewModel.isCorrectingWriting {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Label(String(localized: "action.correctWriting", bundle: .module), systemImage: "checkmark.circle")
                    }
                }
                .disabled(!viewModel.hasCorrectionText || viewModel.isWritingBusy)
                .help(String(localized: "action.correctWriting.help", bundle: .module))

                Button {
                    viewModel.rewriteCorrectionText()
                } label: {
                    if viewModel.isRewritingWriting {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Label(String(localized: "action.rewrite", bundle: .module), systemImage: "wand.and.stars")
                    }
                }
                .disabled(!viewModel.hasCorrectionText || viewModel.isWritingBusy)
                .help(String(localized: "action.rewrite.help", bundle: .module))

                Button {
                    PasteboardHelper.setString(viewModel.correctionText)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(!viewModel.hasCorrectionText)
                .help(String(localized: "action.copyCorrection.help", bundle: .module))
                .accessibilityLabel(String(localized: "action.copyCorrection", bundle: .module))

                Button {
                    viewModel.clearCorrectionContent()
                } label: {
                    Label(String(localized: "action.clearCorrection", bundle: .module), systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.hasCorrectionText && viewModel.correctionIssues.isEmpty)
                .help(String(localized: "action.clearCorrection.help", bundle: .module))
            }

            HStack(spacing: 8) {
                Image(systemName: "text.bubble")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField(
                    String(localized: "writing.instruction.placeholder", bundle: .module),
                    text: $viewModel.writingInstruction
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: settings.editorFontSize))
                .disabled(viewModel.isWritingBusy)
            }

            CorrectionTextEditor(
                text: $viewModel.correctionText,
                corrections: $viewModel.correctionIssues,
                fontSize: settings.editorFontSize
            )
            .frame(minHeight: 430)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct DocumentProcessingPaneView: View {
    let settings: AppSettingsStore
    @ObservedObject var viewModel: TranslationViewModel
    @State private var displayedElapsedSeconds = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                documentDropZone
                exportPanel
            }

            actionBar
            progressSection
            resultsSection
        }
        .onAppear {
            viewModel.ensureSelectedDocumentFormatIsAvailable()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            displayedElapsedSeconds = viewModel.documentProgress.elapsedSeconds
        }
        .onChange(of: viewModel.documentProgress.startedAt) { _, _ in
            displayedElapsedSeconds = viewModel.documentProgress.elapsedSeconds
        }
        .onChange(of: viewModel.documentProgress.finishedAt) { _, _ in
            displayedElapsedSeconds = viewModel.documentProgress.elapsedSeconds
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var documentDropZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "document.drop.title", bundle: .module))
                    .font(.headline)
                Spacer()
                Button {
                    chooseInputFiles()
                } label: {
                    Label(String(localized: "document.action.chooseFiles", bundle: .module), systemImage: "folder.badge.plus")
                }
                Button {
                    viewModel.clearDocumentJobs()
                } label: {
                    Label(String(localized: "document.action.clear", bundle: .module), systemImage: "xmark.circle")
                }
                .disabled(viewModel.documentJobs.isEmpty || viewModel.documentProgress.isRunning)
            }

            DropTargetView(isTargeted: $viewModel.isDocumentDropTargeted) { urls in
                viewModel.addDocumentURLs(urls)
            }

            if let message = viewModel.documentStatusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if viewModel.documentJobs.isEmpty {
                        Text(String(localized: "document.drop.emptyList", bundle: .module))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(viewModel.documentJobs) { job in
                            DocumentJobRow(job: job) {
                                viewModel.removeDocumentJob(job)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 170, maxHeight: 220)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var exportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "document.export.title", bundle: .module))
                .font(.headline)

            HStack(spacing: 10) {
                FileTypeIconView(format: viewModel.documentOptions.exportFormat)
                    .frame(width: 34, height: 34)
                Picker(String(localized: "document.export.format", bundle: .module), selection: $viewModel.documentOptions.exportFormat) {
                    ForEach(viewModel.availableDocumentExportFormats) { format in
                        Label(
                            String(localized: String.LocalizationValue(format.localizationKey), bundle: .module),
                            systemImage: format.systemImage
                        )
                        .tag(format)
                    }
                }
                .frame(minWidth: 240)
            }

            Picker(String(localized: "pane.target", bundle: .module), selection: $viewModel.targetLanguage) {
                ForEach(TranslationLanguage.allCases.filter { $0 != .automatic }) { language in
                    Text(String(localized: String.LocalizationValue(language.displayNameKey), bundle: .module))
                        .tag(language)
                }
            }
            .onChange(of: viewModel.targetLanguage) { _, _ in
                settings.targetLanguage = viewModel.targetLanguage
            }

            HStack(spacing: 8) {
                TextField(
                    String(localized: "document.instruction.placeholder", bundle: .module),
                    text: $viewModel.documentOptions.instruction
                )
                .textFieldStyle(.roundedBorder)
                Button {
                    chooseOutputDirectory()
                } label: {
                    Label(String(localized: "document.action.chooseOutput", bundle: .module), systemImage: "folder")
                }
            }

            Text(viewModel.documentOutputDirectory?.path ?? String(localized: "document.output.none", bundle: .module))
                .font(.callout)
                .foregroundStyle(viewModel.documentOutputDirectory == nil ? .red : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 16) {
                Toggle(String(localized: "document.operation.correct", bundle: .module), isOn: $viewModel.documentOptions.shouldCorrect)
                Toggle(String(localized: "document.operation.translate", bundle: .module), isOn: $viewModel.documentOptions.shouldTranslate)
            }

            if viewModel.documentOptions.exportFormat == .asciidoc {
                Toggle(String(localized: "document.export.images", bundle: .module), isOn: $viewModel.documentOptions.exportImagesForAsciiDoc)
            }

            DisclosureGroup(String(localized: "document.naming.title", bundle: .module)) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(String(localized: "document.naming.customize", bundle: .module), isOn: $viewModel.documentOptions.nameOptions.customizeName)
                    Toggle(String(localized: "document.naming.timestamp", bundle: .module), isOn: $viewModel.documentOptions.nameOptions.appendTimestamp)
                        .disabled(!viewModel.documentOptions.nameOptions.customizeName)
                    Toggle(String(localized: "document.naming.language", bundle: .module), isOn: $viewModel.documentOptions.nameOptions.appendTargetLanguage)
                        .disabled(!viewModel.documentOptions.nameOptions.customizeName)
                    TextField(
                        String(localized: "document.naming.suffix", bundle: .module),
                        text: $viewModel.documentOptions.nameOptions.customSuffix
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(!viewModel.documentOptions.nameOptions.customizeName)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.startDocumentProcessing()
            } label: {
                if viewModel.documentProgress.isRunning {
                    ProgressView()
                        .scaleEffect(0.75)
                } else {
                    Label(String(localized: "document.action.start", bundle: .module), systemImage: "play.fill")
                }
            }
            .disabled(!viewModel.canProcessDocuments)

            Button {
                viewModel.cancelDocumentProcessing()
            } label: {
                Label(String(localized: "document.action.cancel", bundle: .module), systemImage: "stop.fill")
            }
            .disabled(!viewModel.documentProgress.isRunning)

            Spacer()

            Text(
                String(
                    format: String(localized: "document.jobs.summary", bundle: .module),
                    viewModel.supportedDocumentJobs.count,
                    viewModel.documentJobs.count
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.documentProgress.total > 0 {
                ProgressView(
                    value: Double(viewModel.documentProgress.completed),
                    total: Double(max(viewModel.documentProgress.total, 1))
                )
                HStack {
                    Text(
                        String(
                            format: String(localized: "document.progress.counts", bundle: .module),
                            viewModel.documentProgress.completed,
                            viewModel.documentProgress.total,
                            viewModel.documentProgress.remaining
                        )
                    )
                    if let current = viewModel.documentProgress.currentFile {
                        Text(String(format: String(localized: "document.progress.current", bundle: .module), current))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(String(format: String(localized: "document.progress.elapsed", bundle: .module), formattedElapsedSeconds(displayedElapsedSeconds)))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var resultsSection: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(viewModel.documentResults) { result in
                    DocumentResultRow(result: result)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(minHeight: 110, maxHeight: 150)
    }

    private func chooseInputFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "document.action.chooseFiles", bundle: .module)
        if panel.runModal() == .OK {
            viewModel.addDocumentURLs(panel.urls)
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "document.action.chooseOutput", bundle: .module)
        if panel.runModal() == .OK {
            viewModel.setDocumentOutputDirectory(panel.url)
        }
    }

    private func formattedElapsedSeconds(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct DropTargetView: View {
    @Binding var isTargeted: Bool
    let onURLs: ([URL]) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34))
            Text(String(localized: "document.drop.message", bundle: .module))
                .font(.headline)
            Text(String(localized: "document.drop.detail", bundle: .module))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 145)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? Color.accentColor : Color(nsColor: .separatorColor), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isTargeted) { providers in
            loadDroppedURLs(providers)
            return true
        }
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }
                guard let data,
                      let url = URL(dataRepresentation: data, relativeTo: nil)
                else {
                    return
                }
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            onURLs(urls)
        }
    }
}

private struct FileTypeIconView: View {
    let format: DocumentExportFormat

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if let type = UTType(filenameExtension: format.fileExtension) {
            return NSWorkspace.shared.icon(for: type)
        }
        return NSImage(systemSymbolName: format.systemImage, accessibilityDescription: nil) ?? NSImage()
    }
}

private struct DocumentJobRow: View {
    let job: DocumentJob
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.sourceURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(job.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let statusMessage = job.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .font(.callout)
    }
}

private struct DocumentResultRow: View {
    let result: DocumentProcessingResult

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.sourceURL.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let outputURL = result.outputURL {
                    Text(outputURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(result.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .font(.callout)
    }

    private var iconName: String {
        switch result.status {
        case .success:
            return "checkmark.circle.fill"
        case .skipped:
            return "minus.circle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch result.status {
        case .success:
            return .green
        case .skipped:
            return .secondary
        case .failed:
            return .red
        }
    }
}

private struct AlternativesSectionView: View {
    @ObservedObject var output: TranslationOutputState
    @State private var instructionText = ""

    let fontSize: Double
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReload: () -> Void
    let onInstructionSubmit: (String) -> Void
    let onApplyAlternative: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(String(localized: "synonyms.title", bundle: .module))
                    .font(.headline)

                if !output.synonyms.isEmpty {
                    Text("\(output.selectedAlternativeIndex + 1)/\(output.synonyms.count)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onPrevious) {
                    Image(systemName: "chevron.left")
                }
                .disabled(output.synonyms.isEmpty)
                .help(String(localized: "alternatives.previous", bundle: .module))

                Button(action: onNext) {
                    Image(systemName: "chevron.right")
                }
                .disabled(output.synonyms.isEmpty)
                .help(String(localized: "alternatives.next", bundle: .module))

                Button(action: onReload) {
                    if output.isSuggestingAlternatives {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!output.canReloadAlternatives || output.isSuggestingAlternatives)
                .help(String(localized: "alternatives.reload", bundle: .module))
            }

            HStack(spacing: 8) {
                TextField(
                    String(localized: "alternatives.instruction.placeholder", bundle: .module),
                    text: $instructionText
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: fontSize))
                .onSubmit(submitInstruction)

                Button(action: submitInstruction) {
                    if output.isSuggestingAlternatives {
                        ProgressView()
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                }
                .disabled(!canSubmitInstruction)
                .help(String(localized: "alternatives.instruction.submit", bundle: .module))
            }

            if let notes = output.spellingNotes, !notes.isEmpty {
                Text(notes)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.vertical, showsIndicators: true) {
                Button {
                    if let alternative = output.selectedAlternative {
                        onApplyAlternative(alternative)
                    }
                } label: {
                    Text(output.selectedAlternative ?? String(localized: "synonyms.empty", bundle: .module))
                        .font(.system(size: fontSize))
                        .foregroundStyle(output.selectedAlternative == nil ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .disabled(output.selectedAlternative == nil)
                .help(String(localized: "synonyms.insertHelp", bundle: .module))
            }
            .frame(minHeight: 92, maxHeight: 92)
            .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var canSubmitInstruction: Bool {
        !instructionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !output.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !output.isSuggestingAlternatives
    }

    private func submitInstruction() {
        let trimmed = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onInstructionSubmit(trimmed)
    }
}

private struct FooterStatusView: View {
    @ObservedObject var output: TranslationOutputState

    var body: some View {
        Group {
            if let error = output.lastError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct SourcePaneView: View {
    @Binding var sourceLanguage: TranslationLanguage
    @Binding var injectedText: String?
    let fontSize: Double
    let onSourceChanged: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourcePaneHeader(
                sourceLanguage: $sourceLanguage,
                onClear: onClear
            )

            SourceEditorArea(
                injectedText: $injectedText,
                fontSize: fontSize,
                onSourceChanged: onSourceChanged
            )
        }
    }
}

private struct SourcePaneHeader: View {
    @Binding var sourceLanguage: TranslationLanguage
    let onClear: () -> Void

    var body: some View {
        HStack {
            Text(String(localized: "pane.source", bundle: .module))
                .font(.headline)
            Button(action: onClear) {
                Label(String(localized: "action.clearSource", bundle: .module), systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "action.clearSource.help", bundle: .module))
            Spacer()
            Picker(String(localized: "picker.language", bundle: .module), selection: $sourceLanguage) {
                ForEach(TranslationLanguage.allCases) { language in
                    Text(String(localized: String.LocalizationValue(language.displayNameKey), bundle: .module))
                        .tag(language)
                }
            }
            .labelsHidden()
            .frame(minWidth: 180)
        }
    }
}

private struct SourceEditorArea: View {
    @Binding var injectedText: String?
    let fontSize: Double
    let onSourceChanged: (String) -> Void

    var body: some View {
        SourceTextEditor(
            injectedText: $injectedText,
            focusOnAppear: true,
            fontSize: fontSize,
            onTextChanged: onSourceChanged
        )
            .frame(minHeight: 260)
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
    }
}

private struct DockReopenRegistration: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                (NSApp.delegate as? AppDelegate)?.reopenMainWindow = {
                    openWindow(id: "translator")
                }
            }
    }
}

private struct WindowChromeInsetReader: NSViewRepresentable {
    @Binding var topInset: CGFloat

    func makeNSView(context: Context) -> WindowChromeInsetView {
        let view = WindowChromeInsetView()
        view.onTopInsetChange = context.coordinator.updateTopInset
        return view
    }

    func updateNSView(_ nsView: WindowChromeInsetView, context: Context) {
        nsView.onTopInsetChange = context.coordinator.updateTopInset
        nsView.updateTopInset()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(topInset: $topInset)
    }

    final class Coordinator {
        private let topInset: Binding<CGFloat>

        init(topInset: Binding<CGFloat>) {
            self.topInset = topInset
        }

        func updateTopInset(_ nextTopInset: CGFloat) {
            DispatchQueue.main.async {
                guard abs(self.topInset.wrappedValue - nextTopInset) > 0.5 else { return }
                self.topInset.wrappedValue = nextTopInset
            }
        }
    }

    final class WindowChromeInsetView: NSView {
        var onTopInsetChange: ((CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateTopInset()
        }

        override func layout() {
            super.layout()
            updateTopInset()
        }

        func updateTopInset() {
            guard let window,
                  let contentView = window.contentView
            else {
                onTopInsetChange?(MainWindowView.minimumWindowChromeTopInset)
                return
            }

            let layoutRectInContent = contentView.convert(window.contentLayoutRect, from: nil)
            let titlebarOverlap = max(contentView.bounds.maxY - layoutRectInContent.maxY, 0)
            let topInset = max(ceil(titlebarOverlap), MainWindowView.minimumWindowChromeTopInset)
            onTopInsetChange?(min(topInset, 96))
        }
    }
}

private struct WindowFrameAutosaveRegistration: NSViewRepresentable {
    let name: String
    let minimumContentSize: NSSize

    func makeNSView(context: Context) -> WindowFrameAutosaveView {
        let view = WindowFrameAutosaveView()
        view.autosaveName = name
        view.minimumContentSize = minimumContentSize
        return view
    }

    func updateNSView(_ nsView: WindowFrameAutosaveView, context: Context) {
        nsView.autosaveName = name
        nsView.minimumContentSize = minimumContentSize
    }

    final class WindowFrameAutosaveView: NSView {
        var autosaveName: String = "" {
            didSet {
                configuredWindow = nil
                configureWindowIfNeeded()
            }
        }
        var minimumContentSize: NSSize = .zero {
            didSet {
                configureWindowIfNeeded()
                enforceMinimumContentSize()
            }
        }

        private weak var configuredWindow: NSWindow?
        private var notificationObservers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            configureWindowIfNeeded()
        }

        deinit {
            removeNotificationObservers()
        }

        private func configureWindowIfNeeded() {
            guard let window,
                  configuredWindow !== window,
                  !autosaveName.isEmpty
            else {
                return
            }

            removeNotificationObservers()
            configuredWindow = window
            window.contentMinSize = minimumContentSize
            restoreSavedFrame(for: window)
            enforceMinimumContentSize(window)
            registerFrameObservers(for: window)
            persistFrame(for: window)
        }

        private func enforceMinimumContentSize(_ targetWindow: NSWindow? = nil) {
            let targetWindow = targetWindow ?? window
            guard let targetWindow,
                  minimumContentSize.width > 0,
                  minimumContentSize.height > 0
            else {
                return
            }

            targetWindow.contentMinSize = minimumContentSize
            let currentSize = targetWindow.contentLayoutRect.size
            let nextSize = NSSize(
                width: max(currentSize.width, minimumContentSize.width),
                height: max(currentSize.height, minimumContentSize.height)
            )
            guard nextSize != currentSize else { return }
            targetWindow.setContentSize(nextSize)
        }

        private var frameDefaultsKey: String {
            "abyssl.windowFrame.\(autosaveName)"
        }

        private func restoreSavedFrame(for window: NSWindow) {
            guard let savedFrameString = UserDefaults.standard.string(forKey: frameDefaultsKey) else { return }
            let savedFrame = NSRectFromString(savedFrameString)
            guard savedFrame.width > 0,
                  savedFrame.height > 0,
                  frameIntersectsVisibleScreen(savedFrame)
            else {
                return
            }
            window.setFrame(savedFrame, display: false)
        }

        private func persistFrame(for window: NSWindow) {
            UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: frameDefaultsKey)
        }

        private func registerFrameObservers(for window: NSWindow) {
            let center = NotificationCenter.default
            notificationObservers = [
                center.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.persistFrame(for: window)
                },
                center.addObserver(
                    forName: NSWindow.didEndLiveResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.enforceMinimumContentSize(window)
                    self.persistFrame(for: window)
                },
                center.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    self.persistFrame(for: window)
                },
            ]
        }

        private func removeNotificationObservers() {
            let center = NotificationCenter.default
            for observer in notificationObservers {
                center.removeObserver(observer)
            }
            notificationObservers = []
        }

        private func frameIntersectsVisibleScreen(_ frame: NSRect) -> Bool {
            NSScreen.screens.contains { screen in
                screen.visibleFrame.intersects(frame)
            }
        }
    }
}
