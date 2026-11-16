# Changelog

All notable changes to Gift Huddle are listed here. Store versions may skip numbers.

## Unreleased

- Website (gifthuddle.app): the footer links to the public source code on GitHub (github.com/dferrandizmont/gift-huddle, GPL-3.0).
- Settings shows the real number of phones in the family (it always said 2), and a phone removed from the family counts only itself.
- After confirming "Remove phone", its sheet closes at once instead of staying open while the access is cut; the result still shows as a message, and if it fails the phone stays in the list to try again.
- The old trial addresses no longer open the app or sync; all services now use gifthuddle.app and its subdomains.
- Website (gifthuddle.app): a discreet link in the header and footer opens the web version (web.gifthuddle.app), and the sync feature now says you can view and edit the list in your computer's browser after pairing it once with your phone.
- Website (gifthuddle.app): the grey panel behind the animated phone on the home page is gone, and the screenshots follow the site theme: light screenshots in light mode and dark ones in dark mode (new dark screenshots of the same five screens in Spanish, Catalan and English).
- Website (gifthuddle.app): the whole site now uses the app's current colours, including the neutral dark theme (grey backgrounds without tint, vivid accents) and darker control borders in light mode, and the animated phone on the home page and its two floating cards match the app screenshots, with the occasion colours on the filter chips.

## 1.0.1 · 2026-11-16

- With very large text, Who gives what no longer cuts or splits words: the screen title, dates, countdowns, totals, person cards, gift rows, the gift sheets and the "Not in the split" block wrap onto more lines or shrink slightly, and long giver names fit in their chip.
- After unlocking, the list can no longer stay dimmed behind a light grey veil if the fade-in animation stalls: it always finishes within a second.
- Website (gifthuddle.app): a button next to the language selector switches between light and dark mode and remembers the choice (it still follows the system until you use it), and the animated phone on the home page now has a phone frame.
- With very large text (200 %), the giver names above the columns of Who gives what turn sideways and take up to two lines, so "Grandparents" or "Avis de Girona" read in full instead of "Gra..."; and the four labels of the bottom tab bar all use the same size instead of some looking bigger than others.
- Keep the phone name confirmed on the welcome screen when joining by invitation link or QR. A phone with confirmed removal from the family now shows the existing reconnect notice, stops retrying sync and lists only itself, including after restarting. Ordinary authentication failures remain retryable, and older unconfirmed removal flags are checked again with the server.

## 1.0.0 · 2026-11-16

First version in the stores.

- A list of gifts for each person in the family: what they want, who gives it, for which occasion, the price and where to buy it.
- Who gives what: a grid with every person and every giver, so nobody repeats a gift and nobody is left without one. Possible duplicates are flagged.
- Occasions with a countdown: Tió, Christmas, Three Kings, birthdays and any you add, with what is still pending for each one and a budget.
- Each gift moves from idea to decided, bought, arrived, wrapped and given, with filters for what is left to buy or to wrap.
- Secret gifts: surprises for someone in the family stay hidden on that person's phone.
- Share the list with the family's other phones and with the web version (web.gifthuddle.app). The first phone is connected in person with a QR code, and everything travels end-to-end encrypted: the server cannot read it.
- A 24-word recovery code brings your list back on a new phone if you lose yours.
- No accounts, no ads and no analytics. PIN, fingerprint or face to open the app, and no preview in the recent apps screen.
- Light and dark themes, phones and tablets, in Spanish, Catalan and English.

Earlier development builds were private and are not listed here.
