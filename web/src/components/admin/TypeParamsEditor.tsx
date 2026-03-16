import {
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

  const startPlacement = async (field: string, model: string, entityType: 'ped' | 'prop') => {
    if (!model) return;
    setCapturingField(field);
    const result = await fetchNui<{ ok: boolean; reason?: string }>('admin:startPlacement', { field, model, entityType });
    if (result && !result.ok) {
      setCapturingField(null);
    }
  };

  if (editing.type === 'cleanup') {
    const props: Array<{ model: string; coords: { x: number; y: number; z: number } }> = params.props || [];

    const addProp = () => {
      updateParams({ props: [...props, { model: 'prop_beer_bottle', coords: { x: 0, y: 0, z: 0 } }] });
    };

    const removeProp = (idx: number) => {
      updateParams({ props: props.filter((_, i) => i !== idx) });
    };

    const updateProp = (idx: number, partial: Record<string, any>) => {
      const updated = [...props];
      updated[idx] = { ...updated[idx], ...partial };
      updateParams({ props: updated });
    };

    const updatePropCoords = (idx: number, partial: Record<string, number>) => {
      const updated = [...props];
      updated[idx] = { ...updated[idx], coords: { ...updated[idx].coords, ...partial } };
      updateParams({ props: updated });
    };

    return (
      <Stack gap="xs">
        <TextInput
          label="Item Label"
          placeholder="e.g. trash bag"
          value={params.itemLabel || ''}
          onChange={(e) => updateParams({ itemLabel: e.currentTarget.value })}
          size="xs"
        />
        <Text size="xs" fw={500}>Props ({props.length})</Text>
        {errors['params.props'] && <Text size="xs" c="red">{errors['params.props']}</Text>}
        {props.map((prop, idx) => (
          <Stack key={idx} gap={4} style={{ padding: '8px', borderRadius: 4, background: 'rgba(40, 40, 60, 0.3)' }}>
            <Group gap="xs">
              <TextInput
                placeholder="Prop model"
                value={prop.model}
                onChange={(e) => updateProp(idx, { model: e.currentTarget.value })}
                style={{ flex: 1 }}
                size="xs"
              />
              <ActionIcon size="sm" color="red" variant="subtle" onClick={() => removeProp(idx)}>✕</ActionIcon>
            </Group>
            <Group grow gap="xs">
              <NumberInput label="X" value={prop.coords.x} onChange={(v) => updatePropCoords(idx, { x: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
              <NumberInput label="Y" value={prop.coords.y} onChange={(v) => updatePropCoords(idx, { y: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
              <NumberInput label="Z" value={prop.coords.z} onChange={(v) => updatePropCoords(idx, { z: round2(Number(v) || 0) })} step={0.01} decimalScale={2} size="xs" />
            </Group>
            <Button
              size="xs"
              variant="subtle"
              disabled={!prop.model}
              onClick={() => startPlacement(`prop_${idx}`, prop.model, 'prop')}
            >
              Place Prop
            </Button>
          </Stack>
        ))}
        <Button size="xs" variant="subtle" onClick={addProp}>+ Add Prop</Button>
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
          value={params.timeSeconds || 0}
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
              onClick={() => startPlacement(`target_${idx}`, target.model, 'ped')}
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
