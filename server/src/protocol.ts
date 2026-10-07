import type { InvasionRole } from "./invasion.js";
import type { WorldEventSummary } from "./world-events.js";
import type { GuildBattleSummary, RealmWarSummary, EndgameCreatureSummary, MythicContentSummary } from "./endgame.js";
import type { TerritorySeasonStanding, TerritorySeasonSummary } from "./territory-seasons.js";
import type { PublicPlayerState } from "./player.js";
import type { AuctionCategory, AuctionRarity, AuctionSummary } from "./auction.js";
import type { ChatMessage, FriendRecord, PartyInvitation, PartyState } from "./social.js";
export interface ChunkCoordinate { x:number; y:number; }

export type ClientMessage =
  | { type:"ping" }
  | { type:"auth"; token:string }
  | { type:"subscribe_chunks"; requestId:string; chunks:ChunkCoordinate[] }
  | { type:"gather_resource"; requestId:string; resourceId:string }
  | { type:"move"; dx:number; dy:number; dt:number }
  | { type:"select_hotbar"; slot:number }
  | { type:"attack"; requestId:string; targetId:string; facingX:number; facingY:number }
  | { type:"dodge"; facingX:number; facingY:number }
  | { type:"block"; active:boolean }
  | { type:"capture"; requestId:string; targetId:string }
  | { type:"tame"; requestId:string; creatureId:string }
  | { type:"set_creature_party"; requestId:string; creatureId:string; slot:number|null }
  | { type:"set_creature_ai"; requestId:string; creatureId:string; mode:"follow"|"assist"|"stay" }
  | { type:"create_base"; requestId:string; name:string; x:number; y:number }
  | { type:"build"; requestId:string; buildingType:string; level:number; gridX:number; gridY:number }
  | { type:"upgrade_building"; requestId:string; buildingId:string }
  | { type:"storage"; requestId:string; changes:Record<string,number> }
  | { type:"set_base_permission"; requestId:string; targetUserId:string; permission:string; enabled:boolean }
  | { type:"assign_worker"; requestId:string; creatureId:string; buildingId:string; task:string }
  | { type:"set_work_priorities"; requestId:string; priorities:string[] }
  | { type:"craft"; requestId:string; recipeId:string }
  | { type:"shop_purchase"; requestId:string; itemId:string; quantity:number }
  | { type:"trade"; requestId:string; toUserId:string; gold:string; items:Array<{itemId:string;quantity:number}> }
  | { type:"start_breeding"; requestId:string; baseId:string; penBuildingId:string; parentAId:string; parentBId:string; durationMs?:number }
  | { type:"list_breeding"; requestId:string }
  | { type:"create_guild"; requestId:string; name:string; tag:string }
  | { type:"get_guild"; requestId:string }
  | { type:"list_guild_invitations"; requestId:string }
  | { type:"list_realms"; requestId:string }
  | { type:"list_territories"; requestId:string }
  | { type:"list_realm_fortresses"; requestId:string }
  | { type:"territory_at"; requestId:string; x:number; y:number }
  | { type:"claim_guild_territory"; requestId:string; territoryId:string; guildId:string }
  | { type:"change_realm_reputation"; requestId:string; realm:string; delta:number }
  | { type:"my_realm_reputation"; requestId:string }
  | { type:"create_trade_route"; requestId:string; sourceTerritoryId:string; destinationTerritoryId:string; resourceKey:string; quantity:string; travelSeconds:number; guildId:string|null; realmId:string|null }
  | { type:"list_trade_routes"; requestId:string }
  | { type:"tick_realm_ai"; requestId:string }
  | { type:"list_invasions"; requestId:string; territoryId:string|null }
  | { type:"get_invasion_waves"; requestId:string; invasionId:string }
  | { type:"join_invasion"; requestId:string; invasionId:string; armyId:string; role:InvasionRole }
  | { type:"invasion_action"; requestId:string; invasionId:string; action:"attack"|"reinforce"|"retreat"; waveId:string|null }
  | { type:"invite_guild_member"; requestId:string; guildId:string; targetUserId:string }
  | { type:"accept_guild_invite"; requestId:string; invitationId:string }
  | { type:"decline_guild_invite"; requestId:string; invitationId:string }
  | { type:"leave_guild"; requestId:string; guildId:string }
  | { type:"remove_guild_member"; requestId:string; guildId:string; targetUserId:string }
  | { type:"set_guild_rank"; requestId:string; guildId:string; targetUserId:string; rank:string }
  | { type:"set_guild_permission"; requestId:string; guildId:string; rank:string; permission:string; enabled:boolean }
  | { type:"guild_bank"; requestId:string; guildId:string }
  | { type:"guild_bank_deposit"; requestId:string; guildId:string; itemId:string; quantity:number; gold:string }
  | { type:"guild_bank_withdraw"; requestId:string; guildId:string; itemId:string; quantity:number; gold:string }
  | { type:"build_guild_infrastructure"; requestId:string; guildId:string; structureType:string }
  | { type:"create_army"; requestId:string; name:string }
  | { type:"list_armies"; requestId:string }
  | { type:"train_army"; requestId:string; armyId:string; unitType:string; quantity:number }
  | { type:"garrison_army"; requestId:string; armyId:string; baseId:string }
  | { type:"add_army_creature"; requestId:string; armyId:string; creatureId:string }
  | { type:"set_army_assignment"; requestId:string; armyId:string; assignment:string }
  | { type:"set_army_formation"; requestId:string; armyId:string; name:string; formationType:string; layout:Record<string,unknown> }
  | { type:"nominate_commander"; requestId:string; guildId:string; targetUserId:string }
  | { type:"assign_army_commander"; requestId:string; armyId:string; commanderUserId:string }
  | { type:"issue_army_order"; requestId:string; armyId:string; battleId:string|null; orderType:string; targetUnitId:string|null; targetX:number|null; targetY:number|null; payload:Record<string,unknown> }
  | { type:"create_army_battle"; requestId:string; attackerArmyId:string; defenderArmyId:string|null; targetX:number; targetY:number }
  | { type:"deploy_battle_unit"; requestId:string; battleId:string; unitId:string; formationSlot:number }
  | { type:"execute_battle_turn"; requestId:string; battleId:string }
  | { type:"get_army_battle"; requestId:string; battleId:string }
  | { type:"army_tactical_action"; requestId:string; battleId:string; unitId:string; actionType:"ability"|"retreat"|"fire_cannon"|"deploy_trap"|"reinforce"; targetUnitId:string|null }
  | { type:"build_defense"; requestId:string; baseId:string; structureType:string; gridX:number; gridY:number }
  | { type:"list_defenses"; requestId:string; baseId:string }
  | { type:"create_ship"; requestId:string; name:string; shipClass:string }
  | { type:"list_ships"; requestId:string }
  | { type:"ship_inventory"; requestId:string; shipId:string }
  | { type:"ship_cargo"; requestId:string; shipId:string; itemId:string; quantity:number }
  | { type:"create_fleet"; requestId:string; name:string; shipId:string }
  | { type:"list_fleets"; requestId:string }
  | { type:"add_fleet_ship"; requestId:string; fleetId:string; shipId:string }
  | { type:"remove_fleet_ship"; requestId:string; fleetId:string; shipId:string }
  | { type:"sail"; requestId:string; shipId:string; dx:number; dy:number; dt:number }
  | { type:"assign_ship_crew"; requestId:string; shipId:string; creatureId:string; role:string; skill:number; morale:number }
  | { type:"fire_cannon"; requestId:string; shipId:string; targetShipId:string }
  | { type:"assign_ship_npc_crew"; requestId:string; shipId:string; npcType:"pirate"|"mermaid"|"dragon"|"npc_specialist"; role:string; skill:number; morale:number }
  | { type:"board_ship"; requestId:string; shipId:string; targetShipId:string }
  | { type:"repair_ship"; requestId:string; shipId:string }
  | { type:"retreat_ship"; requestId:string; shipId:string }
  | { type:"fight_ship_fire"; requestId:string; shipId:string }
  | { type:"list_friends"; requestId:string }
  | { type:"add_friend"; requestId:string; targetUserId:string }
  | { type:"remove_friend"; requestId:string; targetUserId:string }
  | { type:"block_user"; requestId:string; targetUserId:string }
  | { type:"unblock_user"; requestId:string; targetUserId:string }
  | { type:"list_blocks"; requestId:string }
  | { type:"report_user"; requestId:string; targetUserId:string; reason:string; details:string }
  | { type:"chat_send"; requestId:string; channel:"local"|"region"|"party"|"guild"|"trade"|"global"|"system"|"whisper"; body:string; recipientUserId:string|null; guildId:string|null; partyId:string|null }
  | { type:"chat_history"; requestId:string; channel:"local"|"region"|"party"|"guild"|"trade"|"global"|"system"|"whisper"; recipientUserId:string|null; guildId:string|null; partyId:string|null }
  | { type:"create_party"; requestId:string }
  | { type:"get_party"; requestId:string }
  | { type:"party_invitations"; requestId:string }
  | { type:"party_invite"; requestId:string; targetUserId:string }
  | { type:"party_accept"; requestId:string; invitationId:string }
  | { type:"party_leave"; requestId:string }
  | { type:"party_kick"; requestId:string; targetUserId:string }
  | { type:"auction_list"; requestId:string; itemId:string|null; rarity?:AuctionRarity|null; category?:AuctionCategory|null; minLevel?:number|null; maxLevel?:number|null; minPrice:string|null; maxPrice:string|null }
  | { type:"auction_create"; requestId:string; itemId:string; quantity:number; startPrice:string; buyNowPrice:string|null; durationMs:number }
  | { type:"auction_bid"; requestId:string; listingId:string; amount:string }
  | { type:"auction_buy_now"; requestId:string; listingId:string }
  | { type:"auction_cancel"; requestId:string; listingId:string }
  | { type:"auction_history"; requestId:string }
  | { type:"list_world_events"; requestId:string }
  | { type:"world_event_contribute"; requestId:string; eventId:string }
  | { type:"world_event_reward"; requestId:string; eventId:string }
  | { type:"list_realm_wars"; requestId:string }
  | { type:"create_realm_war"; requestId:string; attackerRealmId:string; defenderRealmId:string; targetTerritoryId:string }
  | { type:"join_realm_war"; requestId:string; warId:string; guildId:string; realmId:string }
  | { type:"realm_war_action"; requestId:string; warId:string; guildId:string; armyId:string }
  | { type:"list_guild_battles"; requestId:string }
  | { type:"create_guild_battle"; requestId:string; attackerGuildId:string; defenderGuildId:string; targetTerritoryId:string }
  | { type:"join_guild_battle"; requestId:string; battleId:string; armyId:string }
  | { type:"guild_battle_action"; requestId:string; battleId:string; armyId:string }
  | { type:"list_endgame_creatures"; requestId:string }
  | { type:"engage_endgame_creature"; requestId:string; creatureId:string }
  | { type:"list_mythic_content"; requestId:string }
  | { type:"list_territory_season"; requestId:string };


export type ServerMessage =
  | { type:"server_ready"; timestamp:number }
  | { type:"pong"; timestamp:number }
  | { type:"auth_ok"; userId:string }
  | { type:"player_state"; state:PublicPlayerState }
  | { type:"resource_gathered"; requestId:string; resourceId:string; itemId:string; quantity:number; respawnsAt:string; state:PublicPlayerState }
  | { type:"world_chunk"; requestId:string; chunk:unknown }
  | { type:"projectile_spawn"; projectileId:string; ownerUserId:string; targetId:string; x:number; y:number; vx:number; vy:number; expiresAt:number }
  | { type:"combat_result"; requestId:string; targetId:string; damage:number; critical:boolean; killed:boolean; targetHealth:number; status?:string; missed?:boolean }
  | { type:"creature_state"; requestId?:string; creature:unknown }
  | { type:"creature_party"; creatures:unknown[] }
  | { type:"base_state"; base:unknown }
  | { type:"building_state"; requestId:string; building:unknown }
  | { type:"craft_result"; requestId:string; transactionId:string; recipeId:string; state:PublicPlayerState }
  | { type:"shop_purchase_result"; requestId:string; transactionId:string; itemId:string; quantity:number; totalGold:string; state:PublicPlayerState }
  | { type:"trade_result"; requestId:string; transactionId:string; from:unknown; to:unknown }
  | { type:"breeding_started"; requestId:string; job:unknown }
  | { type:"breeding_jobs"; requestId:string; jobs:unknown[] }
  | { type:"guild_state"; requestId:string; guild:unknown }
  | { type:"guild_invitations"; requestId:string; invitations:unknown[] }
  | { type:"guild_bank_state"; requestId:string; guildId:string; bank:unknown }
  | { type:"guild_operation_ok"; requestId:string; guildId:string; transactionId?:string; rewardTransactionIds?:string[] }
  | { type:"realm_list"; requestId:string; realms:unknown[] }
  | { type:"territory_list"; requestId:string; territories:unknown[] }
  | { type:"fortress_list"; requestId:string; fortresses:unknown[] }
  | { type:"territory_state"; requestId:string; territory:unknown }
  | { type:"realm_reputation"; requestId:string; reputation:unknown }
  | { type:"trade_route_state"; requestId:string; route:unknown }
  | { type:"trade_route_list"; requestId:string; routes:unknown[] }
  | { type:"realm_operation_ok"; requestId:string }
  | { type:"invasion_list"; requestId:string; invasions:unknown[] }
  | { type:"invasion_waves"; requestId:string; invasionId:string; waves:unknown[] }
  | { type:"invasion_state"; requestId:string; invasion:unknown }
  | { type:"invasion_operation_ok"; requestId:string; invasionId:string }
  | { type:"army_state"; requestId:string; army:unknown }
  | { type:"army_list"; requestId:string; armies:unknown[] }
  | { type:"army_training"; requestId:string; queueId:string; completesAt:string }
  | { type:"army_operation_ok"; requestId:string }
  | { type:"battle_state"; requestId:string; battle:unknown }
  | { type:"defense_state"; requestId:string; defense:unknown }
  | { type:"defense_list"; requestId:string; defenses:unknown[] }
  | { type:"ship_state"; requestId:string; ship:unknown }
  | { type:"ship_list"; requestId:string; ships:unknown[] }
  | { type:"ship_inventory"; requestId:string; shipId:string; items:unknown[] }
  | { type:"ship_crew"; requestId:string; crew:unknown }
  | { type:"fleet_state"; requestId:string; fleet:unknown }
  | { type:"fleet_list"; requestId:string; fleets:unknown[] }
  | { type:"naval_combat_result"; requestId:string; attacker:unknown; target:unknown; damage:number; fireStarted?:boolean; captured?:boolean }
  | { type:"friends_list"; requestId:string; friends:FriendRecord[] }
  | { type:"blocks_list"; requestId:string; blockedUserIds:string[] }
  | { type:"social_operation_ok"; requestId:string }
  | { type:"social_reported"; requestId:string; reportId:string }
  | { type:"chat_message"; requestId:string; message:ChatMessage }
  | { type:"chat_history"; requestId:string; messages:ChatMessage[] }
  | { type:"party_state"; requestId:string; party:PartyState|null }
  | { type:"party_invitations"; requestId:string; invitations:PartyInvitation[] }
  | { type:"party_operation_ok"; requestId:string }
  | { type:"auction_list"; requestId:string; listings:AuctionSummary[] }
  | { type:"auction_state"; requestId:string; listing:AuctionSummary }
  | { type:"auction_history"; requestId:string; transactions:Record<string, unknown>[] }
  | { type:"auction_operation_ok"; requestId:string }
  | { type:"world_event_list"; requestId:string; events:WorldEventSummary[] }
  | { type:"world_event_state"; requestId:string; event:WorldEventSummary }
  | { type:"world_event_reward"; requestId:string; eventId:string; gold:string; items:Record<string,number> }
  | { type:"realm_war_list"; requestId:string; wars:RealmWarSummary[] }
  | { type:"realm_war_state"; requestId:string; war:RealmWarSummary }
  | { type:"guild_battle_list"; requestId:string; battles:GuildBattleSummary[] }
  | { type:"guild_battle_state"; requestId:string; battle:GuildBattleSummary }
  | { type:"endgame_creature_list"; requestId:string; creatures:EndgameCreatureSummary[] }
  | { type:"endgame_creature_state"; requestId:string; creature:EndgameCreatureSummary }
  | { type:"mythic_content_list"; requestId:string; content:MythicContentSummary[] }
  | { type:"territory_season_state"; requestId:string; season:TerritorySeasonSummary|null; standings:TerritorySeasonStanding[] }
  | { type:"error"; code:
      | "INVALID_MESSAGE"|"UNSUPPORTED_MESSAGE"|"AUTH_REQUIRED"|"INVALID_TOKEN"|"INTERNAL_SERVER_ERROR"|"COMBAT_COOLDOWN"|"OUT_OF_RANGE"|"NO_STAMINA"|"NO_AMMO"|"COMBAT_IN_PROGRESS"|"PLAYER_DEAD"|"PLAYER_STUNNED"|"RATE_LIMITED"
      | "RESOURCE_NOT_FOUND"|"RESOURCE_DEPLETED"|"RESOURCE_OUT_OF_RANGE"|"RESOURCE_REQUEST_CONFLICT"|"RESOURCE_NODE_MISMATCH"|"RESOURCE_NODE_UPDATE_FAILED"
      | "CREATURE_TOO_HEALTHY"|"NO_CAPTURE_ORB"|"CREATURE_ALREADY_CAPTURED"|"CREATURE_NOT_FOUND"|"NO_CREATURE_FEED"|"CREATURE_NOT_TAMED"|"INVALID_PARTY_SLOT"
      | "BASE_ALREADY_EXISTS"|"BASE_NOT_FOUND"|"BASE_PERMISSION_DENIED"|"INVALID_BASE_COORDINATES"|"INVALID_BUILDING_TYPE"|"INVALID_BUILDING_LEVEL"
      | "INVALID_BUILDING_POSITION"|"BUILDING_POSITION_OCCUPIED"|"BUILDING_PREREQUISITE_MISSING"|"BUILDING_NOT_FOUND"|"BUILDING_MAX_LEVEL"
      | "INSUFFICIENT_STORAGE"|"STORAGE_CAPACITY_EXCEEDED"|"INVALID_STORAGE_QUANTITY"|"INSUFFICIENT_INVENTORY"|"PLAYER_NOT_FOUND"|"INVALID_WORK_TASK"|"CREATURE_IN_PARTY"|"WORKER_CAPACITY_REACHED"|"INVALID_SHIP_CLASS"|"SHIPYARD_REQUIRED"|"INSUFFICIENT_SHIPYARD_RESOURCES"|"INVALID_SHIP_CARGO"|"INSUFFICIENT_SHIP_CARGO"|"SHIP_CARGO_CAPACITY_EXCEEDED"|"FLEET_NOT_FOUND"|"SHIP_ALREADY_IN_FLEET"|"SHIP_NOT_IN_FLEET"|"FLEET_COMMANDER_REQUIRED"|"INVALID_SAIL_INPUT"|"SHIP_NOT_FOUND"|"SHIP_NOT_ACTIVE"|"INSUFFICIENT_SHIP_FUEL"|"INVALID_CREW_ASSIGNMENT"|"SHIP_CREW_CAPACITY_REACHED"|"CREW_CREATURE_NOT_FOUND"|"CREW_CREATURE_NOT_TAMED"|"CREW_CREATURE_IN_PARTY"|"CREW_ALREADY_ASSIGNED"|"INVALID_NAVAL_TARGET"|"TARGET_SHIP_NOT_ACTIVE"|"NAVAL_TARGET_OUT_OF_RANGE"|"CANNON_COOLDOWN"|"NO_CANNON_AMMO"|"CANNON_OUTSIDE_ARC"|"SHIP_RETREATING"|"TARGET_SHIP_RETREATING"|"BOARDING_OUT_OF_RANGE"|"SHIP_FULL_HEALTH"|"NO_REPAIR_LUMBER"|"SHIP_NOT_ON_FIRE"|"INVALID_WIND"
      | "RECIPE_NOT_FOUND"|"INVENTORY_LIMIT"|"SHOP_ITEM_NOT_FOUND"|"INVALID_PURCHASE_QUANTITY"|"INSUFFICIENT_GOLD"|"INVALID_REQUEST_ID"|"SHOP_REQUEST_CONFLICT"|"TRADE_REQUEST_CONFLICT"|"INVALID_TRADE_REQUEST"|"INVALID_TRADE_PARTICIPANTS"|"INVALID_TRADE_ITEMS"|"INVALID_TRADE_ITEM"|"INVALID_TRADE_QUANTITY"
      | "INVALID_SOCIAL_TARGET"|"SOCIAL_BLOCKED"|"ALREADY_FRIENDS"|"FRIEND_REQUEST_EXISTS"|"CHAT_RATE_LIMITED"|"INVALID_CHAT_CHANNEL"|"INVALID_CHAT_TARGET"|"INVALID_CHAT_CONTEXT"|"PARTY_MEMBERSHIP_REQUIRED"|"ALREADY_IN_PARTY"|"PARTY_NOT_FOUND"|"PARTY_FULL"|"TARGET_IN_PARTY"|"PARTY_INVITATION_NOT_FOUND"|"PARTY_INVITATION_EXISTS"|"PARTY_LEADER_REQUIRED"|"INVALID_PARTY_TARGET"|"PARTY_MEMBER_NOT_FOUND"
      | "INVALID_AUCTION_ITEM"|"INVALID_AUCTION_QUANTITY"|"INVALID_AUCTION_PRICE"|"INVALID_AUCTION_DURATION"|"INVALID_AUCTION_FILTER"|"INVALID_AUCTION_BID"|"AUCTION_NOT_FOUND"|"AUCTION_NOT_ACTIVE"|"AUCTION_SELF_BID"|"AUCTION_BID_TOO_LOW"|"AUCTION_NO_BUY_NOW"|"AUCTION_SELF_BUY"|"AUCTION_OWNER_REQUIRED"|"AUCTION_HAS_BID"
      | "BUILD_FAILED"|"BASE_CREATE_FAILED"|"INVALID_INVASION_ROLE"|"INVASION_ALREADY_PARTICIPATING"|"INVALID_INVASION_THREAT"|"INVALID_INVASION_SOURCE"|"INVASION_ALREADY_ACTIVE"|"INVASION_NOT_FOUND"|"INVASION_NOT_JOINABLE"|"ARMY_NOT_OWNED"|"ARMY_ALREADY_IN_INVASION"|"INVASION_NOT_IN_BATTLE"|"INVASION_NOT_PARTICIPANT"|"INVASION_WAVE_REQUIRED"|"INVASION_WAVE_NOT_FOUND"|"INVASION_WAVE_NOT_ACTIVE"|"INVALID_TERRITORY_COORDINATES"|"TERRITORY_NOT_FOUND"|"INSUFFICIENT_TERRITORY_INFLUENCE"|"INVALID_REPUTATION_DELTA"|"REALM_NOT_FOUND"|"INVALID_TRADE_ROUTE"|"INVALID_TRADE_ROUTE_ENDPOINTS"|"BARRACKS_REQUIRED"|"INVALID_ARMY_UNIT_TYPE"|"INVALID_TRAINING_QUANTITY"|"INSUFFICIENT_BASE_RESOURCES"|"ARMY_NOT_FOUND"|"CREATURE_ALREADY_GARRISONED"|"INVALID_ARMY_ASSIGNMENT"|"INVALID_ARMY_FORMATION"|"GUILD_PERMISSION_DENIED"|"GUILD_MEMBER_NOT_FOUND"|"COMMANDER_NOT_NOMINATED"|"COMMANDER_PERMISSION_DENIED"|"INVALID_COMMANDER_ORDER"|"ARMY_UNIT_NOT_FOUND"|"INVALID_COMMAND_TARGET"|"DEFENDER_ARMY_NOT_FOUND"|"INVALID_BATTLE_ARMIES"|"BATTLE_NOT_FOUND"|"BATTLE_NOT_ACTIVE"|"BATTLE_UNIT_NOT_FOUND"|"INVALID_FORMATION_SLOT"|"INVALID_DEFENSIVE_STRUCTURE"|"INVALID_DEFENSE_POSITION"|"DEFENSE_POSITION_OCCUPIED"|"BATTLE_UNIT_NOT_DEPLOYED"|"ARMY_UNIT_TARGET_REQUIRED"|"INVALID_BATTLE_TARGET"|"DEFENDER_GARRISON_NOT_FOUND"|"NO_AVAILABLE_TRAP"|"CANNON_UNIT_REQUIRED"|"DEFENSE_STRUCTURE_REQUIRED"|"DEFENSE_STRUCTURE_NOT_FOUND"|"BREEDING_PEN_NOT_FOUND"|"BREEDING_CAPACITY_REACHED"|"INVALID_GUILD_NAME"|"INVALID_GUILD_TAG"|"GUILD_NAME_OR_TAG_EXISTS"|"GUILD_HALL_REQUIRED"|"ALREADY_IN_GUILD"|"GUILD_NOT_FOUND"|"GUILD_MEMBERSHIP_REQUIRED"|"INVALID_GUILD_INVITEE"|"TARGET_ALREADY_IN_GUILD"|"GUILD_INVITATION_NOT_FOUND"|"GUILD_MASTER_CANNOT_LEAVE"|"INVALID_GUILD_MEMBER"|"GUILD_MASTER_PROTECTED"|"INVALID_GUILD_RANK"|"INVALID_GUILD_PERMISSION"|"INVALID_GUILD_INFRASTRUCTURE"|"INVALID_GUILD_BANK_QUANTITY"|"INVALID_GUILD_BANK_DEPOSIT"|"INVALID_GUILD_BANK_WITHDRAW"|"INSUFFICIENT_GUILD_BANK"|"GUILD_QUEST_NOT_FOUND"|"GUILD_INFRASTRUCTURE_MAX"|"BREEDING_PEN_BUSY"|"INVALID_BREEDING_DURATION"|"BREEDING_PARENTS_MUST_DIFFER"|"INCOMPATIBLE_BREEDING_PARENTS"|"BREEDING_GENERATION_LIMIT"|"POPULATION_LIMIT_REACHED"|"NO_BREEDING_FEED"|"BREEDING_PARENT_MISSING"|"STORAGE_UPDATE_FAILED"|"UPGRADE_FAILED"|"PERMISSION_UPDATE_FAILED"|"WORKER_UPDATE_FAILED"|"PRIORITY_UPDATE_FAILED" };

function isSafeInteger(value:unknown):value is number{return typeof value==="number"&&Number.isSafeInteger(value);}
function isFiniteNumber(value:unknown):value is number{return typeof value==="number"&&Number.isFinite(value);}
function requestId(value:unknown):value is string{return typeof value==="string"&&value.length>0&&value.length<=64;}
function recordValue(value:unknown):value is Record<string,unknown>{return typeof value==="object"&&value!==null&&!Array.isArray(value);}

const isAuctionRarity = (value: unknown): value is AuctionRarity => typeof value === "string" && ["common","uncommon","rare","epic","legendary","mythic"].includes(value);
const isAuctionCategory = (value: unknown): value is AuctionCategory => typeof value === "string" && ["resource","upgrade","defence","equipment","consumable","other"].includes(value);

const isChatChannel = (value: unknown): value is "local"|"region"|"party"|"guild"|"trade"|"global"|"system"|"whisper" => typeof value === "string" && ["local","region","party","guild","trade","global","system","whisper"].includes(value);

export function parseClientMessage(raw:string):ClientMessage|null{
  try{
    const value:unknown=JSON.parse(raw);
    if(typeof value!=="object"||value===null||!("type" in value))return null;
    const type=(value as {type?:unknown}).type;
    if(type==="ping")return {type:"ping"};
    if(type==="auth"){const token=(value as {token?:unknown}).token;return typeof token==="string"&&token.length>0&&token.length<=4096?{type:"auth",token}:null;}
    if(type==="subscribe_chunks"){
      const id=(value as {requestId?:unknown}).requestId,chunks=(value as {chunks?:unknown}).chunks;
      if(!requestId(id)||!Array.isArray(chunks)||chunks.length===0||chunks.length>9)return null;
      const coordinates:ChunkCoordinate[]=[]; for(const chunk of chunks){if(typeof chunk!=="object"||chunk===null)return null;const x=(chunk as {x?:unknown}).x,y=(chunk as {y?:unknown}).y;if(!isSafeInteger(x)||!isSafeInteger(y)||Math.abs(x)>1_000_000||Math.abs(y)>1_000_000)return null;coordinates.push({x,y});}
      return {type:"subscribe_chunks",requestId:id,chunks:coordinates};
    }
    if(type==="move"){const dx=(value as {dx?:unknown}).dx,dy=(value as {dy?:unknown}).dy,dt=(value as {dt?:unknown}).dt;if(!isFiniteNumber(dx)||!isFiniteNumber(dy)||!isFiniteNumber(dt)||Math.abs(dx)>1||Math.abs(dy)>1||dt<0||dt>0.25)return null;return {type:"move",dx,dy,dt};}
    if(type==="select_hotbar"){const slot=(value as {slot?:unknown}).slot;return isSafeInteger(slot)&&slot>=0&&slot<8?{type:"select_hotbar",slot}:null;}
    if(type==="dodge"){const facingX=(value as {facingX?:unknown}).facingX,facingY=(value as {facingY?:unknown}).facingY;if(!isFiniteNumber(facingX)||!isFiniteNumber(facingY)||Math.abs(facingX)>1||Math.abs(facingY)>1||(facingX===0&&facingY===0))return null;return {type:"dodge",facingX,facingY};}
    if(type==="block"){const active=(value as {active?:unknown}).active;return typeof active==="boolean"?{type:"block",active}:null;}
    if(type==="capture"||type==="tame"||type==="set_creature_party"||type==="set_creature_ai"){
      const id=(value as {requestId?:unknown}).requestId;if(!requestId(id))return null;
      if(type==="capture"){const targetId=(value as {targetId?:unknown}).targetId;return typeof targetId==="string"&&targetId.length>0&&targetId.length<=128?{type:"capture",requestId:id,targetId}:null;}
      const creatureId=(value as {creatureId?:unknown}).creatureId;if(typeof creatureId!=="string"||creatureId.length===0||creatureId.length>64)return null;
      if(type==="tame")return {type:"tame",requestId:id,creatureId};
      if(type==="set_creature_party"){const slot=(value as {slot?:unknown}).slot;return slot===null||(isSafeInteger(slot)&&slot>=0&&slot<3)?{type:"set_creature_party",requestId:id,creatureId,slot}:null;}
      const mode=(value as {mode?:unknown}).mode;return mode==="follow"||mode==="assist"||mode==="stay"?{type:"set_creature_ai",requestId:id,creatureId,mode}:null;
    }
    if(type==="create_base"||type==="build"){
      const id=(value as {requestId?:unknown}).requestId;if(!requestId(id))return null;
      if(type==="create_base"){const name=(value as {name?:unknown}).name,x=(value as {x?:unknown}).x,y=(value as {y?:unknown}).y;return typeof name==="string"&&name.length<=64&&isSafeInteger(x)&&isSafeInteger(y)&&Math.abs(x)<=1_000_000&&Math.abs(y)<=1_000_000?{type:"create_base",requestId:id,name,x,y}:null;}
      const buildingType=(value as {buildingType?:unknown}).buildingType,level=(value as {level?:unknown}).level,gridX=(value as {gridX?:unknown}).gridX,gridY=(value as {gridY?:unknown}).gridY;return typeof buildingType==="string"&&buildingType.length>0&&buildingType.length<=32&&isSafeInteger(level)&&isSafeInteger(gridX)&&isSafeInteger(gridY)&&Math.abs(gridX)<=128&&Math.abs(gridY)<=128?{type:"build",requestId:id,buildingType,level,gridX,gridY}:null;
    }
    if(type==="upgrade_building"){const id=(value as {requestId?:unknown}).requestId,b=(value as {buildingId?:unknown}).buildingId;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64&&b.length>0&&b.length<=64?{type:"upgrade_building",requestId:id,buildingId:b}:null;}
    if(type==="storage"){const id=(value as {requestId?:unknown}).requestId,changes=(value as {changes?:unknown}).changes;if(!requestId(id)||typeof changes!=="object"||changes===null||Array.isArray(changes))return null;const next:Record<string,number>={};const entries=Object.entries(changes);if(entries.length===0||entries.length>32)return null;for(const [key,delta] of entries){if(key.length===0||key.length>64||!isSafeInteger(delta)||Math.abs(delta)>1_000_000_000)return null;next[key]=delta;}return {type:"storage",requestId:id,changes:next};}
    if(type==="set_base_permission"){const id=(value as {requestId?:unknown}).requestId,targetUserId=(value as {targetUserId?:unknown}).targetUserId,permission=(value as {permission?:unknown}).permission,enabled=(value as {enabled?:unknown}).enabled;return requestId(id)&&typeof targetUserId==="string"&&targetUserId.length>0&&targetUserId.length<=64&&typeof permission==="string"&&permission.length>0&&permission.length<=32&&typeof enabled==="boolean"?{type:"set_base_permission",requestId:id,targetUserId,permission,enabled}:null;}
    if(type==="assign_worker"){const id=(value as {requestId?:unknown}).requestId,creatureId=(value as {creatureId?:unknown}).creatureId,buildingId=(value as {buildingId?:unknown}).buildingId,task=(value as {task?:unknown}).task;return requestId(id)&&typeof creatureId==="string"&&creatureId.length>0&&creatureId.length<=64&&typeof buildingId==="string"&&buildingId.length>0&&buildingId.length<=64&&typeof task==="string"&&task.length>0&&task.length<=32?{type:"assign_worker",requestId:id,creatureId,buildingId,task}:null;}
    if(type==="set_work_priorities"){const id=(value as {requestId?:unknown}).requestId,priorities=(value as {priorities?:unknown}).priorities;if(!requestId(id)||!Array.isArray(priorities)||priorities.length>6||priorities.some(p=>typeof p!=="string"||p.length===0||p.length>32))return null;return {type:"set_work_priorities",requestId:id,priorities:priorities as string[]};}
    if(type==="gather_resource"){const id=(value as {requestId?:unknown}).requestId,resourceId=(value as {resourceId?:unknown}).resourceId;return requestId(id)&&typeof resourceId==="string"&&resourceId.length>0&&resourceId.length<=128?{type:"gather_resource",requestId:id,resourceId}:null;}
    if(type==="craft"){const id=(value as {requestId?:unknown}).requestId,recipeId=(value as {recipeId?:unknown}).recipeId;return requestId(id)&&typeof recipeId==="string"&&recipeId.length>0&&recipeId.length<=64?{type:"craft",requestId:id,recipeId}:null;}
    if(type==="shop_purchase"){const id=(value as {requestId?:unknown}).requestId,itemId=(value as {itemId?:unknown}).itemId,quantity=(value as {quantity?:unknown}).quantity;return requestId(id)&&typeof itemId==="string"&&itemId.length>0&&itemId.length<=64&&isSafeInteger(quantity)&&quantity>=1&&quantity<=100?{type:"shop_purchase",requestId:id,itemId,quantity}:null;}
    if(type==="trade"){
      const id=(value as {requestId?:unknown}).requestId,toUserId=(value as {toUserId?:unknown}).toUserId,gold=(value as {gold?:unknown}).gold,items=(value as {items?:unknown}).items;
      if(!requestId(id)||typeof toUserId!=="string"||toUserId.length===0||toUserId.length>64||typeof gold!=="string"||gold.length===0||gold.length>32||!Array.isArray(items)||items.length>32)return null;
      const normalized:Array<{itemId:string;quantity:number}>=[];
      for(const item of items){if(typeof item!=="object"||item===null||Array.isArray(item))return null;const itemId=(item as {itemId?:unknown}).itemId,quantity=(item as {quantity?:unknown}).quantity;if(typeof itemId!=="string"||itemId.length===0||itemId.length>128||!isSafeInteger(quantity)||quantity<1||quantity>1_000_000)return null;normalized.push({itemId,quantity});}
      return {type:"trade",requestId:id,toUserId,gold,items:normalized};
    }
    if(type==="start_breeding"){const id=(value as {requestId?:unknown}).requestId,baseId=(value as {baseId?:unknown}).baseId,penBuildingId=(value as {penBuildingId?:unknown}).penBuildingId,parentAId=(value as {parentAId?:unknown}).parentAId,parentBId=(value as {parentBId?:unknown}).parentBId,durationMs=(value as {durationMs?:unknown}).durationMs;if(!requestId(id)||![baseId,penBuildingId,parentAId,parentBId].every(v=>typeof v==="string"&&v.length>0&&v.length<=64)||(durationMs!==undefined&&(!isSafeInteger(durationMs)||durationMs<=0||durationMs>86400000)))return null;return {type:"start_breeding",requestId:id,baseId:baseId as string,penBuildingId:penBuildingId as string,parentAId:parentAId as string,parentBId:parentBId as string,...(durationMs===undefined?{}:{durationMs})};}
    if(type==="list_breeding"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type:"list_breeding",requestId:id}:null;}
    if(type==="list_territory_season"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type,requestId:id}:null;}
    if(type==="list_realm_wars"||type==="list_guild_battles"||type==="list_endgame_creatures"||type==="list_mythic_content"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type,requestId:id}:null;}
    if(type==="create_realm_war"){const id=(value as {requestId?:unknown}).requestId,a=(value as {attackerRealmId?:unknown}).attackerRealmId,d=(value as {defenderRealmId?:unknown}).defenderRealmId,t=(value as {targetTerritoryId?:unknown}).targetTerritoryId;return requestId(id)&&typeof a==="string"&&a.length>0&&a.length<=64&&typeof d==="string"&&d.length>0&&d.length<=64&&typeof t==="string"&&t.length>0&&t.length<=64?{type,requestId:id,attackerRealmId:a,defenderRealmId:d,targetTerritoryId:t}:null;}
    if(type==="join_realm_war"){const id=(value as {requestId?:unknown}).requestId,w=(value as {warId?:unknown}).warId,g=(value as {guildId?:unknown}).guildId,r=(value as {realmId?:unknown}).realmId;return requestId(id)&&typeof w==="string"&&w.length>0&&w.length<=64&&typeof g==="string"&&g.length>0&&g.length<=64&&typeof r==="string"&&r.length>0&&r.length<=64?{type,requestId:id,warId:w,guildId:g,realmId:r}:null;}
    if(type==="realm_war_action"){const id=(value as {requestId?:unknown}).requestId,w=(value as {warId?:unknown}).warId,g=(value as {guildId?:unknown}).guildId,a=(value as {armyId?:unknown}).armyId;return requestId(id)&&typeof w==="string"&&w.length>0&&w.length<=64&&typeof g==="string"&&g.length>0&&g.length<=64&&typeof a==="string"&&a.length>0&&a.length<=64?{type,requestId:id,warId:w,guildId:g,armyId:a}:null;}
    if(type==="create_guild_battle"){const id=(value as {requestId?:unknown}).requestId,a=(value as {attackerGuildId?:unknown}).attackerGuildId,d=(value as {defenderGuildId?:unknown}).defenderGuildId,t=(value as {targetTerritoryId?:unknown}).targetTerritoryId;return requestId(id)&&typeof a==="string"&&a.length>0&&a.length<=64&&typeof d==="string"&&d.length>0&&d.length<=64&&typeof t==="string"&&t.length>0&&t.length<=64?{type,requestId:id,attackerGuildId:a,defenderGuildId:d,targetTerritoryId:t}:null;}
    if(type==="join_guild_battle"||type==="guild_battle_action"){const id=(value as {requestId?:unknown}).requestId,b=(value as {battleId?:unknown}).battleId,a=(value as {armyId?:unknown}).armyId;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64&&typeof a==="string"&&a.length>0&&a.length<=64?{type,requestId:id,battleId:b,armyId:a}:null;}
    if(type==="engage_endgame_creature"){const id=(value as {requestId?:unknown}).requestId,c=(value as {creatureId?:unknown}).creatureId;return requestId(id)&&typeof c==="string"&&c.length>0&&c.length<=64?{type,requestId:id,creatureId:c}:null;}
    if(type==="list_realms"||type==="list_territories"||type==="list_realm_fortresses"||type==="my_realm_reputation"||type==="list_trade_routes"||type==="tick_realm_ai"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type,requestId:id}:null;}
    if(type==="territory_at"){const id=(value as {requestId?:unknown}).requestId,x=(value as {x?:unknown}).x,y=(value as {y?:unknown}).y;return requestId(id)&&isSafeInteger(x)&&isSafeInteger(y)?{type:"territory_at",requestId:id,x,y}:null;}
    if(type==="claim_guild_territory"){const id=(value as {requestId?:unknown}).requestId,t=(value as {territoryId?:unknown}).territoryId,g=(value as {guildId?:unknown}).guildId;return requestId(id)&&typeof t==="string"&&t.length>0&&t.length<=64&&typeof g==="string"&&g.length>0&&g.length<=64?{type:"claim_guild_territory",requestId:id,territoryId:t,guildId:g}:null;}
    if(type==="change_realm_reputation"){const id=(value as {requestId?:unknown}).requestId,realm=(value as {realm?:unknown}).realm,delta=(value as {delta?:unknown}).delta;return requestId(id)&&typeof realm==="string"&&isSafeInteger(delta)&&Math.abs(delta)<=1000?{type:"change_realm_reputation",requestId:id,realm,delta}:null;}
    if(type==="create_trade_route"){const id=(value as {requestId?:unknown}).requestId,s=(value as {sourceTerritoryId?:unknown}).sourceTerritoryId,d=(value as {destinationTerritoryId?:unknown}).destinationTerritoryId,k=(value as {resourceKey?:unknown}).resourceKey,q=(value as {quantity?:unknown}).quantity,t=(value as {travelSeconds?:unknown}).travelSeconds,g=(value as {guildId?:unknown}).guildId,r=(value as {realmId?:unknown}).realmId;return requestId(id)&&typeof s==="string"&&typeof d==="string"&&d.length>0&&d.length<=64&&typeof k==="string"&&typeof q==="string"&&/^\d+$/.test(q)&&isSafeInteger(t)&&t>0&&t<=604800&&(g===null||typeof g==="string"&&g.length>0&&g.length<=64)&&(r===null||typeof r==="string"&&r.length>0&&r.length<=64)?{type:"create_trade_route",requestId:id,sourceTerritoryId:s,destinationTerritoryId:d,resourceKey:k,quantity:q,travelSeconds:t,guildId:g,realmId:r}:null;}
    if(type==="list_invasions"||type==="get_invasion_waves"){const id=(value as {requestId?:unknown}).requestId;if(type==="list_invasions"){const territoryId=(value as {territoryId?:unknown}).territoryId;return requestId(id)&&(territoryId===null||(typeof territoryId==="string"&&territoryId.length>0&&territoryId.length<=64))?{type:"list_invasions",requestId:id,territoryId}:null;}const invasionId=(value as {invasionId?:unknown}).invasionId;return requestId(id)&&typeof invasionId==="string"&&invasionId.length>0&&invasionId.length<=64?{type:"get_invasion_waves",requestId:id,invasionId}:null;}
    if(type==="join_invasion"){const id=(value as {requestId?:unknown}).requestId,invasionId=(value as {invasionId?:unknown}).invasionId,armyId=(value as {armyId?:unknown}).armyId,role=(value as {role?:unknown}).role;const roles=["tank","damage","support","scout","commander","logistics"];return requestId(id)&&typeof invasionId==="string"&&invasionId.length>0&&invasionId.length<=64&&typeof armyId==="string"&&armyId.length>0&&armyId.length<=64&&typeof role==="string"&&roles.includes(role)?{type:"join_invasion",requestId:id,invasionId,armyId,role:role as InvasionRole}:null;}
    if(type==="invasion_action"){const id=(value as {requestId?:unknown}).requestId,invasionId=(value as {invasionId?:unknown}).invasionId,action=(value as {action?:unknown}).action,waveId=(value as {waveId?:unknown}).waveId;return requestId(id)&&typeof invasionId==="string"&&invasionId.length>0&&invasionId.length<=64&&typeof action==="string"&&["attack","reinforce","retreat"].includes(action)&&(waveId===null||(typeof waveId==="string"&&waveId.length>0&&waveId.length<=64))?{type:"invasion_action",requestId:id,invasionId,action:action as "attack"|"reinforce"|"retreat",waveId}:null;}
    if(type==="create_guild"){const id=(value as {requestId?:unknown}).requestId,name=(value as {name?:unknown}).name,tag=(value as {tag?:unknown}).tag;return requestId(id)&&typeof name==="string"&&name.length<=64&&typeof tag==="string"&&tag.length<=8?{type:"create_guild",requestId:id,name,tag}:null;}
    if(type==="get_guild"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type:"get_guild",requestId:id}:null;}
    if(type==="list_guild_invitations"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type:"list_guild_invitations",requestId:id}:null;}
    if(type==="invite_guild_member"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,targetUserId=(value as {targetUserId?:unknown}).targetUserId;return requestId(id)&&typeof guildId==="string"&&guildId.length>0&&typeof targetUserId==="string"&&targetUserId.length>0?{type:"invite_guild_member",requestId:id,guildId,targetUserId}:null;}
    if(type==="accept_guild_invite"||type==="decline_guild_invite"){const id=(value as {requestId?:unknown}).requestId,invitationId=(value as {invitationId?:unknown}).invitationId;return requestId(id)&&typeof invitationId==="string"&&invitationId.length>0?{type,requestId:id,invitationId}:null;}
    if(type==="leave_guild"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId;return requestId(id)&&typeof guildId==="string"&&guildId.length>0?{type:"leave_guild",requestId:id,guildId}:null;}
    if(type==="remove_guild_member"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,targetUserId=(value as {targetUserId?:unknown}).targetUserId;return requestId(id)&&typeof guildId==="string"&&typeof targetUserId==="string"&&guildId.length>0&&targetUserId.length>0?{type:"remove_guild_member",requestId:id,guildId,targetUserId}:null;}
    if(type==="set_guild_rank"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,targetUserId=(value as {targetUserId?:unknown}).targetUserId,rank=(value as {rank?:unknown}).rank;return requestId(id)&&typeof guildId==="string"&&typeof targetUserId==="string"&&typeof rank==="string"&&rank.length>0&&rank.length<=16?{type:"set_guild_rank",requestId:id,guildId,targetUserId,rank}:null;}
    if(type==="set_guild_permission"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,rank=(value as {rank?:unknown}).rank,permission=(value as {permission?:unknown}).permission,enabled=(value as {enabled?:unknown}).enabled;return requestId(id)&&typeof guildId==="string"&&typeof rank==="string"&&typeof permission==="string"&&typeof enabled==="boolean"?{type:"set_guild_permission",requestId:id,guildId,rank,permission,enabled}:null;}
    if(type==="guild_bank"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId;return requestId(id)&&typeof guildId==="string"&&guildId.length>0?{type:"guild_bank",requestId:id,guildId}:null;}
    if(type==="guild_bank_deposit"||type==="guild_bank_withdraw"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,itemId=(value as {itemId?:unknown}).itemId,quantity=(value as {quantity?:unknown}).quantity,gold=(value as {gold?:unknown}).gold;return requestId(id)&&typeof guildId==="string"&&typeof itemId==="string"&&typeof quantity==="number"&&isSafeInteger(quantity)&&quantity>=0&&quantity<=1000000&&typeof gold==="string"&&gold.length<=32?{type,requestId:id,guildId,itemId,quantity,gold}:null;}
    if(type==="build_guild_infrastructure"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,structureType=(value as {structureType?:unknown}).structureType;return requestId(id)&&typeof guildId==="string"&&typeof structureType==="string"&&structureType.length>0&&structureType.length<=32?{type:"build_guild_infrastructure",requestId:id,guildId,structureType}:null;}

    if(type==="create_army"){const id=(value as {requestId?:unknown}).requestId,name=(value as {name?:unknown}).name;return requestId(id)&&typeof name==="string"&&name.length<=64?{type:"create_army",requestId:id,name}:null;}
    if(type==="list_armies"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type:"list_armies",requestId:id}:null;}
    if(type==="train_army"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,unitType=(value as {unitType?:unknown}).unitType,quantity=(value as {quantity?:unknown}).quantity;return requestId(id)&&typeof armyId==="string"&&typeof unitType==="string"&&isSafeInteger(quantity)&&quantity>0&&quantity<=1000?{type:"train_army",requestId:id,armyId,unitType,quantity}:null;}
    if(type==="garrison_army"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,baseId=(value as {baseId?:unknown}).baseId;return requestId(id)&&typeof armyId==="string"&&typeof baseId==="string"?{type:"garrison_army",requestId:id,armyId,baseId}:null;}
    if(type==="add_army_creature"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,creatureId=(value as {creatureId?:unknown}).creatureId;return requestId(id)&&typeof armyId==="string"&&typeof creatureId==="string"?{type:"add_army_creature",requestId:id,armyId,creatureId}:null;}
    if(type==="set_army_assignment"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,assignment=(value as {assignment?:unknown}).assignment;return requestId(id)&&typeof armyId==="string"&&typeof assignment==="string"?{type:"set_army_assignment",requestId:id,armyId,assignment}:null;}
    if(type==="set_army_formation"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,name=(value as {name?:unknown}).name,formationType=(value as {formationType?:unknown}).formationType,layout=(value as {layout?:unknown}).layout;return requestId(id)&&typeof armyId==="string"&&typeof name==="string"&&typeof formationType==="string"&&recordValue(layout)?{type:"set_army_formation",requestId:id,armyId,name,formationType,layout}:null;}
    if(type==="nominate_commander"){const id=(value as {requestId?:unknown}).requestId,guildId=(value as {guildId?:unknown}).guildId,targetUserId=(value as {targetUserId?:unknown}).targetUserId;return requestId(id)&&typeof guildId==="string"&&typeof targetUserId==="string"?{type:"nominate_commander",requestId:id,guildId,targetUserId}:null;}
    if(type==="assign_army_commander"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,commanderUserId=(value as {commanderUserId?:unknown}).commanderUserId;return requestId(id)&&typeof armyId==="string"&&typeof commanderUserId==="string"?{type:"assign_army_commander",requestId:id,armyId,commanderUserId}:null;}
    if(type==="issue_army_order"){const id=(value as {requestId?:unknown}).requestId,armyId=(value as {armyId?:unknown}).armyId,battleId=(value as {battleId?:unknown}).battleId,orderType=(value as {orderType?:unknown}).orderType,targetUnitId=(value as {targetUnitId?:unknown}).targetUnitId,targetX=(value as {targetX?:unknown}).targetX,targetY=(value as {targetY?:unknown}).targetY,payload=(value as {payload?:unknown}).payload;return requestId(id)&&typeof armyId==="string"&&(battleId===null||typeof battleId==="string")&&(targetUnitId===null||typeof targetUnitId==="string")&&(targetX===null||isFiniteNumber(targetX))&&(targetY===null||isFiniteNumber(targetY))&&typeof orderType==="string"&&recordValue(payload)?{type:"issue_army_order",requestId:id,armyId,battleId,orderType,targetUnitId,targetX,targetY,payload}:null;}
    if(type==="create_army_battle"){const id=(value as {requestId?:unknown}).requestId,a=(value as {attackerArmyId?:unknown}).attackerArmyId,d=(value as {defenderArmyId?:unknown}).defenderArmyId,x=(value as {targetX?:unknown}).targetX,y=(value as {targetY?:unknown}).targetY;return requestId(id)&&typeof a==="string"&&a.length>0&&a.length<=64&&(d===null||typeof d==="string"&&d.length>0&&d.length<=64)&&isFiniteNumber(x)&&isFiniteNumber(y)?{type:"create_army_battle",requestId:id,attackerArmyId:a,defenderArmyId:d,targetX:x,targetY:y}:null;}
    if(type==="deploy_battle_unit"){const id=(value as {requestId?:unknown}).requestId,b=(value as {battleId?:unknown}).battleId,u=(value as {unitId?:unknown}).unitId,s=(value as {formationSlot?:unknown}).formationSlot;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64&&typeof u==="string"&&isSafeInteger(s)&&s>=0&&s<=999?{type:"deploy_battle_unit",requestId:id,battleId:b,unitId:u,formationSlot:s}:null;}
    if(type==="army_tactical_action"){const id=(value as {requestId?:unknown}).requestId,b=(value as {battleId?:unknown}).battleId,u=(value as {unitId?:unknown}).unitId,a=(value as {actionType?:unknown}).actionType,t=(value as {targetUnitId?:unknown}).targetUnitId;const actions=["ability","retreat","fire_cannon","deploy_trap","reinforce"];return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64&&typeof u==="string"&&typeof a==="string"&&a.length>0&&a.length<=64&&actions.includes(a)&&(t===null||typeof t==="string"&&t.length>0&&t.length<=64)?{type:"army_tactical_action",requestId:id,battleId:b,unitId:u,actionType:a as "ability"|"retreat"|"fire_cannon"|"deploy_trap"|"reinforce",targetUnitId:t}:null;}
    if(type==="execute_battle_turn"||type==="get_army_battle"){const id=(value as {requestId?:unknown}).requestId,b=(value as {battleId?:unknown}).battleId;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64?{type,requestId:id,battleId:b}:null;}
    if(type==="build_defense"){const id=(value as {requestId?:unknown}).requestId,b=(value as {baseId?:unknown}).baseId,s=(value as {structureType?:unknown}).structureType,x=(value as {gridX?:unknown}).gridX,y=(value as {gridY?:unknown}).gridY;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64&&typeof s==="string"&&isSafeInteger(x)&&isSafeInteger(y)?{type:"build_defense",requestId:id,baseId:b,structureType:s,gridX:x,gridY:y}:null;}
    if(type==="list_defenses"){const id=(value as {requestId?:unknown}).requestId,b=(value as {baseId?:unknown}).baseId;return requestId(id)&&typeof b==="string"&&b.length>0&&b.length<=64?{type:"list_defenses",requestId:id,baseId:b}:null;}
    if(type==="create_ship"){const id=(value as {requestId?:unknown}).requestId,name=(value as {name?:unknown}).name,shipClass=(value as {shipClass?:unknown}).shipClass;if(!requestId(id)||typeof name!=="string"||name.length>64||typeof shipClass!=="string"||shipClass.length===0||shipClass.length>32)return null;return {type:"create_ship",requestId:id,name,shipClass};}
    if(type==="list_ships"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type:"list_ships",requestId:id}:null;}
    if(type==="ship_inventory"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId;return requestId(id)&&typeof shipId==="string"&&shipId.length>0&&shipId.length<=64?{type:"ship_inventory",requestId:id,shipId}:null;}
    if(type==="ship_cargo"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId,itemId=(value as {itemId?:unknown}).itemId,quantity=(value as {quantity?:unknown}).quantity;return requestId(id)&&typeof shipId==="string"&&shipId.length>0&&shipId.length<=64&&typeof itemId==="string"&&itemId.length>0&&itemId.length<=128&&isSafeInteger(quantity)&&quantity!==0&&Math.abs(quantity)<=1_000_000?{type:"ship_cargo",requestId:id,shipId,itemId,quantity}:null;}
    if(type==="create_fleet"){const id=(value as {requestId?:unknown}).requestId,name=(value as {name?:unknown}).name,shipId=(value as {shipId?:unknown}).shipId;return requestId(id)&&typeof name==="string"&&name.length>0&&name.length<=64&&typeof shipId==="string"&&shipId.length>0&&shipId.length<=64?{type:"create_fleet",requestId:id,name,shipId}:null;}
    if(type==="list_fleets"){const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type:"list_fleets",requestId:id}:null;}
    if(type==="add_fleet_ship"||type==="remove_fleet_ship"){const id=(value as {requestId?:unknown}).requestId,fleetId=(value as {fleetId?:unknown}).fleetId,shipId=(value as {shipId?:unknown}).shipId;return requestId(id)&&typeof fleetId==="string"&&fleetId.length>0&&fleetId.length<=64&&typeof shipId==="string"&&shipId.length>0&&shipId.length<=64?{type,requestId:id,fleetId,shipId}:null;}
    if(type==="sail"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId,dx=(value as {dx?:unknown}).dx,dy=(value as {dy?:unknown}).dy,dt=(value as {dt?:unknown}).dt;return requestId(id)&&typeof shipId==="string"&&shipId.length>0&&shipId.length<=64&&isFiniteNumber(dx)&&isFiniteNumber(dy)&&isFiniteNumber(dt)&&dt>0&&dt<=60&&Math.abs(dx)<=1&&Math.abs(dy)<=1&&(dx!==0||dy!==0)?{type:"sail",requestId:id,shipId,dx,dy,dt}:null;}
    if(type==="assign_ship_crew"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId,creatureId=(value as {creatureId?:unknown}).creatureId,role=(value as {role?:unknown}).role,skill=(value as {skill?:unknown}).skill,morale=(value as {morale?:unknown}).morale;return requestId(id)&&typeof shipId==="string"&&typeof creatureId==="string"&&typeof role==="string"&&shipId.length>0&&creatureId.length>0&&role.length>0&&role.length<=32&&isSafeInteger(skill)&&skill>=1&&skill<=100&&isSafeInteger(morale)&&morale>=0&&morale<=100?{type:"assign_ship_crew",requestId:id,shipId,creatureId,role,skill,morale}:null;}
    if(type==="fire_cannon"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId,targetShipId=(value as {targetShipId?:unknown}).targetShipId;return requestId(id)&&typeof shipId==="string"&&typeof targetShipId==="string"&&shipId.length>0&&targetShipId.length>0?{type:"fire_cannon",requestId:id,shipId,targetShipId}:null;}
    if(type==="assign_ship_npc_crew"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId,npcType=(value as {npcType?:unknown}).npcType,role=(value as {role?:unknown}).role,skill=(value as {skill?:unknown}).skill,morale=(value as {morale?:unknown}).morale;return requestId(id)&&typeof shipId==="string"&&shipId.length>0&&typeof npcType==="string"&&["pirate","mermaid","dragon","npc_specialist"].includes(npcType)&&typeof role==="string"&&role.length>0&&role.length<=32&&isSafeInteger(skill)&&skill>=1&&skill<=100&&isSafeInteger(morale)&&morale>=0&&morale<=100?{type:"assign_ship_npc_crew",requestId:id,shipId,npcType:npcType as "pirate"|"mermaid"|"dragon"|"npc_specialist",role,skill,morale}:null;}
    if(type==="board_ship"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId,targetShipId=(value as {targetShipId?:unknown}).targetShipId;return requestId(id)&&typeof shipId==="string"&&typeof targetShipId==="string"&&shipId.length>0&&targetShipId.length>0?{type:"board_ship",requestId:id,shipId,targetShipId}:null;}
    if(type==="repair_ship"||type==="retreat_ship"||type==="fight_ship_fire"){const id=(value as {requestId?:unknown}).requestId,shipId=(value as {shipId?:unknown}).shipId;return requestId(id)&&typeof shipId==="string"&&shipId.length>0&&shipId.length<=64?{type,requestId:id,shipId}:null;}
    if(type==="attack"){
      const id=(value as {requestId?:unknown}).requestId,targetId=(value as {targetId?:unknown}).targetId,facingX=(value as {facingX?:unknown}).facingX,facingY=(value as {facingY?:unknown}).facingY;
      if(!requestId(id)||typeof targetId!=="string"||targetId.length===0||targetId.length>128||!isFiniteNumber(facingX)||!isFiniteNumber(facingY)||Math.abs(facingX)>1||Math.abs(facingY)>1||(facingX===0&&facingY===0))return null;
      return {type:"attack",requestId:id,targetId,facingX,facingY};
    }
    if(type==="list_friends"||type==="list_blocks"||type==="create_party"||type==="get_party"||type==="party_invitations"||type==="party_leave"||type==="auction_history"){
      const id=(value as {requestId?:unknown}).requestId;return requestId(id)?{type,requestId:id}:null;
    }
    if(type==="add_friend"||type==="remove_friend"||type==="block_user"||type==="unblock_user"||type==="party_invite"||type==="party_kick"||type==="party_accept"||type==="auction_bid"||type==="auction_buy_now"||type==="auction_cancel"){
      const id=(value as {requestId?:unknown}).requestId;if(!requestId(id))return null;
      const key=type==="party_accept"?"invitationId":type==="auction_bid"||type==="auction_buy_now"||type==="auction_cancel"?"listingId":"targetUserId";
      const v=(value as Record<string,unknown>)[key];if(typeof v!=="string"||v.length===0||v.length>128)return null;
      if(type==="auction_bid"){const amount=(value as {amount?:unknown}).amount;return typeof amount==="string"&&amount.length>0?{type,requestId:id,listingId:v,amount}:null;}
      return {...value} as ClientMessage;
    }
    if(type==="report_user"){
      const id=(value as {requestId?:unknown}).requestId,target=(value as {targetUserId?:unknown}).targetUserId,reason=(value as {reason?:unknown}).reason,details=(value as {details?:unknown}).details;
      return requestId(id)&&typeof target==="string"&&target.length>0&&target.length<=128&&typeof reason==="string"&&reason.length>0&&reason.length<=32&&typeof details==="string"&&details.length<=512?{type:"report_user",requestId:id,targetUserId:target,reason,details}:null;
    }
    if(type==="chat_send"){
      const id=(value as {requestId?:unknown}).requestId,ch=(value as {channel?:unknown}).channel,body=(value as {body?:unknown}).body;
      const recipient=(value as {recipientUserId?:unknown}).recipientUserId,guildId=(value as {guildId?:unknown}).guildId,partyId=(value as {partyId?:unknown}).partyId;
      
      return requestId(id)&&isChatChannel(ch)&&typeof body==="string"&&body.trim().length>0&&body.length<=512&&(recipient===null||typeof recipient==="string")&&(guildId===null||typeof guildId==="string")&&(partyId===null||typeof partyId==="string")?{type:"chat_send",requestId:id,channel:ch,body,recipientUserId:recipient,guildId,partyId}:null;
    }
    if(type==="chat_history"){
      const id=(value as {requestId?:unknown}).requestId,ch=(value as {channel?:unknown}).channel;
      const recipient=(value as {recipientUserId?:unknown}).recipientUserId,guildId=(value as {guildId?:unknown}).guildId,partyId=(value as {partyId?:unknown}).partyId;
      
      return requestId(id)&&isChatChannel(ch)&&(recipient===null||typeof recipient==="string")&&(guildId===null||typeof guildId==="string")&&(partyId===null||typeof partyId==="string")?{type:"chat_history",requestId:id,channel:ch,recipientUserId:recipient,guildId,partyId}:null;
    }
    if(type==="list_world_events" || type==="world_event_contribute" || type==="world_event_reward"){
    const id=(value as {requestId?:unknown}).requestId,eventId=(value as {eventId?:unknown}).eventId;
    if(typeof id!=="string") return null;
    if(type!=="list_world_events" && (typeof eventId!=="string" || eventId.length<1 || eventId.length>64)) return null;
    if(type==="list_world_events") return {type:"list_world_events",requestId:id};
    if(type==="world_event_contribute") return {type:"world_event_contribute",requestId:id,eventId:eventId as string};
    return {type:"world_event_reward",requestId:id,eventId:eventId as string};
  }
  if(type==="auction_list"){
      const id=(value as {requestId?:unknown}).requestId,item=(value as {itemId?:unknown}).itemId;
      const rarityRaw=(value as {rarity?:unknown}).rarity,categoryRaw=(value as {category?:unknown}).category,minLevelRaw=(value as {minLevel?:unknown}).minLevel,maxLevelRaw=(value as {maxLevel?:unknown}).maxLevel,min=(value as {minPrice?:unknown}).minPrice,max=(value as {maxPrice?:unknown}).maxPrice;
      const rarity=rarityRaw===undefined?null:rarityRaw,category=categoryRaw===undefined?null:categoryRaw,minLevel=minLevelRaw===undefined?null:minLevelRaw,maxLevel=maxLevelRaw===undefined?null:maxLevelRaw;
      return requestId(id)&&(item===null||typeof item==="string")&&(rarity===null||isAuctionRarity(rarity))&&(category===null||isAuctionCategory(category))&&(minLevel===null||isSafeInteger(minLevel))&&(maxLevel===null||isSafeInteger(maxLevel))&&(min===null||typeof min==="string")&&(max===null||typeof max==="string")?{type:"auction_list",requestId:id,itemId:item,rarity,category,minLevel,maxLevel,minPrice:min,maxPrice:max}:null;
    }
    if(type==="auction_create"){
      const id=(value as {requestId?:unknown}).requestId,item=(value as {itemId?:unknown}).itemId,q=(value as {quantity?:unknown}).quantity,start=(value as {startPrice?:unknown}).startPrice,buy=(value as {buyNowPrice?:unknown}).buyNowPrice,d=(value as {durationMs?:unknown}).durationMs;
      return requestId(id)&&typeof item==="string"&&item.length>0&&item.length<=128&&isSafeInteger(q)&&q>0&&q<=1_000_000&&typeof start==="string"&&start.length>0&&(buy===null||typeof buy==="string")&&isSafeInteger(d)&&d>=60000&&d<=604800000?{type:"auction_create",requestId:id,itemId:item,quantity:q,startPrice:start,buyNowPrice:buy,durationMs:d}:null;
    }
  }catch{return null;}
  return null;
}
