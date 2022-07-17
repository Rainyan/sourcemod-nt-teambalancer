/**************************************************************
--------------------------------------------------------------
 NEOTOKYO° Team Balancer

 Plugin licensed under the GPLv3

 Coded by gH0sTy - www.affenkaefig.com

 This version is modified from gHosTy's original work
 (v1.0.0 to v1.0.5), please see the changelog below.

 Credits to:
 	dubbeh for his Deathmatch Team Balancer plugin
 	BrutalGoerge for his  [TF2] gScramble + Balance plugin
--------------------------------------------------------------


Changelog

	1.0.0
		* Initial release

	1.0.1
		* Fixed an error in the team restriction function which would allow a player to switch the teams even if it would unbalance the teams
		* Added translation support

	1.0.2
		*  Admin can now switch teams or join a team even if it would result in unbalanced teams
		*  Teams will now be balanced in consideration of their XP
		*  Added scramble support
			* Admins with kick flag can schedule a team scramble for the next round (sm_ntscramble)
			* Teams can be auto scrambled (neottb_autoscramble) if the team score difference is >= neottb_minscoredif

	1.0.3
		* Fixed an auto scramble issue

	1.0.4
		* Team menu will close now for players trying to switch form one team to a full one
		* Fixed a sm_ntscramble command issue (wrong translation phrase)
		* Added votescramble support (!votescramble in chat)

	1.0.5
		* Fix for the latest Patch

	1.0.6
		* Fix for detecting invalid client indexes
		
	1.0.7
		* Fix compile warning for deprecated convar flag FCVAR_PLUGIN in the cvar "neottb_version"

**************************************************************/

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#define PLUGIN_VERSION	"1.0.7"
#define MAX_STRING_LEN 256
#define TEAM_Jin	2
#define TEAM_NSF	3

public Plugin:myinfo =
{
    name = "NEOTOKYO° Team Balancer",
    author = "gH0sTy",
    description = "Keep the teams balanced in NEOTOKYO°",
    version = PLUGIN_VERSION,
    url = "http://www.affenkaefig.com"
};

new Handle:g_cVarNeoTVersion = INVALID_HANDLE;
new Handle:g_cVarNeoTEnable = INVALID_HANDLE;
new Handle:g_cVarPlayerLimit = INVALID_HANDLE;
new Handle:g_cVarAdminsImmune = INVALID_HANDLE;
new Handle:g_cVarMapStartPlayerLimit = INVALID_HANDLE;
new Handle:g_cVarAutoScramble = INVALID_HANDLE;
new Handle:g_cVarScrambleVoteEnable = INVALID_HANDLE;
new Handle:g_cVarScrambleVoteDelay = INVALID_HANDLE;
new Handle:g_cVarMinScoreDif = INVALID_HANDLE;
new Handle:g_cVarDebugLog = INVALID_HANDLE;
new bool:g_bMapStart = false;
new bool:g_bScramble = false;
new bool:g_bVoteScramble = false;
new g_lastJinScore = 0;
new g_lastNSFScore = 0;
new g_LastScrambleVote = 0;
new String:g_LogFile[64];

public OnPluginStart ()
{
	g_cVarNeoTVersion = CreateConVar ("neottb_version", PLUGIN_VERSION, "NEOTOKYO° Team Balancer version", FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);
	g_cVarNeoTEnable = CreateConVar ("neottb_enable", "1", "Enable or disable the team balancer", 0);
	g_cVarPlayerLimit = CreateConVar ("neottb_playerlimit", "1", "How uneven the teams can get before getting balanced", 0, true, 1.0, true, 32.0);
	g_cVarMapStartPlayerLimit = CreateConVar ("neottb_mapstart_playerlimit", "4", "How uneven the teams can get on the first Map load", 0, true, 1.0, true, 32.0);
	g_cVarAdminsImmune = CreateConVar ("neottb_adminsimmune", "1", "Enable / Disable admins immunity from getting switched", 0, true, 0.0, true, 1.0);
	g_cVarAutoScramble = CreateConVar ("neottb_autoscramble", "0", "Enable / Disable the auto scramble", 0);
	g_cVarScrambleVoteEnable = CreateConVar ("neottb_scramble_vote_enable", "0", "Enable / Disable vote scramble", 0);
	g_cVarScrambleVoteDelay = CreateConVar ("neottb_scramble_vote_delay", "180.0", "Delay in seconds between scramble votes, will prevent spamming of votes", 0, true, 30.0);
	g_cVarMinScoreDif = CreateConVar("neottb_minscoredif", "3", "The min. team score difference before teams get scrambled", 0);
	g_cVarDebugLog = CreateConVar ("neottb_debug", "0", "Enable / Disable Debug Log output", 0, true, 0.0, true, 1.0);
	AutoExecConfig(true);

	// Update the Plugin Version cvar
	SetConVarString(g_cVarNeoTVersion, PLUGIN_VERSION, true, true);

	if(GetConVarBool(g_cVarNeoTEnable)){
		HookEvent("game_round_start", Event_TeamBalanceThread, EventHookMode_Post);
		RegConsoleCmd("jointeam", con_cmd_JoinTeam);
		RegAdminCmd("sm_ntscramble", CommandScramble, ADMFLAG_KICK);
		RegConsoleCmd("sm_votescramble", con_cmd_DoScrambleVote);
	}

	//Load Translations
	LoadTranslations("common.phrases");
	LoadTranslations("neottb.phrases");

}

public OnMapStart()
{
	g_bMapStart = true;
	g_bScramble = false;
	g_bVoteScramble = false;
}

public Action:CommandScramble(client, args){

  if (!IsValidClient(client)) {
    return Plugin_Continue;
  }

  if (g_bScramble || g_bVoteScramble) {
    PrintToChat(client, "[nt-TB] %T", "ScrambleAdminNo", client);
  } else {
    PrintToChat(client, "[nt-TB] %T", "ScrambleAdminYes", client);
    g_bScramble = true;
  }

  return Plugin_Handled;
}
public Action:Event_TeamBalanceThread(Handle:event,const String:name[],bool:dontBroadcast){

	if(GetConVarBool(g_cVarDebugLog)){
		BuildPath(Path_SM, g_LogFile, sizeof(g_LogFile), "logs/neottb.log");
	}

	decl String:balclient[MAX_STRING_LEN];
	new count = 0, iPlayerLimit;
	//new iMaxClients = GetMaxClients ();
	iPlayerLimit = GetConVarInt (g_cVarPlayerLimit);
	new iScores[MaxClients+1][2];

	g_bMapStart=false;

	// is there currently more Jinrais then NSFs
	// also is the player limit less than the Jinrais count minus the NSFs count
	if ((GetJinTeamSize() > GetNSFTeamSize()) && ((GetJinTeamSize() - GetNSFTeamSize()) > iPlayerLimit)){
		if(GetConVarBool(g_cVarDebugLog))
			LogToFile(g_LogFile, "[BALANCING Jin > NSF]");
		// get the scores of the clients
		for (new i = 1; i <= MaxClients; i++){
			if (IsValidClient(i) && GetClientTeam(i) == TEAM_Jin)
			{
				iScores[count][0] = i;
				iScores[count][1] = GetClientFrags(i);
				count++;
			}
		}
		// Sort the scores descending
		SortCustom2D(iScores, count, SortScoreDesc);
		// Balance the Teams by starting with the highest XP players
		for(new i = 0; i < count; i++){
			if((GetJinTeamSize() - GetNSFTeamSize()) > iPlayerLimit){
				new iClient = iScores[i][0];
				new iScore = iScores[i][1];
				new iJinXP = GetTeamXP(TEAM_Jin) - iScore;
				new iNSFXP = GetTeamXP(TEAM_NSF) + iScore;
				if (IsValidClient(iClient) && !IsProtectedAdmin(iClient) && iNSFXP <= iJinXP){
					if(GetConVarBool(g_cVarDebugLog)){
						LogToFile(g_LogFile, "NSF Score before: %i", GetTeamXP(TEAM_NSF));
						LogToFile(g_LogFile, "Jin Score before: %i", GetTeamXP(TEAM_Jin));
					}
					ChangeClientTeam (iClient, TEAM_NSF);
					GetClientName(iClient, balclient, sizeof(balclient));
					SendTranslatedMessage(1, "BalanceMessage", balclient, "NSF");
					if(GetConVarBool(g_cVarDebugLog)){
						LogToFile(g_LogFile, "NSF Score after: %i", GetTeamXP(TEAM_NSF));
						LogToFile(g_LogFile, "Jin Score after: %i", GetTeamXP(TEAM_Jin));
					}
				}
			}else{
				break;
			}
		}
		// We couldn't balance the Teams because even the player with the lowest XP would result in a higher total XP for the other team
		// so we balance the teams now by starting with the lowest XP players
		if((GetJinTeamSize() - GetNSFTeamSize()) > iPlayerLimit){
			if(GetConVarBool(g_cVarDebugLog))
				LogToFile(g_LogFile, "Balance by lowest XP");

			for(new i = count; i > 0; i--){
				if((GetJinTeamSize() - GetNSFTeamSize()) > iPlayerLimit){
					new iClient = iScores[i][0];
					//new iScore = iScores[i][1];
					if (IsValidClient(iClient) && !IsProtectedAdmin(iClient)){
						ChangeClientTeam (iClient, TEAM_NSF);
						GetClientName(iClient, balclient, sizeof(balclient));
						SendTranslatedMessage(1, "BalanceMessage", balclient, "NSF");
					}
				}else{
					break;
				}
			}
		}
	//else is there currently more NSFs then Jinrais
	//also is the player limit less than the NSFs count minus the Jinrais count
	}else if((GetNSFTeamSize() > GetJinTeamSize()) && ((GetNSFTeamSize()- GetJinTeamSize()) > iPlayerLimit)){
		if(GetConVarBool(g_cVarDebugLog))
			LogToFile(g_LogFile, "[BALANCING NSF > Jin]");
		for (new i = 1; i <= MaxClients; i++){
			if (IsValidClient(i) && GetClientTeam(i) == TEAM_NSF)
			{
				iScores[count][0] = i;
				iScores[count][1] = GetClientFrags(i);
				count++;
			}
		}
		// Sort the scores descending
		SortCustom2D(iScores, count, SortScoreDesc);
		// Balance the Teams by starting with the highest XP players
		for(new i = 0; i < count; i++){
			if((GetNSFTeamSize() - GetJinTeamSize()) > iPlayerLimit){
				new iClient = iScores[i][0];
				new iScore = iScores[i][1];
				new iJinXP = GetTeamXP(TEAM_Jin) + iScore;
				new iNSFXP = GetTeamXP(TEAM_NSF) - iScore;
				if (IsValidClient(iClient) && !IsProtectedAdmin(iClient) && iJinXP <= iNSFXP){
					if(GetConVarBool(g_cVarDebugLog)){
						LogToFile(g_LogFile, "Jin Score before: %i", GetTeamXP(TEAM_Jin));
						LogToFile(g_LogFile, "NSF Score before: %i", GetTeamXP(TEAM_NSF));
					}
					ChangeClientTeam (iClient, TEAM_Jin);
					GetClientName(iClient, balclient, sizeof(balclient));
					SendTranslatedMessage(1, "BalanceMessage", balclient, "Jinrai");
					if(GetConVarBool(g_cVarDebugLog)){
						LogToFile(g_LogFile, "Jin Score after: %i", GetTeamXP(TEAM_Jin));
						LogToFile(g_LogFile, "NSF Score after: %i", GetTeamXP(TEAM_NSF));
					}
				}
			}else{
				break;
			}
		}
		// We couldn't balance the Teams because even the player with the lowest XP would result in a higher total XP for the other team
		// so we balance the teams now by starting with the lowest XP players
		if((GetNSFTeamSize() - GetJinTeamSize()) > iPlayerLimit){
			if(GetConVarBool(g_cVarDebugLog))
				LogToFile(g_LogFile, "Balance by lowest XP");

			for(new i = count; i > 0; i--){
				if((GetNSFTeamSize() - GetJinTeamSize()) > iPlayerLimit){
					new iClient = iScores[i][0];
					//new iScore = iScores[i][1];
					if (IsValidClient(iClient) && !IsProtectedAdmin(iClient)){
						ChangeClientTeam (iClient, TEAM_Jin);
						GetClientName(iClient, balclient, sizeof(balclient));
						SendTranslatedMessage(1, "BalanceMessage", balclient, "Jinrai");
					}
				}else{
					break;
				}
			}
		}
	}

	new iJinScore = GetTeamScore(TEAM_Jin);
	new iNSFScore = GetTeamScore(TEAM_NSF);
	new minScoreDif = GetConVarInt(g_cVarMinScoreDif);

	// If an Admin or the Auto scramble wants it we scramble the teams
	if(g_bScramble || g_bVoteScramble){
		scramble();
	}else if(GetConVarBool(g_cVarAutoScramble)){
		if(iJinScore > iNSFScore){
			if((iJinScore - iNSFScore) >= minScoreDif && g_lastJinScore + g_lastNSFScore == 0){
				g_lastJinScore = iJinScore;
				g_lastNSFScore = iNSFScore;
				scramble();
			}else if((iJinScore - g_lastJinScore) >= minScoreDif && (iJinScore - iNSFScore) >= minScoreDif){
				g_lastJinScore = iJinScore;
				g_lastNSFScore = iNSFScore;
				scramble();
			}
		}else if(iNSFScore > iJinScore){
			if((iNSFScore - iJinScore) >= minScoreDif && g_lastJinScore + g_lastNSFScore == 0){
				g_lastNSFScore = iNSFScore;
				g_lastJinScore = iJinScore;
				scramble();
			}else if((iNSFScore - g_lastNSFScore) >= minScoreDif && (iNSFScore - iJinScore) >= minScoreDif){
				g_lastNSFScore = iNSFScore;
				g_lastJinScore = iJinScore;
				scramble();
			}
		}
	}
}

public GetJinTeamSize(){
	new iTeam_Jin;
	iTeam_Jin = GetTeamClientCount(TEAM_Jin);
	return iTeam_Jin;
}

public GetNSFTeamSize(){
	new iTeam_NSF;
	iTeam_NSF = GetTeamClientCount(TEAM_NSF);
	return iTeam_NSF;
}

// Get the total XP of a team
public GetTeamXP(f_Team){

	new totalScore = 0;

	for(new i=1; i<=MaxClients;i++)
	{
		if (IsValidClient(i) && GetClientTeam(i) == f_Team)
		{
			totalScore = totalScore + GetClientFrags(i);
		}
	}
	return totalScore;
}

public Action:con_cmd_DoScrambleVote(client, args){

	if(!IsValidClient(client))
		return Plugin_Continue;

	if(!GetConVarBool(g_cVarScrambleVoteEnable)){

		PrintToChat(client, "[nt-TB] %T", "VoteScrambleDisabled", client);
		return Plugin_Continue;
	}

	if(g_bVoteScramble || g_bScramble){

		PrintToChat(client, "[nt-TB] %T", "ScrambleAdminNo", client);
		return Plugin_Continue;
	}else if(g_LastScrambleVote > 0 && (GetTime() - g_LastScrambleVote) < GetConVarFloat(g_cVarScrambleVoteDelay)){

		new wait_time = g_LastScrambleVote + GetConVarInt(g_cVarScrambleVoteDelay) - GetTime();
		PrintToChat(client, "[nt-TB] %T", "Vote Delay Seconds", client, wait_time);
		return Plugin_Continue;
	}
	decl String:initiator[MAX_STRING_LEN];
	GetClientName(client, initiator, sizeof(initiator));
	SendTranslatedMessage(3, "InitScrambleVote", initiator, "");
	DoScrambleVote(client);
	return Plugin_Continue;
}

DoScrambleVote(client)
{
	if (IsVoteInProgress() && client != 0)
	{
		PrintToChat(client, "[nt-TB] %T", "Vote in Progress", client);
		return;
	}

	new Handle:g_hScrambleVoteMenu = CreateMenu(Handle_ScrambleVoteMenu, MenuAction_DisplayItem|MenuAction_Display);
	SetMenuTitle(g_hScrambleVoteMenu, "Scramble teams?");
	AddMenuItem(g_hScrambleVoteMenu, "yes", "Yes");
	AddMenuItem(g_hScrambleVoteMenu, "no", "No");
	SetMenuExitButton(g_hScrambleVoteMenu, false);
	VoteMenuToAll(g_hScrambleVoteMenu, 40);
}

public Handle_ScrambleVoteMenu(Handle:g_hScrambleVoteMenu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End)
	{
		/* This is called after VoteEnd */
		CloseHandle(g_hScrambleVoteMenu);
	} else if (action == MenuAction_VoteEnd) {
		/* 0=yes, 1=no */
		if (param1 == 0){

			SendTranslatedMessage(2, "ScrambleVoteResultYes", "", "");
			g_bVoteScramble = true;
			g_LastScrambleVote = GetTime();

		}else if (param1 == 1){

			SendTranslatedMessage(2, "ScrambleVoteResultNo", "", "");
			g_LastScrambleVote = GetTime();
		}
	} else if (action == MenuAction_DisplayItem) {
		/* Get the display string, we'll use it as a translation phrase */
		decl String:display[64];
		GetMenuItem(g_hScrambleVoteMenu, param2, "", 0, _, display, sizeof(display));

		/* Translate the string to the client's language */
		decl String:buffer[255];
		Format(buffer, sizeof(buffer), "%T", display, param1);

		/* Override the text */
		RedrawMenuItem(buffer);
	} else if (action == MenuAction_Display) {
		/* Panel Handle is the second parameter */
		new Handle:panel = Handle:param2;

		/* Translate to our phrase */
		decl String:buffer[255];
		Format(buffer, sizeof(buffer), "%T", "ScrambleTeams?", param1);

		SetPanelTitle(panel, buffer);
	}
}

scramble(){
	if(GetConVarBool(g_cVarDebugLog)){
		BuildPath(Path_SM, g_LogFile, sizeof(g_LogFile), "logs/neottb.log");
		LogToFile(g_LogFile, "[SCRAMBLING TEAMS]");
	}

	new iScores[MaxClients+1][2];
	new count = 0, team;

	team = GetRandomInt(0,1) == 1 ? TEAM_Jin : TEAM_NSF; // randomizes which team gets the first player

	if(GetConVarBool(g_cVarDebugLog)){
		LogToFile(g_LogFile, "Jin Score before: %i", GetTeamXP(TEAM_Jin));
		LogToFile(g_LogFile, "NSF Score before: %i", GetTeamXP(TEAM_NSF));
	}

	for (new i=1; i<=MaxClients;i++){
		if (IsValidClient(i) && IsValidTeam(i)){
			iScores[count][0] = i;
			iScores[count][1] = GetClientFrags(i);
			count++;
		}
	}
	SortCustom2D(iScores, count, SortScoreDesc);
	for(new i = 0; i < count; i++){
		new iClient = iScores[i][0];

		if(IsValidClient(iClient)){
			ChangeClientTeam(iClient, team);
			team = team == TEAM_Jin ? TEAM_NSF : TEAM_Jin;
		}
	}
	SendTranslatedMessage(2, "ScrambleMessage", "", "");
	g_bScramble = false;
	g_bVoteScramble = false;
	if(GetConVarBool(g_cVarDebugLog)){
		LogToFile(g_LogFile, "Jin Score after: %i", GetTeamXP(TEAM_Jin));
		LogToFile(g_LogFile, "NSF Score after: %i", GetTeamXP(TEAM_NSF));
	}
}

// This sorts everything in the info array descending
public SortScoreDesc(x[], y[], array[][], Handle:data){

    if (x[1] > y[1])
		return -1;
    else if (x[1] < y[1])
		return 1;
    return 0;
}

public Action:con_cmd_JoinTeam(client, args){
	new iPlayerLimit;

	if(g_bMapStart){
		iPlayerLimit = GetConVarInt(g_cVarMapStartPlayerLimit);
	}else{
		iPlayerLimit = GetConVarInt(g_cVarPlayerLimit);
	}


	decl String:speech[5];
	GetCmdArgString(speech,sizeof(speech));
	new cmdInt = StringToInt(speech);
	new clTeam = GetClientTeam(client);

	// Player joins spectator, pressed Auto Assign or is an Admin
	if(cmdInt == 1 || cmdInt == 0 || IsProtectedAdmin(client))
		return Plugin_Continue;

	if(cmdInt == TEAM_Jin){
		// Player wants to switch from NSF to Jinrai
		if(clTeam == TEAM_NSF && ((GetJinTeamSize()+1) - (GetNSFTeamSize()-1)) > iPlayerLimit){
			PrintToChat(client, "[nt-TB] %T", "TeamFull", client);
			//ClientCommand(client, "teammenu");
			return Plugin_Handled;
		// Player has no Team yet
		}else if((GetJinTeamSize() - GetNSFTeamSize())+1 > iPlayerLimit){
			PrintToChat(client, "[nt-TB] %T", "TeamFull", client);
			ClientCommand(client, "teammenu");
			return Plugin_Handled;
		}
	}else if(cmdInt == TEAM_NSF){
		// Player wants to switch from Jinrai to NSF
		if(clTeam == TEAM_Jin && ((GetNSFTeamSize()+1)- (GetJinTeamSize()-1)) > iPlayerLimit){
			PrintToChat(client, "[nt-TB] %T", "TeamFull", client);
			//ClientCommand(client, "teammenu");
			return Plugin_Handled;
		// Player has no Team yet
		}else if((GetNSFTeamSize() - GetJinTeamSize())+1 > iPlayerLimit){
			PrintToChat(client, "[nt-TB] %T", "TeamFull", client);
			ClientCommand(client, "teammenu");
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

stock bool:IsProtectedAdmin (client)
{
    return (GetConVarBool (g_cVarAdminsImmune) && (GetUserAdmin (client) != INVALID_ADMIN_ID));
}

public SendTranslatedMessage(mode, String:phrase[], String:name[], String:team[]){
	//new iMaxClients = GetMaxClients ();
	for(new i=1; i <= MaxClients; i++){
		if(IsValidClient(i)){
			switch (mode){
				case 1:
				{
					PrintToChat(i, "[nt-TB] %T", phrase, i, name, team);
				}
				case 2:
				{
					PrintToChat(i, "[nt-TB] %T", phrase, i);
				}
				case 3:
				{
					PrintToChat(i, "[nt-TB] %T", phrase, i, name);
				}
			}
		}
	}
}

bool:IsValidClient(client){

	if (client < 1 || client > MaxClients)
		return false;

	if (!IsClientConnected(client))
		return false;

	if (IsFakeClient(client))
		return false;

	if (!IsClientInGame(client))
		return false;

	return true;
}

bool:IsValidTeam(client){

	new team = GetClientTeam(client);
	if (team == TEAM_Jin || team == TEAM_NSF)
		return true;
	return false;
}
