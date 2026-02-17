const npcMap = new Map<string, number>();

export function registerNpc(id: string, ped: number) {
  npcMap.set(id, ped);
}

export function getNpc(id: string) {
  return npcMap.get(id);
}
