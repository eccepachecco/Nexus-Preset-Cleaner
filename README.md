# Nexus Preset Cleaner

A tiny Windows tool for **reFX Nexus 2**. If your preset browser is full of
downloaded presets that won't play and just throw:

> *"the expansion product is unknown. The output has been muted."*

…it moves those dead presets out of your way and keeps only the ones that
actually play on **your** machine.

---

## Safety first (read this)

- **It never deletes anything.** Broken presets are *moved* into an `_INVALID`
  folder. Nothing is erased — you delete `_INVALID` yourself once you're happy.
- **100% offline.** It makes zero internet connections and sends your data
  nowhere. It only reads and moves local files.
- **Open source.** It's a single `.bat` you can read top to bottom before
  running it. No compiled black box.
- **One admin prompt (UAC).** Needed only because Nexus lives in
  `C:\Program Files`, and Windows requires admin rights to write there.

---

## Requirements

- Windows 10 / 11
- **reFX Nexus 2**

---

## How to use it

1. **Download** `Nexus-Preset-Cleaner.bat` from this repo.
2. **Drag your downloaded pack folder onto the `.bat`** — a single preset folder,
   or a folder containing many sub-folders, but **unzipped** (no `.zip` / `.rar`).
3. Windows **SmartScreen** will warn you (normal for any downloaded script) →
   click **More info → Run anyway**.
4. Approve the single **UAC** (admin) prompt.
5. Answer two quick questions:
   - **Nexus path** — Where is your Nexus folder located? (usually `C:\Program Files\Nexus`).
   - **Prefix** — type `zz` (recommended) so the new folders group neatly at the
     bottom of your Nexus browser, or press ENTER for none.
6. When it asks, **restart FL Studio**, open the `_CALIBRATION (temp)` folder in
   Nexus (at the bottom of your preset browser), and **play the listed presets**.
   Type the **numbers** of the ones that do **not** sound (show the error / are muted),
   separated by spaces. Press ENTER if they all play.
7. Done. Broken presets are in `Nexus\Presets\_INVALID`; everything that plays
   stays. Delete `_INVALID` whenever you're satisfied.

It remembers which expansions you have in `Documents\Nexus Cleaner\whitelist.txt`,
so the next pack you clean won't make you re-test those again.

---

## How it decides what's broken

- Every preset references a sample library by an internal ID. The tool reads that
  ID straight from the preset bytes.
- The **factory ROM** libraries ship with every Nexus install, so they're always
  treated as installed.
- For **expansions**, it can't know which you own — so it picks one representative
  preset per unknown library, you test it, and it remembers the answer.
- Why do you need to manually test only 10 or 20 presets if there are like thousands?
  Because all of them use the same 10 or 20 libraries. So if a preset doesn't work, the 
  program knows that the other 100 presets that use the same library won't work. When a
  library is confirmed missing, **every** preset using it is moved at once.
- For presets in a **format it can't read** (some packs are encrypted), it falls
  back to a **folder-level test**: it samples a few presets from that folder and,
  only if **all** of them are muted, treats the whole folder as a missing
  expansion. Mixed results → it leaves the folder alone and tells you.

### Honesty about accuracy

- For the readable format it has **zero false positives**: a preset is moved only
  if it references a library you confirmed you don't have. It will never move a
  working preset.
- For the unreadable format the guarantee is **per-folder**, not per-preset (it
  relies on a downloaded pack folder being a single expansion, which is almost
  always true). It samples 6 presets per folder to catch exceptions.
- Built and tested for Nexus 2 packs. Anything in a format it doesn't recognize
  is simply **left untouched** — never broken, never moved blindly.

---

## FAQ

**Will this damage my Nexus install?** No. It only adds folders to
`Nexus\Presets` and moves preset files between them. It never touches your
`Samples` (the actual sounds) or any Nexus settings.

**Can I undo it?** Yes — the "broken" presets are all in `_INVALID` with a
`_source-folders.txt` listing where each came from, so you can move any back.

**Why does it need admin?** Only to write inside `C:\Program Files\Nexus`.
That's the single UAC prompt.

**Does it pirate / download expansions?** No. It doesn't obtain, crack, or
unlock any content. It only organizes preset files you already have.

---

## Donations

I've spent a whole week refining this code in order to be effective, secure but also
as easy as possible for everyone to use. If this helped you somehow, you can support
me with a symbolic donation on Ko-fi. I will be very happy knowing that this helped
someone.

Donation link: https://ko-fi.com/pachecosolutions

---

## License

MIT — do whatever you like with it.
