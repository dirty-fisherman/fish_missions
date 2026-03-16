import { useEffect, useState } from 'react';
import {
  Accordion,
  ActionIcon,
  Badge,
  Button,
  Group,
  Modal,
  NumberInput,
  ScrollArea,
  Select,
  Stack,
  Switch,
  Text,
  TextInput,
  Textarea,
  Title,
} from '@mantine/core';
import { fetchNui } from '../../utils/fetchNui';
import { useAdminStore } from '../../stores/adminStore';
import { TypeParamsEditor } from './TypeParamsEditor';
import { IconPlayerPlay } from '../icons';

interface MissionEditorProps {
  onSaved: () => void;
  onDeleted: () => void;
}

const round2 = (v: number) => Math.round(v * 100) / 100;

function decomposeCooldown(secs: number) {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  const s = secs % 60;
  return { h, m, s };
}

export function MissionEditor({ onSaved, onDeleted }: MissionEditorProps) {
  const {
    editing,
    selectedId,
    saving,
    updateEditing,
    updateNpc,
    updateReward,
    setSaving,
    setCapturingField,
    setEditing,
    setSelectedId,
  } = useAdminStore();

  const [deleteConfirm, setDeleteConfirm] = useState(false);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [saveError, setSaveError] = useState<string | null>(null);
  const [expandedMetadata, setExpandedMetadata] = useState<Set<number>>(new Set());
  const [metadataErrors, setMetadataErrors] = useState<Record<number, string>>({});

  const cooldown = decomposeCooldown(editing?.cooldownSeconds ?? 3600);

  const setCooldownPart = (part: 'h' | 'm' | 's', val: number) => {
    const c = { ...cooldown, [part]: Math.max(0, Math.round(val || 0)) };
    updateEditing({ cooldownSeconds: c.h * 3600 + c.m * 60 + c.s });
  };

  // Reset display state when switching to a differently-identified mission
  useEffect(() => {
    if (!editing) return;
    setExpandedMetadata(new Set());
    setMetadataErrors({});
  }, [editing?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!editing) return null;

  const isNew = !selectedId;
  const npc = editing.npc || {};
  const reward = editing.reward || { cash: 0, items: [] };
  const coords = npc.coords || { x: 0, y: 0, z: 0, w: 0 };

  const startPlacement = async (field: string, model: string, entityType: 'ped' | 'prop') => {
    if (!model) {
      setErrors((e) => ({ ...e, [field]: 'Enter a model name first' }));
      return;
    }
    setCapturingField(field);
    const result = await fetchNui<{ ok: boolean; reason?: string }>('admin:startPlacement', { field, model, entityType });
    if (result && !result.ok) {
      setCapturingField(null);
      if (result.reason === 'invalid_model') {
        setErrors((e) => ({ ...e, [field]: 'Invalid model: ' + model }));
      }
    }
  };

  const validate = (): boolean => {
    const errs: Record<string, string> = {};
    setSaveError(null);
    if (!editing.label?.trim()) errs.label = 'Label is required';
    if (!editing.type) errs.type = 'Type is required';
    if (!npc.model?.trim()) errs['npc.model'] = 'NPC model is required';
    if (!coords.x && !coords.y && !coords.z) errs['npc.coords'] = 'NPC position is required';

    // Type-specific validation
    if (editing.type === 'cleanup') {
      const propGroups = editing.params?.propGroups;
      const legacyProps = editing.params?.props;
      const hasGroups = propGroups && Array.isArray(propGroups) && propGroups.length > 0;
      const hasLegacy = legacyProps && Array.isArray(legacyProps) && legacyProps.length > 0;
      if (!hasGroups && !hasLegacy) {
        errs['params.props'] = 'At least 1 prop group required for cleanup';
      }
    }
    if (editing.type === 'delivery') {
      const dest = editing.params?.destination;
      if (!dest || (!dest.x && !dest.y && !dest.z)) {
        errs['params.destination'] = 'Destination coords required for delivery';
      }
    }
    if (editing.type === 'assassination') {
      const targets = editing.params?.targets;
      if (!targets || !Array.isArray(targets) || targets.length === 0) {
        errs['params.targets'] = 'At least 1 target required for assassination';
      }
    }

    setErrors(errs);
    return Object.keys(errs).length === 0;
  };

  const handleSave = async () => {
    if (!validate()) {
      setSaveError('Fix the errors above before saving');
      return;
    }
    setSaving(true);
    setSaveError(null);
    try {
      const result = await fetchNui<{ id?: string; isNew?: boolean }>('admin:saveMission', editing);
      if (result?.id) {
        setSelectedId(result.id);
        updateEditing({ id: result.id });
        onSaved();
        void fetchNui('admin:notify', { type: 'success', description: result.isNew ? 'Mission created' : 'Mission saved' });
      } else {
        setSaveError('Save failed — server returned no ID');
        void fetchNui('admin:notify', { type: 'error', description: 'Save failed' });
      }
    } catch {
      setSaveError('Save failed — unexpected error');
      void fetchNui('admin:notify', { type: 'error', description: 'Save failed — unexpected error' });
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!selectedId) return;
    setSaving(true);
    try {
      await fetchNui('admin:deleteMission', { id: selectedId });
      setDeleteConfirm(false);
      onDeleted();
      void fetchNui('admin:notify', { type: 'success', description: 'Mission deleted' });
    } finally {
      setSaving(false);
    }
  };

  const handleCancel = () => {
    setEditing(null);
    setSelectedId(null);
  };

  // Reward item helpers
  const addRewardItem = () => {
    const items = [...(reward.items || []), { name: '', count: 1 }];
    updateReward({ items });
  };

  const removeRewardItem = (idx: number) => {
    const items = (reward.items || []).filter((_, i) => i !== idx);
    updateReward({ items });
  };

  const updateRewardItem = (idx: number, field: 'name' | 'count', value: string | number) => {
    const items = [...(reward.items || [])];
    items[idx] = { ...items[idx], [field]: value };
    updateReward({ items });
  };

  const updateRewardItemMeta = (idx: number, raw: string) => {
    try {
      const parsed = raw.trim() === '' ? undefined : JSON.parse(raw);
      const items = [...(reward.items || [])];
      items[idx] = { ...items[idx], metadata: parsed };
      updateReward({ items });
      setMetadataErrors((e) => { const n = { ...e }; delete n[idx]; return n; });
    } catch {
      setMetadataErrors((e) => ({ ...e, [idx]: 'Invalid JSON' }));
    }
  };

  return (
    <Stack gap={0} style={{ height: '100%', overflow: 'hidden' }}>
      {/* Fixed header */}
      <Group justify="space-between" p="sm" style={{ flexShrink: 0, borderBottom: '1px solid rgba(60, 60, 80, 0.5)', background: 'rgba(22, 22, 30, 0.95)' }}>
        <Title order={4} c="white">{isNew ? 'New Mission' : `Edit: ${editing.label || editing.id}`}</Title>
        {editing.id && <Badge size="sm" variant="outline" color="gray">{editing.id}</Badge>}
      </Group>

      <ScrollArea style={{ flex: 1 }} offsetScrollbars pr="md">
        <Stack gap="md" pb="md" pt="md">

        <Accordion defaultValue={['basic', 'npc', 'params', 'reward']} multiple variant="separated">
          {/* ── Basic Info ──────────────────────────────────────── */}
          <Accordion.Item value="basic">
            <Accordion.Control><Text fw={600} size="sm">Basic Info</Text></Accordion.Control>
            <Accordion.Panel>
              <Stack gap="xs">
                <TextInput
                  label="Label"
                  required
                  value={editing.label}
                  onChange={(e) => updateEditing({ label: e.currentTarget.value })}
                  error={errors.label}
                  size="xs"
                />
                <Textarea
                  label="Description"
                  value={editing.description}
                  onChange={(e) => updateEditing({ description: e.currentTarget.value })}
                  autosize
                  minRows={2}
                  maxRows={5}
                  size="xs"
                />
                <Select
                  label="Type"
                  required
                  data={[
                    { value: 'cleanup', label: 'Cleanup' },
                    { value: 'delivery', label: 'Delivery' },
                    { value: 'assassination', label: 'Assassination' },
                  ]}
                  value={editing.type}
                  onChange={(val) => val && updateEditing({ type: val as any, params: {} })}
                  error={errors.type}
                  allowDeselect={false}
                  comboboxProps={{ withinPortal: false }}
                  size="xs"
                />
                <Text size="xs" fw={500}>Cooldown</Text>
                <Group grow gap="xs">
                  <NumberInput
                    label="Hours"
                    value={cooldown.h}
                    onChange={(val) => setCooldownPart('h', Number(val) || 0)}
                    min={0}
                    size="xs"
                  />
                  <NumberInput
                    label="Minutes"
                    value={cooldown.m}
                    onChange={(val) => setCooldownPart('m', Number(val) || 0)}
                    min={0}
                    max={59}
                    size="xs"
                  />
                  <NumberInput
                    label="Seconds"
                    value={cooldown.s}
                    onChange={(val) => setCooldownPart('s', Number(val) || 0)}
                    min={0}
                    max={59}
                    size="xs"
                  />

                </Group>
                <Text size="xs" c="dimmed">Total: {editing.cooldownSeconds}s</Text>
                <Group>
                  <Switch
                    label="Enabled"
                    checked={!!editing.enabled}
                    onChange={(e) => updateEditing({ enabled: e.currentTarget.checked })}
                    size="xs"
                  />
                </Group>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* ── NPC Configuration ──────────────────────────────── */}
          <Accordion.Item value="npc">
            <Accordion.Control><Text fw={600} size="sm">NPC</Text></Accordion.Control>
            <Accordion.Panel>
              <Stack gap="xs">
                <TextInput
                  label="Ped Model"
                  required
                  placeholder="e.g. s_m_m_postal_01"
                  value={npc.model || ''}
                  onChange={(e) => updateNpc({ model: e.currentTarget.value })}
                  error={errors['npc.model']}
                  size="xs"
                />

                <Text size="xs" fw={500}>Position</Text>
                <Group grow>
                  <NumberInput label="X" value={coords.x} onChange={(v) => updateNpc({ coords: { ...coords, x: round2(Number(v) || 0) } })} step={0.01} decimalScale={2} size="xs" />
                  <NumberInput label="Y" value={coords.y} onChange={(v) => updateNpc({ coords: { ...coords, y: round2(Number(v) || 0) } })} step={0.01} decimalScale={2} size="xs" />
                  <NumberInput label="Z" value={coords.z} onChange={(v) => updateNpc({ coords: { ...coords, z: round2(Number(v) || 0) } })} step={0.01} decimalScale={2} size="xs" />
                  <NumberInput label="Heading" value={coords.w} onChange={(v) => updateNpc({ coords: { ...coords, w: round2(Number(v) || 0) } })} step={1} decimalScale={2} size="xs" />
                </Group>
                {errors['npc.coords'] && <Text size="xs" c="red">{errors['npc.coords']}</Text>}
                <Button
                  size="xs"
                  variant="light"
                  onClick={() => startPlacement('npc', npc.model || '', 'ped')}
                >
                  Place NPC In-World
                </Button>

                <TextInput
                  label="Scenario"
                  placeholder="e.g. WORLD_HUMAN_CLIPBOARD"
                  value={npc.scenario || ''}
                  onChange={(e) => updateNpc({ scenario: e.currentTarget.value || undefined })}
                  size="xs"
                />

                <Group grow>
                  <TextInput
                    label="Target Label"
                    value={npc.target?.label || ''}
                    onChange={(e) => updateNpc({ target: { ...npc.target, label: e.currentTarget.value } })}
                    size="xs"
                  />
                  <TextInput
                    label="Target Icon"
                    placeholder="fa-solid fa-clipboard"
                    value={npc.target?.icon || ''}
                    onChange={(e) => updateNpc({ target: { ...npc.target, icon: e.currentTarget.value } })}
                    size="xs"
                  />
                </Group>

                <Text size="xs" fw={500}>Blip</Text>
                <Switch
                  label="Display Blip"
                  checked={npc.blip !== false}
                  onChange={(e) => updateNpc({ blip: e.currentTarget.checked ? {} : false as any })}
                  size="xs"
                />

                <Text size="xs" fw={500}>Speech</Text>
                <Group grow>
                  <Group gap={4} wrap="nowrap" style={{ flex: 1 }}>
                    <TextInput label="Greet" value={npc.speech || ''} onChange={(e) => updateNpc({ speech: e.currentTarget.value || undefined })} placeholder="GENERIC_HI" size="xs" style={{ flex: 1 }} />
                    <ActionIcon size="sm" variant="subtle" mt={18} onClick={() => void fetchNui('admin:previewSpeech', { speech: npc.speech || 'GENERIC_HI', model: npc.model })} title="Preview"><IconPlayerPlay /></ActionIcon>
                  </Group>
                  <Group gap={4} wrap="nowrap" style={{ flex: 1 }}>
                    <TextInput label="Claim" value={npc.speechClaim || ''} onChange={(e) => updateNpc({ speechClaim: e.currentTarget.value || undefined })} placeholder="GENERIC_THANKS" size="xs" style={{ flex: 1 }} />
                    <ActionIcon size="sm" variant="subtle" mt={18} onClick={() => void fetchNui('admin:previewSpeech', { speech: npc.speechClaim || 'GENERIC_THANKS', model: npc.model })} title="Preview"><IconPlayerPlay /></ActionIcon>
                  </Group>
                  <Group gap={4} wrap="nowrap" style={{ flex: 1 }}>
                    <TextInput label="Bye" value={npc.speechBye || ''} onChange={(e) => updateNpc({ speechBye: e.currentTarget.value || undefined })} placeholder="GENERIC_BYE" size="xs" style={{ flex: 1 }} />
                    <ActionIcon size="sm" variant="subtle" mt={18} onClick={() => void fetchNui('admin:previewSpeech', { speech: npc.speechBye || 'GENERIC_BYE', model: npc.model })} title="Preview"><IconPlayerPlay /></ActionIcon>
                  </Group>
                </Group>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* ── Type-Specific Params ──────────────────────────── */}
          <Accordion.Item value="params">
            <Accordion.Control><Text fw={600} size="sm">Parameters ({editing.type})</Text></Accordion.Control>
            <Accordion.Panel>
              <TypeParamsEditor errors={errors} />
            </Accordion.Panel>
          </Accordion.Item>

          {/* ── Reward ─────────────────────────────────────────── */}
          <Accordion.Item value="reward">
            <Accordion.Control><Text fw={600} size="sm">Reward</Text></Accordion.Control>
            <Accordion.Panel>
              <Stack gap="xs">
                <NumberInput
                  label="Cash"
                  value={reward.cash || 0}
                  onChange={(v) => updateReward({ cash: Number(v) || 0 })}
                  min={0}
                  size="xs"
                />
                <Text size="xs" fw={500}>Items</Text>
                {(reward.items || []).map((item, idx) => (
                  <Stack key={idx} gap={4}>
                    <Group gap="xs">
                      <TextInput
                        placeholder="Item name"
                        value={item.name}
                        onChange={(e) => updateRewardItem(idx, 'name', e.currentTarget.value)}
                        style={{ flex: 1 }}
                        size="xs"
                      />
                      <NumberInput
                        value={item.count}
                        onChange={(v) => updateRewardItem(idx, 'count', Number(v) || 1)}
                        min={1}
                        w={70}
                        size="xs"
                      />
                      <ActionIcon
                        size="sm"
                        variant="subtle"
                        title="Edit metadata"
                        onClick={() =>
                          setExpandedMetadata((s) => {
                            const n = new Set(s);
                            if (n.has(idx)) n.delete(idx); else n.add(idx);
                            return n;
                          })
                        }
                      >
                        ⚙
                      </ActionIcon>
                      <ActionIcon size="sm" color="red" variant="subtle" onClick={() => removeRewardItem(idx)}>
                        ✕
                      </ActionIcon>
                    </Group>
                    {expandedMetadata.has(idx) && (
                      <Textarea
                        placeholder='{"quality": "good"}'
                        defaultValue={item.metadata ? JSON.stringify(item.metadata, null, 2) : ''}
                        onBlur={(e) => updateRewardItemMeta(idx, e.currentTarget.value)}
                        error={metadataErrors[idx]}
                        autosize
                        minRows={2}
                        maxRows={5}
                        size="xs"
                        styles={{ input: { fontFamily: 'monospace', fontSize: 11 } }}
                      />
                    )}
                  </Stack>
                ))}
                <Button size="xs" variant="subtle" onClick={addRewardItem}>+ Add Item</Button>
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>

          {/* ── Advanced ───────────────────────────────────────── */}
          <Accordion.Item value="advanced">
            <Accordion.Control><Text fw={600} size="sm">Advanced</Text></Accordion.Control>
            <Accordion.Panel>
              <Stack gap="xs">
                <NumberInput
                  label="Level Required"
                  value={editing.levelRequired || 0}
                  onChange={(v) => updateEditing({ levelRequired: Number(v) || 0 })}
                  min={0}
                  size="xs"
                />
                <TextInput
                  label="Prerequisites (comma-separated mission IDs)"
                  value={(editing.prerequisites || []).join(', ')}
                  onChange={(e) => {
                    const ids = e.currentTarget.value.split(',').map((s) => s.trim()).filter(Boolean);
                    updateEditing({ prerequisites: ids.length > 0 ? ids : undefined });
                  }}
                  size="xs"
                />
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>
        </Stack>
      </ScrollArea>

      {/* ── Fixed action bar ──────────────────────────────────── */}
      <Group
        justify="space-between"
        p="sm"
        style={{
          borderTop: '1px solid rgba(60, 60, 80, 0.5)',
          background: 'rgba(22, 22, 30, 0.95)',
          flexShrink: 0,
        }}
      >
        <Group>
          <Button size="sm" onClick={handleSave} loading={saving}>
            {isNew ? 'Create Mission' : 'Save Changes'}
          </Button>
          <Button size="sm" variant="subtle" color="gray" onClick={handleCancel}>
            Cancel
          </Button>
          {saveError && <Text size="xs" c="red">{saveError}</Text>}
        </Group>
        {!isNew && (
          <Button size="sm" color="red" variant="light" onClick={() => setDeleteConfirm(true)}>
            Delete
          </Button>
        )}
      </Group>

      {/* Delete confirmation modal */}
      {deleteConfirm && (
      <Modal
        opened
        onClose={() => setDeleteConfirm(false)}
        title="Delete Mission"
        size="sm"
        centered
        withinPortal
        overlayProps={{ backgroundOpacity: 0.6, color: '#000' }}
        zIndex={3000}
        styles={{
          content: { background: 'rgba(22, 22, 30, 0.97)', border: '1px solid rgba(60, 60, 80, 0.5)' },
          header: { background: 'rgba(22, 22, 30, 0.97)' },
        }}
      >
        <Stack>
          <Text size="sm">
            Are you sure you want to delete <strong>{editing.label || editing.id}</strong>?
            This will also remove all player progress for this mission.
          </Text>
          <Group justify="flex-end">
            <Button variant="subtle" onClick={() => setDeleteConfirm(false)}>Cancel</Button>
            <Button color="red" onClick={handleDelete} loading={saving}>Delete</Button>
          </Group>
        </Stack>
      </Modal>
      )}
    </Stack>
  );
}
