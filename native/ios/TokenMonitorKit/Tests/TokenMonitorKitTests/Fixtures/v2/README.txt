Round-2 fixtures (Fixtures/v2) - not shipped; test resources only
====================================================================

What this is
------------
Responses captured verbatim from a real Node Hub (src/hub/server.js, unmodified)
plus "golden" outputs rendered by running the desktop JS modules on those
responses. Swift ports must reproduce the goldens exactly (plan section 0.5).
All data is synthetic: emails are example.com/example.org, account keys are
sha256:fixture-*, no real accounts or tokens.

Frozen clock
------------
capture.json holds the instant every file was rendered at:
  now       2026-10-10T16:30:00.000Z (a Saturday)
  timeZone  UTC   (the "phone": every local-time desktop helper ran with TZ=UTC)
  todayKey  2026-10-10
Per-device time zones, today keys and expiry live in capture.json "devices":
  studio-mac  America/Los_Angeles  today 2026-10-10  fresh (uploaded now-20s)
  build-box   UTC                  today 2026-10-10  fresh (now-5m, 10-minute upload interval)
  tokyo-mac   Asia/Tokyo           today 2026-10-11  fresh (now-40s), no history
  old-laptop  Asia/Shanghai        today 2026-10-10  STALE (now-70m), today window expired, history null
The Hub ran under a preload that freezes Date (clock.js); the seed log with the
clock value of every request is in capture.json "seed".

Hub captures (raw response bodies)
----------------------------------
health.json            GET /api/health (no auth)
stats.json             GET /api/stats
stats-stream.txt       GET /api/stats/stream without x-token-monitor-stream: 2 (iOS request);
                       2 frames: `snapshot` at now, `stats` (reason ingest) at now+5s after
                       build-box re-uploads with today x1.04
history.json           GET /api/history  ({daily, monthly, summary}; daily capped at 370 days)
devices.json           GET /api/devices  ({devices: [stored records incl. history]})
subscriptions.json     GET /api/subscriptions
sync-content.json      GET /api/sync/content (session titles enabled on this Hub)
model-aliases.json     GET /api/sync/settings/modelAliases (revision 1, grouping duplicates)
custom-pricing.json    GET /api/sync/settings/customPricing (revision 1)
capture.json           clock, per-device day keys, locales, seed log
.gitattributes         keeps the export CSVs' CRLF and the stream's final blank line byte-exact

Seed: PUT /api/sync/titles/studio-mac {enabled:true} (generation 1) before the
studio upload, so only studio-mac session titles survive; build-box sends a
title that the Hub strips. Subscriptions cover a Jan-31 monthly anchor, a
yearly plan with nextRenewalOverride, autoRenew off with endDate, a lapsed
plan, a TWD quarterly plan, and HKD/CNY top-up ledgers (one invalid top-up
date that the Hub drops).

Goldens (golden/)
-----------------
Every file carries a "source" field naming the module path, function and
arguments. Module paths are relative to the repo root. Internal (unexported)
functions were reached by loading the unmodified source with extra names added
to its export list; their names are marked "internal". Layout notes:
"outputs[i]" rows align with the sibling "values" list; "...Fields" arrays name
the columns of compact array rows.

compact-tokens.json    src/shared/compactTokens.js  formatCompactTokens/formatCompactValue grid
                       (values x western/localized x desktop + iOS locales), option variants,
                       units/threshold table, and every vector of tests/shared/compactTokens.test.js
compact-money.json     src/shared/currency.js convertUsd/formatCurrencyFromUsd (built-in and configured
                       rates), src/shared/compactMoney.js formatCompactCurrencyFromUsd (incl. options and
                       tests/shared/compactMoney.test.js vectors), src/shared/limits/balanceDisplay.js
                       formatMoney/formatCompactMoney
exchange-rates.json    src/shared/exchangeRates.js parseUsdRates on sample CDN payloads, isCacheStale,
                       todayUtc, SOURCES; src/shared/currency.js resolveEffectiveRates; the configured
                       rates used by compact-money.json and subscriptions.json
heatmap.json           fixedPeriodRanges dailyWithLiveToday (internal) + usageCharts
                       computeHeatmapIntensities/rollingYearHeatmap for tokens and cost (Sunday rows),
                       aggregate (history.json) and device (studio-mac from devices.json); statsCards
bars.json              usageCharts dailyBarsChart over 7/30 calendar days (dailyForRange fill + today
                       patch), stacked by client and model, tokens and cost
candles.json           usageCharts candleChart for ranges 7/30/90/365/all at plot widths
                       200/320/390/600/1200 (bucketDays from dashboard.js:365-367)
area-line.json         usageCharts areaLineChart (Home trend: patchDailyToday + clampDaily 45, curve)
                       and calendar ranges; homeOverview homeTrendSummary/longRangePeakDayTokens
fixed-range.json       fixedPeriodRanges weekStartsOn, rangeForSelection (week en-US/en-GB, last7,
                       last30), fixedPeriodSnapshot (aggregate), fixedPeriodSnapshotFromDevices (per
                       device), deviceDayState (internal), tokenComponentBreakdown
aliases.json           renderer/modelAliases.js resolver/inference for off/duplicates/prefix;
                       electron/modelAliasPresentation.js collectStatsModelIds (internal),
                       projectModelAliasStats periods, projectModelAliasHistory summary/rows
subscriptions.json     src/shared/subscriptionDisplay.js every function at 4 "today" dates with the
                       configured rates; matchProviderAccount against stats limits; topUpProjection
sessions.json          renderer/sessionRows.js sessionRowsForPeriod/groupBackgroundReviewRows and
                       per-session helpers; src/shared/sessionLive.js state/context/promptCache and
                       next-change instants; at now and now+20m
projects.json          renderer/projectRows.js projectRowsForPeriod/projectBreakdownIncomplete;
                       src/shared/projectKey.js
attribution.json       renderer/usageAttributionRows.js tool/model rows, ranking, cost labels;
                       renderer/toolDetails.js model rows per tool and percentages;
                       renderer/clientDisplayPreferences.js applyClientDisplayPreferences
usage-items.json       src/shared/limits/usageItems.js window keys, item ids, fallback labels,
                       hidden-item normalization and edits, for every window in stats.json
limit-status.json      renderer/limits/providerPresentation.js status label, freshness, boundary
                       text, source and plan labels; renderer/limits/displayMode.js fill percent;
                       balanceDisplay credits helpers; homeOverview homeLimitAccounts
client-health.json     renderer/clientHealthPresentation.js details/counts,
                       renderer/clientStatusPresentation.js tags, renderer/deviceBreakdown.js tool rows
live-rate.json         renderer/tokenRatePresentation.js group and single trackers driven by a fake
                       clock, selectLiveTokenRatePeriods, tooltip entries, per-period rates
export/manifest.json   src/shared/exporter.js exportFileSet inputs, file list, csvEscape cases
export/token-monitor-export.json         exportFileSet output (LF, pretty JSON)
export/token-monitor-snapshot.csv        exportFileSet output (BOM + CRLF)
export/token-monitor-daily.csv           exportFileSet output (BOM + CRLF)
export/token-monitor-daily-models.csv    exportFileSet output (BOM + CRLF)
statuspage/none.json         synthetic Statuspage v2 summary (all operational)
statuspage/minor.json        synthetic summary (degraded components, one active incident)
statuspage/major.json        synthetic summary (outage, unnamed component, two incidents)
statuspage/maintenance.json  synthetic summary (maintenance in progress)
statuspage/malformed.json    synthetic summary with wrong types everywhere
statuspage/summaries.json    src/electron/serviceStatus.js summarizeStatuspageProvider for each file
                             plus error cases; renderer/serviceStatusPresentation.js helpers

Regenerating
------------
The generator lives outside the repo (scratchpad fixturegen-r2/run.sh); re-running
it with the same "now" reproduces every file byte for byte.
