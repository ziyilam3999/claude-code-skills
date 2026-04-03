# Known AI Detection Patterns

Patterns graduated from real pipeline runs. Each pattern has been observed and validated.

## Word Choice Patterns

### P1: Em-dash overuse
**What:** AI uses em-dashes (—) at 5-15x the rate of human writers.
**Threshold:** More than 2 em-dashes per document is suspicious. More than 5 is a strong signal.
**Why:** LLMs treat em-dashes as a universal connector. Humans use periods, commas, colons, and sentence restructuring.
**Evidence:** Run 1 (GitHub README) — 15 em-dashes in a 77-line document. All removed or replaced.

### P2: Buzzword chains
**What:** 3+ jargon/technical words packed into a single clause without plain-language grounding.
**Example:** "PRD-driven AI orchestrator that transforms product requirements into working code through multi-stage agent pipelines with human-in-the-loop checkpoints."
**Why:** LLMs optimize for information density. Humans explain things more plainly, especially about their own work.
**Evidence:** Run 1 — Hive Mind description had 5 buzzwords in one sentence. Rewritten to conversational explanation.

### P3: Filler phrases
**What:** Stock phrases like "passionate about", "driven by", "dedicated to", "at the intersection of", "leveraging", "cutting-edge".
**Why:** These appear in LLM training data frequently. Humans tend to be more specific or skip the self-description entirely.
**Note:** This pattern had 0 detections in Run 1 (the document avoided these). Keep checking — common in other document types.

## Sentence Structure Patterns

### P4: Bold-dash template repetition
**What:** Every bullet follows the same `**Bold keyword** — explanation` structure.
**Threshold:** If 3+ consecutive bullets follow the same template, it's AI-patterned.
**Why:** LLMs default to uniform formatting. Humans naturally vary how they structure lists.
**Evidence:** Run 1 — All 5 Professional Highlights bullets and all 4 project descriptions used identical template.

### P5: Perfect parallel structure
**What:** Every bullet in a list starts with the same grammatical form (all past-tense verbs, all nouns, all gerunds).
**Threshold:** 4+ consecutive items with identical grammatical start.
**Why:** LLMs enforce parallelism as a "good writing" rule. Real lists have organic variation.
**Evidence:** Run 1 — Professional Highlights all started with past-tense action phrases.

### P6: Connector monotony
**What:** Same punctuation mark (usually em-dash) used as the connector between clause pairs throughout the document.
**Why:** Humans naturally alternate between commas, periods, colons, semicolons, and sentence restructuring.
**Evidence:** Run 1 — em-dash used as connector in 15 locations. Zero variety.

## Formatting Patterns

### P7: Systematic emoji placement
**What:** One emoji placed before every item in a list, at the same position.
**Threshold:** 3+ consecutive list items each prefixed with exactly one emoji.
**Why:** Humans use emojis sporadically or not at all. The one-per-item pattern is an LLM default for "friendly" formatting.
**Evidence:** Run 1 — All 4 project descriptions had emoji prefix (brain, magnifier, pencil, camera).

### P8: Section length symmetry
**What:** All sections are suspiciously similar in length (±20% of each other).
**Note:** This pattern PASSED in Run 1 (sections varied enough). Some well-organized humans write balanced sections too. Use cautiously — high false-positive risk.

## Tone Patterns

### P9: Press release tone
**What:** Achievements described in third-person corporate voice. Reads like a company announcement, not a person talking.
**Example:** "Accelerating digital initiatives during COVID-19" vs "This was during COVID-19, so everything moved faster than usual."
**Why:** LLMs default to formal, impressive-sounding language. Humans writing about themselves use first-person and casual phrasing.
**Evidence:** Run 1 — Professional Highlights read like a press release. Rewritten with first-person, conversational framing.

### P10: Missing personality
**What:** No humor, asides, self-deprecation, or rough edges anywhere. Everything is perfectly polished.
**Why:** LLMs produce "safe", neutral text. Real people have opinions, make jokes, admit things aren't perfect.
**Evidence:** Run 1 — Zero personality in original. Added: "Not the fun kind of project, but someone has to do it", "Still evolving", "I got tired of writing these by hand."

### P11: Absent casual first-person voice
**What:** No instances of "I built this because...", "I got tired of...", "this is still rough". Everything described in detached product-description style.
**Why:** LLMs default to third-person or impersonal descriptions even for personal projects.
**Evidence:** Run 1 — Zero first-person casual voice. All project descriptions were impersonal product blurbs.

## Specificity Patterns

### P12: Vague quantifiers
**What:** "Various", "multiple", "numerous", "several" used instead of specific numbers.
**Why:** LLMs hedge with vague words. Humans either know the number or don't mention it.
**Evidence:** Run 1 — "multiple organisations" replaced with "three organisations."
