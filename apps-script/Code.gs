// ShrADD — bank transaction alert parser
// Reads transaction alert emails from DBS and Trust, parses them, and writes
// each one to Firestore's `transactions` collection.

const CONFIG = {
  firestoreProjectId: 'expense-tracker-7d7f1',
  gmailSearchQuery: '(subject:"Card Transaction Alert" OR subject:"Transaction Alerts" OR subject:"Yay! Transaction successful" OR subject:"received a transfer") -label:dbs-processed',
  processedLabel: 'dbs-processed'
  // Discord webhook URL lives in Script Properties (DISCORD_WEBHOOK_URL), not
  // here — same place as FIREBASE_PRIVATE_KEY and ANTHROPIC_API_KEY, so this
  // file has no secrets in it and is safe to keep in source control.
};

function processAlerts() {
  processBatch_(true, 50);
}

// Run this to catch up on a backlog (e.g. a bank's emails matched the search
// query for the first time and years of history are suddenly "unprocessed")
// without flooding Discord. Writes still go to Firestore and threads still
// get labeled, just no notifications fire. Capped at 25 threads per run so it
// can't blow the 6-minute execution limit — if there's more left to do, the
// log will tell you to run it again.
function backfillSilently() {
  processBatch_(false, 25);
}

// Shared core for both the live 5-minute trigger and the silent backfill.
// `maxThreads` bounds how many threads GmailApp.search returns, so a single
// run can never process an unbounded backlog in one go.
function processBatch_(notify, maxThreads) {
  const label = getOrCreateLabel_(CONFIG.processedLabel);
  const threads = GmailApp.search(CONFIG.gmailSearchQuery, 0, maxThreads);
  const customRules = fetchMerchantRules_();
  // Fetched once per batch (not per transaction) so the LLM fallback in
  // categorize_ never invents a category that doesn't exist in your app.
  const availableCategories = fetchCategoryNames_();

  Logger.log('Processing ' + threads.length + ' thread(s) (notify=' + notify + ').');

  threads.forEach(thread => {
    thread.getMessages().forEach(message => {
      const body = message.getPlainBody();
      const parsed = parseAlert_(message.getSubject(), body, message.getDate(), customRules, availableCategories);
      if (!parsed) {
        Logger.log('Could not parse message: ' + message.getSubject());
        return;
      }
      // Using the Gmail message ID as the Firestore document ID makes this
      // idempotent: reprocessing the same email overwrites the same document
      // instead of creating a duplicate.
      writeTransactionToFirestore_(parsed, message.getId());

      if (notify) {
        const amountText = 'SGD ' + parsed.amount.toFixed(2);

        if (parsed.type === 'income') {
          sendDiscordNotification_('💵 New income logged', parsed.merchant + ' — ' + amountText);
        } else {
          sendDiscordNotification_('💰 New expense logged', parsed.merchant + ' — ' + amountText + ' (' + parsed.category + ')');

          if (parsed.category === 'Uncategorized') {
            sendDiscordNotification_('⚠️ Expense needs categorisation', parsed.merchant + ' — ' + amountText);
          }
        }
      }
    });
    thread.addLabel(label);
  });

  if (notify) {
    checkOverallBudgetThreshold_();
  }

  if (threads.length === maxThreads) {
    Logger.log('Hit the batch limit (' + maxThreads + ') — there may be more unprocessed threads left. Run this again to continue.');
  } else {
    Logger.log('Done — no more unprocessed threads matched the search query.');
  }
}

// Checks total spend for the current month against the overall budget set in
// the app's Settings screen, and sends a Discord alert once per threshold per
// month (80%, then 100%) — not every single run, so it doesn't spam you.
function checkOverallBudgetThreshold_() {
  const token = getFirestoreAccessToken_();
  const budgetUrl = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents/budgets/OVERALL_BUDGET`;
  const budgetResponse = UrlFetchApp.fetch(budgetUrl, {
    method: 'get',
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });
  if (budgetResponse.getResponseCode() >= 300) {
    Logger.log('No overall budget document found (' + budgetResponse.getResponseCode() + '): ' + budgetResponse.getContentText());
    return;
  }
  const budgetData = JSON.parse(budgetResponse.getContentText());
  const budget = budgetData.fields && budgetData.fields.limit ? budgetData.fields.limit.doubleValue : null;
  if (!budget || budget <= 0) {
    Logger.log('Overall budget document exists but has no valid limit field.');
    return;
  }

  const now = new Date();
  const monthKey = now.getFullYear() + '-' + (now.getMonth() + 1);
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
  const monthEnd = new Date(now.getFullYear(), now.getMonth() + 1, 1);

  const monthTotal = fetchTransactionsTotalInRange_(token, monthStart, monthEnd);
  if (monthTotal === null) {
    return;
  }

  const percentage = (monthTotal / budget) * 100;
  const props = PropertiesService.getScriptProperties();
  const notifiedKey = 'notifiedThresholds_' + monthKey;
  const alreadyNotified = (props.getProperty(notifiedKey) || '').split(',').filter(String);

  Logger.log('Budget check: SGD ' + monthTotal.toFixed(2) + ' of SGD ' + budget.toFixed(2) + ' (' + percentage.toFixed(1) + '%). Already notified this month: [' + alreadyNotified.join(', ') + ']');

  [80, 100].forEach(threshold => {
    const thresholdStr = String(threshold);
    if (percentage >= threshold && alreadyNotified.indexOf(thresholdStr) === -1) {
      const emoji = threshold >= 100 ? '🚨' : '⚠️';
      sendDiscordNotification_(
        emoji + ' ' + threshold + '% of monthly budget reached',
        'SGD ' + monthTotal.toFixed(2) + ' of SGD ' + budget.toFixed(2) + ' spent this month.'
      );
      alreadyNotified.push(thresholdStr);
    }
  });

  props.setProperty(notifiedKey, alreadyNotified.join(','));
}

// Sums the `amount` field of transactions whose `date` falls in [start, end)
// using a proper Firestore query, instead of listing every document in the
// collection and filtering client-side. This runs every 5 minutes via the
// trigger, so without this it re-reads your ENTIRE transaction history on
// every run — the main thing that was burning through the free Firestore
// read quota.
function fetchTransactionsTotalInRange_(token, start, end) {
  const url = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents:runQuery`;
  const body = {
    structuredQuery: {
      from: [{ collectionId: 'transactions' }],
      where: {
        compositeFilter: {
          op: 'AND',
          filters: [
            {
              fieldFilter: {
                field: { fieldPath: 'date' },
                op: 'GREATER_THAN_OR_EQUAL',
                value: { timestampValue: start.toISOString() }
              }
            },
            {
              fieldFilter: {
                field: { fieldPath: 'date' },
                op: 'LESS_THAN',
                value: { timestampValue: end.toISOString() }
              }
            }
          ]
        }
      }
    }
  };

  const response = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + token },
    payload: JSON.stringify(body),
    muteHttpExceptions: true
  });

  if (response.getResponseCode() >= 300) {
    Logger.log('Failed to query transactions in range: ' + response.getContentText());
    return null;
  }

  const results = JSON.parse(response.getContentText());
  let total = 0;
  results.forEach(entry => {
    if (!entry.document) return;
    const fields = entry.document.fields || {};
    // Budget tracking is spend-only — income transactions live in the same
    // collection but must never count toward "how much you've spent".
    const type = fields.type ? fields.type.stringValue : 'expense';
    if (type === 'expense' && fields.amount) {
      total += fields.amount.doubleValue;
    }
  });
  return total;
}

function sendDiscordNotification_(title, message) {
  const webhookUrl = PropertiesService.getScriptProperties().getProperty('DISCORD_WEBHOOK_URL');
  if (!webhookUrl) {
    Logger.log('No DISCORD_WEBHOOK_URL set in Script Properties — skipping notification.');
    return;
  }
  const payload = {
    username: 'shrADD',
    content: '**' + title + '**\n' + message
  };
  const response = UrlFetchApp.fetch(webhookUrl, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });
  Logger.log('Discord response (' + response.getResponseCode() + '): ' + response.getContentText());
}

// Picks the right parser based on the email's subject line, since DBS and
// Trust (and any bank added later) each have their own alert format.
function parseAlert_(subject, body, receivedDate, customRules, availableCategories) {
  if (subject.indexOf('Transaction successful') !== -1) {
    return parseTrustAlert_(body, receivedDate, customRules, availableCategories);
  }
  if (subject.indexOf('received a transfer') !== -1) {
    return parseDbsIncomeAlert_(body, receivedDate);
  }
  return parseDbsAlert_(body, receivedDate, customRules, availableCategories);
}

// Trust alert body looks like:
// "You've spent SGD 11.76 at Shein Shein SG on 4 Aug 2026 09:19SGT with Trust Link card."
function parseTrustAlert_(body, receivedDate, customRules, availableCategories) {
  const match = body.match(/You've spent SGD\s*([\d,]+\.\d{2})\s+at\s+(.+?)\s+on\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2})/i);
  if (!match) {
    return null;
  }

  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const day = parseInt(match[3], 10);
  const monthIndex = months.indexOf(match[4]);
  const year = parseInt(match[5], 10);
  const hour = parseInt(match[6], 10);
  const minute = parseInt(match[7], 10);
  const date = new Date(year, monthIndex, day, hour, minute);

  return {
    merchant: match[2].trim(),
    amount: parseFloat(match[1].replace(/,/g, '')),
    date: date,
    category: categorize_(match[2].trim(), customRules, availableCategories),
    type: 'expense'
  };
}

function parseDbsAlert_(body, receivedDate, customRules, availableCategories) {
  const amountMatch = body.match(/Amount:\s*SGD\s*([\d,]+\.\d{2})/i);
  const merchantMatch = body.match(/To:\s*(.+)/);
  const dateTimeMatch = body.match(/Date & Time:\s*(\d{1,2})\s+(\w{3})\s+(\d{2}):(\d{2})/i);

  if (!amountMatch || !merchantMatch || !dateTimeMatch) {
    return null;
  }

  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const day = parseInt(dateTimeMatch[1], 10);
  const monthIndex = months.indexOf(dateTimeMatch[2]);
  const hour = parseInt(dateTimeMatch[3], 10);
  const minute = parseInt(dateTimeMatch[4], 10);
  const year = receivedDate.getFullYear();
  const date = new Date(year, monthIndex, day, hour, minute);

  return {
    merchant: merchantMatch[1].trim(),
    amount: parseFloat(amountMatch[1].replace(/,/g, '')),
    date: date,
    category: categorize_(merchantMatch[1].trim(), customRules, availableCategories),
    type: 'expense'
  };
}

// DBS "You've received a transfer" alert body looks like:
// "You have received SGD 10.00 via FAST transfer on 04 Sep 2026 16:36 SGT.
//  From: Airwallex (Singapore) Pte Ltd
//  To: Your DBS/ POSB account ending 8639"
// Income transactions skip auto-categorization entirely (category is always
// "Income") and instead run the sender name through resolveIncomeSource_ so
// a payment processor's name (e.g. "Airwallex") can map to who it's really
// from (e.g. "Ottodot").
function parseDbsIncomeAlert_(body, receivedDate) {
  const amountMatch = body.match(/You have received SGD\s*([\d,]+\.\d{2})\s+via\s+\S+\s+transfer\s+on\s+(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2})/i);
  const fromMatch = body.match(/From:\s*(.+)/i);

  if (!amountMatch || !fromMatch) {
    return null;
  }

  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const day = parseInt(amountMatch[2], 10);
  const monthIndex = months.indexOf(amountMatch[3]);
  const year = parseInt(amountMatch[4], 10);
  const hour = parseInt(amountMatch[5], 10);
  const minute = parseInt(amountMatch[6], 10);
  const date = new Date(year, monthIndex, day, hour, minute);

  return {
    merchant: resolveIncomeSource_(fromMatch[1].trim()),
    amount: parseFloat(amountMatch[1].replace(/,/g, '')),
    date: date,
    category: 'Income',
    type: 'income'
  };
}

// Maps a raw sender name from a bank alert to a friendlier label. Add entries
// as you notice recurring senders — e.g. a client who pays through a payment
// processor whose name on its own doesn't tell you who it actually is.
const INCOME_SOURCE_NAMES = {
  'airwallex': 'Ottodot',
  'mind stretcher': 'Mind Stretcher',
  'bluetree': 'Bluetree',
  'curious minds': 'Curious Minds',
  'allowance': 'Mastermath',
  'natarajan sriram': 'Pocket Money'
};

function resolveIncomeSource_(rawSender) {
  const lower = rawSender.toLowerCase();
  for (const key in INCOME_SOURCE_NAMES) {
    if (lower.indexOf(key) !== -1) return INCOME_SOURCE_NAMES[key];
  }
  return rawSender;
}

// Fetches the user's custom rules from the app's "Auto-Categorization Rules"
// screen (stored in Firestore's merchantRules collection). Checked before the
// hardcoded list below, so rules set in the app always take priority.
function fetchMerchantRules_() {
  const token = getFirestoreAccessToken_();
  const url = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents/merchantRules?pageSize=300`;
  const response = UrlFetchApp.fetch(url, {
    method: 'get',
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });
  if (response.getResponseCode() >= 300) {
    Logger.log('Failed to fetch merchant rules: ' + response.getContentText());
    return {};
  }
  const data = JSON.parse(response.getContentText());
  const documents = data.documents || [];
  const rules = {};
  documents.forEach(doc => {
    const category = doc.fields && doc.fields.category ? doc.fields.category.stringValue : null;
    if (category) {
      rules[doc.name.split('/').pop()] = category;
    }
  });
  return rules;
}

// Simple rule-based lookup. Add entries as you notice recurring merchants.
// Anything unmatched falls through to the LLM fallback (if configured), then
// finally "Uncategorized" for manual fix-up in the app.
const MERCHANT_CATEGORIES = {
  'fairprice': 'Food',
  'ntuc': 'Food',
  'grab': 'Transport',
  'gojek': 'Transport',
  'netflix': 'Subscriptions',
  'spotify': 'Subscriptions',
  'shopee': 'Shopping',
  'lazada': 'Shopping',
  'sp group': 'Utilities',
  'pizza': 'Food',
  'starbucks': 'Food',
  'coffee': 'Food'
};

// `availableCategories` is optional — pass it (fetched once per batch via
// fetchCategoryNames_) to enable the LLM fallback for anything your rules and
// the hardcoded list above don't catch. Omit it (or leave ANTHROPIC_API_KEY
// unset) and this behaves exactly as before, ending at "Uncategorized".
function categorize_(merchant, customRules, availableCategories) {
  const lower = merchant.toLowerCase();

  if (customRules) {
    for (const keyword in customRules) {
      if (lower.indexOf(keyword) !== -1) return customRules[keyword];
    }
  }

  for (const key in MERCHANT_CATEGORIES) {
    if (lower.indexOf(key) !== -1) return MERCHANT_CATEGORIES[key];
  }

  if (availableCategories && availableCategories.length > 0) {
    const guess = categorizeWithLLM_(merchant, availableCategories);
    if (guess) return guess;
  }

  return 'Uncategorized';
}

// Fetches the current list of category names from Firestore's `categories`
// collection, so the LLM can only ever pick from categories that actually
// exist in your app instead of inventing new ones.
function fetchCategoryNames_() {
  const token = getFirestoreAccessToken_();
  const url = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents/categories?pageSize=300`;
  const response = UrlFetchApp.fetch(url, {
    method: 'get',
    headers: { Authorization: 'Bearer ' + token },
    muteHttpExceptions: true
  });
  if (response.getResponseCode() >= 300) {
    Logger.log('Failed to fetch categories: ' + response.getContentText());
    return [];
  }
  const data = JSON.parse(response.getContentText());
  const documents = data.documents || [];
  return documents.map(doc => doc.name.split('/').pop());
}

// Last-resort categorizer: asks Claude to pick the best-fitting category for
// a merchant name out of your existing categories. Only called for
// transactions that didn't match a rule or the hardcoded list, so this is a
// rare call, not a per-transaction cost. Returns null (falls through to
// "Uncategorized") if the API key isn't set, the call fails, or the model's
// answer isn't one of the categories offered — never invents a new category.
function categorizeWithLLM_(merchant, availableCategories) {
  const apiKey = PropertiesService.getScriptProperties().getProperty('ANTHROPIC_API_KEY');
  if (!apiKey) {
    return null;
  }

  const prompt = 'Merchant name: "' + merchant + '"\n\n' +
    'Categories: ' + availableCategories.join(', ') + '\n\n' +
    'Reply with exactly one category name from the list above that best fits this merchant. ' +
    'If none fit reasonably well, reply with exactly: Uncategorized. ' +
    'Reply with the category name only, nothing else.';

  const response = UrlFetchApp.fetch('https://api.anthropic.com/v1/messages', {
    method: 'post',
    contentType: 'application/json',
    headers: {
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01'
    },
    payload: JSON.stringify({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 20,
      temperature: 0,
      messages: [{ role: 'user', content: prompt }]
    }),
    muteHttpExceptions: true
  });

  if (response.getResponseCode() >= 300) {
    Logger.log('LLM categorization call failed: ' + response.getContentText());
    return null;
  }

  const data = JSON.parse(response.getContentText());
  const text = data.content && data.content[0] ? data.content[0].text.trim() : '';

  // Guard against the model returning something outside the offered list —
  // only trust it if it echoed back one of your actual categories.
  if (availableCategories.indexOf(text) !== -1) {
    Logger.log('LLM categorized "' + merchant + '" as "' + text + '".');
    return text;
  }
  if (text !== 'Uncategorized') {
    Logger.log('LLM returned an unrecognized category ("' + text + '") for "' + merchant + '" — falling back to Uncategorized.');
  }
  return null;
}

function getOrCreateLabel_(name) {
  return GmailApp.getUserLabelByName(name) || GmailApp.createLabel(name);
}

function writeTransactionToFirestore_(transaction, docId) {
  const token = getFirestoreAccessToken_();
  const url = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents/transactions/${docId}`;

  const payload = {
    fields: {
      merchant: { stringValue: transaction.merchant },
      amount: { doubleValue: transaction.amount },
      date: { timestampValue: transaction.date.toISOString() },
      category: { stringValue: transaction.category },
      type: { stringValue: transaction.type || 'expense' }
    }
  };

  // PATCH to a specific document ID = create-or-overwrite (upsert), which is
  // what makes reprocessing safe.
  const response = UrlFetchApp.fetch(url, {
    method: 'patch',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + token },
    payload: JSON.stringify(payload),
    muteHttpExceptions: true
  });

  if (response.getResponseCode() >= 300) {
    throw new Error('Firestore write failed: ' + response.getContentText());
  }
}

function getFirestoreAccessToken_() {
  const service = getService_();
  if (!service.hasAccess()) {
    throw new Error('OAuth service has no access: ' + service.getLastError());
  }
  return service.getAccessToken();
}

function getService_() {
  const props = PropertiesService.getScriptProperties();
  const privateKey = getCleanedPrivateKey_();
  return OAuth2.createService('firestore')
    .setTokenUrl('https://oauth2.googleapis.com/token')
    .setPrivateKey(privateKey)
    .setIssuer(props.getProperty('FIREBASE_CLIENT_EMAIL'))
    .setPropertyStore(props)
    .setScope('https://www.googleapis.com/auth/datastore');
}

function getCleanedPrivateKey_() {
  const raw = PropertiesService.getScriptProperties().getProperty('FIREBASE_PRIVATE_KEY');
  return raw.trim().replace(/^"|"$/g, '').replace(/\\n/g, '\n').replace(/\r/g, '');
}

// Run this once manually from the Apps Script editor to test the whole
// pipeline against your most recent alert email before turning on the trigger.
function testRun() {
  processAlerts();
}

// Run this to confirm the Discord webhook is wired up correctly before
// relying on real transactions to test it.
function testDiscordNotification() {
  sendDiscordNotification_('Test notification', 'If you see this, the Discord webhook is working.');
}

// Run this to manually check your overall budget right now, instead of
// waiting for a new transaction email to trigger it. Check the log for the
// actual numbers even if no Discord alert fires.
function testBudgetCheck() {
  checkOverallBudgetThreshold_();
}

// Run this once to make processAlerts run automatically every 5 minutes.
// Safe to re-run — it clears any existing trigger for this function first,
// so you won't end up with duplicates.
function createTrigger() {
  ScriptApp.getProjectTriggers().forEach(trigger => {
    if (trigger.getHandlerFunction() === 'processAlerts') {
      ScriptApp.deleteTrigger(trigger);
    }
  });
  ScriptApp.newTrigger('processAlerts')
    .timeBased()
    .everyMinutes(5)
    .create();
}

// One-time cleanup: removes duplicate transactions already sitting in
// Firestore from before writes became idempotent. Keeps the first document
// in each duplicate group, deletes the rest. Safe to run more than once —
// if there's nothing left to dedupe, it just does nothing.
function deduplicateTransactions() {
  const token = getFirestoreAccessToken_();
  const baseUrl = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents/transactions`;

  const allDocuments = [];
  let pageToken = null;

  do {
    let listUrl = baseUrl + '?pageSize=300';
    if (pageToken) {
      listUrl += '&pageToken=' + encodeURIComponent(pageToken);
    }
    const response = UrlFetchApp.fetch(listUrl, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + token },
      muteHttpExceptions: true
    });
    if (response.getResponseCode() >= 300) {
      throw new Error('Failed to list transactions: ' + response.getContentText());
    }
    const data = JSON.parse(response.getContentText());
    allDocuments.push(...(data.documents || []));
    pageToken = data.nextPageToken || null;
  } while (pageToken);

  const seen = {};
  let deletedCount = 0;
  let failedCount = 0;

  allDocuments.forEach(doc => {
    const fields = doc.fields || {};
    const merchant = fields.merchant ? fields.merchant.stringValue : '';
    const amount = fields.amount ? fields.amount.doubleValue : 0;
    const date = fields.date ? fields.date.timestampValue : '';
    const key = merchant + '|' + amount + '|' + date;

    if (seen[key]) {
      const deleteUrl = 'https://firestore.googleapis.com/v1/' + doc.name;
      const deleteResponse = UrlFetchApp.fetch(deleteUrl, {
        method: 'delete',
        headers: { Authorization: 'Bearer ' + token },
        muteHttpExceptions: true
      });
      if (deleteResponse.getResponseCode() >= 300) {
        failedCount++;
        Logger.log('Failed to delete ' + doc.name + ': ' + deleteResponse.getContentText());
      } else {
        deletedCount++;
      }
    } else {
      seen[key] = true;
    }
  });

  Logger.log('Checked ' + allDocuments.length + ' documents total. Deleted ' + deletedCount + ', failed ' + failedCount + '.');
}

// Run this whenever you add/change a rule in the app and want it to also fix
// up transactions that were already logged before the rule existed. Goes
// through every transaction, and if its merchant matches a rule and the
// category differs, updates it to match.
function applyRulesToExistingTransactions() {
  const token = getFirestoreAccessToken_();
  const customRules = fetchMerchantRules_();
  const baseUrl = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents/transactions`;

  const allDocuments = [];
  let pageToken = null;
  do {
    let listUrl = baseUrl + '?pageSize=300';
    if (pageToken) {
      listUrl += '&pageToken=' + encodeURIComponent(pageToken);
    }
    const response = UrlFetchApp.fetch(listUrl, {
      method: 'get',
      headers: { Authorization: 'Bearer ' + token },
      muteHttpExceptions: true
    });
    if (response.getResponseCode() >= 300) {
      throw new Error('Failed to list transactions: ' + response.getContentText());
    }
    const data = JSON.parse(response.getContentText());
    allDocuments.push(...(data.documents || []));
    pageToken = data.nextPageToken || null;
  } while (pageToken);

  let updatedCount = 0;

  allDocuments.forEach(doc => {
    const fields = doc.fields || {};
    const type = fields.type ? fields.type.stringValue : 'expense';
    if (type !== 'expense') return;

    const merchant = fields.merchant ? fields.merchant.stringValue : '';
    const currentCategory = fields.category ? fields.category.stringValue : '';
    const lower = merchant.toLowerCase();

    let matchedCategory = null;
    for (const keyword in customRules) {
      if (lower.indexOf(keyword) !== -1) {
        matchedCategory = customRules[keyword];
        break;
      }
    }

    if (matchedCategory && matchedCategory !== currentCategory) {
      const docId = doc.name.split('/').pop();
      const updateUrl = baseUrl + '/' + docId + '?updateMask.fieldPaths=category';
      const updateResponse = UrlFetchApp.fetch(updateUrl, {
        method: 'patch',
        contentType: 'application/json',
        headers: { Authorization: 'Bearer ' + token },
        payload: JSON.stringify({ fields: { category: { stringValue: matchedCategory } } }),
        muteHttpExceptions: true
      });
      if (updateResponse.getResponseCode() < 300) {
        updatedCount++;
      } else {
        Logger.log('Failed to update ' + doc.name + ': ' + updateResponse.getContentText());
      }
    }
  });

  Logger.log('Checked ' + allDocuments.length + ' transactions. Updated ' + updatedCount + ' to match your rules.');
}

// Run this to have the LLM take a pass at transactions that are still
// "Uncategorized" (didn't match any rule or the hardcoded list at the time
// they were processed). Only queries Uncategorized docs (not your whole
// history) and caps at 30 per run to keep both Firestore reads and API calls
// small — run it again if the log says there's more.
function categorizeUncategorizedWithLLM() {
  const apiKey = PropertiesService.getScriptProperties().getProperty('ANTHROPIC_API_KEY');
  if (!apiKey) {
    Logger.log('No ANTHROPIC_API_KEY set in Script Properties — nothing to do.');
    return;
  }

  const token = getFirestoreAccessToken_();
  const customRules = fetchMerchantRules_();
  const availableCategories = fetchCategoryNames_();
  const baseUrl = `https://firestore.googleapis.com/v1/projects/${CONFIG.firestoreProjectId}/databases/(default)/documents`;
  const batchLimit = 30;

  const queryResponse = UrlFetchApp.fetch(baseUrl + ':runQuery', {
    method: 'post',
    contentType: 'application/json',
    headers: { Authorization: 'Bearer ' + token },
    payload: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'transactions' }],
        where: {
          fieldFilter: {
            field: { fieldPath: 'category' },
            op: 'EQUAL',
            value: { stringValue: 'Uncategorized' }
          }
        },
        limit: batchLimit
      }
    }),
    muteHttpExceptions: true
  });

  if (queryResponse.getResponseCode() >= 300) {
    Logger.log('Failed to query uncategorized transactions: ' + queryResponse.getContentText());
    return;
  }

  const results = JSON.parse(queryResponse.getContentText()).filter(entry => entry.document);
  let updatedCount = 0;

  results.forEach(entry => {
    const doc = entry.document;
    const fields = doc.fields || {};
    const merchant = fields.merchant ? fields.merchant.stringValue : '';
    if (!merchant) return;

    const category = categorize_(merchant, customRules, availableCategories);
    if (category === 'Uncategorized') return;

    const docId = doc.name.split('/').pop();
    const updateResponse = UrlFetchApp.fetch(baseUrl + '/transactions/' + docId + '?updateMask.fieldPaths=category', {
      method: 'patch',
      contentType: 'application/json',
      headers: { Authorization: 'Bearer ' + token },
      payload: JSON.stringify({ fields: { category: { stringValue: category } } }),
      muteHttpExceptions: true
    });
    if (updateResponse.getResponseCode() < 300) {
      updatedCount++;
    } else {
      Logger.log('Failed to update ' + doc.name + ': ' + updateResponse.getContentText());
    }
  });

  Logger.log('Checked ' + results.length + ' uncategorized transaction(s). Updated ' + updatedCount + '.');
  if (results.length === batchLimit) {
    Logger.log('Hit the batch limit (' + batchLimit + ') — there may be more. Run this again to continue.');
  }
}

// Run this to confirm the LLM fallback is working before relying on it —
// picks an obviously-not-hardcoded merchant name and shows what category it
// gets assigned. Uses your real category list but doesn't write anything.
function testLLMCategorization() {
  const apiKey = PropertiesService.getScriptProperties().getProperty('ANTHROPIC_API_KEY');
  if (!apiKey) {
    Logger.log('No ANTHROPIC_API_KEY set in Script Properties. Add one (Project Settings → Script Properties) to enable this.');
    return;
  }
  const availableCategories = fetchCategoryNames_();
  Logger.log('Available categories: ' + availableCategories.join(', '));
  const result = categorizeWithLLM_('Din Tai Fung Paragon', availableCategories);
  Logger.log('Result: ' + (result || 'null (fell through to Uncategorized)'));
}

// Safe diagnostic: logs only shape/structure of the key, never the actual
// key material, so you can share the output with me without exposing anything.
function debugKey() {
  const key = getCleanedPrivateKey_();
  Logger.log('length: ' + key.length);
  Logger.log('startsWithBegin: ' + key.startsWith('-----BEGIN PRIVATE KEY-----'));
  Logger.log('endsWithEnd: ' + key.trim().endsWith('-----END PRIVATE KEY-----'));
  Logger.log('lineCount: ' + key.split('\n').length);
  Logger.log('hasLiteralBackslashN: ' + key.includes('\\n'));
}
