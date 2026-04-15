import SwiftUI
import UIKit
import AVFAudio

struct RephraserView: View {
    @FocusState private var isInputFocused: Bool
    @State private var inputText = ""
    @State private var outputText = ""
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var speaker = SpeechPlayer()
    @State private var voiceOptions = VoiceCatalog.options()
    @State private var selectedVoiceIdentifier: String = ""
    @State private var showingNVCInfo = false

    private let service = BedrockNVCService()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 20) {
                        inputSection
                        if isLoading {
                            loadingIndicator
                        } else if !outputText.isEmpty {
                            outputSection
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }

                bottomBar
            }
            .navigationTitle("Rephrase")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
            .onTapGesture {
                isInputFocused = false
            }
            .alert("Rephrase Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("What would you like to rephrase?", systemImage: "text.quote")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showingNVCInfo.toggle()
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(MoodboundDesign.tint)
                }
            }

            if showingNVCInfo {
                nvcInfoBanner
            }

            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text("Paste a tense message here…")
                        .foregroundStyle(Color(.placeholderText))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $inputText)
                    .focused($isInputFocused)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
            }
            .frame(minHeight: 120)
            .background(Color(.systemGray6).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
            )
        }
    }

    // MARK: - NVC Info

    private var nvcInfoBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What is NVC?")
                .font(.subheadline.weight(.semibold))
            Text("Nonviolent Communication is a framework by Marshall Rosenberg that separates what happened from how you feel, what you need, and what you're asking for.")
                .font(.caption)
            Text("During mood episodes, it's easy to say things you don't mean. NVC slows you down — it turns reactive impulses into clear, honest language that protects your relationships even when your emotions are intense.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoodboundDesign.tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
    }

    // MARK: - Loading

    private var loadingIndicator: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Rephrasing with empathy…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Output

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.subheadline)
                    .foregroundStyle(MoodboundDesign.tint)
                Text("NVC Rewrite")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MoodboundDesign.tint)
                Spacer()
                Button {
                    UIPasteboard.general.string = outputText
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            let sections = parseNVCSections(outputText)
            if sections.isEmpty {
                Text(outputText)
                    .font(.body)
                    .textSelection(.enabled)
            } else {
                ForEach(sections, id: \.label) { section in
                    nvcSectionRow(section)
                }
            }

            Text("Generated by AI — not a substitute for professional advice.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MoodboundDesign.tint.opacity(0.2), lineWidth: 1)
        )
        .textSelection(.enabled)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func nvcSectionRow(_ section: NVCSection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: section.icon)
                .font(.caption)
                .foregroundStyle(MoodboundDesign.tint)
                .frame(width: 20, height: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(section.content)
                    .font(.body)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 12) {
                // Voice picker row
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Voice", selection: $selectedVoiceIdentifier) {
                        ForEach(voiceOptions) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(.secondary)
                    .onAppear {
                        if selectedVoiceIdentifier.isEmpty {
                            selectedVoiceIdentifier = VoiceCatalog.defaultIdentifier()
                        }
                    }
                    Spacer()
                }

                // Action buttons
                HStack(spacing: 10) {
                    Button {
                        Task { await rephrase() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline.weight(.semibold))
                            Text("Rephrase")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .background(MoodboundDesign.tint)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .disabled(isLoading || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(isLoading || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                    Button {
                        let chosen = selectedVoiceIdentifier.isEmpty ? voiceOptions.first?.id : selectedVoiceIdentifier
                        speaker.speak(outputText, voiceIdentifier: chosen)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.subheadline)
                            .frame(width: 44, height: 44)
                    }
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .disabled(outputText.isEmpty)
                    .opacity(outputText.isEmpty ? 0.4 : 1)

                    Button {
                        speaker.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.subheadline)
                            .frame(width: 44, height: 44)
                    }
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }

    // MARK: - NVC Parsing

    private struct NVCSection {
        let label: String
        let icon: String
        let content: String
    }

    private func parseNVCSections(_ text: String) -> [NVCSection] {
        let patterns: [(key: String, label: String, icon: String)] = [
            ("Observation", "Observation", "eye"),
            ("Feeling", "Feeling", "heart"),
            ("Need", "Need", "sparkles"),
            ("Request", "Request", "hand.raised"),
        ]

        var results: [NVCSection] = []
        for pattern in patterns {
            let regex = "\\*\\*\(pattern.key):?\\*\\*:?\\s*"
            guard let range = text.range(of: regex, options: .regularExpression) else { continue }
            let after = text[range.upperBound...]
            // Take everything until the next bold section or end
            let nextBold = after.range(of: "\\*\\*\\w+:?\\*\\*", options: .regularExpression)
            let content: String
            if let nextBold {
                content = String(after[..<nextBold.lowerBound])
            } else {
                content = String(after)
            }
            results.append(NVCSection(
                label: pattern.label,
                icon: pattern.icon,
                content: content.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }
        return results
    }

    private static let maxInputCharacters = 2000

    @MainActor
    private func rephrase() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var cleaned = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.count > Self.maxInputCharacters {
                cleaned = String(cleaned.prefix(Self.maxInputCharacters))
            }
            withAnimation(.easeInOut(duration: 0.3)) {
                outputText = ""
            }
            let result = try await service.rephrase(input: cleaned)
            let guarded = NVCOutputGuard.validate(result)
            withAnimation(.easeInOut(duration: 0.3)) {
                outputText = guarded
            }
        } catch {
            AppLogger.error("NVC rephrase failed", error: error)
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}

@Observable
final class SpeechPlayer {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String, voiceIdentifier: String?) {
        guard !text.isEmpty else { return }
        stop()

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            AppLogger.error("Failed to configure audio session", error: error)
        }

        let cleaned = stripNVCHeadings(text)
        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.rate = 0.5
        if let voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        synthesizer.speak(utterance)
    }

    private func stripNVCHeadings(_ text: String) -> String {
        var result = text
        // Remove markdown headings like ### NVC Rephrasing:
        result = result.replacingOccurrences(of: "###\\s*.*\\n?", with: "", options: .regularExpression)
        // Remove bold labels like **Observation:** or **Feeling:**
        result = result.replacingOccurrences(of: "\\*\\*\\w+:?\\*\\*:?\\s*", with: "", options: .regularExpression)
        // Collapse multiple newlines
        result = result.replacingOccurrences(of: "\\n{2,}", with: "\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

struct VoiceCatalog {
    struct Option: Identifiable {
        let id: String
        let label: String
    }

    /// Natural-sounding voices only, Samantha first.
    private static let allowedNames = ["Samantha", "Karen", "Daniel", "Moira", "Alex", "Ava", "Allison", "Zoe"]

    static let defaultVoiceName = "Samantha"

    static func options() -> [Option] {
        let englishVoices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }

        let matched = allowedNames.compactMap { wanted in
            englishVoices.first(where: { $0.name.caseInsensitiveCompare(wanted) == .orderedSame })
        }

        guard !matched.isEmpty else {
            return [Option(id: "default", label: "Default (System)")]
        }

        return matched.map { voice in
            Option(id: voice.identifier, label: "\(voice.name) (\(voice.language))")
        }
    }

    static func defaultIdentifier() -> String {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        return voices.first(where: { $0.name.caseInsensitiveCompare(defaultVoiceName) == .orderedSame })?.identifier
            ?? options().first?.id ?? "default"
    }
}
