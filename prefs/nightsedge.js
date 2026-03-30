// NightsEdge — default preference overrides
// Baked into the build via browser/defaults/preferences/

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
pref("browser.newtabpage.activity-stream.showSponsored", false);
pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);

// --- Glean ---
pref("toolkit.telemetry.glean.upload.enabled", false);

// --- Pocket ---
pref("extensions.pocket.enabled", false);

// --- Update channel ---
pref("app.update.url", "https://updates.example.com/update/6/%PRODUCT%/%VERSION%/%BUILD_ID%/%BUILD_TARGET%/%LOCALE%/%CHANNEL%/%OS_VERSION%/%SYSTEM_CAPABILITIES%/%DISTRIBUTION%/%DISTRIBUTION_VERSION%/update.xml");
pref("app.update.url.manual", "https://updates.example.com");
pref("app.update.url.details", "https://updates.example.com");
