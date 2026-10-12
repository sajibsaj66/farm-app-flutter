import '../models/farm_module.dart';

/// Extra fictional livestock records so every screen has at least ten. They
/// follow the app's rules: animals lost or sold are marked Dead or Sold,
/// payments never exceed what is owed, and every illness case has a
/// consistent lifecycle.
void addDemoExtras(Map<String, List<Map<String, dynamic>>> m, String Function(int daysAgo) d, String Function({int years, int months}) ago) {
  void add(String module, List<Map<String, dynamic>> rows) {
    m.putIfAbsent(module, () => []).addAll(rows);
  }

  const shona = 'AN-1001 · Shona';
  const lali = 'AN-1005 · Lali';
  const kali = 'AN-1006 · Kali';
  const mohini = 'AN-1007 · Mohini';
  const sundori = 'AN-1008 · Sundori';
  const doli = 'AN-1010 · Doli';
  String at(int daysAgo, String time) => '${d(daysAgo)} $time';

  add(FarmModule.locations, [
    {'id': 'LC-10', 'name': 'Feed Store', 'kind': 'Store', 'capacity': '', 'area': '600 sq ft', 'notes': '', 'status': 'Active'},
  ]);

  add(FarmModule.animals, [
    {
      'id': 'AN-1007',
      'name': 'Mohini',
      'tag': 'BD-1007',
      'species': 'Buffalo',
      'type': 'Cow',
      'breed': 'Murrah',
      'sex': 'Female',
      'dob': ago(years: 6),
      'group': 'Dry cows',
      'initialWeight': '460',
      'weight': '480',
      'status': 'Dry',
      'location': 'Shed B',
      'sire': '',
      'dam': '',
      'source': 'Purchased',
      'purchaseDate': ago(years: 1, months: 2),
      'purchasePrice': '160000',
      'notes': ''
    },
    {
      'id': 'AN-1008',
      'name': 'Sundori',
      'tag': 'BD-1008',
      'species': 'Cattle',
      'type': 'Heifer',
      'breed': 'Sahiwal Cross',
      'sex': 'Female',
      'dob': ago(years: 1, months: 8),
      'group': 'Heifers',
      'initialWeight': '120',
      'weight': '240',
      'status': 'Active',
      'location': 'Shed B',
      'sire': 'BULL-009 · Tiger',
      'dam': '',
      'source': 'Born on farm',
      'purchaseDate': '',
      'purchasePrice': '',
      'notes': ''
    },
    {
      'id': 'AN-1009',
      'name': 'Toofan',
      'tag': 'BD-1009',
      'species': 'Cattle',
      'type': 'Bull',
      'breed': 'Local Deshi',
      'sex': 'Male',
      'dob': ago(years: 1, months: 6),
      'group': 'Fattening',
      'initialWeight': '190',
      'weight': '260',
      'status': 'Active',
      'location': 'Fattening Shed',
      'sire': '',
      'dam': '',
      'source': 'Purchased',
      'purchaseDate': ago(months: 5),
      'purchasePrice': '65000',
      'notes': 'For Qurbani sale'
    },
    {
      'id': 'AN-1010',
      'name': 'Doli',
      'tag': 'BD-1010',
      'species': 'Sheep',
      'type': 'Ewe',
      'breed': 'Garole',
      'sex': 'Female',
      'dob': ago(years: 2, months: 3),
      'group': 'Sheep',
      'initialWeight': '18',
      'weight': '22',
      'status': 'Active',
      'location': 'Goat house',
      'sire': '',
      'dam': '',
      'source': 'Purchased',
      'purchaseDate': ago(months: 9),
      'purchasePrice': '7000',
      'notes': ''
    },
    // Lost over the past year (see Mortality & Losses).
    for (final (i, (name, species, type, breed, sex, group, location, years, months)) in [
      ('Chotu', 'Cattle', 'Calf', 'Holstein Friesian Cross', 'Male', 'Calves', 'Calf pen', 0, 10),
      ('Bindu', 'Cattle', 'Calf', 'Sahiwal Cross', 'Female', 'Calves', 'Calf pen', 0, 9),
      ('Kalo', 'Goat', 'Buck', 'Black Bengal', 'Male', 'Goats', 'Goat house', 1, 6),
      ('Dhola', 'Cattle', 'Heifer', 'Local Deshi', 'Female', 'Heifers', 'Heifer Shed', 1, 9),
      ('Mukta', 'Goat', 'Doe', 'Jamunapari', 'Female', 'Goats', 'Goat house', 3, 0),
      ('Pinki', 'Cattle', 'Cow', 'Red Chittagong', 'Female', 'Dry cows', 'Shed B', 7, 0),
      ('Bhola', 'Sheep', 'Lamb', 'Garole', 'Male', 'Sheep', 'Goat house', 0, 4),
      ('Tara', 'Cattle', 'Heifer', 'Sahiwal Cross', 'Female', 'Heifers', 'Heifer Shed', 1, 3),
      ('Chandu', 'Goat', 'Kid', 'Black Bengal', 'Male', 'Goats', 'Goat house', 0, 5),
      ('Lucky', 'Cattle', 'Calf', 'Jersey Cross', 'Female', 'Calves', 'Calf pen', 0, 1),
    ].indexed)
      {
        'id': 'AN-${1011 + i}',
        'name': name,
        'tag': 'BD-${1011 + i}',
        'species': species,
        'type': type,
        'breed': breed,
        'sex': sex,
        'dob': ago(years: years, months: months),
        'group': group,
        'initialWeight': '',
        'weight': '',
        'status': 'Dead',
        'location': location,
        'sire': '',
        'dam': '',
        'source': 'Born on farm',
        'purchaseDate': '',
        'purchasePrice': '',
        'notes': ''
      },
    // Sold at the haat (see Sales).
    {
      'id': 'AN-1021',
      'name': 'Kalu',
      'tag': 'BD-1021',
      'species': 'Cattle',
      'type': 'Bull',
      'breed': 'Local Deshi',
      'sex': 'Male',
      'dob': ago(years: 2, months: 4),
      'group': 'Fattening',
      'initialWeight': '210',
      'weight': '340',
      'status': 'Sold',
      'location': 'Fattening Shed',
      'sire': '',
      'dam': '',
      'source': 'Purchased',
      'purchaseDate': ago(months: 7),
      'purchasePrice': '85000',
      'notes': 'Qurbani bull'
    },
    {
      'id': 'AN-1022',
      'name': 'Lalu',
      'tag': 'BD-1022',
      'species': 'Cattle',
      'type': 'Bull',
      'breed': 'Sahiwal Cross',
      'sex': 'Male',
      'dob': ago(years: 2, months: 1),
      'group': 'Fattening',
      'initialWeight': '180',
      'weight': '300',
      'status': 'Sold',
      'location': 'Fattening Shed',
      'sire': '',
      'dam': '',
      'source': 'Purchased',
      'purchaseDate': ago(months: 6),
      'purchasePrice': '70000',
      'notes': ''
    },
    {
      'id': 'AN-1023',
      'name': 'Sada',
      'tag': 'BD-1023',
      'species': 'Goat',
      'type': 'Buck',
      'breed': 'Black Bengal',
      'sex': 'Male',
      'dob': ago(years: 1, months: 2),
      'group': 'Goats',
      'initialWeight': '10',
      'weight': '16',
      'status': 'Sold',
      'location': 'Goat house',
      'sire': '',
      'dam': '',
      'source': 'Born on farm',
      'purchaseDate': '',
      'purchasePrice': '',
      'notes': ''
    },
    {
      'id': 'AN-1024',
      'name': 'Bachchu',
      'tag': 'BD-1024',
      'species': 'Cattle',
      'type': 'Calf',
      'breed': 'Holstein Friesian Cross',
      'sex': 'Male',
      'dob': ago(months: 5),
      'group': 'Calves',
      'initialWeight': '35',
      'weight': '95',
      'status': 'Sold',
      'location': 'Calf pen',
      'sire': 'BULL-012 · Hero',
      'dam': 'AN-1002 · Rani',
      'source': 'Born on farm',
      'purchaseDate': '',
      'purchasePrice': '',
      'notes': ''
    },
    // Given to a relative's farm.
    {
      'id': 'AN-1025',
      'name': 'Chhoto',
      'tag': 'BD-1025',
      'species': 'Cattle',
      'type': 'Heifer',
      'breed': 'Local Deshi',
      'sex': 'Female',
      'dob': ago(years: 1, months: 1),
      'group': 'Heifers',
      'initialWeight': '',
      'weight': '150',
      'status': 'Transferred',
      'location': 'Heifer Shed',
      'sire': '',
      'dam': '',
      'source': 'Born on farm',
      'purchaseDate': '',
      'purchasePrice': '',
      'notes': 'Transferred to the family farm in Bogura'
    },
  ]);

  add(FarmModule.weights, [
    for (final (cow, kg) in [(mohini, '480'), (sundori, '240'), ('AN-1009 · Toofan', '260'), (doli, '22')])
      {'id': 'WT-${cow.substring(3, 7)}-5', 'date': d(5), 'animal': cow, 'weight': kg, 'bcs': '3'},
  ]);

  add(FarmModule.breeding, [
    {
      'id': 'BR-2006',
      'animal': sundori,
      'date': d(20),
      'method': 'AI',
      'semen': 'SEM-7802',
      'bull': 'BULL-025 · Raja',
      'technician': 'Rahim Uddin',
      'result': 'Pregnancy check due',
      'calvingDate': '',
      'cost': '500'
    },
    {
      'id': 'BR-2007',
      'animal': mohini,
      'date': d(90),
      'method': 'Natural mating',
      'semen': '',
      'bull': 'BUF-01 · Raja (buffalo)',
      'technician': '',
      'result': 'Confirmed pregnant',
      'calvingDate': '',
      'cost': '1000'
    },
    {'id': 'BR-2008', 'animal': doli, 'date': d(150), 'method': 'Natural mating', 'semen': '', 'bull': 'RAM-02 · Kalo', 'technician': '', 'result': 'Not pregnant', 'calvingDate': '', 'cost': ''},
    {
      'id': 'BR-2009',
      'animal': kali,
      'date': d(45),
      'method': 'Natural mating',
      'semen': '',
      'bull': 'BUCK-01 · Raju',
      'technician': '',
      'result': 'Pregnancy check due',
      'calvingDate': '',
      'cost': '200'
    },
    {
      'id': 'BR-2010',
      'animal': sundori,
      'date': d(41),
      'method': 'AI',
      'semen': 'SEM-7781',
      'bull': 'BULL-018 · Sultan',
      'technician': 'Rahim Uddin',
      'result': 'Not pregnant',
      'calvingDate': '',
      'cost': '500'
    },
  ]);

  add(FarmModule.semen, [
    for (final (i, (bull, breed, sire, dam, supplier, straws, cost)) in [
      ('BULL-031 · Bijoy', 'Holstein Friesian', 'BULL-020 · Ranger', 'COW-401 · Rupa', 'BRAC AI Centre', 12, 900),
      ('BULL-032 · Shapla', 'Sahiwal', 'BULL-003 · Raja Sr', 'COW-402 · Mala', 'DLS AI Centre, Savar', 8, 700),
      ('BULL-033 · Tufan', 'Jersey', 'BULL-021 · Comet', 'COW-403 · Bela', 'American Dairy Ltd', 10, 1200),
      ('BULL-034 · Megh', 'Red Chittagong', 'BULL-022 · Lal', 'COW-404 · Champa', 'BLRI, Savar', 6, 600),
      ('BULL-035 · Sagor', 'Holstein Friesian', 'BULL-023 · Atlas', 'COW-405 · Jui', 'BRAC AI Centre', 15, 950),
      ('BULL-036 · Durjoy', 'Brahman', 'BULL-024 · Titan', 'COW-406 · Moyna', 'Lal Teer Livestock', 9, 1100),
      ('BULL-037 · Akash', 'Sahiwal × HF', 'BULL-012 · Hero', 'COW-407 · Tara', 'DLS AI Centre, Savar', 7, 800),
    ].indexed)
      {
        'id': 'SM-${5004 + i}',
        'code': 'SEM-${7811 + i}',
        'bull': bull,
        'breed': breed,
        'bullSire': sire,
        'bullDam': dam,
        'supplier': supplier,
        'straws': '$straws',
        'expiry': d(-(300 + i * 60)),
        'tank': 'Tank ${1 + i % 2} · Canister ${String.fromCharCode(66 + i % 3)}',
        'costPerStraw': '$cost',
        'status': 'Available'
      },
  ]);

  add(FarmModule.health, [
    {
      'id': 'VH-7007',
      'animal': kali,
      'batch': '',
      'date': d(15),
      'type': 'Vaccination',
      'details': 'PPR vaccine',
      'medicine': 'PPR vaccine',
      'vet': 'Upazila Livestock Office',
      'withdrawalDays': '',
      'cost': '40',
      'next': d(-350),
      'status': 'Completed'
    },
    {
      'id': 'VH-7008',
      'animal': sundori,
      'batch': '',
      'date': d(60),
      'type': 'Vaccination',
      'details': 'Lumpy skin disease (LSD)',
      'medicine': 'LSD vaccine',
      'vet': 'Upazila Livestock Office',
      'withdrawalDays': '',
      'cost': '900',
      'next': d(-120),
      'status': 'Completed'
    },
    {
      'id': 'VH-7009',
      'animal': mohini,
      'batch': '',
      'date': d(20),
      'type': 'Vaccination',
      'details': 'FMD vaccine',
      'medicine': 'FMD Vaccine',
      'vet': 'Dr. Karim Ali',
      'withdrawalDays': '',
      'cost': '85',
      'next': d(-160),
      'status': 'Completed'
    },
    {
      'id': 'VH-7010',
      'animal': doli,
      'batch': '',
      'date': d(10),
      'type': 'Deworming',
      'details': 'Routine deworming',
      'medicine': 'Albendazole',
      'vet': '',
      'withdrawalDays': '',
      'cost': '60',
      'next': d(-80),
      'status': 'Completed'
    },
    {
      'id': 'VH-7011',
      'animal': sundori,
      'batch': '',
      'date': d(-3),
      'type': 'Vaccination',
      'details': 'Brucellosis (scheduled)',
      'medicine': '',
      'vet': 'Dr. Karim Ali',
      'withdrawalDays': '',
      'cost': '',
      'next': d(-3),
      'status': 'Scheduled'
    },
  ]);

  // Seven more illness cases with consultations, treatments, doses and follow-ups.
  Map<String, dynamic> illness(String id, String animal, int noticed, String symptoms, String severity,
          {String closure = '', int? closedDaysAgo, String closureNotes = '', String appetite = 'Reduced', String vet = 'Dr. Karim Ali'}) =>
      {
        'id': id,
        'animal': animal,
        'species': '',
        'noticedAt': at(noticed, '07:00'),
        'reportedAt': at(noticed, '08:00'),
        'reportedBy': 'Rahim Uddin',
        'symptoms': symptoms,
        'dangerSigns': '',
        'observations': '',
        'appetite': appetite,
        'water': 'Not checked',
        'milkChange': 'Not milking / not applicable',
        'behaviour': '',
        'temperature': '',
        'tempUnit': '',
        'injury': '',
        'severity': severity,
        'suspectedCause': '',
        'vetName': vet,
        'vetPhone': vet.isEmpty ? '' : '01711000000',
        'notes': '',
        'stage': '',
        'diagnosisStatus': '',
        'diagnosis': '',
        'closure': closure,
        'closedOn': closedDaysAgo == null ? '' : d(closedDaysAgo),
        'closureNotes': closureNotes,
        'reopenedCount': '0',
      };
  add(FarmModule.illness, [
    illness('IL-04', shona, 30, 'Mild lameness, front left leg', 'Low', closure: FarmModule.closeRecovered, closedDaysAgo: 24, closureNotes: 'Walking normally', appetite: 'Normal'),
    illness('IL-05', kali, 18, 'Diarrhoea, eating less', 'Moderate', closure: FarmModule.closeRecovered, closedDaysAgo: 9, closureNotes: 'Dung normal, eating well'),
    illness('IL-06', mohini, 60, 'Reduced appetite after transport', 'Low', closure: FarmModule.closeRecovered, closedDaysAgo: 54, closureNotes: 'Eating normally again'),
    illness('IL-07', sundori, 8, 'Round hairless patches on the neck', 'Low', appetite: 'Normal'),
    illness('IL-08', doli, 5, 'Coughing, nasal discharge', 'Moderate', vet: ''),
    illness('IL-09', lali, 12, 'Swollen, painful navel', 'Moderate'),
    illness('IL-10', kali, 70, 'Swollen left side, uneasy (bloat)', 'High', closure: FarmModule.closeRecovered, closedDaysAgo: 65, closureNotes: 'Bloat resolved, grazing normally'),
  ]);

  Map<String, dynamic> consult(String id, String illnessRef, String animal, int daysAgo, String findings, String diagnosis, String status, String fee, {String advice = '', String next = ''}) => {
        'id': id,
        'illness': illnessRef,
        'animal': animal,
        'date': d(daysAgo),
        'vetName': 'Dr. Karim Ali',
        'vetPhone': '01711000000',
        'observations': findings,
        'diagnosis': diagnosis,
        'diagnosisStatus': status,
        'recommendedTreatment': advice,
        'prescriptionRef': '',
        'fee': fee,
        'nextDate': next,
        'instructions': '',
      };
  add(FarmModule.consultations, [
    consult('VC-03', 'IL-04 · Shona', shona, 29, 'Heat in the sole, no wound', 'Sole bruise', FarmModule.diagSuspected, '300', advice: 'Hoof dressing, rest on soft bedding'),
    consult('VC-04', 'IL-05 · Kali', kali, 17, 'Pale gums, soft dung', 'Worm burden', FarmModule.diagSuspected, '250', advice: 'Deworm as prescribed'),
    consult('VC-05', 'IL-06 · Mohini', mohini, 59, 'Alert, rumen moving, no fever recorded', 'Transport stress', FarmModule.diagSuspected, '200'),
    consult('VC-06', 'IL-07 · Sundori', sundori, 7, 'Crusty circular lesions', 'Ringworm (dermatophytosis)', FarmModule.diagConfirmed, '300',
        advice: 'Antifungal spray; keep separate from calves', next: d(-4)),
    consult('VC-07', 'IL-09 · Lali', lali, 11, 'Hot swollen navel, discharge', 'Navel ill (omphalitis)', FarmModule.diagConfirmed, '400', advice: 'Antibiotic injection and navel dip'),
    consult('VC-08', 'IL-10 · Kali', kali, 70, 'Left flank distended, frothy rumen content', 'Frothy bloat', FarmModule.diagConfirmed, '500', advice: 'Anti-bloat drench'),
    consult('VC-09', 'IL-09 · Lali', lali, 6, 'Swelling smaller, no discharge', 'Navel ill (omphalitis)', FarmModule.diagConfirmed, ''),
    consult('VC-10', 'IL-07 · Sundori', sundori, 3, 'Lesions drying, no new patches', 'Ringworm (dermatophytosis)', FarmModule.diagConfirmed, ''),
  ]);

  Map<String, dynamic> treatment(
          String id, String illnessRef, String animal, int start, int end, String medicine, String type, String dose, String unit, String route, String frequency, String cost, String outcome,
          {String notes = ''}) =>
      {
        'id': id,
        'illness': illnessRef,
        'animal': animal,
        'startDate': d(start),
        'endDate': d(end),
        'medicine': medicine,
        'activeIngredient': '',
        'medicineType': type,
        'dose': dose,
        'doseUnit': unit,
        'route': route,
        'frequency': frequency,
        'prescribedBy': 'Dr. Karim Ali',
        'prescriptionRef': '',
        'stockItem': '',
        'stockPerDose': '',
        'withdrawalDays': '',
        'cost': cost,
        'outcome': outcome,
        'outcomeNotes': outcome == 'Completed' ? 'Course finished as prescribed' : notes,
        'notes': '',
      };
  add(FarmModule.treatments, [
    treatment('TR-03', 'IL-04 · Shona', shona, 29, 25, 'Hoof dressing', 'Topical / wound care', '1', 'application', 'Topical', 'Once daily for 4 days', '250', 'Completed'),
    treatment('TR-04', 'IL-05 · Kali', kali, 17, 17, 'Albendazole (oral)', 'Antiparasitic', '5', 'ml', 'Oral', 'Single dose', '60', 'Completed'),
    treatment('TR-05', 'IL-07 · Sundori', sundori, 7, -7, 'Antifungal spray', 'Topical / wound care', '2', 'sprays', 'Topical', 'Every 2 days for 2 weeks', '350', FarmModule.treatmentOngoing),
    treatment('TR-06', 'IL-09 · Lali', lali, 11, 7, 'Penicillin-Streptomycin Inj.', 'Antibiotic', '3', 'ml', 'Intramuscular (IM)', 'Once daily for 5 days', '600', 'Completed'),
    treatment('TR-07', 'IL-10 · Kali', kali, 70, 70, 'Anti-bloat oral drench', 'Other', '50', 'ml', 'Oral', 'Single dose', '300', 'Completed'),
    treatment('TR-08', 'IL-09 · Lali', lali, 11, 7, 'Iodine navel dip', 'Topical / wound care', '1', 'dip', 'Topical', 'Twice daily for 5 days', '', 'Completed'),
    treatment('TR-09', 'IL-05 · Kali', kali, 17, 15, 'Oral rehydration salts', 'Fluid / electrolyte', '250', 'ml', 'Oral', 'Twice daily for 2 days', '', 'Completed'),
    treatment('TR-10', 'IL-04 · Shona', shona, 29, 27, 'Meloxicam Inj.', 'Anti-inflammatory / pain relief', '10', 'ml', 'Subcutaneous (SC)', 'Once daily for 3 days', '', 'Completed'),
  ]);

  Map<String, dynamic> dose(String id, String treatmentRef, String illnessRef, String animal, String medicine, String status, int daysAgo, {String reason = '', String doseGiven = ''}) => {
        'id': id,
        'treatment': treatmentRef,
        'animal': animal,
        'illness': illnessRef,
        'medicine': medicine,
        'status': status,
        'scheduledAt': status == FarmModule.medMissed ? at(daysAgo, '08:00') : '',
        'givenAt': status == FarmModule.medMissed ? '' : at(daysAgo, '08:00'),
        'doseGiven': status == FarmModule.medMissed ? '' : doseGiven,
        'administeredBy': status == FarmModule.medMissed ? '' : 'Sabbir Hossain',
        'reason': reason,
        'sideEffects': '',
        'notes': '',
      };
  add(FarmModule.medication, [
    dose('MA-05', 'TR-05 · Antifungal spray · Sundori', 'IL-07 · Sundori', sundori, 'Antifungal spray', FarmModule.medGiven, 7, doseGiven: '2 sprays'),
    dose('MA-06', 'TR-05 · Antifungal spray · Sundori', 'IL-07 · Sundori', sundori, 'Antifungal spray', FarmModule.medGiven, 5, doseGiven: '2 sprays'),
    dose('MA-07', 'TR-06 · Penicillin-Streptomycin Inj. · Lali', 'IL-09 · Lali', lali, 'Penicillin-Streptomycin Inj.', FarmModule.medGiven, 11, doseGiven: '3 ml'),
    dose('MA-08', 'TR-06 · Penicillin-Streptomycin Inj. · Lali', 'IL-09 · Lali', lali, 'Penicillin-Streptomycin Inj.', FarmModule.medGiven, 10, doseGiven: '3 ml'),
    dose('MA-09', 'TR-06 · Penicillin-Streptomycin Inj. · Lali', 'IL-09 · Lali', lali, 'Penicillin-Streptomycin Inj.', FarmModule.medGiven, 9, doseGiven: '3 ml'),
    dose('MA-10', 'TR-06 · Penicillin-Streptomycin Inj. · Lali', 'IL-09 · Lali', lali, 'Penicillin-Streptomycin Inj.', FarmModule.medMissed, 8, reason: 'Calf could not be caught in time'),
  ]);

  Map<String, dynamic> followUp(String id, String illnessRef, String animal, int dueDaysAgo, String type, String status, {String progress = '', String observations = '', String next = ''}) => {
        'id': id,
        'illness': illnessRef,
        'animal': animal,
        'dueDate': d(dueDaysAgo),
        'type': type,
        'assignedTo': 'Sabbir Hossain',
        'status': status,
        'doneDate': status == 'Done' ? d(dueDaysAgo) : '',
        'progress': progress,
        'observations': observations,
        'vetAssessment': '',
        'nextAction': next,
        'notes': '',
      };
  add(FarmModule.followUps, [
    followUp('FU-03', 'IL-04 · Shona', shona, 25, 'Farm check', 'Done', progress: 'Improved', observations: 'Bearing weight on the leg', next: 'Treatment finished — decide on recovery'),
    followUp('FU-04', 'IL-05 · Kali', kali, 10, 'Farm check', 'Done', progress: 'Improved', observations: 'Dung firm'),
    followUp('FU-05', 'IL-06 · Mohini', mohini, 55, 'Farm check', 'Done', progress: 'Improved', observations: 'Eating full ration'),
    followUp('FU-06', 'IL-07 · Sundori', sundori, -4, 'Vet visit', 'Scheduled'),
    followUp('FU-07', 'IL-09 · Lali', lali, 6, 'Vet visit', 'Done', progress: 'Improved', observations: 'Navel drying', next: 'Another follow-up needed'),
    followUp('FU-08', 'IL-09 · Lali', lali, -5, 'Farm check', 'Scheduled'),
    followUp('FU-09', 'IL-10 · Kali', kali, 68, 'Farm check', 'Done', progress: 'Improved', observations: 'Left side normal'),
    followUp('FU-10', 'IL-10 · Kali', kali, 66, 'Farm check', 'Done', progress: 'Improved', observations: 'Grazing normally', next: 'Treatment finished — decide on recovery'),
  ]);

  add(FarmModule.purchases, [
    for (final (i, (daysAgo, supplier, item, qty, amount, status)) in [
      (6, 'Fresh Feed Traders', 'Wheat bran', '500 kg', '22000', 'Received'),
      (10, 'Fresh Feed Traders', 'Fattening concentrate', '400 kg', '20800', 'Received'),
      (14, 'Rahman Vet Pharmacy', 'Oxytetracycline Inj.', '10 vials', '2200', 'Received'),
      (20, 'Krishi Seba', 'Napier grass cuttings', '500 kg', '3000', 'Received'),
      (25, 'Upazila Livestock Office', 'LSD and FMD vaccines', '20 vials', '2400', 'Received'),
      (30, 'BRAC AI Centre', 'Semen straws', '12 straws', '10800', 'Received'),
      (3, 'Agro Silage Ltd', 'Maize silage bales', '1000 kg', '12000', 'Ordered'),
      (2, 'Sohag Dairy Equipment', 'Milk cans (40 L)', '4 pcs', '11200', 'Due'),
      (1, 'Krishi Seba', 'Rice straw', '300 kg', '2400', 'Ordered'),
    ].indexed)
      {'id': 'PO-${9002 + i}', 'date': d(daysAgo), 'supplier': supplier, 'item': item, 'qty': qty, 'amount': amount, 'status': status},
  ]);

  add(FarmModule.customers, [
    {'id': 'CU-10006', 'name': 'Hasan Dairy Products', 'phone': '01700000006', 'type': 'Wholesale', 'balance': '0', 'status': 'Active'},
    {'id': 'CU-10007', 'name': 'Krishi Seba Compost', 'phone': '01800000007', 'type': 'Other', 'balance': '0', 'status': 'Active'},
    {'id': 'CU-10008', 'name': 'Moyna Store', 'phone': '01900000008', 'type': 'Retail', 'balance': '0', 'status': 'Active'},
    {'id': 'CU-10009', 'name': 'Shapla Sweets', 'phone': '01600000009', 'type': 'Retail', 'balance': '0', 'status': 'Active'},
    {'id': 'CU-10010', 'name': 'Bismillah Traders', 'phone': '01500000010', 'type': 'Trader', 'balance': '0', 'status': 'Active'},
  ]);

  add(FarmModule.expenses, [
    {
      'id': 'EX-6009',
      'date': d(15),
      'category': 'Water',
      'amount': '1200',
      'description': 'Deep tube-well maintenance',
      'scope': FarmModule.scopeFarm,
      'animal': '',
      'batch': '',
      'location': '',
      'allocation': FarmModule.allocEqual,
      'payment': 'Paid',
      'paymentMethod': 'Cash',
      'reference': '',
      'vendor': 'Local mechanic',
      'notes': ''
    },
    {
      'id': 'EX-6010',
      'date': d(12),
      'category': 'Equipment',
      'amount': '3500',
      'description': 'Milking machine service',
      'scope': FarmModule.scopeFarm,
      'animal': '',
      'batch': '',
      'location': '',
      'allocation': FarmModule.allocNone,
      'payment': 'Paid',
      'paymentMethod': 'Cash',
      'reference': 'SRV-221',
      'vendor': 'DeLaval service',
      'notes': ''
    },
  ]);
}
