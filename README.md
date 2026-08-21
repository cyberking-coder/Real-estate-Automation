# Real Estate Lead Automation — n8n (localhost)

One n8n workflow that takes a lead from **any ad, campaign, app or website form** all the way to a
**booked site visit**, entirely over WhatsApp, with Google Sheets as the CRM.

**Import these two files:**

| File | What it is |
|---|---|
| [`workflows/RE-00_lead_to_whatsapp_buttons_to_site_visit.json`](workflows/RE-00_lead_to_whatsapp_buttons_to_site_visit.json) | capture → WhatsApp menu → details / brochure / site visit, plus the AI agent for free text and AI lead grading |
| [`workflows/RE-05_followup_engine.json`](workflows/RE-05_followup_engine.json) | the daily follow-up sweep for leads who never replied |

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
        ├── [ Schedule Visit ]      → reads Google Calendar, offers 3 free slots
        │                              ↓ buyer taps a slot
        │                           Google Calendar event created
        │                           Sales manager added as attendee + emailed + WhatsApp'd
        │                           "Visits" tab + "Leads" status = Visit Scheduled
        │                           Buyer gets a confirmation with address & Maps link
        └── anything else typed    → AI agent answers, then re-grades the lead
                                     HOT / WARM / COLD / JUNK (timepass)

  never replied at all? → RE-05 follows up on a cadence set by that grade
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
| **Anthropic** (API key) | lead grading, the free-text agent, follow-up copy. Used via *Predefined Credential Type → Anthropic*, so **no key is stored in these JSONs** |

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
| `CLAUDE_MODEL` | `claude-opus-5` (swap for `claude-sonnet-5` if you want to trade some judgement for cost) |
| `CONVERSATION_HOLD_HOURS` | `72` — how long a live conversation blocks automated follow-ups |

RE-05 has its own `Config` node with the same shape plus the cadence numbers.

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

RE-05 needs a second approved template, `followup_update`:

* **Name:** `followup_update`  **Category:** Marketing  **Language:** `en`
* **Body:** `Hi {{1}}, an update on {{2}}: {{3}}`
* **Buttons → Quick Reply ×3, same order:** `View Details`, `Download Brochure`, `Schedule Visit`

Claude writes `{{3}}` only. The template itself never changes, stays approved, and its buttons carry
the same payloads as RE-00 — so a tap on a follow-up drops the buyer straight back into the button flow.

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

## The AI layer

**Grading at capture.** `Claude - Qualify Lead` runs before the CRM write and returns
`grade` (HOT / WARM / COLD / JUNK), `score` 0-100, `is_broker`, `is_timepass`, intent signals, risk
flags and a one-line `next_action`. JUNK is the "timepass" bucket: no real intent, prank entries,
gibberish, job seekers, vendor pitches, competitors fishing for price, brokers hunting inventory.
The manager's new-lead email is subject-lined `[HOT 82/100] …` so the phone gets picked up in the
right order.

**Free text goes to an agent.** Anything that is not a button tap routes to `Sales AI Agent`
(Claude + conversation memory keyed on the buyer's number). It answers only from the `Projects` tab,
qualifies with at most one question per message, replies in Hinglish if the buyer does, and keeps to
about 60 words. It escalates price negotiation, complaints, legal and possession-delay questions to
the sales manager by email.

Its booking tool is deliberately **read-only**: it can say "Saturday morning is open" but cannot
create an event. Every real booking goes through the Schedule Visit button, so the calendar, the
`Visits` tab and the manager alert can never drift apart. If the agent errors, the buyer still gets
the 3-button menu — the conversation never dead-ends.

**Re-grading after every exchange.** `Claude - Re-grade Lead` runs *after* the reply is sent, so it
adds no latency. Behaviour outranks the form: someone asking about carpet area, loan eligibility or
possession is warming up; someone who only asks price and vanishes, or pitches a service, becomes
JUNK. A failed grading call never overwrites an existing grade.

Both calls use `output_config.format` (structured outputs), so the JSON is guaranteed valid — no
markdown stripping, no brittle parsing. Both fall back safely: a failed grading call saves the lead
as WARM with an `ai_grading_unavailable` flag rather than losing it.

---

## RE-05 — the follow-up engine

A single sweep at **10:00 IST**. For each lead it computes the days between `last_touch` and now and
compares that against the interval for its grade.

| Grade | Cadence | 6 follow-ups spans |
|---|---|---|
| HOT | every 3 days | ~3 weeks |
| WARM | every 5 days | ~1 month |
| COLD | every 21 days | ~4 months |
| JUNK | never | — |

**6 touches, not 6 days** — the gap depends on the grade, and the cap is a safety stop rather than a
target. Most leads book, reply, or get marked Lost long before touch 6. A HOT lead who has ignored
six messages over three weeks is not hot any more; a human should take over or the grade should drop.

**Who gets skipped**

* `Booked`, `Lost`, `Dropped` — never touched again.
* `Engaged` **while the conversation is still live** — RE-00 sets `Engaged` the moment a buyer
  replies, so without this a scheduled nudge would land on top of a live chat. Once they have gone
  quiet for `CONVERSATION_HOLD_HOURS` (default 72) the conversation is over and nurture resumes.
  A permanent `Engaged` skip would be worse: everyone who ever replied would fall out of nurture
  forever, which is the opposite of what you want.
* Anyone at the 6-follow-up cap, anyone not yet due, JUNK, and anyone with no WhatsApp number.

**`followup_count`, not `touch_count`.** The cap counts *automated follow-ups only*. `touch_count`
also increments on every button tap, so capping on it would lock an engaged buyer out of nurture
after six taps. Replying resets `followup_count` to 0 — someone who re-engages earns a fresh
sequence.

**Why Claude is in the loop.** A fixed template would be simpler, but follow-up 5 saying the same
thing as follow-up 2 is why nurture sequences get muted. The prompt forces each message to carry one
genuinely new reason to reply — a unit released, a possession update, a loan offer, a weekend open
house — and escalates *value*, not pressure, as the number climbs. "Just following up" and "gentle
reminder" are banned outright. The variable is then sanitised in code: WhatsApp rejects template
parameters containing newlines, tabs or 4+ consecutive spaces, so those are stripped and the line is
capped at 240 characters. If the model returns nothing usable, a safe generic line is sent instead of
an empty variable.

**Why the write-back matters.** `Update Touch Count` sets `last_touch` to now, so tomorrow's sweep
sees the lead as freshly touched and skips it until the interval passes. Without it the same lead
would be messaged **every single day** — which is why that node failing silently is worse than the
workflow not running at all. So it does not fail silently: it retries 3 times, and if it still fails
its error output emails the sales manager with the exact row to fix by hand. A touch is also only
recorded if Meta actually accepted the message, so a rejected send never burns one of the six.

**The tradeoff.** Because it is a daily sweep rather than a job scheduled per lead, a lead due at 2pm
is not messaged until 10am the next day. That is deliberate: all outbound lands in one predictable
window instead of pinging buyers at random hours, and one cron failure delays messages by a day
rather than losing them permanently.

**Tuning.** Open RE-05's `Config` node — `CADENCE_HOT_DAYS`, `CADENCE_WARM_DAYS`, `CADENCE_COLD_DAYS`,
`MAX_FOLLOWUPS`, `CONVERSATION_HOLD_HOURS`, `DAILY_SEND_CAP`. These are a starting point, not a law;
review them after a month of real data. Worth saying out loud to the client — it signals you have
thought about their brand, not just the automation.

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
| Free text | `Sales AI Agent` (+ Claude model, memory, `project_knowledge`, `check_availability`, `escalate_to_human`) → `WA - Send AI Reply` → `Claude - Re-grade Lead` → `Parse New Grade` → `Grade Changed?` → `Update Grade in CRM` |
| Agent failure | `WA - Send Main Menu` → `Log Outbound Reply` |
| RE-05 | `Daily 10am IST` → `Config` → `Read Full Pipeline` → `Find Follow-Ups Due` → `Claude - Write Follow-Up` → `Sanitise Template Variable` → `WA - Send Follow-Up Template` → `Actually Delivered?` → `Update Touch Count` → `Log Follow-Up` → `Email Sweep Summary` (error output → `Alert - CRM Write-Back Failed`) |

### Behaviour worth knowing

* **De-dupe** — a repeat enquiry from the same phone keeps its original `lead_id` and `created_at`,
  bumps `touch_count`, and is marked `Re-enquiry` instead of creating a second row.
* **Slots** — the next three genuinely free 45-minute slots inside office hours over the coming 8 days,
  skipping anything already on the calendar and anything less than 3 hours away.
* **A WhatsApp-first contact** (someone who messages you without ever filling a form) gets a `Leads` row
  created automatically with `source = whatsapp`.
* **Free text** first hits keyword shortcuts (`brochure`, `visit`, `price`) so booking intent never
  reaches the model unnecessarily; everything else goes to the AI agent.
* Every WhatsApp send is `continue on error`, so a Meta hiccup never loses the CRM write.

### Where the other workflows fit

This file is the front end. The workflows you already have slot in behind it, all on the same sheet:

* **RE-01** — AI lead scoring (HOT/WARM/COLD) on capture
* **RE-02** — your standalone conversational agent. RE-00 now has one built in, so run RE-02 only if
  you still need the web-chat endpoint.
* **RE-03** — T-24h / T-2h visit reminders and post-visit feedback (reads the same calendar & `Visits` tab)
* **RE-04** — superseded by **RE-05** for follow-ups (RE-04 is email-first, 2-day HOT cadence, 12-touch
  cap, and does not skip live conversations). Keep RE-04 only for its manager's daily pipeline digest,
  and if you run both, apply the same skip list and cadence there or leads get messaged twice.
