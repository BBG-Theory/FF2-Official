//Freak Fortress 2 v2
//By Powerlord

//Freak Fortress 2 v1
//By Rainbolt Dash: programmer, modeller, mapper, painter.
//Author of Demoman The Pirate: http://www.randomfortress.ru/thepirate/
//And one of two creators of Floral Defence: http://www.polycount.com/forum/showthread.php?t=73688
//And author of VS Saxton Hale Mode

#include <sourcemod>
#include <sdktools>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <sdkhooks>
#include <morecolors>

#include <freak_fortress_2>
#include "freak_fortress_2/natives.inc"

#undef REQUIRE_EXTENSIONS
#tryinclude <steamtools>

#define PLUGIN_VERSION "2.0 alpha"

#pragma semicolon 1

#define SET_AND_BOSS_LENGTH 64

enum FF2Stats
{
	FF2Stat_UserId=0,
	FF2Stat_Damage,
	FF2Stat_Healing,
	FF2Stat_Lifelength,
	FF2Stat_Points,
};

// FF2 status
// ------------------------
new String:g_ConfigPath[PLATFORM_MAX_PATH];
// These will be set as maps change.  Enabled and FirstRound correspond to cvars
// Enabled is directly affected by g_bFF2Map
// Setting active while not setting enabled is a bug
new bool:g_bEnabled;
new bool:g_bFirstRound;
new bool:g_bFF2Map;
new bool:g_bActive;
// ------------------------

// Valve Cvars
// ------------------------
new Handle:g_Cvar_ArenaQueue;
new Handle:g_Cvar_UnbalanceLimit;
new Handle:g_Cvar_Autobalance;
new Handle:g_Cvar_FirstBlood;
new Handle:g_Cvar_ForceCamera;
new Handle:g_Cvar_Medieval;
// ------------------------

// Our Cvars
// ------------------------
new Handle:g_Cvar_Enabled;
new Handle:g_Cvar_FirstRound;
new Handle:g_Cvar_PointType;
new Handle:g_Cvar_PointDelay;
new Handle:g_Cvar_PointAlive;
new Handle:g_Cvar_Announce;
new Handle:g_Cvar_Crits;
new Handle:g_Cvar_ShortCircuit;
new Handle:g_Cvar_Countdown;
new Handle:g_Cvar_SpecForceBoss;
// ------------------------

// All boss sets.
// ------------------------
new Handle:g_Array_BossSets;
// ------------------------

// Current set and its bosses
// ------------------------
new String:g_CurrentBossSet[SET_AND_BOSS_LENGTH];
new Handle:g_Array_Bosses;
// ------------------------

// Available boss abilities
// ------------------------
// The array is the keys to the map
new Handle:g_Array_AbilityList;
new Handle:g_Trie_AbilityMap;
// ------------------------

// Boss Tracking Variables
// ------------------------
new g_CurrentBossCount;
// Client ID of current bosses, based on boss index
new g_CurrentBosses[MAXPLAYERS]; // Do NOT change this to MAXPLAYERS+1
// Stores handles to KeyValues for bosses currently in play, based on boss index
new Handle:g_KeyValues_CurrentBosses[MAXPLAYERS]; // Do NOT change this to MAXPLAYERS+1
// ------------------------

// Player data
// ------------------------
// Damage and healing done by non-bosses
// Note that damage done by targets being healed by medigun are
// counted as damage
new g_CurrentStats[MAXPLAYERS+1][FF2Stats];
new g_PlayersRemaining;
new TFTeam:g_BossTeam = TFTeam_Blue;
new TFTeam:g_OtherTeam = TFTeam_Red; // We're lazy
// ------------------------

// Map status
// ------------------------
new g_RoundStartTime;
new g_CurrentRound;
// ------------------------

public Plugin:myinfo = 
{
	name = "Freak Fortress 2",
	author = "Powerlord & Rainbolt Dash",
	description = "Freak Fortress 2 is an \"all versus one (or two)\" game mode for Team Fortress 2",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/forumdisplay.php?f=154"
}

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	RegPluginLibrary("freak_fortress_2");

	CreateFF2Natives();
	CreateVSHNatives();

	return APLRes_Success;
}

public OnPluginStart()
{
	new cells = ByteCountToCells(SET_AND_BOSS_LENGTH);
	g_Array_BossSets = CreateArray(cells);
	g_Array_Bosses = CreateArray(cells);
	g_Array_AbilityList = CreateArray(cells);
	g_Trie_AbilityMap = CreateTrie();
	
	
	g_Cvar_ArenaQueue = FindConVar("tf_arena_use_queue");
	g_Cvar_UnbalanceLimit = FindConVar("mp_teams_unbalance_limit");
	g_Cvar_Autobalance = FindConVar("mp_autobalance");
	g_Cvar_FirstBlood = FindConVar("tf_arena_first_blood");
	g_Cvar_ForceCamera = FindConVar("mp_forcecamera");
	g_Cvar_Medieval = FindConVar("tf_medieval");
	
	CreateConVar("ff2_version", PLUGIN_VERSION, "Freak Fortress 2 version", FCVAR_DONTRECORD | FCVAR_NOTIFY);
	g_Cvar_Enabled = CreateConVar("ff2_enabled", "1", "Enable Freak Fortress 2? If you want to control this from another plugin, comment out the ff2_enabled line in the config file", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_FirstRound = CreateConVar("ff2_first_round", "0", "Should first round be FF2? Set to 0 for normal arena", FCVAR_NONE, true, 0.0, true, 1.0);
	g_Cvar_Announce = CreateConVar("ff2_announce", "120", "How often in seconds should we advertise information about FF2? Set to 0 to hide", FCVAR_NONE, true, 0.0);
	g_Cvar_Crits = CreateConVar("ff2_crits", "0", "Can bosses get crits?", FCVAR_NONE, true, 0.0, true, 1.0);
	//g_Cvar_Countdown = CreateConVar("ff2_countdown", "", "", FCVAR_NONE, true, 60.0);
	//g_Cvar_PointAlive = CreateConVar("ff2_point_alive", "5", "", FCVAR_NONE, true, 0.0, true, 1.0);
	//g_Cvar_PointDelay = CreateConVar("ff2_point_delay", "60", "", FCVAR_NONE, true, 60.0);
	//g_Cvar_PointType = CreateConVar("ff2_point_type", "0", "", FCVAR_NONE, true, 0.0, true, 1.0);
	//g_Cvar_ShortCircuit = CreateConVar("ff2_shortcircuit_stun", "2", "", FCVAR_NONE, true, 0.0);
	//g_Cvar_SpecForceBoss = CreateConVar("ff2_spec_forceboss", "0", "", FCVAR_NONE, true, 0.0, true, 1.0);

	
	BuildPath(Path_SM, g_ConfigPath, PLATFORM_MAX_PATH, "configs/freak_fortress_2");
}

public OnMapStart()
{
	g_bFF2Map = false;
	
	decl String:mapName[64];
	GetCurrentMap(mapName, sizeof(mapName));
	
	decl String:mapConfig[PLATFORM_MAX_PATH];
	Format(mapConfig, PLATFORM_MAX_PATH, "%s/%s", g_ConfigPath, "maps.cfg");
	
	new Handle:fh = OpenFile(mapConfig, "r");
	
	// Get the map prefix
	new pos = FindCharInString(mapName, '_');
	decl String:mapPrefix[10]; // 10 is arbitrary, but it had to be longer than "deathrun"
	strcopy(mapPrefix, (pos < sizeof(mapPrefix) ? pos : sizeof(mapPrefix)), mapName);
	
	while (!IsEndOfFile(fh))
	{
		decl String:line[10];
		ReadFileLine(fh, line, sizeof(line));
		TrimString(line);
		if (StrEqual(mapPrefix, line, false))
		{
			g_bFF2Map = true;
			break;
		}
	}
	CloseHandle(fh);
}

public OnConfigsExecuted()
{
	g_CurrentRound = 0;

	// These values are read once to prevent issues mid-map
	g_bEnabled = g_bFF2Map && GetConVarBool(g_Cvar_Enabled);
	g_bActive = false;

	g_bFirstRound = GetConVarBool(g_Cvar_FirstRound);
	
	if (g_bEnabled && g_bFirstRound)
	{
		PrepareFF2();
		ChangeValveCvars();
	}
}

public Action:TF2_CalcIsAttackCritical(client, weapon, String:weaponname[], &bool:result)
{
	if (g_bActive && !GetConVarBool(g_Cvar_Crits) && IsBoss(client))
	{
		result = false;
		return Plugin_Changed;
	}
	
	return Plugin_Continue;
}

bool:IsBoss(client)
{
	if (!g_bActive)
		return false;
	
	for (new i = 0; i  < g_CurrentBossCount; i++)
	{
		if (g_CurrentBosses[i] == client)
			return true;
	}
	
	return false;
}

/**
 * Called before players can move
 * Initial boss selection here.
 */
public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled || !g_bFF2Map)
		return;

	g_CurrentRound++;
	
	if (g_CurrentRound == 1 && !g_bFirstRound)
		return;

	for (new i = 1; i <= MaxClients; i++)
	{
		for (new j = 0; j < _:FF2Stats; j++)
		{
			g_CurrentStats[i][j] = 0;
		}
	}

}

/**
 * Called when players unfreeze and can move around.  This is when the arena clock would start.
 * Force the boss back to the boss class and loadout here
 */
public Event_ArenaRoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_bEnabled || !g_bFF2Map)
		return;

	g_PlayersRemaining = GetTeamClientCount(_:g_OtherTeam);
	
	g_RoundStartTime = GetTime();
	// TODO fix boss here
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && TFTeam:GetClientTeam(i) == g_OtherTeam)
		{
			new userId = GetClientUserId(i);
			g_CurrentStats[i][FF2Stat_UserId] = userId;
		}
	}
}

public Event_RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (g_bEnabled && g_CurrentRound == 1 && !g_bFirstRound)
	{
		ChangeValveCvars();
	}
	
}

public Action:Event_ArenaWinPanel(Handle:event, const String:name[], bool:dontBroadcast)
{
	new Handle:top = CreateArray();
	//new top[3];
	
	for (new i = 1; i < MaxClients; i++)
	{
		if (!IsBoss(i))
		{
			new damage = g_CurrentStats[i][FF2Stat_Damage];
			if (damage == 0)
			{
				continue;
			}
			
			new size = GetArraySize(top);

			new insertPoint = -1;

			for (new j = 0; j < 3; j++)
			{
				if (size == j)
				{
					insertPoint = j;
					break;
				}
				
				if (damage > GetArrayCell(top, j))
				{
					insertPoint = j;
					break;
				}
				
			}
			if (insertPoint > -1)
			{
				ShiftArrayUp(top, insertPoint);
				SetArrayCell(top, insertPoint, i);
			}
		}
	}
	
	ResizeArray(top, 3);
	
	new TFTeam:winner = TFTeam:GetEventInt(event, "winning_team");
	
	new currentPlayer;
	if (winner == g_BossTeam)
	{
		currentPlayer = 4;
	}
	else
	{
		currentPlayer = 1;
	}

	for (new i = 0; i < 3; i++)
	{
		decl String:player[9]; // in format "player_1"
		decl String:player_damage[16]; // in format "player_1_damage"
		decl String:player_healing[17]; // in format "player_1_healing"
		decl String:player_lifetime[17]; // in format "player_1_lifetime"
		decl String:player_kills[14]; // in format "player_1_kills"
		
		Format(player, sizeof(player), "%s%d", "player_", currentPlayer);
		
		Format(player_damage, sizeof(player_damage), "%s%s", player, "_damage");
		Format(player_healing, sizeof(player_healing), "%s%s", player, "_healing");
		Format(player_lifetime, sizeof(player_lifetime), "%s%s", player, "_lifetime");
		Format(player_kills, sizeof(player_kills), "%s%s", player, "_kills");
		
		new client = GetArrayCell(top, i);
		
		// TODO Fix these values
		SetEventInt(event, player, g_CurrentStats[client][FF2Stat_UserId]);
		SetEventInt(event, player_damage, g_CurrentStats[client][FF2Stat_Damage]);
		SetEventInt(event, player_healing, g_CurrentStats[client][FF2Stat_Healing]);
		SetEventInt(event, player_lifetime, g_CurrentStats[client][FF2Stat_Lifelength]);
		SetEventInt(event, player_kills, g_CurrentStats[client][FF2Stat_Points]);
		
		currentPlayer++;
	}
	
	return Plugin_Changed;
}

public Event_Player_Healed(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "healer"));
	new amount = GetEventInt(event, "amount");
	
	g_CurrentStats[client][FF2Stat_Healing] += amount;
}

/**
 * Prepare the next round for FF2
 */
PrepareFF2()
{
	g_bActive = true;
	ChangeValveCvars();
}

ChangeValveCvars()
{
	SetConVarBool(g_Cvar_ArenaQueue, false);
	SetConVarBool(g_Cvar_Autobalance, false);
	SetConVarInt(g_Cvar_UnbalanceLimit, 0);
	SetConVarBool(g_Cvar_FirstBlood, false);
	SetConVarInt(g_Cvar_ForceCamera, 0);
}

public ResetData()
{
	for (new i = 1; i <= MaxClients; i++)
	{
		for (new j = 0; j < _:FF2Stats; j++)
		{
			g_CurrentStats[i][j] = 0;
		}
	}
}

public GetCharacterSets()
{
	ClearArray(g_Array_BossSets);
	new Handle:characterKv = OpenCharacterKv();
	
	do
	{
		decl String:charSet[SET_AND_BOSS_LENGTH];
		KvGetString(characterKv, NULL_STRING, charSet, sizeof(charSet));
		if (!StrEqual(charSet, ""))
		{
			PushArrayString(g_Array_BossSets, charSet);
		}
	} while (KvGotoNextKey(characterKv);

	CloseHandle(characterKv);
}

public bool:DownloadBossSet(String:setName[])
{
	new Handle:characterKv = OpenCharacterKv();
	
	if (!KvJumpToKey(characterKv, setName) || !KvGotoFirstSubKey(characterKv, false))
	{
		return false;
	}
	
	do
	{
		decl String:bossName[SET_AND_BOSS_LENGTH];
		KvGetString(characterKv, NULL_STRING, bossName, SET_AND_BOSS_LENGTH);
		if (!StrEqual(bossName, ""))
		{
			decl String:bossFile[PLATFORM_MAX_PATH];
			Format(bossFile, PLATFORM_MAX_PATH, "%s/%s.%s", g_ConfigPath, bossName, ".cfg");
			// We have the boss name
			new Handle:bossKv = CreateKeyValues("Character");
			if (!FileToKeyValues(bossKv, bossFile))
			{
				CloseHandle(bossKv);
				continue;
			}
			
			// TODO Load the various sections
		}
	} while (KvGotoNextKey(characterKv, false));
	
	CloseHandle(characterKv);
}

public Handle:OpenCharacterKv()
{
	decl String:characterFile[PLATFORM_MAX_PATH];
	Format(characterFile, PLATFORM_MAX_PATH, "%s/%s", g_ConfigPath, "characters.cfg");
	
	new Handle:characterKv = CreateKeyValues("Boss Sets");
	if (!FileToKeyValues(characterKv, characterFile))
	{
		CloseHandle(characterKv);
		SetFailState("Could not locate boss character set file: %s", characterFile);
	}

	return characterKv;
}

public Handle:LoadBoss(client, String:bossName[])
{
	//TODO
	
}
