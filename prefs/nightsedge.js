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
pref("toolkit.telemetry.shutdownPingSender.backgroundtask.enabled", false, locked);
pref("toolkit.telemetry.updatePing.enabled", false);
pref("toolkit.telemetry.server", "data:,");
pref("toolkit.telemetry.dap_enabled", false, locked);
pref("dom.security.unexpected_system_load_telemetry_enabled", false, locked);
pref("browser.search.serpEventTelemetryCategorization.enabled", false, locked);
pref("toolkit.telemetry.pioneer-new-studies-available", false);
pref("toolkit.telemetry.coverage.opt-out", true);
pref("toolkit.coverage.opt-out", true);
pref("toolkit.coverage.endpoint.base", "");

// --- Health Report ---
pref("datareporting.healthreport.uploadEnabled", false);
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("datareporting.usage.uploadEnabled", false, locked);

// --- Crash Reporter ---
pref("breakpad.reportURL", "");
pref("browser.tabs.crashReporting.sendReport", false);
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
pref("browser.crashReports.unsubmittedCheck.enabled", false);

// --- Studies / Normandy / Shield ---
pref("app.normandy.enabled", false, locked);
pref("app.normandy.api_url", "", locked);
pref("app.shield.optoutstudies.enabled", false, locked);

// --- Experiments ---
pref("messaging-system.rsexperimentloader.enabled", false, locked);
pref("browser.ping-centre.telemetry", false);
pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
pref("browser.newtabpage.activity-stream.telemetry", false);

// --- Network Services ---
pref("network.connectivity-service.enabled", false);
pref("captivedetect.canonicalURL", "");
pref("network.captive-portal-service.enabled", false);

// --- Attribution ---
pref("browser.attribution.enabled", false);

// --- Website-to-browser integration ---
pref("browser.uitour.enabled", false, locked);
pref("browser.uitour.url", "", locked);

// --- Discovery / Recommendations ---
pref("browser.discovery.enabled", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
pref("browser.newtabpage.activity-stream.feeds.discoverystreamfeed", false, locked);
pref("extensions.htmlaboutaddons.recommendations.enabled", false, locked);
pref("browser.preferences.moreFromMozilla", false, locked);

// --- Firefox Home ---
pref("browser.newtabpage.activity-stream.feeds.topsites", false);
pref("browser.newtabpage.activity-stream.showWeather", false);

// --- Sponsored Content / Advertising ---
// Disable the Recommended Stories / Popular Today surface as well as every
// advertising path. The endpoint and placement overrides also prevent ad
// requests if a feature rollout changes a higher-level UI default.
pref("browser.newtabpage.activity-stream.feeds.section.topstories", false, locked);
pref("browser.newtabpage.activity-stream.feeds.system.topstories", false, locked);
pref("browser.newtabpage.activity-stream.discoverystream.enabled", false, locked);
pref("browser.newtabpage.activity-stream.discoverystream.sections.enabled", false, locked);
pref("browser.newtabpage.activity-stream.discoverystream.sections.cards.enabled", false, locked);
pref("browser.newtabpage.activity-stream.showSponsored", false, locked);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false, locked);
pref("browser.newtabpage.activity-stream.system.showSponsored", false, locked);
pref("browser.newtabpage.activity-stream.showSponsoredCheckboxes", false, locked);
pref("browser.newtabpage.activity-stream.discoverystream.sections.contextualAds.enabled", false, locked);
pref("browser.newtabpage.activity-stream.discoverystream.region-spocs-config", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.spocs-endpoint", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.endpoints", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.endpointSpocsClear", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.placements.spocs", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.placements.spocs.counts", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.placements.tiles", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.placements.tiles.counts", "", locked);
pref("browser.newtabpage.activity-stream.discoverystream.placements.contextualSpocs", "", locked);
pref("browser.newtabpage.activity-stream.unifiedAds.tiles.enabled", false, locked);
pref("browser.newtabpage.activity-stream.unifiedAds.spocs.enabled", false, locked);
pref("browser.newtabpage.activity-stream.unifiedAds.adsFeed.enabled", false, locked);
pref("browser.newtabpage.activity-stream.unifiedAds.adsFeed.tiles.enabled", false, locked);
pref("browser.newtabpage.activity-stream.unifiedAds.ohttp.enabled", false, locked);
pref("browser.newtabpage.activity-stream.unifiedAds.endpoint", "", locked);
pref("browser.topsites.contile.enabled", false, locked);
pref("browser.topsites.contile.endpoint", "", locked);
pref("browser.topsites.useRemoteSetting", false, locked);
pref("browser.urlbar.sponsoredTopSites", false, locked);
pref("browser.urlbar.suggest.quicksuggest.sponsored", false, locked);
pref("browser.partnerlink.attributionURL", "", locked);
pref("browser.partnerlink.campaign.topsites", "", locked);

// --- General privacy hardening ---
pref("privacy.globalprivacycontrol.enabled", true);
pref("privacy.globalprivacycontrol.functionality.enabled", true);
pref("browser.privatebrowsing.forceMediaMemoryCache", true);
pref("dom.battery.enabled", false);
pref("security.tls.enable_0rtt_data", false);

// --- Glean ---
pref("toolkit.telemetry.glean.upload.enabled", false);

// --- Pocket ---
pref("extensions.pocket.enabled", false);

// --- Theme appearance ---
// false: paint theme background images only behind the top toolbox (Firefox 149 behavior).
// true: paint them behind both the toolbox and vertical-tabs sidebar (Firefox 150+ behavior).
pref("browser.theme.background-image-on-sidebar.enabled", false);
