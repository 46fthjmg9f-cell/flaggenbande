import SwiftUI
import Foundation
import Combine
import CloudKit
import GameKit
import StoreKit
import UIKit
import SceneKit
import simd
import UserNotifications
import AudioToolbox

let customFlagImageURLByCode: [String: URL] = [
    "AB": URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/Flag_of_the_Republic_of_Abkhazia.svg?width=1280")!,
    "OS": URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/Flag_of_South_Ossetia.svg?width=1280")!,
    "NC": URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/Flag_of_the_Turkish_Republic_of_Northern_Cyprus.svg?width=1280")!,
    "SLD": URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/Flag_of_Somaliland.svg?width=1280")!
]

struct Country: Identifiable, Equatable, Codable {
    let code: String
    let name: String
    let continent: String
    
    var id: String { code }
    var flagImageURL: URL? {
        customFlagImageURLByCode[code] ?? URL(string: "https://flagcdn.com/w1280/\(code.lowercased()).png")
    }
}

let capitalByCountryCode: [String: String] = [
    "AF": "Kabul", "AL": "Tirana", "DZ": "Algier", "AD": "Andorra la Vella", "AO": "Luanda",
    "AG": "St. John's", "AR": "Buenos Aires", "AM": "Jerewan", "AZ": "Baku", "AU": "Canberra",
    "BS": "Nassau", "BH": "Manama", "BD": "Dhaka", "BB": "Bridgetown", "BE": "Brüssel",
    "BZ": "Belmopan", "BJ": "Porto-Novo", "BT": "Thimphu", "BO": "Sucre", "BA": "Sarajevo",
    "BW": "Gaborone", "BR": "Brasília", "BN": "Bandar Seri Begawan", "BG": "Sofia", "BF": "Ouagadougou",
    "BI": "Gitega", "CL": "Santiago de Chile", "CN": "Peking", "CR": "San José", "DE": "Berlin",
    "DM": "Roseau", "DO": "Santo Domingo", "DJ": "Dschibuti", "DK": "Kopenhagen", "EC": "Quito",
    "SV": "San Salvador", "CI": "Yamoussoukro", "ER": "Asmara", "EE": "Tallinn", "FJ": "Suva",
    "FI": "Helsinki", "FR": "Paris", "GA": "Libreville", "GM": "Banjul", "GE": "Tiflis",
    "GH": "Accra", "GD": "St. George's", "GR": "Athen", "GT": "Guatemala-Stadt", "GN": "Conakry",
    "GW": "Bissau", "GY": "Georgetown", "HT": "Port-au-Prince", "HN": "Tegucigalpa", "IN": "Neu-Delhi",
    "ID": "Jakarta", "IQ": "Bagdad", "IR": "Teheran", "IE": "Dublin", "IS": "Reykjavík",
    "IL": "Jerusalem", "IT": "Rom", "JM": "Kingston", "JP": "Tokio", "YE": "Sanaa",
    "JO": "Amman", "KH": "Phnom Penh", "CM": "Yaoundé", "CA": "Ottawa", "CV": "Praia",
    "KZ": "Astana", "QA": "Doha", "KE": "Nairobi", "KG": "Bischkek", "KI": "South Tarawa",
    "CO": "Bogotá", "KM": "Moroni", "CG": "Brazzaville", "CD": "Kinshasa", "HR": "Zagreb",
    "CU": "Havanna", "KW": "Kuwait-Stadt", "LA": "Vientiane", "LS": "Maseru", "LV": "Riga",
    "LB": "Beirut", "LR": "Monrovia", "LY": "Tripolis", "LI": "Vaduz", "LT": "Vilnius",
    "LU": "Luxemburg", "MG": "Antananarivo", "MW": "Lilongwe", "MY": "Kuala Lumpur", "MV": "Malé",
    "ML": "Bamako", "MT": "Valletta", "MA": "Rabat", "MH": "Majuro", "MR": "Nouakchott",
    "MU": "Port Louis", "MX": "Mexiko-Stadt", "FM": "Palikir", "MD": "Chișinău", "MC": "Monaco",
    "MN": "Ulaanbaatar", "ME": "Podgorica", "MZ": "Maputo", "MM": "Naypyidaw", "NA": "Windhoek",
    "NR": "Yaren", "NP": "Kathmandu", "NZ": "Wellington", "NI": "Managua", "NL": "Amsterdam",
    "NE": "Niamey", "NG": "Abuja", "KP": "Pjöngjang", "MK": "Skopje", "NO": "Oslo",
    "OM": "Maskat", "TL": "Dili", "PK": "Islamabad", "PW": "Ngerulmud", "PA": "Panama-Stadt",
    "PG": "Port Moresby", "PY": "Asunción", "PE": "Lima", "PH": "Manila", "PL": "Warschau",
    "PT": "Lissabon", "RW": "Kigali", "RO": "Bukarest", "RU": "Moskau", "SB": "Honiara",
    "ZM": "Lusaka", "WS": "Apia", "SM": "San Marino", "SA": "Riad", "SE": "Stockholm",
    "CH": "Bern", "SN": "Dakar", "RS": "Belgrad", "SC": "Victoria", "SL": "Freetown",
    "ZW": "Harare", "SG": "Singapur", "SK": "Bratislava", "SI": "Ljubljana", "SO": "Mogadischu",
    "ES": "Madrid", "LK": "Sri Jayawardenepura Kotte", "KN": "Basseterre", "LC": "Castries", "VC": "Kingstown",
    "SD": "Khartum", "SR": "Paramaribo", "SZ": "Mbabane", "SY": "Damaskus", "ST": "São Tomé",
    "ZA": "Pretoria", "KR": "Seoul", "SS": "Juba", "TJ": "Duschanbe", "TZ": "Dodoma",
    "TH": "Bangkok", "TG": "Lomé", "TO": "Nukuʻalofa", "TT": "Port of Spain", "TD": "N'Djamena",
    "CZ": "Prag", "TN": "Tunis", "TM": "Aschgabat", "TV": "Funafuti", "TR": "Ankara",
    "UG": "Kampala", "UA": "Kiew", "HU": "Budapest", "UY": "Montevideo", "UZ": "Taschkent",
    "VU": "Port Vila", "VE": "Caracas", "AE": "Abu Dhabi", "US": "Washington, D.C.", "GB": "London",
    "VN": "Hanoi", "BY": "Minsk", "CF": "Bangui", "CY": "Nikosia", "EG": "Kairo",
    "GQ": "Malabo", "ET": "Addis Abeba", "AT": "Wien", "GL": "Nuuk", "FO": "Tórshavn",
    "XK": "Pristina", "TW": "Taipeh", "PS": "Ramallah", "EH": "El Aaiún",
    "CK": "Avarua", "NU": "Alofi", "AB": "Suchumi", "OS": "Zchinwali",
    "NC": "Nord-Nikosia", "SLD": "Hargeisa"
]

let capitalPronunciationByCountryCode: [String: String] = [
    "AF": "Ka-bul", "DZ": "Al-dschir", "AO": "Lu-an-da", "AZ": "Ba-ku", "BH": "Ma-na-ma",
    "BD": "Dha-ka", "BZ": "Bel-mo-pan", "BJ": "Por-to No-vo", "BT": "Tim-pu",
    "BA": "Sa-ra-je-wo", "BW": "Ga-bo-ro-ne", "BR": "Bra-si-li-a", "BN": "Ban-dar Se-ri Be-ga-wan",
    "BF": "Wa-ga-du-gu", "BI": "Gi-te-ga", "CN": "Pe-king", "DJ": "Dschi-bu-ti",
    "CI": "Ja-mu-ssu-kro", "ER": "As-ma-ra", "FJ": "Su-wa", "GA": "Li-bre-wil",
    "GM": "Ban-dschul", "GE": "Tif-lis", "GH": "Ak-kra", "GN": "Ko-na-kri",
    "GW": "Bi-ssau", "HT": "Port-o-Prens", "IN": "Neu-De-li", "ID": "Dja-kar-ta",
    "IQ": "Bag-dad", "IR": "Te-he-ran", "IS": "Reik-ja-wik", "IL": "Je-ru-sa-lem",
    "JP": "To-kio", "YE": "Sa-na-a", "JO": "Am-man", "KH": "Pnom Pen",
    "CV": "Pra-ja", "KZ": "As-ta-na", "QA": "Do-ha", "KE": "Nai-ro-bi",
    "KG": "Bisch-kek", "KI": "Sauth Ta-ra-wa", "KM": "Mo-ro-ni", "CG": "Bra-sa-wil",
    "CD": "Kin-scha-sa", "KW": "Ku-wait-Stadt", "LA": "Wi-en-tian", "LS": "Ma-se-ru",
    "LB": "Bei-rut", "LR": "Mon-ro-wi-a", "LY": "Tri-po-lis", "MG": "An-ta-na-na-ri-wo",
    "MW": "Li-long-we", "MY": "Ku-a-la Lum-pur", "MV": "Ma-le", "ML": "Ba-ma-ko",
    "MA": "Ra-bat", "MH": "Ma-dschu-ro", "MR": "Nu-ak-schott", "MU": "Port Lu-is",
    "FM": "Pa-li-kir", "MD": "Ki-schi-nau", "MN": "U-lan-ba-tor", "MZ": "Ma-pu-to",
    "MM": "Ne-pi-do", "NA": "Wind-huk", "NR": "Ja-ren", "NP": "Kat-man-du",
    "NE": "Ni-a-me", "NG": "A-bu-dscha", "KP": "Pjöng-jang", "OM": "Mas-kat",
    "TL": "Di-li", "PK": "Is-la-ma-bad", "PW": "Nge-rul-mud", "PG": "Port Mors-bi",
    "PY": "A-sun-si-on", "PE": "Li-ma", "PH": "Ma-ni-la", "RW": "Ki-ga-li",
    "RU": "Mos-kau", "SB": "Ho-ni-a-ra", "ZM": "Lu-sa-ka", "WS": "A-pi-a",
    "SA": "Ri-ad", "SN": "Se-ne-gal", "SC": "Vik-to-ri-a", "SL": "Fri-taun",
    "ZW": "Ha-ra-re", "LK": "Sri Dschaja-war-de-ne-pu-ra Kot-te", "KN": "Bass-tehr",
    "LC": "Kas-tris", "VC": "Kings-taun", "SD": "Khar-tum", "SR": "Pa-ra-ma-ri-bo",
    "SZ": "Mba-ba-ne", "SY": "Da-mas-kus", "ST": "Sao To-me", "KR": "Se-ul",
    "SS": "Dschu-ba", "TJ": "Du-schan-be", "TZ": "Do-do-ma", "TH": "Bang-kok",
    "TG": "Lo-me", "TO": "Nu-ku-a-lo-fa", "TD": "Nd-scha-me-na", "TM": "Asch-ga-bat",
    "TV": "Fu-na-fu-ti", "UG": "Kam-pa-la", "UZ": "Taschkent", "VU": "Port Wi-la",
    "AE": "A-bu Da-bi", "VN": "Ha-noi", "CF": "Ban-gi", "EG": "Kai-ro",
    "GQ": "Ma-la-bo", "ET": "Ad-dis A-be-ba", "FO": "Tor-schhaun", "XK": "Pris-ti-na",
    "TW": "Tai-peh", "PS": "Ra-mal-lah", "EH": "El A-jun", "CK": "A-wa-ru-a",
    "NU": "A-lo-fi", "AB": "Su-chu-mi", "OS": "Zchin-wa-li", "NC": "Nord-Ni-ko-si-a",
    "SLD": "Har-gei-sa"
]

let allCountries: [Country] = [
    Country(code: "AF", name: "Afghanistan", continent: "Asien"),
    Country(code: "AL", name: "Albanien", continent: "Europa"),
    Country(code: "DZ", name: "Algerien", continent: "Afrika"),
    Country(code: "AD", name: "Andorra", continent: "Europa"),
    Country(code: "AO", name: "Angola", continent: "Afrika"),
    Country(code: "AG", name: "Antigua und Barbuda", continent: "Nordamerika"),
    Country(code: "AR", name: "Argentinien", continent: "Südamerika"),
    Country(code: "AM", name: "Armenien", continent: "Asien"),
    Country(code: "AZ", name: "Aserbaidschan", continent: "Europa"),
    Country(code: "AU", name: "Australien", continent: "Ozeanien"),
    Country(code: "BS", name: "Bahamas", continent: "Nordamerika"),
    Country(code: "BH", name: "Bahrain", continent: "Asien"),
    Country(code: "BD", name: "Bangladesch", continent: "Asien"),
    Country(code: "BB", name: "Barbados", continent: "Nordamerika"),
    Country(code: "BE", name: "Belgien", continent: "Europa"),
    Country(code: "BZ", name: "Belize", continent: "Nordamerika"),
    Country(code: "BJ", name: "Benin", continent: "Afrika"),
    Country(code: "BT", name: "Bhutan", continent: "Asien"),
    Country(code: "BO", name: "Bolivien", continent: "Südamerika"),
    Country(code: "BA", name: "Bosnien und Herzegowina", continent: "Europa"),
    Country(code: "BW", name: "Botswana", continent: "Afrika"),
    Country(code: "BR", name: "Brasilien", continent: "Südamerika"),
    Country(code: "BN", name: "Brunei", continent: "Asien"),
    Country(code: "BG", name: "Bulgarien", continent: "Europa"),
    Country(code: "BF", name: "Burkina Faso", continent: "Afrika"),
    Country(code: "BI", name: "Burundi", continent: "Afrika"),
    Country(code: "CL", name: "Chile", continent: "Südamerika"),
    Country(code: "CN", name: "China", continent: "Asien"),
    Country(code: "CR", name: "Costa Rica", continent: "Nordamerika"),
    Country(code: "DE", name: "Deutschland", continent: "Europa"),
    Country(code: "DM", name: "Dominica", continent: "Nordamerika"),
    Country(code: "DO", name: "Dominikanische Republik", continent: "Nordamerika"),
    Country(code: "DJ", name: "Dschibuti", continent: "Afrika"),
    Country(code: "DK", name: "Dänemark", continent: "Europa"),
    Country(code: "EC", name: "Ecuador", continent: "Südamerika"),
    Country(code: "SV", name: "El Salvador", continent: "Nordamerika"),
    Country(code: "CI", name: "Elfenbeinküste", continent: "Afrika"),
    Country(code: "ER", name: "Eritrea", continent: "Afrika"),
    Country(code: "EE", name: "Estland", continent: "Europa"),
    Country(code: "FJ", name: "Fidschi", continent: "Ozeanien"),
    Country(code: "FI", name: "Finnland", continent: "Europa"),
    Country(code: "FO", name: "Färöer", continent: "Europa"),
    Country(code: "FR", name: "Frankreich", continent: "Europa"),
    Country(code: "GA", name: "Gabun", continent: "Afrika"),
    Country(code: "GM", name: "Gambia", continent: "Afrika"),
    Country(code: "GE", name: "Georgien", continent: "Asien"),
    Country(code: "GH", name: "Ghana", continent: "Afrika"),
    Country(code: "GD", name: "Grenada", continent: "Nordamerika"),
    Country(code: "GR", name: "Griechenland", continent: "Europa"),
    Country(code: "GL", name: "Grönland", continent: "Nordamerika"),
    Country(code: "GT", name: "Guatemala", continent: "Nordamerika"),
    Country(code: "GN", name: "Guinea", continent: "Afrika"),
    Country(code: "GW", name: "Guinea-Bissau", continent: "Afrika"),
    Country(code: "GY", name: "Guyana", continent: "Südamerika"),
    Country(code: "HT", name: "Haiti", continent: "Nordamerika"),
    Country(code: "HN", name: "Honduras", continent: "Nordamerika"),
    Country(code: "IN", name: "Indien", continent: "Asien"),
    Country(code: "ID", name: "Indonesien", continent: "Asien"),
    Country(code: "IQ", name: "Irak", continent: "Asien"),
    Country(code: "IR", name: "Iran", continent: "Asien"),
    Country(code: "IE", name: "Irland", continent: "Europa"),
    Country(code: "IS", name: "Island", continent: "Europa"),
    Country(code: "IL", name: "Israel", continent: "Asien"),
    Country(code: "IT", name: "Italien", continent: "Europa"),
    Country(code: "JM", name: "Jamaika", continent: "Nordamerika"),
    Country(code: "JP", name: "Japan", continent: "Asien"),
    Country(code: "YE", name: "Jemen", continent: "Asien"),
    Country(code: "JO", name: "Jordanien", continent: "Asien"),
    Country(code: "KH", name: "Kambodscha", continent: "Asien"),
    Country(code: "CM", name: "Kamerun", continent: "Afrika"),
    Country(code: "CA", name: "Kanada", continent: "Nordamerika"),
    Country(code: "CV", name: "Kap Verde", continent: "Afrika"),
    Country(code: "KZ", name: "Kasachstan", continent: "Asien"),
    Country(code: "QA", name: "Katar", continent: "Asien"),
    Country(code: "KE", name: "Kenia", continent: "Afrika"),
    Country(code: "KG", name: "Kirgisistan", continent: "Asien"),
    Country(code: "KI", name: "Kiribati", continent: "Ozeanien"),
    Country(code: "CO", name: "Kolumbien", continent: "Südamerika"),
    Country(code: "KM", name: "Komoren", continent: "Afrika"),
    Country(code: "CG", name: "Kongo", continent: "Afrika"),
    Country(code: "CD", name: "Kongo (Dem. Rep.)", continent: "Afrika"),
    Country(code: "HR", name: "Kroatien", continent: "Europa"),
    Country(code: "CU", name: "Kuba", continent: "Nordamerika"),
    Country(code: "KW", name: "Kuwait", continent: "Asien"),
    Country(code: "LA", name: "Laos", continent: "Asien"),
    Country(code: "LS", name: "Lesotho", continent: "Afrika"),
    Country(code: "LV", name: "Lettland", continent: "Europa"),
    Country(code: "LB", name: "Libanon", continent: "Asien"),
    Country(code: "LR", name: "Liberia", continent: "Afrika"),
    Country(code: "LY", name: "Libyen", continent: "Afrika"),
    Country(code: "LI", name: "Liechtenstein", continent: "Europa"),
    Country(code: "LT", name: "Litauen", continent: "Europa"),
    Country(code: "LU", name: "Luxemburg", continent: "Europa"),
    Country(code: "MG", name: "Madagaskar", continent: "Afrika"),
    Country(code: "MW", name: "Malawi", continent: "Afrika"),
    Country(code: "MY", name: "Malaysia", continent: "Asien"),
    Country(code: "MV", name: "Malediven", continent: "Asien"),
    Country(code: "ML", name: "Mali", continent: "Afrika"),
    Country(code: "MT", name: "Malta", continent: "Europa"),
    Country(code: "MA", name: "Marokko", continent: "Afrika"),
    Country(code: "MH", name: "Marshallinseln", continent: "Ozeanien"),
    Country(code: "MR", name: "Mauretanien", continent: "Afrika"),
    Country(code: "MU", name: "Mauritius", continent: "Afrika"),
    Country(code: "MX", name: "Mexiko", continent: "Nordamerika"),
    Country(code: "FM", name: "Mikronesien", continent: "Ozeanien"),
    Country(code: "MD", name: "Moldawien", continent: "Europa"),
    Country(code: "MC", name: "Monaco", continent: "Europa"),
    Country(code: "MN", name: "Mongolei", continent: "Asien"),
    Country(code: "ME", name: "Montenegro", continent: "Europa"),
    Country(code: "MZ", name: "Mosambik", continent: "Afrika"),
    Country(code: "MM", name: "Myanmar", continent: "Asien"),
    Country(code: "NA", name: "Namibia", continent: "Afrika"),
    Country(code: "NR", name: "Nauru", continent: "Ozeanien"),
    Country(code: "NP", name: "Nepal", continent: "Asien"),
    Country(code: "NZ", name: "Neuseeland", continent: "Ozeanien"),
    Country(code: "NI", name: "Nicaragua", continent: "Nordamerika"),
    Country(code: "NL", name: "Niederlande", continent: "Europa"),
    Country(code: "NE", name: "Niger", continent: "Afrika"),
    Country(code: "NG", name: "Nigeria", continent: "Afrika"),
    Country(code: "KP", name: "Nordkorea", continent: "Asien"),
    Country(code: "MK", name: "Nordmazedonien", continent: "Europa"),
    Country(code: "NO", name: "Norwegen", continent: "Europa"),
    Country(code: "OM", name: "Oman", continent: "Asien"),
    Country(code: "TL", name: "Osttimor", continent: "Ozeanien"),
    Country(code: "PK", name: "Pakistan", continent: "Asien"),
    Country(code: "PW", name: "Palau", continent: "Ozeanien"),
    Country(code: "PA", name: "Panama", continent: "Nordamerika"),
    Country(code: "PG", name: "Papua-Neuguinea", continent: "Ozeanien"),
    Country(code: "PY", name: "Paraguay", continent: "Südamerika"),
    Country(code: "PE", name: "Peru", continent: "Südamerika"),
    Country(code: "PH", name: "Philippinen", continent: "Asien"),
    Country(code: "PL", name: "Polen", continent: "Europa"),
    Country(code: "PT", name: "Portugal", continent: "Europa"),
    Country(code: "RW", name: "Ruanda", continent: "Afrika"),
    Country(code: "RO", name: "Rumänien", continent: "Europa"),
    Country(code: "RU", name: "Russland", continent: "Europa"),
    Country(code: "SB", name: "Salomonen", continent: "Ozeanien"),
    Country(code: "ZM", name: "Sambia", continent: "Afrika"),
    Country(code: "WS", name: "Samoa", continent: "Ozeanien"),
    Country(code: "SM", name: "San Marino", continent: "Europa"),
    Country(code: "SA", name: "Saudi-Arabien", continent: "Asien"),
    Country(code: "SE", name: "Schweden", continent: "Europa"),
    Country(code: "CH", name: "Schweiz", continent: "Europa"),
    Country(code: "SN", name: "Senegal", continent: "Afrika"),
    Country(code: "RS", name: "Serbien", continent: "Europa"),
    Country(code: "SC", name: "Seychellen", continent: "Afrika"),
    Country(code: "SL", name: "Sierra Leone", continent: "Afrika"),
    Country(code: "ZW", name: "Simbabwe", continent: "Afrika"),
    Country(code: "SG", name: "Singapur", continent: "Asien"),
    Country(code: "SK", name: "Slowakei", continent: "Europa"),
    Country(code: "SI", name: "Slowenien", continent: "Europa"),
    Country(code: "SO", name: "Somalia", continent: "Afrika"),
    Country(code: "ES", name: "Spanien", continent: "Europa"),
    Country(code: "LK", name: "Sri Lanka", continent: "Asien"),
    Country(code: "KN", name: "St. Kitts und Nevis", continent: "Nordamerika"),
    Country(code: "LC", name: "St. Lucia", continent: "Nordamerika"),
    Country(code: "VC", name: "St. Vincent und die Grenadinen", continent: "Nordamerika"),
    Country(code: "SD", name: "Sudan", continent: "Afrika"),
    Country(code: "SR", name: "Suriname", continent: "Südamerika"),
    Country(code: "SZ", name: "Swasiland", continent: "Afrika"),
    Country(code: "SY", name: "Syrien", continent: "Asien"),
    Country(code: "ST", name: "São Tomé und Príncipe", continent: "Afrika"),
    Country(code: "ZA", name: "Südafrika", continent: "Afrika"),
    Country(code: "KR", name: "Südkorea", continent: "Asien"),
    Country(code: "SS", name: "Südsudan", continent: "Afrika"),
    Country(code: "TJ", name: "Tadschikistan", continent: "Asien"),
    Country(code: "TZ", name: "Tansania", continent: "Afrika"),
    Country(code: "TH", name: "Thailand", continent: "Asien"),
    Country(code: "TG", name: "Togo", continent: "Afrika"),
    Country(code: "TO", name: "Tonga", continent: "Ozeanien"),
    Country(code: "TT", name: "Trinidad und Tobago", continent: "Nordamerika"),
    Country(code: "TD", name: "Tschad", continent: "Afrika"),
    Country(code: "CZ", name: "Tschechien", continent: "Europa"),
    Country(code: "TN", name: "Tunesien", continent: "Afrika"),
    Country(code: "TM", name: "Turkmenistan", continent: "Asien"),
    Country(code: "TV", name: "Tuvalu", continent: "Ozeanien"),
    Country(code: "TR", name: "Türkei", continent: "Europa"),
    Country(code: "UG", name: "Uganda", continent: "Afrika"),
    Country(code: "UA", name: "Ukraine", continent: "Europa"),
    Country(code: "HU", name: "Ungarn", continent: "Europa"),
    Country(code: "UY", name: "Uruguay", continent: "Südamerika"),
    Country(code: "UZ", name: "Usbekistan", continent: "Asien"),
    Country(code: "VU", name: "Vanuatu", continent: "Ozeanien"),
    Country(code: "VE", name: "Venezuela", continent: "Südamerika"),
    Country(code: "AE", name: "Vereinigte Arabische Emirate", continent: "Asien"),
    Country(code: "US", name: "Vereinigte Staaten", continent: "Nordamerika"),
    Country(code: "GB", name: "Vereinigtes Königreich", continent: "Europa"),
    Country(code: "VN", name: "Vietnam", continent: "Asien"),
    Country(code: "BY", name: "Belarus (Weißrussland)", continent: "Europa"),
    Country(code: "CF", name: "Zentralafrikanische Republik", continent: "Afrika"),
    Country(code: "CY", name: "Zypern", continent: "Europa"),
    Country(code: "EG", name: "Ägypten", continent: "Afrika"),
    Country(code: "GQ", name: "Äquatorialguinea", continent: "Afrika"),
    Country(code: "ET", name: "Äthiopien", continent: "Afrika"),
    Country(code: "AT", name: "Österreich", continent: "Europa")
]

let partiallyRecognizedCategory = "Teilweise anerkannt"

let worldCupWinnerCountryCodes: Set<String> = ["AR", "BR", "DE", "ES", "FR", "GB", "IT", "UY"]

let partiallyRecognizedCountries: [Country] = [
    Country(code: "XK", name: "Kosovo", continent: "Europa"),
    Country(code: "TW", name: "Taiwan", continent: "Asien"),
    Country(code: "PS", name: "Palästina", continent: "Asien"),
    Country(code: "EH", name: "Westsahara", continent: "Afrika"),
    Country(code: "CK", name: "Cookinseln", continent: "Ozeanien"),
    Country(code: "NU", name: "Niue", continent: "Ozeanien"),
    Country(code: "AB", name: "Abchasien", continent: "Asien"),
    Country(code: "OS", name: "Südossetien", continent: "Asien"),
    Country(code: "NC", name: "Nordzypern", continent: "Asien"),
    Country(code: "SLD", name: "Somaliland", continent: "Afrika")
]

let allPracticeCountries = allCountries + partiallyRecognizedCountries

let countryEnglishNameByCode: [String: String] = [
    "AF": "Afghanistan", "AL": "Albania", "DZ": "Algeria", "AD": "Andorra", "AO": "Angola",
    "AG": "Antigua and Barbuda", "AR": "Argentina", "AM": "Armenia", "AZ": "Azerbaijan", "AU": "Australia",
    "BS": "Bahamas", "BH": "Bahrain", "BD": "Bangladesh", "BB": "Barbados", "BE": "Belgium",
    "BZ": "Belize", "BJ": "Benin", "BT": "Bhutan", "BO": "Bolivia", "BA": "Bosnia and Herzegovina",
    "BW": "Botswana", "BR": "Brazil", "BN": "Brunei", "BG": "Bulgaria", "BF": "Burkina Faso",
    "BI": "Burundi", "CL": "Chile", "CN": "China", "CR": "Costa Rica", "DE": "Germany",
    "DM": "Dominica", "DO": "Dominican Republic", "DJ": "Djibouti", "DK": "Denmark", "EC": "Ecuador",
    "SV": "El Salvador", "CI": "Cote d'Ivoire", "ER": "Eritrea", "EE": "Estonia", "FJ": "Fiji",
    "FI": "Finland", "FO": "Faroe Islands", "FR": "France", "GA": "Gabon", "GM": "Gambia", "GE": "Georgia",
    "GH": "Ghana", "GD": "Grenada", "GR": "Greece", "GL": "Greenland", "GT": "Guatemala", "GN": "Guinea",
    "GW": "Guinea-Bissau", "GY": "Guyana", "HT": "Haiti", "HN": "Honduras", "IN": "India",
    "ID": "Indonesia", "IQ": "Iraq", "IR": "Iran", "IE": "Ireland", "IS": "Iceland",
    "IL": "Israel", "IT": "Italy", "JM": "Jamaica", "JP": "Japan", "YE": "Yemen",
    "JO": "Jordan", "KH": "Cambodia", "CM": "Cameroon", "CA": "Canada", "CV": "Cape Verde",
    "KZ": "Kazakhstan", "QA": "Qatar", "KE": "Kenya", "KG": "Kyrgyzstan", "KI": "Kiribati",
    "CO": "Colombia", "KM": "Comoros", "CG": "Congo", "CD": "Democratic Republic of the Congo", "HR": "Croatia",
    "CU": "Cuba", "KW": "Kuwait", "LA": "Laos", "LS": "Lesotho", "LV": "Latvia",
    "LB": "Lebanon", "LR": "Liberia", "LY": "Libya", "LI": "Liechtenstein", "LT": "Lithuania",
    "LU": "Luxembourg", "MG": "Madagascar", "MW": "Malawi", "MY": "Malaysia", "MV": "Maldives",
    "ML": "Mali", "MT": "Malta", "MA": "Morocco", "MH": "Marshall Islands", "MR": "Mauritania",
    "MU": "Mauritius", "MX": "Mexico", "FM": "Micronesia", "MD": "Moldova", "MC": "Monaco",
    "MN": "Mongolia", "ME": "Montenegro", "MZ": "Mozambique", "MM": "Myanmar", "NA": "Namibia",
    "NR": "Nauru", "NP": "Nepal", "NZ": "New Zealand", "NI": "Nicaragua", "NL": "Netherlands",
    "NE": "Niger", "NG": "Nigeria", "KP": "North Korea", "MK": "North Macedonia", "NO": "Norway",
    "OM": "Oman", "TL": "East Timor", "PK": "Pakistan", "PW": "Palau", "PA": "Panama",
    "PG": "Papua New Guinea", "PY": "Paraguay", "PE": "Peru", "PH": "Philippines", "PL": "Poland",
    "PT": "Portugal", "RW": "Rwanda", "RO": "Romania", "RU": "Russia", "SB": "Solomon Islands",
    "ZM": "Zambia", "WS": "Samoa", "SM": "San Marino", "SA": "Saudi Arabia", "SE": "Sweden",
    "CH": "Switzerland", "SN": "Senegal", "RS": "Serbia", "SC": "Seychelles", "SL": "Sierra Leone",
    "ZW": "Zimbabwe", "SG": "Singapore", "SK": "Slovakia", "SI": "Slovenia", "SO": "Somalia",
    "ES": "Spain", "LK": "Sri Lanka", "KN": "St. Kitts and Nevis", "LC": "St. Lucia", "VC": "St. Vincent and the Grenadines",
    "SD": "Sudan", "SR": "Suriname", "SZ": "Eswatini", "SY": "Syria", "ST": "Sao Tome and Principe",
    "ZA": "South Africa", "KR": "South Korea", "SS": "South Sudan", "TJ": "Tajikistan", "TZ": "Tanzania",
    "TH": "Thailand", "TG": "Togo", "TO": "Tonga", "TT": "Trinidad and Tobago", "TD": "Chad",
    "CZ": "Czechia", "TN": "Tunisia", "TM": "Turkmenistan", "TV": "Tuvalu", "TR": "Turkey",
    "UG": "Uganda", "UA": "Ukraine", "HU": "Hungary", "UY": "Uruguay", "UZ": "Uzbekistan",
    "VU": "Vanuatu", "VE": "Venezuela", "AE": "United Arab Emirates", "US": "United States", "GB": "United Kingdom",
    "VN": "Vietnam", "BY": "Belarus", "CF": "Central African Republic", "CY": "Cyprus", "EG": "Egypt",
    "GQ": "Equatorial Guinea", "ET": "Ethiopia", "AT": "Austria", "XK": "Kosovo", "TW": "Taiwan",
    "PS": "Palestine", "EH": "Western Sahara", "CK": "Cook Islands", "NU": "Niue",
    "AB": "Abkhazia", "OS": "South Ossetia", "NC": "Northern Cyprus", "SLD": "Somaliland"
]


enum AppLanguage: String, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .german: return "Deutsch"
        case .english: return "English"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    
    func title(language: AppLanguage) -> String {
        switch self {
        case .system: return localized("System", "System", language: language)
        case .light: return localized("Hell", "Light", language: language)
        case .dark: return localized("Dunkel", "Dark", language: language)
        }
    }
}

enum AppAccent: String, CaseIterable, Identifiable {
    case teal
    case blue
    case purple
    case pink
    case orange
    case green
    
    var id: String { rawValue }
    
    func title(language: AppLanguage) -> String {
        switch self {
        case .teal: return localized("Türkis", "Teal", language: language)
        case .blue: return localized("Blau", "Blue", language: language)
        case .purple: return localized("Lila", "Purple", language: language)
        case .pink: return localized("Pink", "Pink", language: language)
        case .orange: return localized("Orange", "Orange", language: language)
        case .green: return localized("Grün", "Green", language: language)
        }
    }
    
    var lightUIColor: UIColor {
        switch self {
        case .teal: return UIColor(red: 0.0, green: 0.62, blue: 0.58, alpha: 1)
        case .blue: return UIColor(red: 0.12, green: 0.42, blue: 0.86, alpha: 1)
        case .purple: return UIColor(red: 0.48, green: 0.28, blue: 0.86, alpha: 1)
        case .pink: return UIColor(red: 0.86, green: 0.18, blue: 0.48, alpha: 1)
        case .orange: return UIColor(red: 0.86, green: 0.38, blue: 0.08, alpha: 1)
        case .green: return UIColor(red: 0.13, green: 0.55, blue: 0.25, alpha: 1)
        }
    }
    
    var darkUIColor: UIColor {
        switch self {
        case .teal: return UIColor(red: 0.23, green: 0.88, blue: 0.86, alpha: 1)
        case .blue: return UIColor(red: 0.36, green: 0.64, blue: 1.0, alpha: 1)
        case .purple: return UIColor(red: 0.72, green: 0.54, blue: 1.0, alpha: 1)
        case .pink: return UIColor(red: 1.0, green: 0.46, blue: 0.70, alpha: 1)
        case .orange: return UIColor(red: 1.0, green: 0.62, blue: 0.24, alpha: 1)
        case .green: return UIColor(red: 0.38, green: 0.82, blue: 0.46, alpha: 1)
        }
    }
}

func localized(_ german: String, _ english: String, language: AppLanguage) -> String {
    language == .german ? german : english
}

func localizedCountryName(_ country: Country, language: AppLanguage) -> String {
    language == .english ? (countryEnglishNameByCode[country.code] ?? country.name) : country.name
}

func capitalPronunciation(for country: Country, capital: String) -> String {
    capitalPronunciationByCountryCode[country.code] ?? capital
}

enum Haptics {
    static func tap(style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    
    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

enum LearningSubject: String, CaseIterable, Identifiable {
    case countries
    case capitals
    
    var id: String { rawValue }
    
    func title(language: AppLanguage) -> String {
        switch self {
        case .countries: return localized("Länder", "Countries", language: language)
        case .capitals: return localized("Hauptstädte", "Capitals", language: language)
        }
    }
    
    func displayTitle(language: AppLanguage) -> String {
        switch self {
        case .countries: return localized("Länderflaggen", "Country flags", language: language)
        case .capitals: return localized("Hauptstädte", "Capitals", language: language)
        }
    }
    
    func statsKey(for country: Country) -> String {
        switch self {
        case .countries: return country.code
        case .capitals: return "capital_\(country.code)"
        }
    }
}

enum MasteryTier: String, CaseIterable, Identifiable, Codable {
    case s = "S"
    case a = "A"
    case b = "B"
    case c = "C"
    case d = "D"
    case f = "F"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .s: return "Stufe S"
        case .a: return "Stufe A"
        case .b: return "Stufe B"
        case .c: return "Stufe C"
        case .d: return "Stufe D"
        case .f: return "Stufe F"
        }
    }
    
    var description: String {
        switch self {
        case .s: return "Perfekt"
        case .a: return "Sehr sicher"
        case .b: return "Sicher"
        case .c: return "Noch wackelig"
        case .d: return "Schwer"
        case .f: return "Noch nie gekonnt"
        }
    }
    
    var color: Color {
        switch self {
        case .s: return .blue
        case .a: return .green
        case .b: return .mint
        case .c: return .yellow
        case .d: return .orange
        case .f: return .red
        }
    }
    
    var promoted: MasteryTier {
        switch self {
        case .s: return .s
        case .a: return .s
        case .b: return .a
        case .c: return .b
        case .d: return .c
        case .f: return .d
        }
    }
    
    var demoted: MasteryTier {
        switch self {
        case .s: return .a
        case .a: return .b
        case .b: return .c
        case .c: return .d
        case .d: return .f
        case .f: return .f
        }
    }
}

struct TierDecayChange: Identifiable {
    var statsKey: String = ""
    let from: MasteryTier
    let to: MasteryTier
    let daysSinceLastPractice: Int
    
    var id: String {
        "\(statsKey)-\(from.rawValue)-\(to.rawValue)-\(daysSinceLastPractice)"
    }
}

struct TierDecayPopup: Identifiable {
    let id = UUID()
    let changes: [TierDecayChange]
    
    var maxDaysSinceLastPractice: Int {
        changes.map(\.daysSinceLastPractice).max() ?? 0
    }
    
    var groupedChanges: [(from: MasteryTier, to: MasteryTier, count: Int)] {
        let grouped = Dictionary(grouping: changes) { "\($0.from.rawValue)-\($0.to.rawValue)" }
        return grouped.compactMap { _, changes in
            guard let first = changes.first else { return nil }
            return (from: first.from, to: first.to, count: changes.count)
        }
        .sorted { lhs, rhs in
            if lhs.from.rawValue == rhs.from.rawValue {
                return lhs.to.rawValue < rhs.to.rawValue
            }
            return lhs.from.rawValue < rhs.from.rawValue
        }
    }
}

struct TierHistoryEntry: Codable, Identifiable {
    let date: Date
    let tier: MasteryTier
    
    var id: String { "\(date.timeIntervalSince1970)-\(tier.rawValue)" }
}

struct LeagueAnswerRecord: Identifiable, Codable {
    let id: UUID
    let countryCode: String
    let countryName: String
    let submittedAnswer: String
    let detectedCountryName: String
    let wasCorrect: Bool
    let responseTime: Double
    let pointsAwarded: Int
}

struct LeagueMatchResult: Identifiable, Codable {
    let id: UUID
    let date: Date
    let opponentName: String
    let ownScore: Int
    let opponentScore: Int
    let correct: Int
    let wrong: Int
    let duration: Int
    let answerDetails: [LeagueAnswerRecord]?
    let ratingBefore: Int?
    let ratingAfter: Int?
    let ratingDelta: Int?
    
    var totalAnswers: Int {
        correct + wrong
    }
    
    var accuracy: Double {
        totalAnswers == 0 ? 0 : Double(correct) / Double(totalAnswers)
    }
    
    var didWin: Bool {
        ownScore >= opponentScore
    }
}

struct LeaguePresetOpponent: Identifiable {
    let id: String
    let titleDE: String
    let titleEN: String
    let subtitleDE: String
    let subtitleEN: String
    let score: Int
    let rating: Int
}

struct LeagueStats: Codable {
    var rating: Int = 1000
    var played: Int = 0
    var wins: Int = 0
    var draws: Int = 0
    var losses: Int = 0
    var bestScore: Int = 0
    var totalScore: Int = 0
    var totalCorrect: Int = 0
    var totalWrong: Int = 0
    var currentWinStreak: Int = 0
    var bestWinStreak: Int = 0
    var recentMatches: [LeagueMatchResult] = []
    
    var averageScore: Double {
        played == 0 ? 0 : Double(totalScore) / Double(played)
    }
    
    var accuracy: Double {
        let total = totalCorrect + totalWrong
        return total == 0 ? 0 : Double(totalCorrect) / Double(total)
    }
    
    var leagueName: String {
        switch rating {
        case ..<800: return "Bronze"
        case 800..<1100: return "Silber"
        case 1100..<1400: return "Gold"
        case 1400..<1700: return "Platin"
        case 1700..<2000: return "Meister"
        default: return "Legende"
        }
    }
    
    var division: String {
        let clampedRating = max(rating, 100)
        let positionInLeague = clampedRating % 300
        switch positionInLeague {
        case 0..<100: return "III"
        case 100..<200: return "II"
        default: return "I"
        }
    }
    
    var leagueTitle: String {
        "\(leagueName) \(division)"
    }
    
    var nextDivisionRating: Int {
        let clampedRating = max(rating, 100)
        return ((clampedRating / 100) + 1) * 100
    }
    
    mutating func recordMatch(_ result: LeagueMatchResult, opponentRating: Int) {
        played += 1
        bestScore = max(bestScore, result.ownScore)
        totalScore += result.ownScore
        totalCorrect += result.correct
        totalWrong += result.wrong
        
        let actualScore: Double
        
        if result.didWin {
            wins += 1
            actualScore = 1
            currentWinStreak += 1
            bestWinStreak = max(bestWinStreak, currentWinStreak)
        } else {
            losses += 1
            actualScore = 0
            currentWinStreak = 0
        }
        
        let expectedScore = 1 / (1 + pow(10, Double(opponentRating - rating) / 400))
        let performanceBonus = min(max(Double(result.ownScore - result.opponentScore) / 1000, -0.08), 0.08)
        let delta = Int((32 * (actualScore - expectedScore + performanceBonus)).rounded())
        rating = max(100, rating + delta)
        
        recentMatches.insert(result, at: 0)
        recentMatches = Array(recentMatches.prefix(12))
    }
}

struct LeagueAnswerMatch {
    let country: Country
    let matchedName: String
    let normalizedAnswer: String
    let normalizedMatchedName: String
    let confidence: Double
    let runnerUpConfidence: Double
    
    var isCertain: Bool {
        normalizedAnswer.count >= 3
            && confidence >= 0.84
            && confidence - runnerUpConfidence >= 0.07
    }
    
    var isAcceptable: Bool {
        normalizedAnswer.count >= 3
            && confidence >= 0.72
            && confidence - runnerUpConfidence >= 0.04
    }
}

enum LeagueMatchPhase {
    case loading
    case countdown
    case playing
    case feedback
}

struct CountryStats: Codable {
    var attempts: Int = 0
    var correct: Int = 0
    var wrong: Int = 0
    var cardReviews: Int = 0
    var cardKnown: Int = 0
    var cardUnknown: Int = 0
    var showmasterPlayed: Int = 0
    var storedTier: MasteryTier = .f
    var totalResponseTime: Double = 0
    var fastestResponseTime: Double?
    var slowestResponseTime: Double?
    var lastPracticedAt: Date?
    var lastKnownAt: Date?
    var lastTierDecayAt: Date?
    var tierHistory: [TierHistoryEntry]?
    
    var accuracy: Double {
        attempts == 0 ? 0 : Double(correct) / Double(attempts)
    }
    
    var cardAccuracy: Double {
        cardReviews == 0 ? 0 : Double(cardKnown) / Double(cardReviews)
    }
    
    var averageResponseTime: Double? {
        attempts == 0 ? nil : totalResponseTime / Double(attempts)
    }
    
    var tier: MasteryTier {
        storedTier
    }
    
    mutating func recordQuizAnswer(isCorrect: Bool, responseTime: Double) {
        attempts += 1
        totalResponseTime += responseTime
        fastestResponseTime = minOptional(fastestResponseTime, responseTime)
        slowestResponseTime = maxOptional(slowestResponseTime, responseTime)
        
        if isCorrect {
            correct += 1
        } else {
            wrong += 1
        }
    }
    
    mutating func recordCardReview(isKnown: Bool, now: Date = Date()) {
        cardReviews += 1
        lastPracticedAt = now
        lastTierDecayAt = nil
        
        if isKnown {
            cardKnown += 1
            lastKnownAt = now
            storedTier = storedTier.promoted
        } else {
            cardUnknown += 1
            storedTier = storedTier.demoted
        }
        appendTierHistory(tier: storedTier, date: now)
    }
    
    mutating func recordShowmasterCard() {
        showmasterPlayed += 1
    }
    
    mutating func applyWeeklyDecay(now: Date = Date(), calendar: Calendar = .current) -> TierDecayChange? {
        guard storedTier != .f else { return nil }
        let knownReferenceDate = lastKnownAt ?? lastPracticedAt
        guard let knownReferenceDate else { return nil }
        let decayReferenceDate = lastTierDecayAt ?? knownReferenceDate
        guard let daysSinceReference = calendar.dateComponents([.day], from: decayReferenceDate, to: now).day, daysSinceReference >= 3 else { return nil }
        
        let decaySteps = min(daysSinceReference / 3, decayDistanceToF)
        guard decaySteps > 0 else { return nil }
        
        let tierBeforeDecay = storedTier
        for _ in 0..<decaySteps {
            storedTier = storedTier.demoted
        }
        lastTierDecayAt = calendar.date(byAdding: .day, value: decaySteps * 3, to: decayReferenceDate) ?? now
        appendTierHistory(tier: storedTier, date: lastTierDecayAt ?? now)
        
        let daysSinceLastKnown = calendar.dateComponents([.day], from: knownReferenceDate, to: now).day ?? daysSinceReference
        return TierDecayChange(from: tierBeforeDecay, to: storedTier, daysSinceLastPractice: daysSinceLastKnown)
    }
    
    private var decayDistanceToF: Int {
        switch storedTier {
        case .s: return 5
        case .a: return 4
        case .b: return 3
        case .c: return 2
        case .d: return 1
        case .f: return 0
        }
    }
    
    mutating func appendTierHistory(tier: MasteryTier, date: Date) {
        var history = tierHistory ?? []
        if let last = history.last, Calendar.current.isDate(last.date, inSameDayAs: date), last.tier == tier {
            return
        }
        history.append(TierHistoryEntry(date: date, tier: tier))
        tierHistory = Array(history.suffix(21))
    }
    
    private func minOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return min(current, newValue)
    }
    
    private func maxOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return max(current, newValue)
    }
}

struct UserProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var pin: String
    var totalAnswers: Int = 0
    var correctAnswers: Int = 0
    var wrongAnswers: Int = 0
    var currentStreak: Int = 0
    var bestStreak: Int = 0
    var totalResponseTime: Double = 0
    var fastestResponseTime: Double?
    var slowestResponseTime: Double?
    var showmasterCards: Int = 0
    var byCountry: [String: CountryStats] = [:]
    var learningStreak: Int?
    var bestLearningStreak: Int?
    var lastLearningStreakDate: Date?
    var practiceCardsByDay: [String: Int]?
    var perfectFullPracticeSessionSubjects: [String]?
    var announcedAchievementIDs: [String]?
    var achievedAchievementDates: [String: Date]?
    var leagueStats: LeagueStats?
    
    var accuracy: Double {
        totalAnswers == 0 ? 0 : Double(correctAnswers) / Double(totalAnswers)
    }
    
    var averageResponseTime: Double? {
        totalAnswers == 0 ? nil : totalResponseTime / Double(totalAnswers)
    }
    
    mutating func recordQuizAnswer(country: Country, isCorrect: Bool, responseTime: Double) {
        totalAnswers += 1
        totalResponseTime += responseTime
        fastestResponseTime = minOptional(fastestResponseTime, responseTime)
        slowestResponseTime = maxOptional(slowestResponseTime, responseTime)
        
        if isCorrect {
            correctAnswers += 1
            currentStreak += 1
            bestStreak = max(bestStreak, currentStreak)
        } else {
            wrongAnswers += 1
            currentStreak = 0
        }
        
        var countryStats = byCountry[country.code] ?? CountryStats()
        countryStats.recordQuizAnswer(isCorrect: isCorrect, responseTime: responseTime)
        byCountry[country.code] = countryStats
    }
    
    mutating func recordCardReview(country: Country, subject: LearningSubject = .countries, isKnown: Bool, now: Date = Date(), calendar: Calendar = .current) {
        let key = subject.statsKey(for: country)
        var countryStats = byCountry[key] ?? CountryStats()
        countryStats.recordCardReview(isKnown: isKnown, now: now)
        byCountry[key] = countryStats
        
        let dayKey = Self.practiceDayKey(for: now, subject: subject, calendar: calendar)
        var cardsByDay = practiceCardsByDay ?? [:]
        cardsByDay[dayKey, default: 0] += 1
        practiceCardsByDay = cardsByDay
    }
    
    func maxPracticeCardsInOneDay(subject: LearningSubject) -> Int {
        let prefix = "\(subject.rawValue)|"
        return practiceCardsByDay?
            .filter { $0.key.hasPrefix(prefix) }
            .map(\.value)
            .max() ?? 0
    }
    
    func practiceCardsInLastSevenDays(subject: LearningSubject, now: Date = Date(), calendar: Calendar = .current) -> Int {
        let prefix = "\(subject.rawValue)|"
        let validDayKeys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now).map {
                "\(prefix)\(Self.dayKey(for: $0, calendar: calendar))"
            }
        })
        
        return practiceCardsByDay?
            .filter { validDayKeys.contains($0.key) }
            .map(\.value)
            .reduce(0, +) ?? 0
    }
    
    mutating func recordPerfectFullPracticeSession(subject: LearningSubject) {
        var subjects = Set(perfectFullPracticeSessionSubjects ?? [])
        subjects.insert(subject.rawValue)
        perfectFullPracticeSessionSubjects = Array(subjects).sorted()
    }
    
    func hasPerfectFullPracticeSession(subject: LearningSubject) -> Bool {
        Set(perfectFullPracticeSessionSubjects ?? []).contains(subject.rawValue)
    }
    
    static func practiceDayKey(for date: Date, subject: LearningSubject, calendar: Calendar = .current) -> String {
        "\(subject.rawValue)|\(dayKey(for: date, calendar: calendar))"
    }
    
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
    
    mutating func recordCompletedTenBlock(on date: Date = Date(), calendar: Calendar = .current) {
        if let lastLearningStreakDate, calendar.isDate(lastLearningStreakDate, inSameDayAs: date) {
            return
        }
        
        if
            let lastLearningStreakDate,
            let yesterday = calendar.date(byAdding: .day, value: -1, to: date),
            calendar.isDate(lastLearningStreakDate, inSameDayAs: yesterday)
        {
            learningStreak = (learningStreak ?? 0) + 1
        } else {
            learningStreak = 1
        }
        
        bestLearningStreak = max(bestLearningStreak ?? 0, learningStreak ?? 0)
        lastLearningStreakDate = date
    }
    
    mutating func applyWeeklyTierDecay(now: Date = Date()) -> [TierDecayChange] {
        var changes: [TierDecayChange] = []
        for key in Array(byCountry.keys) {
            if var change = byCountry[key]?.applyWeeklyDecay(now: now) {
                change.statsKey = key
                changes.append(change)
            }
        }
        return changes
    }
    
    mutating func recordShowmasterCard(country: Country, subject: LearningSubject = .countries) {
        showmasterCards += 1
        let key = subject.statsKey(for: country)
        var countryStats = byCountry[key] ?? CountryStats()
        countryStats.recordShowmasterCard()
        byCountry[key] = countryStats
    }
    
    mutating func recordLeagueMatch(_ result: LeagueMatchResult, opponentRating: Int = 1000) {
        var stats = leagueStats ?? LeagueStats()
        stats.recordMatch(result, opponentRating: opponentRating)
        leagueStats = stats
    }
    
    func stats(for country: Country, subject: LearningSubject = .countries) -> CountryStats {
        byCountry[subject.statsKey(for: country)] ?? CountryStats()
    }
    
    func tier(for country: Country, subject: LearningSubject = .countries) -> MasteryTier {
        stats(for: country, subject: subject).tier
    }
    
    func countries(in tier: MasteryTier, from countries: [Country] = allCountries) -> [Country] {
        countries.filter { self.tier(for: $0) == tier }.sorted { $0.name < $1.name }
    }
    
    func tierCounts(in countries: [Country] = allCountries) -> [MasteryTier: Int] {
        Dictionary(uniqueKeysWithValues: MasteryTier.allCases.map { tier in
            (tier, self.countries(in: tier, from: countries).count)
        })
    }
    
    private func minOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return min(current, newValue)
    }
    
    private func maxOptional(_ current: Double?, _ newValue: Double) -> Double {
        guard let current else { return newValue }
        return max(current, newValue)
    }
}

struct AppData: Codable {
    var profiles: [UserProfile] = []
    var activeProfileID: UUID?
    
    var activeProfile: UserProfile? {
        guard let activeProfileID else { return nil }
        return profiles.first { $0.id == activeProfileID }
    }
}

enum AppStorageService {
    static let key = "flagTrainerAppDataV2"
    static let legacyStatsKey = "flagQuizStatsV1"
    
    static func load() -> AppData {
        guard let data = UserDefaults.standard.data(forKey: key),
              let appData = try? JSONDecoder().decode(AppData.self, from: data) else {
            return AppData()
        }
        
        return appData
    }
    
    static func save(_ data: AppData) {
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: legacyStatsKey)
    }
}

struct OnlinePlayerStats: Identifiable {
    let id: String
    let playerName: String
    let gameCenterPlayerID: String
    let gameCenterAlias: String
    let totalPracticed: Int
    let known: Int
    let unknown: Int
    let showmasterPlayed: Int
    let learnedThisWeek: Int
    let achievementCount: Int
    let tierS: Int
    let tierA: Int
    let tierB: Int
    let tierC: Int
    let tierD: Int
    let tierF: Int
    let tiersByCountryCode: [String: MasteryTier]
    let achievementIDs: Set<String>
    let sTierHistory: [Int]
    let leagueRating: Int
    let leaguePlayed: Int
    let leagueWins: Int
    let leagueBestScore: Int
    let leagueAverageScore: Double
    let leagueAccuracy: Double
    let updatedAt: Date
    
    var accuracy: Double {
        totalPracticed == 0 ? 0 : Double(known) / Double(totalPracticed)
    }
    
    var displayName: String {
        playerName.isEmpty ? gameCenterAlias : playerName
    }
    
    var friendCode: String {
        String(id.suffix(6)).uppercased()
    }
}

struct LeagueLiveMatch {
    let id: String
    let playerAID: String
    let playerBID: String
    let playerAName: String
    let playerBName: String
    let countryCodes: [String]
    let playerAScore: Int?
    let playerBScore: Int?
    
    func opponentName(for playerID: String) -> String {
        playerID == playerAID ? playerBName : playerAName
    }
    
    func opponentScore(for playerID: String) -> Int? {
        playerID == playerAID ? playerBScore : playerAScore
    }
}

enum OnlineStatsService {
    static let recordType = "PlayerStats"
    static let liveMatchRecordType = "LeagueLiveMatch"
    static let nicknameRecordType = "NicknameClaim"
    static let playerIDKey = "onlinePlayerID"
    static let testFriendName = "FlaggenTest"
    static let testFriendRecordName = "test_friend_flaggenbande"
    static let containerIdentifier = "iCloud.de.phil.SpassmitFlaggen"
    static let container = CKContainer(identifier: containerIdentifier)
    static let database = container.publicCloudDatabase
    
    enum OnlineStatsError: LocalizedError {
        case iCloudAccountUnavailable(CKAccountStatus)
        case timeout
        case profileSnapshotEncodingFailed
        case nicknameAlreadyTaken
        
        var errorDescription: String? {
            switch self {
            case .iCloudAccountUnavailable(.noAccount):
                return "Kein iCloud-Account angemeldet."
            case .iCloudAccountUnavailable(.restricted):
                return "iCloud ist auf diesem Gerät eingeschränkt."
            case .iCloudAccountUnavailable(.couldNotDetermine):
                return "iCloud-Status konnte nicht bestimmt werden."
            case .iCloudAccountUnavailable(.temporarilyUnavailable):
                return "iCloud ist vorübergehend nicht verfügbar."
            case .iCloudAccountUnavailable:
                return "iCloud ist nicht verfügbar."
            case .timeout:
                return "CloudKit hat nicht rechtzeitig geantwortet."
            case .profileSnapshotEncodingFailed:
                return "Die lokale Statistik konnte nicht für iCloud vorbereitet werden."
            case .nicknameAlreadyTaken:
                return "Dieser Spitzname ist schon vergeben."
            }
        }
    }
    
    static func playerID(gameCenterPlayerID: String?) -> String {
        if let gameCenterPlayerID, !gameCenterPlayerID.isEmpty {
            return "gc_" + gameCenterPlayerID.map { character in
                character.isLetter || character.isNumber ? String(character) : "_"
            }.joined()
        }
        
        if let existingID = UserDefaults.standard.string(forKey: playerIDKey) {
            return existingID
        }
        
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: playerIDKey)
        return newID
    }
    
    static func upload(
        name: String,
        gameCenterPlayerID: String?,
        gameCenterAlias: String,
        appData: AppData,
        profile: UserProfile,
        countries: [Country],
        subject: LearningSubject,
        achievementIDs: [String]
    ) async throws {
        try await ensureAccountAvailable()
        let playerRecordName = playerID(gameCenterPlayerID: gameCenterPlayerID)
        let recordID = CKRecord.ID(recordName: playerRecordName)
        let record = try await fetchRecord(recordID: recordID) ?? CKRecord(recordType: recordType, recordID: recordID)
        let profileSnapshot = try profileSnapshotData(profile: profile)
        let displayName = normalizedName(name, fallback: gameCenterAlias)
        let subjectStats = countries.map { profile.stats(for: $0, subject: subject) }
        let counts = Dictionary(grouping: subjectStats.map(\.tier), by: { $0 }).mapValues(\.count)
        if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try await claimNickname(displayName, ownerRecordName: playerRecordName)
        }
        
        record["playerName"] = displayName as CKRecordValue
        record["gameCenterPlayerID"] = (gameCenterPlayerID ?? "") as CKRecordValue
        record["gameCenterAlias"] = gameCenterAlias as CKRecordValue
        record["totalPracticed"] = subjectStats.reduce(0) { $0 + $1.cardReviews } as CKRecordValue
        record["known"] = subjectStats.reduce(0) { $0 + $1.cardKnown } as CKRecordValue
        record["unknown"] = subjectStats.reduce(0) { $0 + $1.cardUnknown } as CKRecordValue
        record["showmasterPlayed"] = subjectStats.reduce(0) { $0 + $1.showmasterPlayed } as CKRecordValue
        record["learnedThisWeek"] = profile.practiceCardsInLastSevenDays(subject: subject) as CKRecordValue
        record["achievementCount"] = achievementIDs.count as CKRecordValue
        record["achievementIDs"] = achievementIDs.sorted().joined(separator: "|") as CKRecordValue
        record["leagueRating"] = (profile.leagueStats?.rating ?? 1000) as CKRecordValue
        record["leaguePlayed"] = (profile.leagueStats?.played ?? 0) as CKRecordValue
        record["leagueWins"] = (profile.leagueStats?.wins ?? 0) as CKRecordValue
        record["leagueBestScore"] = (profile.leagueStats?.bestScore ?? 0) as CKRecordValue
        record["leagueAverageScore"] = (profile.leagueStats?.averageScore ?? 0) as CKRecordValue
        record["leagueAccuracy"] = (profile.leagueStats?.accuracy ?? 0) as CKRecordValue
        record["tierS"] = (counts[.s] ?? 0) as CKRecordValue
        record["tierA"] = (counts[.a] ?? 0) as CKRecordValue
        record["tierB"] = (counts[.b] ?? 0) as CKRecordValue
        record["tierC"] = (counts[.c] ?? 0) as CKRecordValue
        record["tierD"] = (counts[.d] ?? 0) as CKRecordValue
        record["tierF"] = (counts[.f] ?? 0) as CKRecordValue
        record["tierSnapshot"] = tierSnapshot(profile: profile, countries: countries, subject: subject) as CKRecordValue
        record["sTierHistory"] = sTierHistorySnapshot(profile: profile, countries: countries, subject: subject) as CKRecordValue
        record["profileSnapshot"] = profileSnapshot
        record["profileSnapshotVersion"] = 1 as CKRecordValue
        record["appDataSnapshot"] = try appDataSnapshotData(appData)
        record["appDataSnapshotVersion"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        
        try await save(record: record)
        try? await deleteLegacyAnonymousRecordIfNeeded(currentRecordName: playerRecordName, gameCenterPlayerID: gameCenterPlayerID)
    }
    
    static func fetchAppDataSnapshot(gameCenterPlayerID: String?) async throws -> AppData? {
        try await ensureAccountAvailable()
        let playerRecordName = playerID(gameCenterPlayerID: gameCenterPlayerID)
        guard let record = try await fetchRecord(recordID: CKRecord.ID(recordName: playerRecordName)) else {
            return nil
        }
        
        if let snapshotData = record["appDataSnapshot"] as? Data,
           let snapshot = try? JSONDecoder().decode(AppData.self, from: snapshotData) {
            return snapshot
        }
        
        if let snapshotData = record["appDataSnapshot"] as? NSData,
           let snapshot = try? JSONDecoder().decode(AppData.self, from: snapshotData as Data) {
            return snapshot
        }
        
        if let profileData = record["profileSnapshot"] as? Data,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData) {
            return AppData(profiles: [profile], activeProfileID: profile.id)
        }
        
        if let profileData = record["profileSnapshot"] as? NSData,
           let profile = try? JSONDecoder().decode(UserProfile.self, from: profileData as Data) {
            return AppData(profiles: [profile], activeProfileID: profile.id)
        }
        
        return nil
    }
    
    static func fetchLeaderboard() async throws -> [OnlinePlayerStats] {
        try await ensureAccountAvailable()
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let records = try await queryRecords(query)
        return records
            .compactMap(OnlinePlayerStats.init(record:))
            .sorted {
                if $0.totalPracticed == $1.totalPracticed {
                    return $0.accuracy > $1.accuracy
                }
                return $0.totalPracticed > $1.totalPracticed
            }
    }
    
    static func findOrCreateLiveLeagueMatch(
        currentPlayerID: String,
        currentPlayerName: String,
        opponent: OnlinePlayerStats,
        countries: [Country]
    ) async throws -> LeagueLiveMatch {
        try await ensureAccountAvailable()
        let ids = [currentPlayerID, opponent.id].sorted()
        let recordName = "league_live_" + ids.joined(separator: "_").filter { $0.isLetter || $0.isNumber || $0 == "_" }
        let recordID = CKRecord.ID(recordName: recordName)
        
        if let existing = try await fetchRecord(recordID: recordID),
           let match = LeagueLiveMatch(record: existing),
           match.countryCodes.count >= 20,
           existing["createdAt"] as? Date ?? .distantPast > Date().addingTimeInterval(-900),
           (match.playerAScore == nil || match.playerBScore == nil) {
            return match
        }
        
        let currentIsA = currentPlayerID == ids[0]
        let sequence = countries.shuffled().prefix(80).map(\.code).joined(separator: "|")
        let record = CKRecord(recordType: liveMatchRecordType, recordID: recordID)
        record["playerAID"] = ids[0] as CKRecordValue
        record["playerBID"] = ids[1] as CKRecordValue
        record["playerAName"] = (currentIsA ? currentPlayerName : opponent.displayName) as CKRecordValue
        record["playerBName"] = (currentIsA ? opponent.displayName : currentPlayerName) as CKRecordValue
        record["countryCodes"] = sequence as CKRecordValue
        record["createdAt"] = Date() as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record)
        return LeagueLiveMatch(record: record) ?? LeagueLiveMatch(
            id: recordName,
            playerAID: ids[0],
            playerBID: ids[1],
            playerAName: currentIsA ? currentPlayerName : opponent.displayName,
            playerBName: currentIsA ? opponent.displayName : currentPlayerName,
            countryCodes: sequence.split(separator: "|").map(String.init),
            playerAScore: nil,
            playerBScore: nil
        )
    }
    
    static func submitLiveLeagueScore(matchID: String, playerID: String, score: Int) async throws {
        try await ensureAccountAvailable()
        let recordID = CKRecord.ID(recordName: matchID)
        guard let record = try await fetchRecord(recordID: recordID) else { return }
        if (record["playerAID"] as? String) == playerID {
            record["playerAScore"] = score as CKRecordValue
        } else if (record["playerBID"] as? String) == playerID {
            record["playerBScore"] = score as CKRecordValue
        }
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record)
    }
    
    static func fetchLiveLeagueMatch(matchID: String) async throws -> LeagueLiveMatch? {
        try await ensureAccountAvailable()
        guard let record = try await fetchRecord(recordID: CKRecord.ID(recordName: matchID)) else { return nil }
        return LeagueLiveMatch(record: record)
    }
    
    static func createTestFriend(countries: [Country]) async throws {
        try await ensureAccountAvailable()
        let record = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: testFriendRecordName))
        let tiers = countries.enumerated().map { index, country in
            let tier: MasteryTier
            switch index % 6 {
            case 0: tier = .s
            case 1: tier = .a
            case 2: tier = .b
            case 3: tier = .c
            case 4: tier = .d
            default: tier = .f
            }
            return (country.code, tier)
        }
        let tierCounts = Dictionary(grouping: tiers.map(\.1), by: { $0 }).mapValues(\.count)
        
        record["playerName"] = testFriendName as CKRecordValue
        record["gameCenterPlayerID"] = "test.friend.flaggenbande" as CKRecordValue
        record["gameCenterAlias"] = testFriendName as CKRecordValue
        record["totalPracticed"] = 418 as CKRecordValue
        record["known"] = 337 as CKRecordValue
        record["unknown"] = 81 as CKRecordValue
        record["showmasterPlayed"] = 12 as CKRecordValue
        record["learnedThisWeek"] = 73 as CKRecordValue
        record["achievementCount"] = 9 as CKRecordValue
        record["achievementIDs"] = [
            "first-card",
            "ten-known",
            "fifty-known",
            "fifty-reviews",
            "two-hundred-fifty-reviews",
            "three-day-streak",
            "a-tier-five",
            "first-s-tier",
            "showmaster-ten"
        ].joined(separator: "|") as CKRecordValue
        record["leagueRating"] = 1138 as CKRecordValue
        record["leaguePlayed"] = 18 as CKRecordValue
        record["leagueWins"] = 11 as CKRecordValue
        record["leagueBestScore"] = 1240 as CKRecordValue
        record["leagueAverageScore"] = 840.0 as CKRecordValue
        record["leagueAccuracy"] = 0.82 as CKRecordValue
        record["tierS"] = (tierCounts[.s] ?? 0) as CKRecordValue
        record["tierA"] = (tierCounts[.a] ?? 0) as CKRecordValue
        record["tierB"] = (tierCounts[.b] ?? 0) as CKRecordValue
        record["tierC"] = (tierCounts[.c] ?? 0) as CKRecordValue
        record["tierD"] = (tierCounts[.d] ?? 0) as CKRecordValue
        record["tierF"] = (tierCounts[.f] ?? 0) as CKRecordValue
        record["tierSnapshot"] = tiers.map { "\($0.0):\($0.1.rawValue)" }.joined(separator: "|") as CKRecordValue
        record["sTierHistory"] = [19, 21, 23, 24, 26, 28, 29, 31, 33, 34, 35, 37, 38, tierCounts[.s] ?? 0].map(String.init).joined(separator: "|") as CKRecordValue
        record["profileSnapshotVersion"] = 1 as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record)
    }
    
    static func fetchRecord(recordID: CKRecord.ID) async throws -> CKRecord? {
        try await withTimeout {
            try await withCheckedThrowingContinuation { continuation in
                database.fetch(withRecordID: recordID) { record, error in
                    if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                        continuation.resume(returning: nil)
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: record)
                    }
                }
            }
        }
    }
    
    static func save(record: CKRecord) async throws {
        try await withTimeout {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                operation.savePolicy = .changedKeys
                operation.qualityOfService = .userInitiated
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                database.add(operation)
            }
        }
    }
    
    static func delete(recordID: CKRecord.ID) async throws {
        try await withTimeout {
            try await withCheckedThrowingContinuation { continuation in
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
                operation.qualityOfService = .utility
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        if let cloudError = error as? CKError, cloudError.code == .unknownItem {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
                database.add(operation)
            }
        }
    }
    
    static func deleteLegacyAnonymousRecordIfNeeded(currentRecordName: String, gameCenterPlayerID: String?) async throws {
        guard let gameCenterPlayerID, !gameCenterPlayerID.isEmpty else { return }
        guard let legacyRecordName = UserDefaults.standard.string(forKey: playerIDKey) else { return }
        guard legacyRecordName != currentRecordName else { return }
        
        try await delete(recordID: CKRecord.ID(recordName: legacyRecordName))
    }
    
    static func queryRecords(_ query: CKQuery) async throws -> [CKRecord] {
        try await withTimeout {
            var allRecords: [CKRecord] = []
            var cursor: CKQueryOperation.Cursor?
            
            repeat {
                let page = try await queryRecordPage(query: query, cursor: cursor)
                allRecords.append(contentsOf: page.records)
                cursor = page.cursor
            } while cursor != nil
            
            return allRecords
        }
    }
    
    static func queryRecordPage(query: CKQuery, cursor: CKQueryOperation.Cursor?) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let lock = NSLock()
            let operation = cursor.map(CKQueryOperation.init(cursor:)) ?? CKQueryOperation(query: query)
            operation.resultsLimit = 100
            operation.qualityOfService = .userInitiated
            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    lock.lock()
                    records.append(record)
                    lock.unlock()
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (records, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }
    
    static func normalizedName(_ name: String, fallback: String = "Spieler") -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (fallbackName.isEmpty ? "Spieler" : fallbackName) : trimmed
    }
    
    static func claimNickname(_ nickname: String, ownerRecordName: String) async throws {
        let key = nicknameKey(for: nickname)
        guard !key.isEmpty else { return }
        
        let recordID = CKRecord.ID(recordName: "nickname_\(key)")
        if let existingRecord = try await fetchRecord(recordID: recordID) {
            let owner = existingRecord["ownerRecordName"] as? String ?? ""
            if owner != ownerRecordName {
                throw OnlineStatsError.nicknameAlreadyTaken
            }
            return
        }
        
        let record = CKRecord(recordType: nicknameRecordType, recordID: recordID)
        record["nickname"] = nickname as CKRecordValue
        record["ownerRecordName"] = ownerRecordName as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
        try await save(record: record)
    }
    
    static func nicknameKey(for nickname: String) -> String {
        nickname
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .map { character in
                character.isLetter || character.isNumber ? String(character) : "_"
            }
            .joined()
    }
    
    static func userFacingMessage(for error: Error) -> String {
        if let onlineError = error as? OnlineStatsError {
            return onlineError.localizedDescription
        }
        
        guard let cloudError = error as? CKError else {
            return error.localizedDescription
        }
        
        let detail = cloudError.errorUserInfo[NSLocalizedDescriptionKey] as? String ?? cloudError.localizedDescription
        switch cloudError.code {
        case .notAuthenticated:
            return "iCloud ist nicht angemeldet. Melde dich in den iOS-Einstellungen bei iCloud an."
        case .permissionFailure:
            return "CloudKit hat keine Berechtigung für diesen Container. Prüfe iCloud/CloudKit in Signing & Capabilities."
        case .networkUnavailable, .networkFailure:
            return "Keine stabile Netzwerkverbindung zu iCloud."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud ist gerade ausgelastet. Bitte später erneut versuchen."
        case .invalidArguments:
            return "CloudKit lehnt die Datenstruktur ab: \(detail)"
        case .serverRecordChanged:
            return "Der iCloud-Datensatz wurde gleichzeitig geändert. Bitte erneut synchronisieren."
        case .unknownItem:
            return "Der CloudKit-Datensatz existiert noch nicht."
        default:
            return "CloudKit-Fehler \(cloudError.code.rawValue): \(detail)"
        }
    }
    
    static func tierSnapshot(profile: UserProfile, countries: [Country], subject: LearningSubject) -> String {
        countries
            .map { "\($0.code):\(profile.tier(for: $0, subject: subject).rawValue)" }
            .joined(separator: "|")
    }
    
    static func sTierHistorySnapshot(profile: UserProfile, countries: [Country], subject: LearningSubject, days: Int = 14) -> String {
        let calendar = Calendar.current
        let now = Date()
        let values = (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: now) ?? now
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day) ?? day
            return countries.reduce(0) { count, country in
                let stats = profile.stats(for: country, subject: subject)
                let historyTier = stats.tierHistory?
                    .filter { $0.date <= endOfDay }
                    .sorted { $0.date < $1.date }
                    .last?
                    .tier
                return count + ((historyTier ?? stats.tier) == .s ? 1 : 0)
            }
        }
        return values.map(String.init).joined(separator: "|")
    }
    
    static func profileSnapshotData(profile: UserProfile) throws -> CKRecordValue {
        guard let data = try? JSONEncoder().encode(profile) else {
            throw OnlineStatsError.profileSnapshotEncodingFailed
        }
        return data as NSData
    }
    
    static func appDataSnapshotData(_ appData: AppData) throws -> CKRecordValue {
        guard let data = try? JSONEncoder().encode(appData) else {
            throw OnlineStatsError.profileSnapshotEncodingFailed
        }
        return data as NSData
    }
    
    static func ensureAccountAvailable() async throws {
        let status: CKAccountStatus = try await withTimeout(seconds: 8) {
            try await withCheckedThrowingContinuation { continuation in
                container.accountStatus { status, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: status)
                    }
                }
            }
        }
        
        guard status == .available else {
            throw OnlineStatsError.iCloudAccountUnavailable(status)
        }
    }
    
    static func withTimeout<T>(seconds: Double = 15, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw OnlineStatsError.timeout
            }
            
            guard let result = try await group.next() else {
                throw OnlineStatsError.timeout
            }
            group.cancelAll()
            return result
        }
    }
}

extension OnlinePlayerStats {
    init?(record: CKRecord) {
        guard let playerName = record["playerName"] as? String else { return nil }
        id = record.recordID.recordName
        self.playerName = playerName
        gameCenterPlayerID = record["gameCenterPlayerID"] as? String ?? ""
        gameCenterAlias = record["gameCenterAlias"] as? String ?? ""
        totalPracticed = (record["totalPracticed"] as? NSNumber)?.intValue ?? 0
        known = (record["known"] as? NSNumber)?.intValue ?? 0
        unknown = (record["unknown"] as? NSNumber)?.intValue ?? 0
        showmasterPlayed = (record["showmasterPlayed"] as? NSNumber)?.intValue ?? 0
        learnedThisWeek = (record["learnedThisWeek"] as? NSNumber)?.intValue ?? 0
        achievementCount = (record["achievementCount"] as? NSNumber)?.intValue ?? 0
        tierS = (record["tierS"] as? NSNumber)?.intValue ?? 0
        tierA = (record["tierA"] as? NSNumber)?.intValue ?? 0
        tierB = (record["tierB"] as? NSNumber)?.intValue ?? 0
        tierC = (record["tierC"] as? NSNumber)?.intValue ?? 0
        tierD = (record["tierD"] as? NSNumber)?.intValue ?? 0
        tierF = (record["tierF"] as? NSNumber)?.intValue ?? 0
        tiersByCountryCode = Self.parseTierSnapshot(record["tierSnapshot"] as? String)
        achievementIDs = Set((record["achievementIDs"] as? String ?? "").split(separator: "|").map(String.init))
        sTierHistory = Self.parseIntSnapshot(record["sTierHistory"] as? String, fallback: tierS)
        leagueRating = (record["leagueRating"] as? NSNumber)?.intValue ?? 1000
        leaguePlayed = (record["leaguePlayed"] as? NSNumber)?.intValue ?? 0
        leagueWins = (record["leagueWins"] as? NSNumber)?.intValue ?? 0
        leagueBestScore = (record["leagueBestScore"] as? NSNumber)?.intValue ?? 0
        leagueAverageScore = (record["leagueAverageScore"] as? NSNumber)?.doubleValue ?? 0
        leagueAccuracy = (record["leagueAccuracy"] as? NSNumber)?.doubleValue ?? 0
        updatedAt = (record["updatedAt"] as? Date) ?? .distantPast
    }
    
    private static func parseTierSnapshot(_ snapshot: String?) -> [String: MasteryTier] {
        guard let snapshot else { return [:] }
        return Dictionary(uniqueKeysWithValues: snapshot.split(separator: "|").compactMap { entry in
            let parts = entry.split(separator: ":")
            guard parts.count == 2, let tier = MasteryTier(rawValue: String(parts[1])) else { return nil }
            return (String(parts[0]), tier)
        })
    }
    
    private static func parseIntSnapshot(_ snapshot: String?, fallback: Int) -> [Int] {
        let values = snapshot?.split(separator: "|").compactMap { Int($0) } ?? []
        return values.isEmpty ? [fallback] : values
    }
}

extension LeagueLiveMatch {
    init?(record: CKRecord) {
        guard let playerAID = record["playerAID"] as? String,
              let playerBID = record["playerBID"] as? String,
              let playerAName = record["playerAName"] as? String,
              let playerBName = record["playerBName"] as? String,
              let countryCodesRaw = record["countryCodes"] as? String else {
            return nil
        }
        
        id = record.recordID.recordName
        self.playerAID = playerAID
        self.playerBID = playerBID
        self.playerAName = playerAName
        self.playerBName = playerBName
        countryCodes = countryCodesRaw.split(separator: "|").map(String.init)
        playerAScore = (record["playerAScore"] as? NSNumber)?.intValue
        playerBScore = (record["playerBScore"] as? NSNumber)?.intValue
    }
}

enum CountryScope {
    static let worldwide = "Alle Länder"
}

enum AppScreen: String, CaseIterable, Hashable, Identifiable {
    case practice = "practice"
    case showmaster = "showmaster"
    case miniWorldCup = "miniWorldCup"
    case league = "league"
    case statistics = "statistics"
    case globe = "globe"
    case achievements = "achievements"
    case friends = "friends"
    case options = "options"
    
    func title(language: AppLanguage) -> String {
        switch self {
        case .practice: return localized("Üben", "Practice", language: language)
        case .showmaster: return "Showmaster"
        case .miniWorldCup: return "Mini-WM"
        case .league: return localized("Liga (WIP)", "League (WIP)", language: language)
        case .statistics: return localized("Statistik", "Statistics", language: language)
        case .globe: return localized("Globus", "Globe", language: language)
        case .achievements: return localized("Achievements", "Achievements", language: language)
        case .friends: return localized("Freunde", "Friends", language: language)
        case .options: return localized("Optionen", "Options", language: language)
        }
    }
    
    var iconName: String {
        switch self {
        case .practice: return "rectangle.stack.fill"
        case .showmaster: return "rectangle.on.rectangle"
        case .miniWorldCup: return "trophy.fill"
        case .league: return "trophy.circle.fill"
        case .statistics: return "chart.bar.fill"
        case .globe: return "globe.europe.africa.fill"
        case .achievements: return "trophy.fill"
        case .friends: return "person.2.fill"
        case .options: return "gearshape.fill"
        }
    }
    
    var id: String { rawValue }
    
    func infoText(language: AppLanguage) -> String {
        switch self {
        case .practice:
            return localized("Trainiere einzelne Flaggen oder Hauptstädte. Du wischt Karten als gewusst oder nicht gewusst, damit schwierige Karten häufiger kommen.", "Train individual flags or capitals. Swipe cards as known or not known so difficult cards appear more often.", language: language)
        case .showmaster:
            return localized("Starte eine kurze Kartenrunde ohne Eingabe. Du entscheidest selbst, ob eine Flagge gewusst wurde.", "Start a short card round without typing. You decide whether a flag was known.", language: language)
        case .miniWorldCup:
            return localized("Gib das Handy im Kreis weiter. Jede Person bekommt Flaggen, braucht genug richtige Antworten und scheidet sonst aus.", "Pass the phone around. Each person gets flags, needs enough correct answers, and is eliminated otherwise.", language: language)
        case .league:
            return localized("WIP: Liga, ELO und 1-gegen-1-Runden. Dieser Bereich ist noch im Aufbau.", "WIP: league, ELO, and 1v1 rounds. This area is still being built.", language: language)
        case .statistics:
            return localized("Sieh deine Lernstände, Trefferquoten, Serien und gespeicherten Ergebnisse.", "View your mastery levels, accuracy, streaks, and saved results.", language: language)
        case .globe:
            return localized("Erkunde deine Länder auf dem Globus und öffne einzelne Statistiken direkt über die Karte.", "Explore your countries on the globe and open individual stats directly from the map.", language: language)
        case .achievements:
            return localized("Hier siehst du freigeschaltete Erfolge und deinen Fortschritt zu den nächsten Zielen.", "See unlocked achievements and your progress toward the next goals.", language: language)
        case .friends:
            return localized("Verbinde Onlinefunktionen, vergleiche Fortschritt und verwalte Freundesdaten.", "Connect online features, compare progress, and manage friend data.", language: language)
        case .options:
            return localized("Passe Sprache, Daten, Onlinefunktionen, Debugschalter und App-Einstellungen an.", "Adjust language, data, online features, debug toggles, and app settings.", language: language)
        }
    }
}

struct AchievementItem: Identifiable {
    let id: String
    let title: String
    let description: String
    let iconName: String
    let currentValue: Int
    let targetValue: Int
    let tint: Color
    
    var isUnlocked: Bool {
        currentValue >= targetValue
    }
    
    var progress: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(currentValue) / Double(targetValue), 1)
    }
}

struct PracticeSessionChange: Identifiable {
    let id = UUID()
    let country: Country
    let wasKnown: Bool
    let fromTier: MasteryTier
    let toTier: MasteryTier
}

struct PracticeHistoryPreview: Identifiable, Equatable {
    let change: PracticeSessionChange
    let index: Int
    let total: Int
    
    var id: UUID { change.id }
    
    static func == (lhs: PracticeHistoryPreview, rhs: PracticeHistoryPreview) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index && lhs.total == rhs.total
    }
}

struct GameCenterAuthPresentation: Identifiable {
    let id = UUID()
    let viewController: UIViewController
}

struct GameCenterAuthView: UIViewControllerRepresentable {
    let viewController: UIViewController
    
    func makeUIViewController(context: Context) -> UIViewController {
        viewController
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    }
}

enum OnlineLeaderboardMetric {
    case total
    case week
    case achievements
}

enum OnlineLeaderboardScope: String, CaseIterable, Identifiable {
    case friends
    case global
    
    var id: String { rawValue }
}

enum AchievementSortMode: String, CaseIterable, Identifiable {
    case category
    case date
    case worldwide
    
    var id: String { rawValue }
    
    func title(language: AppLanguage) -> String {
        switch self {
        case .category: return localized("Kategorie", "Category", language: language)
        case .date: return localized("Datum", "Date", language: language)
        case .worldwide: return localized("Weltweit", "Worldwide", language: language)
        }
    }
}

struct ShowSessionEntry: Identifiable {
    let id = UUID()
    let country: Country
}

struct ShowHistoryPreview: Identifiable, Equatable {
    let entry: ShowSessionEntry
    let index: Int
    let total: Int
    
    var id: UUID { entry.id }
    
    static func == (lhs: ShowHistoryPreview, rhs: ShowHistoryPreview) -> Bool {
        lhs.id == rhs.id && lhs.index == rhs.index && lhs.total == rhs.total
    }
}

struct MiniWorldCupPlayer: Identifiable, Equatable {
    let id = UUID()
    var name: String
}

struct MiniWorldCupElimination: Identifiable, Equatable {
    let id = UUID()
    let playerName: String
    let country: Country
    let round: Int
    let correctCount: Int
    let flagCount: Int
}

struct MiniWorldCupBracketRow: Identifiable {
    let place: Int
    let elimination: MiniWorldCupElimination
    
    var id: UUID { elimination.id }
}

enum MiniWorldCupPhase {
    case setup
    case handoff
    case question
    case finished
}

struct PracticeUndoSnapshot {
    let appData: AppData
    let currentCountry: Country
    let practiceSessionCount: Int
    let practiceSessionKnown: Int
    let practiceSessionUnknown: Int
    let practiceSessionImproved: Int
    let practiceSessionResults: [Bool]
    let practiceSessionChanges: [PracticeSessionChange]
    let practiceSessionSeenCountryCodes: Set<String>
    let cardIsFlipped: Bool
    let cardHintIsVisible: Bool
    let currentCardUsedHint: Bool
    let recapEndCounts: [MasteryTier: Int]
}

enum StoreProductID: String, CaseIterable {
    case fullVersion = "de.phil.SpassmitFlaggen.fullversion"
    case donationSmall = "de.phil.SpassmitFlaggen.donation.small"
    case donationMedium = "de.phil.SpassmitFlaggen.donation.medium"
    case donationLarge = "de.phil.SpassmitFlaggen.donation.large"
    
    static var allIDs: [String] {
        allCases.map(\.rawValue)
    }
    
    static var donationIDs: Set<String> {
        [donationSmall.rawValue, donationMedium.rawValue, donationLarge.rawValue]
    }
}

@MainActor
final class StoreKitManager: ObservableObject {
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchasedFullVersion: Bool = false
    @Published private(set) var isLoading: Bool = false
    @Published var statusText: String?
    
    private var updatesTask: Task<Void, Never>?
    
    init() {}
    
    deinit {
        updatesTask?.cancel()
    }
    
    var fullVersionProduct: Product? {
        products.first { $0.id == StoreProductID.fullVersion.rawValue }
    }
    
    var donationProducts: [Product] {
        products
            .filter { StoreProductID.donationIDs.contains($0.id) }
            .sorted { $0.displayPrice < $1.displayPrice }
    }
    
    private func startObservingTransactionsIfNeeded() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                await self?.handleTransactionResult(result)
            }
        }
    }
    
    func loadProducts() async {
        startObservingTransactionsIfNeeded()
        isLoading = true
        defer { isLoading = false }
        
        do {
            products = try await Product.products(for: StoreProductID.allIDs)
            await refreshEntitlements()
            statusText = nil
        } catch {
            statusText = "Store konnte nicht geladen werden."
        }
    }
    
    func purchase(_ product: Product) async {
        startObservingTransactionsIfNeeded()
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verificationResult):
                await handleTransactionResult(verificationResult)
            case .pending:
                statusText = "Kauf wartet auf Bestätigung."
            case .userCancelled:
                statusText = nil
            @unknown default:
                statusText = "Kauf konnte nicht abgeschlossen werden."
            }
        } catch {
            statusText = "Kauf fehlgeschlagen."
        }
    }
    
    func restorePurchases() async {
        startObservingTransactionsIfNeeded()
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusText = purchasedFullVersion ? "Vollversion wiederhergestellt." : "Keine Vollversion gefunden."
        } catch {
            statusText = "Wiederherstellen fehlgeschlagen."
        }
    }
    
    func refreshEntitlements() async {
        var hasFullVersion = false
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == StoreProductID.fullVersion.rawValue && transaction.revocationDate == nil {
                hasFullVersion = true
            }
        }
        purchasedFullVersion = hasFullVersion
    }
    
    private func handleTransactionResult(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            if transaction.productID == StoreProductID.fullVersion.rawValue {
                purchasedFullVersion = transaction.revocationDate == nil
                statusText = purchasedFullVersion ? "Vollversion freigeschaltet." : nil
            } else if StoreProductID.donationIDs.contains(transaction.productID) {
                statusText = "Danke für deine Unterstützung."
            }
            await transaction.finish()
        case .unverified:
            statusText = "Kauf konnte nicht verifiziert werden."
        }
    }
}

struct ContentView: View {
    @AppStorage("onlinePlayerName") private var onlinePlayerName: String = ""
    @AppStorage("appLanguage") private var appLanguageRawValue: String = AppLanguage.german.rawValue
    @AppStorage("appTheme") private var appThemeRawValue: String = AppTheme.system.rawValue
    @AppStorage("appAccent") private var appAccentRawValue: String = AppAccent.teal.rawValue
    @AppStorage("friendNames") private var friendNamesRawValue: String = ""
    @AppStorage("includePartiallyRecognizedFlags") private var includePartiallyRecognizedFlags: Bool = false
    @AppStorage("onlineFeaturesEnabled") private var onlineFeaturesEnabled: Bool = true
    @AppStorage("didEnableOnlineByDefault") private var didEnableOnlineByDefault: Bool = false
    @AppStorage("debugToolsEnabled") private var debugToolsEnabled: Bool = false
    @AppStorage("fullVersionUnlocked") private var fullVersionUnlocked: Bool = false
    @StateObject private var storeKit = StoreKitManager()
    @State private var appData: AppData = AppStorageService.load()
    @State private var onlineLeaderboard: [OnlinePlayerStats] = []
    @State private var onlineLeaderboardRefreshID: Int = 0
    @State private var onlineStatusText: String = "Online-Rangliste noch nicht geladen"
    @State private var isSyncingOnlineStats: Bool = false
    @State private var isRestoringCloudBackup: Bool = false
    @State private var cloudBackupRestoreAttemptedPlayerID: String = ""
    @State private var pendingOnlineSyncTask: Task<Void, Never>?
    @State private var isGameCenterAuthenticated: Bool = false
    @State private var gameCenterPlayerID: String = ""
    @State private var gameCenterAlias: String = ""
    @State private var gameCenterStatusText: String = "Game Center noch nicht verbunden"
    @State private var gameCenterAuthPresentation: GameCenterAuthPresentation?
    @State private var gameCenterFriendIDs: Set<String> = []
    @State private var selectedOnlineGlobePlayer: OnlinePlayerStats?
    @State private var selectedOnlineScope: OnlineLeaderboardScope = .friends
    @State private var isShowingFriendInfo: Bool = false
    @State private var isShowingOnlineInfo: Bool = false
    @State private var isShowingNicknameInfo: Bool = false
    @State private var isShowingFriendList: Bool = false
    @State private var friendPendingRemoval: String?
    @State private var selectedSubject: LearningSubject = .countries
    @State private var selectedPracticeContinents: Set<String> = [CountryScope.worldwide]
    @State private var selectedShowContinents: Set<String> = [CountryScope.worldwide]
    @State private var selectedStatisticsContinents: Set<String> = [CountryScope.worldwide]
    @State private var selectedStatisticsTier: MasteryTier?
    @State private var isTierExplanationExpanded: Bool = false
    @State private var isMasteryScoreInfoExpanded: Bool = false
    @State private var isDisputedTerritoriesInfoExpanded: Bool = false
    @State private var expandedStatisticsCountryCodes: Set<String> = []
    @State private var statisticsSearchText: String = ""
    @FocusState private var isStatisticsSearchFocused: Bool
    @State private var newFriendName: String = ""
    @State private var selectedPracticeCardLimit: Int = 10
    @State private var selectedShowCardLimit: Int = 0
    @State private var showAvoidsRecentRepeats: Bool = true
    @State private var leagueShowsStartMenu: Bool = true
    @State private var leagueOpponentPickerPulse: Bool = false
    @State private var selectedLeagueOpponentID: String = "preset_average"
    @State private var leagueMatchActive: Bool = false
    @State private var leagueSecondsRemaining: Int = 60
    @State private var leagueCurrentCountry: Country = allCountries[0]
    @State private var leagueAnswerText: String = ""
    @State private var leagueCorrect: Int = 0
    @State private var leagueWrong: Int = 0
    @State private var leagueScore: Int = 0
    @State private var leagueRecentCountryCodes: [String] = []
    @State private var leagueAnswerRecords: [LeagueAnswerRecord] = []
    @State private var leagueSummaryResult: LeagueMatchResult?
    @State private var leagueAnswerMatch: LeagueAnswerMatch?
    @State private var leagueAutoSubmitTask: Task<Void, Never>?
    @State private var leagueTimerIsRunning: Bool = false
    @State private var leagueTimerStartTask: Task<Void, Never>?
    @State private var leagueCountdownTask: Task<Void, Never>?
    @State private var leagueAdvanceTask: Task<Void, Never>?
    @State private var leagueFeedbackClearTask: Task<Void, Never>?
    @State private var leagueInputIsLocked: Bool = false
    @State private var leagueLockedAnswerText: String = ""
    @State private var leagueAnswerFeedback: Bool?
    @State private var leagueRevealedCountryName: String = ""
    @State private var leagueMatchPhase: LeagueMatchPhase = .loading
    @State private var leagueStartCountdown: Int = 3
    @State private var leagueFirstFlagIsReady: Bool = false
    @State private var leaguePreloadedFlagImage: UIImage?
    @State private var leagueTypingLockedUntil: Date = .distantPast
    @State private var leagueCurrentQuestionStartedAt: Date = Date()
    @State private var leagueIsPreparingLiveMatch: Bool = false
    @State private var leagueLiveMatchID: String?
    @State private var leagueLivePlayerID: String = ""
    @State private var leagueLiveOpponentName: String = ""
    @State private var leagueLiveOpponentScore: Int?
    @State private var leagueLiveCountryCodes: [String] = []
    @State private var leagueLiveCountryIndex: Int = 0
    @State private var leagueLiveResultText: String = ""
    @State private var leagueLivePollTask: Task<Void, Never>?
    @State private var leagueNotificationsAuthorized: Bool = false
    @State private var leagueTestFriendEnsured: Bool = false
    @FocusState private var isLeagueAnswerFocused: Bool
    @State private var practiceSessionSeenCountryCodes: Set<String> = []
    @State private var showRecentCountryCodes: [String] = []
    @State private var showDeckCountryCodes: [String] = []
    @State private var practiceSessionCount: Int = 0
    @State private var practiceSessionKnown: Int = 0
    @State private var practiceSessionUnknown: Int = 0
    @State private var practiceSessionImproved: Int = 0
    @State private var practiceSessionResults: [Bool] = []
    @State private var practiceSessionChanges: [PracticeSessionChange] = []
    @State private var practiceHistoryPreview: PracticeHistoryPreview?
    @State private var practiceHistoryBarMinY: CGFloat = 150
    @State private var practiceForcedNextCountry: Country?
    @State private var practiceUndoSnapshot: PracticeUndoSnapshot?
    @State private var practiceSessionActive: Bool = false
    @State private var showSessionActive: Bool = false
    @State private var showSessionCount: Int = 0
    @State private var showSessionEntries: [ShowSessionEntry] = []
    @State private var showHistoryPreview: ShowHistoryPreview?
    @State private var showHistoryBarMinY: CGFloat = 150
    @State private var miniWorldCupPlayers: [MiniWorldCupPlayer] = []
    @State private var miniWorldCupNewPlayerName: String = ""
    @State private var miniWorldCupActivePlayers: [MiniWorldCupPlayer] = []
    @State private var miniWorldCupEliminations: [MiniWorldCupElimination] = []
    @State private var miniWorldCupPhase: MiniWorldCupPhase = .setup
    @State private var miniWorldCupCurrentPlayerIndex: Int = 0
    @State private var miniWorldCupCurrentCountry: Country = allCountries[0]
    @State private var miniWorldCupRound: Int = 1
    @State private var miniWorldCupFlagsPerPlayer: Int = 2
    @State private var miniWorldCupRequiredCorrect: Int = 1
    @State private var miniWorldCupCurrentAttempt: Int = 1
    @State private var miniWorldCupCurrentCorrect: Int = 0
    @State private var miniWorldCupCardDragOffset: CGSize = .zero
    @State private var miniWorldCupAnswerFeedback: Bool?
    @State private var currentCountry: Country = allCountries[0]
    @State private var cardIsFlipped: Bool = false
    @State private var cardHintIsVisible: Bool = false
    @State private var currentCardUsedHint: Bool = false
    @State private var hintBlockFeedbackIsVisible: Bool = false
    @State private var practiceCardDragOffset: CGFloat = 0
    @State private var practiceCardEntryOffset: CGFloat = 0
    @State private var practiceCardEntryOpacity: Double = 1
    @State private var isFinishingPracticeSwipe: Bool = false
    @State private var recapStartCounts: [MasteryTier: Int] = [:]
    @State private var recapEndCounts: [MasteryTier: Int] = [:]
    @State private var showRecap: Bool = false
    @State private var isShowingStartupScreen: Bool = true
    @State private var selectedGlobeCountry: Country?
    @State private var globeResetToken: Int = 0
    @State private var tierDecayPopup: TierDecayPopup?
    @State private var selectedTierDecayChangeID: String?
    @State private var achievementPopupItem: AchievementItem?
    @State private var achievementSortMode: AchievementSortMode = .category
    @State private var selectedMenuInfoScreen: AppScreen?
    @State private var isShowingResetConfirmation: Bool = false
    @State private var isShowingShowCancelConfirmation: Bool = false
    
    var body: some View {
        ZStack {
            NavigationStack {
                startView
                    .navigationDestination(for: AppScreen.self) { screen in
                        switch screen {
                        case .practice:
                            practiceView
                        case .showmaster:
                            showView
                        case .miniWorldCup:
                            miniWorldCupView
                        case .league:
                            leagueView
                        case .statistics:
                            statisticsView
                        case .globe:
                            fullVersionUnlocked ? AnyView(globeView) : AnyView(fullVersionLockedView(feature: L("Globus", "Globe")))
                        case .achievements:
                            achievementsView
                        case .friends:
                            friendsView
                        case .options:
                            optionsView
                        }
                    }
            }
            .scaleEffect(isShowingStartupScreen ? 0.96 : 1)
            .opacity(isShowingStartupScreen ? 0.72 : 1)
            .blur(radius: isShowingStartupScreen ? 10 : 0)
            .animation(.spring(response: 0.58, dampingFraction: 0.86), value: isShowingStartupScreen)
            
            if isShowingStartupScreen {
                StartupScreen(language: appLanguage)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .top).combined(with: .opacity)))
                    .zIndex(1)
            }
            
            if let tierDecayPopup {
                tierDecayPopupView(tierDecayPopup)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.22).ignoresSafeArea())
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
            }
            
            if let achievementPopupItem {
                AchievementPopup(item: achievementPopupItem, language: appLanguage)
                    .padding(.horizontal, 18)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    .zIndex(2)
            }
        }
        .task {
            await runStartupWorkAfterFirstRender()
        }
        .sheet(item: $gameCenterAuthPresentation) { presentation in
            GameCenterAuthView(viewController: presentation.viewController)
        }
        .sheet(item: $selectedOnlineGlobePlayer) { player in
            onlineGlobeSheet(for: player)
        }
        .sheet(item: $selectedMenuInfoScreen) { screen in
            menuInfoSheet(for: screen)
        }
        .sheet(isPresented: $isShowingFriendList) {
            friendListSheet
        }
        .alert(L("Statistik zurücksetzen?", "Reset statistics?"), isPresented: $isShowingResetConfirmation) {
            Button(L("Abbrechen", "Cancel"), role: .cancel) {}
            Button(L("Zurücksetzen", "Reset"), role: .destructive) {
                Haptics.notify(.warning)
                resetAllLocalData()
            }
        } message: {
            Text(L("Möchtest du wirklich deine komplette Statistik zurücksetzen? Dadurch wird dein gesamter Fortschritt gelöscht.", "Do you really want to reset your complete statistics? This will delete all of your progress."))
        }
        .alert(L("Showmaster abbrechen?", "Cancel Showmaster?"), isPresented: $isShowingShowCancelConfirmation) {
            Button(L("Weiter", "Continue"), role: .cancel) {}
            Button(L("Abbrechen", "Cancel"), role: .destructive) {
                Haptics.notify(.warning)
                resetShowSession()
            }
        } message: {
            Text(L("Möchtest du diese Showmaster-Runde wirklich abbrechen?", "Do you really want to cancel this Showmaster round?"))
        }
        .tint(tealAccentColor)
        .preferredColorScheme(appTheme.colorScheme)
        .onChange(of: selectedSubject) { _, _ in
            practiceSessionActive = false
            showSessionActive = false
            showSessionCount = 0
            showSessionEntries = []
            showHistoryPreview = nil
            showRecentCountryCodes = []
            showDeckCountryCodes = []
            showRecap = false
            statisticsSearchText = ""
            cardIsFlipped = false
            resetCurrentCardHint()
            currentCountry = nextRandomCountry(excluding: currentCountry)
        }
        .onChange(of: includePartiallyRecognizedFlags) { _, _ in
            practiceSessionActive = false
            showSessionActive = false
            showRecap = false
            showSessionCount = 0
            showSessionEntries = []
            showHistoryPreview = nil
            showRecentCountryCodes = []
            showDeckCountryCodes = []
            statisticsSearchText = ""
            cardIsFlipped = false
            resetCurrentCardHint()
            currentCountry = nextRandomCountry(excluding: currentCountry)
        }
        .onChange(of: onlineFeaturesEnabled) { _, isEnabled in
            if isEnabled {
                onlineStatusText = L("Online-Rangliste noch nicht geladen", "Online leaderboard not loaded yet")
                gameCenterStatusText = L("Game Center noch nicht verbunden", "Game Center not connected")
                authenticateGameCenter(syncAfterAuthentication: true)
            } else {
                disableOnlineRuntimeState()
            }
        }
        .onChange(of: storeKit.purchasedFullVersion) { _, isUnlocked in
            fullVersionUnlocked = isUnlocked
        }
        .onChange(of: fullVersionUnlocked) { _, isUnlocked in
            if !isUnlocked {
                appAccentRawValue = AppAccent.teal.rawValue
                selectedPracticeContinents = [CountryScope.worldwide]
                selectedShowContinents = [CountryScope.worldwide]
                selectedStatisticsContinents = [CountryScope.worldwide]
                selectedStatisticsTier = nil
                expandedStatisticsCountryCodes = []
                statisticsSearchText = ""
            }
        }
    }
    
    var activeProfile: UserProfile {
        appData.activeProfile ?? UserProfile(id: UUID(), name: "Training", pin: "")
    }
    
    var appLanguage: AppLanguage {
        AppLanguage(rawValue: appLanguageRawValue) ?? .german
    }
    
    var appTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .system
    }
    
    var appAccent: AppAccent {
        AppAccent(rawValue: appAccentRawValue) ?? .teal
    }
    
    func L(_ german: String, _ english: String) -> String {
        localized(german, english, language: appLanguage)
    }
    
    func localizedScope(_ scope: String) -> String {
        if scope == CountryScope.worldwide {
            return L("Alle Länder", "All countries")
        }
        
        switch scope {
        case "Afrika": return L("Afrika", "Africa")
        case "Asien": return L("Asien", "Asia")
        case "Europa": return L("Europa", "Europe")
        case "Nordamerika": return L("Nordamerika", "North America")
        case "Ozeanien": return L("Ozeanien", "Oceania")
        case "Südamerika": return L("Südamerika", "South America")
        case partiallyRecognizedCategory: return L("Teilweise anerkannt", "Partly recognized")
        default: return scope
        }
    }
    
    func scopeTitleWithCount(_ scope: String) -> String {
        "\(localizedScope(scope)) (\(countries(inContinent: scope).count))"
    }
    
    var continents: [String] {
        Array(Set(allCountries.map { $0.continent })).sorted()
    }
    
    var continentOptions: [String] {
        [CountryScope.worldwide] + continents
    }
    
    var appBackgroundColor: Color {
        if selectedSubject == .capitals {
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.05, green: 0.11, blue: 0.13, alpha: 1)
                    : UIColor(red: 0.91, green: 0.97, blue: 0.96, alpha: 1)
            })
        }
        return Color(.systemGroupedBackground)
    }
    
    var appBackgroundGradient: LinearGradient {
        let colors: [Color]
        if selectedSubject == .capitals {
            colors = [
                adaptiveColor(light: UIColor(red: 0.53, green: 0.94, blue: 0.78, alpha: 1), dark: UIColor(red: 0.01, green: 0.15, blue: 0.16, alpha: 1)),
                adaptiveColor(light: UIColor(red: 0.93, green: 1.00, blue: 0.74, alpha: 1), dark: UIColor(red: 0.05, green: 0.24, blue: 0.22, alpha: 1)),
                adaptiveColor(light: UIColor(red: 0.52, green: 0.72, blue: 1.00, alpha: 1), dark: UIColor(red: 0.04, green: 0.08, blue: 0.28, alpha: 1))
            ]
        } else {
            colors = [
                adaptiveColor(light: UIColor(red: 0.55, green: 0.83, blue: 1.00, alpha: 1), dark: UIColor(red: 0.02, green: 0.07, blue: 0.24, alpha: 1)),
                adaptiveColor(light: UIColor(red: 1.00, green: 0.74, blue: 0.45, alpha: 1), dark: UIColor(red: 0.24, green: 0.12, blue: 0.03, alpha: 1)),
                adaptiveColor(light: UIColor(red: 0.48, green: 0.91, blue: 0.70, alpha: 1), dark: UIColor(red: 0.02, green: 0.20, blue: 0.16, alpha: 1))
            ]
        }
        
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    
    func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }
    
    var panelBackgroundColor: Color {
        if selectedSubject == .capitals {
            return Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark
                    ? UIColor(red: 0.08, green: 0.20, blue: 0.22, alpha: 0.96)
                    : UIColor(red: 0.95, green: 1.0, blue: 0.96, alpha: 0.94)
            })
        }
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 0.96)
                : UIColor(red: 1.0, green: 0.98, blue: 0.93, alpha: 0.94)
        })
    }
    
    var tealAccentColor: Color {
        let accent = appAccent
        return Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? accent.darkUIColor
                : accent.lightUIColor
        })
    }
    
    var cardLimitOptions: [Int] {
        [0, 10, 20, 50, 100]
    }
    
    var practiceLimitReached: Bool {
        selectedPracticeCardLimit > 0 && practiceSessionCount >= selectedPracticeCardLimit
    }
    
    var showLimitReached: Bool {
        selectedShowCardLimit > 0 && showSessionCount >= selectedShowCardLimit
    }
    
    var statisticsCountries: [Country] {
        countries(inContinents: selectedStatisticsContinents)
    }
    
    var isAllCountriesStatisticsScope: Bool {
        selectedStatisticsContinents.isEmpty || selectedStatisticsContinents.contains(CountryScope.worldwide)
    }
    
    var duePracticeCountries: [Country] {
        countries(inContinents: selectedPracticeContinents)
    }
    
    func countryName(for country: Country) -> String {
        localizedCountryName(country, language: appLanguage)
    }
    
    func capitalName(for country: Country) -> String {
        capitalByCountryCode[country.code] ?? countryName(for: country)
    }
    
    func stats(for country: Country) -> CountryStats {
        activeProfile.stats(for: country, subject: selectedSubject)
    }
    
    func tier(for country: Country) -> MasteryTier {
        activeProfile.tier(for: country, subject: selectedSubject)
    }
    
    var filteredStatisticsCountries: [Country] {
        let scopedCountries = countries(inContinents: selectedStatisticsContinents)
        let trimmedSearch = statisticsSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return scopedCountries }
        
        return scopedCountries.filter {
            countryName(for: $0).localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.name.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.continent.localizedCaseInsensitiveContains(trimmedSearch) ||
            $0.code.localizedCaseInsensitiveContains(trimmedSearch) ||
            localizedScope($0.continent).localizedCaseInsensitiveContains(trimmedSearch) ||
            capitalName(for: $0).localizedCaseInsensitiveContains(trimmedSearch)
        }
    }
    
    var hasStatisticsSearch: Bool {
        !statisticsSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    func masteryScore(in countries: [Country]) -> Double {
        guard !countries.isEmpty else { return 0 }
        let total = countries.reduce(0) { partialResult, country in
            partialResult + tierScoreValue(for: stats(for: country).tier)
        }
        return total / Double(countries.count)
    }
    
    func tierScoreValue(for tier: MasteryTier) -> Double {
        switch tier {
        case .f: return 0.0
        case .d: return 0.2
        case .c: return 0.4
        case .b: return 0.6
        case .a: return 0.8
        case .s: return 1.0
        }
    }
    
    func tierScoreRows(in countries: [Country]) -> [TierScoreRow] {
        MasteryTier.allCases.map { tier in
            let count = countries.filter { stats(for: $0).tier == tier }.count
            return TierScoreRow(tier: tier, count: count, value: tierScoreValue(for: tier))
        }
    }
    
    func scopeScoreRows(in countries: [Country]) -> [ScopeScoreRow] {
        let visibleContinents = continents.filter { continent in
            countries.contains { $0.continent == continent }
        }
        return visibleContinents.map { continent in
            let continentCountries = countries.filter { $0.continent == continent }
            return ScopeScoreRow(
                title: localizedScope(continent),
                score: masteryScore(in: continentCountries),
                practiced: totalCardReviews(in: continentCountries),
                total: continentCountries.count
            )
        }
        .sorted { $0.score > $1.score }
    }
    
    func practiceBalanceRows(in countries: [Country]) -> [PracticeBalanceRow] {
        [
            PracticeBalanceRow(title: L("Gewusst", "Known"), count: totalCardKnown(in: countries), color: .green),
            PracticeBalanceRow(title: L("Nicht gewusst", "Not known"), count: totalCardUnknown(in: countries), color: .red),
            PracticeBalanceRow(title: L("Showmaster", "Showmaster"), count: totalShowmasterPlayed(in: countries), color: tealAccentColor)
        ]
    }
    
    func flaggenbossPoints(in countries: [Country], days: Int = 30) -> [ScoreHistoryPoint] {
        guard !countries.isEmpty else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dailyPoints = (0..<days).reversed().compactMap { offset -> ScoreHistoryPoint? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: day) ?? day
            let total = countries.reduce(0.0) { partialResult, country in
                let countryStats = stats(for: country)
                return partialResult + tierScoreValue(for: tier(for: countryStats, at: endOfDay))
            }
            return ScoreHistoryPoint(date: day, score: total / Double(countries.count))
        }
        
        var changePoints: [ScoreHistoryPoint] = []
        var previousScore: Double?
        for point in dailyPoints {
            if previousScore == nil || abs((previousScore ?? 0) - point.score) > 0.0001 {
                changePoints.append(point)
                previousScore = point.score
            }
        }
        return changePoints.filter { $0.score > 0 || changePoints.count == 1 }
    }
    
    func tier(for stats: CountryStats, at date: Date) -> MasteryTier {
        guard let history = stats.tierHistory, !history.isEmpty else {
            return (stats.lastPracticedAt ?? .distantPast) <= date ? stats.tier : .f
        }
        return history
            .filter { $0.date <= date }
            .sorted { $0.date < $1.date }
            .last?
            .tier ?? .f
    }
    
    var friendNames: [String] {
        friendNamesRawValue
            .split(separator: "|")
            .map { String($0) }
            .filter { !$0.isEmpty }
    }
    
    var deduplicatedOnlineLeaderboard: [OnlinePlayerStats] {
        var playersByKey: [String: OnlinePlayerStats] = [:]
        let newestFirst = onlineLeaderboard.sorted { $0.updatedAt > $1.updatedAt }
        
        for player in newestFirst {
            let key = onlineDeduplicationKey(for: player)
            if let existingPlayer = playersByKey[key] {
                playersByKey[key] = preferredOnlinePlayer(existingPlayer, player)
            } else {
                playersByKey[key] = player
            }
        }
        
        return playersByKey.values.sorted {
            if $0.totalPracticed == $1.totalPracticed {
                return $0.accuracy > $1.accuracy
            }
            return $0.totalPracticed > $1.totalPracticed
        }
    }
    
    var friendLeaderboard: [OnlinePlayerStats] {
        let normalizedFriends = Set(friendNames.map { normalizedFriendToken($0) })
        return deduplicatedOnlineLeaderboard.filter { player in
            gameCenterFriendIDs.contains(player.gameCenterPlayerID) ||
            normalizedFriends.contains(normalizedFriendToken(player.playerName)) ||
            normalizedFriends.contains(normalizedFriendToken(player.gameCenterAlias)) ||
            normalizedFriends.contains(normalizedFriendToken(player.friendCode))
        }
    }
    
    var scopedOnlineLeaderboard: [OnlinePlayerStats] {
        selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
    }
    
    var scopedLearnedThisWeekLeaderboard: [OnlinePlayerStats] {
        let source = selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
        return source.sorted {
            if $0.learnedThisWeek == $1.learnedThisWeek {
                return $0.accuracy > $1.accuracy
            }
            return $0.learnedThisWeek > $1.learnedThisWeek
        }
    }
    
    var scopedAchievementLeaderboard: [OnlinePlayerStats] {
        let source = selectedOnlineScope == .friends ? friendLeaderboard : deduplicatedOnlineLeaderboard
        return source.sorted {
            if $0.achievementCount == $1.achievementCount {
                return $0.totalPracticed > $1.totalPracticed
            }
            return $0.achievementCount > $1.achievementCount
        }
    }
    
    var learnedThisWeekLeaderboard: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard.sorted {
            if $0.learnedThisWeek == $1.learnedThisWeek {
                return $0.accuracy > $1.accuracy
            }
            return $0.learnedThisWeek > $1.learnedThisWeek
        }
    }
    
    var achievementLeaderboard: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard.sorted {
            if $0.achievementCount == $1.achievementCount {
                return $0.totalPracticed > $1.totalPracticed
            }
            return $0.achievementCount > $1.achievementCount
        }
    }
    
    func onlineDeduplicationKey(for player: OnlinePlayerStats) -> String {
        if isCurrentOnlinePlayer(player) {
            return "current"
        }
        
        if !player.gameCenterPlayerID.isEmpty {
            return "gc:\(player.gameCenterPlayerID)"
        }
        
        let displayNameToken = normalizedFriendToken(player.displayName)
        if !displayNameToken.isEmpty && displayNameToken != "spieler" && displayNameToken != "player" {
            return "name:\(displayNameToken)"
        }
        
        return "id:\(player.id)"
    }
    
    func preferredOnlinePlayer(_ first: OnlinePlayerStats, _ second: OnlinePlayerStats) -> OnlinePlayerStats {
        if isCurrentOnlinePlayer(first) != isCurrentOnlinePlayer(second) {
            return isCurrentOnlinePlayer(first) ? first : second
        }
        
        if first.gameCenterPlayerID.isEmpty != second.gameCenterPlayerID.isEmpty {
            return first.gameCenterPlayerID.isEmpty ? second : first
        }
        
        if first.updatedAt != second.updatedAt {
            return first.updatedAt > second.updatedAt ? first : second
        }
        
        return first.totalPracticed >= second.totalPracticed ? first : second
    }
    
    var currentLearningStreak: Int {
        guard let lastDate = activeProfile.lastLearningStreakDate else { return 0 }
        let calendar = Calendar.current
        if calendar.isDateInToday(lastDate) {
            return activeProfile.learningStreak ?? 0
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: Date()), calendar.isDate(lastDate, inSameDayAs: yesterday) {
            return activeProfile.learningStreak ?? 0
        }
        return 0
    }
    
    var subjectName: String {
        selectedSubject == .capitals ? L("Hauptstädte", "capitals") : L("Flaggen", "flags")
    }
    
    var practiceAchievementItems: [AchievementItem] {
        let countries = availableCountries
        let total = max(countries.count, 1)
        let seen = totalSeenFlags(in: countries)
        let knownOnce = totalKnownAtLeastOnceFlags(in: countries)
        let reviewed = totalCardReviews(in: countries)
        let sTierCount = countries.filter { stats(for: $0).tier == .s }.count
        let aOrBetterCount = countries.filter { [.s, .a].contains(stats(for: $0).tier) }.count
        let bestLearningStreak = max(activeProfile.bestLearningStreak ?? 0, currentLearningStreak)
        let allSHeldDays = allSTierHeldDays(in: countries)
        
        return [
            AchievementItem(
                id: "first-card",
                title: L("Erste Karte", "First card"),
                description: L("Eine \(subjectName)-Karte gelernt", "Study one \(subjectName) card"),
                iconName: "sparkle.magnifyingglass",
                currentValue: seen,
                targetValue: 1,
                tint: tealAccentColor
            ),
            AchievementItem(
                id: "ten-known",
                title: L("Zehn sicher", "Ten known"),
                description: L("10 verschiedene \(subjectName) mindestens einmal gewusst", "Know 10 different \(subjectName) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: knownOnce,
                targetValue: 10,
                tint: .green
            ),
            AchievementItem(
                id: "fifty-known",
                title: L("50 sicher", "50 known"),
                description: L("50 verschiedene \(subjectName) mindestens einmal gewusst", "Know 50 different \(subjectName) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: knownOnce,
                targetValue: 50,
                tint: .green
            ),
            AchievementItem(
                id: "all-known-once",
                title: L("Einmal alles gekonnt", "Known all once"),
                description: L("Alle verfügbaren \(subjectName) mindestens einmal gewusst", "Know every available \(subjectName) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: knownOnce,
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "perfect-full-session",
                title: L("Perfekte Session", "Perfect session"),
                description: selectedSubject == .capitals
                    ? L("In einer Session alle Hauptstädte als gewusst geloggt", "Log every capital as known in one session")
                    : L("In einer Session alle Flaggen als gewusst geloggt", "Log every flag as known in one session"),
                iconName: "checkmark.circle.badge.star",
                currentValue: activeProfile.hasPerfectFullPracticeSession(subject: selectedSubject) ? 1 : 0,
                targetValue: 1,
                tint: .green
            ),
            AchievementItem(
                id: "fifty-reviews",
                title: L("Dranbleiben", "Keep going"),
                description: L("50 Karten im Üben-Modus bearbeitet", "Review 50 cards in practice mode"),
                iconName: "rectangle.stack.badge.play.fill",
                currentValue: reviewed,
                targetValue: 50,
                tint: .orange
            ),
            AchievementItem(
                id: "two-hundred-fifty-reviews",
                title: L("Routine", "Routine"),
                description: L("250 Karten im Üben-Modus bearbeitet", "Review 250 cards in practice mode"),
                iconName: "rectangle.stack.badge.play.fill",
                currentValue: reviewed,
                targetValue: 250,
                tint: .orange
            ),
            AchievementItem(
                id: "thousand-reviews",
                title: L("Trainingsmaschine", "Training machine"),
                description: L("1000 Karten im Üben-Modus bearbeitet", "Review 1000 cards in practice mode"),
                iconName: "rectangle.stack.badge.play.fill",
                currentValue: reviewed,
                targetValue: 1000,
                tint: .orange
            ),
            AchievementItem(
                id: "daily-500-practice",
                title: L("500 an einem Tag", "500 in one day"),
                description: selectedSubject == .capitals ? L("Über 500 Hauptstädte an einem Tag im Üben-Modus gelernt", "Study more than 500 capitals in one day in practice mode") : L("Über 500 Flaggen an einem Tag im Üben-Modus gelernt", "Study more than 500 flags in one day in practice mode"),
                iconName: "calendar.badge.clock",
                currentValue: activeProfile.maxPracticeCardsInOneDay(subject: selectedSubject),
                targetValue: 501,
                tint: .orange
            ),
            AchievementItem(
                id: "three-day-streak",
                title: L("Drei-Tage-Serie", "Three-day streak"),
                description: L("An 3 Tagen in Folge einen 10er-Block abgeschlossen", "Complete a block of 10 on 3 days in a row"),
                iconName: "flame.fill",
                currentValue: bestLearningStreak,
                targetValue: 3,
                tint: .red
            ),
            AchievementItem(
                id: "seven-day-streak",
                title: L("Wochenserie", "Weekly streak"),
                description: L("An 7 Tagen in Folge einen 10er-Block abgeschlossen", "Complete a block of 10 on 7 days in a row"),
                iconName: "flame.fill",
                currentValue: bestLearningStreak,
                targetValue: 7,
                tint: .red
            ),
            AchievementItem(
                id: "a-tier-five",
                title: L("A-Team", "A team"),
                description: L("5 Länder auf Stufe A oder S bringen", "Bring 5 countries to level A or S"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount,
                targetValue: 5,
                tint: .green
            ),
            AchievementItem(
                id: "a-tier-half",
                title: L("Halbes A-Feld", "Half A field"),
                description: L("Die Hälfte aller verfügbaren Länder mindestens auf Stufe A bringen", "Bring half of all available countries to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount,
                targetValue: max((total + 1) / 2, 1),
                tint: .green
            ),
            AchievementItem(
                id: "all-a-tier",
                title: L("Alle auf A", "All on A"),
                description: L("Alle verfügbaren Länder mindestens auf Stufe A bringen", "Bring every available country to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount,
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "first-s-tier",
                title: L("S-Stufe", "S level"),
                description: L("Ein Land auf Stufe S bringen", "Bring one country to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount,
                targetValue: 1,
                tint: .blue
            ),
            AchievementItem(
                id: "s-tier-twenty-five",
                title: L("S-Block", "S block"),
                description: L("25 Länder auf Stufe S bringen", "Bring 25 countries to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount,
                targetValue: 25,
                tint: .blue
            ),
            AchievementItem(
                id: "all-s-tier",
                title: L("Alle auf S", "All on S"),
                description: L("Alle verfügbaren Länder auf Stufe S bringen", "Bring every available country to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount,
                targetValue: total,
                tint: .blue
            ),
            AchievementItem(
                id: "all-s-two-weeks",
                title: L("S zwei Wochen gehalten", "Held S for two weeks"),
                description: L("Alle verfügbaren Karten 14 Tage lang auf Stufe S halten", "Keep every available card on level S for 14 days"),
                iconName: "calendar.badge.checkmark",
                currentValue: allSHeldDays,
                targetValue: 14,
                tint: .blue
            ),
            AchievementItem(
                id: "all-seen",
                title: L("Alles gesehen", "Seen everything"),
                description: L("Alle verfügbaren Länder einmal gesehen", "See every available country once"),
                iconName: "globe.europe.africa.fill",
                currentValue: seen,
                targetValue: total,
                tint: .purple
            )
        ]
    }
    
    var regionAchievementItems: [AchievementItem] {
        let continentItems = continents.flatMap { continent in
            continentAchievementItems(for: continent, countries: allCountries.filter { $0.continent == continent })
        }
        return continentItems + worldCupAchievementItems + partiallyRecognizedAchievementItems
    }
    
    var worldCupAchievementItems: [AchievementItem] {
        let countries = allCountries.filter { worldCupWinnerCountryCodes.contains($0.code) }
        let total = max(countries.count, 1)
        
        return [
            AchievementItem(
                id: "world-cup-heroes-known",
                title: L("WM-Held", "World Cup hero"),
                description: L("Alle Länder, die eine Fußball-WM gewonnen haben, mindestens einmal richtig erkannt", "Correctly recognize every country that has won a FIFA World Cup at least once"),
                iconName: "soccerball",
                currentValue: totalKnownAtLeastOnceFlags(in: countries),
                targetValue: total,
                tint: .orange
            )
        ]
    }
    
    var partiallyRecognizedAchievementItems: [AchievementItem] {
        let countries = partiallyRecognizedCountries
        let total = max(countries.count, 1)
        let groupTitle = L("umkämpfte Gebiete", "contested territories")
        
        return [
            AchievementItem(
                id: "contested-seen",
                title: L("Umkämpfte Gebiete gesehen", "Contested territories seen"),
                description: L("Alle \(groupTitle) einmal gesehen", "See all \(groupTitle) once"),
                iconName: "flag.filled.and.flag.crossed",
                currentValue: totalSeenFlags(in: countries),
                targetValue: total,
                tint: .indigo
            ),
            AchievementItem(
                id: "contested-known",
                title: L("Umkämpfte Gebiete sicher", "Contested territories known"),
                description: L("Alle \(groupTitle) mindestens einmal gewusst", "Know all \(groupTitle) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: totalKnownAtLeastOnceFlags(in: countries),
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "contested-a-tier",
                title: L("Diplomaten-A", "Diplomat A"),
                description: L("Alle \(groupTitle) mindestens auf Stufe A bringen", "Bring all \(groupTitle) to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount(in: countries),
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "contested-s-tier",
                title: L("Diplomaten-S", "Diplomat S"),
                description: L("Alle \(groupTitle) auf Stufe S bringen", "Bring all \(groupTitle) to level S"),
                iconName: "s.circle.fill",
                currentValue: sTierCount(in: countries),
                targetValue: total,
                tint: .blue
            )
        ]
    }
    
    func continentAchievementItems(for continent: String, countries: [Country]) -> [AchievementItem] {
        let total = max(countries.count, 1)
        let name = localizedScope(continent)
        let idPrefix = continent
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        
        return [
            AchievementItem(
                id: "\(idPrefix)-seen",
                title: L("\(name) gesehen", "\(name) seen"),
                description: L("Alle \(subjectName) aus \(name) einmal gesehen", "See every \(subjectName) from \(name) once"),
                iconName: "globe.europe.africa.fill",
                currentValue: totalSeenFlags(in: countries),
                targetValue: total,
                tint: .purple
            ),
            AchievementItem(
                id: "\(idPrefix)-known",
                title: L("\(name) sicher", "\(name) known"),
                description: L("Alle \(subjectName) aus \(name) mindestens einmal gewusst", "Know every \(subjectName) from \(name) at least once"),
                iconName: "checkmark.seal.fill",
                currentValue: totalKnownAtLeastOnceFlags(in: countries),
                targetValue: total,
                tint: .green
            ),
            AchievementItem(
                id: "\(idPrefix)-a-tier",
                title: "\(name) A",
                description: L("Alle Länder aus \(name) mindestens auf Stufe A bringen", "Bring every country from \(name) to at least level A"),
                iconName: "a.circle.fill",
                currentValue: aOrBetterCount(in: countries),
                targetValue: total,
                tint: .green
            )
        ]
    }
    
    var showmasterAchievementItems: [AchievementItem] {
        let countries = availableCountries
        let showmasterPlayed = totalShowmasterPlayed(in: countries)
        let showmasterCountries = countries.filter { stats(for: $0).showmasterPlayed > 0 }.count
        
        return [
            AchievementItem(
                id: "showmaster-ten",
                title: "Showmaster 10",
                description: L("10 Karten im Showmaster gespielt", "Play 10 cards in Showmaster"),
                iconName: "rectangle.on.rectangle.angled",
                currentValue: showmasterPlayed,
                targetValue: 10,
                tint: tealAccentColor
            ),
            AchievementItem(
                id: "showmaster-hundred",
                title: "Showmaster 100",
                description: L("100 Karten im Showmaster gespielt", "Play 100 cards in Showmaster"),
                iconName: "sparkles.rectangle.stack.fill",
                currentValue: showmasterPlayed,
                targetValue: 100,
                tint: tealAccentColor
            ),
            AchievementItem(
                id: "showmaster-all-seen",
                title: L("Showmaster-Rundblick", "Showmaster overview"),
                description: L("Jedes verfügbare Land mindestens einmal im Showmaster gespielt", "Play every available country at least once in Showmaster"),
                iconName: "eye.fill",
                currentValue: showmasterCountries,
                targetValue: max(countries.count, 1),
                tint: .purple
            )
        ]
    }
    
    var achievementItems: [AchievementItem] {
        practiceAchievementItems + regionAchievementItems + showmasterAchievementItems
    }
    
    var unlockedAchievementCount: Int {
        achievementItems.filter(\.isUnlocked).count
    }
    
    var activeAchievementIDs: Set<String> {
        Set(achievementItems.filter(\.isUnlocked).map(\.id))
    }
    
    var globalAchievementPlayerCount: Int {
        max(deduplicatedOnlineLeaderboard.count, activeAchievementIDs.isEmpty ? 0 : 1)
    }
    
    func globalUnlockCount(for achievementID: String) -> Int {
        var count = deduplicatedOnlineLeaderboard.filter { $0.achievementIDs.contains(achievementID) }.count
        if activeAchievementIDs.contains(achievementID) && !deduplicatedOnlineLeaderboard.contains(where: { isCurrentOnlinePlayer($0) }) {
            count += 1
        }
        return count
    }
    
    func achievementsSortedByGlobalUnlocks(_ items: [AchievementItem]) -> [AchievementItem] {
        items.sorted {
            let firstCount = globalUnlockCount(for: $0.id)
            let secondCount = globalUnlockCount(for: $1.id)
            if firstCount == secondCount {
                if $0.isUnlocked == $1.isUnlocked {
                    return $0.title < $1.title
                }
                return $0.isUnlocked && !$1.isUnlocked
            }
            return firstCount < secondCount
        }
    }
    
    func achievementsSortedByDate(_ items: [AchievementItem]) -> [AchievementItem] {
        items.sorted {
            let firstDate = achievedDate(for: $0)
            let secondDate = achievedDate(for: $1)
            switch (firstDate, secondDate) {
            case let (first?, second?):
                if first == second { return $0.title < $1.title }
                return first > second
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                if $0.isUnlocked == $1.isUnlocked {
                    return $0.progress > $1.progress
                }
                return $0.isUnlocked && !$1.isUnlocked
            }
        }
    }
    
    func achievedDate(for item: AchievementItem) -> Date? {
        activeProfile.achievedAchievementDates?[achievementAnnouncementID(for: item)]
    }
    
    func achievementDateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: appLanguage == .german ? "de_DE" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var decayPopupIsPresented: Binding<Bool> {
        Binding(
            get: { tierDecayPopup != nil },
            set: { isPresented in
                if !isPresented {
                    tierDecayPopup = nil
                }
            }
        )
    }
    
    var decayPopupTitle: String {
        L("Stufen angepasst", "Levels adjusted")
    }
    
    var decayPopupMessage: String {
        guard let tierDecayPopup else { return "" }
        let dayText = tierDecayPopup.maxDaysSinceLastPractice == 1 ? L("Tag", "day") : L("Tagen", "days")
        let intro = L("Zuletzt gelernt vor \(tierDecayPopup.maxDaysSinceLastPractice) \(dayText).", "Last practiced \(tierDecayPopup.maxDaysSinceLastPractice) \(dayText) ago.")
        let lines = tierDecayPopup.groupedChanges.map { group in
            L("\(group.count) von \(group.from.rawValue) auf \(group.to.rawValue)", "\(group.count) from \(group.from.rawValue) to \(group.to.rawValue)")
        }
        .joined(separator: "\n")
        
        return "\(intro)\n\(lines)"
    }
    
    var startView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 18)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 76, weight: .regular))
                            .foregroundStyle(tealAccentColor.opacity(0.42))
                            .padding(.bottom, 2)
                        
                        Text("Flaggenbande")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        
                        Label(L("Streak: \(currentLearningStreak) Tage", "Streak: \(currentLearningStreak) days"), systemImage: "flame.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(currentLearningStreak > 0 ? .orange : .secondary)
                    }
                    
                    subjectModePickerCard()
                    
                    VStack(spacing: 12) {
                        ForEach(AppScreen.allCases, id: \.self) { screen in
                            HStack(spacing: 10) {
                                NavigationLink(value: screen) {
                                    HStack(spacing: 14) {
                                        Image(systemName: screen.iconName)
                                            .font(.title3)
                                            .frame(width: 28)
                                        Text(screen.title(language: appLanguage))
                                            .font(.title3.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.82)
                                        Spacer()
                                        if screen == .globe && !fullVersionUnlocked {
                                            Image(systemName: "lock.fill")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.headline)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.leading, 14)
                                    .contentShape(Rectangle())
                                }
                                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                                .buttonStyle(.plain)
                                
                                Button {
                                    Haptics.tap()
                                    selectedMenuInfoScreen = screen
                                } label: {
                                    Image(systemName: "info.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(tealAccentColor)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L("Info zu \(screen.title(language: appLanguage))", "Info about \(screen.title(language: appLanguage))"))
                            }
                            .padding(.trailing, 6)
                            .frame(maxWidth: .infinity)
                            .background(panelBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    
                    NavigationLink(value: AppScreen.options) {
                        Label(
                            fullVersionUnlocked ? L("Du hast die Vollversion, Dankeschön!", "You have the full version, thank you!") : L("Vollversion freischalten", "Unlock full version"),
                            systemImage: fullVersionUnlocked ? "checkmark.seal.fill" : "lock.open.fill"
                        )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fullVersionUnlocked ? tealAccentColor : .pink)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(panelBackgroundColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    .buttonStyle(.plain)
                    
                    Spacer(minLength: 18)
                }
                .padding()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            
            if let leagueSummaryResult {
                leagueSummaryOverlay(leagueSummaryResult)
                    .padding(.horizontal, 18)
                    .frame(maxWidth: 620)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.24).ignoresSafeArea())
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(3)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }
    
    func menuInfoSheet(for screen: AppScreen) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: screen.iconName)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(tealAccentColor)
                    .frame(width: 72, height: 72)
                    .background(tealAccentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                
                Text(screen.title(language: appLanguage))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                
                Text(screen.infoText(language: appLanguage))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(appBackgroundGradient.ignoresSafeArea())
            .navigationTitle(L("Info", "Info"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        selectedMenuInfoScreen = nil
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    var practiceView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                modeHeader(title: L("Üben", "Practice"), subtitle: "")
                if !practiceSessionActive {
                    subjectModePickerCard()
                }
                if practiceSessionActive {
                    Spacer(minLength: 42)
                }
                
                if practiceSessionActive {
                    PracticeHistoryBar(
                        results: practiceSessionResults,
                        changes: practiceSessionChanges,
                        limit: selectedPracticeCardLimit,
                        accentColor: tealAccentColor,
                        selectedChangeID: practiceHistoryPreview?.id,
                        onSelectChange: showPracticeHistoryPreview
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: PracticeHistoryBarMinYKey.self, value: proxy.frame(in: .named("practicePreviewSpace")).minY)
                        }
                    )
                    
                    VStack(spacing: 8) {
                        practiceSwipeCard
                        Text(L("Wischen!", "Swipe!"))
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap()
                            undoLastPracticeSwipe()
                        } label: {
                            Label(L("Rückgängig", "Undo"), systemImage: "arrow.uturn.backward")
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                        .disabled(practiceUndoSnapshot == nil)
                        
                        Button {
                            Haptics.tap()
                            finishPracticeSession(showSummary: practiceSessionCount > 0)
                        } label: {
                            Text(L("Session abbrechen", "Cancel session"))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    }
                    
                    hintControl
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Kategorie", "Category"))
                            .font(.headline)
                        continentButtonGrid(selection: $selectedPracticeContinents)
                    }
                    
                    if showRecap {
                        PracticeRecapView(
                            startCounts: recapStartCounts,
                            endCounts: recapEndCounts,
                            known: practiceSessionKnown,
                            unknown: practiceSessionUnknown,
                            improved: practiceSessionImproved,
                            changes: practiceSessionChanges,
                            language: appLanguage,
                            accentColor: tealAccentColor,
                            onRepeat: {
                                Haptics.tap()
                                startPracticeSession()
                            },
                            onDismiss: {
                                Haptics.tap()
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                    showRecap = false
                                }
                            }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    
                    if !showRecap {
                        Spacer(minLength: 18)
                        
                        Button {
                            Haptics.tap()
                            startPracticeSession()
                        } label: {
                            Text(L("Starten", "Start"))
                                .font(.title3.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                        .padding(.top, 12)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        
                        practiceInfoTile
                    }
                }
            }
            .padding()
        }
            if let practiceHistoryPreview {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissPracticeHistoryPreview()
                    }
                    .zIndex(1)
                
                practiceHistoryPreviewBubble(for: practiceHistoryPreview)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, practiceHistoryBarMinY + 38)
                    .transition(.scale(scale: 0.25, anchor: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .coordinateSpace(name: "practicePreviewSpace")
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: practiceSessionActive)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: showRecap)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: practiceHistoryPreview?.id)
        .onPreferenceChange(PracticeHistoryBarMinYKey.self) { value in
            if value > 0 {
                practiceHistoryBarMinY = value
            }
        }
        .onChange(of: selectedPracticeContinents) { _, _ in
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                practiceSessionActive = false
                practiceHistoryPreview = nil
            }
        }
    }
    
    func practiceHistoryPreviewBubble(for preview: PracticeHistoryPreview) -> some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let horizontalMargin: CGFloat = 12
            let outerPadding: CGFloat = 16
            let barInnerPadding: CGFloat = 10
            let pillWidth: CGFloat = 28
            let pillSpacing: CGFloat = 7
            let bubbleWidth = min(max(screenWidth - horizontalMargin * 2, 260), 360)
            let contentMaxWidth = min(screenWidth - outerPadding * 2, 520)
            let contentStart = (screenWidth - contentMaxWidth) / 2
            let barContentWidth = max(contentMaxWidth - barInnerPadding * 2, 1)
            let entriesWidth = CGFloat(preview.total) * pillWidth + CGFloat(max(preview.total - 1, 0)) * pillSpacing
            let entriesStart = contentStart + barInnerPadding + max((barContentWidth - entriesWidth) / 2, 0)
            let selectedCenterX = entriesStart + CGFloat(preview.index) * (pillWidth + pillSpacing) + pillWidth / 2
            let bubbleLeft = min(max(selectedCenterX - bubbleWidth / 2, horizontalMargin), screenWidth - bubbleWidth - horizontalMargin)
            let arrowX = min(max(selectedCenterX - bubbleLeft, 24), bubbleWidth - 24)
            
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: arrowX - 13)
                    Triangle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 26, height: 14)
                        .overlay(
                            Triangle()
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
                .frame(width: bubbleWidth)
                
                practiceHistoryPreview(for: preview.change)
            }
            .frame(width: bubbleWidth)
            .position(x: bubbleLeft + bubbleWidth / 2, y: (selectedSubject == .capitals ? 164 : 146) / 2)
        }
        .frame(height: selectedSubject == .capitals ? 164 : 146)
        .onTapGesture {
            dismissPracticeHistoryPreview()
        }
    }
    
    func practiceHistoryPreview(for change: PracticeSessionChange) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                FlagImage(country: change.country, width: 74, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                    )
                
                MiniLocationGlobe(country: change.country, accentColor: tealAccentColor)
                    .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(countryName(for: change.country))
                        .font(.headline.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                    Text(localizedScope(change.country.continent))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedSubject == .capitals {
                        Text(capitalName(for: change.country))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tealAccentColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                }
                
                Spacer(minLength: 0)
            }
            
            HStack(spacing: 8) {
                Label(change.wasKnown ? L("Gewusst", "Known") : L("Nicht gewusst", "Not known"), systemImage: change.wasKnown ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(change.wasKnown ? .green : .red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background((change.wasKnown ? Color.green : Color.red).opacity(0.12), in: Capsule())
                
                Spacer(minLength: 0)
                
                HStack(spacing: 5) {
                    tierMiniBadge(change.fromTier)
                    Image(systemName: change.wasKnown ? "arrow.up.right" : "arrow.down.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(change.wasKnown ? .green : .red)
                    tierMiniBadge(change.toTier)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(change.wasKnown ? Color.green.opacity(0.32) : Color.red.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            dismissPracticeHistoryPreview()
        }
    }
    
    func tierMiniBadge(_ tier: MasteryTier) -> some View {
        Text(tier.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(tier.color, in: RoundedRectangle(cornerRadius: 6))
    }
    
    func showPracticeHistoryPreview(_ preview: PracticeHistoryPreview) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            practiceHistoryPreview = preview
        }
    }
    
    func dismissPracticeHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            practiceHistoryPreview = nil
        }
    }
    
    func showHistoryPreviewBubble(for preview: ShowHistoryPreview) -> some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let horizontalMargin: CGFloat = 12
            let outerPadding: CGFloat = 16
            let barInnerPadding: CGFloat = 10
            let pillWidth: CGFloat = 28
            let pillSpacing: CGFloat = 7
            let bubbleWidth = min(max(screenWidth - horizontalMargin * 2, 260), 360)
            let contentMaxWidth = min(screenWidth - outerPadding * 2, 520)
            let contentStart = (screenWidth - contentMaxWidth) / 2
            let barContentWidth = max(contentMaxWidth - barInnerPadding * 2, 1)
            let entriesWidth = CGFloat(preview.total) * pillWidth + CGFloat(max(preview.total - 1, 0)) * pillSpacing
            let entriesStart = contentStart + barInnerPadding + max((barContentWidth - entriesWidth) / 2, 0)
            let selectedCenterX = entriesStart + CGFloat(preview.index) * (pillWidth + pillSpacing) + pillWidth / 2
            let bubbleLeft = min(max(selectedCenterX - bubbleWidth / 2, horizontalMargin), screenWidth - bubbleWidth - horizontalMargin)
            let arrowX = min(max(selectedCenterX - bubbleLeft, 24), bubbleWidth - 24)
            
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                        .frame(width: arrowX - 13)
                    Triangle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 26, height: 14)
                        .overlay(
                            Triangle()
                                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                        )
                    Spacer(minLength: 0)
                }
                .frame(width: bubbleWidth)
                
                showHistoryPreviewContent(for: preview.entry.country)
            }
            .frame(width: bubbleWidth)
            .position(x: bubbleLeft + bubbleWidth / 2, y: 73)
        }
        .frame(height: 146)
        .onTapGesture {
            dismissShowmasterHistoryPreview()
        }
    }
    
    func showHistoryPreviewContent(for country: Country) -> some View {
        HStack(alignment: .top, spacing: 12) {
            FlagImage(country: country, width: 74, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )
            
            MiniLocationGlobe(country: country, accentColor: tealAccentColor)
                .frame(width: 50, height: 50)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(countryName(for: country))
                    .font(.headline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text(localizedScope(country.continent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if selectedSubject == .capitals {
                    Text(capitalName(for: country))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tealAccentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                Text("Showmaster")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tealAccentColor)
            }
            
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.32), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            dismissShowmasterHistoryPreview()
        }
    }
    
    func showShowmasterHistoryPreview(_ preview: ShowHistoryPreview) {
        Haptics.tap()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            showHistoryPreview = preview
        }
    }
    
    func dismissShowmasterHistoryPreview() {
        withAnimation(.easeOut(duration: 0.16)) {
            showHistoryPreview = nil
        }
    }
    
    var practiceInfoTile: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(tealAccentColor)
            Text(L("Flaggen und Hauptstädte, die du gut kannst, kommen seltener. Wenn du eine Karte 3 Tage nicht als gewusst loggst, fällt sie eine Stufe runter. Unsichere Karten tauchen häufiger auf, damit du sie schneller lernst.", "Flags and capitals you know well appear less often. If you do not log a card as known for 3 days, it drops one level. Uncertain cards show up more frequently so you learn them faster."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    var practiceSwipeCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(practiceSwipeColor.opacity(practiceSwipeOpacity))
                .frame(height: 260)
                .overlay(alignment: practiceCardDragOffset >= 0 ? .leading : .trailing) {
                    Image(systemName: practiceCardDragOffset >= 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(practiceCardDragOffset >= 0 ? .green : .red)
                        .opacity(practiceSwipeOpacity)
                        .padding(.horizontal, 26)
                }
            
            FlipCard(country: currentCountry, isFlipped: cardIsFlipped, hasGoldAura: tier(for: currentCountry) == .s, language: appLanguage, subject: selectedSubject, capital: capitalName(for: currentCountry))
                .id(currentCountry.id)
                .offset(x: practiceCardDragOffset, y: practiceCardEntryOffset)
                .opacity((isFinishingPracticeSwipe ? 0.82 : 1) * practiceCardEntryOpacity)
                .scaleEffect(practiceCardEntryOpacity < 1 ? 0.985 : 1)
                .rotationEffect(.degrees(max(min(Double(practiceCardDragOffset / 22), 10), -10)))
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(.spring(response: 0.32, dampingFraction: 0.88), value: currentCountry.id)
                .animation(.spring(response: 0.34, dampingFraction: 0.86), value: practiceCardEntryOffset)
                .animation(.easeOut(duration: 0.2), value: practiceCardEntryOpacity)
                .gesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard !isFinishingPracticeSwipe else { return }
                            practiceCardDragOffset = max(min(value.translation.width, 220), -220)
                        }
                        .onEnded { value in
                            finishPracticeSwipe(translation: value.translation, predictedTranslation: value.predictedEndTranslation)
                        }
                )
            
            if hintBlockFeedbackIsVisible {
                Label(L("Mit Tipp nur als nicht gewusst möglich", "With a hint, only not known is possible"), systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.94), in: Capsule())
                    .shadow(color: .orange.opacity(0.28), radius: 12, y: 5)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 12)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            guard !isFinishingPracticeSwipe else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                cardIsFlipped.toggle()
            }
        }
    }
    
    var hintControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                activateHint()
            } label: {
                Label(cardHintIsVisible ? L("Tipp aktiviert", "Hint active") : L("Tipp anzeigen", "Show hint"), systemImage: cardHintIsVisible ? "lightbulb.fill" : "lightbulb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(cardHintIsVisible ? .orange : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemFill).opacity(cardHintIsVisible ? 0.45 : 0.32), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(cardHintIsVisible ? Color.orange.opacity(0.34) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
            
            if cardHintIsVisible {
                VStack(alignment: .leading, spacing: 7) {
                    Text(hintText(for: currentCountry))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(L("Diese Karte kann jetzt nicht mehr als gewusst geloggt werden.", "This card can no longer be logged as known."))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.26), lineWidth: 1)
                )
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: cardHintIsVisible)
    }
    
    var showRandomnessControl: some View {
        Toggle(isOn: $showAvoidsRecentRepeats) {
            VStack(alignment: .leading, spacing: 3) {
                Label(L("Wiederholungen vermeiden", "Avoid repeats"), systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
                Text(showAvoidsRecentRepeats ? L("Alle verfügbaren Karten kommen erst einmal dran, bevor neu gemischt wird.", "Every available card appears once before shuffling again.") : L("Komplett zufällig.", "Completely random."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    var practiceSwipeColor: Color {
        practiceCardDragOffset >= 0 ? .green : .red
    }
    
    var practiceSwipeOpacity: Double {
        min(abs(Double(practiceCardDragOffset)) / 140, 0.35)
    }
    
    var showView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                modeHeader(title: "Showmaster", subtitle: "")
                subjectModePickerCard()
                
                if showSessionActive {
                    Text(showSessionProgressText())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    
                    ShowHistoryBar(
                        entries: showSessionEntries,
                        limit: selectedShowCardLimit,
                        accentColor: tealAccentColor,
                        selectedEntryID: showHistoryPreview?.id,
                        onSelectEntry: showShowmasterHistoryPreview
                    )
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(key: ShowHistoryBarMinYKey.self, value: proxy.frame(in: .named("showPreviewSpace")).minY)
                        }
                    )
                    
                    FlipCard(country: currentCountry, isFlipped: cardIsFlipped, hasGoldAura: tier(for: currentCountry) == .s, language: appLanguage, subject: selectedSubject, capital: capitalName(for: currentCountry))
                        .id(currentCountry.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.easeInOut(duration: 0.22), value: currentCountry.id)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                        .onTapGesture {
                            Haptics.tap()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                cardIsFlipped.toggle()
                            }
                        }
                    Button {
                        Haptics.tap()
                        nextShowCard()
                    } label: {
                        Text(L("Nächste Flagge", "Next flag"))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    .disabled(showLimitReached)
                    
                    Button {
                        Haptics.tap()
                        isShowingShowCancelConfirmation = true
                    } label: {
                        Text(L("Abbrechen", "Cancel"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    
                    hintControl
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Kategorie", "Category"))
                            .font(.headline)
                        continentButtonGrid(selection: $selectedShowContinents)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Karten", "Cards"))
                            .font(.headline)
                        cardLimitSelector(selection: $selectedShowCardLimit)
                    }
                    
                    showRandomnessControl
                    
                    Spacer(minLength: 18)
                    
                    Button {
                        Haptics.tap()
                        startShowSession()
                    } label: {
                        Text(L("Starten", "Start"))
                            .font(.title3.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 58)
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                    .padding(.top, 8)
                }
            }
            .padding()
        }
            if let showHistoryPreview {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissShowmasterHistoryPreview()
                    }
                    .zIndex(1)
                
                showHistoryPreviewBubble(for: showHistoryPreview)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, showHistoryBarMinY + 38)
                    .transition(.scale(scale: 0.25, anchor: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .coordinateSpace(name: "showPreviewSpace")
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: showHistoryPreview?.id)
        .onPreferenceChange(ShowHistoryBarMinYKey.self) { value in
            if value > 0 {
                showHistoryBarMinY = value
            }
        }
        .onAppear { resetShowSession() }
        .onChange(of: selectedShowContinents) { _, _ in
            resetShowSession()
        }
        .onChange(of: selectedShowCardLimit) { _, _ in
            resetShowSession()
        }
    }
    
    var miniWorldCupView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 18) {
                    modeHeader(title: "Mini-WM", subtitle: L("Handy weitergeben, Flagge wischen, bis nur noch eine Person übrig ist.", "Pass the phone, swipe the flag, until one person remains."))
                    
                    switch miniWorldCupPhase {
                    case .setup:
                        miniWorldCupSetupView
                    case .handoff:
                        miniWorldCupHandoffView
                    case .question:
                        miniWorldCupQuestionView
                    case .finished:
                        miniWorldCupResultView
                    }
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Mini-WM")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    var miniWorldCupSetupView: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label(L("Spieler im Uhrzeigersinn", "Players clockwise"), systemImage: "arrow.clockwise.circle.fill")
                    .font(.headline)
                
                HStack(spacing: 10) {
                    TextField(L("Name", "Name"), text: $miniWorldCupNewPlayerName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        .onSubmit { addMiniWorldCupPlayer() }
                    
                    Button {
                        Haptics.tap()
                        addMiniWorldCupPlayer()
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.bold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(tealAccentColor)
                }
                
                if miniWorldCupPlayers.isEmpty {
                    Text(L("Füge mindestens zwei Personen in Sitzreihenfolge hinzu.", "Add at least two people in seating order."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(Array(miniWorldCupPlayers.enumerated()), id: \.element.id) { index, player in
                            HStack(spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit().weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(tealAccentColor, in: Circle())
                                Text(player.name)
                                    .font(.headline)
                                Spacer()
                                Button {
                                    Haptics.tap()
                                    miniWorldCupPlayers.removeAll { $0.id == player.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(14)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            
            miniWorldCupRulesView
            
            Button {
                Haptics.tap()
                startMiniWorldCup()
            } label: {
                Label(L("Mini-WM starten", "Start mini world cup"), systemImage: "play.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
            .disabled(miniWorldCupPlayers.count < 2)
        }
    }
    
    var miniWorldCupRulesView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Rundenregeln", "Round rules"), systemImage: "slider.horizontal.3")
                .font(.headline)
            
            Stepper(value: $miniWorldCupFlagsPerPlayer, in: 1...5) {
                HStack {
                    Text(L("Flaggen pro Person", "Flags per person"))
                    Spacer()
                    Text("\(miniWorldCupFlagsPerPlayer)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(tealAccentColor)
                }
            }
            .onChange(of: miniWorldCupFlagsPerPlayer) { _, newValue in
                miniWorldCupRequiredCorrect = min(miniWorldCupRequiredCorrect, newValue)
            }
            
            Stepper(value: $miniWorldCupRequiredCorrect, in: 1...miniWorldCupFlagsPerPlayer) {
                HStack {
                    Text(L("Muss richtig sein", "Needed correct"))
                    Spacer()
                    Text("\(miniWorldCupRequiredCorrect)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(tealAccentColor)
                }
            }
            
            Text(L("Standard: 2 Flaggen, 1 richtige Antwort. Ab 4 verbleibenden Personen wird automatisch auf 1 Flagge pro Person gewechselt.", "Default: 2 flags, 1 correct answer. At 4 remaining people, the game automatically switches to 1 flag per person."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }
    
    var miniWorldCupHandoffView: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(tealAccentColor)
                .padding(.top, 4)
            
            Text(L("Handy weitergeben", "Pass the phone"))
                .font(.title.bold())
            
            Text(L("Gib das Handy an", "Give the phone to"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Text(miniWorldCupCurrentPlayer?.name ?? "-")
                .font(.largeTitle.weight(.black))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            
            VStack(spacing: 4) {
                Text(L("Die Flagge wird erst nach OK angezeigt.", "The flag appears only after OK."))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(miniWorldCupTurnRuleText)
                    .font(.caption)
                    .foregroundStyle(tealAccentColor)
            }
            
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    miniWorldCupCardDragOffset = .zero
                    miniWorldCupAnswerFeedback = nil
                    miniWorldCupPhase = .question
                }
            } label: {
                Label(L("OK, ich habe das Handy", "OK, I have the phone"), systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
        .padding(18)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
    
    var miniWorldCupQuestionView: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(miniWorldCupCurrentPlayer?.name ?? "-")
                        .font(.title2.weight(.bold))
                    Text(L("Wischen!", "Swipe!"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(miniWorldCupQuestionProgressText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tealAccentColor)
                }
                Spacer()
                Text("\(miniWorldCupActivePlayers.count)")
                    .font(.headline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tealAccentColor, in: Circle())
            }
            
            VStack(spacing: 12) {
                FlagImage(country: miniWorldCupCurrentCountry, width: 260, height: 170)
                    .padding(.top, 12)
                Text(L("Wischen!", "Swipe!"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(miniWorldCupSwipeColor.opacity(0.55), lineWidth: abs(miniWorldCupCardDragOffset.width) > 8 ? 3 : 1)
            )
            .offset(x: miniWorldCupCardDragOffset.width, y: miniWorldCupCardDragOffset.height * 0.15)
            .rotationEffect(.degrees(Double(miniWorldCupCardDragOffset.width / 18)))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        guard miniWorldCupAnswerFeedback == nil else { return }
                        miniWorldCupCardDragOffset = value.translation
                    }
                    .onEnded { value in
                        guard miniWorldCupAnswerFeedback == nil else { return }
                        finishMiniWorldCupSwipe(width: value.predictedEndTranslation.width)
                    }
            )
            .animation(.spring(response: 0.28, dampingFraction: 0.78), value: miniWorldCupCardDragOffset)
            
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    var miniWorldCupResultView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(L("Gewinner", "Winner"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(miniWorldCupActivePlayers.first?.name ?? "-")
                    .font(.largeTitle.weight(.black))
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
            
            miniWorldCupBracketView
            
            Button {
                Haptics.tap()
                resetMiniWorldCupToSetup(keepPlayers: true)
            } label: {
                Label(L("Neue Mini-WM", "New mini world cup"), systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
    }
    
    var miniWorldCupBracketView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Turnierbaum", "Tournament bracket"), systemImage: "trophy.fill")
                .font(.headline)
            
            if let winner = miniWorldCupActivePlayers.first {
                HStack(spacing: 10) {
                    Text("1.")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Label(winner.name, systemImage: "crown.fill")
                            .font(.headline)
                            .foregroundStyle(.yellow)
                        Text(L("Champion", "Champion"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            
            ForEach(miniWorldCupBracketStageKeys, id: \.self) { stageKey in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(miniWorldCupStageTitle(for: stageKey))
                            .font(.subheadline.weight(.bold))
                        Spacer()
                        Text(miniWorldCupStageRange(for: stageKey))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(miniWorldCupRows(forStage: stageKey)) { row in
                        miniWorldCupBracketRow(row)
                    }
                }
                .padding(10)
                .background(tealAccentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 12))
    }
    
    func miniWorldCupBracketRow(_ row: MiniWorldCupBracketRow) -> some View {
        HStack(spacing: 10) {
            Text("\(row.place).")
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.elimination.playerName)
                    .font(.headline)
                Text(L("Raus bei \(localizedCountryName(row.elimination.country, language: appLanguage))", "Out on \(localizedCountryName(row.elimination.country, language: appLanguage))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("Runde \(row.elimination.round) · \(row.elimination.correctCount)/\(row.elimination.flagCount) richtig", "Round \(row.elimination.round) · \(row.elimination.correctCount)/\(row.elimination.flagCount) correct"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tealAccentColor)
            }
            Spacer()
            FlagImage(country: row.elimination.country, width: 42, height: 28)
        }
        .padding(10)
        .background(panelBackgroundColor.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
    }
    
    var miniWorldCupBracketRows: [MiniWorldCupBracketRow] {
        Array(miniWorldCupEliminations.enumerated()).map { index, elimination in
            MiniWorldCupBracketRow(place: index + 2, elimination: elimination)
        }
    }
    
    var miniWorldCupBracketStageKeys: [Int] {
        Array(Set(miniWorldCupBracketRows.map { miniWorldCupStageKey(for: $0.place) })).sorted()
    }
    
    func miniWorldCupRows(forStage stageKey: Int) -> [MiniWorldCupBracketRow] {
        miniWorldCupBracketRows.filter { miniWorldCupStageKey(for: $0.place) == stageKey }
    }
    
    func miniWorldCupStageKey(for place: Int) -> Int {
        switch place {
        case 2: return 2
        case 3...4: return 4
        case 5...8: return 8
        case 9...16: return 16
        default: return 32
        }
    }
    
    func miniWorldCupStageTitle(for stageKey: Int) -> String {
        switch stageKey {
        case 2: return L("Finale", "Final")
        case 4: return L("Halbfinale", "Semifinal")
        case 8: return L("Viertelfinale", "Quarterfinal")
        case 16: return L("Achtelfinale", "Round of 16")
        default: return L("Frühe Runden", "Early rounds")
        }
    }
    
    func miniWorldCupStageRange(for stageKey: Int) -> String {
        let places = miniWorldCupRows(forStage: stageKey).map(\.place).sorted()
        guard let first = places.first, let last = places.last else { return "" }
        return first == last ? L("Platz \(first)", "Place \(first)") : L("Platz \(first)-\(last)", "Places \(first)-\(last)")
    }
    
    var achievementsView: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "trophy.fill")
                        .font(.title2)
                        .foregroundStyle(tealAccentColor)
                        .frame(width: 38, height: 38)
                        .background(tealAccentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("\(unlockedAchievementCount) von \(achievementItems.count) erreicht", "\(unlockedAchievementCount) of \(achievementItems.count) unlocked"))
                            .font(.headline)
                        Text(L("Üben und Showmaster werden getrennt gewertet.", "Practice and Showmaster are tracked separately."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(L("Sortieren", "Sort")) {
                Picker(L("Sortieren", "Sort"), selection: $achievementSortMode) {
                    ForEach(AchievementSortMode.allCases) { mode in
                        Text(mode.title(language: appLanguage)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            switch achievementSortMode {
            case .category:
                Section(L("Üben", "Practice")) {
                    ForEach(practiceAchievementItems) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
                
                Section(L("Regionen & Spezialsets", "Regions & special sets")) {
                    ForEach(regionAchievementItems) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
                
                Section("Showmaster") {
                    ForEach(showmasterAchievementItems) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            case .date:
                Section(L("Datum", "Date")) {
                    ForEach(achievementsSortedByDate(achievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            case .worldwide:
                Section(L("Weltweit", "Worldwide")) {
                    ForEach(achievementsSortedByGlobalUnlocks(achievementItems)) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            achievedAt: achievedDate(for: item),
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Achievements", "Achievements"))
        .onAppear {
            checkForUnlockedAchievements()
        }
        .safeAreaInset(edge: .bottom) {
            subjectGlassSwitcher()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
    }
    
    var statisticsView: some View {
        List {
            if fullVersionUnlocked {
                Section(L("Bereich", "Scope")) {
                    continentButtonGrid(selection: $selectedStatisticsContinents)
                }
                .onTapGesture { dismissStatisticsSearchKeyboard() }
            }
            
            if isAllCountriesStatisticsScope {
                Section(L("Flaggenboss", "Flaggenboss")) {
                    MasteryScoreCard(
                        score: masteryScore(in: availableCountries),
                        rows: tierScoreRows(in: availableCountries),
                        language: appLanguage,
                        accentColor: tealAccentColor,
                        isInfoPresented: $isMasteryScoreInfoExpanded
                    )
                }
                .onTapGesture { dismissStatisticsSearchKeyboard() }
            }
            
            Section(L("Allgemein", "General")) {
                let seenFlags = totalSeenFlags(in: filteredStatisticsCountries)
                let knownOnceFlags = totalKnownAtLeastOnceFlags(in: filteredStatisticsCountries)
                let knownAnswers = totalCardKnown(in: filteredStatisticsCountries)
                let totalFlags = filteredStatisticsCountries.count
                
                StatRow(title: selectedSubject == .capitals ? L("Gesehene Länder", "Seen countries") : L("Gesehene Flaggen", "Seen flags"), value: "\(seenFlags) / \(totalFlags) · \(percent(seenFlags, of: totalFlags))")
                StatRow(title: selectedSubject == .capitals ? L("Mindestens einmal die Hauptstadt gewusst", "Known capital at least once") : L("Mindestens einmal gewusst", "Known at least once"), value: "\(knownOnceFlags) / \(totalFlags) · \(percent(knownOnceFlags, of: totalFlags))")
                StatRow(title: selectedSubject == .capitals ? L("Gewusste Hauptstädte insgesamt", "Known capitals total") : L("Gewusst insgesamt", "Known total"), value: "\(knownAnswers)")
                StatRow(title: selectedSubject == .capitals ? L("Geübte Länder", "Practiced countries") : L("Geübte Flaggen", "Practiced flags"), value: "\(totalCardReviews(in: filteredStatisticsCountries))")
                StatRow(title: selectedSubject == .capitals ? L("Hauptstädte nicht gewusst", "Capitals not known") : L("Nicht gewusst", "Not known"), value: "\(totalCardUnknown(in: filteredStatisticsCountries))")
                StatRow(title: selectedSubject == .capitals ? L("Gespielte Länder im Showmaster", "Countries played in Showmaster") : L("Gespielte Flaggen im Showmaster", "Flags played in Showmaster"), value: "\(activeProfile.showmasterCards)")
                StatRow(title: L("Streak", "Streak"), value: "\(currentLearningStreak) \(L("Tage", "days"))")
                StatRow(title: L("Beste Streak", "Best streak"), value: "\((activeProfile.bestLearningStreak ?? 0)) \(L("Tage", "days"))")
                
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        dismissStatisticsSearchKeyboard()
                        Haptics.tap()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isTierExplanationExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Label(L("Erklärung der Stufenstruktur", "Level structure explained"), systemImage: "info.circle")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isTierExplanationExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if isTierExplanationExpanded {
                        Text(selectedSubject == .capitals ? L("Die Stufen gehen von F bis S. F bedeutet neu oder unsicher, S bedeutet sehr sicher. Wenn du eine Hauptstadt nach rechts wischst, steigt sie eine Stufe. Nach links fällt sie eine Stufe. Hohe Stufen kommen seltener, werden aber weiterhin abgefragt. Wenn du die Hauptstadt eines Landes 3 Tage lang nicht als gewusst loggst, fällt sie wegen Inaktivität eine Stufe ab.", "Levels go from F to S. F means new or unsure, S means very confident. Swiping a capital to the right moves it up one level. Swiping left moves it down one level. Higher levels appear less often, but still come up. If you do not log a country's capital as known for 3 days, it drops one level due to inactivity.") : L("Die Stufen gehen von F bis S. F bedeutet neu oder unsicher, S bedeutet sehr sicher. Wenn du eine Flagge nach rechts wischst, steigt sie eine Stufe. Nach links fällt sie eine Stufe. Hohe Stufen kommen seltener, werden aber weiterhin abgefragt. Wenn du eine Flagge 3 Tage lang nicht als gewusst loggst, fällt sie wegen Inaktivität eine Stufe ab.", "Levels go from F to S. F means new or unsure, S means very confident. Swiping a flag to the right moves it up one level. Swiping left moves it down one level. Higher levels appear less often, but still come up. If you do not log a flag as known for 3 days, it drops one level due to inactivity."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .onTapGesture { dismissStatisticsSearchKeyboard() }
            
            if !fullVersionUnlocked {
                Section(L("Flaggenboss-Stufen", "Flaggenboss levels")) {
                    TierSummaryGrid(profile: activeProfile, countries: availableCountries, subject: selectedSubject, selectedTier: selectedStatisticsTier) { tier in
                        dismissStatisticsSearchKeyboard()
                        Haptics.tap()
                        selectedStatisticsTier = selectedStatisticsTier == tier ? nil : tier
                    }
                }
                .onTapGesture { dismissStatisticsSearchKeyboard() }
                
                if let selectedStatisticsTier {
                    Section("Flaggenboss-Stufe \(selectedStatisticsTier.rawValue)") {
                        ForEach(statisticsCountries(in: selectedStatisticsTier, from: availableCountries)) { country in
                            FreeTierCountryRow(
                                country: country,
                                stats: stats(for: country),
                                language: appLanguage,
                                subject: selectedSubject,
                                capital: capitalName(for: country),
                                accentColor: tealAccentColor
                            )
                        }
                    }
                }
            }
            
            if isAllCountriesStatisticsScope {
                Section(L("Auswertung", "Analysis")) {
                if fullVersionUnlocked {
                    ScopeScoreBarChart(
                        rows: scopeScoreRows(in: availableCountries),
                        language: appLanguage,
                        accentColor: tealAccentColor
                    )
                    
                    PracticeBalanceChart(
                        rows: practiceBalanceRows(in: availableCountries),
                        language: appLanguage
                    )
                    
                    FlaggenbossScoreChart(
                        points: flaggenbossPoints(in: availableCountries),
                        language: appLanguage,
                        accentColor: tealAccentColor
                    )
                } else {
                    premiumFeatureNotice(feature: L("Premium-Statistiken", "Premium statistics"))
                    ZStack {
                        VStack(alignment: .leading, spacing: 12) {
                            ScopeScoreBarChart(
                                rows: scopeScoreRows(in: availableCountries),
                                language: appLanguage,
                                accentColor: tealAccentColor
                            )
                            PracticeBalanceChart(
                                rows: practiceBalanceRows(in: availableCountries),
                                language: appLanguage
                            )
                            FlaggenbossScoreChart(
                                points: flaggenbossPoints(in: availableCountries),
                                language: appLanguage,
                                accentColor: tealAccentColor
                            )
                        }
                        .blur(radius: 4)
                        .saturation(0.72)
                        .opacity(0.48)
                        .allowsHitTesting(false)
                        
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(tealAccentColor)
                            .frame(width: 52, height: 52)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
            .onTapGesture { dismissStatisticsSearchKeyboard() }
            }
            
            if fullVersionUnlocked {
                Section(selectedSubject == .capitals ? L("Länder", "Countries") : L("Flaggen", "Flags")) {
                    TextField(selectedSubject == .capitals ? L("Land, Hauptstadt, Kontinent oder Code suchen", "Search country, capital, continent, or code") : L("Land, Kontinent oder Code suchen", "Search country, continent, or code"), text: $statisticsSearchText)
                        .focused($isStatisticsSearchFocused)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .font(.subheadline)
                    
                    if !hasStatisticsSearch {
                        TierSummaryGrid(profile: activeProfile, countries: filteredStatisticsCountries, subject: selectedSubject, selectedTier: selectedStatisticsTier) { tier in
                            dismissStatisticsSearchKeyboard()
                            Haptics.tap()
                            expandedStatisticsCountryCodes = []
                            selectedStatisticsTier = selectedStatisticsTier == tier ? nil : tier
                        }
                    }
                }
                
                if hasStatisticsSearch {
                    Section(L("Suchergebnisse", "Search results")) {
                        if filteredStatisticsCountries.isEmpty {
                            Text(selectedSubject == .capitals ? L("Kein Land oder keine Hauptstadt gefunden", "No country or capital found") : L("Keine Flagge gefunden", "No flag found"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(filteredStatisticsCountries.sorted { countryName(for: $0) < countryName(for: $1) }) { country in
                                CountryStatsRow(country: country, stats: stats(for: country), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country))
                                    .contentShape(Rectangle())
                                    .onTapGesture { dismissStatisticsSearchKeyboard() }
                            }
                        }
                    }
                } else if let selectedStatisticsTier {
                    Section("Stufe \(selectedStatisticsTier.rawValue)") {
                        let countries = statisticsCountries(in: selectedStatisticsTier, from: filteredStatisticsCountries)
                        if countries.isEmpty {
                            Text(selectedSubject == .capitals ? L("Keine Länder in dieser Stufe gefunden", "No countries found in this tier") : L("Keine Flaggen in dieser Stufe gefunden", "No flags found in this tier"))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(countries) { country in
                                let isExpanded = expandedStatisticsCountryCodes.contains(country.code)
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        dismissStatisticsSearchKeyboard()
                                        Haptics.tap()
                                        if isExpanded {
                                            expandedStatisticsCountryCodes.remove(country.code)
                                        } else {
                                            expandedStatisticsCountryCodes.insert(country.code)
                                        }
                                    } label: {
                                        CompactCountryStatsRow(country: country, stats: stats(for: country), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if isExpanded {
                                        CountryStatsRow(country: country, stats: stats(for: country), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country), showsHeader: false)
                                            .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Statistik", "Statistics"))
        .safeAreaInset(edge: .bottom) {
            subjectGlassSwitcher()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .onChange(of: selectedStatisticsContinents) { _, _ in
            selectedStatisticsTier = nil
            expandedStatisticsCountryCodes = []
        }
        .onChange(of: selectedSubject) { _, _ in
            selectedStatisticsTier = nil
            expandedStatisticsCountryCodes = []
        }
        .onChange(of: statisticsSearchText) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedStatisticsTier = nil
                expandedStatisticsCountryCodes = []
            }
        }
    }
    
    func dismissStatisticsSearchKeyboard() {
        isStatisticsSearchFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    var globeCountries: [Country] {
        availableCountries
    }
    
    var globeTierByCountryCode: [String: MasteryTier] {
        Dictionary(uniqueKeysWithValues: globeCountries.map { country in
            (country.code, activeProfile.tier(for: country, subject: selectedSubject))
        })
    }
    
    var globeView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    modeHeader(title: L("Globus", "Globe"), subtitle: "")
                    
                    GlobeSceneView(
                        countries: globeCountries,
                        tiersByCountryCode: globeTierByCountryCode,
                        resetToken: globeResetToken,
                        onSelectCountryCode: { code in
                            selectedGlobeCountry = globeCountries.first { $0.code == code }
                            Haptics.tap()
                        }
                    )
                    .frame(height: 430)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.secondary.opacity(0.16), lineWidth: 1)
                    )
                    .overlay(alignment: .topTrailing) {
                        Button {
                            Haptics.tap()
                            globeResetToken += 1
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.headline)
                                .frame(width: 38, height: 38)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                    }
                    
                    TierSummaryGrid(profile: activeProfile, countries: globeCountries, subject: selectedSubject)
                        .padding(12)
                        .background(panelBackgroundColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                }
                .padding()
            }
        }
        .navigationTitle(L("Globus", "Globe"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            subjectGlassSwitcher()
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .sheet(item: $selectedGlobeCountry) { country in
            NavigationStack {
                List {
                    Section {
                        CountryStatsRow(country: country, stats: activeProfile.stats(for: country, subject: selectedSubject), language: appLanguage, subject: selectedSubject, capital: capitalName(for: country))
                    }
                }
                .navigationTitle(countryName(for: country))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }
    }
    
    var friendsView: some View {
        List {
            if onlineFeaturesEnabled {
                Section {
                    subjectModePickerCard()
                }
                
                Section(L("Profil", "Profile")) {
                    HStack(spacing: 10) {
                        Image(systemName: isGameCenterAuthenticated ? "gamecontroller.fill" : "gamecontroller")
                            .foregroundStyle(isGameCenterAuthenticated ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(isGameCenterAuthenticated ? gameCenterAlias : L("Game Center", "Game Center"))
                                .font(.headline)
                            Text(gameCenterStatusText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Haptics.tap()
                            isShowingFriendInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(tealAccentColor)
                                .frame(width: 32, height: 32)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $isShowingFriendInfo) {
                            Text(L("Dein angezeigter Name ist dein Game-Center-Name, außer du gibst dir in den Einstellungen einen Spitznamen, unter dem dich Freunde finden können.", "Your displayed name is your Game Center name unless you set a nickname in Settings that friends can use to find you."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(16)
                                .frame(width: 320, alignment: .leading)
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                
                onlineComparisonSection
                    .id(onlineLeaderboardRefreshID)
            } else {
                Section(L("Online ausgeschaltet", "Online off")) {
                    Label(L("Freunde und Ranglisten sind pausiert", "Friends and leaderboards are paused"), systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                    Text(L("Aktiviere die Online-Funktionen in den Optionen, wenn du Game Center verbinden, deine Statistik hochladen, Bestenlisten laden oder fremde Globusse ansehen möchtest.", "Turn on online features in Options when you want to connect Game Center, upload your stats, load leaderboards, or view other players' globes."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Freunde", "Friends"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    isShowingFriendList = true
                } label: {
                    Image(systemName: "person.2.fill")
                }
                .disabled(!onlineFeaturesEnabled)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if onlineFeaturesEnabled {
                onlineScopeGlassSwitcher()
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
        .task {
            guard onlineFeaturesEnabled else { return }
            await requestLeagueNotificationPermissionIfNeeded()
            try? await Task.sleep(for: .milliseconds(350))
            guard onlineFeaturesEnabled, onlineLeaderboard.isEmpty else { return }
            if !isGameCenterAuthenticated {
                authenticateGameCenter(syncAfterAuthentication: true)
            } else {
                await loadOnlineStats()
            }
        }
    }
    
    var friendsComparisonSection: some View {
        Section(L("Freunde", "Friends")) {
            if friendNames.isEmpty && gameCenterFriendIDs.isEmpty {
                Text(L("Füge Freunde unten in diesem Reiter hinzu.", "Add friends below in this tab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if friendLeaderboard.isEmpty {
                Text(L("Keine Online-Statistiken für deine Freunde gefunden. Freunde müssen Game Center verbinden und ihre Statistik hochladen.", "No online stats found for your friends. Friends need to connect Game Center and upload their stats."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(friendLeaderboard.enumerated()), id: \.element.id) { index, player in
                    onlinePlayerRow(rank: index + 1, player: player, metric: .total)
                }
            }
        }
    }
    
    var friendListSheet: some View {
        NavigationStack {
            List {
                Section(L("Freund hinzufügen", "Add friend")) {
                    HStack {
                        TextField(L("Spitzname oder Code", "Nickname or code"), text: $newFriendName)
                            .textInputAutocapitalization(.words)
                        Button {
                            Haptics.tap()
                            addFriend()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .disabled(newFriendName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Text(L("Freunde finden dich über ihren eindeutigen Spitznamen oder den Code aus der Rangliste.", "Friends can be found by their unique nickname or the code from the leaderboard."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        Haptics.tap()
                        Task { await createTestFriend() }
                    } label: {
                        Label(L("Testfreund erstellen", "Create test friend"), systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(isSyncingOnlineStats)
                }
                
                Section(L("Meine Freunde", "My friends")) {
                    if friendNames.isEmpty && gameCenterFriendIDs.isEmpty {
                        Text(L("Noch keine Freunde hinzugefügt.", "No friends added yet."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    ForEach(friendNames, id: \.self) { friend in
                        HStack {
                            Text(friend)
                            Spacer()
                            Button(role: .destructive) {
                                Haptics.tap(style: .medium)
                                friendPendingRemoval = friend
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    if !gameCenterFriendIDs.isEmpty {
                        Label(L("\(gameCenterFriendIDs.count) Game-Center-Freunde erkannt", "\(gameCenterFriendIDs.count) Game Center friends found"), systemImage: "gamecontroller.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog(
                L("Freund entfernen?", "Remove friend?"),
                isPresented: Binding(
                    get: { friendPendingRemoval != nil },
                    set: { if !$0 { friendPendingRemoval = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let friendPendingRemoval {
                    Button(L("\(friendPendingRemoval) entfernen", "Remove \(friendPendingRemoval)"), role: .destructive) {
                        removeFriend(friendPendingRemoval)
                        self.friendPendingRemoval = nil
                    }
                }
                Button(L("Abbrechen", "Cancel"), role: .cancel) {
                    friendPendingRemoval = nil
                }
            } message: {
                Text(L("Dieser Freund wird nur aus deiner lokalen Freundesliste entfernt.", "This friend will only be removed from your local friend list."))
            }
            .navigationTitle(L("Freundesliste", "Friend list"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        isShowingFriendList = false
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    var onlineComparisonSection: some View {
        Section(L("Online-Vergleich", "Online comparison")) {
            if isSyncingOnlineStats {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(onlineStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label(onlineStatusText, systemImage: onlineLeaderboard.isEmpty ? "icloud" : "icloud.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if selectedOnlineScope == .global && !fullVersionUnlocked {
                premiumFeatureNotice(feature: L("Globale Bestenlisten", "Global leaderboards"))
            } else {
            if selectedOnlineScope == .friends && scopedOnlineLeaderboard.isEmpty {
                Text(L("Keine Freundes-Statistiken gefunden. Füge Freunde oben rechts hinzu oder warte, bis Game-Center-Freunde ihre Statistik hochgeladen haben.", "No friend stats found. Add friends from the top-right button or wait until Game Center friends have uploaded their stats."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            ForEach(Array(scopedOnlineLeaderboard.prefix(10).enumerated()), id: \.element.id) { index, player in
                onlinePlayerRow(rank: index + 1, player: player, metric: .total)
            }
            }
        }
        
        if selectedOnlineScope == .global && !fullVersionUnlocked {
            EmptyView()
        } else {
        Section(L("Letzte 7 Tage", "Last 7 days")) {
            ForEach(Array(scopedLearnedThisWeekLeaderboard.prefix(10).enumerated()), id: \.element.id) { index, player in
                onlinePlayerRow(rank: index + 1, player: player, metric: .week)
            }
        }
        
        Section(L("Meiste Achievements", "Most achievements")) {
            ForEach(Array(scopedAchievementLeaderboard.prefix(10).enumerated()), id: \.element.id) { index, player in
                onlinePlayerRow(rank: index + 1, player: player, metric: .achievements)
            }
        }
        }
    }
    
    func onlinePlayerRow(rank: Int, player: OnlinePlayerStats, metric: OnlineLeaderboardMetric) -> some View {
        Button {
            Haptics.tap()
            selectedOnlineGlobePlayer = player
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text("#\(rank)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        HStack(spacing: 5) {
                            if isCurrentOnlinePlayer(player) {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(tealAccentColor)
                                    .accessibilityLabel(L("Du", "You"))
                            }
                            Text(onlineMetricSubtitle(for: player, metric: metric))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(onlineMetricValue(for: player, metric: metric))
                            .font(.headline.weight(.bold))
                            .foregroundStyle(tealAccentColor)
                        Text(onlineMetricTitle(metric))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                
                if metric == .total {
                    SLevelBar(value: player.tierS, total: max(availableCountries.count, 1), accentColor: tealAccentColor)
                        .frame(height: 10)
                        .padding(.leading, 46)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    func onlineMetricSubtitle(for player: OnlinePlayerStats, metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .total:
            return selectedSubject == .capitals ? L("Hauptstädte auf S", "Capitals on S") : L("Flaggen auf S", "Flags on S")
        case .week:
            return selectedSubject == .capitals ? L("Hauptstädte gewusst", "Capitals known") : L("Flaggen gewusst", "Flags known")
        case .achievements:
            return L("Achievements", "Achievements")
        }
    }
    
    func onlineMetricValue(for player: OnlinePlayerStats, metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .total: return "\(percent(player.tierS, of: availableCountries.count)) · \(player.tierS)"
        case .week: return "\(player.learnedThisWeek)"
        case .achievements: return "\(player.achievementCount)"
        }
    }
    
    func onlineMetricTitle(_ metric: OnlineLeaderboardMetric) -> String {
        switch metric {
        case .total: return "S"
        case .week: return selectedSubject == .capitals ? L("gewusst", "known") : L("gewusst", "known")
        case .achievements: return L("Erfolge", "badges")
        }
    }
    
    func percentText(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
    
    var activeProfileTotalPracticed: Int {
        activeProfile.byCountry.values.reduce(0) { $0 + $1.cardReviews }
    }
    
    var activeProfileCardAccuracy: Double {
        let subjectStats = availableCountries.map { activeProfile.stats(for: $0, subject: selectedSubject) }
        let known = subjectStats.reduce(0) { $0 + $1.cardKnown }
        let total = subjectStats.reduce(0) { $0 + $1.cardReviews }
        guard total > 0 else { return 0 }
        return Double(known) / Double(total)
    }
    
    func activeProfileTierCount(_ tier: MasteryTier) -> Int {
        availableCountries.filter { activeProfile.tier(for: $0, subject: selectedSubject) == tier }.count
    }
    
    func achievementItems(for player: OnlinePlayerStats) -> [AchievementItem] {
        achievementItems.map { item in
            AchievementItem(
                id: item.id,
                title: item.title,
                description: item.description,
                iconName: item.iconName,
                currentValue: player.achievementIDs.contains(item.id) ? item.targetValue : 0,
                targetValue: item.targetValue,
                tint: item.tint
            )
        }
    }
    
    func isCurrentOnlinePlayer(_ player: OnlinePlayerStats) -> Bool {
        if isGameCenterAuthenticated, !gameCenterPlayerID.isEmpty, player.gameCenterPlayerID == gameCenterPlayerID {
            return true
        }
        
        if let localPlayerID = UserDefaults.standard.string(forKey: OnlineStatsService.playerIDKey), player.id == localPlayerID {
            return true
        }
        
        return false
    }
    
    func onlineGlobeSheet(for player: OnlinePlayerStats) -> some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(player.displayName)
                            .font(.title2.bold())
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(L("\(player.totalPracticed) gelernt · \(player.achievementCount) Achievements · Code \(player.friendCode)", "\(player.totalPracticed) learned · \(player.achievementCount) achievements · Code \(player.friendCode)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                
                Section(L("Direkter Vergleich", "Direct comparison")) {
                    ComparisonStatRow(title: L("Gelernt", "Learned"), ownValue: "\(activeProfileTotalPracticed)", otherValue: "\(player.totalPracticed)", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: L("Letzte 7 Tage", "Last 7 days"), ownValue: "\(activeProfile.practiceCardsInLastSevenDays(subject: selectedSubject))", otherValue: "\(player.learnedThisWeek)", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: L("Quote", "Rate"), ownValue: percentText(activeProfileCardAccuracy), otherValue: percentText(player.accuracy), otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: L("Achievements", "Achievements"), ownValue: "\(unlockedAchievementCount)", otherValue: "\(player.achievementCount)", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: "S", ownValue: "\(activeProfileTierCount(.s)) (\(percent(activeProfileTierCount(.s), of: availableCountries.count)))", otherValue: "\(player.tierS) (\(percent(player.tierS, of: availableCountries.count)))", otherName: player.displayName, language: appLanguage)
                    ComparisonStatRow(title: "A", ownValue: "\(activeProfileTierCount(.a))", otherValue: "\(player.tierA)", otherName: player.displayName, language: appLanguage)
                }
                
                Section(L("S-Stufe Verlauf", "S level history")) {
                    STierHistorySparkline(values: player.sTierHistory, maxValue: max(availableCountries.count, 1), accentColor: tealAccentColor)
                        .frame(height: 72)
                    Text(L("Zeigt, wie viele \(selectedSubject == .capitals ? "Hauptstädte" : "Flaggen") zuletzt auf S-Stufe waren.", "Shows how many \(selectedSubject == .capitals ? "capitals" : "flags") were recently on S level."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if fullVersionUnlocked {
                    Section(L("Globus", "Globe")) {
                        GlobeSceneView(
                            countries: availableCountries,
                            tiersByCountryCode: player.tiersByCountryCode,
                            resetToken: globeResetToken
                        ) { countryCode in
                            selectedGlobeCountry = availableCountries.first { $0.code == countryCode }
                        }
                        .frame(height: 320)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } else {
                    Section(L("Globus", "Globe")) {
                        lockedGlobePreview(tiersByCountryCode: player.tiersByCountryCode)
                    }
                }
                
                Section(L("Stufen", "Levels")) {
                    TierSummaryGrid(
                        profile: virtualProfile(for: player),
                        countries: availableCountries,
                        subject: selectedSubject
                    )
                    .padding(.vertical, 6)
                }
                
                Section(L("Achievements", "Achievements")) {
                    ForEach(achievementsSortedByGlobalUnlocks(achievementItems(for: player))) { item in
                        AchievementRow(
                            item: item,
                            language: appLanguage,
                            globalUnlockCount: globalUnlockCount(for: item.id),
                            globalPlayerCount: globalAchievementPlayerCount
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackgroundGradient.ignoresSafeArea())
            .navigationTitle(L("Freund-Statistik", "Friend stats"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Fertig", "Done")) {
                        selectedOnlineGlobePlayer = nil
                    }
                }
            }
        }
    }
    
    func virtualProfile(for player: OnlinePlayerStats) -> UserProfile {
        var profile = UserProfile(id: UUID(), name: player.displayName, pin: "")
        for country in availableCountries {
            var stats = CountryStats()
            stats.storedTier = player.tiersByCountryCode[country.code] ?? .f
            profile.byCountry[selectedSubject.statsKey(for: country)] = stats
        }
        return profile
    }
    
    func fullVersionLockedView(feature: String) -> some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            VStack(spacing: 14) {
                lockedGlobePreview(tiersByCountryCode: globeTierByCountryCode)
                    .frame(height: 280)
                
                Text(feature)
                    .font(.title2.bold())

                NavigationLink(value: AppScreen.options) {
                    Label(L("Vollversion ansehen", "View full version"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(ActionButtonStyle(color: tealAccentColor))
                .padding(.top, 4)
            }
            .padding()
            .frame(maxWidth: 420)
        }
        .navigationTitle(feature)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    func lockedGlobePreview(tiersByCountryCode: [String: MasteryTier]) -> some View {
        ZStack {
            GlobeSceneView(
                countries: availableCountries,
                tiersByCountryCode: tiersByCountryCode,
                resetToken: globeResetToken,
                onSelectCountryCode: { _ in }
            )
            .blur(radius: 6)
            .saturation(0.72)
            .opacity(0.72)
            
            Image(systemName: "lock.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(tealAccentColor)
                .frame(width: 58, height: 58)
                .background(.ultraThinMaterial, in: Circle())
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.22), lineWidth: 1)
        )
    }
    
    func premiumFeatureNotice(feature: String) -> some View {
        Label(L("\(feature) ist Teil der Vollversion.", "\(feature) is part of the full version."), systemImage: "lock.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
    
    func infoButton<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
        Button {
            Haptics.tap()
            isPresented.wrappedValue = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body.weight(.semibold))
                .foregroundStyle(tealAccentColor)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isPresented) {
            content()
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(16)
                .frame(width: 320, alignment: .leading)
                .presentationCompactAdaptation(.popover)
        }
    }
    
    func tierDecayPopupView(_ popup: TierDecayPopup) -> some View {
        let selectedChange = popup.changes.first { $0.id == selectedTierDecayChangeID } ?? popup.changes.first
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tealAccentColor)
                    .frame(width: 42, height: 42)
                    .background(tealAccentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Stufen angepasst", "Levels adjusted"))
                        .font(.title3.bold())
                    Text(L("Keine Sorge, das bekommst du schnell wieder hin!", "No worries, you will get this back quickly!"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tealAccentColor)
                    Text(L("Tippe auf ein Land, um zu sehen, was sich verändert hat.", "Tap a country to see what changed."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
                        tierDecayPopup = nil
                        selectedTierDecayChangeID = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(popup.changes) { change in
                        tierDecayChangeButton(change)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)
            
            if let selectedChange {
                tierDecayDetailView(selectedChange)
            }
        }
        .padding(18)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(tealAccentColor.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
    }
    
    func tierDecayChangeButton(_ change: TierDecayChange) -> some View {
        let isSelected = selectedTierDecayChangeID == change.id
        return Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.84)) {
                selectedTierDecayChangeID = change.id
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tierDecayCountryTitle(for: change))
                        .font(.subheadline.weight(.semibold))
                    Text(tierDecaySubjectTitle(for: change))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(change.from.rawValue)
                        .foregroundStyle(change.from.color)
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(change.to.rawValue)
                        .foregroundStyle(change.to.color)
                }
                .font(.headline.weight(.bold))
            }
            .padding(12)
            .background(isSelected ? tealAccentColor.opacity(0.14) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? tealAccentColor.opacity(0.42) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    
    func tierDecayDetailView(_ change: TierDecayChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tierDecayCountryTitle(for: change))
                .font(.headline)
            HStack(spacing: 8) {
                Label(L("Vorher: \(change.from.rawValue)", "Before: \(change.from.rawValue)"), systemImage: "arrow.up.circle")
                    .foregroundStyle(change.from.color)
                Spacer()
                Label(L("Jetzt: \(change.to.rawValue)", "Now: \(change.to.rawValue)"), systemImage: "arrow.down.circle")
                    .foregroundStyle(change.to.color)
            }
            .font(.caption.weight(.semibold))
            Text(L("Zuletzt gewusst vor \(change.daysSinceLastPractice) Tagen.", "Last known \(change.daysSinceLastPractice) days ago."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
    
    func tierDecayCountryTitle(for change: TierDecayChange) -> String {
        let code = change.statsKey.replacingOccurrences(of: "capital_", with: "")
        guard let country = allCountries.first(where: { $0.code == code }) else { return change.statsKey }
        return localizedCountryName(country, language: appLanguage)
    }
    
    func tierDecaySubjectTitle(for change: TierDecayChange) -> String {
        change.statsKey.hasPrefix("capital_") ? L("Hauptstadt", "Capital") : L("Flagge", "Flag")
    }
    
    var leagueView: some View {
        ZStack {
            appBackgroundGradient
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 16) {
                    modeHeader(title: L("Liga (WIP)", "League (WIP)"), subtitle: L("One-on-One auf Zeit", "Timed one-on-one"))
                    
                    if leagueMatchActive {
                        leagueMatchCard
                    } else if leagueShowsStartMenu {
                        leagueStartMenuView
                    } else {
                        leagueSetupView
                    }
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(L("Liga (WIP)", "League (WIP)"))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if leagueMatchActive && leagueMatchPhase == .playing {
                leagueUnknownButton
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
            }
        }
        .task {
            guard onlineFeaturesEnabled else { return }
            try? await Task.sleep(for: .milliseconds(350))
            if !isGameCenterAuthenticated {
                authenticateGameCenter(syncAfterAuthentication: false)
            } else if gameCenterFriendIDs.isEmpty {
                await loadGameCenterFriends()
            }
            if onlineLeaderboard.isEmpty {
                await loadOnlineStats()
            }
            await ensureLeagueTestFriendIfNeeded()
        }
    }
    
    var leagueStartMenuView: some View {
        VStack(spacing: 14) {
            Button {
                Haptics.tap()
                showLeagueOpponentPicker()
            } label: {
                Label(L("Liga spielen", "Play league"), systemImage: "trophy.circle.fill")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
            
            leagueStatsCard
            
            leagueMatchHistoryCard
        }
    }
    
    func showLeagueOpponentPicker() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            leagueShowsStartMenu = false
            leagueOpponentPickerPulse = true
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                leagueOpponentPickerPulse = false
            }
        }
    }
    
    func leagueSummaryOverlay(_ result: LeagueMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(result.didWin ? L("Gewonnen", "Won") : L("Verloren", "Lost"), systemImage: result.didWin ? "crown.fill" : "flag.checkered")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(result.didWin ? .green : .red)
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        leagueSummaryResult = nil
                        leagueShowsStartMenu = true
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            HStack(spacing: 10) {
                leagueMetricTile(title: L("Score", "Score"), value: "\(result.ownScore)")
                leagueMetricTile(title: L("Gegner", "Opponent"), value: "\(result.opponentScore)")
            }
            
            if let before = result.ratingBefore, let after = result.ratingAfter, let delta = result.ratingDelta {
                HStack {
                    Text("\(before) → \(after) ELO")
                        .font(.headline.monospacedDigit().weight(.bold))
                    Spacer()
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(.title2.monospacedDigit().weight(.black))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                }
                .padding(12)
                .background((delta >= 0 ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            
            Text(L("\(result.correct) richtig · \(result.wrong) falsch · Gegner: \(result.opponentName)", "\(result.correct) correct · \(result.wrong) wrong · Opponent: \(result.opponentName)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if !leagueLiveResultText.isEmpty {
                Text(leagueLiveResultText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tealAccentColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    leagueSummaryResult = nil
                    leagueShowsStartMenu = true
                }
            } label: {
                Label(L("Zurück zum Liga-Menü", "Back to league menu"), systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        }
        .padding(16)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }
    
    var leagueSetupView: some View {
        VStack(spacing: 14) {
            leagueStartMatchButton
            leagueStatsCard
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "scope")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(tealAccentColor)
                        .rotationEffect(.degrees(leagueOpponentPickerPulse ? 8 : 0))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Gegner auswählen", "Choose opponent"))
                            .font(.headline)
                        Text(L("Wähle jetzt, gegen wen du spielst.", "Now choose who you play against."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                
                if leagueOpponents.isEmpty && leagueFriendOpponents.isEmpty {
                    Text(L("Noch keine Online-Gegner geladen. Du kannst trotzdem gegen den Liga-Durchschnitt starten.", "No online opponents loaded yet. You can still start against the league baseline."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Standardgegner", "Preset opponents"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    ForEach(leaguePresetOpponents) { opponent in
                        leagueOpponentButton(
                            id: opponent.id,
                            title: L(opponent.titleDE, opponent.titleEN),
                            subtitle: L(opponent.subtitleDE, opponent.subtitleEN),
                            score: opponent.score
                        )
                    }
                    
                    if !leagueFriendOpponents.isEmpty {
                        Text(L("Freunde 1gg1", "Friends 1v1"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tealAccentColor)
                            .padding(.top, 4)
                        
                        ForEach(leagueFriendOpponents.prefix(8)) { opponent in
                            leagueOpponentButton(
                                id: opponent.id,
                                title: opponent.displayName,
                                subtitle: "\(LeagueLeaderboardRow.leagueTitle(for: opponent.leagueRating)) · \(opponent.leagueRating) ELO · \(opponent.leaguePlayed) \(L("Spiele", "matches"))",
                                score: max(opponent.leagueBestScore, Int(opponent.leagueAverageScore.rounded()))
                            )
                        }
                    }
                    
                    if !leagueGlobalOpponents.isEmpty {
                        Text(L("Weitere Online-Gegner", "More online opponents"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                        
                        ForEach(leagueGlobalOpponents.prefix(6)) { opponent in
                            leagueOpponentButton(
                                id: opponent.id,
                                title: opponent.displayName,
                                subtitle: "\(LeagueLeaderboardRow.leagueTitle(for: opponent.leagueRating)) · \(opponent.leagueRating) ELO · \(opponent.leaguePlayed) \(L("Spiele", "matches"))",
                                score: max(opponent.leagueBestScore, Int(opponent.leagueAverageScore.rounded()))
                            )
                        }
                    }
                }
            }
            .padding(14)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(tealAccentColor.opacity(leagueOpponentPickerPulse ? 0.85 : 0.18), lineWidth: leagueOpponentPickerPulse ? 2 : 1)
            )
            .scaleEffect(leagueOpponentPickerPulse ? 1.012 : 1)
            .animation(.spring(response: 0.34, dampingFraction: 0.68), value: leagueOpponentPickerPulse)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(L("Online-Liga", "Online league"), systemImage: onlineFeaturesEnabled ? "network" : "network.slash")
                        .font(.headline)
                    Spacer()
                    Button {
                        Haptics.tap()
                        Task { await syncOnlineStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.plain)
                    .disabled(!onlineFeaturesEnabled || isSyncingOnlineStats)
                }
                
                Text(onlineStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                ForEach(onlineLeagueLeaderboard.prefix(6)) { player in
                    LeagueLeaderboardRow(player: player, isCurrentPlayer: isCurrentOnlinePlayer(player), language: appLanguage)
                }
            }
            .padding(14)
            .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    
    var leagueStartMatchButton: some View {
        Button {
            Haptics.tap()
            Task { await startLeagueMatch() }
        } label: {
            Label(L("Match starten", "Start match"), systemImage: "play.fill")
                .font(.title3.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(ActionButtonStyle(color: tealAccentColor))
        .disabled(leagueIsPreparingLiveMatch)
    }
    
    var leagueUnknownButton: some View {
        let isEnabled = leagueTimerIsRunning && !leagueInputIsLocked
        return Button {
            guard isEnabled else { return }
            Haptics.notify(.warning)
            submitLeagueAnswer(forcedCorrectness: false, keepsTypedAnswer: false)
        } label: {
            Label(L("Weiß ich nicht", "I don't know"), systemImage: "questionmark.circle.fill")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(ActionButtonStyle(color: .orange, isProminent: false))
        .disabled(!isEnabled)
    }
    
    var leagueStatsCard: some View {
        let stats = activeProfile.leagueStats ?? LeagueStats()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(L("Deine Liga", "Your league"), systemImage: "bolt.trophy.fill")
                    .font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(stats.leagueTitle)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(tealAccentColor)
                    Text("\(stats.rating) ELO")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 10) {
                leagueMetricTile(title: L("Spiele", "Matches"), value: "\(stats.played)")
                leagueMetricTile(title: L("Bilanz", "Record"), value: "\(stats.wins)-\(stats.losses)")
                leagueMetricTile(title: L("Bestscore", "Best score"), value: "\(stats.bestScore)")
                leagueMetricTile(title: L("Bis Aufstieg", "To promote"), value: "\(max(stats.nextDivisionRating - stats.rating, 0))")
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }
    
    func leagueMetricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
    
    var leagueMatchHistoryCard: some View {
        let matches = activeProfile.leagueStats?.recentMatches ?? []
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Match-History", "Match history"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                Text("\(matches.count)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.secondary)
            }
            
            if matches.isEmpty {
                Text(L("Noch keine Liga-Matches gespielt.", "No league matches played yet."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(matches.prefix(5)) { match in
                        leagueHistoryRow(match)
                    }
                }
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
    }
    
    func leagueHistoryRow(_ match: LeagueMatchResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: match.didWin ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(match.didWin ? .green : .red)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(match.opponentName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(match.ownScore) : \(match.opponentScore) · \(match.correct) \(L("richtig", "correct")) · \(match.wrong) \(L("falsch", "wrong"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if let delta = match.ratingDelta {
                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                    .font(.caption.monospacedDigit().weight(.black))
                    .foregroundStyle(delta >= 0 ? .green : .red)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
    
    func leagueOpponentButton(id: String, title: String, subtitle: String, score: Int) -> some View {
        let isSelected = selectedLeagueOpponentID == id
        return Button {
            Haptics.tap()
            selectedLeagueOpponentID = id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? tealAccentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(score)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(tealAccentColor)
            }
            .padding(10)
            .background(isSelected ? tealAccentColor.opacity(0.12) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
    
    var leagueMatchCard: some View {
        VStack(spacing: 16) {
            if leagueMatchPhase == .loading || leagueMatchPhase == .countdown {
                leagueMatchPreparationView
            } else {
                leaguePlayableView
            }
        }
        .padding(14)
        .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
        .onAppear {
            prepareLeagueTimerAfterLayout()
        }
        .onDisappear {
            leagueTimerStartTask?.cancel()
        }
    }
    
    var leagueMatchPreparationView: some View {
        VStack(spacing: 18) {
            Text(L("Lädt", "Loading"))
                .font(.headline)
                .foregroundStyle(.secondary)
            
            if leagueMatchPhase == .loading {
                ProgressView()
                    .tint(tealAccentColor)
            } else {
                Text("\(leagueStartCountdown)")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tealAccentColor)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250)
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: leagueMatchPhase)
        .animation(.spring(response: 0.28, dampingFraction: 0.84), value: leagueStartCountdown)
    }
    
    var leaguePlayableView: some View {
        VStack(spacing: 16) {
            HStack {
                Label(leagueTimerIsRunning ? "\(leagueSecondsRemaining)s" : L("Bereit", "Ready"), systemImage: "timer")
                    .font(.title2.monospacedDigit().weight(.bold))
                    .foregroundStyle(leagueSecondsRemaining <= 10 ? .red : tealAccentColor)
                Spacer()
                Text("\(leagueScore)")
                    .font(.title2.monospacedDigit().weight(.bold))
            }
            
            ZStack {
                Group {
                    if let leaguePreloadedFlagImage {
                        Image(uiImage: leaguePreloadedFlagImage)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 280, height: 170)
                    } else {
                        FlagImage(country: leagueCurrentCountry, width: 280, height: 170)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .opacity(leagueInputIsLocked ? 0.55 : 1)
            }
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: leagueAnswerFeedback)
            .animation(.easeOut(duration: 0.16), value: leagueInputIsLocked)
            
            TextField(L("Name der Flagge", "Flag name"), text: $leagueAnswerText)
                .focused($isLeagueAnswerFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.send)
                .onSubmit { submitLeagueAnswer() }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(tealAccentColor.opacity(0.32), lineWidth: 1)
                )
                .onChange(of: leagueAnswerText) { _, newValue in
                    guard !leagueInputIsLocked && Date() >= leagueTypingLockedUntil else {
                        if newValue != leagueLockedAnswerText {
                            leagueAnswerText = leagueLockedAnswerText
                        }
                        return
                    }
                    evaluateLeagueAnswer(newValue)
                }
                .allowsHitTesting(leagueTimerIsRunning && !leagueInputIsLocked)
                .opacity(leagueInputIsLocked ? 0.82 : 1)
            
            if let leagueAnswerFeedback {
                leagueFeedbackField(isCorrect: leagueAnswerFeedback)
            }
            
            HStack(spacing: 10) {
                leagueMetricTile(title: L("Richtig", "Correct"), value: "\(leagueCorrect)")
                leagueMetricTile(title: L("Falsch", "Wrong"), value: "\(leagueWrong)")
            }
            
            Button(role: .destructive) {
                Haptics.notify(.warning)
                finishLeagueMatch()
            } label: {
                Text(L("Runde beenden", "Finish round"))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(ActionButtonStyle(color: .red, isProminent: false))
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    
    func leagueFeedbackField(isCorrect: Bool) -> some View {
        Label(
            isCorrect ? L("Richtig: \(leagueRevealedCountryName)", "Correct: \(leagueRevealedCountryName)") : L("Falsch: \(leagueRevealedCountryName)", "Wrong: \(leagueRevealedCountryName)"),
            systemImage: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .font(.subheadline.weight(.bold))
        .foregroundStyle(isCorrect ? .green : .red)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background((isCorrect ? Color.green : Color.red).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
    
    var leagueRecognitionView: some View {
        HStack(spacing: 10) {
            if let match = leagueAnswerMatch {
                let isCurrentCountry = match.country == leagueCurrentCountry
                Image(systemName: isCurrentCountry ? (match.isCertain ? "checkmark.circle.fill" : "scope") : (match.isCertain ? "xmark.circle.fill" : "questionmark.circle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrentCountry ? tealAccentColor : (match.isCertain ? .red : .orange))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrentCountry ? L("Erkannt: \(localizedCountryName(match.country, language: appLanguage))", "Recognized: \(localizedCountryName(match.country, language: appLanguage))") : L("Meintest du \(localizedCountryName(match.country, language: appLanguage))?", "Did you mean \(localizedCountryName(match.country, language: appLanguage))?"))
                        .font(.caption.weight(.semibold))
                    Text(match.isCertain ? (isCurrentCountry ? L("Wird automatisch richtig gewertet", "Will be marked correct automatically") : L("Wird automatisch falsch gewertet", "Will be marked wrong automatically")) : L("Weiter tippen oder Enter drücken", "Keep typing or press Return"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L("Tippe den Ländernamen. Kleine Fehler sind okay.", "Type the country name. Small typos are okay."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
    
    func leagueAnswerDetailRow(_ answer: LeagueAnswerRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: answer.wasCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(answer.wasCorrect ? .green : .red)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(answer.countryName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(answer.wasCorrect ? L("gewusst", "known") : L("nicht gewusst", "missed"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .foregroundStyle(answer.wasCorrect ? .green : .red)
                        .background((answer.wasCorrect ? Color.green : Color.red).opacity(0.12), in: Capsule())
                }
                
                Text(L("Eingabe: \(answer.submittedAnswer) · Erkannt: \(answer.detectedCountryName)", "Input: \(answer.submittedAnswer) · Detected: \(answer.detectedCountryName)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                
                Text(L("\(leagueResponseTimeText(answer.responseTime)) · +\(answer.pointsAwarded) Punkte", "\(leagueResponseTimeText(answer.responseTime)) · +\(answer.pointsAwarded) points"))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(answer.wasCorrect ? tealAccentColor : .secondary)
            }
            
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
    
    var leagueOpponents: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard
            .filter { !isCurrentOnlinePlayer($0) }
            .sorted {
                if $0.leagueRating == $1.leagueRating {
                    return $0.leagueBestScore > $1.leagueBestScore
                }
                return $0.leagueRating > $1.leagueRating
            }
    }
    
    var leaguePresetOpponents: [LeaguePresetOpponent] {
        [
            LeaguePresetOpponent(
                id: "preset_rookie",
                titleDE: "Bronze Herausforderer",
                titleEN: "Bronze challenger",
                subtitleDE: "Ziel: 900 Punkte · 850 ELO",
                subtitleEN: "Target: 900 points · 850 ELO",
                score: 900,
                rating: 850
            ),
            LeaguePresetOpponent(
                id: "preset_average",
                titleDE: "Liga-Durchschnitt",
                titleEN: "League baseline",
                subtitleDE: "Ziel: 1500 Punkte · 1000 ELO",
                subtitleEN: "Target: 1500 points · 1000 ELO",
                score: 1500,
                rating: 1000
            ),
            LeaguePresetOpponent(
                id: "preset_rival",
                titleDE: "Starker Rivale",
                titleEN: "Strong rival",
                subtitleDE: "Ziel: 2200 Punkte · 1250 ELO",
                subtitleEN: "Target: 2200 points · 1250 ELO",
                score: 2200,
                rating: 1250
            ),
            LeaguePresetOpponent(
                id: "preset_champion",
                titleDE: "Meisterprüfung",
                titleEN: "Champion check",
                subtitleDE: "Ziel: 3000 Punkte · 1650 ELO",
                subtitleEN: "Target: 3000 points · 1650 ELO",
                score: 3000,
                rating: 1650
            )
        ]
    }
    
    var leagueFriendOpponents: [OnlinePlayerStats] {
        friendLeaderboard
            .filter { !isCurrentOnlinePlayer($0) }
            .sorted {
                if $0.leagueRating == $1.leagueRating {
                    return $0.leagueBestScore > $1.leagueBestScore
                }
                return $0.leagueRating > $1.leagueRating
            }
    }
    
    var leagueGlobalOpponents: [OnlinePlayerStats] {
        let friendIDs = Set(leagueFriendOpponents.map(\.id))
        return leagueOpponents.filter { !friendIDs.contains($0.id) }
    }
    
    var selectedLeagueOpponent: OnlinePlayerStats? {
        leagueOpponents.first { $0.id == selectedLeagueOpponentID }
    }
    
    var selectedLeaguePresetOpponent: LeaguePresetOpponent {
        leaguePresetOpponents.first { $0.id == selectedLeagueOpponentID } ?? leaguePresetOpponents[1]
    }
    
    func leagueResponseTimeText(_ seconds: Double) -> String {
        String(format: "%.1f s", max(seconds, 0))
    }
    
    func leaguePointsForAnswer(responseTime: Double) -> Int {
        let basePoints = 100
        let speedBonus = max(0, Int((8.0 - min(responseTime, 8.0)) * 16.0))
        let timePressureBonus = max(0, leagueSecondsRemaining / 10)
        return basePoints + speedBonus + timePressureBonus
    }
    
    @MainActor
    func requestLeagueNotificationPermissionIfNeeded() async {
        guard !leagueNotificationsAuthorized else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            leagueNotificationsAuthorized = true
            return
        }
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            leagueNotificationsAuthorized = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            leagueNotificationsAuthorized = false
        }
    }
    
    func playLeagueSound(success: Bool) {
        AudioServicesPlaySystemSound(success ? 1057 : 1053)
    }
    
    func scheduleLeagueNotification(title: String, body: String) {
        guard leagueNotificationsAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "league-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
    
    var onlineLeagueLeaderboard: [OnlinePlayerStats] {
        deduplicatedOnlineLeaderboard.sorted {
            if $0.leagueRating == $1.leagueRating {
                return $0.leagueBestScore > $1.leagueBestScore
            }
            return $0.leagueRating > $1.leagueRating
        }
    }
    
    @MainActor
    func startLeagueMatch() async {
        guard !leagueIsPreparingLiveMatch else { return }
        leagueIsPreparingLiveMatch = true
        defer { leagueIsPreparingLiveMatch = false }
        
        leagueCorrect = 0
        leagueWrong = 0
        leagueScore = 0
        leagueSecondsRemaining = 60
        leagueRecentCountryCodes = []
        leagueAnswerRecords = []
        leagueAnswerText = ""
        leagueAnswerMatch = nil
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = nil
        leagueCountdownTask?.cancel()
        leagueCountdownTask = nil
        leagueTimerIsRunning = false
        leagueInputIsLocked = false
        leagueLockedAnswerText = ""
        leagueTypingLockedUntil = .distantPast
        leagueCurrentQuestionStartedAt = Date()
        leagueLivePollTask?.cancel()
        leagueLivePollTask = nil
        leagueLiveMatchID = nil
        leagueLivePlayerID = ""
        leagueLiveOpponentName = ""
        leagueLiveOpponentScore = nil
        leagueLiveCountryCodes = []
        leagueLiveCountryIndex = 0
        leagueLiveResultText = ""
        leagueAnswerFeedback = nil
        leagueRevealedCountryName = ""
        leagueMatchPhase = .loading
        leagueStartCountdown = 3
        leagueFirstFlagIsReady = false
        leaguePreloadedFlagImage = nil
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = nil
        await prepareLiveLeagueMatchIfNeeded()
        leagueCurrentCountry = nextLeagueCountry()
        leagueMatchActive = true
    }
    
    @MainActor
    func prepareLiveLeagueMatchIfNeeded() async {
        guard
            onlineFeaturesEnabled,
            let opponent = selectedLeagueOpponent,
            leagueFriendOpponents.contains(where: { $0.id == opponent.id })
        else { return }
        
        if !isGameCenterAuthenticated {
            authenticateGameCenter(syncAfterAuthentication: false)
        }
        
        let playerID = OnlineStatsService.playerID(gameCenterPlayerID: isGameCenterAuthenticated ? gameCenterPlayerID : nil)
        let playerName = OnlineStatsService.normalizedName(onlinePlayerName, fallback: gameCenterAlias)
        do {
            let match = try await OnlineStatsService.findOrCreateLiveLeagueMatch(
                currentPlayerID: playerID,
                currentPlayerName: playerName,
                opponent: opponent,
                countries: availableCountries
            )
            leagueLiveMatchID = match.id
            leagueLivePlayerID = playerID
            leagueLiveOpponentName = match.opponentName(for: playerID)
            leagueLiveOpponentScore = match.opponentScore(for: playerID)
            leagueLiveCountryCodes = match.countryCodes
            leagueLiveCountryIndex = 0
            leagueLiveResultText = L("Async 1gg1 gegen \(leagueLiveOpponentName): \(match.countryCodes.count) identische Flaggen in exakt derselben Reihenfolge.", "Async 1v1 against \(leagueLiveOpponentName): \(match.countryCodes.count) identical flags in the exact same order.")
        } catch {
            leagueLiveResultText = L("Live 1gg1 konnte nicht vorbereitet werden: \(OnlineStatsService.userFacingMessage(for: error))", "Live 1v1 could not be prepared: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }
    
    func prepareLeagueTimerAfterLayout() {
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = Task { @MainActor in
            await Task.yield()
            leagueMatchPhase = .loading
            await prepareFirstLeagueFlag()
            guard leagueMatchActive else { return }
            leagueFirstFlagIsReady = true
            
            leagueMatchPhase = .countdown
            for value in stride(from: 3, through: 1, by: -1) {
                leagueStartCountdown = value
                try? await Task.sleep(for: .seconds(1))
                guard leagueMatchActive else { return }
            }
            
            leagueMatchPhase = .playing
            leagueCurrentQuestionStartedAt = Date()
            await Task.yield()
            isLeagueAnswerFocused = true
            try? await Task.sleep(for: .milliseconds(180))
            guard leagueMatchActive else { return }
            leagueTimerIsRunning = true
            startLeagueCountdown()
        }
    }
    
    func prepareFirstLeagueFlag() async {
        for _ in 0..<8 {
            guard leagueMatchActive else { return }
            if let image = await preloadedLeagueFlagImage(for: leagueCurrentCountry) {
                leaguePreloadedFlagImage = image
                return
            }
            leagueCurrentCountry = nextLeagueCountry()
        }
        
        leaguePreloadedFlagImage = nil
    }
    
    func preloadedLeagueFlagImage(for country: Country) async -> UIImage? {
        guard let url = country.flagImageURL else { return nil }
        do {
            let result = try await OnlineStatsService.withTimeout(seconds: 4) {
                try await FlagImageCache.shared.loadImage(from: url)
            }
            return result
        } catch {
            return nil
        }
    }
    
    func startLeagueCountdown() {
        leagueCountdownTask?.cancel()
        let endDate = Date().addingTimeInterval(Double(leagueSecondsRemaining))
        leagueCountdownTask = Task { @MainActor in
            while leagueMatchActive && leagueTimerIsRunning {
                let remaining = max(0, Int(ceil(endDate.timeIntervalSinceNow)))
                leagueSecondsRemaining = remaining
                if remaining == 0 {
                    finishLeagueMatch()
                    return
                }
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }
    
    func submitLeagueAnswer() {
        submitLeagueAnswer(forcedCorrectness: nil, keepsTypedAnswer: true)
    }
    
    func submitLeagueAnswer(forcedCorrectness: Bool?, keepsTypedAnswer: Bool) {
        guard leagueMatchActive, leagueTimerIsRunning, !leagueInputIsLocked else { return }
        let answer = normalizedLeagueAnswer(leagueAnswerText)
        guard !answer.isEmpty || forcedCorrectness != nil else { return }
        let match = leagueAnswerMatch ?? bestLeagueAnswerMatch(for: leagueAnswerText)
        let isCorrect = forcedCorrectness ?? (match?.country == leagueCurrentCountry && (match?.isAcceptable == true || match?.isCertain == true))
        let correctCountryName = localizedCountryName(leagueCurrentCountry, language: appLanguage)
        let submittedAnswer = leagueAnswerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleSubmittedAnswer = submittedAnswer.isEmpty ? L("Weiß ich nicht", "I don't know") : submittedAnswer
        let detectedCountryName = match.map { localizedCountryName($0.country, language: appLanguage) } ?? L("Keine eindeutige Erkennung", "No clear detection")
        let responseTime = Date().timeIntervalSince(leagueCurrentQuestionStartedAt)
        let pointsAwarded = isCorrect ? leaguePointsForAnswer(responseTime: responseTime) : 0
        
        leagueLockedAnswerText = keepsTypedAnswer ? leagueAnswerText : ""
        leagueInputIsLocked = true
        leagueTypingLockedUntil = .distantFuture
        leagueMatchPhase = .feedback
        leagueAnswerFeedback = isCorrect
        leagueRevealedCountryName = correctCountryName
        leagueAnswerRecords.append(
            LeagueAnswerRecord(
                id: UUID(),
                countryCode: leagueCurrentCountry.code,
                countryName: correctCountryName,
                submittedAnswer: visibleSubmittedAnswer,
                detectedCountryName: detectedCountryName,
                wasCorrect: isCorrect,
                responseTime: responseTime,
                pointsAwarded: pointsAwarded
            )
        )
        
        if isCorrect {
            leagueCorrect += 1
            leagueScore += pointsAwarded
            Haptics.tap(style: .heavy)
            Haptics.notify(.success)
            playLeagueSound(success: true)
        } else {
            leagueWrong += 1
            leagueScore = max(0, leagueScore - 25)
            Haptics.tap(style: .light)
            playLeagueSound(success: false)
        }
        
        leagueRecentCountryCodes.append(leagueCurrentCountry.code)
        leagueRecentCountryCodes = Array(leagueRecentCountryCodes.suffix(12))
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard leagueMatchActive else { return }
            leagueAnswerFeedback = nil
            leagueRevealedCountryName = ""
        }
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = Task { @MainActor in
            guard leagueMatchActive else { return }
            let nextCountry = nextLeagueCountry()
            let nextImage = await preloadedLeagueFlagImage(for: nextCountry)
            leagueAnswerText = ""
            leagueLockedAnswerText = ""
            leagueAnswerMatch = nil
            leagueCurrentCountry = nextCountry
            leaguePreloadedFlagImage = nextImage
            leagueMatchPhase = .playing
            leagueTypingLockedUntil = Date().addingTimeInterval(0.32)
            try? await Task.sleep(for: .milliseconds(320))
            guard leagueMatchActive, leagueCurrentCountry == nextCountry else { return }
            leagueInputIsLocked = false
            leagueTypingLockedUntil = .distantPast
            leagueCurrentQuestionStartedAt = Date()
            isLeagueAnswerFocused = true
        }
    }
    
    func finishLeagueMatch() {
        guard leagueMatchActive else { return }
        leagueMatchActive = false
        leagueTimerIsRunning = false
        isLeagueAnswerFocused = false
        leagueAutoSubmitTask?.cancel()
        leagueAutoSubmitTask = nil
        leagueTimerStartTask?.cancel()
        leagueTimerStartTask = nil
        leagueCountdownTask?.cancel()
        leagueCountdownTask = nil
        leagueAdvanceTask?.cancel()
        leagueAdvanceTask = nil
        leagueFeedbackClearTask?.cancel()
        leagueFeedbackClearTask = nil
        leagueInputIsLocked = false
        leagueLockedAnswerText = ""
        leagueTypingLockedUntil = .distantPast
        leagueAnswerFeedback = nil
        leagueRevealedCountryName = ""
        leagueMatchPhase = .loading
        
        let opponent = selectedLeagueOpponent
        let preset = selectedLeaguePresetOpponent
        let opponentScore = opponent.map { max($0.leagueBestScore, Int($0.leagueAverageScore.rounded())) } ?? preset.score
        let opponentRating = opponent?.leagueRating ?? preset.rating
        let opponentName = opponent?.displayName ?? L(preset.titleDE, preset.titleEN)
        let ratingBefore = activeProfile.leagueStats?.rating ?? 1000
        let previewResult = LeagueMatchResult(
            id: UUID(),
            date: Date(),
            opponentName: opponentName,
            ownScore: leagueScore,
            opponentScore: opponentScore,
            correct: leagueCorrect,
            wrong: leagueWrong,
            duration: 60,
            answerDetails: leagueAnswerRecords,
            ratingBefore: nil,
            ratingAfter: nil,
            ratingDelta: nil
        )
        var previewStats = activeProfile.leagueStats ?? LeagueStats()
        previewStats.recordMatch(previewResult, opponentRating: opponentRating)
        let ratingAfter = previewStats.rating
        let result = LeagueMatchResult(
            id: previewResult.id,
            date: previewResult.date,
            opponentName: previewResult.opponentName,
            ownScore: previewResult.ownScore,
            opponentScore: previewResult.opponentScore,
            correct: previewResult.correct,
            wrong: previewResult.wrong,
            duration: previewResult.duration,
            answerDetails: previewResult.answerDetails,
            ratingBefore: ratingBefore,
            ratingAfter: ratingAfter,
            ratingDelta: ratingAfter - ratingBefore
        )
        
        leagueSummaryResult = result
        leagueShowsStartMenu = true
        updateActiveProfile { profile in
            profile.recordLeagueMatch(result, opponentRating: opponentRating)
        }
        scheduleOnlineStatsSync()
        submitLiveLeagueScoreIfNeeded(score: leagueScore)
        Haptics.notify(result.didWin ? .success : .warning)
        playLeagueSound(success: result.didWin)
    }
    
    func nextLeagueCountry() -> Country {
        if !leagueLiveCountryCodes.isEmpty {
            let index = min(leagueLiveCountryIndex, leagueLiveCountryCodes.count - 1)
            leagueLiveCountryIndex = min(leagueLiveCountryIndex + 1, leagueLiveCountryCodes.count)
            if let country = availableCountries.first(where: { $0.code == leagueLiveCountryCodes[index] }) {
                return country
            }
        }
        
        let candidates = availableCountries.filter { !leagueRecentCountryCodes.contains($0.code) }
        return (candidates.isEmpty ? availableCountries : candidates).randomElement() ?? allCountries[0]
    }
    
    func submitLiveLeagueScoreIfNeeded(score: Int) {
        guard let matchID = leagueLiveMatchID, !leagueLivePlayerID.isEmpty else { return }
        let playerID = leagueLivePlayerID
        leagueLiveResultText = L("Dein Score ist hochgeladen. Warte auf \(leagueLiveOpponentName) ...", "Your score is uploaded. Waiting for \(leagueLiveOpponentName) ...")
        leagueLivePollTask?.cancel()
        leagueLivePollTask = Task { @MainActor in
            do {
                try await OnlineStatsService.submitLiveLeagueScore(matchID: matchID, playerID: playerID, score: score)
            } catch {
                leagueLiveResultText = L("Live-Score konnte nicht hochgeladen werden: \(OnlineStatsService.userFacingMessage(for: error))", "Live score could not be uploaded: \(OnlineStatsService.userFacingMessage(for: error))")
                return
            }
            
            for _ in 0..<18 {
                guard !Task.isCancelled else { return }
                if let match = try? await OnlineStatsService.fetchLiveLeagueMatch(matchID: matchID),
                   let opponentScore = match.opponentScore(for: playerID) {
                    leagueLiveOpponentScore = opponentScore
                    if score >= opponentScore {
                        leagueLiveResultText = L("Live 1gg1: \(score) : \(opponentScore) gegen \(leagueLiveOpponentName) - Sieg", "Live 1v1: \(score) : \(opponentScore) against \(leagueLiveOpponentName) - win")
                    } else {
                        leagueLiveResultText = L("Live 1gg1: \(score) : \(opponentScore) gegen \(leagueLiveOpponentName) - Niederlage", "Live 1v1: \(score) : \(opponentScore) against \(leagueLiveOpponentName) - loss")
                    }
                    playLeagueSound(success: score >= opponentScore)
                    scheduleLeagueNotification(
                        title: L("Async 1gg1 fertig", "Async 1v1 finished"),
                        body: leagueLiveResultText
                    )
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            
            leagueLiveResultText = L("Live 1gg1: Dein Score \(score) ist gespeichert. \(leagueLiveOpponentName) ist noch nicht fertig.", "Live 1v1: Your score \(score) is saved. \(leagueLiveOpponentName) is not finished yet.")
        }
    }
    
    func evaluateLeagueAnswer(_ value: String) {
        leagueAutoSubmitTask?.cancel()
        let match = bestLeagueAnswerMatch(for: value)
        leagueAnswerMatch = match
        
        guard
            leagueMatchActive,
            let match,
            !leagueInputIsLocked,
            match.isCertain
        else {
            return
        }
        
        let submittedText = value
        leagueAutoSubmitTask = Task { @MainActor in
            await Task.yield()
            guard leagueMatchActive, leagueAnswerText == submittedText, leagueAnswerMatch?.isCertain == true else { return }
            submitLeagueAnswer()
        }
    }
    
    func bestLeagueAnswerMatch(for rawAnswer: String) -> LeagueAnswerMatch? {
        let answer = normalizedLeagueAnswer(rawAnswer)
        guard answer.count >= 2 else { return nil }
        
        let scoredMatches = availableCountries.compactMap { country -> LeagueAnswerMatch? in
            let aliases = leagueAnswerAliases(for: country)
            guard let bestAlias = aliases
                .map({ alias in (name: alias.displayName, normalizedName: alias.normalizedName, score: leagueSimilarity(answer: answer, candidate: alias.normalizedName)) })
                .max(by: { $0.score < $1.score })
            else {
                return nil
            }
            
            guard bestAlias.score >= 0.45 else { return nil }
            return LeagueAnswerMatch(
                country: country,
                matchedName: bestAlias.name,
                normalizedAnswer: answer,
                normalizedMatchedName: bestAlias.normalizedName,
                confidence: bestAlias.score,
                runnerUpConfidence: 0
            )
        }
        .sorted { first, second in
            if first.confidence == second.confidence {
                return localizedCountryName(first.country, language: appLanguage).count < localizedCountryName(second.country, language: appLanguage).count
            }
            return first.confidence > second.confidence
        }
        
        guard let best = scoredMatches.first else { return nil }
        let runnerUp = scoredMatches.dropFirst().first?.confidence ?? 0
        return LeagueAnswerMatch(
            country: best.country,
            matchedName: best.matchedName,
            normalizedAnswer: best.normalizedAnswer,
            normalizedMatchedName: best.normalizedMatchedName,
            confidence: best.confidence,
            runnerUpConfidence: runnerUp
        )
    }
    
    func leagueAnswerAliases(for country: Country) -> [(displayName: String, normalizedName: String)] {
        let rawAliases = [
            localizedCountryName(country, language: appLanguage),
            country.name,
            countryEnglishNameByCode[country.code]
        ].compactMap { $0 } + leagueExtraAliases(for: country)
        
        let aliases = Set(rawAliases.flatMap { name -> [String] in
            let normalized = normalizedLeagueAnswer(name)
            var values = [name]
            if normalized.hasPrefix("vereinigte ") {
                values.append(normalized.replacingOccurrences(of: "vereinigte ", with: ""))
            }
            if normalized.hasPrefix("demokratische republik ") {
                values.append(normalized.replacingOccurrences(of: "demokratische republik ", with: ""))
            }
            if name.contains("("), let prefix = name.split(separator: "(").first {
                values.append(String(prefix))
            }
            return values
        })
        
        return aliases.map { alias in
            (displayName: alias, normalizedName: normalizedLeagueAnswer(alias))
        }
        .filter { !$0.normalizedName.isEmpty }
    }
    
    func leagueExtraAliases(for country: Country) -> [String] {
        switch country.code {
        case "US": return ["USA", "U.S.A.", "America", "United States of America", "Vereinigte Staaten von Amerika"]
        case "GB": return ["UK", "U.K.", "Great Britain", "Britain", "England", "Großbritannien", "Grossbritannien"]
        case "AE": return ["UAE", "Emirates", "VAE"]
        case "BA": return ["Bosnien", "Bosnia"]
        case "BO": return ["Bolivia"]
        case "BN": return ["Brunei Darussalam"]
        case "BY": return ["Weissrussland", "Weißrussland"]
        case "CD": return ["DR Kongo", "Demokratische Republik Kongo", "Kongo Kinshasa", "Congo Kinshasa", "DR Congo"]
        case "CG": return ["Republik Kongo", "Kongo Brazzaville", "Congo Brazzaville"]
        case "CI": return ["Elfenbeinkueste", "Elfenbeinkuste", "Ivory Coast", "Cote d Ivoire", "Côte d'Ivoire"]
        case "CZ": return ["Tschechische Republik", "Czech Republic"]
        case "DO": return ["Dominikanische Rep", "Dominican Rep"]
        case "FM": return ["Micronesia"]
        case "GQ": return ["Equatorial Guinea"]
        case "GW": return ["Guinea Bissau"]
        case "KR": return ["Korea Sued", "Korea Sud", "South Korea", "Republic of Korea"]
        case "KP": return ["Korea Nord", "North Korea"]
        case "LA": return ["Lao", "Laos"]
        case "MD": return ["Moldova"]
        case "MK": return ["Mazedonien", "Macedonia"]
        case "MM": return ["Burma", "Birma"]
        case "PS": return ["Palestine"]
        case "RU": return ["Russian Federation"]
        case "ST": return ["Sao Tome", "São Tomé"]
        case "SZ": return ["Eswatini"]
        case "TL": return ["Timor Leste", "East Timor"]
        case "TR": return ["Turkey"]
        case "TZ": return ["Tanzania"]
        case "VA": return ["Vatican", "Vatikan"]
        case "VN": return ["Viet Nam"]
        case "ZA": return ["South Africa"]
        default: return []
        }
    }
    
    func leagueSimilarity(answer: String, candidate: String) -> Double {
        guard !answer.isEmpty, !candidate.isEmpty else { return 0 }
        if answer == candidate { return 1 }
        if let tokenScore = leagueTokenPrefixSimilarity(answer: answer, candidate: candidate) {
            return tokenScore
        }
        
        let shorterCount = min(answer.count, candidate.count)
        let longerCount = max(answer.count, candidate.count)
        let prefixLength = commonPrefixLength(answer, candidate)
        
        if candidate.hasPrefix(answer), answer.count >= 3 {
            let completeness = Double(answer.count) / Double(candidate.count)
            return min(0.97, 0.80 + completeness * 0.18)
        }
        
        if answer.count < candidate.count, answer.count >= 3 {
            let candidatePrefix = String(candidate.prefix(answer.count))
            let prefixDistance = levenshteinDistance(answer, candidatePrefix, maxDistance: 2)
            if prefixDistance <= 2 {
                let prefixSimilarity = 1 - (Double(prefixDistance) / Double(max(answer.count, candidatePrefix.count)))
                let completeness = Double(answer.count) / Double(candidate.count)
                if prefixSimilarity >= 0.58 {
                    return min(0.96, 0.72 + prefixSimilarity * 0.20 + completeness * 0.08)
                }
            }
        }
        
        if answer.hasPrefix(candidate), candidate.count >= 3 {
            let extraPenalty = Double(answer.count - candidate.count) / Double(max(answer.count, 1))
            return max(0.72, 0.92 - extraPenalty * 0.35)
        }
        
        let maxDistance: Int
        switch longerCount {
        case 0...4:
            maxDistance = 1
        case 5...8:
            maxDistance = 2
        default:
            maxDistance = 3
        }
        
        let distance = levenshteinDistance(answer, candidate, maxDistance: maxDistance)
        guard distance <= maxDistance else { return 0 }
        let similarity = 1 - (Double(distance) / Double(longerCount))
        let prefixBonus = min(Double(prefixLength) / Double(max(shorterCount, 1)), 1) * 0.08
        return min(similarity + prefixBonus, 0.99)
    }
    
    func leagueTokenPrefixSimilarity(answer: String, candidate: String) -> Double? {
        let answerTokens = answer.split(separator: " ").map(String.init)
        let candidateTokens = candidate.split(separator: " ").map(String.init)
        guard answerTokens.count > 1, candidateTokens.count >= answerTokens.count else { return nil }
        
        guard answerTokens.first == candidateTokens.first else { return nil }
        
        var tokenScores: [Double] = []
        for index in answerTokens.indices {
            let answerToken = answerTokens[index]
            let candidateToken = candidateTokens[index]
            
            if candidateToken.hasPrefix(answerToken) {
                tokenScores.append(1)
                continue
            }
            
            guard answerToken.count >= 3 else { return 0 }
            let candidatePrefix = String(candidateToken.prefix(answerToken.count))
            let allowedDistance = answerToken.count >= 4 ? 2 : 1
            let distance = levenshteinDistance(answerToken, candidatePrefix, maxDistance: allowedDistance)
            guard distance <= allowedDistance || hasSameLetters(answerToken, candidatePrefix) else { return 0 }
            
            let score = hasSameLetters(answerToken, candidatePrefix)
                ? 0.78
                : 1 - (Double(distance) / Double(max(answerToken.count, candidatePrefix.count)))
            guard score >= 0.62 else { return 0 }
            tokenScores.append(score)
        }
        
        let averageTokenScore = tokenScores.reduce(0, +) / Double(tokenScores.count)
        let completeness = Double(answer.count) / Double(candidate.count)
        return min(0.98, 0.84 + averageTokenScore * 0.08 + completeness * 0.08)
    }
    
    func hasSameLetters(_ first: String, _ second: String) -> Bool {
        first.count == second.count && first.sorted() == second.sorted()
    }
    
    func commonPrefixLength(_ first: String, _ second: String) -> Int {
        var count = 0
        for (left, right) in zip(first, second) {
            guard left == right else { break }
            count += 1
        }
        return count
    }
    
    func levenshteinDistance(_ first: String, _ second: String, maxDistance: Int) -> Int {
        let firstCharacters = Array(first)
        let secondCharacters = Array(second)
        guard !firstCharacters.isEmpty else { return secondCharacters.count }
        guard !secondCharacters.isEmpty else { return firstCharacters.count }
        if abs(firstCharacters.count - secondCharacters.count) > maxDistance {
            return maxDistance + 1
        }
        
        var previous = Array(0...secondCharacters.count)
        var current = Array(repeating: 0, count: secondCharacters.count + 1)
        
        for firstIndex in 1...firstCharacters.count {
            current[0] = firstIndex
            var rowMinimum = current[0]
            
            for secondIndex in 1...secondCharacters.count {
                let cost = firstCharacters[firstIndex - 1] == secondCharacters[secondIndex - 1] ? 0 : 1
                current[secondIndex] = min(
                    previous[secondIndex] + 1,
                    current[secondIndex - 1] + 1,
                    previous[secondIndex - 1] + cost
                )
                rowMinimum = min(rowMinimum, current[secondIndex])
            }
            
            if rowMinimum > maxDistance {
                return maxDistance + 1
            }
            
            swap(&previous, &current)
        }
        
        return previous[secondCharacters.count]
    }
    
    func normalizedLeagueAnswer(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
    
    var optionsView: some View {
        List {
            Section(L("Vollversion", "Full version")) {
                if fullVersionUnlocked {
                    Label(L("Du hast die Vollversion, Dankeschön!", "You have the full version, thank you!"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(tealAccentColor)
                } else if let product = storeKit.fullVersionProduct {
                    Button {
                        Haptics.tap()
                        Task {
                            await storeKit.purchase(product)
                            fullVersionUnlocked = storeKit.purchasedFullVersion
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Label(L("Vollversion freischalten", "Unlock full version"), systemImage: "lock.open.fill")
                            Spacer()
                            Text(product.displayPrice)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tealAccentColor)
                        }
                    }
                    .disabled(storeKit.isLoading)
                } else {
                    Label(L("Vollversion lädt", "Loading full version"), systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
                
                Button {
                    Haptics.tap()
                    Task {
                        await storeKit.restorePurchases()
                        fullVersionUnlocked = storeKit.purchasedFullVersion
                    }
                } label: {
                    Label(L("Käufe wiederherstellen", "Restore purchases"), systemImage: "arrow.clockwise")
                }
                .disabled(storeKit.isLoading)
            }
            
            Section(L("Sprache", "Language")) {
                Picker(L("Sprache", "Language"), selection: $appLanguageRawValue) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section(L("Theme", "Theme")) {
                Picker(L("Theme", "Theme"), selection: $appThemeRawValue) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(language: appLanguage)).tag(theme.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section(L("Akzentfarbe", "Accent color")) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                    ForEach(AppAccent.allCases) { accent in
                        accentColorButton(for: accent)
                    }
                }
                .padding(.vertical, 4)
            }
            
            Section(L("Flaggen", "Flags")) {
                HStack(spacing: 10) {
                    Toggle(isOn: $includePartiallyRecognizedFlags) {
                        Label(L("Teilweise anerkannte Gebiete", "Partly recognized territories"), systemImage: "checkmark.seal")
                    }
                    
                    infoButton(isPresented: $isDisputedTerritoriesInfoExpanded) {
                        Text(L("Fügt unter anderem Kosovo, Taiwan, Palästina, Westsahara, Cookinseln, Niue, Abchasien, Südossetien, Nordzypern und Somaliland hinzu. Diese Auswahl ist als Lern-Erweiterung gemeint und trifft keine politische Einordnung.", "Adds Kosovo, Taiwan, Palestine, Western Sahara, Cook Islands, Niue, Abkhazia, South Ossetia, Northern Cyprus, and Somaliland. This option is intended as a learning extension and does not make a political classification."))
                    }
                }
            }
            
            Section(L("Online", "Online")) {
                HStack(spacing: 10) {
                    Label(L("Fortschritt online vergleichen", "Compare progress online"), systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                    
                    infoButton(isPresented: $isShowingOnlineInfo) {
                        Text(L("Verbindet Game Center und CloudKit, lädt deine Statistik hoch und zeigt Freunde, Ranglisten und globale Achievement-Werte.", "Connects Game Center and CloudKit, uploads your stats, and shows friends, leaderboards, and global achievement values."))
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(L("Spitzname", "Nickname"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        infoButton(isPresented: $isShowingNicknameInfo) {
                            Text(L("Optional und eindeutig. Freunde können dich darunter finden. Ohne Spitznamen wird dein Game-Center-Name angezeigt.", "Optional and unique. Friends can find you by it. Without a nickname, your Game Center name is shown."))
                        }
                    }
                    
                    HStack(spacing: 10) {
                        Image(systemName: "at")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tealAccentColor)
                            .frame(width: 24)
                        TextField(L("anzeigename", "display name"), text: $onlinePlayerName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(tealAccentColor.opacity(0.24), lineWidth: 1)
                    )
                }
            }
            
            Section(L("Spenden", "Tips")) {
                if storeKit.donationProducts.isEmpty {
                    Label(L("Spenden laden", "Loading tips"), systemImage: "heart")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(storeKit.donationProducts, id: \.id) { product in
                        Button {
                            Haptics.tap()
                            Task {
                                await storeKit.purchase(product)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Label(product.displayName, systemImage: "heart.fill")
                                Spacer()
                                Text(product.displayPrice)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.pink)
                            }
                        }
                        .disabled(storeKit.isLoading)
                    }
                }
            }
            
            if let statusText = storeKit.statusText {
                Section {
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Debug") {
                Toggle(isOn: $debugToolsEnabled) {
                    Label(L("Debug-Werkzeuge", "Debug tools"), systemImage: "ladybug.fill")
                }
                
                if debugToolsEnabled {
                    Toggle(isOn: $fullVersionUnlocked) {
                        Label(L("Vollversion freischalten", "Unlock full version"), systemImage: "lock.open.fill")
                    }
                    
                    Stepper(value: Binding(
                        get: { activeProfile.leagueStats?.rating ?? 1000 },
                        set: { debugSetLeagueRating($0) }
                    ), in: 100...3000, step: 50) {
                        Label("\(L("Liga-ELO", "League ELO")): \(activeProfile.leagueStats?.rating ?? 1000)", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    
                    Button {
                        Haptics.tap()
                        debugResetLeagueStats()
                    } label: {
                        Label(L("Liga-Stats zurücksetzen", "Reset league stats"), systemImage: "arrow.counterclockwise")
                    }
                    
                    Menu {
                        ForEach(MasteryTier.allCases) { tier in
                            Button(tier.rawValue) {
                                Haptics.tap()
                                debugSetAllCountryTiers(tier)
                            }
                        }
                    } label: {
                        Label(L("Alle Flaggen-Stufen setzen", "Set all flag tiers"), systemImage: "slider.horizontal.3")
                    }
                    
                    Button {
                        Haptics.tap()
                        Task { await createTestFriend() }
                    } label: {
                        Label(L("Testfreund erstellen/aktualisieren", "Create/update test friend"), systemImage: "person.crop.circle.badge.plus")
                    }
                    
                    Text(L("Diese Werkzeuge sind nur für Entwicklung und Balancing gedacht und können vor dem Release komplett entfernt werden.", "These tools are only for development and balancing and can be removed before release."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section(L("Daten", "Data")) {
                Button(role: .destructive) {
                    Haptics.tap()
                    isShowingResetConfirmation = true
                } label: {
                    Text(L("Alle lokalen Daten zurücksetzen", "Reset all local data"))
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appBackgroundGradient.ignoresSafeArea())
        .navigationTitle(L("Optionen", "Options"))
        .task {
            guard !fullVersionUnlocked else { return }
            await storeKit.loadProducts()
            fullVersionUnlocked = storeKit.purchasedFullVersion
        }
    }
    
    func accentColorButton(for accent: AppAccent) -> some View {
        let isSelected = appAccent == accent
        let isLocked = !fullVersionUnlocked
        let color = adaptiveColor(light: accent.lightUIColor, dark: accent.darkUIColor)
        
        return Button {
            guard !isLocked else {
                Haptics.notify(.warning)
                return
            }
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                appAccentRawValue = accent.rawValue
            }
        } label: {
            ZStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                    Text(accent.title(language: appLanguage))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                    Spacer(minLength: 0)
                    if isSelected && !isLocked {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    }
                }
                .blur(radius: isLocked ? 3 : 0)
                .opacity(isLocked ? 0.58 : 1)
                
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSelected && !isLocked ? color : panelBackgroundColor, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(isSelected && !isLocked ? .white : .primary)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected && !isLocked ? Color.white.opacity(0.22) : color.opacity(0.28), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    
    func continentButtonGrid(selection: Binding<Set<String>>) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        
        return VStack(spacing: 10) {
            categoryButton(for: CountryScope.worldwide, selection: selection, isWide: true)
            
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(continents, id: \.self) { continent in
                    categoryButton(for: continent, selection: selection)
                }
            }
        }
    }
    
    func categoryButton(for continent: String, selection: Binding<Set<String>>, isWide: Bool = false) -> some View {
        let isSelected = selection.wrappedValue.contains(continent)
        let isLocked = !fullVersionUnlocked && continent != CountryScope.worldwide
        
        return Button {
            guard !isLocked else {
                Haptics.notify(.warning)
                return
            }
            Haptics.tap()
            withAnimation(.easeInOut(duration: 0.18)) {
                togglePracticeContinent(continent, selection: selection)
            }
        } label: {
            HStack(spacing: 10) {
                Text(localizedScope(continent))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 4)
                Text("\(countries(inContinent: continent).count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((isSelected ? Color.white : tealAccentColor).opacity(0.16))
                    .clipShape(Capsule())
                    .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: isWide ? 50 : 56)
            .padding(.horizontal, 12)
            .background(isSelected ? tealAccentColor : panelBackgroundColor)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .opacity(isLocked ? 0.58 : 1)
    }
    
    func togglePracticeContinent(_ continent: String, selection: Binding<Set<String>>) {
        if continent == CountryScope.worldwide {
            selection.wrappedValue = [CountryScope.worldwide]
            return
        }
        
        var selectedContinents = selection.wrappedValue
        selectedContinents.remove(CountryScope.worldwide)
        
        if selectedContinents.contains(continent) {
            selectedContinents.remove(continent)
        } else {
            selectedContinents.insert(continent)
        }
        
        selection.wrappedValue = selectedContinents.isEmpty ? [CountryScope.worldwide] : selectedContinents
    }
    
    func addFriend() {
        let trimmedName = newFriendName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        addFriend(named: trimmedName)
        newFriendName = ""
    }
    
    func addFriend(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        var names = friendNames
        let alreadyExists = names.contains { $0.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }
        if !alreadyExists {
            names.append(trimmedName)
            friendNamesRawValue = names.joined(separator: "|")
        }
    }
    
    func removeFriend(_ friend: String) {
        let names = friendNames.filter { $0 != friend }
        friendNamesRawValue = names.joined(separator: "|")
    }
    
    @MainActor
    func createTestFriend() async {
        guard onlineFeaturesEnabled else { return }
        guard !isSyncingOnlineStats else { return }
        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }
        
        onlineStatusText = L("Erstelle Testfreund ...", "Creating test friend ...")
        do {
            try await OnlineStatsService.createTestFriend(countries: availableCountries)
            addFriend(named: OnlineStatsService.testFriendName)
            onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
            onlineLeaderboardRefreshID += 1
            selectedOnlineScope = .friends
            onlineStatusText = L("Testfreund FlaggenTest erstellt und hinzugefügt.", "Test friend FlaggenTest created and added.")
            Haptics.notify(.success)
        } catch {
            Haptics.notify(.error)
            onlineStatusText = L("Testfreund nicht erstellt: \(OnlineStatsService.userFacingMessage(for: error))", "Test friend not created: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }
    
    @MainActor
    func ensureLeagueTestFriendIfNeeded() async {
        guard onlineFeaturesEnabled, !leagueTestFriendEnsured else { return }
        leagueTestFriendEnsured = true
        
        if !friendNames.contains(where: { normalizedFriendToken($0) == normalizedFriendToken(OnlineStatsService.testFriendName) }) {
            addFriend(named: OnlineStatsService.testFriendName)
        }
        
        guard !onlineLeaderboard.contains(where: { $0.id == OnlineStatsService.testFriendRecordName }) else { return }
        guard !isSyncingOnlineStats else { return }
        
        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }
        
        onlineStatusText = L("Testfreund wird bereitgestellt ...", "Preparing test friend ...")
        do {
            try await OnlineStatsService.createTestFriend(countries: availableCountries)
            onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
            onlineLeaderboardRefreshID += 1
            selectedOnlineScope = .friends
            onlineStatusText = L("Testfreund FlaggenTest ist online und befreundet.", "Test friend FlaggenTest is online and added as friend.")
        } catch {
            onlineStatusText = L("Testfreund nicht bereitgestellt: \(OnlineStatsService.userFacingMessage(for: error))", "Test friend not prepared: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }
    
    func debugSetLeagueRating(_ rating: Int) {
        updateActiveProfile { profile in
            var stats = profile.leagueStats ?? LeagueStats()
            stats.rating = rating
            profile.leagueStats = stats
        }
    }
    
    func debugResetLeagueStats() {
        updateActiveProfile { profile in
            profile.leagueStats = LeagueStats()
        }
        leagueSummaryResult = nil
    }
    
    func debugSetAllCountryTiers(_ tier: MasteryTier) {
        updateActiveProfile { profile in
            let now = Date()
            for country in availableCountries {
                let key = selectedSubject.statsKey(for: country)
                var stats = profile.byCountry[key] ?? CountryStats()
                stats.storedTier = tier
                stats.lastPracticedAt = now
                if tier != .f {
                    stats.lastKnownAt = now
                }
                stats.appendTierHistory(tier: tier, date: now)
                profile.byCountry[key] = stats
            }
        }
    }
    
    func modeHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.largeTitle)
                .bold()
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    func subjectModePickerCard() -> some View {
        HStack(spacing: 10) {
            subjectModeButton(for: .countries)
            subjectModeButton(for: .capitals)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(panelBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tealAccentColor.opacity(0.24), lineWidth: 1)
        )
    }
    
    func subjectModeButton(for subject: LearningSubject) -> some View {
        let isSelected = selectedSubject == subject
        return Button {
            guard selectedSubject != subject else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                selectedSubject = subject
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: subject == .countries ? "flag.fill" : "building.columns.fill")
                    .font(.subheadline.weight(.bold))
                Text(subject.displayTitle(language: appLanguage))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.bold))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 10)
            .background(isSelected ? tealAccentColor : Color.clear)
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(
                RoundedRectangle(cornerRadius: 11)
                    .stroke(isSelected ? Color.white.opacity(0.22) : tealAccentColor.opacity(0.28), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    func subjectGlassSwitcher() -> some View {
        if #available(iOS 26.0, *) {
            subjectGlassSwitcherContent()
                .padding(6)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            subjectGlassSwitcherContent()
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
    }
    
    func subjectGlassSwitcherContent() -> some View {
        GeometryReader { geometry in
            let segmentWidth = max((geometry.size.width - 8) / 2, 0)
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                
                Capsule()
                    .fill(tealAccentColor)
                    .frame(width: segmentWidth, height: 46)
                    .offset(x: selectedSubject == .countries ? 4 : segmentWidth + 4)
                    .shadow(color: tealAccentColor.opacity(0.28), radius: 10, y: 4)
                
                HStack(spacing: 0) {
                    subjectGlassSwitcherButton(for: .countries)
                    subjectGlassSwitcherButton(for: .capitals)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedSubject)
        }
        .frame(maxWidth: 380)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
    }
    
    func subjectGlassSwitcherButton(for subject: LearningSubject) -> some View {
        let isSelected = selectedSubject == subject
        return Button {
            guard selectedSubject != subject else { return }
            dismissStatisticsSearchKeyboard()
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedSubject = subject
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: subject == .countries ? "flag.fill" : "building.columns.fill")
                    .font(.subheadline.weight(.bold))
                Text(subject.title(language: appLanguage))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    func onlineScopeGlassSwitcher() -> some View {
        if #available(iOS 26.0, *) {
            onlineScopeGlassSwitcherContent()
                .padding(6)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            onlineScopeGlassSwitcherContent()
                .padding(6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
        }
    }
    
    func onlineScopeGlassSwitcherContent() -> some View {
        GeometryReader { geometry in
            let segmentWidth = max((geometry.size.width - 8) / 2, 0)
            
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                
                Capsule()
                    .fill(tealAccentColor)
                    .frame(width: segmentWidth, height: 46)
                    .offset(x: selectedOnlineScope == .friends ? 4 : segmentWidth + 4)
                    .shadow(color: tealAccentColor.opacity(0.28), radius: 10, y: 4)
                
                HStack(spacing: 0) {
                    onlineScopeButton(for: .friends)
                    onlineScopeButton(for: .global)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: selectedOnlineScope)
        }
        .frame(maxWidth: 380)
        .frame(height: 54)
        .frame(maxWidth: .infinity)
    }
    
    func onlineScopeButton(for scope: OnlineLeaderboardScope) -> some View {
        let isSelected = selectedOnlineScope == scope
        return Button {
            guard selectedOnlineScope != scope else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                selectedOnlineScope = scope
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: scope == .friends ? "person.2.fill" : "globe.europe.africa.fill")
                    .font(.subheadline.weight(.bold))
                Text(scope == .friends ? L("Freunde", "Friends") : L("Global", "Global"))
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .foregroundStyle(isSelected ? .white : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    @MainActor
    func runStartupWorkAfterFirstRender() async {
        await Task.yield()
        ensureTrainerProfile()
        if !didEnableOnlineByDefault {
            didEnableOnlineByDefault = true
        }
        applyWeeklyTierDecay(showPopup: true)
        if !onlineFeaturesEnabled {
            disableOnlineRuntimeState()
        }
        hideStartupScreenAfterDelay()
    }
    
    func ensureTrainerProfile() {
        if appData.profiles.isEmpty {
            let profile = UserProfile(id: UUID(), name: "Training", pin: "")
            appData.profiles = [profile]
            appData.activeProfileID = profile.id
            saveLocalCache()
        } else if appData.activeProfileID == nil {
            appData.activeProfileID = appData.profiles[0].id
            saveLocalCache()
        }
    }
    
    func updateActiveProfile(_ update: (inout UserProfile) -> Void) {
        ensureTrainerProfile()
        guard let activeProfileID = appData.activeProfileID,
              let index = appData.profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        
        update(&appData.profiles[index])
        saveLocalCache()
    }
    
    func checkForUnlockedAchievements() {
        ensureTrainerProfile()
        guard let activeProfileID = appData.activeProfileID,
              let index = appData.profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        
        let now = Date()
        var alreadyAnnounced = Set(appData.profiles[index].announcedAchievementIDs ?? [])
        var achievedDates = appData.profiles[index].achievedAchievementDates ?? [:]
        let unlockedItems = achievementItems.filter(\.isUnlocked)
        
        for item in unlockedItems {
            let key = achievementAnnouncementID(for: item)
            if achievedDates[key] == nil {
                achievedDates[key] = now
            }
        }
        
        guard let unlockedItem = unlockedItems.first(where: { !alreadyAnnounced.contains(achievementAnnouncementID(for: $0)) }) else {
            appData.profiles[index].achievedAchievementDates = achievedDates
            saveLocalCache()
            return
        }
        
        alreadyAnnounced.insert(achievementAnnouncementID(for: unlockedItem))
        appData.profiles[index].announcedAchievementIDs = Array(alreadyAnnounced).sorted()
        appData.profiles[index].achievedAchievementDates = achievedDates
        saveLocalCache()
        showAchievementPopup(unlockedItem)
    }
    
    func achievementAnnouncementID(for item: AchievementItem) -> String {
        "\(selectedSubject.rawValue)|\(item.id)"
    }
    
    func showAchievementPopup(_ item: AchievementItem) {
        Haptics.notify(.success)
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            achievementPopupItem = item
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard achievementPopupItem?.id == item.id else { return }
            withAnimation(.easeInOut(duration: 0.24)) {
                achievementPopupItem = nil
            }
        }
    }
    
    func authenticateGameCenter(syncAfterAuthentication: Bool = false) {
        guard onlineFeaturesEnabled else {
            disableOnlineRuntimeState()
            return
        }
        
        GKLocalPlayer.local.authenticateHandler = { viewController, error in
            guard onlineFeaturesEnabled else { return }
            
            if let viewController {
                gameCenterAuthPresentation = GameCenterAuthPresentation(viewController: viewController)
                return
            }
            
            if GKLocalPlayer.local.isAuthenticated {
                isGameCenterAuthenticated = true
                gameCenterPlayerID = GKLocalPlayer.local.gamePlayerID
                gameCenterAlias = GKLocalPlayer.local.alias
                gameCenterStatusText = L("Verbunden als \(GKLocalPlayer.local.alias)", "Connected as \(GKLocalPlayer.local.alias)")
                Task {
                    await restoreCloudBackupIfNeeded()
                    await loadGameCenterFriends()
                    if syncAfterAuthentication {
                        await syncOnlineStats()
                    }
                }
            } else {
                isGameCenterAuthenticated = false
                gameCenterPlayerID = ""
                gameCenterAlias = ""
                cloudBackupRestoreAttemptedPlayerID = ""
                gameCenterFriendIDs = []
                gameCenterStatusText = error?.localizedDescription ?? L("Game Center nicht verbunden", "Game Center not connected")
            }
        }
    }
    
    @MainActor
    func loadGameCenterFriends() async {
        guard onlineFeaturesEnabled else {
            gameCenterFriendIDs = []
            return
        }
        guard GKLocalPlayer.local.isAuthenticated else { return }
        do {
            let friends = try await GKLocalPlayer.local.loadFriends()
            gameCenterFriendIDs = Set(friends.map(\.gamePlayerID))
        } catch {
            gameCenterFriendIDs = []
        }
    }
    
    func disableOnlineRuntimeState() {
        isSyncingOnlineStats = false
        isGameCenterAuthenticated = false
        gameCenterPlayerID = ""
        gameCenterAlias = ""
        gameCenterFriendIDs = []
        onlineLeaderboard = []
        selectedOnlineGlobePlayer = nil
        gameCenterAuthPresentation = nil
        gameCenterStatusText = L("Online-Funktionen sind ausgeschaltet", "Online features are turned off")
        onlineStatusText = L("Online-Funktionen sind ausgeschaltet", "Online features are turned off")
    }
    
    func normalizedFriendToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
    
    func applyWeeklyTierDecay(showPopup: Bool = false) {
        var decayChanges: [TierDecayChange] = []
        updateActiveProfile { profile in
            decayChanges = profile.applyWeeklyTierDecay()
        }
        
        if showPopup, !decayChanges.isEmpty {
            selectedTierDecayChangeID = decayChanges.first?.id
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                tierDecayPopup = TierDecayPopup(changes: decayChanges)
            }
        }
    }
    
    func saveLocalCache() {
        AppStorageService.save(appData)
        scheduleOnlineStatsSync()
    }
    
    @MainActor
    func restoreCloudBackupIfNeeded() async {
        guard onlineFeaturesEnabled, isGameCenterAuthenticated, !gameCenterPlayerID.isEmpty else { return }
        guard cloudBackupRestoreAttemptedPlayerID != gameCenterPlayerID else { return }
        cloudBackupRestoreAttemptedPlayerID = gameCenterPlayerID
        
        do {
            guard let cloudData = try await OnlineStatsService.fetchAppDataSnapshot(gameCenterPlayerID: gameCenterPlayerID) else { return }
            let cloudProgress = backupProgressScore(for: cloudData)
            let localProgress = backupProgressScore(for: appData)
            guard cloudProgress > localProgress else { return }
            
            isRestoringCloudBackup = true
            pendingOnlineSyncTask?.cancel()
            appData = cloudData
            AppStorageService.save(appData)
            ensureTrainerProfile()
            recapStartCounts = activeProfile.tierCounts(in: availableCountries)
            recapEndCounts = recapStartCounts
            onlineStatusText = L("Cloud-Statistik wiederhergestellt.", "Cloud stats restored.")
            isRestoringCloudBackup = false
        } catch {
            onlineStatusText = L("Cloud-Backup nicht geladen: \(OnlineStatsService.userFacingMessage(for: error))", "Cloud backup not loaded: \(OnlineStatsService.userFacingMessage(for: error))")
            isRestoringCloudBackup = false
        }
    }
    
    func backupProgressScore(for data: AppData) -> Int {
        var total = 0
        for profile in data.profiles {
            var countryProgress = 0
            for stats in profile.byCountry.values {
                var tierBonus = 0
                switch stats.tier {
                case .s: tierBonus = 30
                case .a: tierBonus = 18
                case .b: tierBonus = 10
                case .c, .d, .f: tierBonus = 0
                }
                countryProgress += stats.attempts
                countryProgress += stats.cardReviews
                countryProgress += stats.showmasterPlayed
                countryProgress += tierBonus
            }
            
            let leaguePlayed = profile.leagueStats?.played ?? 0
            let leagueRating = profile.leagueStats?.rating ?? 1000
            let leagueProgress = leaguePlayed * 25 + max(leagueRating - 1000, 0)
            let practiceProgress = profile.practiceCardsByDay?.values.reduce(0, +) ?? 0
            let achievementProgress = (profile.achievedAchievementDates?.count ?? 0) * 40
            
            total += profile.totalAnswers
            total += practiceProgress
            total += profile.showmasterCards
            total += countryProgress
            total += leagueProgress
            total += achievementProgress
        }
        return total
    }
    
    func scheduleOnlineStatsSync() {
        guard onlineFeaturesEnabled, isGameCenterAuthenticated, !isRestoringCloudBackup else { return }
        pendingOnlineSyncTask?.cancel()
        pendingOnlineSyncTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await syncOnlineStats(showFeedback: false)
        }
    }
    
    func hideStartupScreenAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.45))
            withAnimation(.spring(response: 0.62, dampingFraction: 0.9)) {
                isShowingStartupScreen = false
            }
        }
    }
    
    @MainActor
    func syncOnlineStats(showFeedback: Bool = true) async {
        guard onlineFeaturesEnabled else {
            disableOnlineRuntimeState()
            return
        }
        guard !isSyncingOnlineStats else { return }
        
        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }
        
        onlineStatusText = L("Synchronisiere ...", "Syncing ...")
        do {
            onlineStatusText = L("Lade Statistik hoch ...", "Uploading stats ...")
            try await OnlineStatsService.upload(
                name: onlinePlayerName,
                gameCenterPlayerID: isGameCenterAuthenticated ? gameCenterPlayerID : nil,
                gameCenterAlias: gameCenterAlias,
                appData: appData,
                profile: activeProfile,
                countries: availableCountries,
                subject: selectedSubject,
                achievementIDs: achievementItems.filter(\.isUnlocked).map(\.id)
            )
            onlineStatusText = L("Statistik hochgeladen. Lade Rangliste ...", "Stats uploaded. Loading leaderboard ...")
            
            do {
                onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
                onlineLeaderboardRefreshID += 1
                onlineStatusText = L("Statistik hochgeladen. Rangliste geladen: \(deduplicatedOnlineLeaderboard.count) Spieler", "Stats uploaded. Leaderboard loaded: \(deduplicatedOnlineLeaderboard.count) players")
            } catch {
                onlineStatusText = L("Statistik hochgeladen. Rangliste nicht geladen: \(OnlineStatsService.userFacingMessage(for: error))", "Stats uploaded. Leaderboard not loaded: \(OnlineStatsService.userFacingMessage(for: error))")
            }
            
            Task { await loadGameCenterFriends() }
            if showFeedback {
                Haptics.notify(.success)
            }
        } catch {
            if showFeedback {
                Haptics.notify(.error)
            }
            onlineStatusText = L("Upload fehlgeschlagen: \(OnlineStatsService.userFacingMessage(for: error))", "Upload failed: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }
    
    @MainActor
    func loadOnlineStats(forceRefresh: Bool = false) async {
        guard onlineFeaturesEnabled else {
            disableOnlineRuntimeState()
            return
        }
        guard (forceRefresh || onlineLeaderboard.isEmpty), !isSyncingOnlineStats else { return }
        isSyncingOnlineStats = true
        defer {
            isSyncingOnlineStats = false
        }
        
        do {
            onlineLeaderboard = try await OnlineStatsService.fetchLeaderboard()
            onlineLeaderboardRefreshID += 1
            onlineStatusText = L("Online-Rangliste geladen: \(deduplicatedOnlineLeaderboard.count) Spieler", "Online leaderboard loaded: \(deduplicatedOnlineLeaderboard.count) players")
        } catch {
            onlineStatusText = L("Online-Rangliste nicht geladen: \(OnlineStatsService.userFacingMessage(for: error))", "Online leaderboard not loaded: \(OnlineStatsService.userFacingMessage(for: error))")
        }
    }
    
    func resetAllLocalData() {
        appData = AppData()
        AppStorageService.reset()
        ensureTrainerProfile()
        recapStartCounts = activeProfile.tierCounts(in: availableCountries)
        recapEndCounts = recapStartCounts
        practiceSessionCount = 0
        practiceSessionKnown = 0
        practiceSessionUnknown = 0
        practiceSessionImproved = 0
        practiceSessionResults = []
        practiceSessionChanges = []
        practiceHistoryPreview = nil
        practiceForcedNextCountry = nil
        practiceUndoSnapshot = nil
        practiceSessionActive = false
        practiceCardDragOffset = 0
        practiceCardEntryOffset = 0
        practiceCardEntryOpacity = 1
        isFinishingPracticeSwipe = false
        showSessionActive = false
        showSessionCount = 0
        showRecap = false
        achievementPopupItem = nil
        resetCurrentCardHint()
    }
    
    func nextPracticeCard(entryDirection: CGFloat = 0) {
        let nextCountry = practiceForcedNextCountry ?? nextPracticeCountry()
        practiceForcedNextCountry = nil
        if entryDirection != 0 {
            practiceCardEntryOffset = -58
            practiceCardEntryOpacity = 0
        } else {
            practiceCardEntryOffset = 0
            practiceCardEntryOpacity = 1
        }
        
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            currentCountry = nextCountry
            cardIsFlipped = false
            resetCurrentCardHint()
            practiceHistoryPreview = nil
            practiceCardDragOffset = 0
            isFinishingPracticeSwipe = false
        }
        
        guard entryDirection != 0 else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                practiceCardEntryOffset = 0
                practiceCardEntryOpacity = 1
            }
        }
    }
    
    func startPracticeSession() {
        applyWeeklyTierDecay()
        showRecap = false
        practiceSessionCount = 0
        practiceSessionKnown = 0
        practiceSessionUnknown = 0
        practiceSessionImproved = 0
        practiceSessionResults = []
        practiceSessionChanges = []
        practiceHistoryPreview = nil
        practiceForcedNextCountry = nil
        practiceUndoSnapshot = nil
        practiceSessionSeenCountryCodes = []
        selectedPracticeCardLimit = 10
        recapStartCounts = activeProfile.tierCounts(in: availableCountries)
        recapEndCounts = recapStartCounts
        currentCountry = nextPracticeCountry()
        cardIsFlipped = false
        resetCurrentCardHint()
        practiceHistoryPreview = nil
        practiceCardDragOffset = 0
        practiceCardEntryOffset = 0
        practiceCardEntryOpacity = 1
        isFinishingPracticeSwipe = false
        
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            practiceSessionActive = true
        }
    }
    
    func finishPracticeSession(showSummary: Bool) {
        let availableCodes = Set(availableCountries.map(\.code))
        let completedPerfectFullSession = practiceSessionActive
            && showSummary
            && !availableCodes.isEmpty
            && availableCodes.isSubset(of: practiceSessionSeenCountryCodes)
            && practiceSessionUnknown == 0
            && practiceSessionKnown >= availableCodes.count
        if completedPerfectFullSession {
            updateActiveProfile { profile in
                profile.recordPerfectFullPracticeSession(subject: selectedSubject)
            }
            checkForUnlockedAchievements()
        }
        
        let completedTenBlock = practiceSessionActive && showSummary && selectedPracticeCardLimit == 10 && practiceSessionCount >= 10
        if completedTenBlock {
            updateActiveProfile { profile in
                profile.recordCompletedTenBlock()
            }
            checkForUnlockedAchievements()
        }
        
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            practiceSessionActive = false
            practiceCardDragOffset = 0
            practiceCardEntryOffset = 0
            practiceCardEntryOpacity = 1
            isFinishingPracticeSwipe = false
            recapEndCounts = activeProfile.tierCounts(in: availableCountries)
            showRecap = showSummary && practiceSessionCount > 0
            practiceHistoryPreview = nil
        }
    }
    
    func undoLastPracticeSwipe() {
        guard let snapshot = practiceUndoSnapshot else { return }
        let nextCountryAfterUndo = currentCountry
        appData = snapshot.appData
        saveLocalCache()
        
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            currentCountry = snapshot.currentCountry
            practiceSessionCount = snapshot.practiceSessionCount
            practiceSessionKnown = snapshot.practiceSessionKnown
            practiceSessionUnknown = snapshot.practiceSessionUnknown
            practiceSessionImproved = snapshot.practiceSessionImproved
            practiceSessionResults = snapshot.practiceSessionResults
            practiceSessionChanges = snapshot.practiceSessionChanges
            practiceHistoryPreview = nil
            practiceSessionSeenCountryCodes = snapshot.practiceSessionSeenCountryCodes
            practiceForcedNextCountry = nextCountryAfterUndo
            cardIsFlipped = snapshot.cardIsFlipped
            cardHintIsVisible = snapshot.cardHintIsVisible
            currentCardUsedHint = snapshot.currentCardUsedHint
            hintBlockFeedbackIsVisible = false
            recapEndCounts = snapshot.recapEndCounts
            practiceCardDragOffset = 0
            practiceCardEntryOffset = 0
            practiceCardEntryOpacity = 1
            isFinishingPracticeSwipe = false
            showRecap = false
            practiceSessionActive = true
            practiceUndoSnapshot = nil
        }
    }
    
    func resetShowSession() {
        showSessionActive = false
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        showRecentCountryCodes = []
        showDeckCountryCodes = []
        cardIsFlipped = false
        resetCurrentCardHint()
    }
    
    func startShowSession() {
        showSessionCount = 0
        showSessionEntries = []
        showHistoryPreview = nil
        showRecentCountryCodes = []
        showDeckCountryCodes = []
        resetCurrentCardHint()
        prepareShowCard()
        showSessionActive = true
    }
    
    var miniWorldCupCurrentPlayer: MiniWorldCupPlayer? {
        guard !miniWorldCupActivePlayers.isEmpty else { return nil }
        let index = min(max(miniWorldCupCurrentPlayerIndex, 0), miniWorldCupActivePlayers.count - 1)
        return miniWorldCupActivePlayers[index]
    }
    
    var miniWorldCupEffectiveFlagCount: Int {
        miniWorldCupActivePlayers.count <= 4 ? 1 : miniWorldCupFlagsPerPlayer
    }
    
    var miniWorldCupEffectiveRequiredCorrect: Int {
        min(miniWorldCupRequiredCorrect, miniWorldCupEffectiveFlagCount)
    }
    
    var miniWorldCupTurnRuleText: String {
        L("\(miniWorldCupEffectiveFlagCount) Flagge(n), \(miniWorldCupEffectiveRequiredCorrect) richtig zum Weiterkommen", "\(miniWorldCupEffectiveFlagCount) flag(s), \(miniWorldCupEffectiveRequiredCorrect) correct to advance")
    }
    
    var miniWorldCupQuestionProgressText: String {
        L("Flagge \(miniWorldCupCurrentAttempt)/\(miniWorldCupEffectiveFlagCount) · \(miniWorldCupCurrentCorrect) richtig", "Flag \(miniWorldCupCurrentAttempt)/\(miniWorldCupEffectiveFlagCount) · \(miniWorldCupCurrentCorrect) correct")
    }
    
    var miniWorldCupSwipeColor: Color {
        if miniWorldCupCardDragOffset.width > 24 { return .green }
        if miniWorldCupCardDragOffset.width < -24 { return .red }
        return tealAccentColor
    }
    
    func addMiniWorldCupPlayer() {
        let name = miniWorldCupNewPlayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        guard !miniWorldCupPlayers.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            miniWorldCupNewPlayerName = ""
            return
        }
        miniWorldCupPlayers.append(MiniWorldCupPlayer(name: name))
        miniWorldCupNewPlayerName = ""
    }
    
    func startMiniWorldCup() {
        guard miniWorldCupPlayers.count >= 2 else { return }
        miniWorldCupActivePlayers = miniWorldCupPlayers
        miniWorldCupEliminations = []
        miniWorldCupCurrentPlayerIndex = 0
        miniWorldCupRound = 1
        miniWorldCupCurrentAttempt = 1
        miniWorldCupCurrentCorrect = 0
        miniWorldCupCardDragOffset = .zero
        miniWorldCupAnswerFeedback = nil
        miniWorldCupCurrentCountry = nextMiniWorldCupCountry()
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .handoff
        }
    }
    
    func resetMiniWorldCupToSetup(keepPlayers: Bool) {
        if !keepPlayers {
            miniWorldCupPlayers = []
        }
        miniWorldCupActivePlayers = []
        miniWorldCupEliminations = []
        miniWorldCupCurrentPlayerIndex = 0
        miniWorldCupRound = 1
        miniWorldCupCurrentAttempt = 1
        miniWorldCupCurrentCorrect = 0
        miniWorldCupCardDragOffset = .zero
        miniWorldCupAnswerFeedback = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .setup
        }
    }
    
    func nextMiniWorldCupCountry() -> Country {
        availableCountries.randomElement() ?? allCountries[0]
    }
    
    func finishMiniWorldCupSwipe(width: CGFloat) {
        let threshold: CGFloat = 82
        guard abs(width) >= threshold else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                miniWorldCupCardDragOffset = .zero
            }
            return
        }
        
        handleMiniWorldCupAnswer(known: width > 0)
    }
    
    func handleMiniWorldCupAnswer(known: Bool) {
        guard miniWorldCupPhase == .question, !miniWorldCupActivePlayers.isEmpty, miniWorldCupAnswerFeedback == nil else { return }
        Haptics.tap(style: known ? .medium : .light)
        miniWorldCupAnswerFeedback = known
        
        withAnimation(.easeInOut(duration: 0.18)) {
            miniWorldCupCardDragOffset = CGSize(width: known ? 620 : -620, height: 0)
        }
        
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            finishMiniWorldCupAttempt(known: known)
        }
    }
    
    func finishMiniWorldCupAttempt(known: Bool) {
        guard !miniWorldCupActivePlayers.isEmpty else { return }
        let updatedCorrect = miniWorldCupCurrentCorrect + (known ? 1 : 0)
        let flagCount = miniWorldCupEffectiveFlagCount
        let requiredCorrect = miniWorldCupEffectiveRequiredCorrect
        
        if miniWorldCupCurrentAttempt >= flagCount {
            if updatedCorrect >= requiredCorrect {
                advanceMiniWorldCupCurrentPlayer(correctCount: updatedCorrect)
            } else {
                eliminateMiniWorldCupCurrentPlayer(correctCount: updatedCorrect, flagCount: flagCount)
            }
        } else {
            miniWorldCupCurrentCorrect = updatedCorrect
            miniWorldCupCurrentAttempt += 1
            miniWorldCupCurrentCountry = nextMiniWorldCupCountry()
            miniWorldCupCardDragOffset = .zero
            miniWorldCupAnswerFeedback = nil
        }
    }
    
    func advanceMiniWorldCupCurrentPlayer(correctCount: Int) {
        guard !miniWorldCupActivePlayers.isEmpty else { return }
        miniWorldCupCurrentCorrect = correctCount
        miniWorldCupCurrentPlayerIndex = (miniWorldCupCurrentPlayerIndex + 1) % miniWorldCupActivePlayers.count
        prepareNextMiniWorldCupTurn()
    }
    
    func eliminateMiniWorldCupCurrentPlayer(correctCount: Int, flagCount: Int) {
        guard !miniWorldCupActivePlayers.isEmpty else { return }
        let safeIndex = min(miniWorldCupCurrentPlayerIndex, miniWorldCupActivePlayers.count - 1)
        let eliminated = miniWorldCupActivePlayers.remove(at: safeIndex)
        miniWorldCupEliminations.insert(
            MiniWorldCupElimination(
                playerName: eliminated.name,
                country: miniWorldCupCurrentCountry,
                round: miniWorldCupRound,
                correctCount: correctCount,
                flagCount: flagCount
            ),
            at: 0
        )
        
        if miniWorldCupActivePlayers.count <= 1 {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                miniWorldCupPhase = .finished
                miniWorldCupCardDragOffset = .zero
            }
            return
        }
        
        miniWorldCupCurrentPlayerIndex = safeIndex % miniWorldCupActivePlayers.count
        prepareNextMiniWorldCupTurn()
    }
    
    func prepareNextMiniWorldCupTurn() {
        miniWorldCupRound += 1
        miniWorldCupCurrentAttempt = 1
        miniWorldCupCurrentCorrect = 0
        miniWorldCupCurrentCountry = nextMiniWorldCupCountry()
        miniWorldCupCardDragOffset = .zero
        miniWorldCupAnswerFeedback = nil
        withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
            miniWorldCupPhase = .handoff
        }
    }
    
    func finishPracticeSwipe(translation: CGSize, predictedTranslation: CGSize) {
        guard !isFinishingPracticeSwipe else { return }
        let threshold: CGFloat = 72
        let committedWidth = abs(predictedTranslation.width) > abs(translation.width) ? predictedTranslation.width : translation.width
        let isMostlyHorizontal = abs(committedWidth) > abs(translation.height) * 1.15
        
        guard isMostlyHorizontal, abs(committedWidth) >= threshold else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                practiceCardDragOffset = 0
            }
            return
        }
        
        let isKnown = committedWidth > 0
        if isKnown && currentCardUsedHint {
            showHintKnownBlockedFeedback()
            return
        }
        
        Haptics.tap(style: .medium)
        isFinishingPracticeSwipe = true
        withAnimation(.interpolatingSpring(stiffness: 180, damping: 24)) {
            practiceCardDragOffset = isKnown ? 620 : -620
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            recordPracticeCard(isKnown: isKnown)
        }
    }
    
    func cardLimitTitle(_ limit: Int) -> String {
        limit == 0 ? L("Endlos", "Endless") : L("\(limit) Karten", "\(limit) cards")
    }
    
    func cardLimitSelector(selection: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(cardLimitOptions, id: \.self) { limit in
                let isSelected = selection.wrappedValue == limit
                Button {
                    guard !isSelected else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                        selection.wrappedValue = limit
                    }
                } label: {
                    Text(cardLimitTitle(limit))
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .padding(.horizontal, 6)
                        .background(isSelected ? tealAccentColor : tealAccentColor.opacity(0.10))
                        .foregroundStyle(isSelected ? .white : tealAccentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(isSelected ? Color.white.opacity(0.22) : tealAccentColor.opacity(0.24), lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(tealAccentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tealAccentColor.opacity(0.28), lineWidth: 1)
        )
    }
    
    func sessionProgressText(current: Int, limit: Int, subject: LearningSubject) -> String {
        let displayedCurrent = max(current, 1)
        let unit = subject == .capitals ? L("Länder", "countries") : L("Flaggen", "flags")
        return limit == 0 ? L("\(displayedCurrent) \(unit) · Endlos", "\(displayedCurrent) \(unit) · endless") : "\(displayedCurrent) / \(limit) \(unit)"
    }
    
    func showSessionProgressText() -> String {
        let displayedCurrent = selectedShowCardLimit > 0
            ? min(showSessionCount + 1, selectedShowCardLimit)
            : showSessionCount + 1
        let unit = selectedSubject == .capitals ? L("Land", "country") : L("Flagge", "flag")
        let base = L("\(displayedCurrent). \(unit)", "\(displayedCurrent). \(unit)")
        guard selectedShowCardLimit > 0 else { return base }
        return L("\(base) von \(selectedShowCardLimit)", "\(base) of \(selectedShowCardLimit)")
    }
    
    func nextPracticeCountry() -> Country {
        let candidates = countries(inContinents: selectedPracticeContinents)
        let unseenCandidates = candidates.filter { !practiceSessionSeenCountryCodes.contains($0.code) }
        let availableCandidates = unseenCandidates.isEmpty ? candidates : unseenCandidates
        
        if allPracticeCandidatesAreS(candidates) {
            return decayRiskSortedCountries(from: availableCandidates).first ?? allCountries[0]
        }
        
        let weightedCountries = availableCandidates.flatMap { country in
            Array(repeating: country, count: practiceWeight(for: tier(for: country)))
        }
        
        return (weightedCountries.isEmpty ? availableCandidates : weightedCountries).randomElement() ?? allCountries[0]
    }
    
    func allPracticeCandidatesAreS(_ candidates: [Country]) -> Bool {
        !candidates.isEmpty && candidates.allSatisfy { tier(for: $0) == .s }
    }
    
    func decayRiskSortedCountries(from countries: [Country]) -> [Country] {
        countries.sorted { first, second in
            decayRiskDate(for: first) < decayRiskDate(for: second)
        }
    }
    
    func decayRiskDate(for country: Country) -> Date {
        let countryStats = stats(for: country)
        return countryStats.lastKnownAt ?? countryStats.lastPracticedAt ?? .distantPast
    }
    
    func practiceWeight(for tier: MasteryTier) -> Int {
        switch tier {
        case .f: return 8
        case .d: return 6
        case .c: return 4
        case .b: return 3
        case .a: return 2
        case .s: return 1
        }
    }
    
    func prepareShowCard() {
        withAnimation(.easeInOut(duration: 0.22)) {
            currentCountry = nextShowCountry()
            cardIsFlipped = false
            resetCurrentCardHint()
        }
    }
    
    func nextShowCard() {
        guard !showLimitReached else { return }
        showSessionCount += 1
        showSessionEntries.append(ShowSessionEntry(country: currentCountry))
        updateActiveProfile { profile in
            profile.recordShowmasterCard(country: currentCountry, subject: selectedSubject)
            if showSessionCount == 10 {
                profile.recordCompletedTenBlock()
            }
        }
        checkForUnlockedAchievements()
        
        guard !showLimitReached else { return }
        prepareShowCard()
    }
    
    func nextShowCountry() -> Country {
        let availableCountries = countries(inContinents: selectedShowContinents)
        let next: Country
        if showAvoidsRecentRepeats {
            next = nextFromShowDeck(from: availableCountries, excluding: currentCountry)
        } else {
            next = nextRandomCountry(excluding: currentCountry, from: availableCountries)
        }
        rememberShowCountry(next)
        return next
    }
    
    func nextFromShowDeck(from availableCountries: [Country], excluding country: Country) -> Country {
        let availableCodes = Set(availableCountries.map(\.code))
        showDeckCountryCodes.removeAll { !availableCodes.contains($0) }
        
        if showDeckCountryCodes.isEmpty {
            refillShowDeck(from: availableCountries, excluding: country)
        }
        
        if
            availableCountries.count > 1,
            showDeckCountryCodes.first == country.code,
            let swapIndex = showDeckCountryCodes.firstIndex(where: { $0 != country.code })
        {
            showDeckCountryCodes.swapAt(0, swapIndex)
        }
        
        guard let nextCode = showDeckCountryCodes.first else {
            return nextRandomCountry(excluding: country, from: availableCountries)
        }
        
        showDeckCountryCodes.removeFirst()
        return availableCountries.first { $0.code == nextCode } ?? nextRandomCountry(excluding: country, from: availableCountries)
    }
    
    func refillShowDeck(from availableCountries: [Country], excluding country: Country) {
        var codes = availableCountries.map(\.code).shuffled()
        if
            availableCountries.count > 1,
            codes.first == country.code,
            let swapIndex = codes.firstIndex(where: { $0 != country.code })
        {
            codes.swapAt(0, swapIndex)
        }
        showDeckCountryCodes = codes
    }
    
    func rememberShowCountry(_ country: Country) {
        showRecentCountryCodes.append(country.code)
        if showRecentCountryCodes.count > 8 {
            showRecentCountryCodes.removeFirst(showRecentCountryCodes.count - 8)
        }
    }
    
    func nextRandomCountry(excluding country: Country, in continent: String = CountryScope.worldwide) -> Country {
        nextRandomCountry(excluding: country, from: countries(inContinent: continent))
    }
    
    func nextRandomCountry(excluding country: Country, from availableCountries: [Country]) -> Country {
        var next = availableCountries.randomElement() ?? allCountries[0]
        if availableCountries.count > 1 {
            while next == country {
                next = availableCountries.randomElement() ?? allCountries[0]
            }
        }
        return next
    }
    
    var availableCountries: [Country] {
        includePartiallyRecognizedFlags ? allPracticeCountries : allCountries
    }
    
    func countries(inContinent continent: String) -> [Country] {
        if continent == CountryScope.worldwide {
            return availableCountries
        }
        
        return availableCountries.filter { $0.continent == continent }
    }
    
    func countries(inContinents selectedContinents: Set<String>) -> [Country] {
        if selectedContinents.contains(CountryScope.worldwide) || selectedContinents.isEmpty {
            return availableCountries
        }
        
        return availableCountries.filter { selectedContinents.contains($0.continent) }
    }
    
    func countries(in tier: MasteryTier, continent: String) -> [Country] {
        countries(inContinent: continent)
            .filter { self.tier(for: $0) == tier }
            .sorted { countryName(for: $0) < countryName(for: $1) }
    }
    
    func countries(in tier: MasteryTier, from countries: [Country]) -> [Country] {
        countries
            .filter { self.tier(for: $0) == tier }
            .sorted { countryName(for: $0) < countryName(for: $1) }
    }
    
    func statisticsCountries(in tier: MasteryTier, from countries: [Country]) -> [Country] {
        countries
            .filter { self.tier(for: $0) == tier }
            .sorted { first, second in
                let firstHasBeenSeen = stats(for: first).cardReviews > 0
                let secondHasBeenSeen = stats(for: second).cardReviews > 0
                if firstHasBeenSeen != secondHasBeenSeen {
                    return firstHasBeenSeen
                }
                return countryName(for: first) < countryName(for: second)
            }
    }
    
    func totalSeenFlags(in countries: [Country]) -> Int {
        countries.filter { stats(for: $0).cardReviews > 0 }.count
    }
    
    func totalKnownAtLeastOnceFlags(in countries: [Country]) -> Int {
        countries.filter { stats(for: $0).cardKnown > 0 }.count
    }
    
    func totalCardReviews(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).cardReviews }
    }
    
    func totalCardKnown(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).cardKnown }
    }
    
    func totalCardUnknown(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).cardUnknown }
    }
    
    func aOrBetterCount(in countries: [Country]) -> Int {
        countries.filter { [.s, .a].contains(stats(for: $0).tier) }.count
    }
    
    func sTierCount(in countries: [Country]) -> Int {
        countries.filter { stats(for: $0).tier == .s }.count
    }
    
    func allSTierHeldDays(in countries: [Country], now: Date = Date()) -> Int {
        guard !countries.isEmpty, countries.allSatisfy({ stats(for: $0).tier == .s }) else { return 0 }
        let sStartDates = countries.compactMap { continuousSTierStartDate(for: stats(for: $0)) }
        guard sStartDates.count == countries.count, let allSStartDate = sStartDates.max() else { return 0 }
        
        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: allSStartDate)
        let currentDay = calendar.startOfDay(for: now)
        return max(calendar.dateComponents([.day], from: startDay, to: currentDay).day ?? 0, 0)
    }
    
    func continuousSTierStartDate(for stats: CountryStats) -> Date? {
        guard stats.tier == .s else { return nil }
        let history = (stats.tierHistory ?? []).sorted { $0.date < $1.date }
        guard !history.isEmpty else {
            return stats.lastKnownAt ?? stats.lastPracticedAt
        }
        
        if let lastNonSIndex = history.lastIndex(where: { $0.tier != .s }) {
            return history[(lastNonSIndex + 1)...].first(where: { $0.tier == .s })?.date
        }
        
        return history.first(where: { $0.tier == .s })?.date ?? stats.lastKnownAt ?? stats.lastPracticedAt
    }
    
    func totalShowmasterPlayed(in countries: [Country]) -> Int {
        countries.reduce(0) { $0 + stats(for: $1).showmasterPlayed }
    }
    
    func percent(_ value: Int, of total: Int) -> String {
        guard total > 0 else { return "0.0 %" }
        return String(format: "%.1f %%", Double(value) / Double(total) * 100)
    }
    
    func activateHint() {
        guard !cardHintIsVisible else { return }
        Haptics.tap(style: .medium)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            cardHintIsVisible = true
            currentCardUsedHint = true
            hintBlockFeedbackIsVisible = false
        }
    }
    
    func resetCurrentCardHint() {
        cardHintIsVisible = false
        currentCardUsedHint = false
        hintBlockFeedbackIsVisible = false
    }
    
    func showHintKnownBlockedFeedback() {
        Haptics.notify(.warning)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
            practiceCardDragOffset = 0
            hintBlockFeedbackIsVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
            withAnimation(.easeOut(duration: 0.2)) {
                hintBlockFeedbackIsVisible = false
            }
        }
    }
    
    func hintText(for country: Country) -> String {
        let answer = selectedSubject == .capitals ? capitalName(for: country) : countryName(for: country)
        let firstLetter = answer.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
        let continent = localizedScope(country.continent)
        
        if selectedSubject == .capitals {
            return L("Die Hauptstadt beginnt mit \(firstLetter). Das Land liegt in \(continent).", "The capital starts with \(firstLetter). The country is in \(continent).")
        }
        
        return L("Das Land beginnt mit \(firstLetter) und liegt in \(continent).", "The country starts with \(firstLetter) and is in \(continent).")
    }
    
    func recordPracticeCard(isKnown: Bool) {
        guard practiceSessionActive, !practiceLimitReached else { return }
        let reviewedCountry = currentCountry
        let tierBefore = tier(for: reviewedCountry)
        let tierAfter = isKnown ? tierBefore.promoted : tierBefore.demoted
        practiceUndoSnapshot = PracticeUndoSnapshot(
            appData: appData,
            currentCountry: reviewedCountry,
            practiceSessionCount: practiceSessionCount,
            practiceSessionKnown: practiceSessionKnown,
            practiceSessionUnknown: practiceSessionUnknown,
            practiceSessionImproved: practiceSessionImproved,
            practiceSessionResults: practiceSessionResults,
            practiceSessionChanges: practiceSessionChanges,
            practiceSessionSeenCountryCodes: practiceSessionSeenCountryCodes,
            cardIsFlipped: cardIsFlipped,
            cardHintIsVisible: cardHintIsVisible,
            currentCardUsedHint: currentCardUsedHint,
            recapEndCounts: recapEndCounts
        )
        practiceSessionSeenCountryCodes.insert(reviewedCountry.code)
        updateActiveProfile { profile in
            profile.recordCardReview(country: reviewedCountry, subject: selectedSubject, isKnown: isKnown)
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            practiceSessionCount += 1
            practiceSessionResults.append(isKnown)
            practiceSessionChanges.append(
                PracticeSessionChange(
                    country: reviewedCountry,
                    wasKnown: isKnown,
                    fromTier: tierBefore,
                    toTier: tierAfter
                )
            )
            
            if isKnown {
                practiceSessionKnown += 1
                if tierBefore.promoted != tierBefore {
                    practiceSessionImproved += 1
                }
            } else {
                practiceSessionUnknown += 1
            }
        }
        
        checkForUnlockedAchievements()
        
        if practiceLimitReached {
            finishPracticeSession(showSummary: true)
        } else {
            nextPracticeCard(entryDirection: isKnown ? 1 : -1)
        }
    }
}

enum PracticeHistoryMark: Equatable {
    case known
    case unknown
    case current
    case pending
    case seen
    
    var systemImage: String {
        switch self {
        case .known: return "checkmark"
        case .unknown: return "xmark"
        case .current: return "questionmark"
        case .pending: return "circle"
        case .seen: return "eye.fill"
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct PracticeHistoryBarMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ShowHistoryBarMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct PracticeHistoryBar: View {
    let results: [Bool]
    let changes: [PracticeSessionChange]
    let limit: Int
    let accentColor: Color
    let selectedChangeID: UUID?
    let onSelectChange: (PracticeHistoryPreview) -> Void
    
    private var entries: [(mark: PracticeHistoryMark, change: PracticeSessionChange?)] {
        if limit == 0 {
            return changes.suffix(9).map { change in
                (change.wasKnown ? .known : .unknown, change)
            } + [(.current, nil)]
        }
        
        let total = max(limit, results.count + 1)
        return (0..<total).map { index in
            if index < results.count {
                return (results[index] ? .known : .unknown, index < changes.count ? changes[index] : nil)
            }
            if index == results.count && results.count < total {
                return (.current, nil)
            }
            return (.pending, nil)
        }
    }
    
    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                if let change = entry.change {
                    Button {
                        onSelectChange(PracticeHistoryPreview(change: change, index: index, total: entries.count))
                    } label: {
                        PracticeHistoryPill(mark: entry.mark, accentColor: accentColor, isSelected: selectedChangeID == change.id)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                } else {
                    PracticeHistoryPill(mark: entry.mark, accentColor: accentColor, isSelected: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: results)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Üben Verlauf")
    }
}

struct PracticeHistoryPill: View {
    let mark: PracticeHistoryMark
    let accentColor: Color
    let isSelected: Bool
    
    private var fillColor: Color {
        switch mark {
        case .known: return .green
        case .unknown: return .red
        case .current: return accentColor
        case .pending: return Color(.tertiarySystemFill)
        case .seen: return accentColor.opacity(0.78)
        }
    }
    
    private var iconColor: Color {
        mark == .pending ? .secondary : .white
    }
    
    var body: some View {
        Image(systemName: mark.systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(iconColor)
            .frame(width: 28, height: 28)
            .background(fillColor)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(isSelected ? accentColor : (mark == .pending ? Color.secondary.opacity(0.18) : Color.white.opacity(0.2)), lineWidth: isSelected ? 3 : 1)
            )
            .overlay {
                if isSelected {
                    Circle()
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.2)
                        .padding(3)
                }
            }
            .shadow(color: isSelected ? accentColor.opacity(0.48) : .clear, radius: 8, y: 2)
            .scaleEffect(isSelected ? 1.18 : (mark == .current ? 1.08 : 1))
            .id(mark.systemImage)
            .transition(.scale(scale: 0.72).combined(with: .opacity))
            .animation(.spring(response: 0.26, dampingFraction: 0.58), value: mark)
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: isSelected)
    }
}

struct ShowHistoryBar: View {
    let entries: [ShowSessionEntry]
    let limit: Int
    let accentColor: Color
    let selectedEntryID: UUID?
    let onSelectEntry: (ShowHistoryPreview) -> Void
    
    private var visibleEntries: [ShowSessionEntry] {
        limit == 0 ? Array(entries.suffix(9)) : entries
    }
    
    private var totalSlots: Int {
        limit == 0 ? max(visibleEntries.count + 1, 1) : max(limit, entries.count)
    }
    
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<totalSlots, id: \.self) { index in
                if index < visibleEntries.count {
                    let entry = visibleEntries[index]
                    Button {
                        onSelectEntry(ShowHistoryPreview(entry: entry, index: index, total: totalSlots))
                    } label: {
                        PracticeHistoryPill(mark: .seen, accentColor: accentColor, isSelected: selectedEntryID == entry.id)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                } else if limit == 0 || index == entries.count {
                    PracticeHistoryPill(mark: .current, accentColor: accentColor, isSelected: false)
                } else {
                    PracticeHistoryPill(mark: .pending, accentColor: accentColor, isSelected: false)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.72), value: entries.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Showmaster Verlauf")
    }
}

struct MiniLocationGlobe: View {
    let country: Country
    let accentColor: Color
    @State private var boundaryData: GlobeBoundaryData?
    
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let globeRect = rect.insetBy(dx: 1, dy: 1)
            let circlePath = Path(ellipseIn: globeRect)
            
            context.fill(
                circlePath,
                with: .linearGradient(
                    Gradient(colors: [
                        Color(red: 0.05, green: 0.25, blue: 0.42),
                        Color(red: 0.03, green: 0.13, blue: 0.26)
                    ]),
                    startPoint: CGPoint(x: globeRect.minX, y: globeRect.minY),
                    endPoint: CGPoint(x: globeRect.maxX, y: globeRect.maxY)
                )
            )
            
            context.clip(to: circlePath)
            drawGrid(in: &context, size: size)
            
            guard let boundaryData else {
                drawFallbackFocus(in: &context, size: size)
                return
            }
            
            let center = boundaryData.centroidsByCountryCode[country.code] ?? fallbackCoordinate
            let availableCodes = Set(allPracticeCountries.map(\.code))
            let selectedRings = boundaryData.ringsByCountryCode[country.code] ?? []
            
            for code in availableCodes where code != country.code {
                guard let rings = boundaryData.ringsByCountryCode[code] else { continue }
                for ring in rings {
                    let path = globePath(for: ring, center: center, size: size)
                    context.fill(path, with: .color(Color.white.opacity(0.20)))
                    context.stroke(path, with: .color(Color.white.opacity(0.22)), lineWidth: 0.45)
                }
            }
            
            for ring in selectedRings {
                let path = globePath(for: ring, center: center, size: size)
                context.fill(path, with: .color(accentColor.opacity(0.94)))
                context.stroke(path, with: .color(.white), lineWidth: 1.65)
                context.stroke(path, with: .color(accentColor), lineWidth: 0.75)
            }
            
            context.stroke(circlePath, with: .color(Color.white.opacity(0.46)), lineWidth: 1)
            context.stroke(circlePath, with: .color(accentColor.opacity(0.30)), lineWidth: 2)
        }
        .overlay(alignment: .bottomTrailing) {
            Text(country.code)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(accentColor, in: RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.55), lineWidth: 0.7)
                )
                .offset(x: 3, y: 3)
        }
        .onAppear(perform: loadBoundariesIfNeeded)
        .onChange(of: country.code) { _, _ in
            loadBoundariesIfNeeded()
        }
    }
    
    private var fallbackCoordinate: GlobeCoordinate {
        switch country.continent {
        case "Afrika": return GlobeCoordinate(latitude: 2, longitude: 20)
        case "Asien": return GlobeCoordinate(latitude: 32, longitude: 86)
        case "Europa": return GlobeCoordinate(latitude: 52, longitude: 15)
        case "Nordamerika": return GlobeCoordinate(latitude: 46, longitude: -102)
        case "Ozeanien": return GlobeCoordinate(latitude: -25, longitude: 135)
        case "Südamerika": return GlobeCoordinate(latitude: -16, longitude: -60)
        case partiallyRecognizedCategory: return GlobeCoordinate(latitude: 32, longitude: 35)
        default: return GlobeCoordinate(latitude: 20, longitude: 0)
        }
    }
    
    private func loadBoundariesIfNeeded() {
        if let cachedData = GlobeBoundaryCache.data, GlobeBoundaryCache.source == globeBoundarySource {
            boundaryData = cachedData
            return
        }
        
        guard boundaryData == nil, let url = URL(string: globeBoundaryURLString) else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data, let parsedData = GlobeBoundaryData.parse(data: data) else { return }
            DispatchQueue.main.async {
                GlobeBoundaryCache.source = globeBoundarySource
                GlobeBoundaryCache.data = parsedData
                boundaryData = parsedData
            }
        }.resume()
    }
    
    private func drawFallbackFocus(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(accentColor))
        context.stroke(Path(ellipseIn: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)), with: .color(.white), lineWidth: 1.4)
    }
    
    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        for fraction in [0.25, 0.5, 0.75] {
            var latitudePath = Path()
            latitudePath.addEllipse(in: CGRect(
                x: size.width * 0.08,
                y: size.height * fraction - size.height * 0.035,
                width: size.width * 0.84,
                height: size.height * 0.07
            ))
            context.stroke(latitudePath, with: .color(Color.white.opacity(0.14)), lineWidth: 0.6)
        }
        
        for fraction in [0.32, 0.5, 0.68] {
            var longitudePath = Path()
            longitudePath.addEllipse(in: CGRect(
                x: size.width * fraction - size.width * 0.04,
                y: size.height * 0.08,
                width: size.width * 0.08,
                height: size.height * 0.84
            ))
            context.stroke(longitudePath, with: .color(Color.white.opacity(0.14)), lineWidth: 0.6)
        }
    }
    
    private func globePath(for ring: [GlobeCoordinate], center: GlobeCoordinate, size: CGSize) -> Path {
        var path = Path()
        var isDrawing = false
        
        for coordinate in ring {
            guard let point = projectedPoint(for: coordinate, center: center, size: size) else {
                isDrawing = false
                continue
            }
            
            if isDrawing {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                isDrawing = true
            }
        }
        
        path.closeSubpath()
        return path
    }
    
    private func projectedPoint(for coordinate: GlobeCoordinate, center: GlobeCoordinate, size: CGSize) -> CGPoint? {
        let latitude = coordinate.latitude * .pi / 180
        let longitude = coordinate.longitude * .pi / 180
        let centerLatitude = center.latitude * .pi / 180
        let centerLongitude = center.longitude * .pi / 180
        let deltaLongitude = longitude - centerLongitude
        let visible = sin(centerLatitude) * sin(latitude) + cos(centerLatitude) * cos(latitude) * cos(deltaLongitude)
        
        guard visible >= -0.03 else { return nil }
        
        let radius = min(size.width, size.height) * 0.43
        let x = radius * cos(latitude) * sin(deltaLongitude)
        let y = -radius * (cos(centerLatitude) * sin(latitude) - sin(centerLatitude) * cos(latitude) * cos(deltaLongitude))
        
        return CGPoint(x: size.width / 2 + x, y: size.height / 2 + y)
    }
}

struct StartupScreen: View {
    let language: AppLanguage
    @State private var logoScale: CGFloat = 0.88
    @State private var logoOpacity: Double = 0
    @State private var contentOffset: CGFloat = 24
    @State private var gradientFloatsUp: Bool = false
    
    var tealAccentColor: Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(red: 0.23, green: 0.88, blue: 0.86, alpha: 1)
                : UIColor(red: 0.0, green: 0.62, blue: 0.58, alpha: 1)
        })
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                LinearGradient(
                    colors: [
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.01, green: 0.10, blue: 0.22, alpha: 1)
                                : UIColor(red: 0.56, green: 0.85, blue: 1.00, alpha: 1)
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.00, green: 0.24, blue: 0.22, alpha: 1)
                                : UIColor(red: 0.48, green: 0.94, blue: 0.76, alpha: 1)
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.30, green: 0.13, blue: 0.03, alpha: 1)
                                : UIColor(red: 1.00, green: 0.73, blue: 0.42, alpha: 1)
                        }),
                        Color(UIColor { traitCollection in
                            traitCollection.userInterfaceStyle == .dark
                                ? UIColor(red: 0.03, green: 0.07, blue: 0.26, alpha: 1)
                                : UIColor(red: 0.42, green: 0.64, blue: 1.00, alpha: 1)
                        })
                    ],
                    startPoint: gradientFloatsUp ? .bottomLeading : .topLeading,
                    endPoint: gradientFloatsUp ? .topTrailing : .bottomTrailing
                )
                .frame(width: geometry.size.width, height: geometry.size.height * 1.7)
                .offset(y: gradientFloatsUp ? -geometry.size.height * 0.42 : -geometry.size.height * 0.04)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.45), value: gradientFloatsUp)
            }
            
            VStack(spacing: 18) {
                Image(systemName: "map.fill")
                    .font(.system(size: 104, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: tealAccentColor.opacity(0.35), radius: 22, y: 10)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)
                
                Text("Flaggenbande")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
                    .opacity(logoOpacity)
            }
            .offset(y: contentOffset)
            .padding()
        }
        .onAppear {
            gradientFloatsUp = true
            withAnimation(.spring(response: 0.58, dampingFraction: 0.78)) {
                logoScale = 1
                logoOpacity = 1
                contentOffset = 0
            }
        }
    }
}

struct PracticeRecapView: View {
    let startCounts: [MasteryTier: Int]
    let endCounts: [MasteryTier: Int]
    let known: Int
    let unknown: Int
    let improved: Int
    let changes: [PracticeSessionChange]
    let language: AppLanguage
    let accentColor: Color
    let onRepeat: () -> Void
    let onDismiss: () -> Void
    
    var total: Int { known + unknown }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("Zusammenfassung", "Summary", language: language))
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 10) {
                recapStat(title: localized("Gewusst", "Known", language: language), value: known, color: .green)
                recapStat(title: localized("Nicht gewusst", "Not known", language: language), value: unknown, color: .red)
                recapStat(title: localized("Verbessert", "Improved", language: language), value: improved, color: accentColor)
            }
            
            Text(localized("Unten findest du die Sessionstatistiken und alle Stufenwechsel.", "Below you can see the session stats and every level change.", language: language))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Button {
                onRepeat()
            } label: {
                Text(localized("Weitere 10 üben", "Practice 10 more", language: language))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            
            sessionDetails
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    var sessionDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Sessionstatistiken", "Session stats", language: language))
                .font(.subheadline.weight(.bold))
            
            if changes.isEmpty {
                Text(localized("Keine Stufenwechsel in dieser Session.", "No level changes in this session.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(changes) { change in
                    let didImprove = isImprovement(change)
                    HStack(spacing: 10) {
                        Image(systemName: change.wasKnown ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(change.wasKnown ? .green : .red)
                            .frame(width: 20)
                        Text(localizedCountryName(change.country, language: language))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                        Spacer(minLength: 6)
                        HStack(spacing: 6) {
                            tierBadge(change.fromTier)
                            Image(systemName: didImprove ? "arrow.up.right" : "arrow.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(didImprove ? .green : .secondary)
                            tierBadge(change.toTier)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(recapChangeBackground(for: change), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(didImprove ? Color.green.opacity(0.42) : Color.clear, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    
    func tierBadge(_ tier: MasteryTier) -> some View {
        Text(tier.rawValue)
            .font(.caption.weight(.black))
            .foregroundStyle(.white)
            .frame(width: 26, height: 24)
            .background(tier.color, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
    }
    
    func recapChangeBackground(for change: PracticeSessionChange) -> Color {
        if isImprovement(change) {
            return Color.green.opacity(0.16)
        }
        if isDecline(change) {
            return Color.red.opacity(0.08)
        }
        return Color(.tertiarySystemFill)
    }
    
    func isImprovement(_ change: PracticeSessionChange) -> Bool {
        tierScore(change.toTier) > tierScore(change.fromTier)
    }
    
    func isDecline(_ change: PracticeSessionChange) -> Bool {
        tierScore(change.toTier) < tierScore(change.fromTier)
    }
    
    func tierScore(_ tier: MasteryTier) -> Int {
        switch tier {
        case .f: return 0
        case .d: return 1
        case .c: return 2
        case .b: return 3
        case .a: return 4
        case .s: return 5
        }
    }
    
    func recapStat(title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct FlipCard: View {
    let country: Country
    let isFlipped: Bool
    let hasGoldAura: Bool
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    @State private var auraPulse: Bool = false
    
    func localizedContinent(_ continent: String) -> String {
        switch continent {
        case "Afrika": return localized("Afrika", "Africa", language: language)
        case "Asien": return localized("Asien", "Asia", language: language)
        case "Europa": return localized("Europa", "Europe", language: language)
        case "Nordamerika": return localized("Nordamerika", "North America", language: language)
        case "Ozeanien": return localized("Ozeanien", "Oceania", language: language)
        case "Südamerika": return localized("Südamerika", "South America", language: language)
        default: return continent
        }
    }
    
    var body: some View {
        ZStack {
            if hasGoldAura {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.yellow.opacity(auraPulse ? 0.34 : 0.14))
                    .blur(radius: auraPulse ? 22 : 10)
                    .scaleEffect(auraPulse ? 1.04 : 0.96)
            }
            
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: hasGoldAura ? .yellow.opacity(0.45) : .black.opacity(0.12), radius: hasGoldAura ? 16 : 10, y: 4)
            
            if isFlipped {
                VStack(spacing: 10) {
                    Text(subject == .countries ? localizedCountryName(country, language: language) : capital)
                        .font(.title)
                        .bold()
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                    if subject == .capitals {
                        Text("[\(capitalPronunciation(for: country, capital: capital))]")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                    }
                    if subject == .countries {
                        Text(localizedContinent(country.continent))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 10) {
                        Spacer(minLength: 0)
                        FlagImage(
                            country: country,
                            width: geometry.size.width,
                            height: subject == .capitals ? 198 : 240
                        )
                        if subject == .capitals {
                            Text(localizedCountryName(country, language: language))
                                .font(.title2.bold())
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.75)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .onAppear {
            auraPulse = false
            if hasGoldAura {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    auraPulse = true
                }
            }
        }
        .onChange(of: hasGoldAura) { _, newValue in
            auraPulse = false
            if newValue {
                withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
                    auraPulse = true
                }
            }
        }
    }
}

struct FlagImage: View {
    let country: Country
    let width: CGFloat
    let height: CGFloat
    @State private var image: UIImage?
    @State private var didFailLoading = false
    
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if didFailLoading {
                Image(systemName: "flag.slash")
                    .font(.system(size: min(width, height) * 0.45))
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: country.code) {
            await loadImage()
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = country.flagImageURL else {
            image = nil
            didFailLoading = true
            return
        }
        
        if let cachedImage = FlagImageCache.shared.image(for: url) {
            image = cachedImage
            didFailLoading = false
            return
        }
        
        image = nil
        didFailLoading = false
        do {
            let loadedImage = try await FlagImageCache.shared.loadImage(from: url)
            guard !Task.isCancelled else { return }
            image = loadedImage
        } catch {
            guard !Task.isCancelled else { return }
            didFailLoading = true
        }
    }
}

final class FlagImageCache {
    static let shared = FlagImageCache()
    
    private let cache = NSCache<NSURL, UIImage>()
    private var loadingTasks: [URL: Task<UIImage, Error>] = [:]
    
    private init() {
        cache.countLimit = 220
    }
    
    @MainActor
    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }
    
    @MainActor
    func loadImage(from url: URL) async throws -> UIImage {
        if let cachedImage = image(for: url) {
            return cachedImage
        }
        
        if let task = loadingTasks[url] {
            return try await task.value
        }
        
        let task = Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 8
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
        
        loadingTasks[url] = task
        do {
            let loadedImage = try await task.value
            cache.setObject(loadedImage, forKey: url as NSURL)
            loadingTasks[url] = nil
            return loadedImage
        } catch {
            loadingTasks[url] = nil
            throw error
        }
    }
}

struct ActionButtonStyle: ButtonStyle {
    let color: Color
    var isProminent: Bool = true
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(isEnabled ? 0.95 : 0.35), lineWidth: isProminent ? 0 : 1.4)
            )
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed && isEnabled ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
    
    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled {
            return Color(.tertiarySystemFill)
        }
        return isProminent ? color.opacity(isPressed ? 0.82 : 1) : color.opacity(isPressed ? 0.18 : 0.10)
    }
    
    private var foregroundColor: Color {
        if !isEnabled {
            return .secondary
        }
        return isProminent ? .white : color
    }
}

struct TierScoreRow: Identifiable {
    var id: String { tier.rawValue }
    let tier: MasteryTier
    let count: Int
    let value: Double
}

struct ScopeScoreRow: Identifiable {
    var id: String { title }
    let title: String
    let score: Double
    let practiced: Int
    let total: Int
}

struct PracticeBalanceRow: Identifiable {
    var id: String { title }
    let title: String
    let count: Int
    let color: Color
}

struct ScoreHistoryPoint: Identifiable {
    var id: String { "\(date.timeIntervalSince1970)-\(score)" }
    let date: Date
    let score: Double
}

struct MasteryScoreCard: View {
    let score: Double
    let rows: [TierScoreRow]
    let language: AppLanguage
    let accentColor: Color
    @Binding var isInfoPresented: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            ScoreRingView(score: score, color: accentColor)
                .frame(width: 92, height: 92)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(localized("Flaggenboss-Score", "Flaggenboss score", language: language))
                        .font(.headline)
                    Button {
                        isInfoPresented.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isInfoPresented) {
                        scoreInfoView
                    }
                }
                
                Text(String(format: "%.1f", score * 100))
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(accentColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
    }
    
    var scoreInfoView: some View {
        let totalCards = rows.reduce(0) { $0 + $1.count }
        let weightedPoints = rows.reduce(0.0) { $0 + ($1.value * 100 * Double($1.count)) }
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "function")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 32, height: 32)
                    .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Berechnung", "Calculation", language: language))
                        .font(.headline)
                    Text(localized("Stufenpunkte geteilt durch alle Karten", "Tier points divided by all cards", language: language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(localized("Formel", "Formula", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                
                Text("(S x 100 + A x 80 + B x 60 + C x 40 + D x 20 + F x 0) / \(max(totalCards, 1))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 7) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Text(row.tier.rawValue)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 22)
                            .background(row.tier.color, in: RoundedRectangle(cornerRadius: 5))
                        
                        Text(row.tier.description)
                            .font(.caption)
                            .foregroundStyle(.primary)
                        
                        Spacer(minLength: 8)
                        
                        Text(String(format: "%.0f x %d", row.value * 100, row.count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Divider()
            
            HStack {
                Text(localized("Ergebnis", "Result", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f / %d = %.1f", weightedPoints, max(totalCards, 1), score * 100))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(accentColor)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}

struct ScoreRingView: View {
    let score: Double
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(score, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))

        }
    }
}

struct TierValueBreakdownChart: View {
    let rows: [TierScoreRow]
    let totalCards: Int
    let language: AppLanguage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Stufenwert-Verteilung", "Tier value distribution", language: language))
                .font(.subheadline.weight(.semibold))
            ForEach(rows) { row in
                let share = totalCards == 0 ? 0 : Double(row.count) / Double(totalCards)
                HStack(spacing: 10) {
                    Text(row.tier.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 24)
                        .background(row.tier.color, in: RoundedRectangle(cornerRadius: 5))
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(row.tier.color.opacity(0.12))
                            RoundedRectangle(cornerRadius: 6)
                                .fill(row.tier.color.opacity(0.68))
                                .frame(width: max(geometry.size.width * share, row.count == 0 ? 0 : 8))
                        }
                    }
                    .frame(height: 12)
                    Text("\(row.count)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                    Text(String(format: "%.2f", row.value))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct ScopeScoreBarChart: View {
    let rows: [ScopeScoreRow]
    let language: AppLanguage
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Score nach Bereich", "Score by scope", language: language))
                .font(.subheadline.weight(.semibold))
            if rows.isEmpty {
                Text(localized("Keine Bereiche im aktuellen Filter.", "No scopes in the current filter.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.1f %%", row.score * 100))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(accentColor)
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.secondary.opacity(0.12))
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(accentColor.opacity(0.70))
                                    .frame(width: geometry.size.width * min(max(row.score, 0), 1))
                            }
                        }
                        .frame(height: 10)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct PracticeBalanceChart: View {
    let rows: [PracticeBalanceRow]
    let language: AppLanguage
    
    var total: Int { rows.reduce(0) { $0 + $1.count } }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Trainings-Balance", "Practice balance", language: language))
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 12) {
                ForEach(rows) { row in
                    VStack(spacing: 7) {
                        GeometryReader { geometry in
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(row.color.opacity(row.count == 0 ? 0.18 : 0.75))
                                    .frame(height: max(8, geometry.size.height * barShare(for: row)))
                            }
                        }
                        .frame(height: 96)
                        Text("\(row.count)")
                            .font(.caption.monospacedDigit().weight(.bold))
                        Text(row.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    func barShare(for row: PracticeBalanceRow) -> Double {
        guard let maxCount = rows.map(\.count).max(), maxCount > 0 else { return 0 }
        return Double(row.count) / Double(maxCount)
    }
}

struct FlaggenbossScoreChart: View {
    let points: [ScoreHistoryPoint]
    let language: AppLanguage
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Flaggenboss")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let latest = points.last {
                    Text(String(format: "%.1f", latest.score * 100))
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(accentColor)
                }
            }
            if points.isEmpty {
                Text(localized("Noch keine Änderungen im Verlauf.", "No score changes yet.", language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
            } else {
                Canvas { context, size in
                    let plotRect = CGRect(x: 34, y: 10, width: max(size.width - 46, 1), height: max(size.height - 44, 1))
                    let axisColor = Color.secondary.opacity(0.24)
                    let gridColor = Color.secondary.opacity(0.10)
                    
                    for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                        let y = plotRect.maxY - plotRect.height * fraction
                        var gridPath = Path()
                        gridPath.move(to: CGPoint(x: plotRect.minX, y: y))
                        gridPath.addLine(to: CGPoint(x: plotRect.maxX, y: y))
                        context.stroke(gridPath, with: .color(gridColor), lineWidth: 1)
                    }
                    
                    var axisPath = Path()
                    axisPath.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
                    axisPath.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
                    axisPath.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
                    context.stroke(axisPath, with: .color(axisColor), lineWidth: 1)
                    
                    let resolvedPoints = chartPoints(in: plotRect)
                    guard let first = resolvedPoints.first, let last = resolvedPoints.last else { return }
                    let smoothLine = smoothPath(for: resolvedPoints)
                    
                    var areaPath = smoothLine
                    areaPath.addLine(to: CGPoint(x: last.x, y: plotRect.maxY))
                    areaPath.addLine(to: CGPoint(x: first.x, y: plotRect.maxY))
                    areaPath.closeSubpath()
                    context.fill(areaPath, with: .linearGradient(
                        Gradient(colors: [accentColor.opacity(0.34), accentColor.opacity(0.07)]),
                        startPoint: CGPoint(x: plotRect.midX, y: plotRect.minY),
                        endPoint: CGPoint(x: plotRect.midX, y: plotRect.maxY)
                    ))
                    context.stroke(smoothLine, with: .color(accentColor), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))
                    
                    let latestRect = CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: latestRect), with: .color(accentColor))
                    
                    drawAxisLabel("100", at: CGPoint(x: 13, y: plotRect.minY - 6), context: &context)
                    drawAxisLabel("50", at: CGPoint(x: 18, y: plotRect.midY - 6), context: &context)
                    drawAxisLabel("0", at: CGPoint(x: 24, y: plotRect.maxY - 10), context: &context)
                }
                .frame(height: 178)
                
                VStack(spacing: 6) {
                    HStack {
                        if let first = points.first {
                            Text(dayLabel(for: first.date))
                        }
                        Spacer()
                        Text(localized("Änderungstage", "change days", language: language))
                        Spacer()
                        if let last = points.last {
                            Text(dayLabel(for: last.date))
                        }
                    }
                    if points.count > 2 {
                        Text(points.map { dayLabel(for: $0.date) }.joined(separator: " · "))
                            .lineLimit(2)
                            .minimumScaleFactor(0.72)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    func chartPoints(in rect: CGRect) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        guard let firstDate = points.first?.date, let lastDate = points.last?.date else { return [] }
        let totalInterval = max(lastDate.timeIntervalSince(firstDate), 1)
        return points.map { point in
            let xFraction = points.count == 1 ? 1 : point.date.timeIntervalSince(firstDate) / totalInterval
            let yFraction = min(max(point.score, 0), 1)
            return CGPoint(
                x: rect.minX + rect.width * xFraction,
                y: rect.maxY - rect.height * yFraction
            )
        }
    }
    
    func smoothPath(for points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let controlDistance = (current.x - previous.x) * 0.42
            let control1 = CGPoint(x: previous.x + controlDistance, y: previous.y)
            let control2 = CGPoint(x: current.x - controlDistance, y: current.y)
            path.addCurve(to: current, control1: control1, control2: control2)
        }
        return path
    }
    
    func drawAxisLabel(_ text: String, at point: CGPoint, context: inout GraphicsContext) {
        context.draw(
            Text(text)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary),
            at: point,
            anchor: .leading
        )
    }
    
    func dayLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .german ? "de_DE" : "en_US")
        formatter.dateFormat = "dd.MM"
        return formatter.string(from: date)
    }
}

struct TierSummaryGrid: View {
    let profile: UserProfile
    let countries: [Country]
    let subject: LearningSubject
    var selectedTier: MasteryTier? = nil
    var onSelectTier: ((MasteryTier) -> Void)? = nil
    
    var body: some View {
        let counts = tierCounts()
        VStack(spacing: 10) {
            ForEach(MasteryTier.allCases) { tier in
                if let onSelectTier {
                    Button {
                        onSelectTier(tier)
                    } label: {
                        tierBar(tier: tier, count: counts[tier] ?? 0)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                } else {
                    tierBar(tier: tier, count: counts[tier] ?? 0)
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    func tierCounts() -> [MasteryTier: Int] {
        Dictionary(uniqueKeysWithValues: MasteryTier.allCases.map { tier in
            (tier, countries.filter { profile.tier(for: $0, subject: subject) == tier }.count)
        })
    }
    
    func tierBar(tier: MasteryTier, count: Int) -> some View {
        let percentage = countries.isEmpty ? 0 : Double(count) / Double(countries.count)
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(tier.rawValue)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 30)
                    .background(tier.color, in: RoundedRectangle(cornerRadius: 7))
                
                Text("Stufe \(tier.rawValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Spacer(minLength: 8)
                
                Text("\(count) · \(percent(percentage))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tier.color.opacity(0.10 + percentage * 0.18))
                    
                    RoundedRectangle(cornerRadius: 7)
                        .fill(tier.color.opacity(0.58))
                        .frame(width: max(geometry.size.width * percentage, count == 0 ? 0 : 8))
                }
            }
            .frame(height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(selectedTier == tier ? tier.color.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectedTier == tier ? tier.color.opacity(0.45) : Color.clear, lineWidth: 1)
        )
    }
    
    func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}

struct GlobeSceneView: UIViewRepresentable {
    let countries: [Country]
    let tiersByCountryCode: [String: MasteryTier]
    let resetToken: Int
    let onSelectCountryCode: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectCountryCode: onSelectCountryCode)
    }
    
    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.backgroundColor = .clear
        sceneView.allowsCameraControl = false
        context.coordinator.configure(sceneView)
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        tapGesture.require(toFail: panGesture)
        sceneView.addGestureRecognizer(tapGesture)
        sceneView.addGestureRecognizer(panGesture)
        sceneView.addGestureRecognizer(pinchGesture)
        return sceneView
    }
    
    func updateUIView(_ sceneView: SCNView, context: Context) {
        context.coordinator.onSelectCountryCode = onSelectCountryCode
        context.coordinator.resetIfNeeded(token: resetToken)
        context.coordinator.updateCountries(countries, tiersByCountryCode: tiersByCountryCode)
    }
    
    final class Coordinator: NSObject {
        var onSelectCountryCode: (String) -> Void
        private weak var sceneView: SCNView?
        private let globeNode = SCNNode()
        private let borderNode = SCNNode()
        private let globeMaterial = SCNMaterial()
        private let cameraNode = SCNNode()
        private var boundaryData: GlobeBoundaryData?
        private var currentCountries: [Country] = []
        private var currentTiersByCountryCode: [String: MasteryTier] = [:]
        private var didStartLoadingBoundaries = false
        private var cameraDistance: Float = 3.2
        private var lastResetToken: Int = 0
        private let minimumCameraDistance: Float = 1.65
        private let maximumCameraDistance: Float = 4.8
        private var globeOrientation = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0))
        private var previousTrackballVector: SIMD3<Float>?
        private var inertiaAxis = SIMD3<Float>(0, 1, 0)
        private var inertiaAngularVelocity: Float = 0
        private var lastPanTimestamp: TimeInterval?
        private var inertiaDisplayLink: CADisplayLink?
        
        init(onSelectCountryCode: @escaping (String) -> Void) {
            self.onSelectCountryCode = onSelectCountryCode
        }
        
        func configure(_ sceneView: SCNView) {
            self.sceneView = sceneView
            
            let scene = SCNScene()
            sceneView.scene = scene
            
            cameraNode.camera = SCNCamera()
            cameraNode.camera?.zNear = 0.01
            cameraNode.camera?.zFar = 100
            scene.rootNode.addChildNode(cameraNode)
            sceneView.pointOfView = cameraNode
            applyGermanyFocus(animated: false)
            
            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.intensity = 650
            scene.rootNode.addChildNode(ambientLight)
            
            let directionalLight = SCNNode()
            directionalLight.light = SCNLight()
            directionalLight.light?.type = .directional
            directionalLight.light?.intensity = 500
            directionalLight.eulerAngles = SCNVector3(-0.6, 0.5, 0)
            scene.rootNode.addChildNode(directionalLight)
            
            let sphere = SCNSphere(radius: 1)
            sphere.segmentCount = 160
            globeMaterial.diffuse.contents = UIColor(red: 0.03, green: 0.19, blue: 0.32, alpha: 1)
            globeMaterial.emission.contents = UIColor(red: 0.0, green: 0.07, blue: 0.11, alpha: 1)
            globeMaterial.specular.contents = UIColor.white.withAlphaComponent(0.34)
            globeMaterial.shininess = 0.55
            sphere.firstMaterial = globeMaterial
            
            globeNode.geometry = sphere
            globeNode.addChildNode(borderNode)
            globeNode.addChildNode(makeAtmosphereNode())
            scene.rootNode.addChildNode(globeNode)
            
            loadBoundariesIfNeeded()
        }
        
        func updateCountries(_ countries: [Country], tiersByCountryCode: [String: MasteryTier]) {
            currentCountries = countries
            currentTiersByCountryCode = tiersByCountryCode
            rebuildGlobeTexture()
        }
        
        private func makeAtmosphereNode() -> SCNNode {
            let atmosphere = SCNSphere(radius: 1.018)
            atmosphere.segmentCount = 160
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.28, green: 0.86, blue: 0.92, alpha: 0.16)
            material.emission.contents = UIColor(red: 0.10, green: 0.42, blue: 0.52, alpha: 0.20)
            material.transparency = 0.32
            material.blendMode = .add
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            atmosphere.firstMaterial = material
            return SCNNode(geometry: atmosphere)
        }
        
        func resetIfNeeded(token: Int) {
            guard token != lastResetToken else { return }
            lastResetToken = token
            stopInertia()
            inertiaAngularVelocity = 0
            previousTrackballVector = nil
            cameraDistance = 3.2
            applyGermanyFocus(animated: true)
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let sceneView else { return }
            let location = gesture.location(in: sceneView)
            let hitResults = sceneView.hitTest(location, options: [:])
            
            for result in hitResults {
                guard result.node == globeNode || result.node.parent == globeNode else { continue }
                let coordinate = coordinate(from: result.localCoordinates)
                if let countryCode = countryCode(containing: coordinate) {
                    onSelectCountryCode(countryCode)
                    return
                }
            }
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let timestamp = CACurrentMediaTime()
            let currentVector = trackballVector(for: gesture.location(in: view), in: view.bounds.size)
            
            switch gesture.state {
            case .began:
                stopInertia()
                inertiaAngularVelocity = 0
                previousTrackballVector = currentVector
                lastPanTimestamp = timestamp
            case .changed:
                guard let previousTrackballVector else { return }
                let deltaTime = max(Float(timestamp - (lastPanTimestamp ?? timestamp)), 0.001)
                if let rotation = rotation(from: previousTrackballVector, to: currentVector) {
                    apply(rotation: rotation, animated: false)
                    inertiaAxis = rotation.axis
                    inertiaAngularVelocity = min(rotation.angle / deltaTime, 12)
                }
                self.previousTrackballVector = currentVector
                lastPanTimestamp = timestamp
            case .ended, .cancelled, .failed:
                previousTrackballVector = nil
                lastPanTimestamp = nil
                startInertiaIfNeeded()
            default:
                break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            stopInertia()
            let scale = max(Float(gesture.scale), 0.01)
            cameraDistance = min(max(cameraDistance / scale, minimumCameraDistance), maximumCameraDistance)
            cameraNode.position = SCNVector3(0, 0, cameraDistance)
            gesture.scale = 1
        }
        
        @objc private func handleInertiaFrame(_ displayLink: CADisplayLink) {
            let deltaTime = Float(displayLink.targetTimestamp - displayLink.timestamp)
            let angle = inertiaAngularVelocity * deltaTime
            if angle > 0.0001 {
                apply(rotation: simd_quatf(angle: angle, axis: inertiaAxis), animated: false)
            }
            
            inertiaAngularVelocity *= pow(0.92, deltaTime * 60)
            if inertiaAngularVelocity < 0.08 {
                stopInertia()
            }
        }
        
        private func startInertiaIfNeeded() {
            guard inertiaAngularVelocity > 1.2 else { return }
            stopInertia()
            let displayLink = CADisplayLink(target: self, selector: #selector(handleInertiaFrame(_:)))
            displayLink.add(to: .main, forMode: .common)
            inertiaDisplayLink = displayLink
        }
        
        private func stopInertia() {
            inertiaDisplayLink?.invalidate()
            inertiaDisplayLink = nil
        }
        
        private func apply(rotation: simd_quatf, animated: Bool) {
            globeOrientation = rotation * globeOrientation
            let changes = {
                self.globeNode.simdOrientation = self.globeOrientation
            }
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.28
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes()
                SCNTransaction.commit()
            } else {
                changes()
            }
        }
        
        private func trackballVector(for point: CGPoint, in size: CGSize) -> SIMD3<Float> {
            let dimension = max(Float(min(size.width, size.height)), 1)
            var x = Float((2 * point.x - size.width) / CGFloat(dimension))
            var y = Float((size.height - 2 * point.y) / CGFloat(dimension))
            let lengthSquared = x * x + y * y
            if lengthSquared > 1 {
                let length = sqrt(lengthSquared)
                x /= length
                y /= length
                return SIMD3<Float>(x, y, 0)
            }
            return SIMD3<Float>(x, y, sqrt(1 - lengthSquared))
        }
        
        private func rotation(from start: SIMD3<Float>, to end: SIMD3<Float>) -> simd_quatf? {
            let axis = simd_cross(start, end)
            let axisLength = simd_length(axis)
            let clampedDot = min(max(simd_dot(start, end), -1), 1)
            guard axisLength > 0.0001 else {
                return clampedDot < -0.999 ? simd_quatf(angle: .pi, axis: fallbackAxis(for: start)) : nil
            }
            return simd_quatf(angle: acos(clampedDot), axis: axis / axisLength)
        }
        
        private func fallbackAxis(for vector: SIMD3<Float>) -> SIMD3<Float> {
            let reference = abs(vector.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            return simd_normalize(simd_cross(vector, reference))
        }
        
        private func applyGermanyFocus(animated: Bool) {
            let europeLatitude = Float(52.0 * .pi / 180)
            let europeLongitude = Float(12.0 * .pi / 180)
            let longitudeRotation = simd_quatf(angle: -europeLongitude, axis: SIMD3<Float>(0, 1, 0))
            let latitudeRotation = simd_quatf(angle: europeLatitude, axis: SIMD3<Float>(1, 0, 0))
            globeOrientation = latitudeRotation * longitudeRotation
            
            let changes = {
                self.globeNode.simdOrientation = self.globeOrientation
                self.cameraNode.position = SCNVector3(0, 0, self.cameraDistance)
                self.cameraNode.eulerAngles = SCNVector3Zero
                self.sceneView?.pointOfView = self.cameraNode
            }
            
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.32
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                changes()
                SCNTransaction.commit()
            } else {
                changes()
            }
        }
        
        private func loadBoundariesIfNeeded() {
            guard !didStartLoadingBoundaries else { return }
            didStartLoadingBoundaries = true
            
            if let cachedData = GlobeBoundaryCache.data, GlobeBoundaryCache.source == globeBoundarySource {
                boundaryData = cachedData
                rebuildGlobeTexture()
                rebuildBoundaries()
                return
            }
            
            guard let url = URL(string: globeBoundaryURLString) else { return }
            
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, let boundaryData = GlobeBoundaryData.parse(data: data) else { return }
                DispatchQueue.main.async {
                    GlobeBoundaryCache.source = globeBoundarySource
                    GlobeBoundaryCache.data = boundaryData
                    self.boundaryData = boundaryData
                    self.rebuildGlobeTexture()
                    self.rebuildBoundaries()
                }
            }.resume()
        }
        
        private func rebuildBoundaries() {
            borderNode.childNodes.forEach { $0.removeFromParentNode() }
            guard let boundaryData else { return }
            
            let borderMaterial = SCNMaterial()
            borderMaterial.diffuse.contents = UIColor.white.withAlphaComponent(0.78)
            borderMaterial.emission.contents = UIColor.white.withAlphaComponent(0.28)
            borderMaterial.lightingModel = .constant
            
            for ring in boundaryData.rings {
                guard ring.count > 1 else { continue }
                let vertices = ring.map { position(for: $0, radius: 1.006) }
                let source = SCNGeometrySource(vertices: vertices)
                var indices: [Int32] = []
                for index in 0..<(vertices.count - 1) {
                    indices.append(Int32(index))
                    indices.append(Int32(index + 1))
                }
                let element = SCNGeometryElement(indices: indices, primitiveType: .line)
                let geometry = SCNGeometry(sources: [source], elements: [element])
                geometry.materials = [borderMaterial]
                borderNode.addChildNode(SCNNode(geometry: geometry))
            }
        }
        
        private func rebuildGlobeTexture() {
            guard let boundaryData else { return }
            let size = CGSize(width: 4096, height: 2048)
            let renderer = UIGraphicsImageRenderer(size: size)
            
            let image = renderer.image { context in
                UIColor(red: 0.03, green: 0.19, blue: 0.32, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                
                for country in currentCountries {
                    guard let countryRings = boundaryData.ringsByCountryCode[country.code] else { continue }
                    let tier = currentTiersByCountryCode[country.code] ?? .f
                    tier.globeUIColor.setFill()
                    
                    for ring in countryRings {
                        let path = texturePath(for: ring, in: size)
                        path.fill()
                    }
                }
            }
            
            globeMaterial.diffuse.contents = image
        }
        
        private func texturePath(for ring: [GlobeCoordinate], in size: CGSize) -> UIBezierPath {
            let path = UIBezierPath()
            for (index, coordinate) in ring.enumerated() {
                let point = texturePoint(for: coordinate, in: size)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            path.close()
            return path
        }
        
        private func texturePoint(for coordinate: GlobeCoordinate, in size: CGSize) -> CGPoint {
            let x = (coordinate.longitude + 180) / 360 * size.width
            let y = (90 - coordinate.latitude) / 180 * size.height
            return CGPoint(x: x, y: y)
        }
        
        private func position(for coordinate: GlobeCoordinate, radius: Double) -> SCNVector3 {
            let latitude = coordinate.latitude * .pi / 180
            let longitude = coordinate.longitude * .pi / 180
            let x = radius * cos(latitude) * sin(longitude)
            let y = radius * sin(latitude)
            let z = radius * cos(latitude) * cos(longitude)
            return SCNVector3(Float(x), Float(y), Float(z))
        }
        
        private func coordinate(from position: SCNVector3) -> GlobeCoordinate {
            let x = Double(position.x)
            let y = Double(position.y)
            let z = Double(position.z)
            let radius = max(sqrt(x * x + y * y + z * z), 0.0001)
            let latitude = asin(y / radius) * 180 / .pi
            let longitude = atan2(x, z) * 180 / .pi
            return GlobeCoordinate(latitude: latitude, longitude: longitude)
        }
        
        private func countryCode(containing coordinate: GlobeCoordinate) -> String? {
            guard let boundaryData else { return nil }
            let availableCodes = Set(currentCountries.map(\.code))
            
            for countryCode in availableCodes {
                guard let rings = boundaryData.ringsByCountryCode[countryCode] else { continue }
                if rings.contains(where: { ringContains(coordinate, ring: $0) }) {
                    return countryCode
                }
            }
            
            return nil
        }
        
        private func ringContains(_ coordinate: GlobeCoordinate, ring: [GlobeCoordinate]) -> Bool {
            guard ring.count > 2 else { return false }
            var isInside = false
            var previous = ring[ring.count - 1]
            
            for current in ring {
                let crossesLatitude = (current.latitude > coordinate.latitude) != (previous.latitude > coordinate.latitude)
                if crossesLatitude {
                    let longitudeAtLatitude = (previous.longitude - current.longitude) * (coordinate.latitude - current.latitude) / (previous.latitude - current.latitude) + current.longitude
                    if coordinate.longitude < longitudeAtLatitude {
                        isInside.toggle()
                    }
                }
                previous = current
            }
            
            return isInside
        }
    }
}

private let globeBoundarySource = "ne_50m_admin_0_map_units"
private let globeBoundaryURLString = "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_50m_admin_0_map_units.geojson"

private enum GlobeBoundaryCache {
    static var source: String?
    static var data: GlobeBoundaryData?
}

private struct GlobeCoordinate {
    let latitude: Double
    let longitude: Double
}

private struct GlobeBoundaryData {
    let rings: [[GlobeCoordinate]]
    let ringsByCountryCode: [String: [[GlobeCoordinate]]]
    let centroidsByCountryCode: [String: GlobeCoordinate]
    
    static func parse(data: Data) -> GlobeBoundaryData? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let features = root["features"] as? [[String: Any]]
        else {
            return nil
        }
        
        var rings: [[GlobeCoordinate]] = []
        var ringsByCountryCode: [String: [[GlobeCoordinate]]] = [:]
        var centroidsByCountryCode: [String: GlobeCoordinate] = [:]
        
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any] else { continue }
            let featureRings = parseRings(from: geometry)
            rings.append(contentsOf: featureRings)
            
            if
                let properties = feature["properties"] as? [String: Any],
                let countryCode = normalizedCountryCode(from: properties),
                let centroid = centroid(from: featureRings)
            {
                ringsByCountryCode[countryCode, default: []].append(contentsOf: featureRings)
                centroidsByCountryCode[countryCode] = centroid
            }
        }
        
        return GlobeBoundaryData(rings: rings, ringsByCountryCode: ringsByCountryCode, centroidsByCountryCode: centroidsByCountryCode)
    }
    
    private static func parseRings(from geometry: [String: Any]) -> [[GlobeCoordinate]] {
        guard let type = geometry["type"] as? String else { return [] }
        
        if type == "Polygon", let polygons = geometry["coordinates"] as? [[[Double]]] {
            return polygons.map { parseRing($0) }.filter { !$0.isEmpty }
        }
        
        if type == "MultiPolygon", let multiPolygons = geometry["coordinates"] as? [[[[Double]]]] {
            return multiPolygons.flatMap { polygon in
                polygon.map { parseRing($0) }.filter { !$0.isEmpty }
            }
        }
        
        return []
    }
    
    private static func parseRing(_ rawRing: [[Double]]) -> [GlobeCoordinate] {
        rawRing.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            return GlobeCoordinate(latitude: pair[1], longitude: pair[0])
        }
    }
    
    static func centroid(from rings: [[GlobeCoordinate]]) -> GlobeCoordinate? {
        let allCoordinates = rings.flatMap { $0 }
        guard !allCoordinates.isEmpty else { return nil }
        let latitude = allCoordinates.reduce(0) { $0 + $1.latitude } / Double(allCoordinates.count)
        let longitude = allCoordinates.reduce(0) { $0 + $1.longitude } / Double(allCoordinates.count)
        return GlobeCoordinate(latitude: latitude, longitude: longitude)
    }
    
    private static func normalizedCountryCode(from properties: [String: Any]) -> String? {
        let codeCandidates = [
            properties["ISO_A2"] as? String,
            properties["iso_a2"] as? String,
            properties["ISO_A2_EH"] as? String,
            properties["iso_a2_eh"] as? String,
            properties["WB_A2"] as? String,
            properties["ADM0_A3"] as? String,
            properties["adm0_a3"] as? String,
            properties["ADM0_ISO"] as? String,
            properties["adm0_iso"] as? String,
            properties["GU_A3"] as? String,
            properties["gu_a3"] as? String,
            properties["SU_A3"] as? String,
            properties["su_a3"] as? String,
            properties["SOV_A3"] as? String,
            properties["sov_a3"] as? String
        ].compactMap { $0?.uppercased() }
        
        if let rawCode = codeCandidates.first(where: { !$0.isEmpty && $0 != "-99" }) {
            switch rawCode {
            case "XK", "XKX": return "XK"
            case "GBR", "ENG", "SCT", "WLS", "NIR": return "GB"
            case "FRA": return "FR"
            case "NOR": return "NO"
            case "GRL": return "GL"
            case "FRO": return "FO"
            case "COK": return "CK"
            case "NIU": return "NU"
            case "ABK": return "AB"
            case "SOO": return "OS"
            case "CYN": return "NC"
            case "SOL": return "SLD"
            default:
                if rawCode.count == 2 { return rawCode }
            }
        }
        
        let nameCandidates = [
            properties["NAME"] as? String,
            properties["name"] as? String,
            properties["NAME_LONG"] as? String,
            properties["name_long"] as? String,
            properties["ADMIN"] as? String,
            properties["admin"] as? String
        ].compactMap { $0?.lowercased() }
        
        if nameCandidates.contains(where: { $0.contains("united kingdom") || $0 == "england" || $0 == "scotland" || $0 == "wales" || $0.contains("northern ireland") }) { return "GB" }
        if nameCandidates.contains(where: { $0.contains("france") }) { return "FR" }
        if nameCandidates.contains(where: { $0.contains("norway") }) { return "NO" }
        if nameCandidates.contains(where: { $0.contains("greenland") }) { return "GL" }
        if nameCandidates.contains(where: { $0.contains("faroe") }) { return "FO" }
        if nameCandidates.contains(where: { $0.contains("cook islands") }) { return "CK" }
        if nameCandidates.contains(where: { $0.contains("niue") }) { return "NU" }
        if nameCandidates.contains(where: { $0.contains("abkhazia") }) { return "AB" }
        if nameCandidates.contains(where: { $0.contains("south ossetia") }) { return "OS" }
        if nameCandidates.contains(where: { $0.contains("northern cyprus") || $0.contains("n. cyprus") }) { return "NC" }
        if nameCandidates.contains(where: { $0.contains("somaliland") }) { return "SLD" }
        
        return nil
    }
}

private extension MasteryTier {
    var globeUIColor: UIColor {
        switch self {
        case .s: return UIColor(red: 0.18, green: 0.42, blue: 0.95, alpha: 1)
        case .a: return UIColor(red: 0.18, green: 0.78, blue: 0.32, alpha: 1)
        case .b: return UIColor(red: 0.0, green: 0.78, blue: 0.62, alpha: 1)
        case .c: return UIColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1)
        case .d: return UIColor(red: 0.95, green: 0.45, blue: 0.14, alpha: 1)
        case .f: return UIColor(red: 0.9, green: 0.18, blue: 0.22, alpha: 1)
        }
    }
}

struct OnlinePlayerStatsRow: View {
    let rank: Int
    let stats: OnlinePlayerStats
    let language: AppLanguage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("#\(rank)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text(stats.playerName)
                    .font(.headline)
                Spacer()
                Text(percent(stats.accuracy))
                    .font(.headline)
                    .foregroundStyle(.green)
            }
            
            HStack(spacing: 10) {
                Text(localized("Geübt: \(stats.totalPracticed)", "Practiced: \(stats.totalPracticed)", language: language))
                Text(localized("Gewusst: \(stats.known)", "Known: \(stats.known)", language: language))
                Text("Showmaster: \(stats.showmasterPlayed)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            Text("S \(stats.tierS) · A \(stats.tierA) · B \(stats.tierB) · C \(stats.tierC) · D \(stats.tierD) · F \(stats.tierF)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
}

struct LeagueLeaderboardRow: View {
    let player: OnlinePlayerStats
    let isCurrentPlayer: Bool
    let language: AppLanguage
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrentPlayer ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                .font(.title3)
                .foregroundStyle(isCurrentPlayer ? .green : .secondary)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(localized("\(player.leaguePlayed) Spiele · \(player.leagueWins) Siege", "\(player.leaguePlayed) matches · \(player.leagueWins) wins", language: language))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.leagueRating)")
                    .font(.subheadline.monospacedDigit().weight(.bold))
                Text(Self.leagueTitle(for: player.leagueRating))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
    
    static func leagueTitle(for rating: Int) -> String {
        let league: String
        switch rating {
        case ..<800: league = "Bronze"
        case 800..<1100: league = "Silber"
        case 1100..<1400: league = "Gold"
        case 1400..<1700: league = "Platin"
        case 1700..<2000: league = "Meister"
        default: league = "Legende"
        }
        
        let position = max(rating, 100) % 300
        let division: String
        switch position {
        case 0..<100: division = "III"
        case 100..<200: division = "II"
        default: division = "I"
        }
        
        return "\(league) \(division)"
    }
}

struct AchievementPopup: View {
    let item: AchievementItem
    let language: AppLanguage
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trophy.fill")
                .font(.headline)
                .foregroundStyle(item.tint)
                .frame(width: 30, height: 30)
                .background(item.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(localized("Achievement erreicht", "Achievement unlocked", language: language))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(item.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(item.tint.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }
}

struct AchievementRow: View {
    let item: AchievementItem
    let language: AppLanguage
    var achievedAt: Date? = nil
    var globalUnlockCount: Int? = nil
    var globalPlayerCount: Int? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isUnlocked ? "checkmark.seal.fill" : item.iconName)
                .font(.title3)
                .foregroundStyle(item.isUnlocked ? item.tint : .secondary)
                .frame(width: 34, height: 34)
                .background((item.isUnlocked ? item.tint : Color.secondary).opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.headline)
                    Spacer()
                    Text("\(min(item.currentValue, item.targetValue))/\(item.targetValue)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.isUnlocked ? item.tint : .secondary)
                }
                
                Text(item.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if item.isUnlocked, let achievedAt {
                    Label(
                        localized("Erreicht: \(achievementDateText(achievedAt))", "Unlocked: \(achievementDateText(achievedAt))", language: language),
                        systemImage: "calendar.badge.checkmark"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.tint)
                }
                
                if let globalUnlockCount, let globalPlayerCount, globalPlayerCount > 0 {
                    Label(
                        localized("Weltweit: \(globalUnlockPercent(globalUnlockCount, globalPlayerCount))", "Worldwide: \(globalUnlockPercent(globalUnlockCount, globalPlayerCount))", language: language),
                        systemImage: "globe.europe.africa.fill"
                    )
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.16))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(item.tint.opacity(item.isUnlocked ? 0.85 : 0.58))
                            .frame(width: max(geometry.size.width * item.progress, item.currentValue == 0 ? 0 : 8))
                    }
                }
                .frame(height: 8)
            }
        }
        .padding(.vertical, 6)
        .opacity(item.isUnlocked ? 1 : 0.72)
    }
    
    func globalUnlockPercent(_ count: Int, _ total: Int) -> String {
        guard total > 0 else { return "0 %" }
        return String(format: "%.0f %%", min(max(Double(count) / Double(total), 0), 1) * 100)
    }
    
    func achievementDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language == .german ? "de_DE" : "en_US")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct StatRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

struct FreeTierCountryRow: View {
    let country: Country
    let stats: CountryStats
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    let accentColor: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                FlagImage(country: country, width: 32, height: 22)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizedCountryName(country, language: language))
                        .font(.headline)
                    if subject == .capitals {
                        Text(capital)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Text(localized("Stufe \(stats.tier.rawValue)", "Level \(stats.tier.rawValue)", language: language))
                    .font(.headline)
                    .foregroundStyle(stats.tier.color)
            }
            
            ZStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(subject == .capitals ? localized("Hauptstadt gesehen: \(stats.cardReviews)", "Capital seen: \(stats.cardReviews)", language: language) : localized("Gesehen: \(stats.cardReviews)", "Seen: \(stats.cardReviews)", language: language))
                    Text(subject == .capitals ? localized("Hauptstadt gewusst: \(stats.cardKnown)", "Capital known: \(stats.cardKnown)", language: language) : localized("Gewusst: \(stats.cardKnown)", "Known: \(stats.cardKnown)", language: language))
                    Text(localized("Verlauf und Detailwerte", "History and detailed values", language: language))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .blur(radius: 4)
                .opacity(0.48)
                
                Label(localized("Details", "Details", language: language), systemImage: "lock.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}

struct STierHistorySparkline: View {
    let values: [Int]
    let maxValue: Int
    let accentColor: Color
    
    var body: some View {
        Canvas { context, size in
            let samples = values.isEmpty ? [0] : values
            let maxY = max(maxValue, samples.max() ?? 1, 1)
            let stepX = samples.count > 1 ? size.width / CGFloat(samples.count - 1) : 0
            let points = samples.enumerated().map { index, value in
                let x = CGFloat(index) * stepX
                let normalized = CGFloat(value) / CGFloat(maxY)
                let y = size.height - (normalized * max(size.height - 4, 1)) - 2
                return CGPoint(x: x, y: y)
            }
            
            var fillPath = Path()
            fillPath.move(to: CGPoint(x: 0, y: size.height))
            for point in points {
                fillPath.addLine(to: point)
            }
            fillPath.addLine(to: CGPoint(x: size.width, y: size.height))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(accentColor.opacity(0.12)))
            
            var linePath = Path()
            if let first = points.first {
                linePath.move(to: first)
                for point in points.dropFirst() {
                    linePath.addLine(to: point)
                }
            }
            context.stroke(linePath, with: .color(accentColor.opacity(0.85)), lineWidth: 2)
        }
        .overlay(alignment: .topLeading) {
            Text("S")
                .font(.caption2.weight(.bold))
                .foregroundStyle(accentColor)
        }
        .accessibilityHidden(true)
    }
}

struct SLevelBar: View {
    let value: Int
    let total: Int
    let accentColor: Color
    
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.16))
                Capsule()
                    .fill(accentColor.opacity(0.82))
                    .frame(width: max(geometry.size.width * progress, value == 0 ? 0 : 8))
            }
        }
        .accessibilityHidden(true)
    }
}

struct ComparisonStatRow: View {
    let title: String
    let ownValue: String
    let otherValue: String
    let otherName: String
    let language: AppLanguage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localized("Du", "You", language: language))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(ownValue)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(otherName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(otherValue)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TierHistoryView: View {
    let stats: CountryStats
    let language: AppLanguage
    
    private let tierOrder: [MasteryTier] = [.s, .a, .b, .c, .d, .f]
    
    var visibleHistory: [TierHistoryEntry] {
        let storedHistory = stats.tierHistory ?? []
        let history = storedHistory.isEmpty ? [TierHistoryEntry(date: stats.lastPracticedAt ?? Date(), tier: stats.tier)] : storedHistory
        return Array(oneEntryPerDay(from: history).suffix(10))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("Verlauf", "History", language: language))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Canvas { context, size in
                let leftPadding: CGFloat = 26
                let rightPadding: CGFloat = 6
                let topPadding: CGFloat = 8
                let bottomPadding: CGFloat = 20
                let graphWidth = max(size.width - leftPadding - rightPadding, 1)
                let graphHeight = max(size.height - topPadding - bottomPadding, 1)
                let entries = visibleHistory
                
                for (index, tier) in tierOrder.enumerated() {
                    let y = yPosition(for: tier, top: topPadding, height: graphHeight)
                    var gridPath = Path()
                    gridPath.move(to: CGPoint(x: leftPadding, y: y))
                    gridPath.addLine(to: CGPoint(x: size.width - rightPadding, y: y))
                    context.stroke(gridPath, with: .color(.secondary.opacity(0.16)), lineWidth: 1)
                    
                    let label = Text(tier.rawValue)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(tier.color)
                    context.draw(label, at: CGPoint(x: 9, y: y), anchor: .center)
                    
                    if index == tierOrder.count - 1 {
                        var axisPath = Path()
                        axisPath.move(to: CGPoint(x: leftPadding, y: topPadding))
                        axisPath.addLine(to: CGPoint(x: leftPadding, y: topPadding + graphHeight))
                        axisPath.addLine(to: CGPoint(x: size.width - rightPadding, y: topPadding + graphHeight))
                        context.stroke(axisPath, with: .color(.secondary.opacity(0.32)), lineWidth: 1)
                    }
                }
                
                let points = entries.enumerated().map { index, entry in
                    CGPoint(
                        x: xPosition(for: index, count: entries.count, left: leftPadding, width: graphWidth),
                        y: yPosition(for: entry.tier, top: topPadding, height: graphHeight)
                    )
                }
                
                if points.count > 1 {
                    var linePath = Path()
                    linePath.move(to: points[0])
                    for point in points.dropFirst() {
                        linePath.addLine(to: point)
                    }
                    context.stroke(linePath, with: .color(.primary.opacity(0.72)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                
                for (index, entry) in entries.enumerated() {
                    let point = points[index]
                    let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: rect), with: .color(entry.tier.color))
                    
                    if index == 0 || index == entries.count - 1 || entries.count <= 4 {
                        let dateLabel = Text(shortDate(entry.date))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.secondary)
                        context.draw(dateLabel, at: CGPoint(x: point.x, y: size.height - 6), anchor: .center)
                    }
                }
            }
            .frame(height: 118)
            .padding(.vertical, 4)
        }
        .padding(.top, 2)
    }
    
    func xPosition(for index: Int, count: Int, left: CGFloat, width: CGFloat) -> CGFloat {
        guard count > 1 else { return left + width / 2 }
        return left + width * CGFloat(index) / CGFloat(count - 1)
    }
    
    func yPosition(for tier: MasteryTier, top: CGFloat, height: CGFloat) -> CGFloat {
        let index = tierOrder.firstIndex(of: tier) ?? tierOrder.count - 1
        return top + height * CGFloat(index) / CGFloat(max(tierOrder.count - 1, 1))
    }
    
    func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = language == .german ? Locale(identifier: "de_DE") : Locale(identifier: "en_US")
        formatter.dateFormat = "d.M."
        return formatter.string(from: date)
    }
    
    func oneEntryPerDay(from history: [TierHistoryEntry]) -> [TierHistoryEntry] {
        let calendar = Calendar.current
        let sortedHistory = history.sorted { $0.date < $1.date }
        var entriesByDay: [String: TierHistoryEntry] = [:]
        
        for entry in sortedHistory {
            let components = calendar.dateComponents([.year, .month, .day], from: entry.date)
            let dayKey = "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
            entriesByDay[dayKey] = entry
        }
        
        return entriesByDay.values.sorted { $0.date < $1.date }
    }
}

struct CompactCountryStatsRow: View {
    let country: Country
    let stats: CountryStats
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    
    var hasBeenSeen: Bool { stats.cardReviews > 0 }
    
    var body: some View {
        HStack(spacing: 10) {
            FlagImage(country: country, width: 34, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(localizedCountryName(country, language: language))
                    .font(.headline)
                if subject == .capitals {
                    Text(capital)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(stats.tier.rawValue)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 28)
                .background(stats.tier.color, in: RoundedRectangle(cornerRadius: 7))
            
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(hasBeenSeen ? 1 : 0.46)
    }
}

struct CountryStatsRow: View {
    let country: Country
    let stats: CountryStats
    let language: AppLanguage
    let subject: LearningSubject
    let capital: String
    var showsHeader: Bool = true
    
    var hasBeenSeen: Bool { stats.cardReviews > 0 }
    var cardAccuracyText: String { hasBeenSeen ? percent(stats.cardAccuracy) : "-" }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showsHeader {
                HStack {
                    FlagImage(country: country, width: 32, height: 22)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedCountryName(country, language: language))
                            .font(.headline)
                        if subject == .capitals {
                            Text(capital)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Text(localized("Stufe \(stats.tier.rawValue)", "Level \(stats.tier.rawValue)", language: language))
                        .font(.headline)
                        .foregroundStyle(stats.tier.color)
                }
                
                Text(localizedContinent(country.continent))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                if subject == .capitals {
                    Text(localized("Hauptstadt gesehen: \(stats.cardReviews)", "Capital seen: \(stats.cardReviews)", language: language))
                    Text(localized("Hauptstadt gewusst: \(stats.cardKnown)", "Capital known: \(stats.cardKnown)", language: language))
                    Text(localized("Hauptstadt nicht gewusst: \(stats.cardUnknown)", "Capital not known: \(stats.cardUnknown)", language: language))
                    Text(localized("Im Showmaster gespielt: \(stats.showmasterPlayed)", "Played in Showmaster: \(stats.showmasterPlayed)", language: language))
                    Text(localized("Hauptstadt-Quote: \(cardAccuracyText)", "Capital known rate: \(cardAccuracyText)", language: language))
                } else {
                    Text(localized("Gesehen: \(stats.cardReviews)", "Seen: \(stats.cardReviews)", language: language))
                    Text(localized("Gewusst: \(stats.cardKnown)", "Known: \(stats.cardKnown)", language: language))
                    Text(localized("Nicht gewusst: \(stats.cardUnknown)", "Not known: \(stats.cardUnknown)", language: language))
                    Text(localized("Im Showmaster gespielt: \(stats.showmasterPlayed)", "Played in Showmaster: \(stats.showmasterPlayed)", language: language))
                    Text(localized("Gewusst-Quote: \(cardAccuracyText)", "Known rate: \(cardAccuracyText)", language: language))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            
            TierHistoryView(stats: stats, language: language)
        }
        .padding(.vertical, 4)
        .opacity(hasBeenSeen ? 1 : 0.46)
    }
    
    func localizedContinent(_ continent: String) -> String {
        switch continent {
        case "Afrika": return localized("Afrika", "Africa", language: language)
        case "Asien": return localized("Asien", "Asia", language: language)
        case "Europa": return localized("Europa", "Europe", language: language)
        case "Nordamerika": return localized("Nordamerika", "North America", language: language)
        case "Ozeanien": return localized("Ozeanien", "Oceania", language: language)
        case "Südamerika": return localized("Südamerika", "South America", language: language)
        default: return continent
        }
    }
    
    func percent(_ value: Double) -> String {
        String(format: "%.1f %%", value * 100)
    }
    func seconds(_ value: Double?) -> String {
        guard let value else { return "-" }
        return String(format: "%.2f s", value)
    }
}
