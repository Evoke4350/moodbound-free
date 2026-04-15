# Moodbound

Mood tracking built for bipolar disorder. Reads your body through Apple Health, detects pattern shifts with Bayesian models, warns you when something is changing.

On-device. Open source. [$2.99 on the App Store.](https://apps.apple.com/app/moodbound)

![Swift](https://img.shields.io/badge/Swift-5.9-orange) ![iOS](https://img.shields.io/badge/iOS-17.0%2B-blue) ![License](https://img.shields.io/badge/License-MIT-green) ![HealthKit](https://img.shields.io/badge/HealthKit-Integrated-red)

## Why this exists

Most mood tracking apps are diaries. You log, you read it back, you interpret it yourself. That works for some people. For bipolar disorder, where the condition itself can prevent you from noticing your own shifts, a diary is not enough.

Moodbound runs probabilistic models against your check-ins and biometric data to catch what you might miss. Low HRV for three days, sleep dropping below six hours, activity cratering: these patterns mean something, and Moodbound connects them to your mood trajectory automatically.

## Features

### Check-ins

- Seven-point mood scale: severe depression (-3) through mania (+3)
- Energy, sleep hours, irritability, anxiety
- Medication adherence with structured tracking
- Custom trigger factors with intensity ratings
- Free-form notes
- Adaptive prompts that suggest what to log next, ranked by information gain

### Apple Health

- **Reads**: sleep, resting heart rate, HRV (SDNN), step count, mindful minutes
- **Writes**: State of Mind (iOS 18+), mindful session per check-in
- Granular opt-in. Two levels: sleep-only or full integration.

### Analytics

- Bayesian safety engine with four severity tiers (none, elevated, high, critical)
- Online change-point detection for mood episode transitions
- Conformal prediction intervals on 7-day risk forecasts
- Wasserstein drift scoring for stability
- Hidden Markov model for latent state inference (depressive, stable, elevated, unstable)
- Medication trajectory analysis
- Trigger attribution ranking
- Digital phenotype profiling
- Weather correlation analysis (rain, temperature)

### Safety Planning

- Editable safety plan: warning signs, coping strategies, emergency steps
- Support contacts with one-tap calling
- Risk assessment combines mood, sleep, HRV, heart rate, and activity signals
- Non-clinical language throughout. No diagnoses, no medical claims.

### NVC Rephraser

A communication tool for high-intensity moments. Converts reactive statements into Nonviolent Communication format: observation, feeling, need, request. Powered by AWS Bedrock. Useful during mood episodes when saying what you mean gets harder.

## Tech Stack

| Component | Technology |
|-----------|-----------|
| UI | SwiftUI |
| Persistence | SwiftData (on-device, encrypted) |
| Health data | HealthKit |
| Weather | Open-Meteo API (free, no auth required) |
| NVC engine | AWS Bedrock (Amazon Nova 2 Lite) |
| Project gen | Tuist |
| Target | iOS 17.0+ |

## Build from Source

```bash
brew install tuist
tuist generate
open moodbound.xcworkspace
```

For the NVC rephraser, set `AWS_BEARER_TOKEN_BEDROCK` in your Xcode scheme environment. Everything else works without it.

## Data Model

All data stays in SwiftData on your device.

| Entity | Purpose |
|--------|---------|
| `MoodEntry` | Mood, energy, sleep, anxiety, irritability, weather, health metrics, notes |
| `Medication` | Name, dosage, schedule, active status |
| `MedicationAdherenceEvent` | Taken/not-taken per check-in |
| `TriggerFactor` | Custom trigger with category |
| `TriggerEvent` | Trigger occurrence with intensity |
| `SafetyPlan` | Warning signs, coping strategies, emergency steps |
| `SupportContact` | Name, phone, relationship |
| `ReminderSettings` | Notification preferences |

Export and import everything as JSON through Settings.

## Privacy

No accounts. No sign-up. No analytics. No telemetry. No cloud sync.

Apple Health data requires explicit permission per type. Location is used at kilometer accuracy for weather, then discarded. The NVC rephraser sends text to AWS Bedrock over HTTPS when you use it. That and weather are the only network calls.

The source code is public. Read it.

## License

MIT. See [LICENSE](LICENSE).

Open source code, $2.99 on the App Store. You pay for the signed build, the updates, and not having to compile it yourself.
