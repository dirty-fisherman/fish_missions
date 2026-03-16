import {
  Accordion,
  ActionIcon,
  Button,
  Group,
  NativeSelect,
  NumberInput,
  Select,
  Stack,
  Switch,
  Text,
  TextInput,
} from '@mantine/core';
import { fetchNui } from '../../utils/fetchNui';
import { useAdminStore } from '../../stores/adminStore';

interface TypeParamsEditorProps {
  errors: Record<string, string>;
}

const round2 = (v: number) => Math.round(v * 100) / 100;

const GTA_WEAPONS = [
  'WEAPON_PISTOL', 'WEAPON_COMBATPISTOL', 'WEAPON_APPISTOL', 'WEAPON_HEAVYPISTOL',
  'WEAPON_VINTAGEPISTOL', 'WEAPON_REVOLVER', 'WEAPON_DOUBLEACTION',
  'WEAPON_MICROSMG', 'WEAPON_SMG', 'WEAPON_SMGMK2', 'WEAPON_ASSAULTSMG', 'WEAPON_COMBATPDW',
  'WEAPON_MACHINEPISTOL', 'WEAPON_MINISMG',
  'WEAPON_ASSAULTRIFLE', 'WEAPON_ASSAULTRIFLEMK2', 'WEAPON_CARBINERIFLE', 'WEAPON_CARBINERIFLEMK2',
  'WEAPON_ADVANCEDRIFLE', 'WEAPON_SPECIALCARBINE', 'WEAPON_SPECIALCARBINEREMK2', 'WEAPON_BULLPUPRIFLE',
  'WEAPON_COMPACTRIFLE', 'WEAPON_MILITARYRIFLE', 'WEAPON_HEAVYRIFLE',
  'WEAPON_MG', 'WEAPON_COMBATMG', 'WEAPON_COMBATMGMK2', 'WEAPON_GUSENBERG',
  'WEAPON_PUMPSHOTGUN', 'WEAPON_PUMPSHOTGUNMK2', 'WEAPON_SAWEDOFFSHOTGUN', 'WEAPON_ASSAULTSHOTGUN',
  'WEAPON_BULLPUPSHOTGUN', 'WEAPON_MUSKET', 'WEAPON_HEAVYSHOTGUN', 'WEAPON_DBSHOTGUN',
  'WEAPON_SNIPERRIFLE', 'WEAPON_HEAVYSNIPER', 'WEAPON_HEAVYSNIPERMK2', 'WEAPON_MARKSMANRIFLE',
  'WEAPON_KNIFE', 'WEAPON_NIGHTSTICK', 'WEAPON_HAMMER', 'WEAPON_BAT', 'WEAPON_CROWBAR',
  'WEAPON_GOLFCLUB', 'WEAPON_KNUCKLE', 'WEAPON_MACHETE', 'WEAPON_HATCHET', 'WEAPON_SWITCHBLADE',
  'WEAPON_BOTTLE', 'WEAPON_DAGGER', 'WEAPON_BATTLEAXE', 'WEAPON_POOLCUE',
].map((w) => ({ value: w, label: w }));

export function TypeParamsEditor({ errors }: TypeParamsEditorProps) {
  const { editing, updateParams, setCapturingField } = useAdminStore();

  if (!editing) return null;

  const params = editing.params || {};

  const startPlacement = async (
    field: string,
    model: string,
    entityType: 'ped' | 'prop',
    contextEntities?: Array<{ model: string; coords: { x: number; y: number; z: number }; heading?: number; entityType: 'ped' | 'prop' }>,
  ) => {
    if (!model) return;
    setCapturingField(field);
    const result = await fetchNui<{ ok: boolean; reason?: string }>('admin:startPlacement', { field, model, entityType, contextEntities });
    if (result && !result.ok) {
      setCapturingField(null);
    }
  };

  if (editing.type === 'cleanup') {
    const propGroups: Array<{
      label: string;
      props: Array<{ model: string; coords: { x: number; y: number; z: number }; heading?: number }>;
      randomize?: boolean;
      randomCount?: number;
    }> = params.propGroups || [];

    // Migration: show legacy props as a single group if no propGroups exist yet
    const hasLegacy = (!propGroups.length && params.props?.length);

    const effectiveGroups: typeof propGroups = hasLegacy
      ? [{ label: params.itemLabel || 'Items', props: params.props || [] }]
      : propGroups;

    const commitGroups = (updated: typeof effectiveGroups) => {
      updateParams({ propGroups: updated, props: undefined, itemLabel: undefined });
    };

    const addGroup = () => {
      commitGroups([...effectiveGroups, { label: '', props: [{ model: 'prop_beer_bottle', coords: { x: 0, y: 0, z: 0 }, heading: 0 }] }]);
    };

    const removeGroup = (gi: number) => {
      commitGroups(effectiveGroups.filter((_, i) => i !== gi));
    };

    const updateGroup = (gi: number, partial: Record<string, unknown>) => {
      const updated = [...effectiveGroups];
      updated[gi] = { ...updated[gi], ...partial };
      commitGroups(updated);
    };

    const addProp = (gi: number) => {
      const updated = [...effectiveGroups];
      updated[gi] = { ...updated[gi], props: [...(updated[gi].props || []), { model: 'prop_beer_bottle', coords: { x: 0, y: 0, z: 0 }, heading: 0 }] };
      commitGroups(updated);
    };

    const removeProp = (gi: number, pi: number) => {
      const updated = [...effectiveGroups];
      updated[gi] = { ...updated[gi], props: updated[gi].props.filter((_: any, i: number) => i !== pi) };
      commitGroups(updated);
    };

    const updateProp = (gi: number, pi: number, partial: Record<string, unknown>) => {
      const updated = [...effectiveGroups];
      const props = [...updated[gi].props];
      props[pi] = { ...props[pi], ...partial };
      updated[gi] = { ...updated[gi], props };
      commitGroups(updated);
    };

    const updatePropCoords = (gi: number, pi: number, partial: Record<string, number>) => {
      const updated = [...effectiveGroups];
      const props = [...updated[gi].props];
      props[pi] = { ...props[pi], coords: { ...props[pi].coords, ...partial } };
      updated[gi] = { ...updated[gi], props };
      commitGroups(updated);
    };

    const hasNonZeroCoords = (c: { x: number; y: number; z: number }) => c.x !== 0 || c.y !== 0 || c.z !== 0;

    return (
      <Stack gap="xs">
        <TextInput
          label="Item Label"
          placeholder="e.g. trash bag"
          value={params.itemLabel || effectiveGroups[0]?.label || ''}
          onChange={(e) => updateParams({ itemLabel: e.currentTarget.value })}
          size="xs"
        />
        {errors['params.props'] && <Text size="xs" c="red">{errors['params.props']}</Text>}

        <Text size="xs" fw={500}>Prop Groups ({effectiveGroups.length})</Text>

        <Accordion variant="separated" chevronPosition="left" styles={{ item: { background: 'rgba(40, 40, 60, 0.3)', border: 'none' }, content: { padding: '6px 8px' } }}>
          {effectiveGroups.map((group, gi) => {
            const totalProps = group.props.length;
            const displayCount = group.randomize && group.randomCount
              ? `${Math.min(group.randomCount, totalProps)} of ${totalProps}`
              : String(totalProps);

            return (
              <Accordion.Item key={gi} value={String(gi)}>
                <Accordion.Control>
                  <Group justify="space-between" wrap="nowrap" gap={4}>
                    <Text size="xs" fw={500}>{group.label || `Group ${gi + 1}`} ({displayCount} props)</Text>
                    <ActionIcon size="sm" color="red" variant="subtle" onClick={(e) => { e.stopPropagation(); removeGroup(gi); }}>✕</ActionIcon>
                  </Group>
                </Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    <TextInput
                      label="Group Label"
                      placeholder="e.g. Beer Bottles"
                      value={group.label}
                      onChange={(e) => updateGroup(gi, { label: e.currentTarget.value })}
                      size="xs"
                    />

                    <Switch
                      label="Random Selection"
                      description={group.randomize ? `Spawns ${group.randomCount || 1} of ${totalProps} placed props per mission run` : undefined}
                      checked={!!group.randomize}
                      onChange={(e) => updateGroup(gi, { randomize: e.currentTarget.checked, randomCount: e.currentTarget.checked ? Math.max(1, Math.ceil(totalProps / 2)) : undefined })}
                      size="xs"
                    />

                    {group.randomize && (
                      <NumberInput
                        label="Spawn Count"
                        value={group.randomCount || 1}
                        onChange={(v) => updateGroup(gi, { randomCount: Math.max(1, Math.min(Number(v) || 1, totalProps)) })}
                        min={1}
                        max={totalProps || 1}
                        size="xs"
                      />
                    )}

                    <Stack gap="xs">
                      {group.props.map((prop, pi) => (
                        <Stack key={pi} gap={4} style={{ padding: '6px', borderRadius: 4, background: 'rgba(30, 30, 50, 0.3)' }}>
                          <Group gap="xs">
                            <TextInput
                              placeholder="Prop model"
                              value={prop.model}
                              onChange={(e) => updateProp(gi, pi, { model: e.currentTarget.value })}
                              style={{ flex: 1 }}
                              size="xs"
                            />
                            <ActionIcon size="sm" color="red" variant="subtle" onClick={() => removeProp(gi, pi)}>✕</ActionIcon>
                          </Group>
                          <Group grow gap="xs">
                            <NumberInput label="X" value={prop.coords.x} onChange={(v) => updatePropCoords(gi, pi, { x: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
                            <NumberInput label="Y" value={prop.coords.y} onChange={(v) => updatePropCoords(gi, pi, { y: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
                            <NumberInput label="Z" value={prop.coords.z} onChange={(v) => updatePropCoords(gi, pi, { z: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
                            <NumberInput label="H" value={prop.heading ?? 0} onChange={(v) => updateProp(gi, pi, { heading: round2(Number(v) || 0) })} step={1} decimalScale={2} size="xs" />
                          </Group>
                          <Button
                            size="xs"
                            variant="subtle"
                            disabled={!prop.model}
                            onClick={() => {
                              const ctx = group.props
                                .filter((_: any, i: number) => i !== pi && hasNonZeroCoords(_.coords))
                                .map((p: any) => ({ model: p.model, coords: p.coords, heading: p.heading, entityType: 'prop' as const }));
                              startPlacement(`gprop_${gi}_${pi}`, prop.model, 'prop', ctx.length ? ctx : undefined);
                            }}
                          >
                            Place Prop
                          </Button>
                        </Stack>
                      ))}
                      <Button size="xs" variant="subtle" onClick={() => addProp(gi)}>+ Add Prop</Button>
                    </Stack>
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
            );
          })}
        </Accordion>

        <Button size="xs" variant="subtle" onClick={addGroup}>+ Add Prop Group</Button>
      </Stack>
    );
  }

  if (editing.type === 'delivery') {
    const dest = params.destination || { x: 0, y: 0, z: 0 };
    const hasOffset = params.propOffset || params.propRotation;

    return (
      <Stack gap="xs">
        <Text size="xs" fw={500}>Destination</Text>
        {errors['params.destination'] && <Text size="xs" c="red">{errors['params.destination']}</Text>}
        <Group grow gap="xs">
          <NumberInput label="X" value={dest.x} onChange={(v) => updateParams({ destination: { ...dest, x: round2(Number(v) || 0) } })} step={0.01} decimalScale={2} size="xs" />
          <NumberInput label="Y" value={dest.y} onChange={(v) => updateParams({ destination: { ...dest, y: round2(Number(v) || 0) } })} step={0.01} decimalScale={2} size="xs" />
          <NumberInput label="Z" value={dest.z} onChange={(v) => updateParams({ destination: { ...dest, z: round2(Number(v) || 0) } })} step={0.01} decimalScale={2} size="xs" />
        </Group>
        <Button
          size="xs"
          variant="light"
          onClick={() => {
            setCapturingField('destination');
            void fetchNui('admin:startPlacement', { field: 'destination', model: 'prop_mp_cone_01', entityType: 'prop' });
          }}
        >
          Place Destination
        </Button>

        <NumberInput
          label="Time Limit (seconds)"
          value={params.timeSeconds ?? 60}
          onChange={(v) => updateParams({ timeSeconds: Number(v) || 0 })}
          min={0}
          size="xs"
        />

        <TextInput
          label="Prop Model"
          placeholder="e.g. hei_prop_heist_box"
          value={params.prop || ''}
          onChange={(e) => updateParams({ prop: e.currentTarget.value || undefined })}
          size="xs"
        />

        <NativeSelect
          label="Carry Style"
          data={[
            { value: 'both_hands', label: 'Both Hands (box carry)' },
            { value: 'right_hand', label: 'Right Hand (bag carry)' },
          ]}
          value={params.carry || 'both_hands'}
          onChange={(e) => updateParams({ carry: e.currentTarget.value })}
          size="xs"
        />

        <Button
          size="xs"
          variant="light"
          disabled={!params.prop}
          onClick={async () => {
            setCapturingField('propAdjust');
            const result = await fetchNui<{ ok: boolean; reason?: string }>('admin:startPropAdjust', {
              prop: params.prop,
              carry: params.carry || 'both_hands',
              propOffset: params.propOffset,
              propRotation: params.propRotation,
            });
            if (result && !result.ok) {
              setCapturingField(null);
            }
          }}
        >
          Adjust Prop Position
        </Button>

        {hasOffset && (
          <Stack gap={4} style={{ padding: '6px 8px', borderRadius: 4, background: 'rgba(40, 40, 60, 0.3)' }}>
            {params.propOffset && (
              <Text size="xs" c="dimmed">
                Offset: {params.propOffset.x}, {params.propOffset.y}, {params.propOffset.z}
              </Text>
            )}
            {params.propRotation && (
              <Text size="xs" c="dimmed">
                Rotation: {params.propRotation.x}, {params.propRotation.y}, {params.propRotation.z}
              </Text>
            )}
            <Button
              size="xs"
              variant="subtle"
              color="red"
              onClick={() => updateParams({ propOffset: undefined, propRotation: undefined })}
            >
              Reset to Default
            </Button>
          </Stack>
        )}
      </Stack>
    );
  }

  if (editing.type === 'assassination') {
    const targets: Array<{
      model: string;
      coords: { x: number; y: number; z: number; w: number };
      weapon?: string;
      scenario?: string;
    }> = params.targets || [];

    const addTarget = () => {
      updateParams({
        targets: [...targets, { model: 'a_m_m_business_01', coords: { x: 0, y: 0, z: 0, w: 0 } }],
      });
    };

    const removeTarget = (idx: number) => {
      updateParams({ targets: targets.filter((_, i) => i !== idx) });
    };

    const updateTarget = (idx: number, partial: Record<string, any>) => {
      const updated = [...targets];
      updated[idx] = { ...updated[idx], ...partial };
      updateParams({ targets: updated });
    };

    const updateTargetCoords = (idx: number, partial: Record<string, number>) => {
      const updated = [...targets];
      updated[idx] = { ...updated[idx], coords: { ...updated[idx].coords, ...partial } };
      updateParams({ targets: updated });
    };

    const hasNonZeroCoords = (c: { x: number; y: number; z: number }) => c.x !== 0 || c.y !== 0 || c.z !== 0;

    return (
      <Stack gap="xs">
        <Switch
          label="Aggressive (targets attack player)"
          checked={!!params.aggressive}
          onChange={(e) => updateParams({ aggressive: e.currentTarget.checked })}
          size="xs"
        />
        <Switch
          label="Show target blips"
          checked={params.blip !== false}
          onChange={(e) => updateParams({ blip: e.currentTarget.checked })}
          size="xs"
        />

        <Text size="xs" fw={500}>Targets ({targets.length})</Text>
        {errors['params.targets'] && <Text size="xs" c="red">{errors['params.targets']}</Text>}
        {targets.map((target, idx) => (
          <Stack key={idx} gap={4} style={{ padding: '8px', borderRadius: 4, background: 'rgba(40, 40, 60, 0.3)' }}>
            <Group gap="xs">
              <TextInput
                placeholder="Ped model"
                value={target.model}
                onChange={(e) => updateTarget(idx, { model: e.currentTarget.value })}
                style={{ flex: 1 }}
                size="xs"
              />
              <ActionIcon size="sm" color="red" variant="subtle" onClick={() => removeTarget(idx)}>✕</ActionIcon>
            </Group>
            <Group grow gap="xs">
              <NumberInput label="X" value={target.coords.x} onChange={(v) => updateTargetCoords(idx, { x: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
              <NumberInput label="Y" value={target.coords.y} onChange={(v) => updateTargetCoords(idx, { y: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
              <NumberInput label="Z" value={target.coords.z} onChange={(v) => updateTargetCoords(idx, { z: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
              <NumberInput label="H" value={target.coords.w} onChange={(v) => updateTargetCoords(idx, { w: round2(Number(v) || 0) })} step={1} decimalScale={2} size="xs" />
            </Group>
            <Group grow gap="xs">
              <Select
                label="Weapon"
                placeholder="WEAPON_PISTOL"
                data={GTA_WEAPONS}
                value={target.weapon || null}
                onChange={(val) => updateTarget(idx, { weapon: val || undefined })}
                searchable
                clearable
                allowDeselect
                comboboxProps={{ withinPortal: false }}
                size="xs"
              />
              <TextInput
                label="Scenario"
                placeholder="WORLD_HUMAN_STAND_MOBILE"
                value={target.scenario || ''}
                onChange={(e) => updateTarget(idx, { scenario: e.currentTarget.value || undefined })}
                size="xs"
              />
            </Group>
            <Button
              size="xs"
              variant="subtle"
              disabled={!target.model}
              onClick={() => {
                const ctx = targets
                  .filter((_: any, i: number) => i !== idx && hasNonZeroCoords(_.coords))
                  .map((t: any) => ({ model: t.model, coords: t.coords, heading: t.coords.w, entityType: 'ped' as const }));
                startPlacement(`target_${idx}`, target.model, 'ped', ctx.length ? ctx : undefined);
              }}
            >
              Place Target
            </Button>
          </Stack>
        ))}
        <Button size="xs" variant="subtle" onClick={addTarget}>+ Add Target</Button>
      </Stack>
    );
  }

  return (
    <Text size="sm" c="dimmed">Select a mission type to configure parameters.</Text>
  );
}
