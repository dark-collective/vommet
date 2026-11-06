# Writing Vommet's UI text

Rules for English text in Vommet's own code (adopted 2026-10-14 after a
tester pointed out the inconsistencies). Upstream Commet's strings are left as
they are for now, to keep rebases onto Commet clean; they get one coordinated
pass later, together with the translators.

1. **Sentence case** for titles, setting names, buttons, menu items, tabs,
   dialog titles and tooltips: capitalize the first word and proper nouns only
   ("Copy user ID", "Leave room", "Push to talk"). Names stay capitalized:
   Vommet, Matrix, Element Call, Discord, Telegram, GIF, URL, ID, E2EE, key
   names such as Esc and Shift.
2. **Descriptions are sentences and end with a period**, including the last
   sentence and short ones such as "No restart needed." Titles, buttons,
   menu items, input hints and one-word statuses get no period.
3. **American punctuation with quotes:** commas and periods go inside the
   closing quotation mark: says "Today," "Yesterday," or the weekday.
4. **Oxford comma** in lists of three or more: messages, invites, or calls.

When a description names another control, copy that control's label exactly,
casing included. Every string goes through Intl.message (see the l10n
overlay); changing English text makes existing translations of it stale, so
batch wording changes and tell the translators.
