#include <sourcemod>
#include <cstrike>
#include <sdkhooks>
#include <sdktools>
#include <smlib>
#include <colours>

#define CHECK_PERIOD 60
#define ITEM_PERIOD 7.5
#define MAX_DISTANCE 1000.0

public Plugin myinfo = {
	name = "Multiplay Improved",
	author = "Clarkey",
	description = "Minigame Multiplay improved in various ways.",
	version = "1.0",
	url = "http://finalrespawn.com"
};

/***************/
/** VARIABLES **/
/***************/

ArrayList g_aWeapons;

ConVar g_vAutoBhop;
ConVar g_vRealBhop;

Handle g_hCheckTeleport;
Handle g_hCheckWeapon;

bool g_bAllTeleported;
bool g_bCheckWeapon;
bool g_bWarmup;
bool g_bWeaponsCT;
bool g_bWeaponsT;

// 0 = CT, 1 = T
char g_sPrimary[2][64];
char g_sSecondary[2][64];
char g_sKnife[2][64];
char g_sGrenade[2][64];

float g_fVector[MAXPLAYERS + 1][3];
float g_fSpeed[MAXPLAYERS + 1];

int g_iCheckCount;
int g_iPlayersAlive;
int g_iRoundCounter;
int g_iTeleportedCount;

/***********/
/** START **/
/***********/

public void OnPluginStart()
{
	CreateWeaponsArray();
	
	HookEvent("item_pickup", Event_ItemPickup);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("round_start", Event_RoundStart);
}

public void OnMapStart()
{
	g_bWarmup = true;
	g_bWeaponsCT = false;
	g_bWeaponsT = false;
	
	for (int i; i < 2; i++)
	{
		g_sPrimary[i] = "";
		g_sSecondary[i] = "";
		g_sKnife[i] = "";
		g_sGrenade[i] = "";
	}
	
	g_iRoundCounter = 0;
}

public void OnConfigsExecuted()
{
	g_vAutoBhop = FindConVar("abner_autobhop");
	g_vRealBhop = FindConVar("sm_realbhop_enabled");
	
	// Take away their notify flags
	g_vAutoBhop.Flags &= ~FCVAR_NOTIFY;
	g_vRealBhop.Flags &= ~FCVAR_NOTIFY;
}

public void OnClientDisconnect_Post(int client)
{
	g_fVector[client][0] = 0.0;
}

/************/
/** EVENTS **/
/************/

public Action Event_ItemPickup(Event event, const char[] name, bool dontBroadcast)
{
	// If everyone has teleported
	if (g_bAllTeleported && g_bCheckWeapon)
	{
		if (g_vAutoBhop.IntValue == 1)
		{
			char Weapon[64];
			event.GetString("item", Weapon, sizeof(Weapon));
			
			if (g_aWeapons.FindString(Weapon) != -1)
				DisableAutoBhop();
		}
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int UserId = event.GetInt("userid");
	int Client = GetClientOfUserId(UserId);
	g_fVector[Client][0] = 0.0;
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int UserId = event.GetInt("userid");
	CreateTimer(0.1, Timer_PlayerSpawn, UserId);
}

public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	// Stop the timers are the beginning of the round
	if (g_hCheckTeleport != null)
		g_hCheckTeleport = null;
		
	if (g_hCheckWeapon != null)
		g_hCheckWeapon = null;
		
	// Reset all variables
	g_bAllTeleported = false;
	g_bCheckWeapon = false;
	g_iCheckCount = 0;
	g_iRoundCounter++;
	
	// Reset arrays
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fVector[i][0] = 0.0;
		g_fSpeed[i] = 0.0;
	}
	
	// Check to see if it's warmup
	if (g_bWarmup && g_iRoundCounter > 1)
		g_bWarmup = false;
		
	if ( !g_bWarmup)
		g_hCheckTeleport = CreateTimer(1.0, Timer_CheckTeleport, _, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
		
	if (g_vAutoBhop.IntValue == 0)
		CPrintToChatAll("{pink}[Multiplay]{default} Auto bhop has been {green}enabled.");
		
	g_vAutoBhop.IntValue = 1;
	g_vRealBhop.IntValue = 0;
}

/************/
/** TIMERS **/
/************/

public Action Timer_CheckTeleport(Handle timer)
{
	g_iCheckCount++;
	g_iPlayersAlive = 0;
	g_iTeleportedCount = 0;
	
	// Stop the timer if checked some amount of times
	if (g_iCheckCount >= CHECK_PERIOD)
		return Plugin_Stop;
		
	for (int i = 1; i <= MaxClients; i++)
	{
		if ( !IsClientInGame(i))
			continue;
			
		if ( !IsPlayerAlive(i))
			continue;
			
		g_iPlayersAlive++;
		
		float Vector[3];
		GetClientAbsOrigin(i, Vector);
		
		// Did they just spawn in?
		if (g_fVector[i][0] != 0.0)
		{
			// If they have moved a certain distance
			if (FloatAbs(Vector[0] - g_fVector[i][0]) > MAX_DISTANCE ||
				FloatAbs(Vector[1] - g_fVector[i][1]) > MAX_DISTANCE ||
				FloatAbs(Vector[2] - g_fVector[i][2]) > MAX_DISTANCE)
			{
				float Velocity[3], Speed;
				GetEntPropVector(i, Prop_Data, "m_vecVelocity", Velocity);
				Speed = SquareRoot(Pow(Velocity[0], 2.0) + Pow(Velocity[1], 2.0));
				
				if (Speed < MAX_DISTANCE && g_fSpeed[i] < MAX_DISTANCE)
					g_iTeleportedCount++;
					
				g_fSpeed[i] = Speed;
			}
		}
		
		g_fVector[i] = Vector;
	}
	
	if (g_iPlayersAlive == g_iTeleportedCount)
	{
		g_bAllTeleported = true;
		g_bCheckWeapon = true;
		g_hCheckTeleport = CreateTimer(ITEM_PERIOD, Timer_CheckWeapon, _, TIMER_FLAG_NO_MAPCHANGE);
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

public Action Timer_CheckWeapon(Handle timer)
{
	g_bCheckWeapon = false;
	return Plugin_Handled;
}

public Action Timer_GiveWeapons(Handle timer, any data)
{
	int Client = GetClientOfUserId(data);
	GiveWeapons(Client);
}

public Action Timer_PlayerSpawn(Handle timer, any data)
{
	int Client = GetClientOfUserId(data);
	int Team = GetClientTeam(Client);
	
	if (!g_bWeaponsCT && Team == CS_TEAM_CT && !g_bWarmup)
		GetClientWeapons(Client);
		
	if (!g_bWeaponsT && Team == CS_TEAM_T && !g_bWarmup)
		GetClientWeapons(Client);
		
	Client_RemoveAllWeapons(Client, "weapon_c4");
	CreateTimer(0.1, Timer_GiveWeapons, GetClientUserId(Client));
}

/************/
/** CUSTOM **/
/************/

void CreateWeaponsArray()
{
	g_aWeapons = new ArrayList(64, 0);
	
	char Weapons[][64] = { "deagle", "ak47", "m4a1", "m4a1_silencer", "galilar", "famas", "sg556", "aug", "awp" };
	
	for (int i; i < sizeof(Weapons); i++)
	{
		g_aWeapons.PushString(Weapons[i]);
	}
}

void DisableAutoBhop()
{
	g_vAutoBhop.IntValue = 0;
	g_vRealBhop.IntValue = 1;
	CPrintToChatAll("{pink}[Multiplay]{default} Auto bhop has been {darkred}disabled.");
}

void GetClientWeapons(int client)
{
	int Team = GetClientTeam(client);
	
	if (Team == CS_TEAM_CT)
	{
		Team = 0;
		g_bWeaponsCT = true;
	}
	else if (Team == CS_TEAM_T)
	{
		Team = 1;
		g_bWeaponsT = true;
	}
	
	int Primary = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	int Secondary = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	int Knife = GetPlayerWeaponSlot(client, CS_SLOT_KNIFE);
	int Grenade = GetPlayerWeaponSlot(client, CS_SLOT_GRENADE);
	
	if (Primary != -1)
		GetEntityClassname(Primary, g_sPrimary[Team], sizeof(g_sPrimary[]));
		
	if (Secondary != -1)
		GetEntityClassname(Secondary, g_sSecondary[Team], sizeof(g_sSecondary[]));
		
	if (Knife != -1)
		GetEntityClassname(Knife, g_sKnife[Team], sizeof(g_sKnife[]));
		
	if (Grenade != -1)
		GetEntityClassname(Grenade, g_sGrenade[Team], sizeof(g_sGrenade[]));
}

void GiveWeapons(int client)
{
	int Team = GetClientTeam(client);
	
	if (Team == CS_TEAM_CT)
		Team = 0;
	else if (Team == CS_TEAM_T)
		Team = 1;
		
	if ( !StrEqual("", g_sPrimary[Team]))
		GivePlayerItem(client, g_sPrimary[Team]);
		
	if ( !StrEqual("", g_sSecondary[Team]))
		GivePlayerItem(client, g_sSecondary[Team]);
		
	if ( !StrEqual("", g_sKnife[Team]))
		GivePlayerItem(client, g_sKnife[Team]);
		
	if ( !StrEqual("", g_sGrenade[Team]))
		GivePlayerItem(client, g_sGrenade[Team]);
}