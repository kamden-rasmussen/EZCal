# EZCal Privacy Policy

_Last updated: October 16, 2026_

EZCal is a free, open-source calendar app for macOS and iOS. This policy explains what happens to your data when you use it. The short version: **EZCal has no servers and no accounts. Your data goes between your device and the services you connect (Google, Zoom, Apple Calendar), and nowhere else.**

The developer of EZCal (Kamden Rasmussen, "we") does not receive, collect, store, sell, or share your personal data.

## What EZCal accesses

Only when you choose to connect them:

- **Google account**: your email address and basic profile (to show which account is signed in), your Google Calendar events and calendars (read and write, so you can create, edit, delete and RSVP), and your organization's directory contacts (read-only, to suggest coworkers and check their availability).
- **Zoom account**: permission to create, update and delete Zoom meetings on your behalf (`meeting:write:meeting`, `meeting:update:meeting`, `meeting:delete:meeting`). EZCal does not read your existing meetings, recordings, chats, or contacts.
- **Apple Calendar / Reminders**: calendars and reminders already on your Mac or iPhone, through Apple's system permission prompt.
- **Calendar subscriptions**: any `.ics` / `webcal://` URL you paste in. EZCal downloads it from that address.

## Where your data is stored

- Everything is stored **on your device**. Sign-in tokens (Google and Zoom) are kept in the macOS/iOS **Keychain**. Preferences and cached calendar data are stored locally on your device.
- EZCal does not send your calendar data, tokens, or meeting details to the developer or to any third party other than the service they belong to (Google, Zoom).
- Your requests go directly from your device to Google's and Zoom's APIs, and are governed by their privacy policies:
  - Google: <https://policies.google.com/privacy>
  - Zoom: <https://explore.zoom.us/en/privacy/>

## What we do not do

- No analytics, tracking, advertising, or crash-reporting services.
- No selling, renting, or sharing of personal data.
- No use of your data to train AI or machine-learning models.
- No use of Google or Zoom data for anything except the features you see in the app.

EZCal's use of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.

## Network requests EZCal makes

Besides Google, Zoom, and any calendar subscription URLs you add, EZCal checks GitHub's public releases API (`api.github.com`) to see whether an update is available. This request contains no personal data.

## Optional local agent access (MCP)

If you turn on **Settings → Agents**, EZCal runs a server that listens only on your own machine (`127.0.0.1`) and requires an access token kept in your Keychain. It is off by default. When on, AI agents you configure on your Mac can read or change your calendar through EZCal. What those agents do with the data is governed by the agent's own provider; EZCal itself does not send the data anywhere. A **Read-only** switch limits agents to viewing.

## Your rights and choices

Because we hold none of your data, there is nothing for us to access, export, correct, or delete on our side. You control your data directly:

- **Access, correct, or delete your calendar data**: do it in Google Calendar, Zoom, or Apple Calendar. EZCal shows and edits the same data.
- **Disconnect an account**: use **Settings** in EZCal to sign out of Google or disconnect Zoom. This removes the stored tokens from your Keychain.
- **Revoke access at the source**:
  - Google: <https://myaccount.google.com/permissions>
  - Zoom: Zoom App Marketplace → Manage → Installed Apps → EZCal → Uninstall
- **Delete all local data**: delete the app and its data (on macOS, remove EZCal and its preferences; Keychain entries are removed when you disconnect accounts).

Depending on where you live (for example under GDPR or CCPA), you may have rights to access, correct, delete, port, or object to the processing of your personal data. Since we don't collect your personal data, these rights are exercised through the controls above and with Google and Zoom directly. If you have a question or want to make a request, contact us using the details below and we'll respond promptly.

## Children

EZCal is not directed to children under 13, and we do not knowingly collect any data from anyone.

## Changes

If this policy changes, the updated version will be posted here with a new "Last updated" date. Because EZCal is open source, every change is also visible in the repository's history.

## Contact

Questions or requests: open an issue at <https://github.com/kamden-rasmussen/EZCal/issues>.

Source code: <https://github.com/kamden-rasmussen/EZCal>
