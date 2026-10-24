// SPDX-License-Identifier: PolyForm-Noncommercial-1.0.0
// Copyright (C) 2025-2026 Bain Gurley

//
//  SettingsDescriptors.swift
//  Rivulet
//
//  Per-setting descriptors for the split settings left panel
//

import UIKit

// MARK: - Setting Descriptor

struct SettingDescriptor {
    let icon: String
    let description: String
}

// MARK: - Descriptor Store

enum SettingsDescriptorStore {
    static func descriptor(for id: String) -> SettingDescriptor? {
        if let exact = descriptors[id] { return exact }
        // Rows built per item at runtime carry the item's identity in their id,
        // so they cannot have their own entry. Fall back on the row KIND, which
        // is what the panel wants to explain anyway.
        if id.hasPrefix("homeRow_") { return descriptors["homeRowItem"] }
        if id.hasPrefix("pinnedCollection_") { return descriptors["pinnedCollection"] }
        if id.hasPrefix("fav_") { return descriptors["liveTVFavoriteRow"] }
        if id.hasPrefix("sq_") { return descriptors["streamingQualityOption"] }
        if id.hasPrefix("al_") { return descriptors["audioLanguage"] }
        if id.hasPrefix("sl_") { return descriptors["subtitleLanguage"] }
        if id.hasPrefix("hs_") { return descriptors["heightSpeakers"] }
        if id.hasPrefix("sm_") { return descriptors["subtitleMode"] }
        if id.hasPrefix("ai_") { return descriptors["appIcon"] }
        if id.hasPrefix("dr_") { return descriptors["detailRating"] }
        if id.hasPrefix("alim_") { return descriptors["autoplayLimit"] }
        if id.hasPrefix("plexServer_") { return descriptors["plexServerOption"] }
        if id.hasPrefix("lib_") { return descriptors["libraryRow"] }
        if id.hasPrefix("sb_#livetv") { return descriptors["sidebarLiveTVRow"] }
        if id.hasPrefix("sb_") { return descriptors["sidebarAppRow"] }
        if id.hasPrefix("intHeader_") { return descriptors["intHeaderRow"] }
        return nil
    }

    private static let descriptors: [String: SettingDescriptor] = [
        // MARK: Root Categories
        "cat_appearance": SettingDescriptor(
            icon: "paintbrush.fill",
            description: "Customize how Rivulet looks — display size, hero banners, sidebar libraries, and content discovery rows."
        ),
        "cat_playback": SettingDescriptor(
            icon: "play.fill",
            description: "Configure audio, subtitles, skip behavior, and autoplay."
        ),
        "cat_liveTV": SettingDescriptor(
            icon: "tv.fill",
            description: "Manage Live TV sources, layout preferences, multiview settings, and channel display options."
        ),
        "cat_servers": SettingDescriptor(
            icon: "server.rack",
            description: "Manage your Plex server connection and user profiles."
        ),
        "cat_about": SettingDescriptor(
            icon: "info.circle.fill",
            description: "App version, changelog, and other information about Rivulet."
        ),

        // MARK: Appearance
        "libraries": SettingDescriptor(
            icon: "sidebar.squares.left",
            description: "Choose what appears in the sidebar and set its order. Libraries apply to Home as well: a library you turn off here loses its Home rows, and the order you set here is the order Home draws them in."
        ),
        "resetSidebar": SettingDescriptor(
            icon: "arrow.counterclockwise",
            description: "Put every sidebar row back in its original order and show the ones you hid. Home's rows follow the library order."
        ),
        "sidebarAppRow": SettingDescriptor(
            icon: "sidebar.squares.left",
            description: "Click to show or hide this row in the sidebar. Press and hold to move it up or down."
        ),
        "sidebarLiveTVRow": SettingDescriptor(
            icon: "tv",
            description: "Press and hold to move Live TV up or down. It leaves the sidebar when its sources are removed."
        ),
        "libraryRow": SettingDescriptor(
            icon: "sidebar.squares.left",
            description: "Click to show or hide this library in the sidebar and on Home. Press and hold to move it up or down."
        ),
        "appIcon": SettingDescriptor(
            icon: "app.badge",
            description: "Choose the Rivulet icon on the Apple TV Home Screen."
        ),

        "homeRows": SettingDescriptor(
            icon: "rectangle.grid.1x2",
            description: "Turn individual Home rows off. The rows and their titles come from your Plex account, so they match the Plex app. Turning one off here hides it on this Apple TV only. A library appears here once it is pinned to Home in Plex, under Settings then Manage then Libraries."
        ),
        "showAllHomeRows": SettingDescriptor(
            icon: "eye",
            description: "Show every row your Plex account puts on Home again."
        ),
        "homeRowItem": SettingDescriptor(
            icon: "rectangle.grid.1x2",
            description: "Turn this row off to hide it on this Apple TV. Your Plex account is unchanged, so the row keeps showing in the Plex app and on your other devices."
        ),
        "pinnedCollection": SettingDescriptor(
            icon: "pin",
            description: "A collection you pinned from its tile menu. Hold Select to reorder, or Select to unpin it."
        ),
        "homeHero": SettingDescriptor(
            icon: "sparkles.rectangle.stack",
            description: "Shows a large featured content banner at the top of the Home screen with artwork and quick actions."
        ),
        "detailRating": SettingDescriptor(
            icon: "star.leadinghalf.filled",
            description: "Choose the one rating shown at the top of a movie or show's details. If a title doesn't have the rating you choose, Rotten Tomatoes is shown instead."
        ),
        "libraryHero": SettingDescriptor(
            icon: "rectangle.stack",
            description: "Shows a featured content banner at the top of each library with highlighted picks."
        ),
        "discoveryRows": SettingDescriptor(
            icon: "square.stack.3d.up",
            description: "Adds discovery rows like Top Rated, Rediscover, and Similar Items to help you find things to watch."
        ),
        "recentRows": SettingDescriptor(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            description: "Shows Recently Added and Recently Released rows in each library."
        ),
        "personalizedRecs": SettingDescriptor(
            icon: "person.3",
            description: "Uses TMDB metadata and your watch history to surface personalized recommendations of unwatched content."
        ),
        // MARK: Playback
        "autoSkipIntro": SettingDescriptor(
            icon: "play.circle",
            description: "What happens when an intro starts. Button shows Skip Intro, Automatic skips it after a short countdown, and Off never shows the button."
        ),
        "autoSkipCredits": SettingDescriptor(
            icon: "stop.circle",
            description: "What happens when the credits start. Button shows Skip Credits, Automatic skips straight to the post-play screen, and Off never shows the button."
        ),
        "autoSkipAds": SettingDescriptor(
            icon: "forward.frame",
            description: "What happens when an ad break starts. Button shows Skip Ad, Automatic skips it after a short countdown, and Off never shows the button."
        ),
        "autoSkipRecap": SettingDescriptor(
            icon: "backward.end.circle",
            description: "What happens when a 'previously on' recap starts. Button shows Skip Recap, Automatic skips it, and Off never shows the button. Recap markers come from the community database below."
        ),
        "useIntroDB": SettingDescriptor(
            icon: "magnifyingglass",
            description: "Fills in missing intro, recap, and credits markers from the community database introdb.app, sending only the show's ID and episode number. Your own server's markers are always used first."
        ),
        "promptResumeOrRestart": SettingDescriptor(
            icon: "questionmark.circle",
            description: "In-progress items show a Resume / Start from Beginning prompt before playing, like Apple TV."
        ),
        "instantResume": SettingDescriptor(
            icon: "play.rectangle.on.rectangle",
            description: "Selecting a Continue Watching tile resumes it immediately. Turn this off to open the preview instead, the same as every other Home row, which also disables the Resume or Restart Prompt below."
        ),
        "homeStreamingQuality": SettingDescriptor(
            icon: "house.fill",
            description: "Quality when the server is on your home network. Original plays the file untouched, with HDR, Dolby Vision and Atmos."
        ),
        "awayStreamingQuality": SettingDescriptor(
            icon: "antenna.radiowaves.left.and.right",
            description: "Quality on cellular, a hotspot, Low Data Mode or a remote connection. Auto measures your connection and converts only when the file will not fit."
        ),
        "streamingQualityOption": SettingDescriptor(
            icon: "dial.medium",
            description: "Original plays the file untouched. Auto measures your connection and converts only when the file will not fit. A fixed rate converts anything above it; converted video plays without HDR, Dolby Vision or Atmos."
        ),
        "audioLanguage": SettingDescriptor(
            icon: "waveform",
            description: "The audio track to play when a title has several. Plex Account follows the audio language set in your Plex account (English on other servers). Original plays the file's main track, so foreign films and anime keep their own language. Picking a track in the player also changes this."
        ),
        "subtitleMode": SettingDescriptor(
            icon: "captions.bubble",
            description: "Foreign Audio shows subtitles when the audio is not in your subtitle language, and forced subtitles for foreign lines otherwise. Always shows them on every title. Picking a track in the player also changes this."
        ),
        "subtitleLanguage": SettingDescriptor(
            icon: "globe",
            description: "The language subtitles are shown in."
        ),
        "subtitleSDH": SettingDescriptor(
            icon: "ear",
            description: "Prefers subtitles for the deaf and hard of hearing, which also describe sounds and name who is speaking."
        ),
        "heightSpeakers": SettingDescriptor(
            icon: "hifispeaker.2",
            description: "Keeps the height channels of Dolby TrueHD Atmos and DTS:X soundtracks, in a lossy format. Off plays lossless 7.1 without them. DTS:X needs 7.1.4 or 9.1.6. With Dolby Vision FEL on, a FEL video plays its soundtrack without heights."
        ),
        "dolbyVisionFEL": SettingDescriptor(
            icon: "4k.tv",
            description: "Plays the full enhancement layer of Dolby Vision Profile 7 videos on a Dolby Vision TV. FEL videos play without Atmos and DTS:X height channels, AirPlay or Picture in Picture. Off plays them as Profile 8.1."
        ),
        "autoplayCountdown": SettingDescriptor(
            icon: "forward.end.alt",
            description: "How long to wait before automatically playing the next episode. Set to Off to disable autoplay."
        ),
        "autoplayLimit": SettingDescriptor(
            icon: "moon.zzz",
            description: "After this many episodes play in a row, the next one waits for you instead of starting on its own."
        ),
        "skipLength": SettingDescriptor(
            icon: "forward.fill",
            description: "How far a single Right press skips ahead during playback."
        ),
        "skipBackLength": SettingDescriptor(
            icon: "backward.fill",
            description: "How far a single Left press skips back during playback."
        ),
        "showPostVideoUpNext": SettingDescriptor(
            icon: "rectangle.stack",
            description: "When off, closing credits play uninterrupted and the player returns to Home at the end of the episode."
        ),

        // MARK: Live TV
        "combineSources": SettingDescriptor(
            icon: "square.stack.3d.down.right",
            description: "Shows all Live TV sources together under one sidebar entry, or gives each source its own."
        ),
        "defaultLayout": SettingDescriptor(
            icon: "tv",
            description: "Choose your default Live TV view: the TV guide, or What's On, with rows of what is on now and multiview like the Apple TV app."
        ),
        "liveTVFavorites": SettingDescriptor(
            icon: "star.fill",
            description: "Set the order of your favorite channels, from every source. To add one, hold Select on a channel in What's On or the guide."
        ),
        "liveTVFavoriteRow": SettingDescriptor(
            icon: "star.fill",
            description: "Hold Select to move this channel, then press Select to drop it. Select to remove it. Favorites you set in Plex come after these, in Plex's order."
        ),
        "noLiveTVFavorites": SettingDescriptor(
            icon: "star",
            description: "Hold Select on a channel in What's On or the guide and choose Add to Favorites. Favorites from every source share one list."
        ),
        "liveTVSuggestions": SettingDescriptor(
            icon: "sparkles",
            description: "What's On learns what you watch and suggests what is on now that is like it, in a For You row. It learns on this Apple TV only. Turn it off to hide the row and stop learning."
        ),
        "keepPlayingInGuide": SettingDescriptor(
            icon: "pip",
            description: "When you go back from a live channel, it keeps playing with its sound in the corner of the Guide or What's On. Select it again to return to full screen."
        ),
        "confirmExitMultiview": SettingDescriptor(
            icon: "rectangle.split.2x2",
            description: "Shows a confirmation dialog before closing multiview mode to prevent accidentally ending multiple streams."
        ),

        // MARK: Storage
        "cache": SettingDescriptor(
            icon: "internaldrive",
            description: "View storage usage and manage cached images, metadata, and other temporary data."
        ),
        "forceRefresh": SettingDescriptor(
            icon: "arrow.clockwise",
            description: "Clear metadata cache and reload all library content from your Plex server. Images will be kept."
        ),
        "clearAllCache": SettingDescriptor(
            icon: "trash",
            description: "Remove all cached images and metadata. Content will be re-downloaded as needed."
        ),

        // MARK: Servers
        "plexServer": SettingDescriptor(
            icon: "server.rack",
            description: "Every Plex server on your account. Select one to see its details."
        ),
        "plexServerOption": SettingDescriptor(
            icon: "server.rack",
            description: "See this server's details. A server shared with you shows who owns it."
        ),
        "plexServerEnabled": SettingDescriptor(
            icon: "power",
            description: "Turn off to remove this server from Rivulet: its libraries, Home rows, Continue Watching and Live TV. Your account stays signed in."
        ),
        "plexServerRefresh": SettingDescriptor(
            icon: "arrow.clockwise",
            description: "Ask Plex for this server's latest status."
        ),
        "plexServersLoading": SettingDescriptor(
            icon: "server.rack",
            description: "Finding the servers on your Plex account."
        ),
        "plexServersRetry": SettingDescriptor(
            icon: "arrow.clockwise",
            description: "Plex didn't return your servers. Check your network, then select to try again."
        ),
        "signOut": SettingDescriptor(
            icon: "rectangle.portrait.and.arrow.right",
            description: "Sign out of your Plex account. Every Plex server on it leaves Rivulet until you sign in again."
        ),
        "jellyfinServer": SettingDescriptor(
            icon: "server.rack",
            description: "Sign in to your Jellyfin server."
        ),
        "jellyfinURL": SettingDescriptor(
            icon: "globe",
            description: "Your Jellyfin server's address, including the port, for example http://192.168.1.100:8096. You can paste the address from your browser."
        ),
        "jellyfinUsername": SettingDescriptor(
            icon: "person",
            description: "Your Jellyfin username."
        ),
        "jellyfinPassword": SettingDescriptor(
            icon: "key",
            description: "Used once, to sign in. Rivulet keeps the access token Jellyfin returns, not the password."
        ),
        "jellyfinSignIn": SettingDescriptor(
            icon: "link",
            description: "Check the server and sign in."
        ),
        "jellyfinSignOut": SettingDescriptor(
            icon: "rectangle.portrait.and.arrow.right",
            description: "Sign out of this Jellyfin server and remove its saved credentials."
        ),
        "connectPlex": SettingDescriptor(
            icon: "link",
            description: "Connect to your Plex server to browse and stream your media library."
        ),
        "profilePickerOnLaunch": SettingDescriptor(
            icon: "person.2.circle",
            description: "Shows the profile picker each time Rivulet launches, allowing you to choose which profile to use."
        ),
        "liveTVSources": SettingDescriptor(
            icon: "tv.and.mediabox",
            description: "Add and manage your own Live TV sources — your Plex server's Live TV, or an M3U/IPTV playlist from a provider you subscribe to. Rivulet does not provide any channels or content of its own."
        ),
        "plexLiveTVSource": SettingDescriptor(
            icon: "play.rectangle.fill",
            description: "Plex Live TV source using your server's DVR tuners. Tap to view details or remove."
        ),
        "dispatcharrSource": SettingDescriptor(
            icon: "antenna.radiowaves.left.and.right",
            description: "Dispatcharr source providing managed IPTV channels. Tap to view details or remove."
        ),
        "m3uSource": SettingDescriptor(
            icon: "list.bullet.rectangle",
            description: "M3U playlist source for IPTV channels. Tap to view details or remove."
        ),
        "addLiveTVSource": SettingDescriptor(
            icon: "plus.circle.fill",
            description: "Connect a Live TV source you already have access to: your Plex server's tuners, a login or playlist from an IPTV provider, or a server you run yourself."
        ),
        "refreshChannels": SettingDescriptor(
            icon: "arrow.clockwise",
            description: "Reload the channel list and EPG data from this source."
        ),
        "removeSource": SettingDescriptor(
            icon: "trash",
            description: "Remove this Live TV source and all its channels."
        ),
        "addXtream": SettingDescriptor(
            icon: "person.badge.key",
            description: "Sign in with the server address, username and password your IPTV provider gave you, often called an Xtream Codes login. Rivulet loads the channels, categories and guide. It supplies no channels of its own."
        ),
        "xtreamServerField": SettingDescriptor(
            icon: "globe",
            description: "The server address from your provider, with its port, for example http://provider.example:8080. If your provider gave you a single link with your username and password in it, enter that instead: Rivulet fills in the rest."
        ),
        "xtreamUsernameField": SettingDescriptor(
            icon: "person",
            description: "The username your provider gave you."
        ),
        "xtreamPasswordField": SettingDescriptor(
            icon: "key",
            description: "The password your provider gave you. Rivulet keeps it in the Keychain."
        ),
        "addOwnServer": SettingDescriptor(
            icon: "server.rack",
            description: "A server you run yourself that serves a playlist and a guide, such as Dispatcharr, Threadfin, xTeVe, ErsatzTV, or Cabernet. You give Rivulet the address and it finds the rest."
        ),
        "addPlaylistURL": SettingDescriptor(
            icon: "list.bullet.rectangle",
            description: "An M3U playlist link from an IPTV provider you subscribe to, with an optional guide link. Rivulet supplies no channels of its own."
        ),
        "serverURL": SettingDescriptor(
            icon: "globe",
            description: "The address of your server on your network, including the port. Pick your app from the suggestions to fill in the usual one."
        ),
        "displayNameField": SettingDescriptor(
            icon: "textformat",
            description: "What this source is called in Live TV. Optional."
        ),
        "usernameField": SettingDescriptor(
            icon: "person",
            description: "Dispatcharr only. Sign in with your Dispatcharr user so Rivulet can schedule recordings and series from the guide. Leave it empty to just watch."
        ),
        "passwordField": SettingDescriptor(
            icon: "key",
            description: "Used once, to fetch your Dispatcharr API key. Rivulet keeps the key, not the password."
        ),
        "channelProfileField": SettingDescriptor(
            icon: "line.3.horizontal.decrease.circle",
            description: "Dispatcharr only. The name of a channel profile, to load just that set of channels. Leave it empty and you get every channel on the server."
        ),
        "m3uURLField": SettingDescriptor(
            icon: "list.bullet.rectangle",
            description: "The playlist link your IPTV provider gave you, for example http://provider.example/playlist.m3u. It usually ends in .m3u or .m3u8."
        ),
        "epgURLField": SettingDescriptor(
            icon: "calendar",
            description: "Optional. An XMLTV guide link from the same provider, so channels show what is on. Leave it empty if the playlist names its own guide."
        ),
        "addSourceConfirm": SettingDescriptor(
            icon: "plus.circle.fill",
            description: "Checks the connection and adds the source if it works. If it does not, Rivulet tells you why."
        ),

        // MARK: About
        "changelog": SettingDescriptor(
            icon: "list.bullet.rectangle",
            description: "Release notes for every version of Rivulet."
        ),
        "licensesLegal": SettingDescriptor(
            icon: "doc.text.fill",
            description: "Rivulet's license and the open-source software it uses, including FFmpeg (LGPL), libdovi, and Sentry."
        ),
        "inputDiagnostics": SettingDescriptor(
            icon: "dot.radiowaves.left.and.right",
            description: "Show every remote button press on screen, with how long it was held and which remote sent it. Helpful when reporting a problem with a third-party remote. Leave this off for normal viewing."
        ),
        "inputTest": SettingDescriptor(
            icon: "checklist",
            description: "Asks you to press a short list of buttons, then records what your remote actually sent for each one. The result goes to Rivulet's diagnostics so a reported problem can be traced. Nothing about what you watch is included."
        ),

        "sendDiagnostics": SettingDescriptor(
            icon: "stethoscope",
            description: "Sends a snapshot of how Rivulet is set up and running, with recent log lines, and gives you a short code to include when you report a problem. It holds counts and settings only: no titles, server names, addresses or passwords."
        ),

        // MARK: Content Filtering
        "cat_contentFilter": SettingDescriptor(
            icon: "hand.raised.fill",
            description: "Mute strong language and skip scenes during playback, without ever changing the file. Language is found in the title's English subtitles, even with subtitles turned off. Scene skips come from an imported filter list."
        ),
        "cf_master": SettingDescriptor(
            icon: "hand.raised.fill",
            description: "Turn the local content filter on. Rivulet then mutes and skips in real time based on the categories below. While it's on, a button in the player pauses filtering for the title you're watching."
        ),
        "cf_profanity": SettingDescriptor(
            icon: "exclamationmark.bubble.fill",
            description: "Mutes profane words in the dialogue. Rivulet reads the title's subtitles even when they are off, including ones inside the video file. Use Profanity Strength to choose how much is filtered."
        ),
        "cf_strength": SettingDescriptor(
            icon: "dial.medium.fill",
            description: "How much profanity to mute: mild and up, moderate and up, or strong words only. Also applies to profanity in imported filter lists."
        ),
        "cf_blasphemy": SettingDescriptor(
            icon: "hands.clap.fill",
            description: "Mutes religious names used as exclamations, such as \"oh my god\". The word god on its own is never muted."
        ),
        "cf_slur": SettingDescriptor(
            icon: "person.fill.xmark",
            description: "Mutes racial, homophobic and other slurs in the dialogue."
        ),
        "cf_sexualLanguage": SettingDescriptor(
            icon: "heart.slash.fill",
            description: "Mutes crude and sexual language in the dialogue."
        ),
        "cf_violence": SettingDescriptor(
            icon: "burst.fill",
            description: "Skips violent and gory scenes. Requires an imported filter list — set the Filter List URL below. Dialogue text alone can't detect these scenes."
        ),
        "cf_sexNudity": SettingDescriptor(
            icon: "eye.slash.fill",
            description: "Skips scenes with sex or nudity. Requires an imported filter list — set the Filter List URL below."
        ),
        "cf_frightening": SettingDescriptor(
            icon: "theatermasks.fill",
            description: "Skips frightening or intense scenes. Requires an imported filter list — set the Filter List URL below."
        ),
        "cf_substances": SettingDescriptor(
            icon: "pills.fill",
            description: "Skips scenes featuring drug, alcohol, or tobacco use. Requires an imported filter list — set the Filter List URL below."
        ),
        "cf_sourceURL": SettingDescriptor(
            icon: "link",
            description: "Optional. Where per-title filter files live, in the open MCF (movie content filter) or EDL format. For a folder, Rivulet looks for a file named after the video file, then the IMDb id (tt0133093.edl), then the Plex rating key. An address can use {file}, {imdb}, {tmdb}, {tvdb} or {id} instead. From moviecontentfilter.com, download the EDL format with your copy's start and end times. Rivulet ships no filter data of its own."
        ),
        // MARK: Integrations
        "cat_integrations": SettingDescriptor(
            icon: "puzzlepiece.extension.fill",
            description: "Connect Seerr to request movies and shows that are not on your server, and Radarr and Sonarr to follow their downloads."
        ),
        "int_seerr": SettingDescriptor(
            icon: "tray.and.arrow.down.fill",
            description: "Seerr (Overseerr or Jellyseerr). Adds a Request button to titles that are not in your library, and shows whether a title is requested or available."
        ),
        "int_radarr": SettingDescriptor(
            icon: "film.fill",
            description: "Radarr. Shows how far along a movie's download is on its page."
        ),
        "int_sonarr": SettingDescriptor(
            icon: "tv.fill",
            description: "Sonarr. Shows how far along a show's downloads are on its page."
        ),
        "int_url": SettingDescriptor(
            icon: "link",
            description: "The address you open the service at in a browser, including http:// or https://. A path is fine, for example https://example.com/seerr."
        ),
        "int_apiKey": SettingDescriptor(
            icon: "key.fill",
            description: "Found in the service's web interface under Settings, then General. It is stored in the Keychain on this Apple TV."
        ),
        "int_headers": SettingDescriptor(
            icon: "list.bullet.rectangle",
            description: "Extra headers sent with every request, for a reverse proxy that needs its own authentication (Cloudflare Access, Authelia, basic auth)."
        ),
        "int_test": SettingDescriptor(
            icon: "checkmark.circle",
            description: "Checks the address, the API key and your custom headers together."
        ),
        "int_remove": SettingDescriptor(
            icon: "trash",
            description: "Forgets the address, the API key and the custom headers for this service."
        ),
        "int_addHeader": SettingDescriptor(
            icon: "plus.circle",
            description: "Type a header as Name: Value, for example CF-Access-Client-Id: abc123. Adding a header with a name already in the list replaces it."
        ),
        "intHeaderRow": SettingDescriptor(
            icon: "list.bullet.rectangle",
            description: "Sent with every request to this service. Select to remove it."
        ),
    ]

    // MARK: - Page Descriptors

    /// Icon and title for each settings page (shown in left panel header).
    /// `UIColor` rather than SwiftUI `Color`: the only consumer is the UIKit
    /// left panel, and vending a `Color` forced it to import SwiftUI just to
    /// call `UIColor(_:)`. These are the same system colors either way.
    static func pageInfo(for page: SettingsPage) -> (icon: String, color: UIColor) {
        switch page {
        case .root: return ("gearshape.fill", .systemGray)
        case .appearance: return ("paintbrush.fill", .systemPurple)
        case .playback: return ("play.fill", .systemBlue)
        case .music: return ("music.note", .systemPink)
        case .liveTV: return ("tv.fill", .systemGreen)
        case .servers: return ("server.rack", .systemOrange)
        case .about: return ("info.circle.fill", .systemGray)
        case .plex: return ("server.rack", .systemOrange)
        case .plexServerDetail: return ("server.rack", .systemOrange)
        case .jellyfin: return ("server.rack", .systemPurple)
        case .iptv: return ("tv.and.mediabox", .systemBlue)
        case .libraries: return ("sidebar.squares.left", .systemPurple)
        case .homeRows: return ("rectangle.grid.1x2", .systemTeal)
        case .cache: return ("internaldrive", .systemGray)
        case .appIconPicker: return ("app.badge", .systemPurple)
        case .detailRatingPicker: return ("star.leadinghalf.filled", .systemYellow)
        case .autoplayCountdownPicker: return ("forward.end.alt", .systemPurple)
        case .skipIntervalPicker: return ("forward.fill", .systemBlue)
        case .skipBackIntervalPicker: return ("backward.fill", .systemBlue)
        case .heightSpeakersPicker: return ("hifispeaker.2", .systemCyan)
        case .subtitleModePicker: return ("captions.bubble", .systemYellow)
        case .autoplayLimitPicker: return ("moon.zzz", .systemPurple)
        case .homeQualityPicker: return ("house.fill", .systemBlue)
        case .awayQualityPicker: return ("antenna.radiowaves.left.and.right", .systemBlue)
        case .audioLanguagePicker: return ("waveform", .systemCyan)
        case .subtitleLanguagePicker: return ("captions.bubble", .systemYellow)
        case .contentFilter: return ("hand.raised.fill", .systemOrange)
        case .contentFilterStrength: return ("dial.medium.fill", .systemOrange)
        case .liveTVSourceDetail: return ("tv.and.mediabox", .systemBlue)
        case .liveTVFavorites: return ("star.fill", .systemYellow)
        case .addLiveTVSource: return ("plus.circle.fill", .systemBlue)
        case .addXtream: return ("person.badge.key.fill", .systemIndigo)
        case .addOwnServer: return ("server.rack", .systemBlue)
        case .addPlaylistURL: return ("list.bullet.rectangle", .systemGreen)
        case .integrations: return ("puzzlepiece.extension.fill", .systemIndigo)
        case .seerr: return ("tray.and.arrow.down.fill", .systemIndigo)
        case .radarr: return ("film.fill", .systemYellow)
        case .sonarr: return ("tv.fill", .systemTeal)
        case .integrationHeaders: return ("list.bullet.rectangle", .systemIndigo)
        }
    }
}
