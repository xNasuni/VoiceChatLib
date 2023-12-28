_G.hello = 'exploiter'

local VoiceChatModule = {}

local HttpService = game:GetService('HttpService')
local RunService = game:GetService('RunService')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local MessagingService = game:GetService('MessagingService')
local TeleportService = game:GetService('TeleportService')
local Players = game:GetService('Players')

if (RunService:IsClient()) then return error(`client require attempt blocked`) end

local Servers = {}
local ServerCount = 1
local CurrentUUID = ''

local PlayersFiltered = {}

local VoiceChatCheckEvent = script.VoiceChatCheck

local this = VoiceChatModule

VoiceChatModule.DeveloperMode = true

type PlayerType = {UserId: number}
type ServerType = {JobId: string, VCOnly: boolean, AccessKey: string, PrivateServerId: string, Players: {PlayerType}, MaxPlayers: number}
type MessageType = {Type: string, Value: ServerType, JobId: string, ResponseTo: string, Creating: boolean, Removing: boolean}
type MessageTypeList = {MessageType}
type ServerTypeList = {ServerType}

local Type = {GET = 'get', SEND = 'send', ACTIVATE = 'activate', UPDATE = 'update'}

local AccessKey = ''
local PrivateServerId = game.PrivateServerId

local ActivateQueue: MessageTypeList = {}

local function printf(...)
	if (not VoiceChatModule.DeveloperMode) then return end
	local Message = table.unpack({...})
	print(`VoiceChatModule -> {Message}`)
end

local function warnf(...)
	if (not VoiceChatModule.DeveloperMode) then return end
	local Message = table.unpack({...})
	warn(`VoiceChatModule -> {Message}`)
end

--> From https://devforum.roblox.com/t/efficiently-turn-a-table-into-a-string/1102221
local stringify
stringify = function(v, spaces, usesemicolon, depth)
	if type(v) ~= 'table' then
		return tostring(v)
	elseif not next(v) then
		return '{}'
	end

	spaces = spaces or 4
	depth = depth or 1

	local space = (" "):rep(depth * spaces)
	local sep = usesemicolon and ";" or ","
	local s = "{"

	for k, x in next, v do
		s = s..("\n%s[%s] = %s%s"):format(space,type(k)=='number'and tostring(k)or('"%s"'):format(tostring(k)), stringify(x, spaces, usesemicolon, depth+1), sep)
	end

	return ("%s\n%s}"):format(s:sub(1,-2), space:sub(1, -spaces-1))
end

local function CheckIsReserved()
	return game.PrivateServerId ~= '' and game.PrivateServerOwnerId == 0
end
script.IsVCOnlyServer.Value = CheckIsReserved()

VoiceChatCheckEvent.OnServerEvent:Connect(function(Player, HasVC)
	local TableFind = table.find(PlayersFiltered, Player)
	
	if (HasVC and TableFind == -1) then
		table.insert(PlayersFiltered, Player)
	end

	if (not HasVC and TableFind ~= -1) then
		table.remove(PlayersFiltered, TableFind)
	end
end)

MessagingService:SubscribeAsync('Servers', function(Message: SharedTable)
	script.IsVCOnlyServer.Value = CheckIsReserved()

	local Data: MessageType = HttpService:JSONDecode(Message.Data)

	if (Data.JobId == game.JobId) then return printf(`Prevented server from communicating with itself.`) end --> Prevent sending message to own server which is unlikely to happen but still.

	printf(`Raw Data: {stringify(Data)} typeof {typeof(Message)}`)

	if (Data.Type == Type.ACTIVATE and Data.ResponseTo == PrivateServerId) then
		AccessKey = Data.Value.AccessKey
		printf(`Received AccessKey \`{Data.Value.AccessKey}\` from {Data.JobId}`)
		return
	end

	if (Data.Type == Type.UPDATE) then
		if (Data.Removing) then
			local ArrayIndex = -1
			for Index, Server in pairs(Servers) do
				if (Server.JobId == Data.JobId) then
					ArrayIndex = Index
				end
			end
			if (ArrayIndex == -1) then
				return printf(`Message did not contain valid JobId \`{Data.JobId}\` and could not be removed (!)`)
			end
			ServerCount -= 1;
			return table.remove(Servers, ArrayIndex)
		end
		if (Data.Creating) then
			ServerCount += 1;

			for Index, InfoTable in pairs(ActivateQueue) do
				if (InfoTable.ResponseTo == Data.Value.PrivateServerId) then
					table.remove(ActivateQueue, Index)
					printf(`Sent AccessKey \`{InfoTable.Value.AccessKey}\` to {InfoTable.ResponseTo}`)
					MessagingService:PublishAsync('Servers', HttpService:JSONEncode(InfoTable))
				end
			end

			return table.insert(Servers, Data.Value)
		end
	end

	if (Data.Type == Type.SEND and Data.ResponseTo == CurrentUUID) then
		return table.insert(Servers, Data.Value)
	end

	if (Data.Type == Type.GET) then
		local PlayerList = {}
		for _, Player in pairs(Players:GetPlayers()) do
			table.insert(PlayerList, {UserId = Player.UserId})
		end
		local Send = {JobId = game.JobId, Type = Type.SEND, ResponseTo = Data.ResponseTo, Value = {JobId = game.JobId, VCOnly = script.IsVCOnlyServer.Value, AccessKey = AccessKey, PrivateServerId = PrivateServerId, Players = PlayerList, MaxPlayers = Players.MaxPlayers}}
		printf(`Replied to {Data.JobId} with {HttpService:JSONEncode(Send)}`)
		MessagingService:PublishAsync('Servers', HttpService:JSONEncode(Send))
		return
	end
end)

coroutine.wrap(function()
	local PlayerList = {}
	for _, Player in pairs(Players:GetPlayers()) do
		table.insert(PlayerList, {UserId = Player.UserId})
	end

	local Data = {JobId = game.JobId, Type = Type.UPDATE, Creating = true, Removing = false, Value = {JobId = game.JobId, VCOnly = script.IsVCOnlyServer.Value, AccessKey = AccessKey, PrivateServerId = PrivateServerId, Players = PlayerList, MaxPlayers = Players.MaxPlayers}}

	MessagingService:PublishAsync('Servers', HttpService:JSONEncode(Data))
	printf(`Sent {stringify(Data)}`)

	local Send = {JobId = game.JobId, Type = Type.GET, ResponseTo = CurrentUUID}

	MessagingService:PublishAsync('Servers', HttpService:JSONEncode(Send))
end)()

function VoiceChatModule:GetServers(): ServerTypeList
	Servers = {}
	printf(`Cleared Servers table`)

	CurrentUUID = HttpService:GenerateGUID(false)
	printf(`Generated UUID {CurrentUUID}`)

	local Data = {JobId = game.JobId, Type = Type.GET, ResponseTo = CurrentUUID}
	MessagingService:PublishAsync('Servers', HttpService:JSONEncode(Data))
	printf(`Published message in MessagingService: {HttpService:JSONEncode(Data)}`)

	repeat task.wait() until (#Servers + 1) >= ServerCount
	printf(`Returning Servers {stringify(Servers)}`)

	return Servers
end

function VoiceChatModule:PlayerRequestTeleport(Player: Player)
	---- This may be changed for a system of returning back to the server they were in previously, or if that server is gone then a server with their friends, or just a random server ----
	if (script.IsVCOnlyServer.Value) then return warnf(`Player requested attempted to teleport to VC Only server while being in VC Only server`) end

	VoiceChatCheckEvent:FireClient(Player)

	if (table.find(PlayersFiltered, Player) == -1) then return warnf(`Player without VC was attempted to be sent to be teleported to VC Only Server`) end

	local Servers = this:GetServers()

	local VCOnlyServers: ServerTypeList = {}
	local ServersWithFriends: ServerTypeList = {}

	for _idx, Server in pairs(Servers) do
		warnf(`Went through server @ {_idx} with {stringify(Server)} VC ONLY = {Server.VCOnly}`)
		if (Server.VCOnly) then
			table.insert(VCOnlyServers, Server)
		end
		warnf(`LIST IS #{#VCOnlyServers} (loop)`)
	end

	warnf(`LIST IS #{#VCOnlyServers}`)
	if (#VCOnlyServers <= 0) then --> Create new VC only server 
		local AccessCode, PrivateServerId = TeleportService:ReserveServer(game.PlaceId)

		printf(`Reserving a VC only server -> {AccessCode} <- -> {PrivateServerId} <- Access Code Private Server Id`)
 
		TeleportService:TeleportToPrivateServer(game.PlaceId, AccessCode, {Player})		
		
		local Send = {JobId = game.JobId, Type = Type.ACTIVATE, ResponseTo = PrivateServerId, Creating = false, Removing = false, Value = { JobId = "unknown", VCOnly = true, PrivateServerId = PrivateServerId, AccessKey = AccessCode, Players = {}, MaxPlayers = -1}}
		table.insert(ActivateQueue, Send)
		printf(`Added message to ActivateQueue: {HttpService:JSONEncode(Send)}`)

		return true
	end

	for _, VCOnlyServer in pairs(VCOnlyServers) do
		local FriendsInServer = {}
		for _, ServerPlayer in pairs(VCOnlyServer.Players) do
			if (Player:IsFriendsWith(ServerPlayer.UserId)) then
				table.insert(FriendsInServer, ServerPlayer)
			end 
		end
		if (#FriendsInServer >= 1) then
			VCOnlyServer.Friends = FriendsInServer
			table.insert(ServersWithFriends, VCOnlyServer)
		end
	end

	local TargetServer = nil
	local FriendsLength = 0

	for _, Server in ipairs(VCOnlyServers) do
		if (Server.Friends and #Server.Friends > FriendsLength) then
			if (#Server.Players >= Server.MaxPlayers) then continue end

			TargetServer = Server
			FriendsLength = #Server.Friends
		end
	end

	if (TargetServer ~= nil) then
		warnf(`Teleporting Player {Player.DisplayName} to Friend Server with {TargetServer.AccessKey}`)
		TeleportService:TeleportToPrivateServer(game.PlaceId, TargetServer.AccessKey, {Player})
	else
		local FirstVCOnlyServer = VCOnlyServers[1]
		warnf(`Teleporting Player {Player.DisplayName} to First Server found with {FirstVCOnlyServer.AccessKey}`)
		TeleportService:TeleportToPrivateServer(game.PlaceId, FirstVCOnlyServer.AccessKey, {Player})
	end

	return true
end

game:BindToClose(function()
	MessagingService:PublishAsync('Servers', HttpService:JSONEncode({JobId = game.JobId, Type = Type.UPDATE, Creating = false, Removing = true}))
end)

script.VoiceChatTeleport.OnServerEvent:Connect(function(Player)
	warnf(`Player {Player.DisplayName} requested for VC Only teleport`)
	VoiceChatModule:PlayerRequestTeleport(Player)
end)

return VoiceChatModule
