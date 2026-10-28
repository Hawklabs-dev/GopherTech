# GopherTech V1 product direction

GopherTech is an existing HawkLabs application. Develop it incrementally and
preserve its Python backend, SQLite data, and Godot frontend.

The application is intended for intelligent, practical people doing hands-on
mechanical work. Use clear language, large readable buttons, and straightforward
frames that help users find the next useful action.

Quick standalone tasks should be easy to reach: search for parts, find how-to
help, or get help with a mechanical check. These tasks must not require users to
register equipment, create a profile, or save a record first.

Equipment profiles, repair history, diagnostics, fabrication support, and
AI-assisted workflows can provide more depth when a user chooses to use them.
Introduce that depth progressively rather than putting it in the first screen.

This document records future design requirements. It does not imply that these
features are already implemented. Coordinate website messaging with the actual
application capabilities as both evolve.

## Afternoon owner direction — October 28, 2026

Make Go For Gopher faster to grab and use. Voice input and Clear results are
implemented; the wider interface redesign is deferred. The owner authorized
Firecrawl search/page reading starting with free access, followed by local AI
passage selection. Browser authorization and live retrieval succeeded, and the
owner confirmed microphone capture and useful source discovery. Hosted AI
answering, paid-plan purchases and automatic spending are not authorized.

The next improvement is selecting task-relevant information instead of a forum
introduction. Finding a related page does not establish a correct diagnosis or
repair procedure. See `HANDOFF-2026-10-28-PM.md` for tomorrow's scope and evidence.

## Owner-approved tablet direction — October 28, 2026 morning

Work order numbers organize a standalone tablet helper with Wi-Fi and connected
AI as the target. Open directly to Go For Gopher quick search. Keep the active
order number and machine summary beside the logo. Work Area combines order selection, machine details, parts research,
troubleshooting, repair, fabrication, notes and photos in one scrollable screen.
Four top-level buttons open Go For Gopher, Work Area, Parts and Tools. Research
sections share the layout and machine identity, while each section auto-saves
its own task and notes; unused sections load blank fields. No job status workflow. Keep the four direct Gopher buttons and the
existing Tools capabilities; remove finance from tablet navigation. Parent-PC
administration, inventory, POS and ordering are later work. The owner approved
implementation of the work order foundation, navigation and photo attachment
increment, superseding the earlier interface-only hold below. No paid AI budget
has been approved or activated. See `TABLET-TRIAL-2026-10-28.md` for actual
implementation and test boundaries.

## Earlier owner decisions

These are historical decisions. The October 28 work-order and Firecrawl/voice
approvals supersede the earlier interface-only hold and directory-only research
scope; paid activation still requires a separate owner decision.

- The Shop Buddy mission is the current direction: ASK → FIND → ANALYZE →
  ANSWER → REMEMBER. Milestone 1 is interface-only; stop for owner testing and
  explicit approval before advancing. See `SHOP_BUDDY_MILESTONES.md`.

- Paid API setup and calls are paused until the owner agrees to a budget or
  authorizes them when customers are paying. Do not silently enable paid services.
- Research should stay inside the application. The current no-cost increment is
  a manufacturer reference directory and document reader, not whole-web search.
- Parts tools find and organize information; do not implement automatic buying.
- A question notebook must not be presented as a connected AI assistant.
- The prototype has three main choices: Ask GopherTech, Saved Jobs, Tools. Start
  with one question field and one Ask button; keep category selection in Tools.
- Persist conversations, job context, notes, source references and parts in the
  existing SQLite approach. Never present unsaved changes as saved.
- Reference-mode routing and checklists are labelled as rules, not AI answers.
- Proposed reference locations are not verified documents or compatibility
  matches. Missing and unsupported documents must be reported explicitly.
