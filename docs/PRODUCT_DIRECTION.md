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

## Owner decisions

- Paid API setup and calls are paused until the owner agrees to a budget or
  authorizes them when customers are paying. Do not silently enable paid services.
- Research should stay inside the application. The current no-cost increment is
  a manufacturer reference directory and document reader, not whole-web search.
- Parts tools find and organize information; do not implement automatic buying.
- A question notebook must not be presented as a connected AI assistant.
