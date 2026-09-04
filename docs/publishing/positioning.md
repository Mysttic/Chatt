# Positioning

A working document written before publication. It answers three questions: who
this is for, how it differs from what already exists, and what words people use
to look for it. The store copy ([google-play.md](google-play.md),
[microsoft-store.md](microsoft-store.md)) and the README come out of it.

## One sentence

**EN:** Chatt puts your PC and your phone in one conversation: messages and
files go straight from device to device, always encrypted, with no server,
no account and no cloud.

**PL:** Chatt łączy Twój komputer i telefon w jednej rozmowie: wiadomości
i pliki idą prosto między urządzeniami, zawsze zaszyfrowane, bez serwera,
konta i chmury.

## Who it is for

Ordered from the largest group to the most committed one:

1. **People who "send things to themselves".** A link from the phone to the PC
   through WhatsApp to yourself, a photo through Messenger, a file emailed to
   your own address. The pain: everything goes through somebody else's server,
   with size limits, photo compression and a need for the internet. Chatt: the
   same thing over the home Wi-Fi, with no middleman. This is the main group
   and the store descriptions are written for it.
2. **The privacy-minded** (r/privacy, F-Droid users, people who have read about
   Signal). The pain: for most apps "encrypted" means "to the server and back".
   Chatt: there is no server, so there is nothing to eavesdrop on in the
   middle; forward secrecy; history encrypted on disk. This group reads the
   source, so what counts for them is a public repository and a written threat
   model.
3. **Networks without internet, or with the internet cut off**: a workshop, a
   lab, a school, the outdoors, a ship, a company guest network. The pain:
   nothing "cloud" works. Chatt works, because all it needs is Wi-Fi.
4. **Poland**: a homegrown program with a Polish interface and documentation. A
   small group, but an easy one to reach (Wykop, Polish subreddits, Android
   groups on Facebook).

We are not aiming at: companies looking for a team messenger (that is
Slack/Teams), or people who want to talk over the internet (Chatt does not do
that and will not).

## How it differs

The competition a user will compare us with, at the time of writing (September
2026):

| | Chatt | LocalSend | KDE Connect | PairDrop / Snapdrop |
|---|---|---|---|---|
| Conversation with history | yes | no, transfers only | no (clipboard, notifications, phone SMS) | no |
| Traffic encryption | always, a key per session, forward secrecy | TLS with a self-signed certificate | TLS after pairing | TLS through the browser |
| History on disk | encrypted, key in Keystore / DPAPI | no history | no history | no history |
| Server | none | none | none | a signalling server |
| Receiving with the window closed | yes (an Android service, the Windows tray) | limited | yes | no |
| Confirming who you are talking to | QR code or a digit comparison | none | pairing | none |
| Resuming an interrupted file | yes | no | no | no |

Three things nobody in that table has all at once, and they go at the top of
every description:

1. **A conversation, not just a file drop.** History stays, it can be searched,
   and the phone and the PC see the same thing.
2. **Always encrypted, not "once paired".** The first message to an unknown
   device is encrypted exactly like the hundredth to a paired one.
3. **Nothing leaves the local network.** No server, no account, no telemetry.
   It can be verified in the source.

What we do **not** promise, so as not to collect bad reviews: talking over the
internet, groups, an iPhone version, history syncing between devices.

## Keywords

For store search and for post titles. Ordered by how people actually write, not
by what we call the features.

**EN:** send files from phone to PC, wifi file transfer, local network chat,
LAN messenger, offline messenger, encrypted chat no server, airdrop for
windows and android, localsend alternative, phone to computer messages,
no cloud.

**PL:** przesyłanie plików z telefonu na komputer, wysyłanie plików przez wifi,
komunikator w sieci lokalnej, czat bez internetu, szyfrowany czat, wiadomości
z telefonu na komputer, alternatywa dla localsend, zdjęcia z telefonu na pc bez
kabla, bez chmury.

## Where to talk about it

After going public, in this order:

1. **Show HN** (Hacker News) with a title along the lines of "Show HN: Chatt, a
   LAN messenger for PC and phone with no server and always-on E2E". That
   audience appreciates a threat model and forward secrecy, so link
   `docs/architecture.md` in a comment.
2. **r/selfhosted, r/privacy, r/androidapps, r/opensource**, each with a
   different opening sentence (self-hosted: "there is nothing to host";
   privacy: "there is no server"; androidapps: "photos to the PC without a
   cable or a cloud").
3. **Wykop** (tags #android, #programowanie) and Polish groups, in Polish, with
   the Polish interface as the hook.
4. **Comparison listings**: the LocalSend site has an alternatives list, and
   AlternativeTo accepts submissions.

One post shows one thing: a GIF of sending a photo from a phone and it
appearing on the PC a second later. Not a feature list.

## The name

"Chatt" is short, but in a store it will sit next to hundreds of apps with
"chat" in the name and the search will not tell them apart. The store title
gets a suffix ("Chatt: local network chat"), and before reserving the name in
either console it is worth checking whether "Chatt" is free, because both
platforms require a unique title.
