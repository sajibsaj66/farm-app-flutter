import 'package:flutter/material.dart';

import '../core/utils/units.dart';
import 'field_spec.dart';

/// Describes one record module: its name, icons and the fields its form uses.
///
/// Every record is stored as a map, so adding a field here is enough to have
/// it entered, validated, listed, searched, exported and backed up. Fields
/// whose key starts with `_` are internal bookkeeping and never shown.
class FarmModule {
  const FarmModule({required this.name, required this.navIcon, required this.recordIcon, required this.specs});

  final String name;
  final IconData navIcon;
  final IconData recordIcon;
  final List<FieldSpec> specs;

  List<String> get fields => specs.map((s) => s.key).toList();

  // Setup
  static const species = 'Species & Categories';
  static const locations = 'Sheds, Pens & Ponds';
  // Individual animals
  static const animals = 'Animals';
  static const breeding = 'Breeding';
  static const semen = 'Semen Inventory';
  static const weights = 'Weight Records';
  // Batches (flocks, ponds, hives)
  static const batches = 'Batches';

  /// Poultry, fish and bee batch modules: kept so data saved by older
  /// versions is never lost, but not part of this livestock system — no role
  /// can open them, and they appear in no menu, form or report.
  static const outOfScope = {batches, batchMovements, sampling};
  static const batchMovements = 'Batch Movements';
  static const sampling = 'Batch Sampling';
  static const mortality = 'Mortality & Losses';
  // Feed
  static const feedRecords = 'Feed Records';
  static const inventory = 'Inventory';
  static const inventoryTx = 'Stock Transactions';
  // Production
  static const milkProduction = 'Milk Production';
  static const production = 'Production Records';
  static const productUsage = 'Product Usage';
  // Health
  static const health = 'Health & Vaccination';
  static const illness = 'Illness Cases';
  static const consultations = 'Vet Consultations';
  static const treatments = 'Treatments';
  static const medication = 'Medication Log';
  static const followUps = 'Follow-ups';

  /// An animal's health status — separate from its operational status
  /// (Active, Sold, Dead…).
  static const healthHealthy = 'Healthy / no current illness reported';
  static const healthSymptoms = 'Symptoms reported';
  static const healthAwaitingVet = 'Awaiting veterinary assessment';
  static const healthTreatment = 'Under treatment';
  static const healthFollowUp = 'Follow-up required';
  static const healthRecovered = 'Recovered';
  static const healthChronic = 'Chronic or ongoing condition';
  static const healthOther = 'Other / unknown';
  static const healthStatuses = [healthHealthy, healthSymptoms, healthAwaitingVet, healthTreatment, healthFollowUp, healthRecovered, healthChronic, healthOther];

  /// How an illness case ends. Only an explicit user action sets these.
  static const closeRecovered = 'Recovered';
  static const closeChronic = 'Chronic / ongoing care';
  static const closeReferred = 'Referred / transferred';
  static const closeDied = 'Died';
  static const closeOther = 'Closed — other';
  static const closures = [closeRecovered, closeChronic, closeReferred, closeDied, closeOther];

  static const severities = ['Low', 'Moderate', 'High', 'Emergency'];
  static const dangerSigns = [
    'Severe breathing difficulty',
    'Collapse / cannot get up',
    'Unable to stand',
    'Uncontrolled bleeding',
    'Convulsions / seizures',
    'Severe bloating',
    'Difficult birth (dystocia)',
    'Unresponsive',
  ];
  static const diagNotEvaluated = 'Not evaluated';
  static const diagSuspected = 'Suspected';
  static const diagConfirmed = 'Veterinarian confirmed';
  static const treatmentOngoing = 'Ongoing';
  static const medGiven = 'Given';
  static const medDelayed = 'Delayed';
  static const medMissed = 'Missed';
  static const medDiscontinued = 'Discontinued';
  static const medScheduled = 'Scheduled';
  // Money
  static const purchases = 'Purchases';
  static const sales = 'Sales';
  static const collections = 'Payments Received';
  static const customers = 'Customers';
  static const expenses = 'Expenses';
  // Team and owner control
  static const staff = 'Staff';
  static const tasks = 'Daily Tasks';
  static const requests = 'Requests & Approvals';
  static const managerReports = 'Manager Reports';

  // Owner approval of large expenses and purchases.
  static const approvalNotRequired = 'Not required';
  static const approvalPending = 'Pending owner approval';
  static const approvalApproved = 'Approved';
  static const approvalRejected = 'Rejected';
  static const approvals = [approvalNotRequired, approvalPending, approvalApproved, approvalRejected];

  /// Money that is not spent (or counted) until the owner approves.
  static bool awaitsOrRefused(dynamic approval) => '$approval' == approvalPending || '$approval' == approvalRejected;

  static const requestTypes = ['Feed or supplies needed', 'Equipment', 'Animal purchase', 'Large expense', 'Veterinary or treatment cost', 'Farm expansion', 'Other'];
  static const staffJobs = ['Milker', 'Feeder', 'Herdsman', 'Cleaner', 'Guard', 'Driver', 'Supervisor', 'Other'];
  static const taskAreas = ['Feeding', 'Milking', 'Cleaning', 'Animal health', 'Breeding', 'Stock & store', 'Maintenance', 'Other'];

  // Species categories and tracking methods.
  /// Livestock only: this system is for dairy, rearing, fattening and mixed
  /// livestock farms (no poultry, fisheries or bee-keeping).
  static const speciesCategories = ['Cattle', 'Buffalo', 'Goat & sheep', 'Other livestock'];
  static const trackIndividual = 'Individual';
  static const trackBatch = 'Batch';

  static const shifts = ['Morning', 'Afternoon', 'Evening', 'Night'];
  static const animalGroups = ['Lactating cows', 'Dry cows', 'Pregnant cows', 'Heifers', 'Calves', 'Bulls', 'Fattening', 'Goats', 'Sheep', 'Other'];

  /// Statuses that take an animal or batch out of active use (kept for history).
  static const inactiveStatuses = {'sold', 'dead', 'transferred', 'archived', 'closed', 'inactive'};

  // Breeding results.
  static const resultPending = 'Pregnancy check due';
  static const resultPregnant = 'Confirmed pregnant';
  static const resultOpen = 'Not pregnant';
  static const resultCalved = 'Calved';
  static const resultAborted = 'Aborted';

  // Milk quality values that may not be sold.
  static const qualityWithheld = 'Withheld';
  static const qualityRejected = 'Rejected';

  // Feed sources.
  static const fromInventory = 'From inventory';
  static const manualExpense = 'Manual (expense only)';

  // Products. Production, usage and sales share these names so unsold stock
  // can be worked out per product.
  /// Livestock products. (Older records with other products keep their value.)
  static const products = ['Milk', 'Meat', 'Manure', 'Wool', 'Hides & skins', 'Offspring', 'Other'];
  static const saleProducts = [...products, 'Live animal'];
  static const defaultProductUnit = {
    'Milk': 'L',
    'Eggs': 'pcs',
    'Meat': 'kg',
    'Fish': 'kg',
    'Shrimp': 'kg',
    'Honey': 'kg',
    'Wool': 'kg',
    'Manure': 'kg',
    'Offspring': 'head',
    'Live animal': 'head',
    'Hides & skins': 'pcs',
  };

  // Batch movement types and their effect on the head count.
  static const movementAdds = ['Addition / purchase', 'Hatching', 'Transfer in', 'Count correction (+)'];
  static const movementRemoves = ['Transfer out', 'Culling', 'Count correction (−)'];

  // Stock transaction types.
  static const txPurchase = 'Purchase / receipt';
  static const txOpening = 'Opening stock';
  static const txAdjustUp = 'Adjustment (+)';
  static const txAdjustDown = 'Adjustment (−)';
  static const txWastage = 'Wastage / damage';
  static const txCount = 'Physical count (set to)';
  static const txIssue = 'Issued to feeding';
  static const txTreatment = 'Issued for treatment';
  static const manualTxTypes = [txPurchase, txAdjustUp, txAdjustDown, txWastage, txCount];

  // Expense categories and shared-cost allocation methods.
  static const expenseCategories = [
    'Feed',
    'Veterinary treatment',
    'Medicine and vaccines',
    'Labour and salaries',
    'Electricity',
    'Water',
    'Equipment',
    'Shed and building maintenance',
    'Transportation',
    'Breeding',
    'Packaging',
    'Utilities',
    'Insurance',
    animalPurchase,
    'Other',
  ];
  static const scopeFarm = 'Farm-wide (shared)';
  static const animalPurchase = 'Animal purchase';

  /// Older name of [animalPurchase], still read from saved data.
  static const legacyAnimalPurchase = 'Animal or bird purchase';
  static const scopes = [scopeFarm, 'Animal', 'Location'];
  static const allocNone = 'Not allocated (farm overhead)';
  static const allocEqual = 'Equal per animal';
  static const allocHead = 'By head count';
  static const allocFeed = 'By feed cost';
  static const allocProduction = 'By production value';
  static const allocations = [allocNone, allocEqual, allocHead, allocFeed, allocProduction];
  static const paymentMethods = ['Cash', 'Bank', 'Mobile banking', 'Cheque', 'Credit', 'Other'];

  static const all = [
    // ------------------------------------------------------------------ Setup
    FarmModule(name: species, navIcon: Icons.category_outlined, recordIcon: Icons.category, specs: [
      FieldSpec('name', label: 'Species / category name'),
      FieldSpec('category', type: FieldType.choice, options: speciesCategories),
      FieldSpec('tracking', type: FieldType.choice, options: [trackIndividual], hint: 'Each animal has its own record'),
      FieldSpec('products', label: 'Products', required: false, hint: 'Comma separated, e.g. Milk, Meat, Offspring'),
      FieldSpec('countUnit', label: 'Counted as', hint: 'Usually head'),
      FieldSpec('notes', required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Active', 'Inactive']),
    ]),
    FarmModule(name: locations, navIcon: Icons.holiday_village_outlined, recordIcon: Icons.holiday_village, specs: [
      FieldSpec('name'),
      FieldSpec('kind', type: FieldType.choice, options: ['Shed', 'Barn', 'Pen', 'Calf pen', 'Pasture', 'Isolation', 'Store', 'Other']),
      FieldSpec('capacity', type: FieldType.number, required: false, hint: 'Number of animals it can hold'),
      FieldSpec('area', label: 'Area / size', required: false, hint: 'e.g. 2000 sq ft, 0.5 acre'),
      FieldSpec('notes', required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Active', 'Inactive']),
    ]),
    // ----------------------------------------------------------- Individuals
    FarmModule(name: animals, navIcon: Icons.pets_outlined, recordIcon: Icons.pets, specs: [
      FieldSpec('name'),
      FieldSpec('tag', label: 'Ear tag / RFID', required: false),
      FieldSpec('species', type: FieldType.species),
      FieldSpec('type', type: FieldType.choice, label: 'Class', options: ['Cow', 'Bull', 'Heifer', 'Calf', 'Buck', 'Doe', 'Kid', 'Ram', 'Ewe', 'Lamb', 'Boar', 'Sow', 'Stallion', 'Mare', 'Other']),
      FieldSpec('breed'),
      FieldSpec('sex', type: FieldType.choice, options: ['Female', 'Male']),
      FieldSpec('dob', type: FieldType.date, label: 'Date of birth', required: false),
      FieldSpec('group', type: FieldType.choice, options: animalGroups, hint: 'Used to share group feeding between animals'),
      FieldSpec('initialWeight', type: FieldType.number, label: 'Initial weight (kg)', required: false),
      FieldSpec('weight', type: FieldType.number, label: 'Current weight (kg)', required: false, hint: 'Updated automatically from Weight Records'),
      FieldSpec('status',
          type: FieldType.choice,
          options: ['Active', 'Pregnant', 'Treatment', 'Dry', 'Sold', 'Dead', 'Transferred', 'Archived'],
          hint: 'Sold and Dead are set automatically by sales and mortality records'),
      FieldSpec('location', type: FieldType.location, label: 'Shed / pen'),
      FieldSpec('sire', label: 'Sire (father)', required: false, hint: 'Bull ID and name, e.g. BULL-012 · Hero'),
      FieldSpec('dam', type: FieldType.animal, label: 'Dam (mother)', required: false),
      FieldSpec('source', type: FieldType.choice, options: ['Born on farm', 'Purchased'], required: false),
      FieldSpec('purchaseDate', type: FieldType.date, label: 'Purchase date', required: false),
      FieldSpec('purchasePrice', type: FieldType.number, label: 'Purchase price', required: false, hint: 'Kept as the animal’s asset cost — not charged to daily profit'),
      FieldSpec('healthStatus', label: 'Health status', computed: true, required: false, hint: 'From illness cases — separate from the status above'),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: breeding, navIcon: Icons.biotech_outlined, recordIcon: Icons.biotech, specs: [
      FieldSpec('animal', type: FieldType.animal),
      FieldSpec('date', type: FieldType.date, label: 'Service date'),
      FieldSpec('method', type: FieldType.choice, options: ['AI', 'Natural mating']),
      FieldSpec('semen', type: FieldType.semen, label: 'Semen batch', required: false, hint: 'Required for AI · one straw is taken from stock'),
      FieldSpec('bull', required: false, hint: 'Filled in from the semen batch for AI'),
      FieldSpec('technician', required: false),
      FieldSpec('result', type: FieldType.choice, options: [resultPending, resultPregnant, resultOpen, resultCalved, resultAborted, 'Follow-up required']),
      FieldSpec('calvingDate', type: FieldType.date, label: 'Birth / calving date', required: false),
      FieldSpec('cost', type: FieldType.number, label: 'Service cost', required: false),
    ]),
    FarmModule(name: semen, navIcon: Icons.science_outlined, recordIcon: Icons.science, specs: [
      FieldSpec('code', label: 'Semen code / straw batch'),
      FieldSpec('bull', label: 'Bull ID and name', hint: 'e.g. BULL-018 · Sultan'),
      FieldSpec('breed', label: 'Bull breed'),
      FieldSpec('bullSire', label: 'Bull’s sire', required: false, hint: 'Needed for the inbreeding check'),
      FieldSpec('bullDam', label: 'Bull’s dam', required: false, hint: 'Needed for the inbreeding check'),
      FieldSpec('supplier', label: 'Supplier / AI centre'),
      FieldSpec('straws', type: FieldType.number, label: 'Straws in stock'),
      FieldSpec('expiry', type: FieldType.date, label: 'Expiry date'),
      FieldSpec('tank', label: 'Tank / canister', required: false),
      FieldSpec('costPerStraw', type: FieldType.number, label: 'Cost per straw', required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Available', 'Used up', 'Expired', 'Damaged'], computed: true),
    ]),
    FarmModule(name: weights, navIcon: Icons.monitor_weight_outlined, recordIcon: Icons.monitor_weight, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('animal', type: FieldType.animal),
      FieldSpec('weight', type: FieldType.number, label: 'Weight (kg)'),
      FieldSpec('bcs', type: FieldType.choice, label: 'Body condition score', options: ['1', '2', '3', '4', '5'], required: false),
    ]),
    // ---------------------------------------------------------------- Batches
    FarmModule(name: batches, navIcon: Icons.groups_outlined, recordIcon: Icons.groups, specs: [
      FieldSpec('name', label: 'Batch name'),
      FieldSpec('species', type: FieldType.species),
      FieldSpec('breed', label: 'Breed / variety', required: false),
      FieldSpec('purpose', type: FieldType.choice, options: ['Eggs', 'Meat', 'Grow-out (fish/shrimp)', 'Honey', 'Breeding', 'Other']),
      FieldSpec('startDate', type: FieldType.date, label: 'Start / stocking date'),
      FieldSpec('initialCount', type: FieldType.number, label: 'Opening count', hint: 'Birds, fish, colonies… placed at the start'),
      FieldSpec('countUnit', label: 'Counted as', required: false, hint: 'birds, fish, pcs, colonies'),
      FieldSpec('initialAvgWeight', type: FieldType.number, label: 'Opening average weight (g)', required: false),
      FieldSpec('location', type: FieldType.location, label: 'House / pond / location'),
      FieldSpec('stockingCost', type: FieldType.number, label: 'Purchase / stocking cost'),
      FieldSpec('status', type: FieldType.choice, options: ['Active', 'Closed', 'Archived']),
      FieldSpec('closeDate', type: FieldType.date, label: 'Closing date', required: false),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: batchMovements, navIcon: Icons.swap_horiz_outlined, recordIcon: Icons.swap_horiz, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('batch', type: FieldType.batch),
      FieldSpec('type', type: FieldType.choice, options: [...movementAdds, ...movementRemoves]),
      FieldSpec('quantity', type: FieldType.number, label: 'Number of animals / birds / fish'),
      FieldSpec('cost', type: FieldType.number, label: 'Cost (for purchases)', required: false),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: sampling, navIcon: Icons.scale_outlined, recordIcon: Icons.scale, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('batch', type: FieldType.batch),
      FieldSpec('sampleSize', type: FieldType.number, label: 'Sample size'),
      FieldSpec('avgWeight', type: FieldType.number, label: 'Average weight (g)'),
      FieldSpec('waterTemp', type: FieldType.number, label: 'Water temperature (°C)', required: false),
      FieldSpec('ph', type: FieldType.number, label: 'pH', required: false),
      FieldSpec('oxygen', type: FieldType.number, label: 'Dissolved oxygen (mg/L)', required: false),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: mortality, navIcon: Icons.heart_broken_outlined, recordIcon: Icons.heart_broken, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('animal', type: FieldType.animal, required: false, hint: 'An individual animal (marks it as Dead)'),
      FieldSpec('batch', type: FieldType.batch, required: false, hint: 'Or losses from a flock / pond'),
      FieldSpec('count', type: FieldType.number, label: 'Number lost'),
      FieldSpec('cause', type: FieldType.choice, options: ['Disease', 'Accident', 'Predator', 'Heat stress', 'Calving / birth', 'Culled', 'Unknown', 'Other']),
      FieldSpec('disposal', type: FieldType.choice, options: ['Buried', 'Burned', 'Rendered', 'Sold as by-product', 'Other'], required: false),
      FieldSpec('notes', required: false),
    ]),
    // ------------------------------------------------------------------- Feed
    FarmModule(name: feedRecords, navIcon: Icons.grass_outlined, recordIcon: Icons.grass, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('animal', type: FieldType.animal, required: false, hint: 'Feed given to one animal'),
      FieldSpec('batch', type: FieldType.batch, required: false, hint: 'Or feed given to a flock / pond'),
      FieldSpec('group', type: FieldType.choice, options: animalGroups, required: false, hint: 'Or a group ration — shared equally between its animals'),
      FieldSpec('species', computed: true, required: false, hint: 'From the animal or batch'),
      FieldSpec('feed', type: FieldType.feedItem, label: 'Feed item'),
      FieldSpec('category', label: 'Feed category', computed: true, required: false),
      FieldSpec('source', type: FieldType.choice, options: [fromInventory, manualExpense], hint: 'From inventory reduces stock. Manual records the cost only.'),
      FieldSpec('qty', type: FieldType.number, label: 'Quantity consumed'),
      FieldSpec('unit', type: FieldType.choice, options: Units.feedUnits),
      FieldSpec('unitPrice', type: FieldType.number, label: 'Price per unit', hint: 'Defaults to the item’s cost; kept with this record'),
      FieldSpec('totalCost', type: FieldType.number, label: 'Total cost', computed: true, required: false),
      FieldSpec('shift', type: FieldType.choice, options: shifts),
      FieldSpec('staff', label: 'Fed by', required: false),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: inventory, navIcon: Icons.inventory_2_outlined, recordIcon: Icons.inventory_2, specs: [
      FieldSpec('name'),
      FieldSpec('category', type: FieldType.choice, options: ['Feed', 'Medicine', 'Vaccine', 'Equipment', 'Packaging', 'Other']),
      FieldSpec('feedType',
          label: 'Feed category',
          type: FieldType.choice,
          required: false,
          options: ['Green fodder', 'Dry grass', 'Hay and straw', 'Silage', 'Dairy concentrate', 'Fattening concentrate', 'Calf starter', 'Grains and supplements', 'Minerals and vitamins', 'Other']),
      FieldSpec('qty', type: FieldType.number, label: 'Quantity in stock', lockedOnEdit: true, hint: 'After creation, stock changes only through Stock Transactions and feed records'),
      FieldSpec('unit', type: FieldType.choice, options: [...Units.feedUnits, 'vials', 'doses', 'pcs']),
      FieldSpec('reorder', type: FieldType.number, label: 'Reorder level', hint: 'In the item’s unit — low stock is flagged at or below this'),
      FieldSpec('unitCost', type: FieldType.number, label: 'Cost per unit', required: false, hint: 'Updated by the latest purchase'),
      FieldSpec('status', type: FieldType.choice, options: ['In stock', 'Low stock', 'Out of stock'], computed: true),
    ]),
    FarmModule(name: inventoryTx, navIcon: Icons.receipt_long_outlined, recordIcon: Icons.receipt_long, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('item', type: FieldType.inventoryItem),
      FieldSpec('type', type: FieldType.choice, options: manualTxTypes),
      FieldSpec('quantity', type: FieldType.number, hint: 'For a physical count, enter the quantity actually counted'),
      FieldSpec('unitCost', type: FieldType.number, label: 'Cost per unit', required: false, hint: 'For purchases — becomes the item’s current cost'),
      FieldSpec('reference', label: 'Reference / invoice no.', required: false),
      FieldSpec('notes', required: false),
    ]),
    // ------------------------------------------------------------- Production
    FarmModule(name: milkProduction, navIcon: Icons.water_drop_outlined, recordIcon: Icons.water_drop, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('animal', type: FieldType.animal),
      FieldSpec('shift', type: FieldType.choice, options: ['Morning', 'Afternoon', 'Evening']),
      FieldSpec('litres', type: FieldType.number),
      FieldSpec('quality', type: FieldType.choice, options: ['Accepted', 'Review', qualityRejected, qualityWithheld], hint: 'Set to Withheld automatically during a medicine withdrawal period'),
      FieldSpec('fat', type: FieldType.number, label: 'Fat %', required: false),
      FieldSpec('snf', type: FieldType.number, label: 'SNF %', required: false),
    ]),
    FarmModule(name: production, navIcon: Icons.egg_outlined, recordIcon: Icons.egg, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('product', type: FieldType.choice, options: products),
      FieldSpec('batch', type: FieldType.batch, required: false),
      FieldSpec('animal', type: FieldType.animal, required: false),
      FieldSpec('quantity', type: FieldType.number, hint: 'Total produced or harvested'),
      FieldSpec('unit', type: FieldType.choice, options: Units.productUnits),
      FieldSpec('saleable', type: FieldType.number, label: 'Saleable quantity', required: false, hint: 'e.g. eggs fit for sale; defaults to the total'),
      FieldSpec('damaged', type: FieldType.number, label: 'Broken / damaged', required: false),
      FieldSpec('headCount', type: FieldType.number, label: 'Animals removed', required: false, hint: 'For harvests: fish/birds taken out of the batch'),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: productUsage, navIcon: Icons.outbox_outlined, recordIcon: Icons.outbox, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('product', type: FieldType.choice, options: products),
      FieldSpec('usage', type: FieldType.choice, options: ['Internal use', 'Discarded / wasted', 'Spoiled', 'Given away', 'Processing']),
      FieldSpec('quantity', type: FieldType.number),
      FieldSpec('unit', type: FieldType.choice, options: Units.productUnits),
      FieldSpec('batch', type: FieldType.batch, required: false),
      FieldSpec('notes', required: false),
    ]),
    // ----------------------------------------------------------------- Health
    FarmModule(name: health, navIcon: Icons.medical_services_outlined, recordIcon: Icons.medical_services, specs: [
      FieldSpec('animal', type: FieldType.animal, required: false),
      FieldSpec('batch', type: FieldType.batch, required: false, hint: 'For a flock or pond instead of one animal'),
      FieldSpec('date', type: FieldType.date),
      FieldSpec('type', type: FieldType.choice, options: ['Vaccination', 'Medication', 'Treatment', 'Vet visit', 'Deworming', 'Disease / symptoms', 'Check-up']),
      FieldSpec('details', hint: 'Symptoms, diagnosis or vaccine name'),
      FieldSpec('medicine', required: false, hint: 'As prescribed by your vet — the app does not suggest doses'),
      FieldSpec('vet', label: 'Vet / technician', required: false),
      FieldSpec('withdrawalDays', type: FieldType.number, label: 'Milk/meat withdrawal (days)', required: false, hint: 'Milk is held back from sale for this many days'),
      FieldSpec('cost', type: FieldType.number, required: false, hint: 'Counted in profit — do not enter it again as an expense'),
      FieldSpec('next', type: FieldType.date, label: 'Next due', required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Scheduled', 'Follow-up', 'Completed']),
    ]),
    FarmModule(name: illness, navIcon: Icons.sick_outlined, recordIcon: Icons.sick, specs: [
      FieldSpec('animal', type: FieldType.animal),
      FieldSpec('species', computed: true, required: false),
      FieldSpec('noticedAt', type: FieldType.dateTime, label: 'Symptoms first noticed'),
      FieldSpec('reportedAt', type: FieldType.dateTime, label: 'Reported on'),
      FieldSpec('reportedBy', label: 'Reported by'),
      FieldSpec('symptoms', label: 'Main symptoms', hint: 'What you see, e.g. not eating, coughing, swollen udder, limping'),
      FieldSpec('dangerSigns', type: FieldType.multiChoice, options: dangerSigns, required: false, label: 'Life-threatening signs', hint: 'Tick any you see — call a veterinarian immediately'),
      FieldSpec('observations', label: 'Additional observations', required: false),
      FieldSpec('appetite', type: FieldType.choice, options: ['Normal', 'Reduced', 'Not eating', 'Not checked']),
      FieldSpec('water', type: FieldType.choice, label: 'Water intake', options: ['Normal', 'Reduced', 'Increased', 'Not drinking', 'Not checked']),
      FieldSpec('milkChange', type: FieldType.choice, label: 'Milk production change', options: ['No change', 'Decreased', 'Stopped', 'Not milking / not applicable', 'Not checked']),
      FieldSpec('behaviour', label: 'Activity / behaviour change', required: false),
      FieldSpec('temperature', type: FieldType.number, label: 'Body temperature', required: false, hint: 'Leave blank if not measured — a normal reading does not rule out illness'),
      FieldSpec('tempUnit', type: FieldType.choice, label: 'Temperature unit', options: ['°C', '°F'], required: false),
      FieldSpec('injury', label: 'Visible injury or abnormality', required: false),
      FieldSpec('severity', type: FieldType.choice, options: severities),
      FieldSpec('suspectedCause', label: 'Suspected cause (unconfirmed)', required: false, hint: 'Your guess only — not a diagnosis'),
      FieldSpec('vetName', label: 'Veterinarian', required: false),
      FieldSpec('vetPhone', type: FieldType.phone, label: 'Veterinarian phone', required: false),
      FieldSpec('notes', required: false),
      FieldSpec('stage', label: 'Current stage', computed: true, required: false),
      FieldSpec('diagnosisStatus', label: 'Diagnosis status', computed: true, required: false),
      FieldSpec('diagnosis', label: 'Veterinarian’s diagnosis', computed: true, required: false),
      FieldSpec('closure', label: 'Outcome', computed: true, required: false),
      FieldSpec('closedOn', label: 'Recovered / closed on', computed: true, required: false),
      FieldSpec('closureNotes', label: 'Recovery / closure notes', computed: true, required: false),
      FieldSpec('reopenedCount', label: 'Times reopened', computed: true, required: false),
    ]),
    FarmModule(name: consultations, navIcon: Icons.local_hospital_outlined, recordIcon: Icons.local_hospital, specs: [
      FieldSpec('illness', type: FieldType.illness),
      FieldSpec('animal', computed: true, required: false),
      FieldSpec('date', type: FieldType.date, label: 'Consultation date'),
      FieldSpec('vetName', label: 'Veterinarian'),
      FieldSpec('vetPhone', type: FieldType.phone, label: 'Contact number', required: false),
      FieldSpec('observations', label: 'Clinical observations'),
      FieldSpec('diagnosis', label: 'Diagnosis given by the veterinarian', required: false),
      FieldSpec('diagnosisStatus', type: FieldType.choice, options: [diagNotEvaluated, diagSuspected, diagConfirmed], hint: 'Choose "Veterinarian confirmed" only if the vet confirmed it'),
      FieldSpec('recommendedTreatment', label: 'Recommended treatment', required: false),
      FieldSpec('prescriptionRef', label: 'Prescription reference / notes', required: false),
      FieldSpec('fee', type: FieldType.number, label: 'Consultation fee', required: false),
      FieldSpec('nextDate', type: FieldType.date, label: 'Next consultation', required: false),
      FieldSpec('instructions', label: 'Additional instructions', required: false),
    ]),
    FarmModule(name: treatments, navIcon: Icons.medication_outlined, recordIcon: Icons.medication, specs: [
      FieldSpec('illness', type: FieldType.illness),
      FieldSpec('animal', computed: true, required: false),
      FieldSpec('startDate', type: FieldType.date, label: 'Treatment start'),
      FieldSpec('endDate', type: FieldType.date, label: 'Planned end', required: false, hint: 'The animal is NOT marked recovered when this date passes'),
      FieldSpec('medicine', label: 'Medicine name'),
      FieldSpec('activeIngredient', label: 'Active ingredient', required: false),
      FieldSpec('medicineType',
          type: FieldType.choice,
          label: 'Medicine type',
          options: ['Antibiotic', 'Anti-inflammatory / pain relief', 'Antiparasitic', 'Vitamin / mineral', 'Fluid / electrolyte', 'Topical / wound care', 'Other']),
      FieldSpec('dose', label: 'Prescribed dose', hint: 'Exactly as written by the veterinarian — the app never calculates doses'),
      FieldSpec('doseUnit', label: 'Dose unit', hint: 'e.g. ml, mg, tablet, sachet'),
      FieldSpec('route',
          type: FieldType.choice, options: ['Oral', 'Intramuscular (IM)', 'Intravenous (IV)', 'Subcutaneous (SC)', 'Intramammary', 'Topical', 'Other'], required: false, hint: 'Only as prescribed'),
      FieldSpec('frequency', label: 'Frequency (as prescribed)', hint: 'e.g. once daily for 3 days'),
      FieldSpec('prescribedBy', label: 'Prescribing veterinarian'),
      FieldSpec('prescriptionRef', label: 'Prescription reference', required: false, hint: 'Entered prescriptions are not verified by the app'),
      FieldSpec('stockItem', type: FieldType.inventoryItem, label: 'Take from stock', required: false, hint: 'If the medicine is in Inventory, each given dose takes stock out'),
      FieldSpec('stockPerDose', type: FieldType.number, label: 'Stock used per dose', required: false, hint: 'In the stock item’s unit, e.g. 1 vial'),
      FieldSpec('withdrawalDays', type: FieldType.number, label: 'Milk/meat withdrawal (days)', required: false, hint: 'From the prescription — milk is held back from sale'),
      FieldSpec('cost', type: FieldType.number, label: 'Treatment cost', required: false, hint: 'Counted in profit — do not enter it again as an expense'),
      FieldSpec('outcome',
          type: FieldType.choice,
          label: 'Treatment status',
          options: [treatmentOngoing, 'Completed', 'Discontinued by vet', 'Changed by vet', 'Stopped — other reason'],
          hint: 'Changed only by you, never automatically'),
      FieldSpec('outcomeNotes', label: 'Reason / outcome notes', required: false),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: medication, navIcon: Icons.vaccines_outlined, recordIcon: Icons.vaccines, specs: [
      FieldSpec('treatment', type: FieldType.treatment),
      FieldSpec('animal', computed: true, required: false),
      FieldSpec('illness', computed: true, required: false),
      FieldSpec('medicine', computed: true, required: false),
      FieldSpec('status', type: FieldType.choice, options: [medScheduled, medGiven, medDelayed, medMissed, medDiscontinued]),
      FieldSpec('scheduledAt', type: FieldType.dateTime, label: 'Scheduled for', required: false),
      FieldSpec('givenAt', type: FieldType.dateTime, label: 'Given at', required: false),
      FieldSpec('doseGiven', label: 'Dose given', required: false, hint: 'As prescribed — defaults to the prescribed dose'),
      FieldSpec('administeredBy', label: 'Given by', required: false),
      FieldSpec('reason', label: 'Reason (missed / delayed / discontinued)', required: false),
      FieldSpec('sideEffects', label: 'Side effects / reactions', required: false, hint: 'If you see a reaction, contact the veterinarian before the next dose'),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: followUps, navIcon: Icons.event_repeat_outlined, recordIcon: Icons.event_repeat, specs: [
      FieldSpec('illness', type: FieldType.illness),
      FieldSpec('animal', computed: true, required: false),
      FieldSpec('dueDate', type: FieldType.date, label: 'Due date'),
      FieldSpec('type', type: FieldType.choice, options: ['Farm check', 'Vet visit', 'Medication review', 'Re-examination']),
      FieldSpec('assignedTo', label: 'Assigned to', required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Scheduled', 'Done', 'Missed', 'Cancelled']),
      FieldSpec('doneDate', type: FieldType.date, label: 'Done on', required: false),
      FieldSpec('progress', type: FieldType.choice, label: 'Symptoms since last check', options: ['Improved', 'Unchanged', 'Worsened'], required: false),
      FieldSpec('observations', required: false),
      FieldSpec('vetAssessment', label: 'Veterinarian’s assessment', required: false),
      FieldSpec('nextAction',
          type: FieldType.choice,
          label: 'Next step',
          options: ['Continue treatment', 'Treatment finished — decide on recovery', 'Refer to veterinary hospital', 'Another follow-up needed', 'Other'],
          required: false),
      FieldSpec('notes', required: false),
    ]),
    // ------------------------------------------------------------------ Money
    FarmModule(name: purchases, navIcon: Icons.shopping_bag_outlined, recordIcon: Icons.shopping_bag, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('supplier'),
      FieldSpec('item'),
      FieldSpec('qty'),
      FieldSpec('amount', type: FieldType.number),
      FieldSpec('status', type: FieldType.choice, options: ['Received', 'Ordered', 'Due']),
      FieldSpec('approval',
          type: FieldType.choice, label: 'Owner approval', options: approvals, required: false, ownerOnly: true, hint: 'Set by the app: above the owner’s limit, a manager’s entry waits for approval'),
      FieldSpec('decisionNote', label: 'Owner’s note', required: false, ownerOnly: true),
    ]),
    FarmModule(name: sales, navIcon: Icons.point_of_sale_outlined, recordIcon: Icons.point_of_sale, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('product', type: FieldType.choice, options: saleProducts),
      FieldSpec('customer', type: FieldType.customer),
      FieldSpec('animal', type: FieldType.animal, required: false, hint: 'For a live animal sale (marks it as Sold)'),
      FieldSpec('batch', type: FieldType.batch, required: false),
      FieldSpec('item', label: 'Description', required: false),
      FieldSpec('qty', type: FieldType.number, label: 'Quantity sold'),
      FieldSpec('unit', type: FieldType.choice, options: Units.productUnits),
      FieldSpec('unitPrice', type: FieldType.number, label: 'Price per unit'),
      FieldSpec('headCount', type: FieldType.number, label: 'Animals / birds sold', required: false, hint: 'Reduces the batch head count'),
      FieldSpec('gross', type: FieldType.number, label: 'Gross sales', computed: true, required: false),
      FieldSpec('discount', type: FieldType.number, required: false),
      FieldSpec('deductions', type: FieldType.number, label: 'Sales deductions', required: false, hint: 'Commission, market or transport charges borne by the farm'),
      FieldSpec('amount', type: FieldType.number, label: 'Net sales', computed: true, required: false),
      FieldSpec('paidAtSale', type: FieldType.number, label: 'Paid at sale', required: false, hint: 'Later payments go in Payments Received'),
      FieldSpec('paid', type: FieldType.number, label: 'Total received', computed: true, required: false),
      FieldSpec('due', type: FieldType.number, label: 'Outstanding', computed: true, required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Paid', 'Partial', 'Due'], computed: true),
    ]),
    FarmModule(name: collections, navIcon: Icons.payments_outlined, recordIcon: Icons.payments, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('sale', type: FieldType.sale),
      FieldSpec('customer', computed: true, required: false),
      FieldSpec('amount', type: FieldType.number),
      FieldSpec('method', type: FieldType.choice, options: paymentMethods),
      FieldSpec('reference', required: false),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: customers, navIcon: Icons.people_outline, recordIcon: Icons.people, specs: [
      FieldSpec('name'),
      FieldSpec('phone', type: FieldType.phone),
      FieldSpec('type', type: FieldType.choice, options: ['Wholesale', 'Retail', 'Collection centre', 'Trader', 'Other']),
      FieldSpec('balance', type: FieldType.number, label: 'Opening balance', hint: 'Owed before using this app'),
      FieldSpec('status', type: FieldType.choice, options: ['Active', 'Due', 'Inactive']),
    ]),
    FarmModule(name: expenses, navIcon: Icons.account_balance_wallet_outlined, recordIcon: Icons.payments, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('category', type: FieldType.choice, options: expenseCategories),
      FieldSpec('amount', type: FieldType.number),
      FieldSpec('description'),
      FieldSpec('scope', type: FieldType.choice, label: 'Charged to', options: scopes),
      FieldSpec('animal', type: FieldType.animal, required: false),
      FieldSpec('batch', type: FieldType.batch, required: false),
      FieldSpec('location', type: FieldType.location, required: false),
      FieldSpec('allocation', type: FieldType.choice, label: 'Share farm-wide cost', options: allocations, required: false, hint: 'How a farm-wide cost is shared in animal and batch reports'),
      FieldSpec('payment', type: FieldType.choice, options: ['Paid', 'Due']),
      FieldSpec('paymentMethod', type: FieldType.choice, label: 'Payment method', options: paymentMethods, required: false),
      FieldSpec('reference', label: 'Receipt / reference', required: false),
      FieldSpec('vendor', required: false),
      FieldSpec('notes', required: false),
      FieldSpec('approval',
          type: FieldType.choice, label: 'Owner approval', options: approvals, required: false, ownerOnly: true, hint: 'Above the owner’s limit, a manager’s expense is not counted until approved'),
      FieldSpec('decisionNote', label: 'Owner’s note', required: false, ownerOnly: true),
    ]),
    // ------------------------------------------------------- Team & control
    FarmModule(name: staff, navIcon: Icons.badge_outlined, recordIcon: Icons.badge, specs: [
      FieldSpec('name', label: 'Full name'),
      FieldSpec('job', type: FieldType.choice, label: 'Job', options: staffJobs),
      FieldSpec('phone', type: FieldType.phone, required: false),
      FieldSpec('joinDate', type: FieldType.date, label: 'Joined on', required: false),
      FieldSpec('wage', type: FieldType.number, label: 'Monthly wage', required: false, hint: 'Seen only by users who may see finances'),
      FieldSpec('status', type: FieldType.choice, options: ['Active', 'Inactive']),
      FieldSpec('notes', required: false),
    ]),
    FarmModule(name: tasks, navIcon: Icons.checklist_outlined, recordIcon: Icons.checklist, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('task', label: 'Task', hint: 'e.g. Clean Shed A, feed the fattening bulls'),
      FieldSpec('area', type: FieldType.choice, options: taskAreas),
      FieldSpec('assignedTo', type: FieldType.staff, label: 'Assigned to'),
      FieldSpec('shift', type: FieldType.choice, options: shifts),
      FieldSpec('status', type: FieldType.choice, options: ['Pending', 'Done', 'Not done']),
      FieldSpec('checkedBy', label: 'Checked by', computed: true, required: false, hint: 'Who confirmed the task was done'),
      FieldSpec('notes', required: false, hint: 'Required when a task was not done'),
    ]),
    FarmModule(name: requests, navIcon: Icons.approval_outlined, recordIcon: Icons.approval, specs: [
      FieldSpec('date', type: FieldType.date),
      FieldSpec('type', type: FieldType.choice, options: requestTypes),
      FieldSpec('title', label: 'What is needed'),
      FieldSpec('details', required: false, hint: 'Why it is needed, supplier, quantity…'),
      FieldSpec('estimatedAmount', type: FieldType.number, label: 'Estimated cost', required: false),
      FieldSpec('neededBy', type: FieldType.date, label: 'Needed by', required: false),
      FieldSpec('requestedBy', label: 'Requested by', computed: true, required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Pending', 'Approved', 'Rejected'], required: false, ownerOnly: true),
      FieldSpec('decisionNote', label: 'Owner’s note', required: false, ownerOnly: true),
      FieldSpec('decidedBy', label: 'Decided by', computed: true, required: false),
    ]),
    FarmModule(name: managerReports, navIcon: Icons.summarize_outlined, recordIcon: Icons.summarize, specs: [
      FieldSpec('date', type: FieldType.date, label: 'Report date'),
      FieldSpec('period', type: FieldType.choice, options: ['Daily', 'Monthly']),
      FieldSpec('summary', label: 'Summary', hint: 'Filled in from the records — milk, feed, health, stock, sales and expenses'),
      FieldSpec('issues', label: 'Treatment & stock problems', required: false),
      FieldSpec('notes', label: 'Notes for the owner', required: false),
      FieldSpec('submittedBy', label: 'Submitted by', computed: true, required: false),
      FieldSpec('status', type: FieldType.choice, options: ['Submitted', 'Reviewed'], required: false, ownerOnly: true),
      FieldSpec('ownerComment', label: 'Owner’s comment', required: false, ownerOnly: true),
    ]),
  ];

  static const _fallbackFields = ['name', 'date', 'details', 'status'];

  static FarmModule? byName(String name) {
    for (final m in all) {
      if (m.name == name) return m;
    }
    return null;
  }

  static IconData recordIconFor(String name) => byName(name)?.recordIcon ?? Icons.description;

  /// The input spec for [field]; unknown columns are plain required text.
  static FieldSpec specFor(String module, String field) {
    for (final s in byName(module)?.specs ?? const <FieldSpec>[]) {
      if (s.key == field) return s;
    }
    return FieldSpec(field);
  }

  static bool isInternal(String key) => key.startsWith('_');

  /// Form fields for [module]: every field the module defines, followed by
  /// any extra columns an older or imported record carries, so nothing is lost
  /// when it is edited.
  static List<String> fieldsFor(String module, Map<String, dynamic> sample) {
    final defined = byName(module)?.fields;
    if (defined == null) return sample.isNotEmpty ? sample.keys.where((k) => k != 'id' && !isInternal(k)).toList() : _fallbackFields;
    return [...defined, ...sample.keys.where((k) => k != 'id' && !isInternal(k) && !defined.contains(k))];
  }
}
