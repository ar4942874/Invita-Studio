import 'package:flutter/widgets.dart';

/// One place in the editor the tour can point at.
///
/// `anchor` is the string a [GuideTarget] registers under; the copy lives here
/// so the tour reads as one piece of writing rather than scattered strings.
@immutable
class GuideStop {
  const GuideStop({
    required this.anchor,
    required this.title,
    required this.body,
    required this.why,
    this.icon = 'sparkle',
  });

  final String anchor;
  final String title;
  final String body;

  /// The reason this step exists, shown in small type under the body. People
  /// follow a tip they understand and ignore one they do not.
  final String why;

  /// Which glyph the progress strip shows. Kept as a string so the guide layer
  /// does not depend on Material icons.
  final String icon;
}

/// Anchors, in one place so a target and its step cannot drift apart.
abstract final class GuideAnchors {
  static const details = 'guide.details';
  static const lights = 'guide.lights';
  static const words = 'guide.words';
  static const layers = 'guide.layers';
  static const composition = 'guide.composition';
  static const format = 'guide.format';
  static const motion = 'guide.motion';
  static const export = 'guide.export';
  static const invite = 'guide.invite';
}

/// The tour, in the order a person actually finishes a card.
///
/// Nine steps is the whole editor: the words, the light, the arrangement, the
/// crop, the motion, the file and the send. Each one points at a control that
/// exists — nothing here describes a feature the app does not have.
const List<GuideStop> guideStops = [
  GuideStop(
    anchor: GuideAnchors.details,
    title: 'Start with the details',
    body:
        'Your names, the date and the venue live in Details. Type them once here '
        'and every design places them for you.',
    why: 'One edit updates the card, the thumbnail and the export.',
    icon: 'details',
  ),
  GuideStop(
    anchor: GuideAnchors.lights,
    title: 'Throw a light across the card',
    body:
        'Open Lights and choose warm glow, golden hour, candlelight or cool '
        'dawn. Slide the strength until your names sit in the light.',
    why: 'A pool of light is what makes flat artwork read as printed paper.',
    icon: 'light',
  ),
  GuideStop(
    anchor: GuideAnchors.words,
    title: 'Keep the words short',
    body:
        'Two names, one line for the occasion, then the date and place. Long '
        'copy is the only thing that ever crowds a layout.',
    why: 'Short lines survive every crop, from a phone story to a print page.',
    icon: 'text',
  ),
  GuideStop(
    anchor: GuideAnchors.layers,
    title: 'Restyle one line, not all of them',
    body:
        'Layers lists every word and photo. Select a single line to change its '
        'type, colour, spacing or position.',
    why: 'Selective styling is how a design starts looking like yours.',
    icon: 'layers',
  ),
  GuideStop(
    anchor: GuideAnchors.composition,
    title: 'Try another composition',
    body:
        'Templates offers the same words in different arrangements. Switching '
        'keeps your text, photos and light.',
    why: 'Arrangement changes the mood more than any other setting.',
    icon: 'grid',
  ),
  GuideStop(
    anchor: GuideAnchors.format,
    title: 'Check the story crop',
    body:
        'Story is 9:16, where most invitations get shared; Square is 1:1. The '
        'same design is re-fitted, never redrawn.',
    why: 'A card that fits the screen it lands on gets opened.',
    icon: 'crop',
  ),
  GuideStop(
    anchor: GuideAnchors.motion,
    title: 'Add a little motion',
    body:
        'Switch to Video and the words can arrive one by one over your own '
        'clip or the artwork itself.',
    why: 'Motion is optional — export the still image any time.',
    icon: 'motion',
  ),
  GuideStop(
    anchor: GuideAnchors.export,
    title: 'Export the invitation',
    body:
        'One tap gives a PNG or JPEG at 1× or 2×, or a print-ready PDF. The '
        'file carries the light you chose.',
    why: 'Nothing leaves this device until you export it.',
    icon: 'export',
  ),
  GuideStop(
    anchor: GuideAnchors.invite,
    title: 'Then send it',
    body:
        'Open the ••• menu and choose Invitation actions to copy a message, add '
        'the date to a calendar, show the RSVP code or share the file.',
    why: 'The invitation is finished when it is in someone else’s hands.',
    icon: 'send',
  ),
];
