declare module '@communityox/ox_lib/client' {
  export const cache: any;
}

declare module '@communityox/ox_lib/server' {
  export const addCommand: any;
  export const cache: any;
}

// Optional qb-target export shape used as fallback; typed as any
declare const exports: any;

// FiveM runtime globals (when typings are missing, keep them as any)
declare function onNet(name: string, cb: (...args: any[]) => void): void;
declare function on(name: string, cb: (...args: any[]) => void): void;
declare function emitNet(name: string, target: number, ...args: any[]): void;
declare function GetCurrentResourceName(): string;
declare function GetPlayerIdentifiers(src: string): string[];
declare function getPlayerIdentifiers(src: number): string[];
declare function GetResourceKvpString(key: string): string | undefined;
declare function SetResourceKvpNoSync(key: string, value: string): void;
declare function DeleteResourceKvp(key: string): void;

// Client natives used
declare const SetNuiFocus: (...args: any[]) => void;
declare const SendNUIMessage: (...args: any[]) => void; // legacy casing (some resources)
declare const SendNuiMessage: (json: string) => void; // recommended: stringified JSON
declare const RegisterNuiCallback: (name: string, cb: (data: any, cb: (result: any) => void) => void) => void;
declare const RegisterNuiCallbackType: (name: string) => void;
declare const GetHashKey: (name: string) => number;
declare const RequestModel: (hash: number) => void;
declare const HasModelLoaded: (hash: number) => boolean;
declare const CreatePed: (...args: any[]) => number;
declare const SetEntityInvincible: (entity: number, toggle: boolean) => void;
declare const SetBlockingOfNonTemporaryEvents: (entity: number, toggle: boolean) => void;
declare const FreezeEntityPosition: (entity: number, toggle: boolean) => void;
declare const TaskStartScenarioInPlace: (ped: number, scenario: string, p2: number, p3: boolean) => void;
declare const AddBlipForEntity: (entity: number) => number;
declare const SetBlipSprite: (blip: number, sprite: number) => void;
declare const SetBlipColour: (blip: number, color: number) => void;
declare const SetBlipScale: (blip: number, scale: number) => void;
declare const BeginTextCommandSetBlipName: (text: string) => void;
declare const AddTextComponentString: (text: string) => void;
declare const EndTextCommandSetBlipName: (blip: number) => void;
declare const AddBlipForRadius: (x: number, y: number, z: number, radius: number) => number;
declare const SetBlipAlpha: (blip: number, alpha: number) => void;
declare const GetGroundZFor_3dCoord: (x: number, y: number, z: number, unk: boolean) => [boolean, number];
declare const CreateObject: (hash: number, x: number, y: number, z: number, p5: boolean, p6: boolean, p7: boolean) => number;
declare const PlaceObjectOnGroundProperly: (object: number) => void;
declare const SetEntityAsMissionEntity: (entity: number, p1: boolean, p2: boolean) => void;
declare const DeleteObject: (object: number) => void;
declare const AddBlipForCoord: (x: number, y: number, z: number) => number;
declare const AddBlipForRadius: (x: number, y: number, z: number, radius: number) => number;
declare const SetBlipAsShortRange: (blip: number, toggle: boolean) => void;
declare const SetBlipAlpha: (blip: number, alpha: number) => void;
declare const SetBlipCategory: (blip: number, index: number) => void;
declare const SetBlipDisplay: (blip: number, displayId: number) => void;
declare const setTick: (cb: () => void) => number;
declare const clearTick: (id: number) => void;
declare const DrawMarker: (...args: any[]) => void;
declare const PlayerPedId: () => number;
declare const GetEntityCoords: (entity: number, alive: boolean) => [number, number, number];
declare const GetGameTimer: () => number;
declare const TaskCombatPed: (ped: number, targetPed: number, p2: number, p3: number) => void;
declare const GiveWeaponToPed: (ped: number, weaponHash: number, ammoCount: number, isHidden: boolean, equipNow: boolean) => void;
declare const SetPedAsEnemy: (ped: number, toggle: boolean) => void;
declare const SetPedCombatAttributes: (ped: number, attributeIndex: number, enabled: boolean) => void;
declare const IsEntityDead: (entity: number) => boolean;
declare const IsPedFatallyInjured: (ped: number) => boolean;
declare const RemoveBlip: (blip: number) => void;
declare const DeleteEntity: (entity: number) => void;
