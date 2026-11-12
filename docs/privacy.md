---
id: privacy
title: Privacy Policy
---

# GeoGhost Privacy Policy

_Last updated: November 12, 2026_

GeoGhost is a personal field guide for the stickers, graffiti and murals you find on the street. It is built so that your photos and your whereabouts stay with you.

## What the app stores

- **Photos and cutouts** you choose to keep, saved on your device.
- **Location** of each piece, taken from your device's GPS at the moment you take a photo, or from the location embedded in a photo you import. Location is only read while the capture screen is open.
- **Time, device model and lens** read from the photo's metadata.
- **Notes, tags and types** you enter.

## Where processing happens

Subject detection, cutout, design matching and type suggestion all run on your device using Apple's Vision framework. No image, location or note is sent to us or to any third party. Place names are looked up with Apple's geocoding service, and maps are loaded from Apple Maps; both receive coordinates under Apple's privacy terms, not ours.

## Online features (only when you use them)

Everything above stays on your phone until you use an online feature yourself. Browsing the world map sends nothing about you.

**A guest identity, not an account.** The first time you publish, report or block, GeoGhost creates an anonymous guest identity for you: no name, email address or phone number. A random identifier and a sign-in token are kept in this iPhone's Keychain, so you stay the same guest if you reinstall the app on this phone.

**When you publish a piece.** You publish one piece at a time, after a preview of exactly what others will see. Only this is sent, and it is shown to everyone on the world map:

- the cut-out image, in two sizes, with no photo metadata;
- the rough location, rounded to about 100 m, with the area and country name;
- the day you found it (not the time) and its kind;
- the nickname you chose.

The original photo, the exact location, the time of day, your device, notes and tags are never sent.

**Reports and blocks.** If you report a post, the reason and any note you write are stored with your guest identity so the developer can review it; the author is not told who reported it, and the post disappears for you right away. If you block someone, that is stored so their posts stay hidden for you; they are not told.

**Moderation.** The first posts of new publishers, and posts reported by several people, are checked by the developer before others can see them. Each moderation decision is recorded (which post, what was decided, when).

**Publishing limits.** The number of posts you publish each day and month is counted to apply the publishing limits.

**Where it is stored.** Online data is stored with [Supabase](https://supabase.com/privacy) (database and sign-in) and [Cloudflare](https://www.cloudflare.com/privacypolicy/) (image storage and the service that receives uploads). Like any web service, they process your IP address to deliver requests. Everything is sent over encrypted connections.

**How long it is kept.** Published pieces stay until you retract them or delete your online data. When you retract a piece, its images are deleted at once and the remaining record is deleted later. If you delete your online data, reports you made are kept without your identity, so earlier moderation decisions stay explainable; moderation records are kept as well.

**Deleting it.** **Settings → Online → Delete my online data** deletes your published pieces and their images, your blocks, your nickname and your guest identity from our servers. The pieces in your collection stay on your phone and become private.

## Crash and error reports (only if you agree)

GeoGhost asks once whether you'd like to share crash and error reports, and you can change your answer anytime in **Settings → Share crash & error reports**. If you agree, the app sends a short technical report when it crashes, freezes or runs into an error:

- the app version, device model, iOS version and language/region setting;
- the crash or error itself: which part of the app it happened in and the technical call stack provided by Apple's MetricKit.

Reports never contain your photos, cutouts, locations, notes or tags, and are not linked to you: there is no account, name or device identifier in them. Until you decide, reports wait on your device; if you say no, they are deleted there and never sent.

## Feedback you send

**Settings → Send feedback** sends your message, the screenshot you choose to attach (if any) and the email address you enter (if any, so we can reply), together with the app version, device model and iOS version. It is sent only when you press Send.

## Where reports and feedback go

Reports and feedback are sent over an encrypted connection to a small service we run on Cloudflare, which holds them only until they are downloaded to the developer's own computer, then deletes them. They are used only to fix problems and improve GeoGhost, and are never sold or shared.

## What we do not do

- We never receive your original photos, exact locations, notes or tags. For a piece you choose to publish, we receive only its cutout, rough location, day and kind, as described above.
- We do not use analytics, advertising or tracking SDKs, and do not track you across apps or websites.
- We do not sell or share data with anyone.

## Purchases

GeoGhost is free and currently has no in-app purchases. If optional purchases are added later, they will be handled entirely by the App Store, and we will receive no payment details. Collecting pieces will stay free and unlimited.

## Your control

- Export everything as a ZIP from **Settings → Export everything**.
- Delete everything from **Settings → Delete all data**. Deleting the app also removes all data on the device.
- Retract a published piece from its page, or all of them from **Settings → Online**.
- Delete everything you put online from **Settings → Online → Delete my online data**.
- Camera and location permissions can be changed at any time in iOS Settings.

## Changes and contact

This policy may change when GeoGhost gains features. The current version is always at this address. Questions: open an issue at [github.com/PasserBo/GeoGhost/issues](https://github.com/PasserBo/GeoGhost/issues).
