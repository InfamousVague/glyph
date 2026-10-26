/// The Lovart plugin's manifest and its host (docs/LOVART.md). The port's own: the web app has no Lovart.
///
/// Lovart (lovart.ai) is a design agent that makes images. It has no published API; what it offers agents is a skill
/// for OpenClaw and its kin (github.com/lovartai/lovart-skill), a small Python client over "Lovart Agent OpenAPI" at
/// lgw.lovart.ai, signed with an access key and a secret key the person makes in Lovart. This plugin calls the same
/// API itself (client.dart), with the person's own keys, kept in the device's secure store under [accessKeySecret] and
/// [secretKeySecret], and following the account sealed (lib/sync/connections.dart).
///
/// `lovart.ai` covers both hosts it reaches: `lgw.lovart.ai`, the API, and `assets-persist.lovart.ai`, where the
/// images it makes are fetched from.
library;

import '../host.dart';
import '../types.dart';

/// The names the keys are kept under in the secure store.
const String accessKeySecret = 'glyph-lovart-access-key';
const String secretKeySecret = 'glyph-lovart-secret-key';

/// The Lovart project the images are made in, made once and checked again before each use (client.dart).
const String projectKey = 'glyph-lovart-project';

/// Whether design meetings get inspiration images once written up (meetings.dart), on this device.
const String meetingsKey = 'glyph-lovart-meetings';

/// The meetings already given inspiration, by note id, so a summary made again makes none.
const String meetingsDoneKey = 'glyph-lovart-meetings-done';

/// Whether notes are given header banners by themselves as they are left (banners.dart), on this device.
const String bannersKey = 'glyph-lovart-banners';

/// The notes already given one, by id, so a banner taken off is not made again.
const String bannersDoneKey = 'glyph-lovart-banners-done';

/// The run over the recent notes as it stands (banner_run.dart): the notes left, the ones being made, and how many
/// were made, so a run the app was closed under goes on at the next launch.
const String bannerRunKey = 'glyph-lovart-banner-run';

const PluginManifest manifest = PluginManifest(
  id: 'lovart',
  name: 'Lovart',
  description: 'Make images from your notes with Lovart’s design agent: inspiration for design meetings, and images where you write {image: …}.',
  version: '1.0.0',
  author: 'Ghost.md',
  category: PluginCategory.ai,
  tagline: 'Images from your notes, by Lovart’s design agent',
  adds: [
    'Make images, on a note with {image: a prompt} in it: each becomes a picture',
    'Inspiration images, on any note: a moodboard of four under ## Inspiration',
    'Inspiration for design meetings, once each is written up, where you switch it on',
    'Header images for notes, in the ghost’s dotwork, made as you leave a note',
  ],
  // Off until added: it sends a note's words to Lovart and spends the person's Lovart credits.
  standard: false,
  permissions: [
    PluginPermission(Permission.notes, 'Writes the images it makes into your notes.'),
    PluginPermission(Permission.network, 'Asks Lovart for images, with your own Lovart keys: only the prompt, the note you ask inspiration for, or a note’s title and opening for its header image, goes there.'),
  ],
  hosts: ['lovart.ai'],
  storage: [projectKey, meetingsKey, meetingsDoneKey, bannersKey, bannersDoneKey, bannerRunKey],
  secrets: [accessKeySecret, secretKeySecret],
);

/// The plugin's one way onto the phone (lib/plugins/host.dart): it reads the ground when it is used, so a test's
/// own ground needs no host of its own.
final PluginHost host = createHost(manifest);
