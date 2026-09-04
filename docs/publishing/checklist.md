# Publication checklist

The order matters: the stores need a privacy policy address, and that only
exists once the repository is public.

## Before going public

- [ ] The contact in the [privacy policy](privacy-policy.md), which is a
      placeholder today.
- [ ] Check the name "Chatt" in the Play Console and Partner Center (reserving
      a name does not require publishing).
- [ ] A last pass over the README: does the first sentence say who this is for.
- [ ] Refreshed screenshots in both languages:
      `flutter test tool/product_shots.dart` (Android, PL),
      `set CHATT_SHOTS_LANG=en` and again (Android, EN),
      `flutter test tool/windows_shots.dart` in both languages (Windows),
      then `python tool/store_assets.py`.
      The source screenshots are in git, `docs/publishing/assets/` is **not**:
      it is script output and is produced on demand.
- [ ] The git history holds nothing you do not want to show
      (`git log --all --oneline | head`, searching by phrase with
      `git log -p -S`).
- [ ] `key.properties`, the keystore and `chatt.key` are **not** in the
      repository (`git ls-files | grep -iE "jks|keystore|key.properties"` has
      to return nothing).
- [ ] No local machine paths or personal addresses in the documentation
      (`git grep -niE "c:\\\\users\\\\[a-z]|@gmail|@outlook"` has to return
      nothing).

## Going public

- [ ] Settings, General, Danger Zone, Change visibility, Public.
- [ ] GitHub Pages from the `docs/` directory (Settings, Pages), so the privacy
      policy gets a permanent address. The alternative is a link to the file in
      `master`.
- [ ] Put the policy address into both store listings.

## Google Play

Details in [google-play.md](google-play.md).

- [ ] Create the app and the listing in two languages (EN default, PL).
- [ ] The 512 icon, the promotional graphic, 2 to 8 screenshots per language
      (`docs/publishing/assets/google-play/`).
- [ ] The questionnaires: policy, access, ads, rating, target audience, data
      safety.
- [ ] The first AAB uploaded by hand (from the GitHub release), to the
      **internal testing** track.
- [ ] If the account requires it: a closed test with 20 testers over 14 days.
- [ ] The service account and the `PLAY_SERVICE_ACCOUNT_JSON` secret, plus the
      upload step in the workflow.

## Microsoft Store

Details in [microsoft-store.md](microsoft-store.md).

- [ ] Reserve the name and copy the package identity into the repository
      variables `MSIX_IDENTITY_NAME`, `MSIX_PUBLISHER`,
      `MSIX_PUBLISHER_DISPLAY_NAME`.
- [ ] A release from the workflow will build `chatt-<version>-store.msix`; the
      first submission is done by hand in Partner Center.
- [ ] Check the package on a clean Windows account before sending it to
      certification: startup, firewall, receiving messages, the tray.
- [ ] Autostart in the Store build: either `StartupTask` in the manifest or a
      hidden switch (see the notes in microsoft-store.md).
- [ ] The Azure AD application and the `MSSTORE_*` secrets, plus the
      `msstore publish` step in the workflow.

## After publishing

- [ ] Show HN, r/selfhosted, r/privacy, Wykop, each post with a different
      opening sentence ([positioning.md](positioning.md)).
- [ ] A submission to AlternativeTo as a LocalSend alternative.
- [ ] winget (`wingetcreate` in the workflow) and IzzyOnDroid: both routes are
      free and both need only public releases.
