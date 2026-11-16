import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/device/device_name.dart';
import '../../../core/format/dates.dart';
import '../../../core/layout/content_width.dart';
import '../../../core/layout/window_class.dart';
import '../../../core/motion/animated_rows.dart';
import '../../../core/motion/haptics.dart';
import '../../../core/motion/pop_in.dart';
import '../../../core/motion/shared_axis_switcher.dart';
import '../../../core/motion/stagger.dart';
import '../../../core/motion/step_segments.dart';
import '../../../core/motion/value_switcher.dart';
import '../../../core/theme/regalos_motion.dart';
import '../../../core/sync/model.dart';
import '../../../core/theme/regalos_tokens.dart';
import '../../../core/widgets/filter_pill.dart';
import '../../../core/widgets/person_avatar.dart';
import '../../../core/widgets/regalos_snack_bar.dart';
import '../../../core/widgets/stroke_icon.dart';
import '../../../core/widgets/tag_label.dart';
import '../../../l10n/app_localizations.dart';
import '../../family/application/family_controller.dart';
import '../../family/application/gift_logic.dart';
import '../../family/application/occasion_names.dart';
import '../../family/presentation/family_texts.dart';
import '../../family/presentation/giver_sheet.dart';
import '../../family/presentation/occasion_sheet.dart';
import '../../family/presentation/person_sheet.dart';
import '../../lock/application/lock_controller.dart';
import '../../lock/presentation/pin_setup_screen.dart';
import '../../recovery/presentation/recovery_parts.dart';
import '../../sync/application/recovery_providers.dart';
import '../../tour/application/tour_state.dart';

/// Lo que se ha elegido en el primer uso hasta que se guarda todo junto.
class OnboardingDraft {
  /// Crea el borrador.
  OnboardingDraft({
    this.deviceName = '',
    List<Recipient>? people,
    List<Giver>? givers,
    Set<OccasionKind>? kinds,
    List<Occasion>? extraOccasions,
  }) : people = people ?? <Recipient>[],
       givers = givers ?? <Giver>[],
       kinds = kinds ?? <OccasionKind>{},
       extraOccasions = extraOccasions ?? <Occasion>[];

  /// Nombre de este móvil para el otro.
  String deviceName;

  /// Las personas a las que se regala.
  final List<Recipient> people;

  /// Quien regala.
  final List<Giver> givers;

  /// Las ocasiones fijas elegidas (Tió, Papá Noel, Reyes).
  final Set<OccasionKind> kinds;

  /// Otras ocasiones añadidas a mano.
  final List<Occasion> extraOccasions;
}

/// El código de región con que se proponen las ocasiones fijas.
///
/// Catalán es Cataluña; en otro idioma, el país del móvil.
String regionFor(Locale appLocale, Locale platformLocale) {
  if (appLocale.languageCode == 'ca' || platformLocale.languageCode == 'ca') {
    return 'ES-CT';
  }
  return platformLocale.countryCode ?? '';
}

/// Guarda todo lo elegido en el primer uso: crea la familia, las personas,
/// quien regala y las ocasiones.
Future<void> commitOnboarding(
  FamilyController family,
  OnboardingDraft draft, {
  required String deviceName,
  required String region,
}) async {
  // Todo de una vez: la app sale del primer uso en cuanto hay familia, y no
  // debe ver Personas a medio rellenar.
  await family.createFamilyWith(
    deviceName: deviceName,
    recipients: draft.people,
    givers: draft.givers,
    occasions: draft.extraOccasions,
    region: region,
    kinds: draft.kinds,
  );
}

enum _Step { welcome, people, givers, occasions, pin }

/// El primer uso: bienvenida, personas, quién regala, ocasiones y PIN.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// Crea la pantalla. [region] solo se da en las pruebas.
  const OnboardingScreen({super.key, this.region});

  /// Región para proponer las ocasiones; por defecto, la del móvil.
  final String? region;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final OnboardingDraft _draft = OnboardingDraft();
  final TextEditingController _deviceName = TextEditingController();
  _Step _step = _Step.welcome;
  bool _busy = false;
  bool _failed = false;
  bool _seeded = false;

  /// La entrada de la bienvenida se ve una vez: al volver atrás no se repite.
  bool _welcomeSeen = false;
  late String _region;

  @override
  void dispose() {
    _deviceName.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) {
      return;
    }
    _seeded = true;
    final l10n = AppLocalizations.of(context);
    _region =
        widget.region ??
        regionFor(
          Localizations.localeOf(context),
          WidgetsBinding.instance.platformDispatcher.locale,
        );
    _draft.kinds.addAll(suggestedOccasionKinds(_region));
    _draft.givers.add(
      Giver(
        id: newId(),
        name: l10n.giverUs,
        colorIndex: 0,
        householdPays: true,
        archived: false,
      ),
    );
  }

  int get _index => _step.index;

  void _go(_Step step) => setState(() {
    if (_step == _Step.welcome) {
      _welcomeSeen = true;
    }
    _step = step;
  });

  void _back() {
    if (_index > 0) {
      _go(_Step.values[_index - 1]);
    }
  }

  void _next() {
    if (_index < _Step.values.length - 1) {
      _go(_Step.values[_index + 1]);
    }
  }

  Future<void> _finish({required bool withPin}) async {
    if (_busy) {
      return;
    }
    final navigator = Navigator.of(context, rootNavigator: true);
    final router = GoRouter.of(context);
    final lock = ref.read(lockControllerProvider.notifier);
    final family = ref.read(familyControllerProvider.notifier);
    // La primera vez, al terminar se abre la guía «Cómo funciona»; las
    // siguientes (tras «Borrar todo» se vuelve a ver) va directo a Personas.
    // Se arma antes de guardar la familia: el router decide en cuanto aparece.
    final tour = ref.read(tourAfterWelcomeProvider);
    final tourPending = !ref.read(tourSeenProvider).seen;
    tour.pending = tourPending;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      if (withPin) {
        final chosen = await navigator.push<bool>(
          MaterialPageRoute<bool>(
            builder: (pinContext) => PinSetupScreen(
              onPinChosen: (pin) async {
                await lock.setPin(pin);
                if (pinContext.mounted) {
                  Navigator.of(pinContext).pop(true);
                }
              },
              onSkip: () => Navigator.of(pinContext).pop(false),
            ),
          ),
        );
        if (chosen != true) {
          tour.pending = false;
          if (mounted) {
            setState(() => _busy = false);
          }
          return;
        }
      } else {
        await lock.skipSetup();
      }
      await commitOnboarding(
        family,
        _draft,
        deviceName: deviceNameToSend(ref, _deviceName.text),
        region: _region,
      );
      router.go(tourPending ? AppRoutes.tour : '/people');
    } on Object catch (error) {
      tour.pending = false;
      if (error is RecoveryApplicationException &&
          error.code == 'restore_pending') {
        // Hay una recuperación a medias: se vuelve a la bienvenida, donde se
        // reanuda o se cancela.
        unawaited(ref.read(recoveryApplicationProvider.notifier).refresh());
        if (mounted) {
          setState(() {
            _busy = false;
            _failed = false;
            _go(_Step.welcome);
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final total = _Step.values.length;
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _back();
        }
      },
      child: Scaffold(
        body: SafeArea(
          // En tablet, cabecera, pasos y botones van en una columna de 520
          // centrada (la guía de diseño para tablet, §3); en el móvil cabe
          // entera y `ContentWidth` no hace nada.
          child: Column(
            children: [
              ContentWidth(
                maxWidth: RegalosLayout.onboardingColumn,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: _index == 0
                            ? null
                            : Semantics(
                                button: true,
                                label: l10n.actionBack,
                                excludeSemantics: true,
                                onTap: _busy ? null : _back,
                                child: InkResponse(
                                  onTap: _busy ? null : _back,
                                  child: Center(
                                    child: StrokeIcon(
                                      AppIcons.back,
                                      color: t.text,
                                      strokeWidth: 1.9,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.onboardingStepOf(_index + 1, total),
                              style: t.styles.meta,
                            ),
                            const SizedBox(height: 4),
                            StepSegments(
                              count: total,
                              filled: _index + 1,
                              semanticLabel: l10n.onboardingStepOf(
                                _index + 1,
                                total,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                // La columna va dentro de la vista que se desplaza: arrastrar
                // por los márgenes también desplaza.
                child: SingleChildScrollView(
                  child: ContentWidth(
                    maxWidth: RegalosLayout.onboardingColumn,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      // Entre pasos, eje compartido horizontal (momento M).
                      child: SharedAxisSwitcher(
                        index: _index,
                        child: switch (_step) {
                          _Step.welcome => _WelcomeStep(
                            animate: !_welcomeSeen,
                            nameController: _deviceName,
                            onStart: _next,
                          ),
                          _Step.people => _PeopleStep(
                            draft: _draft,
                            onChanged: () => setState(() {}),
                          ),
                          _Step.givers => _GiversStep(
                            draft: _draft,
                            onChanged: () => setState(() {}),
                          ),
                          _Step.occasions => _OccasionsStep(
                            draft: _draft,
                            onChanged: () => setState(() {}),
                          ),
                          _Step.pin => _PinStep(
                            busy: _busy,
                            failed: _failed,
                            onCreate: () => _finish(withPin: true),
                            onSkip: () => _finish(withPin: false),
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              ),
              // El pie con «Siguiente» sube al salir de la bienvenida y se va
              // en el último paso: la altura cambia con `snap` y el contenido
              // se funde (150 ms), no aparece de golpe.
              _AnimatedFooter(
                show: _step != _Step.welcome && _step != _Step.pin,
                child: Container(
                  padding: const EdgeInsets.only(top: 8, bottom: 12),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.separator)),
                  ),
                  child: ContentWidth(
                    maxWidth: RegalosLayout.onboardingColumn,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_step == _Step.people && _draft.people.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                l10n.obPeopleNeedOne,
                                style: t.styles.meta,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          FilledButton(
                            onPressed:
                                _step == _Step.people && _draft.people.isEmpty
                                ? null
                                : _next,
                            child: Text(l10n.actionNext),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El pie de los pasos intermedios: entra y sale con `snap` (altura) y un
/// fundido; con «Reducir movimiento», solo el fundido de 150 ms.
class _AnimatedFooter extends StatelessWidget {
  const _AnimatedFooter({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = RegalosMotion.of(context).reduce;
    final switcher = AnimatedSwitcher(
      duration: RegalosMotion.fade,
      // Al ocultarse, el pie desaparece a la vez que se pliega su altura (no
      // espera a un fundido); con «Reducir movimiento», fundido de 150 ms.
      reverseDuration: reduce ? RegalosMotion.fade : Duration.zero,
      child: show
          ? KeyedSubtree(key: const ValueKey<bool>(true), child: child)
          : const SizedBox(key: ValueKey<bool>(false), width: double.infinity),
    );
    if (reduce) {
      return switcher;
    }
    return AnimatedSize(
      // Sube con `snap` y se pliega con `fold`, sin rebote al irse.
      duration: show ? RegalosSprings.snapDuration : RegalosCurves.foldDuration,
      curve: show ? RegalosCurves.snap : RegalosCurves.fold,
      alignment: Alignment.bottomCenter,
      child: switcher,
    );
  }
}

/// Cambia de alto con `snap` cuando su contenido crece o se encoge; con
/// «Reducir movimiento» no estira (solo cuenta el fundido del contenido).
class _FoldIn extends StatelessWidget {
  const _FoldIn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (RegalosMotion.of(context).reduce) {
      return child;
    }
    return AnimatedSize(
      duration: RegalosSprings.snapDuration,
      curve: RegalosCurves.snap,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: t.styles.screenTitle),
        ),
        const SizedBox(height: 8),
        Text(body, style: t.styles.body.copyWith(color: t.textSecondary)),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _WelcomeStep extends ConsumerWidget {
  const _WelcomeStep({
    required this.nameController,
    required this.onStart,
    required this.animate,
  });

  /// Si la entrada se anima (solo la primera vez que se ve).
  final bool animate;

  final TextEditingController nameController;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    // Con una recuperación a medias no se crea ni se une a otra familia: se
    // reanuda o se cancela antes.
    final pending = ref.watch(
      recoveryStatusProvider.select((status) => status.hasPendingRestore),
    );
    // La primera impresión: el icono rebota, y el título, el texto, el campo y
    // el botón suben uno tras otro (24 ms entre ellos), una vez.
    return StaggerScope(
      animate: animate,
      maxItems: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: PopIn(
              from: 0.9,
              animate: animate,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.soft,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 80,
                  child: Center(
                    child: StrokeIcon(
                      AppIcons.family,
                      size: 40,
                      color: t.ink,
                      strokeWidth: 1.7,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          StaggerItem(
            index: 0,
            child: Semantics(
              header: true,
              child: Text(
                l10n.obWelcomeTitle,
                style: t.styles.screenTitle.copyWith(
                  fontSize: 28,
                  height: 34 / 28,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 12),
          StaggerItem(
            index: 1,
            child: Column(
              children: [
                Text(
                  l10n.obWelcomeBody,
                  style: t.styles.rowTitle.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.obWelcomePrivacy,
                  style: t.styles.body.copyWith(color: t.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          StaggerItem(
            index: 2,
            child: DeviceNameField(controller: nameController),
          ),
          const SizedBox(height: 20),
          if (pending) ...[
            const SizedBox(height: 4),
            const _PendingRestoreCard(),
            const SizedBox(height: 16),
          ],
          StaggerItem(
            index: 3,
            child: FilledButton(
              onPressed: pending ? null : onStart,
              child: Text(l10n.obStart),
            ),
          ),
          const SizedBox(height: 8),
          StaggerItem(
            index: 4,
            child: Column(
              children: [
                Text(
                  l10n.obHaveListTitle,
                  style: t.styles.meta,
                  textAlign: TextAlign.center,
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: pending
                          ? null
                          : () => context.push(
                              AppRoutes.join,
                              extra: deviceNameToSend(ref, nameController.text),
                            ),
                      child: Text(l10n.shareJoinTitle),
                    ),
                    TextButton(
                      onPressed: pending
                          ? null
                          : () => context.push(
                              AppRoutes.joinLink,
                              extra: deviceNameToSend(ref, nameController.text),
                            ),
                      child: Text(l10n.joinInviteRowTitle),
                    ),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.recover),
                      child: Text(l10n.obHaveRecoveryCode),
                    ),
                    TextButton(
                      onPressed: () => context.push(AppRoutes.recoverFile),
                      child: Text(l10n.obRecoverWithFile),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleStep extends StatefulWidget {
  const _PeopleStep({required this.draft, required this.onChanged});

  final OnboardingDraft draft;
  final VoidCallback onChanged;

  @override
  State<_PeopleStep> createState() => _PeopleStepState();
}

class _PeopleStepState extends State<_PeopleStep> {
  // Las personas que ya estaban al llegar a este paso no rebotan: solo la que
  // se añade ahora.
  late final Set<String> _present = {for (final p in widget.draft.people) p.id};

  OnboardingDraft get draft => widget.draft;
  VoidCallback get onChanged => widget.onChanged;

  Future<void> _edit(BuildContext context, {Recipient? person}) async {
    final result = await showPersonSheet(
      context,
      initial: person,
      defaultColorIndex: draft.people.length,
    );
    if (result == null) {
      return;
    }
    final index = draft.people.indexWhere((p) => p.id == result.id);
    if (index >= 0) {
      draft.people[index] = result;
    } else {
      draft.people.add(result);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(title: l10n.obPeopleTitle, body: l10n.obPeopleBody),
        // La persona añadida se despliega con `snap` y su avatar rebota desde
        // 0,8 a los 60 ms; la quitada se pliega.
        AnimatedRows(
          rows: [
            for (final person in draft.people)
              AnimatedRowItem(
                id: person.id,
                child: _DraftRow(
                  leading: PopIn(
                    animate: !_present.contains(person.id),
                    from: 0.8,
                    delay: const Duration(milliseconds: 60),
                    child: PersonAvatar(
                      name: person.name,
                      colorIndex: person.colorIndex,
                    ),
                  ),
                  title: person.name,
                  subtitle: [
                    ?person.relation,
                    if (person.birthMonth != null && person.birthDay != null)
                      shortDayMonth(
                        person.birthMonth!,
                        person.birthDay!,
                        l10n.localeName,
                      ),
                  ].join(' · '),
                  editLabel: l10n.actionEdit,
                  removeLabel: l10n.obRemove(person.name),
                  onEdit: () => _edit(context, person: person),
                  onRemove: () {
                    draft.people.remove(person);
                    onChanged();
                  },
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => _edit(context),
          icon: StrokeIcon(
            AppIcons.plus,
            size: 18,
            color: t.onFill,
            strokeWidth: 2.2,
          ),
          label: Text(l10n.obPeopleAdd),
        ),
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.title,
    required this.editLabel,
    required this.removeLabel,
    required this.onEdit,
    required this.onRemove,
    this.leading,
    this.subtitle = '',
    this.tag,
  });

  final Widget? leading;
  final String title;
  final String subtitle;
  final String? tag;
  final String editLabel;
  final String removeLabel;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = RegalosTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.separator)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Semantics(
              container: true,
              button: true,
              label: subtitle.isEmpty ? title : '$title. $subtitle',
              excludeSemantics: true,
              onTap: onEdit,
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        children: [
                          Text(title, style: t.styles.rowTitle),
                          if (tag != null) TagLabel(tag!),
                        ],
                      ),
                      if (subtitle.isNotEmpty)
                        Text(subtitle, style: t.styles.meta),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Semantics(
              button: true,
              label: removeLabel,
              excludeSemantics: true,
              onTap: onRemove,
              child: SizedBox.square(
                dimension: 44,
                child: InkResponse(
                  onTap: onRemove,
                  child: Center(
                    child: StrokeIcon(
                      AppIcons.close,
                      size: 20,
                      color: t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GiversStep extends StatelessWidget {
  const _GiversStep({required this.draft, required this.onChanged});

  final OnboardingDraft draft;
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context, {Giver? giver}) async {
    final result = await showGiverSheet(
      context,
      initial: giver,
      defaultColorIndex: draft.givers.length,
    );
    if (result == null) {
      return;
    }
    final index = draft.givers.indexWhere((g) => g.id == result.id);
    if (index >= 0) {
      draft.givers[index] = result;
    } else {
      draft.givers.add(result);
    }
    onChanged();
  }

  void _quickAdd(String name) {
    if (draft.givers.any((g) => g.name == name)) {
      return;
    }
    draft.givers.add(
      Giver(
        id: newId(),
        name: name,
        colorIndex: draft.givers.length,
        householdPays: false,
        archived: false,
      ),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(title: l10n.obGiversTitle, body: l10n.obGiversBody),
        AnimatedRows(
          rows: [
            for (final giver in draft.givers)
              AnimatedRowItem(
                id: giver.id,
                child: _DraftRow(
                  leading: SizedBox.square(
                    dimension: 40,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.giver(giver.colorIndex),
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 14),
                      ),
                    ),
                  ),
                  title: giverDisplayName(l10n, giver.name),
                  tag: giver.householdPays ? l10n.giverHouseholdPays : null,
                  editLabel: l10n.actionEdit,
                  removeLabel: l10n.obRemove(
                    giverDisplayName(l10n, giver.name),
                  ),
                  onEdit: () => _edit(context, giver: giver),
                  onRemove: draft.givers.length > 1
                      ? () {
                          draft.givers.remove(giver);
                          onChanged();
                        }
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(l10n.obGiversSuggestions, style: t.styles.label),
        Wrap(
          spacing: 8,
          children: [
            for (final name in [
              l10n.obGiverGrandparents,
              l10n.obGiverUncles,
              l10n.obGiverFriends,
            ])
              if (!draft.givers.any((g) => g.name == name))
                FilterPill(
                  label: name,
                  icon: AppIcons.plus,
                  semanticLabel: l10n.obAddNamed(name),
                  onTap: () => _quickAdd(name),
                ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _edit(context),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 48),
            foregroundColor: t.ink,
            side: BorderSide(color: t.controlBorder),
          ),
          icon: StrokeIcon(
            AppIcons.plus,
            size: 18,
            color: t.ink,
            strokeWidth: 2.2,
          ),
          label: Text(l10n.giverNew),
        ),
      ],
    );
  }
}

class _OccasionsStep extends StatelessWidget {
  const _OccasionsStep({required this.draft, required this.onChanged});

  final OnboardingDraft draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    final locale = l10n.localeName;
    final fixed = <(OccasionKind, String, int, int)>[
      (OccasionKind.tio, l10n.occasionNameTio, 12, 24),
      (OccasionKind.santa, l10n.occasionNameSanta, 12, 25),
      (OccasionKind.kings, l10n.occasionNameKings, 1, 6),
    ];
    final birthdays = [
      for (final p in draft.people)
        if (p.birthMonth != null && p.birthDay != null) p,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(title: l10n.obOccasionsTitle, body: l10n.obOccasionsBody),
        for (final (kind, name, month, day) in fixed)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: draft.kinds.contains(kind),
            title: Text(name, style: t.styles.rowTitle),
            subtitle: Text(
              shortDayMonth(month, day, locale),
              style: t.styles.meta,
            ),
            onChanged: (checked) {
              context.haptics.selection();
              if (checked ?? false) {
                draft.kinds.add(kind);
              } else {
                draft.kinds.remove(kind);
              }
              onChanged();
            },
          ),
        const SizedBox(height: 8),
        Text(l10n.obBirthdaysSection, style: t.styles.sectionTitle),
        const SizedBox(height: 4),
        if (birthdays.isEmpty)
          Text(l10n.obNoBirthdays, style: t.styles.meta)
        else
          for (final p in birthdays)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  StrokeIcon(
                    AppIcons.check,
                    size: 18,
                    color: t.ink,
                    strokeWidth: 2.4,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${l10n.occasionBirthdayOf(p.name)} · '
                      '${shortDayMonth(p.birthMonth!, p.birthDay!, locale)}',
                      style: t.styles.body,
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Text(l10n.obOtherOccasions, style: t.styles.sectionTitle),
        for (final o in draft.extraOccasions)
          _DraftRow(
            title: o.name,
            subtitle: shortDayMonth(o.month, o.day, locale),
            editLabel: l10n.actionEdit,
            removeLabel: l10n.obRemove(o.name),
            onEdit: () async {
              final result = await showOccasionSheet(context, initial: o);
              if (result != null) {
                final index = draft.extraOccasions.indexWhere(
                  (x) => x.id == result.id,
                );
                draft.extraOccasions[index] = result;
                onChanged();
              }
            },
            onRemove: () {
              draft.extraOccasions.remove(o);
              onChanged();
            },
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            final result = await showOccasionSheet(context);
            if (result != null) {
              draft.extraOccasions.add(result);
              onChanged();
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(44, 48),
            foregroundColor: t.ink,
            side: BorderSide(color: t.controlBorder),
          ),
          icon: StrokeIcon(
            AppIcons.plus,
            size: 18,
            color: t.ink,
            strokeWidth: 2.2,
          ),
          label: Text(l10n.obAddOccasion),
        ),
      ],
    );
  }
}

class _PinStep extends StatelessWidget {
  const _PinStep({
    required this.busy,
    required this.failed,
    required this.onCreate,
    required this.onSkip,
  });

  final bool busy;
  final bool failed;
  final VoidCallback onCreate;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = RegalosTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 24),
        Center(
          child: DecoratedBox(
            decoration: BoxDecoration(color: t.soft, shape: BoxShape.circle),
            child: SizedBox.square(
              dimension: 80,
              child: Center(
                child: StrokeIcon(
                  AppIcons.lock,
                  size: 38,
                  color: t.ink,
                  strokeWidth: 1.7,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Semantics(
          header: true,
          child: Text(
            l10n.obPinTitle,
            style: t.styles.screenTitle,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.obPinBody,
          style: t.styles.rowTitle.copyWith(fontWeight: FontWeight.w400),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // El aviso de error se despliega con `snap` y se funde; no empuja el
        // botón de golpe.
        _FoldIn(
          child: ValueSwitcher(
            alignment: Alignment.topCenter,
            child: failed
                ? Padding(
                    key: const ValueKey<bool>(true),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.obSaveError,
                        style: t.styles.meta,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : const SizedBox(
                    key: ValueKey<bool>(false),
                    width: double.infinity,
                  ),
          ),
        ),
        FilledButton(
          onPressed: busy ? null : onCreate,
          child: ValueSwitcher(
            alignment: Alignment.center,
            dy: 3,
            child: Text(
              busy ? l10n.obFinishing : l10n.obPinCreate,
              key: ValueKey<bool>(busy),
            ),
          ),
        ),
        TextButton(onPressed: busy ? null : onSkip, child: Text(l10n.pinSkip)),
      ],
    );
  }
}

/// El aviso de la bienvenida con una recuperación a medias: Reanudar la abre
/// y Cancelar la descarta (con su pregunta).
class _PendingRestoreCard extends ConsumerWidget {
  const _PendingRestoreCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return RecoveryCard(
      title: l10n.recoverPendingTitle,
      body: l10n.recoverPendingBody,
      extra: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            onPressed: () => context.push(AppRoutes.recover),
            child: Text(l10n.recoverResume),
          ),
          TextButton(
            onPressed: () async {
              final claimSent = ref.read(recoveryStatusProvider).claimSent;
              final ok = await confirmAbandonRecovery(
                context,
                claimSent: claimSent,
              );
              if (!ok || !context.mounted) {
                return;
              }
              try {
                await ref.read(recoveryApplicationProvider.notifier).abandon();
              } on Object {
                if (context.mounted) {
                  showRegalosSnackBar(
                    context,
                    SnackBar(content: Text(l10n.recoverAbandonFailed)),
                  );
                }
              }
            },
            child: Text(l10n.recoverAbandon),
          ),
        ],
      ),
    );
  }
}
