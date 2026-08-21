# Real Estate Lead Automation — n8n (localhost)

One n8n workflow that takes a lead from **any ad, campaign, app or website form** all the way to a
**booked site visit**, entirely over WhatsApp, with Google Sheets as the CRM.

**Import this file:** [`workflows/RE-00_lead_to_whatsapp_buttons_to_site_visit.json`](workflows/RE-00_lead_to_whatsapp_buttons_to_site_visit.json)

---

## What it does

```
Ad / campaign / app / website form
        │  POST http://localhost:5678/webhook/lead-intake
        ▼
  Normalise → de-dupe → write to Google Sheets "Leads"
        ▼
  WhatsApp message: "Welcome to XYZ Properties…"  + 3 buttons
        ├── [ View Details ]        → project photos + price, config, carpet area,
        │                             possession, RERA, amenities  (from the Projects tab)
        ├── [ Download Brochure ]   → the project PDF as a WhatsApp document
        └── [ Schedule Visit ]      → reads Google Calendar, offers 3 free slots
                                       ↓ buyer taps a slot
                                    Google Calendar event created
                                    Sales manager added as attendee + emailed + WhatsApp'd
                                    "Visits" tab + "Leads" status = Visit Scheduled
                                    Buyer gets a confirmation with address & Maps link
```

Everything — inbound taps, outbound replies, bookings — is written back to Google Sheets.

---

## 1. Prerequisites

| Thing | Why |
|---|---|
| n8n running locally (`npx n8n` or Docker) on `http://localhost:5678` | the workflow host |
| Meta WhatsApp Cloud API app (phone number ID + permanent token) | sending & receiving |
| Google account | Sheets (CRM), Calendar (visits), Gmail (manager alerts) |
| A tunnel — `ngrok http 5678` or `cloudflared` | **Meta cannot call `localhost`**, it needs a public HTTPS URL for the inbound webhook |

Docker one-liner (set the tunnel host so webhook URLs are generated correctly):

```bash
docker run -it --rm -p 5678:5678 \
  -e WEBHOOK_URL="https://<your-ngrok-subdomain>.ngrok-free.app/" \
  -e GENERIC_TIMEZONE="Asia/Kolkata" \
  -v n8n_data:/home/node/.n8n n8nio/n8n
```

## 2. Build the CRM spreadsheet

Create one Google Sheet with **four tabs**, headers exactly as in [`google-sheets/`](google-sheets/):

| Tab | Purpose |
|---|---|
| `Leads` | one row per buyer — the CRM |
| `Projects` | price, specs, photo URLs, brochure URL per project — **the workflow reads all content from here, nothing is hard-coded** |
| `Visits` | every booked site visit |
| `Messages` | full inbound/outbound WhatsApp log |

Import each CSV as its own tab (File → Import → Insert new sheet), then fill the `Projects` rows with
your real data. `image_1..3` and `brochure_url` must be **public direct links** that Meta's servers can
fetch — a Google Drive "share" link will not work, use a direct file URL or a CDN/S3 link.

## 3. Credentials to create in n8n

| Credential | Used by |
|---|---|
| **WhatsApp API** (`Access Token` + `Business Account ID`) | all 10 `WA - …` HTTP Request nodes (they use *Predefined Credential Type → WhatsApp API*, so **no token is stored in this JSON**) |
| **WhatsApp OAuth / Trigger** (App ID + App Secret) | the `WhatsApp Message Received` trigger |
| **Google Sheets OAuth2** | all CRM nodes |
| **Google Calendar OAuth2** | availability + booking |
| **Gmail OAuth2** | sales-manager emails (optional — those nodes continue on error) |

## 4. Fill in the `Config` node

Open the workflow and edit the single **`Config`** node — it is the only place with settings:

| Field | Example |
|---|---|
| `COMPANY_NAME` | `XYZ Properties` |
| `SHEET_ID` | the id in your sheet's URL |
| `CALENDAR_ID` | `primary` or the site-visit calendar id |
| `WA_PHONE_NUMBER_ID` | from Meta → WhatsApp → API Setup |
| `USE_APPROVED_TEMPLATE` | `true` in production, `false` for testing (see below) |
| `WELCOME_TEMPLATE_NAME` | `lead_welcome_menu` |
| `SALES_MANAGER_EMAIL` / `SALES_MANAGER_WHATSAPP` | who gets the visit |
| `BOOKING_START_HOUR` / `BOOKING_END_HOUR` / `VISIT_DURATION_MIN` | site-office hours, `10` / `18` / `45` |

## 5. Point Meta at the inbound webhook

1. Start the tunnel: `ngrok http 5678`
2. Activate the workflow, open `WhatsApp Message Received`, copy its **Production URL**, and swap
   `localhost:5678` for your ngrok host.
3. Meta app → WhatsApp → Configuration → **Callback URL** = that URL, verify token = the one in your
   n8n WhatsApp Trigger credential, then **subscribe to the `messages` field**.

## 6. The one Meta rule you cannot code around

A buyer who just filled a form has **not** messaged you, so the 24-hour customer-service window is
closed and Meta only allows a **pre-approved template** as the first message. That is why the welcome
step has two branches, chosen by `USE_APPROVED_TEMPLATE`.

Submit this template in Meta Business Manager → WhatsApp Manager → Message Templates:

* **Name:** `lead_welcome_menu`  **Category:** Marketing (or Utility)  **Language:** `en`
* **Body:**
  `Hi {{1}}, welcome to {{2}}! Thanks for your interest in {{3}}. I can share the full details and photos, send you the brochure, or book a site visit at a time that suits you.`
* **Buttons → Quick Reply ×3, in this exact order:** `View Details`, `Download Brochure`, `Schedule Visit`

The workflow sends the three payloads `VIEW_DETAILS`, `DOWNLOAD_BROCHURE`, `BOOK_VISIT` against button
indexes 0/1/2, so keep the order. Every message *after* the buyer taps a button is inside the 24-hour
window, so all the rich replies (photos, PDF, slot buttons, confirmation) are free-form and need no template.

Set `USE_APPROVED_TEMPLATE` to `false` only while testing with a number that has messaged your business
number in the last 24 hours — then the welcome goes out as a free-form interactive message with the same
three buttons and no approval needed.

## 7. Test it on localhost

```bash
# a website/app submitting a lead
open test/lead-form.html            # or: bash test/curl-examples.sh
```

`test/curl-examples.sh` also drives the **button flow without Meta** through the
`POST /webhook/simulate` entry point:

```bash
curl -X POST http://localhost:5678/webhook/simulate -H 'content-type: application/json' \
  -d '{"phone":"919876543210","action":"VIEW_DETAILS"}'
```

Valid actions: `VIEW_DETAILS`, `DOWNLOAD_BROCHURE`, `BOOK_VISIT`, `SLOT|<ISO datetime>`, or `{"text":"…"}`.
The WhatsApp sends still go out for real, so use your own number.

> While the canvas is open in **Test** mode the paths are `/webhook-test/lead-intake` and
> `/webhook-test/simulate`. Once the workflow is **Active** they are `/webhook/…`.

---

## Node map

| Stage | Nodes |
|---|---|
| Entry | `Lead Intake Webhook`, `WhatsApp Message Received`, `Simulate Button Click (Local Test)` → `Config` → `Inbound WhatsApp Message?` |
| Capture | `Normalise Lead` → `Find Existing Lead` → `Flag Duplicate` → `Save Lead to CRM` |
| Welcome | `Use Approved Template?` → `WA - Welcome Template + 3 Buttons` / `WA - Welcome Interactive Buttons` → `Log Welcome Sent` → `Email New Lead to Sales Manager` → `Respond to Source` |
| Button router | `Parse Inbound Message` → `Find Lead in CRM` → `Resolve Lead` → `Find Project in CRM` → `Build Context` → `Log Inbound Message` → `Update Lead Activity` → `Route Button Action` |
| View Details | `Prepare Project Photos` → `Has Photos?` → `WA - Send Project Photo` → `WA - Send Details + Buttons` |
| Brochure | `Brochure On File?` → `WA - Send Brochure PDF` → `WA - Nudge to Book After Brochure` |
| Schedule Visit | `Read Calendar Availability` → `Build Available Slots` → `WA - Send Slot Options` |
| Slot chosen | `Create Site Visit Event` → `Append Visit to CRM` → `Mark Lead as Visit Scheduled` → `WA - Visit Confirmation to Buyer` → `WA - Notify Sales Manager` → `Email Visit to Sales Manager` |
| Fallback | `WA - Send Main Menu` → `Log Outbound Reply` |

### Behaviour worth knowing

* **De-dupe** — a repeat enquiry from the same phone keeps its original `lead_id` and `created_at`,
  bumps `touch_count`, and is marked `Re-enquiry` instead of creating a second row.
* **Slots** — the next three genuinely free 45-minute slots inside office hours over the coming 8 days,
  skipping anything already on the calendar and anything less than 3 hours away.
* **A WhatsApp-first contact** (someone who messages you without ever filling a form) gets a `Leads` row
  created automatically with `source = whatsapp`.
* **Free text** falls back to the 3-button menu, with keyword shortcuts (`brochure`, `visit`, `price`).
  To answer questions conversationally instead, hang your existing `RE-02` AI agent off the
  `Anything Else` output of `Route Button Action`.
* Every WhatsApp send is `continue on error`, so a Meta hiccup never loses the CRM write.

### Where the other workflows fit

This file is the front end. The workflows you already have slot in behind it, all on the same sheet:

* **RE-01** — AI lead scoring (HOT/WARM/COLD) on capture
* **RE-02** — conversational AI agent for free text
* **RE-03** — T-24h / T-2h visit reminders and post-visit feedback (reads the same calendar & `Visits` tab)
* **RE-04** — follow-up cadence engine and the manager's daily pipeline digest
