# Evaluation Criteria Template

Use this format for every eval criterion:

```
### E{N} — {Descriptive Name}
**Category:** {Word Choice | Sentence Structure | Formatting | Tone | Specificity}
**Severity:** {HIGH | MEDIUM | LOW}
**Question:** {A yes/no question that can be objectively checked against the document}
**Human would:** {Describe what human-written text typically looks like for this criterion}
**AI tends to:** {Describe the AI pattern this criterion detects}
**Threshold:** {Specific, measurable — e.g., "more than 2 instances", "3+ consecutive items"}
```

## Severity Guide

- **HIGH:** Strong AI signal that most readers would notice. Fixing this makes the biggest difference. Examples: em-dash overuse, uniform template repetition, press release tone.
- **MEDIUM:** Moderate signal that attentive readers might catch. Examples: parallel structure, systematic emoji placement, section symmetry.
- **LOW:** Subtle signal, or one with high false-positive risk (some humans do this too). Examples: vague quantifiers, missing rough edges.

## Writing Good Criteria

1. **Be specific.** "Does it sound AI-generated?" is not a criterion. "Does every bullet start with a bold keyword followed by an em-dash?" is.
2. **Set thresholds.** Don't just say "uses em-dashes" — say "uses more than 2 em-dashes."
3. **Acknowledge human variance.** Some humans write balanced sections. Some use em-dashes. The threshold should catch AI patterns without over-flagging human text.
4. **Test both ways.** A good criterion should PASS when applied to genuinely human-written text of the same type.
