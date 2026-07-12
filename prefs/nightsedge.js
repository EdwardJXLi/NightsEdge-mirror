// NightsEdge — default preference overrides
// Included at the end of packaged firefox.js so these defaults load after
// Firefox's application defaults. Nightly's update destinations are patched
// directly in its branding preference file.

// --- Telemetry & Data Collection ---
pref("toolkit.telemetry.enabled", false);
pref("toolkit.telemetry.unified", false);
pref("toolkit.telemetry.archive.enabled", false);
pref("toolkit.telemetry.bhrPing.enabled", false);
pref("toolkit.telemetry.firstShutdownPing.enabled", false);
pref("toolkit.telemetry.newProfilePing.enabled", false);
pref("toolkit.telemetry.shutdownPingSender.enabled", false);
pref("toolkit.telemetry.updatePing.enabled", false);
pref("toolkit.telemetry.server", "data:,");
pref("toolkit.telemetry.pioneer-new-studies-available", false);
pref("toolkit.telemetry.coverage.opt-out", true);
pref("toolkit.coverage.opt-out", true);
pref("toolkit.coverage.endpoint.base", "");

// --- Health Report ---
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);

// --- Crash Reporter ---
pref("breakpad.reportURL", "");
pref("browser.tabs.crashReporting.sendReport", false);
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
pref("browser.crashReports.unsubmittedCheck.enabled", false);

// --- Studies / Normandy / Shield ---
pref("app.normandy.enabled", false);
pref("app.normandy.api_url", "");
pref("app.shield.optoutstudies.enabled", false);

// --- Experiments ---
pref("messaging-system.rsexperimentloader.enabled", false);
pref("browser.ping-centre.telemetry", false);
pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
pref("browser.newtabpage.activity-stream.telemetry", false);

// --- Network Services ---
pref("network.connectivity-service.enabled", false);
pref("captivedetect.canonicalURL", "");
pref("network.captive-portal-service.enabled", false);

// --- Attribution ---
pref("browser.attribution.enabled", false);

// --- Discovery / Recommendations ---
pref("browser.discovery.enabled", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
pref("browser.newtabpage.activity-stream.feeds.discoverystreamfeed", false);

// --- Sponsored Content / Advertising ---
// Disable the Recommended Stories / Popular Today surface as well as every
// advertising path. The endpoint and placement overrides also prevent ad
// requests if a feature rollout changes a higher-level UI default.
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);
pref("browser.newtabpage.activity-stream.feeds.system.topstories", false);
pref("browser.newtabpage.activity-stream.discoverystream.enabled", false);
pref("browser.newtabpage.activity-stream.discoverystream.sections.enabled", false);
pref("browser.newtabpage.activity-stream.discoverystream.sections.cards.enabled", false);
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);
pref("browser.newtabpage.activity-stream.system.showSponsored", false);
pref("browser.newtabpage.activity-stream.discoverystream.sections.contextualAds.enabled", false);
pref("browser.newtabpage.activity-stream.discoverystream.region-spocs-config", "");
pref("browser.newtabpage.activity-stream.discoverystream.spocs-endpoint", "");
pref("browser.newtabpage.activity-stream.discoverystream.placements.spocs", "");
pref("browser.newtabpage.activity-stream.discoverystream.placements.contextualSpocs", "");
pref("browser.newtabpage.activity-stream.unifiedAds.tiles.enabled", false);
pref("browser.newtabpage.activity-stream.unifiedAds.spocs.enabled", false);
pref("browser.newtabpage.activity-stream.unifiedAds.adsFeed.enabled", false);
pref("browser.newtabpage.activity-stream.unifiedAds.adsFeed.tiles.enabled", false);
pref("browser.newtabpage.activity-stream.unifiedAds.endpoint", "");
pref("browser.topsites.contile.enabled", false);
pref("browser.urlbar.sponsoredTopSites", false);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false);
pref("browser.partnerlink.attributionURL", "");

// --- Glean ---
pref("toolkit.telemetry.glean.upload.enabled", false);

// --- Pocket ---
pref("extensions.pocket.enabled", false);

// --- Update channel ---
pref("app.update.url", "https://updates.example.com/update/6/%PRODUCT%/%VERSION%/%BUILD_ID%/%BUILD_TARGET%/%LOCALE%/%CHANNEL%/%OS_VERSION%/%SYSTEM_CAPABILITIES%/%DISTRIBUTION%/%DISTRIBUTION_VERSION%/update.xml");
