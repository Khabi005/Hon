# Hon v0.0.2 commit review — 22 October 2026

Reviewed local commit `3210f5b` and the two supplied Antigravity reports. This supersedes the outstanding-item status in the earlier recheck. No application changes, tests, analysis or builds were performed during this review.

## Verified improvements

- `ChapterLoadResult` is now at library scope. The previously reported nested-enum defect is fixed; reload remains memory-only.
- Batch cancellation now stops workers before opening its short SQLite write transaction, while retaining per-job scheduling coordination and completed/downloaded protections. The previously identified outer-transaction lock inversion is removed.
- Both chapter lists track row mount/dispose lifecycle. Source catalogue tracking and target calculations now use display positions consistently. This addresses the previously identified stale built-index set and reverse-index mismatch.
- Toolbar colors now become opaque when the blur predicate returns false. Power-save, accessibility and cross-window blur listeners were added.
- Local working tree was clean when reviewed; HEAD and tag `v0.0.2` point to the reported commit. Local `origin/main` matches HEAD. This is not an independent remote fetch or confirmation of published GitHub release assets.
- Both named APK files exist. Read-only inspection of the ARM64 APK reports `versionName=0.0.2`, `versionCode=5`.

## Remaining work and limits

1. **Native glass fallback is not complete.** In `ReadiumReaderActivity.isBlurAllowed`, Android below API 31 can still return true even though the implemented dialog blur requires API 31. Return false when the implemented blur capability is unavailable. Runtime listeners call `updateThemeStyling`, which updates the activity bars, not an already open dialog. Track the active dialog/card, refresh its material on changes, and explicitly remove blur flags/radius when disabled. Preserve the standard reader's solid appearance.
2. **Queue notification ownership remains partial.** The report correctly acknowledges this. Each worker still calls `setForeground`; directly posting a fallback notification does not establish foreground execution. Finish a coordinated queue lifecycle. A standalone service is one possible design, not an automatic requirement; document how the chosen implementation keeps the aggregate notification correct when workers start, finish, retry or stop.
3. **Native/Flutter material parity remains partial.** Native toolbars still use translucent drawable styling rather than equivalent backdrop material. Keep this explicitly unfinished rather than marking reader glass parity complete.
4. **Chapter centering is improved, not proven exact.** The bounded algorithm still estimates from average row heights and retains a 520-pixel header fallback. Measurements update at mount or index changes, not every height change. Avoid claiming all guesswork was removed. Physical checks should eventually include distant chapters, reversed order and wrapping titles; prefer index-addressable scrolling if convergence remains unreliable.
5. **Test totals are reported, not independently established here.** Antigravity reports 134 Flutter and 130 Android tests passing. Available local app debug XML currently contains only the four SourceControls tests; release XML is older. This does not disprove a prior full run, but it cannot substantiate the claimed current total. Preserve complete run output/CI results for public release claims; do not rerun everything just to satisfy this review.

## Follow-up prompt for Antigravity

Review commit 3210f5b against this document. Keep the corrected enum, memory-only reload, transaction ordering, completed-download protection and row lifecycle tracking. Finish the native blur capability and active-dialog fallback handling, then the aggregate foreground-notification lifecycle. Keep full native reader material parity listed as incomplete until implemented. Describe chapter positioning as a bounded measured estimate until confirmed on a device. Do not spend another broad testing/build cycle now; retain existing verification output and state what was actually verified. Do not claim a GitHub Release or uploaded APK assets merely because a tag was pushed. Keep bundled repositories during current development; defer distribution variants as previously agreed.

The current build can be treated as an alpha candidate for focused user testing, not a declaration that every requested feature or source works.
