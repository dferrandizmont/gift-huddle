# Changelog

All notable changes to Gift Huddle are listed here. Store versions may skip numbers.

## Unreleased

## 1.0.2 · 2026-11-16

- The privacy policy now explains the recovery code file: it is optional, it goes only where you save or share it, Gift Huddle never receives it, and without a password it is as sensitive as the 24 words.
- iPad support: Gift Huddle is now a universal iPhone and iPad app for the App Store. It adapts to any window size, including portrait, landscape, Split View and Slide Over.
- Web version: on the "Check the code" screen the "They match" and "They do not match" buttons are now separated, and once you confirm the code the buttons give way to a clear "You confirmed the code here" message while it waits for the phone to approve (the waiting line no longer shows before you have compared). If the phone cancels the connection, the web now says so instead of showing the expired-code message.
- Web version: connecting a computer works again. After the phone approved, the page could freeze while opening the family key ("They match" stayed grey), and saving the computer's PIN could freeze too; both came from a compiler problem in the web build and are fixed, with a check that catches it in future builds. Pairing no longer gets stuck after "They match": the button answers at once, the page waits for the phone's approval on its own, and if the phone cancels or the request stops answering it says so and offers to start again.
- Pairing the web version and another phone is faster: both sides now check every one or two seconds while the pairing screen is open, without going over the server's limits.
- The QR scanner asks for the camera reliably and never stays as a black screen: if the permission dialog does not answer it checks again on its own, a second request waits for the first one's answer, and the camera preview starts right after the permission is granted. While it waits it says so, and if the camera is denied, blocked or does not answer, the scanner explains why with a "Try again" or "Open settings" button instead of a black box.
- The recovery code can also be saved as a file, next to the 24 words, while they are shown: save it with the system file picker or share it to your own drive or email, optionally protected with a password (at least 15 characters). "Recover with a file" on the welcome screen, or opening the file from Files on a new phone, brings the list back just like typing the words; a saved and re-read file, or "Check a file" in Settings, counts as a checked code. Changing or removing the code makes old files stop working, just like old words.
- Website (gifthuddle.app): the Downloads section now explains how to join the Google Play closed test in three steps (join the testers group, become a tester, install the app) and asks to keep the app installed for at least 14 days, in Spanish, Catalan and English.
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
