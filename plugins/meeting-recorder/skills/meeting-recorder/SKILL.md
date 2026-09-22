---
name: meeting-recorder
description: Process locally recorded meetings (made with the bundled `record` command, or any audio dropped in the recordings folder) — transcribe on-device with whisper.cpp, write a summary per meeting in the language it was spoken in, then propose either a CRM entry (Airtable, when the profile has one and the counterpart is a customer/account) or a Google Doc in the profile's Drive meetings folder, and only after the user's explicit yes write it; a second explicit step shares the doc read-only with the attendees. Triggers — "process my recordings", "procesa las grabaciones", "processa les gravacions", "transcribe today's meetings", "resume la reunión de hoy", "process the call with X"; the share step "share it", "compártelo", "comparteix-ho", "you can share the meeting doc"; the cleanup step "clean up old recordings", "limpia las grabaciones"; and when the user asks which recordings are pending or how to record a meeting.
---

# meeting-recorder — record → transcribe → summary → CRM or Drive doc → (later) share

Everything is local until the user says yes. Audio and transcripts never leave the machine. The only
things that go out are the summary (to Airtable or a Google Doc) and, on a second explicit step, the
doc share. **Two separate yeses, always: one before creating, one before sharing.**

## Setup and config (read this first)

- Commands: `record`, `transcribe`, `whisper-cli` on PATH (installed by `scripts/install.sh`).
  Not installed → tell the user to run `bash <skill>/scripts/install.sh` and stop.
- **Config** (private, outside the repo): `~/.config/meeting-recorder/config.json`
  (or `$MEETING_RECORDER_CONFIG`). Read it once per run with `scripts/mrconfig dump` — it holds:
  `recordings_dir`, `default_profile`, `speaker_labels`, and `profiles.<name>` with `identity`
  (who the user is in this context), `language`, `summary_language` (`recording` = same as spoken),
  `internal_notes_language`, `mail_account`, `drive` (`remote`, `meetings_folder`,
  `customers_folder`, or `null` = local-only), `doc_title` template, `share_message` per language,
  and `crm` (Airtable base/table ids + a `rules` paragraph, or `null`).
  Missing config → say so, point at `config.example.json`, and stop.
- **Profiles decide context.** Each recording carries a `profile` tag written by `record -p NAME`
  (shown by `pending.sh`); no tag = `default_profile`. The user can also override in the prompt
  ("this one is personal"). The profile fixes: who "I" am in the summary, where the doc goes, whether
  a CRM path exists at all, and the share message. Never mix profiles (a personal meeting never
  touches the work CRM or Drive).

Helpers in `scripts/` (run them, do not reimplement):
- `pending.sh [--all]` — TSV, newest first: file, date, time, title, duration, lang, profile, transcript, summary, state.
- `transcribe <file>` — writes `X.txt`; language from the file tag; `--lang XX|auto` overrides.
- `gdoc_create.py --title T --folder P --md X.md [--description D] [--remote R] [--create-folders]` → JSON `{id, link}`.
- `gdoc_share.py <doc_id> --to a@x.com ... [--lang ca|es|en] [--profile P] [--message M] [--remote R] [--dry-run]`, `--list`.
- `cleanup.sh [--older-than DAYS] [--also-transcripts] [--apply]` — dry run by default.
- `mrconfig path|get|profile|profiles|dump` — config access.

## Files and state (no database)

- `<recordings_dir>/X.ogg` (from `record`) or any audio file dropped there (phone memos, mp3, m4a…).
- `X.txt` transcript, `X.md` summary. **Unprocessed = no `X.md`.** Has `.txt` → summarise only.
- `X.md` starts with front-matter the skill maintains:
  ```
  ---
  kind: meeting | crm
  profile: <name>
  language: <code>
  calendar_event: <link or "title · time", or none>
  attendees: a@x.com, b@y.com
  drive_doc: <id or none>
  drive_link: <url or none>
  drive_folder: <path>
  crm_record: <id or none>
  shared: no | YYYY-MM-DD (a@x.com, b@y.com)
  ---
  ```
- Never touch the file being recorded: `pending.sh` skips it (`.recording` lock, mtime < 60 s, live ffmpeg).

## Flow: "process my recordings"

1. **List.** `pending.sh`. Show the table. Nothing pending → say so and stop. Default target = **the
   most recent pending recording** (the user usually asks right after hanging up); the others follow.
   If the user names a meeting ("the call with Ana yesterday"), process only that one.
2. **Transcribe** each file without `.txt`: `transcribe <file>`. Roughly 15–20 min per meeting hour
   on a GPU build, about real time on CPU: say so before a long one. Then read `X.txt`.
3. **Classify** (per recording, using its profile):
   - `crm` only if the profile has `crm` **and** the counterpart is an account there (search the
     accounts table by name from the title/transcript) or the content is clearly a sales/customer
     conversation for that business.
   - `meeting` otherwise (advisors, partners, investors, candidates, friends, anything personal).
   Show the guess; the user can flip it at confirmation.
4. **Find the calendar event.** Key = the recording's own timestamp (filename `YYYY-MM-DD_HHMM`):
   pick the event whose window contains it or is closest; title similarity only breaks ties. If the
   user names another meeting, search around that date/name instead.
   - Google Calendar tool available (ToolSearch "calendar") → use it.
   - Else Gmail (the profile's `mail_account`): `newer_than:3d (from:calendar-notification@google.com
     OR subject:(Invitation OR Invitación OR Invitació OR Accepted OR Aceptado OR Acceptat))`. When the
     **user is the organiser there is no "Invitation" mail**, only guests' "Accepted:" replies (subject
     carries title + time), so search both. `get_thread` in plain text gives the Meet link, organiser,
     guest list and the `calendar.google.com/calendar/event?...eid=…` link (store it without `tok=`).
   - No match → attendees "to be confirmed"; ask the user.
5. **Write `X.md` in the recording's language** (`summary_language: recording`; the tag says which).
   Never translate unless asked. Exception on request only ("internal notes", "in Spanish for us"):
   use `internal_notes_language`. Front-matter first, then, in that language: title · date and time ·
   duration (say if the recording ran on after the call) · attendees · context/goal · key points
   (5–10 lines) · decisions · next steps (owner, date if said) · open questions · for `crm` also
   who has the ball. Speaker labels come from the config (`speaker_labels.me` = the user). Do not
   invent attendees, names or dates; quotes stay as spoken.
6. **Overview + confirmation.** Per recording: profile, classification, three-line summary, and
   exactly what would be written (CRM record fields, or Drive folder + doc title + attendees +
   calendar reference). Ask "Shall I do it like this?" and **stop**. Nothing external before a yes.
   "No"/changes → adjust and re-ask. "Local only" → keep just `X.md`.
7. **On yes:**
   - `crm` → follow `crm.rules` from the config; always `get_table_schema` before writing; never
     guess select options; never write rollups. Save the record id in the front-matter. If the user
     also wants a doc for the account: `customers_folder` with `{customer}` filled, `--create-folders`.
   - `meeting` → title from `doc_title`: `{date}` = YYYY-MM-DD, `{names}` = first names of the people
     the user talked with (comma-separated; never the user), `{company}` = their organisation (email
     domain, calendar title or transcript; drop the part if unknown), `{goal}` = one or two words
     (Intro, Follow-up, Demo, Advice, Partnership…). Folder = the profile's `meetings_folder` unless
     the user names another. `drive: null` → local only, say so. `--description "Calendar: <event
     link or title+time> · Recording: <X.ogg>"`: the calendar reference lives only there and in
     `X.md`, never in the doc body. Save `drive_doc`, `drive_link`, `drive_folder`. **Do not share here.**
8. Report what was written with the links, and "review it; when you want, say 'share it'".

## Flow: "share it" (second step, always separate)

1. Find the doc: the `X.md` the user means (latest with `shared: no`, or the one named). Read
   `drive_doc`, `attendees`, `language`, `profile`.
2. `gdoc_share.py <id> --list` to show current access; show the attendee list minus the user's own
   addresses; let them trim or add. Ask "Share with these N people?" and **stop**.
3. On yes: `gdoc_share.py <id> --to <emails> --lang <language> --profile <profile>` (reader +
   notification email with the profile's message in that language; the user can dictate another
   with `--message`). Update `shared:` in `X.md`. Never re-share addresses that already have access
   (the helper skips them; say so).

## Flow: "clean up old recordings"

1. `cleanup.sh --older-than <days said, default 30>` (dry run); show the list and the MB freed.
   Transcripts only with `--also-transcripts` when the user says so.
2. Ask "Delete these N files (X MB)?" and **stop**. On yes rerun with `--apply`. Summaries (`X.md`)
   always stay: they index what was recorded and where each doc/CRM entry lives.

## Guard rails

- Ask before every external write; two separate yeses for create and share; a yes for one recording
  is not a yes for the next.
- Recordings, `.txt` and `.md` are never committed, uploaded or synced. No `git init` in the folder.
- Don't run `transcribe` next to other RAM-heavy jobs.
- Airtable tool missing → skip the CRM write, say how to attach it, keep `X.md`.
- Drive helper failing with 401/403 → the rclone token expired: `rclone lsd <remote>:` refreshes it;
  if rclone itself asks to re-authorise, tell the user. Drive limits: unencrypted `rclone.conf`, OAuth
  remotes only, folders under "My Drive" (no Shared Drives).
- Speaking about the user in the summary: use the profile's `identity` only to understand context;
  the summary itself names people as they were named in the meeting.
