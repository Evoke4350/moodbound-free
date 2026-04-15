import SwiftUI
import SwiftData
import CoreLocation

struct NewEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MoodEntry.timestamp, order: .reverse) private var recentEntries: [MoodEntry]
    @Query(filter: #Predicate<Medication> { $0.isActive }, sort: \Medication.name)
    private var activeMedications: [Medication]
    @Query(sort: \TriggerFactor.name) private var allTriggers: [TriggerFactor]

    private let entryToEdit: MoodEntry?

    @State private var timestamp: Date
    @State private var moodLevel: Int
    @State private var energy: Int
    @State private var sleepHours: Double
    @State private var irritability: Int
    @State private var anxiety: Int
    @State private var note: String
    @State private var selectedMedicationNames: Set<String> = []
    @State private var medsTaken: Bool
    @State private var selectedTriggerNames: Set<String> = []
    @State private var newTriggerText: String = ""
    @State private var newMedicationText: String = ""
    @State private var newlyAddedTriggers: Set<String> = []
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""
    @State private var didApplyDefaults = false
    @State private var currentWeather: WeatherKitWeatherService.CurrentWeather?
    @State private var weatherStatus: WeatherFetchStatus = .idle
    @State private var locationService = LocationService()
    @State private var sleepSource: SleepSource = .manual
    @State private var restingHeartRate: Double?
    @State private var hrvSDNN: Double?
    @State private var stepCount: Int?
    @State private var mindfulMinutes: Double?
    @State private var checkinStartTime: Date = Date()
    @AppStorage("healthKitSleepEnabled") private var healthKitSleepEnabled = false
    @AppStorage("healthKitFullEnabled") private var healthKitFullEnabled = false

    init(entryToEdit: MoodEntry? = nil) {
        self.entryToEdit = entryToEdit
        _timestamp = State(initialValue: entryToEdit?.timestamp ?? AppClock.now)
        _moodLevel = State(initialValue: entryToEdit?.moodLevel ?? 0)
        _energy = State(initialValue: entryToEdit?.energy ?? 3)
        _sleepHours = State(initialValue: entryToEdit?.sleepHours ?? 7)
        _irritability = State(initialValue: entryToEdit?.irritability ?? 0)
        _anxiety = State(initialValue: entryToEdit?.anxiety ?? 0)
        _note = State(initialValue: entryToEdit?.note ?? "")
        let medicationNames = entryToEdit?.medicationNames ?? []
        _medsTaken = State(initialValue: !medicationNames.isEmpty)
        _selectedMedicationNames = State(initialValue: Set(medicationNames.map { $0.lowercased() }))
        let existingTriggers = entryToEdit?.triggerEvents.compactMap { $0.trigger?.name } ?? []
        _selectedTriggerNames = State(initialValue: Set(existingTriggers.map { $0.lowercased() }))

        // Preserve any weather already attached to the entry being edited.
        // Without this, fetchWeatherIfNeeded short-circuits on edit, currentWeather
        // stays nil, and saveAndDismiss writes nil into every weather field —
        // wiping the original record on every edit.
        if let entry = entryToEdit, let code = entry.weatherCode, let tempC = entry.temperatureC {
            let preloaded = WeatherKitWeatherService.CurrentWeather(
                city: entry.weatherCity ?? "",
                weatherCode: code,
                temperatureC: tempC,
                precipitationMM: entry.precipitationMM ?? 0,
                summary: entry.weatherSummary ?? ""
            )
            _currentWeather = State(initialValue: preloaded)
            _weatherStatus = State(initialValue: .success)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let prompt = topAdaptivePrompt {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(MoodboundDesign.tint)
                                Text(prompt.title)
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(prompt.prompt)
                                .font(.body)
                            Text(prompt.rationale)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Suggested focus: \(prompt.title). \(prompt.prompt)")
                    } header: {
                        Text("Worth noting today")
                    }
                }

                Section {
                    DatePicker("When", selection: $timestamp)
                }

                Section {
                    VStack(spacing: 12) {
                        Text(moodEmoji)
                            .font(.system(size: 60))

                        Text(moodLabel)
                            .font(.headline)
                            .foregroundStyle(moodColor)

                        MoodSlider(value: $moodLevel)
                            .padding(.horizontal)

                        HStack {
                            Text("Depression")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                            Spacer()
                            Text("Balanced")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Spacer()
                            Text("Mania")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("How are you feeling?")
                }

                Section {
                    HStack {
                        ForEach(1...5, id: \.self) { level in
                            Button {
                                energy = level
                            } label: {
                                Image(systemName: level <= energy ? "bolt.fill" : "bolt")
                                    .font(.title2)
                                    .foregroundStyle(level <= energy ? .orange : .gray.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Energy level \(level)")
                            .accessibilityValue(level == energy ? "Selected" : "Not selected")
                            if level < 5 { Spacer() }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Energy Level")
                }

                Section {
                    HStack {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(.indigo)
                        Slider(value: $sleepHours, in: 0...16, step: 0.5)
                            .accessibilityLabel("Sleep hours")
                            .accessibilityValue("\(String(format: "%.1f", sleepHours)) hours")
                        Text(String(format: "%.1fh", sleepHours))
                            .monospacedDigit()
                            .frame(width: 44)
                    }
                    if sleepSource == .healthKit {
                        HStack(spacing: 6) {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                            Text("From Apple Health — adjust if needed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(hasLoggedSleepToday ? "Include naps or additional rest since your last check-in. Set to 0 if none." : "How much sleep did you get last night?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Sleep")
                }

                Section {
                    Stepper("Irritability: \(irritability)/3", value: $irritability, in: 0...3)
                    Stepper("Anxiety: \(anxiety)/3", value: $anxiety, in: 0...3)
                } header: {
                    Text("Warning Signs")
                }

                Section {
                    Toggle("Medications taken", isOn: $medsTaken)
                    if !activeMedications.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(activeMedications) { med in
                                ChipToggle(
                                    label: med.name,
                                    isOn: selectedMedicationNames.contains(med.normalizedName)
                                ) {
                                    if selectedMedicationNames.contains(med.normalizedName) {
                                        selectedMedicationNames.remove(med.normalizedName)
                                    } else {
                                        selectedMedicationNames.insert(med.normalizedName)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    HStack {
                        TextField("Add new medication…", text: $newMedicationText)
                            .textInputAutocapitalization(.words)
                        if !newMedicationText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                let name = newMedicationText.trimmingCharacters(in: .whitespaces)
                                let normalized = Medication.normalize(name)
                                selectedMedicationNames.insert(normalized)
                                medsTaken = true
                                newMedicationText = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(MoodboundDesign.tint)
                            }
                        }
                    }
                } header: {
                    Text("Medication")
                }

                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(allTriggers) { trigger in
                            ChipToggle(
                                label: trigger.name,
                                isOn: selectedTriggerNames.contains(trigger.normalizedName)
                            ) {
                                if selectedTriggerNames.contains(trigger.normalizedName) {
                                    selectedTriggerNames.remove(trigger.normalizedName)
                                } else {
                                    selectedTriggerNames.insert(trigger.normalizedName)
                                }
                            }
                        }
                        ForEach(newlyAddedTriggerNames, id: \.self) { name in
                            ChipToggle(
                                label: name,
                                isOn: true
                            ) {
                                let normalized = TriggerFactor.normalize(name)
                                selectedTriggerNames.remove(normalized)
                                newlyAddedTriggers.remove(name)
                            }
                        }
                    }
                    .padding(.vertical, allTriggers.isEmpty && newlyAddedTriggers.isEmpty ? 0 : 4)

                    HStack {
                        TextField("Add new trigger…", text: $newTriggerText)
                            .textInputAutocapitalization(.words)
                        if !newTriggerText.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button {
                                let name = newTriggerText.trimmingCharacters(in: .whitespaces)
                                let normalized = TriggerFactor.normalize(name)
                                let existingNormalized = Set(allTriggers.map(\.normalizedName))
                                if !existingNormalized.contains(normalized) {
                                    newlyAddedTriggers.insert(name)
                                }
                                selectedTriggerNames.insert(normalized)
                                newTriggerText = ""
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(MoodboundDesign.tint)
                            }
                        }
                    }
                } header: {
                    Text("Triggers")
                }

                Section {
                    TextField("Anything you want to remember...", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                }

                weatherSection

                if healthKitFullEnabled, hasAnyHealthData {
                    healthDataSection
                }
            }
            .navigationTitle(entryToEdit == nil ? "New Entry" : "Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .sensoryFeedback(.selection, trigger: moodLevel)
            .sensoryFeedback(.selection, trigger: energy)
            .onAppear { applySmartDefaults() }
            .task { await fetchWeatherIfNeeded() }
            .task { await fetchHealthKitData() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(entryToEdit == nil ? "Save" : "Update") {
                        saveAndDismiss()
                    }
                    .fontWeight(.bold)
                    .buttonStyle(PressableScaleButtonStyle())
                    .accessibilityIdentifier("entry-save-button")
                }
            }
            .alert("Couldn't Save Entry", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func saveAndDismiss() {
        let saveTimestamp = timestamp
        let saveMoodLevel = moodLevel
        // Normalize empty strings to nil so a preloaded weather record without a
        // city doesn't round-trip as "" on save.
        let weatherCityForSave: String? = {
            guard let city = currentWeather?.city, !city.isEmpty else { return nil }
            return city
        }()
        let weatherSummaryForSave: String? = {
            guard let summary = currentWeather?.summary, !summary.isEmpty else { return nil }
            return summary
        }()
        do {
            let entry: MoodEntry
            if let entryToEdit {
                try entryToEdit.applyValidatedUpdate(
                    timestamp: timestamp,
                    moodLevel: moodLevel,
                    energy: energy,
                    sleepHours: sleepHours,
                    irritability: irritability,
                    anxiety: anxiety,
                    note: note,
                    weatherCity: weatherCityForSave,
                    weatherCode: currentWeather?.weatherCode,
                    weatherSummary: weatherSummaryForSave,
                    temperatureC: currentWeather?.temperatureC,
                    precipitationMM: currentWeather?.precipitationMM,
                    restingHeartRate: restingHeartRate,
                    hrvSDNN: hrvSDNN,
                    stepCount: stepCount,
                    mindfulMinutes: mindfulMinutes
                )
                entry = entryToEdit
            } else {
                entry = try MoodEntry.makeValidated(
                    timestamp: timestamp,
                    moodLevel: moodLevel,
                    energy: energy,
                    sleepHours: sleepHours,
                    irritability: irritability,
                    anxiety: anxiety,
                    note: note,
                    weatherCity: weatherCityForSave,
                    weatherCode: currentWeather?.weatherCode,
                    weatherSummary: weatherSummaryForSave,
                    temperatureC: currentWeather?.temperatureC,
                    precipitationMM: currentWeather?.precipitationMM,
                    restingHeartRate: restingHeartRate,
                    hrvSDNN: hrvSDNN,
                    stepCount: stepCount,
                    mindfulMinutes: mindfulMinutes
                )
                context.insert(entry)
            }

            try syncStructuredAssociations(for: entry)
            try context.save()

            // Write to HealthKit in background after successful save
            if healthKitFullEnabled {
                let checkinStart = checkinStartTime
                Task.detached {
                    if #available(iOS 18.0, *) {
                        await HealthKitService.writeStateOfMind(
                            moodLevel: saveMoodLevel,
                            timestamp: saveTimestamp
                        )
                    }
                    await HealthKitService.writeMindfulSession(
                        start: checkinStart,
                        end: Date()
                    )
                }
            }

            dismiss()
        } catch {
            AppLogger.error("Failed to save mood entry", error: error)
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }

    private func applySmartDefaults() {
        guard entryToEdit == nil, !didApplyDefaults, let last = recentEntries.first else { return }
        didApplyDefaults = true

        if hasLoggedSleepToday {
            sleepHours = 0
        } else {
            sleepHours = last.sleepHours
        }
        energy = last.energy

        // Carry forward active medications from last entry
        let lastMeds = last.medicationNames.map { $0.lowercased() }
        if !lastMeds.isEmpty {
            selectedMedicationNames = Set(lastMeds)
            medsTaken = true
        }
    }

    private func syncStructuredAssociations(for entry: MoodEntry) throws {
        for event in entry.medicationAdherenceEvents {
            context.delete(event)
        }
        entry.medicationAdherenceEvents.removeAll()

        for event in entry.triggerEvents {
            context.delete(event)
        }
        entry.triggerEvents.removeAll()

        // Resolve selected medication names back to display names, including newly typed ones
        let medNames: [String] = {
            var names = activeMedications
                .filter { selectedMedicationNames.contains($0.normalizedName) }
                .map(\.name)
            let existingNormalized = Set(activeMedications.map(\.normalizedName))
            for normalized in selectedMedicationNames where !existingNormalized.contains(normalized) {
                names.append(normalized.capitalized)
            }
            return names
        }()

        for name in medNames {
            let medication = try findOrCreateMedication(named: name)
            let adherence = MedicationAdherenceEvent(
                timestamp: timestamp,
                taken: medsTaken,
                note: medsTaken ? "Marked taken in entry" : "Marked not taken in entry",
                medication: medication,
                moodEntry: entry
            )
            context.insert(adherence)
            entry.medicationAdherenceEvents.append(adherence)
        }

        // Resolve selected trigger names, including any newly typed ones
        let triggerNames: [String] = {
            var names = allTriggers
                .filter { selectedTriggerNames.contains($0.normalizedName) }
                .map(\.name)
            // Add any newly typed trigger that doesn't match existing
            let existingNormalized = Set(allTriggers.map(\.normalizedName))
            for normalized in selectedTriggerNames where !existingNormalized.contains(normalized) {
                // Capitalize for display
                names.append(normalized.capitalized)
            }
            return names
        }()

        for name in triggerNames {
            let trigger = try findOrCreateTrigger(named: name)
            let event = TriggerEvent(
                timestamp: timestamp,
                intensity: 2,
                note: "",
                trigger: trigger,
                moodEntry: entry
            )
            context.insert(event)
            entry.triggerEvents.append(event)
        }
    }

    private func findOrCreateMedication(named name: String) throws -> Medication {
        let normalized = Medication.normalize(name)
        let descriptor = FetchDescriptor<Medication>(
            predicate: #Predicate { medication in
                medication.normalizedName == normalized
            }
        )
        if let existing = try context.fetch(descriptor).first {
            if existing.name != name {
                existing.name = name
                existing.normalizedName = normalized
            }
            existing.isActive = true
            return existing
        }
        let created = Medication(name: name)
        context.insert(created)
        return created
    }

    private func findOrCreateTrigger(named name: String) throws -> TriggerFactor {
        let normalized = TriggerFactor.normalize(name)
        let descriptor = FetchDescriptor<TriggerFactor>(
            predicate: #Predicate { trigger in
                trigger.normalizedName == normalized
            }
        )
        if let existing = try context.fetch(descriptor).first {
            if existing.name != name {
                existing.name = name
                existing.normalizedName = normalized
            }
            return existing
        }
        let created = TriggerFactor(name: name)
        context.insert(created)
        return created
    }

    private var moodEmoji: String {
        moodScale.emoji
    }

    private var moodLabel: String {
        moodScale.label
    }

    private var moodColor: Color {
        moodScale.color
    }

    private var moodScale: MoodScale {
        MoodScale(rawValue: moodLevel) ?? .balanced
    }

    /// B3: Top adaptive prompt from the insight snapshot, shown as a soft
    /// header section above the entry form to nudge users toward the
    /// information with the highest marginal value. Only surfaces when the
    /// user has enough history to produce a snapshot at all; otherwise the
    /// form stays static. Sanitized through SafetyCopyPolicy for
    /// future-proofing — prompts are template-generated today but this
    /// keeps them honest if we ever route them through an LLM.
    private var topAdaptivePrompt: AdaptivePrompt? {
        guard recentEntries.count >= 3 else { return nil }
        let snapshot = InsightEngine.snapshot(entries: recentEntries, now: AppClock.now)
        guard let raw = snapshot.adaptivePrompts.first else { return nil }
        return AdaptivePrompt(
            id: raw.id,
            title: SafetyCopyPolicy.sanitizeMessage(raw.title),
            prompt: SafetyCopyPolicy.sanitizeMessage(raw.prompt),
            rationale: SafetyCopyPolicy.sanitizeMessage(raw.rationale),
            informationGain: raw.informationGain
        )
    }

    private var hasLoggedSleepToday: Bool {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: AppClock.now)
        return recentEntries.contains { calendar.startOfDay(for: $0.timestamp) == todayStart }
    }

    private var newlyAddedTriggerNames: [String] {
        let existingNormalized = Set(allTriggers.map(\.normalizedName))
        return newlyAddedTriggers
            .filter { !existingNormalized.contains(TriggerFactor.normalize($0)) }
            .sorted()
    }

    @ViewBuilder
    private var weatherSection: some View {
        Section {
            switch weatherStatus {
            case .idle, .fetching:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Getting local weather…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .success:
                if let w = currentWeather {
                    HStack(spacing: 10) {
                        Text(weatherEmoji(for: w.weatherCode))
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(w.summary), \(formattedTemperature(w.temperatureC))")
                                .font(.subheadline.weight(.semibold))
                            Text(w.city)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            currentWeather = nil
                            weatherStatus = .skipped
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove weather")
                    }
                }
            case .denied:
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.secondary)
                    Text("Location access needed for weather")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .failed:
                HStack(spacing: 8) {
                    Image(systemName: "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text("Couldn't load weather")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await fetchWeatherIfNeeded() }
                    }
                    .font(.subheadline)
                }
            case .skipped:
                EmptyView()
            }
        } header: {
            if weatherStatus != .skipped {
                Text("Weather")
            }
        }
    }

    private func fetchWeatherIfNeeded() async {
        guard entryToEdit == nil, weatherStatus == .idle else { return }
        weatherStatus = .fetching

        do {
            let location = try await locationService.requestOneShotLocation()

            async let placemarksFetch = CLGeocoder().reverseGeocodeLocation(location)
            async let weatherFetch = WeatherKitWeatherService.fetchCurrentWeather(
                for: location, city: ""
            )

            // Reverse geocoding is best-effort: a network blip or throttling
            // shouldn't fail the whole weather fetch. Treat the city as nil if
            // the geocoder errors out.
            let placemarks = (try? await placemarksFetch) ?? []
            let placemark = placemarks.first
            let cityName = placemark?.locality ?? placemark?.administrativeArea

            var weather = try await weatherFetch
            weather = WeatherKitWeatherService.CurrentWeather(
                city: cityName ?? "",
                weatherCode: weather.weatherCode,
                temperatureC: weather.temperatureC,
                precipitationMM: weather.precipitationMM,
                summary: weather.summary
            )
            currentWeather = weather
            weatherStatus = .success
        } catch let error as CLError where error.code == .denied {
            weatherStatus = .denied
        } catch {
            AppLogger.error("Weather fetch failed", error: error)
            weatherStatus = .failed
        }
    }

    private func fetchHealthKitData() async {
        guard entryToEdit == nil else { return }

        // Sleep (uses its own toggle for backwards compat)
        if healthKitSleepEnabled, !hasLoggedSleepToday {
            if let hours = await HealthKitService.fetchLastNightSleepHours() {
                sleepHours = hours
                sleepSource = .healthKit
            }
        }

        // Additional health data requires full toggle
        guard healthKitFullEnabled else { return }

        async let hr = HealthKitService.fetchRestingHeartRate()
        async let hrv = HealthKitService.fetchHRV()
        async let steps = HealthKitService.fetchTodayStepCount()
        async let mindful = HealthKitService.fetchTodayMindfulMinutes()

        let (hrVal, hrvVal, stepsVal, mindfulVal) = await (hr, hrv, steps, mindful)
        restingHeartRate = hrVal
        hrvSDNN = hrvVal
        stepCount = stepsVal
        mindfulMinutes = mindfulVal
    }

    private var hasAnyHealthData: Bool {
        restingHeartRate != nil || hrvSDNN != nil || stepCount != nil || mindfulMinutes != nil
    }

    @ViewBuilder
    private var healthDataSection: some View {
        Section {
            if let hr = restingHeartRate {
                HStack {
                    Label("Resting HR", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Spacer()
                    Text("\(Int(hr)) bpm")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let hrv = hrvSDNN {
                HStack {
                    Label("HRV", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("\(Int(hrv)) ms")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let steps = stepCount {
                HStack {
                    Label("Steps", systemImage: "figure.walk")
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(steps.formatted())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            if let minutes = mindfulMinutes {
                HStack {
                    Label("Mindful", systemImage: "brain.head.profile")
                        .foregroundStyle(.purple)
                    Spacer()
                    Text("\(Int(minutes)) min")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text("Apple Health")
            }
        }
    }

    private func formattedTemperature(_ celsius: Double) -> String {
        let usesMetric = Locale.current.measurementSystem == .metric
        if usesMetric {
            return "\(Int(celsius.rounded()))°C"
        } else {
            let fahrenheit = celsius * 9.0 / 5.0 + 32.0
            return "\(Int(fahrenheit.rounded()))°F"
        }
    }

    private func weatherEmoji(for code: Int) -> String {
        switch code {
        case 0: return "☀️"
        case 1, 2: return "🌤️"
        case 3: return "☁️"
        case 45, 48: return "🌫️"
        case 51, 53, 55, 56, 57: return "🌦️"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "🌧️"
        case 71, 73, 75, 77, 85, 86: return "❄️"
        case 95, 96, 99: return "⛈️"
        default: return "🌡️"
        }
    }
}

enum WeatherFetchStatus {
    case idle, fetching, success, denied, failed, skipped
}

enum SleepSource {
    case manual, healthKit
}

struct MoodSlider: View {
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(-3...3, id: \.self) { level in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        value = level
                    }
                } label: {
                    Circle()
                        .fill(level == value ? colorFor(level) : colorFor(level).opacity(0.2))
                        .frame(width: level == value ? 36 : 24, height: level == value ? 36 : 24)
                        .overlay {
                            if level == value {
                                Circle()
                                    .strokeBorder(Color(.systemBackground), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mood level \(level)")
                .accessibilityValue(value == level ? "Selected" : "Not selected")
                if level < 3 { Spacer() }
            }
        }
    }

    private func colorFor(_ level: Int) -> Color {
        MoodScale(rawValue: level)?.color ?? .gray
    }
}
