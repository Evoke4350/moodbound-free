import Foundation

/// Region-aware crisis-line directory. Bipolar OSS apps that ship
/// internationally fail by hard-coding US 988; this picks the right
/// resource per `Locale.current.region` with an international fallback.
///
/// Numbers verified 2026-05 against the operating organizations'
/// public-facing pages. Update this file when an org changes a number;
/// resist the urge to add unverified third-party hotlines.
struct CrisisResource: Equatable, Identifiable {
    let regionCode: String
    let name: String
    let phone: String
    let sms: String?
    let web: String?
    let hoursNote: String

    var id: String { "\(regionCode)-\(name)" }
}

enum CrisisResources {
    /// Primary resource(s) for the given ISO 3166-1 region code, or the
    /// international fallback when we don't have a region-specific entry.
    static func forRegion(_ regionCode: String?) -> [CrisisResource] {
        let key = (regionCode ?? "").uppercased()
        if let direct = byRegion[key] { return direct }
        return [internationalFallback]
    }

    /// Resolved against the device locale at call time. Wrap in
    /// `@MainActor` callers if you need sub-second freshness; for
    /// SafetyPlan-render purposes the cached `Locale.current` is fine.
    static func current(locale: Locale = .current) -> [CrisisResource] {
        forRegion(locale.region?.identifier)
    }

    private static let internationalFallback = CrisisResource(
        regionCode: "INT",
        name: "Find a Helpline",
        phone: "",
        sms: nil,
        web: "https://findahelpline.com",
        hoursNote: "Searchable directory of crisis lines worldwide."
    )

    private static let byRegion: [String: [CrisisResource]] = [
        "US": [
            CrisisResource(
                regionCode: "US",
                name: "988 Suicide & Crisis Lifeline",
                phone: "988",
                sms: "988",
                web: "https://988lifeline.org",
                hoursNote: "Call or text 988, 24/7."
            ),
            CrisisResource(
                regionCode: "US",
                name: "Crisis Text Line",
                phone: "",
                sms: "741741",
                web: "https://www.crisistextline.org",
                hoursNote: "Text HOME to 741741, 24/7."
            ),
        ],
        "CA": [
            CrisisResource(
                regionCode: "CA",
                name: "9-8-8 Suicide Crisis Helpline",
                phone: "988",
                sms: "988",
                web: "https://988.ca",
                hoursNote: "Call or text 988, 24/7."
            ),
        ],
        "GB": [
            CrisisResource(
                regionCode: "GB",
                name: "Samaritans",
                phone: "116123",
                sms: nil,
                web: "https://www.samaritans.org",
                hoursNote: "Free to call, 24/7."
            ),
            CrisisResource(
                regionCode: "GB",
                name: "Shout",
                phone: "",
                sms: "85258",
                web: "https://giveusashout.org",
                hoursNote: "Text SHOUT to 85258, 24/7."
            ),
        ],
        "IE": [
            CrisisResource(
                regionCode: "IE",
                name: "Samaritans Ireland",
                phone: "116123",
                sms: nil,
                web: "https://www.samaritans.org/ireland",
                hoursNote: "Free to call, 24/7."
            ),
        ],
        "AU": [
            CrisisResource(
                regionCode: "AU",
                name: "Lifeline",
                phone: "131114",
                sms: "0477131114",
                web: "https://www.lifeline.org.au",
                hoursNote: "Call 13 11 14 or text 0477 13 11 14, 24/7."
            ),
        ],
        "NZ": [
            CrisisResource(
                regionCode: "NZ",
                name: "1737, Need to Talk?",
                phone: "1737",
                sms: "1737",
                web: "https://1737.org.nz",
                hoursNote: "Call or text 1737, 24/7."
            ),
        ],
        "DE": [
            CrisisResource(
                regionCode: "DE",
                name: "Telefonseelsorge",
                phone: "08001110111",
                sms: nil,
                web: "https://www.telefonseelsorge.de",
                hoursNote: "0800 111 0 111, free, 24/7."
            ),
        ],
        "FR": [
            CrisisResource(
                regionCode: "FR",
                name: "3114 Numéro national de prévention du suicide",
                phone: "3114",
                sms: nil,
                web: "https://3114.fr",
                hoursNote: "Appel gratuit, 24/7."
            ),
        ],
        "NL": [
            CrisisResource(
                regionCode: "NL",
                name: "113 Zelfmoordpreventie",
                phone: "113",
                sms: nil,
                web: "https://www.113.nl",
                hoursNote: "Bel 113, 24/7."
            ),
        ],
        "ES": [
            CrisisResource(
                regionCode: "ES",
                name: "024 Línea de atención a la conducta suicida",
                phone: "024",
                sms: nil,
                web: "https://www.sanidad.gob.es/linea024",
                hoursNote: "Llamada gratuita, 24/7."
            ),
        ],
        "BR": [
            CrisisResource(
                regionCode: "BR",
                name: "CVV — Centro de Valorização da Vida",
                phone: "188",
                sms: nil,
                web: "https://www.cvv.org.br",
                hoursNote: "Ligue 188, gratuito, 24h."
            ),
        ],
        "MX": [
            CrisisResource(
                regionCode: "MX",
                name: "SAPTEL",
                phone: "5552598121",
                sms: nil,
                web: "https://www.saptel.org.mx",
                hoursNote: "55 5259-8121, 24/7."
            ),
        ],
        "JP": [
            CrisisResource(
                regionCode: "JP",
                name: "TELL Lifeline",
                phone: "0357740992",
                sms: nil,
                web: "https://telljp.com/lifeline",
                hoursNote: "03-5774-0992 (English support)."
            ),
        ],
        "IN": [
            CrisisResource(
                regionCode: "IN",
                name: "iCall",
                phone: "9152987821",
                sms: nil,
                web: "https://icallhelpline.org",
                hoursNote: "Mon–Sat, 8am–10pm IST."
            ),
        ],
    ]
}
