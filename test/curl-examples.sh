#!/usr/bin/env bash
# Local smoke tests for RE-00. Workflow must be ACTIVE (or use /webhook-test/ while in Test mode).
set -euo pipefail
# Local by default. To go through your tunnel instead:
#   BASE=https://landline-sternum-fence.ngrok-free.dev/webhook bash test/curl-examples.sh
# curl is not treated as a browser, so ngrok's interstitial does not apply here.
BASE="${BASE:-http://localhost:5678/webhook}"
PHONE="${PHONE:-919876543210}"

echo "--- 1. new lead from a campaign (writes CRM + sends the 3-button WhatsApp welcome)"
curl -sS -X POST "$BASE/lead-intake" -H 'content-type: application/json' -d "{
  \"name\": \"Rohan Kelkar\",
  \"phone\": \"$PHONE\",
  \"email\": \"buyer@example.com\",
  \"project\": \"XYZ Skyline Residences\",
  \"source\": \"meta_ads\",
  \"campaign\": \"aug-skyline-3bhk\",
  \"budget\": \"1.2 Cr\",
  \"configuration\": \"3BHK\",
  \"timeline\": \"0-3m\",
  \"message\": \"Looking for a 3BHK with lake view\"
}"; echo; echo

echo "--- 2. buyer taps VIEW DETAILS (photos + specs)"
curl -sS -X POST "$BASE/simulate" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"action\":\"VIEW_DETAILS\"}"; echo

echo "--- 3. buyer taps DOWNLOAD BROCHURE (PDF document)"
curl -sS -X POST "$BASE/simulate" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"action\":\"DOWNLOAD_BROCHURE\"}"; echo

echo "--- 4. buyer taps SCHEDULE VISIT (reads calendar, offers 3 free slots)"
curl -sS -X POST "$BASE/simulate" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"action\":\"BOOK_VISIT\"}"; echo

echo "--- 5. buyer picks a slot (books calendar + notifies sales manager + updates CRM)"
echo "    replace the ISO time with one of the slots offered in step 4"
curl -sS -X POST "$BASE/simulate" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"action\":\"SLOT|2026-01-15T11:00:00.000+05:30\"}"; echo

echo "--- 6. free text (falls back to the main menu)"
curl -sS -X POST "$BASE/simulate" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"text\":\"kya price hai?\"}"; echo

echo "--- 7. free text that is NOT a keyword (goes to the AI agent, then re-grades the lead)"
curl -sS -X POST "$BASE/simulate" -H 'content-type: application/json' \
  -d "{\"phone\":\"$PHONE\",\"text\":\"is the clubhouse ready and how far is the metro?\"}"; echo
