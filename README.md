# sourcemod-nt-teambalancer
Neotokyo team balance / votescramble plugin (neottb).<br />
Coded by gH0sTy. Rehosted here with GPLv3 license as the Neotokyo forums went offline.<br />
<br />
<a href="https://github.com/Rainyan/sourcemod-nt-teambalancer/archive/master.zip">Download</a> (the compiled binary is for SourceMod 1.7 or newer, however the source should compile fine for older versions).

### Cvars
```
* neottb_enable                   Enable or disable the team balancer. Default: 1
* neottb_playerlimit              How uneven the teams can get before getting balanced. Default: 1
* neottb_mapstart_playerlimit     How uneven the teams can get on the first Map load. Default: 4
* neottb_adminsimmune             Enable / Disable admins immunity from getting switched. Default: 1
* neottb_autoscramble             Enable / Disable the auto scramble. Default: 0
* neottb_scramble_vote_enable     Enable / Disable vote scramble. Default: 0
* neottb_scramble_vote_delay      Delay in seconds between scramble votes, will prevent spamming of votes. Default: 180
* neottb_minscoredif              The min. team score difference before teams get scrambled. Default: 3
* neottb_debug                    Enable / Disable Debug Log output. Default: 0
```
